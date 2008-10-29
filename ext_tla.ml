(*  Copyright 2008 INRIA  *)
Version.add "$Id: ext_tla.ml,v 1.14 2008-10-29 10:37:58 doligez Exp $";;

(* Extension for TLA+ : set theory. *)
(* Symbols: TLA.in *)

open Printf;;

open Expr;;
open Misc;;
open Mlproof;;
open Node;;
open Phrase;;

let add_formula e = ();;
let remove_formula e = ();;

let tla_set_constructors = [
  "TLA.emptyset";
  "TLA.upair";
  "TLA.add";
  "TLA.infinity";
  "TLA.SUBSET";
  "TLA.UNION";
  "TLA.INTER";
  "TLA.cup";
  "TLA.cap";
  "TLA.setminus";
  "TLA.subsetOf";
  "TLA.setOfAll";
  "TLA.FuncSet";
];;

let is_set_expr e =
  match e with
  | Evar (v, _) -> List.mem v tla_set_constructors
  | Eapp (f, _, _) -> List.mem f tla_set_constructors
  | _ -> false
;;

let tla_fcn_constructors = [
  "TLA.Fcn";
  "TLA.except";
  "TLA.oneArg";
  "TLA.extend";
];;

let is_fcn_expr e =
  match e with
  | Evar (v, _) -> List.mem v tla_fcn_constructors
  | Eapp (f, _, _) -> List.mem f tla_fcn_constructors
  | _ -> false
;;

let newnodes_prop e g =
  let mknode name args branches =
    [ Node {
      nconc = [e];
      nrule = Ext ("tla", name, args);
      nprio = Arity;
      ngoal = g;
      nbranches = branches;
    } ]
  in
  match e with
  | Eapp ("=", [e1; Etrue], _) ->
     mknode "eq_x_true" [e; e1; e1] [| [e1] |]

  | Eapp ("=", [Etrue; e1], _) ->
     mknode "eq_true_x" [e; e1; e1] [| [e1] |]

  | Eapp ("=", [e1; Efalse], _) ->
     let h = enot (e1) in
     mknode "eq_x_false" [e; h; e1] [| [h] |]

  | Eapp ("=", [Efalse; e1], _) ->
     let h = enot (e1) in
     mknode "eq_false_x" [e; h; e1] [| [h] |]

  | Eapp ("TLA.in", [e1; Evar ("TLA.emptyset", _)], _) ->
    mknode "in_emptyset" [e; e1] [| |]

  | Eapp ("TLA.in", [e1; Eapp ("TLA.upair", [e2; e3], _)], _) ->
    let h1 = eapp ("=", [e1; e2]) in
    let h2 = eapp ("=", [e1; e3]) in
    mknode "in_upair" [e; h1; h2; e1; e2; e3] [| [h1]; [h2] |]
  | Enot (Eapp ("TLA.in", [e1; Eapp ("TLA.upair", [e2; e3], _)], _), _) ->
    let h1 = enot (eapp ("=", [e1; e2])) in
    let h2 = enot (eapp ("=", [e1; e3])) in
    mknode "notin_upair" [e; h1; h2; e1; e2; e3] [| [h1; h2] |]

  | Eapp ("TLA.in", [e1; Eapp ("TLA.add", [e2; e3], _)], _) ->
     let h1 = eapp ("=", [e1; e2]) in
     let h2 = eapp ("TLA.in", [e1; e3]) in
     mknode "in_add" [e; h1; h2; e1; e2; e3] [| [h1]; [h2] |]
  | Enot (Eapp ("TLA.in", [e1; Eapp ("TLA.add", [e2; e3], _)], _), _) ->
     let h1 = enot (eapp ("=", [e1; e2])) in
     let h2 = enot (eapp ("TLA.in", [e1; e3])) in
     mknode "notin_add" [e; h1; h2; e1; e2; e3] [| [h1; h2] |]

  (* infinity -- needed ? *)

  | Eapp ("TLA.in", [e1; Eapp ("TLA.SUBSET", [s], _)], _) ->
     let h1 = eapp ("TLA.subseteq", [e1; s]) in
     mknode "in_SUBSET" [e; h1; e1; s] [| [h1] |]
  | Enot (Eapp ("TLA.in", [e1; Eapp ("TLA.SUBSET", [s], _)], _), _) ->
     let h1 = enot (eapp ("TLA.subseteq", [e1; s])) in
     mknode "notin_SUBSET" [e; h1; e1; s] [| [h1] |]

  | Eapp ("TLA.in", [e1; Eapp ("TLA.UNION", [s], _)], _) ->
     let b = Expr.newvar () in
     let h1 = eex (b, "", eand (eapp ("TLA.in", [b; s]),
                                eapp ("TLA.in", [e1; b]))) in
     mknode "in_UNION" [e; h1; e1; s] [| [h1] |]
  | Enot (Eapp ("TLA.in", [e1; Eapp ("TLA.UNION", [s], _)], _), _) ->
     let b = Expr.newvar () in
     let h1 = enot (eex (b, "", eand (eapp ("TLA.in", [b; s]),
                                      eapp ("TLA.in", [e1; b])))) in
     mknode "notin_UNION" [e; h1; e1; s] [| [h1] |]

  (* INTER -- needed ? *)

  | Eapp ("TLA.in", [e1; Eapp ("TLA.cup", [e2; e3], _)], _) ->
     let h1 = eapp ("TLA.in", [e1; e2]) in
     let h2 = eapp ("TLA.in", [e1; e3]) in
     mknode "in_cup" [e; h1; h2; e1; e2; e3] [| [h1]; [h2] |]
  | Enot (Eapp ("TLA.in", [e1; Eapp ("TLA.cup", [e2; e3], _)], _), _) ->
     let h1 = enot (eapp ("TLA.in", [e1; e2])) in
     let h2 = enot (eapp ("TLA.in", [e1; e3])) in
     mknode "notin_cup" [e; h1; h2; e1; e2; e3] [| [h1; h2] |]

  | Eapp ("TLA.in", [e1; Eapp ("TLA.cap", [e2; e3], _)], _) ->
     let h1 = eapp ("TLA.in", [e1; e2]) in
     let h2 = eapp ("TLA.in", [e1; e3]) in
     mknode "in_cap" [e; h1; h2; e1; e2; e3] [| [h1; h2] |]
  | Enot (Eapp ("TLA.in", [e1; Eapp ("TLA.cap", [e2; e3], _)], _), _) ->
     let h1 = enot (eapp ("TLA.in", [e1; e2])) in
     let h2 = enot (eapp ("TLA.in", [e1; e3])) in
     mknode "notin_cap" [e; h1; h2; e1; e2; e3] [| [h1]; [h2] |]

  | Eapp ("TLA.in", [e1; Eapp ("TLA.setminus", [e2; e3], _)], _) ->
     let h1 = eapp ("TLA.in", [e1; e2]) in
     let h2 = enot (eapp ("TLA.in", [e1; e3])) in
     mknode "in_setminus" [e; h1; h2; e1; e2; e3] [| [h1; h2] |]
  | Enot (Eapp ("TLA.in", [e1; Eapp ("TLA.setminus", [e2; e3], _)], _), _) ->
     let h1 = enot (eapp ("TLA.in", [e1; e2])) in
     let h2 = eapp ("TLA.in", [e1; e3]) in
     mknode "notin_setminus" [e; h1; h2; e1; e2; e3] [| [h1]; [h2] |]

  | Eapp ("TLA.in",
          [e1; Eapp ("TLA.subsetOf", [s; Elam (v, _, p, _) as pred], _)],
          _) ->
     let h1 = eapp ("TLA.in", [e1; s]) in
     let h2 = substitute [(v, e1)] p in
     mknode "in_subsetof" [e; h1; h2; e1; s; pred] [| [h1; h2] |]
  | Enot (Eapp ("TLA.in",
                [e1; Eapp ("TLA.subsetOf", [s; Elam (v, _, p, _) as pred], _)],
                _), _) ->
     let h1 = enot (eapp ("TLA.in", [e1; s])) in
     let h2 = enot (substitute [(v, e1)] p) in
     mknode "notin_subsetof" [e; h1; h2; e1; s; pred] [| [h1]; [h2] |]

  | Eapp ("TLA.in",
          [e1; Eapp ("TLA.setOfAll", [s; Elam (v, _, p, _) as pred], _)],
          _) ->
     let x = Expr.newvar () in
     let h1 = eex (x, "", eand (eapp ("TLA.in", [x; s]),
                                eapp ("=", [e1; substitute [(v, x)] p])))
     in
     mknode "in_setofall" [e; h1; e1; s; pred] [| [h1] |]
  | Enot (Eapp ("TLA.in",
                [e1; Eapp ("TLA.setOfAll", [s; Elam (v, _, p, _) as pred], _)],
                _), _) ->
     let x = Expr.newvar () in
     let h1 = enot (eex (x, "", eand (eapp ("TLA.in", [x; s]),
                                      eapp ("=", [e1; substitute [(v, x)] p]))))
     in
     mknode "notin_setofall" [e; h1; e1; s; pred] [| [h1] |]

  | Eapp ("TLA.in", [f; Eapp ("TLA.FuncSet", [a; b], _)], _) ->
     let h1 = eapp ("TLA.isAFcn", [f]) in
     let h2 = eapp ("=", [eapp ("TLA.DOMAIN", [f]); a]) in
     let x = Expr.newvar () in
     let h3 = eall (x, "",
                eimply (eapp ("TLA.in", [x; a]),
                        eapp ("TLA.in", [eapp ("TLA.fapply", [f; x]); b])))
     in
     mknode "in_funcset" [e; h1; h2; h3; f; a; b] [| [h1; h2; h3] |]
  | Enot (Eapp ("TLA.in", [f; Eapp ("TLA.FuncSet", [a; b], _)], _), _) ->
     let h1 = enot (eapp ("TLA.isAFcn", [f])) in
     let h2 = enot (eapp ("=", [eapp ("TLA.DOMAIN", [f]); a]))
     in
     let x = Expr.newvar () in
     let h3 = enot (
               eall (x, "",
                     eimply (eapp ("TLA.in", [x; a]),
                             eapp ("TLA.in", [eapp ("TLA.fapply", [f; x]); b]))))
     in
     mknode "notin_funcset" [e; h1; h2; h3; f; a; b] [| [h1; h2; h3] |]

  | Eapp ("=", [e1; e2], _) when is_set_expr e1 || is_set_expr e2 ->
     let x = Expr.newvar () in
     let h = eall (x, "", eequiv (eapp ("TLA.in", [x; e1]),
                                  eapp ("TLA.in", [x; e2])))
     in
     mknode "setequal" [e; h; e1; e2] [| [h] |]
  | Enot (Eapp ("=", [e1; e2], _), _) when is_set_expr e1 || is_set_expr e2 ->
     let x = Expr.newvar () in
     let h = enot (eall (x, "", eequiv (eapp ("TLA.in", [x; e1]),
                                        eapp ("TLA.in", [x; e2]))))
     in
     mknode "notsetequal" [e; h; e1; e2] [| [h] |]

  | Eapp ("=", [e1; e2], _) when is_fcn_expr e1 || is_fcn_expr e2 ->
     let x = Expr.newvar () in
     let h1 = eequiv (eapp ("TLA.isAFcn", [e1]), eapp ("TLA.isAFcn", [e2])) in
     let h2 = eapp ("=", [eapp ("TLA.DOMAIN", [e1]); eapp ("TLA.DOMAIN", [e2])])
     in
     let h3 = eall (x, "", eapp ("=", [eapp ("TLA.fapply", [e1; x]);
                                       eapp ("TLA.fapply", [e2; x])]))
     in
     let h = eand (eand (h1, h2), h3) in
     mknode "funequal" [e; h; e1; e2] [| [h] |]
  | Enot (Eapp ("=", [e1; e2], _), _) when is_fcn_expr e1 || is_fcn_expr e2 ->
     let x = Expr.newvar () in
     let h0 = eapp ("TLA.isAFcn", [e1]) in
     let h1 = eapp ("TLA.isAFcn", [e2]) in
     let h2 = eapp ("=", [eapp ("TLA.DOMAIN", [e1]); eapp ("TLA.DOMAIN", [e2])])
     in
     let h3 = eall (x, "", eimply (eapp ("TLA.in", [x; eapp("TLA.DOMAIN",[e2])]),
                                   eapp ("=", [eapp ("TLA.fapply", [e1; x]);
                                               eapp ("TLA.fapply", [e2; x])])))
     in
     let h = enot (eand (eand (eand (h0, h1), h2), h3)) in
     mknode "notfunequal" [e; h; e1; e2] [| [h] |]
  | _ -> []
;;

let apply f e =
  match f with
  | Elam (v, _, b, _) -> Expr.substitute [(v, e)] b
  | _ -> assert false
;;

let rewrites ctx e mknode =
  match e with
  | Eapp ("TLA.fapply", [Eapp ("TLA.Fcn", [s; Elam (v, _, b, _) as l], _); a], _)
  -> let x = Expr.newvar () in
     let lamctx = elam (x, "", ctx x) in
     let h1 = enot (eapp ("TLA.in", [a; s])) in
     let h2 = ctx (Expr.substitute [(v, a)] b) in
     mknode "fapplyfcn" [ctx e; h1; h2; lamctx; s; l; a] [| [h1]; [h2] |]
  | Eapp ("TLA.fapply", [Eapp ("TLA.except", [f; v; e1], _); w], _)
  -> let x = Expr.newvar () in
     let lamctx = elam (x, "", ctx x) in
     let indom = eapp ("TLA.in", [w; eapp ("TLA.DOMAIN", [f])]) in
     let h1a = indom in
     let h1b = eapp ("=", [v; w]) in
     let h1c = ctx e1 in
     let h2a = indom in
     let h2b = enot (eapp ("=", [v; w])) in
     let h2c = ctx (eapp ("TLA.fapply", [f; w])) in
     let h3 = enot indom in
     mknode "fapplyexcept" [ctx e; h1a; h1b; h1c; h2a; h2b; h2c; h3;
                            lamctx; f; v; e1; w]
            [| [h1a; h1b; h1c]; [h2a; h2b; h2c]; [h3] |]
  | _ -> []
;;

let rec find_rewrites ctx e mknode =
  let local = rewrites ctx e mknode in
  match e with
  | _ when local <> [] -> local
  | Eapp (p, args, _) ->
     let rec loop leftarg rightarg =
       match rightarg with
       | [] -> []
       | h::t ->
          let newctx x = ctx (eapp (p, List.rev_append leftarg (x :: t)))
          in
          begin match find_rewrites newctx h mknode with
          | [] -> loop (h::leftarg) t
          | l -> l
          end
     in
     loop [] args
  | Enot (e1, _) -> find_rewrites (fun x -> (ctx (enot x))) e1 mknode
  | _ -> []
;;

let newnodes_rewrites e g =
  let mknode name args branches =
    [ Node {
      nconc = [e];
      nrule = Ext ("tla", name, args);
      nprio = Arity;
      ngoal = g;
      nbranches = branches;
    }]
  in
  find_rewrites (fun x -> x) e mknode
;;

let newnodes e g =
  newnodes_prop e g @ newnodes_rewrites e g
;;

let to_llargs r =
  let alpha r =
    match r with
    | Ext (_, name, c :: h1 :: h2 :: args) ->
       ("zenon_" ^ name, args, [c], [ [h1; h2] ])
    | _ -> assert false
  in
  let beta r =
    match r with
    | Ext (_, name, c :: h1 :: h2 :: args) ->
       ("zenon_" ^ name, args, [c], [ [h1]; [h2] ])
    | _ -> assert false
  in
  let single r =
    match r with
    | Ext (_, name, c :: h :: args) ->
       ("zenon_" ^ name, args, [c], [ [h] ])
    | _ -> assert false
  in
  match r with
  | Ext (_, "in_emptyset", [c; e1]) -> ("zenon_in_emptyset", [e1], [c], [])
  | Ext (_, "in_upair", _) -> beta r
  | Ext (_, "notin_upair", _) -> alpha r
  | Ext (_, "in_add", _) -> beta r
  | Ext (_, "notin_add", _) -> alpha r
  | Ext (_, "in_cup", _) -> beta r
  | Ext (_, "notin_cup", _) -> alpha r
  | Ext (_, "in_cap", _) -> alpha r
  | Ext (_, "notin_cap", _) -> beta r
  | Ext (_, "in_setminus", _) -> alpha r
  | Ext (_, "notin_setminus", _) -> beta r
  | Ext (_, "in_subsetof", _) -> alpha r
  | Ext (_, "notin_subsetof", _) -> beta r
  | Ext (_, "in_funcset", [c; h1; h2; h3; f; a; b]) ->
     ("zenon_in_funcset", [f; a; b], [c], [ [h1; h2; h3] ])
  | Ext (_, "notin_funcset", [c; h1; h2; h3; f; a; b]) ->
     ("zenon_notin_funcset", [f; a; b], [c], [ [h1]; [h2]; [h3] ])
  | Ext (_, "fapplyfcn", _) -> beta r
  | Ext (_, "fapplyexcept", [c; h1a; h1b; h1c; h2a; h2b; h2c; h3; ctx; f; v; e1; w])
  -> ("zenon_fapplyexcept", [ctx; f; v; e1; w], [c],
      [ [h1a; h1b; h1c]; [h2a; h2b; h2c]; [h3] ])
  | Ext (_, name, _) -> single r
  | _ -> assert false
;;

let to_llproof tr_expr mlp args =
  let (name, meta, con, hyps) = to_llargs mlp.mlrule in
  let tmeta = List.map tr_expr meta in
  let tcon = List.map tr_expr con in
  let thyps = List.map (List.map tr_expr) hyps in
  let (subs, exts) = List.split (Array.to_list args) in
  let ext = List.fold_left Expr.union [] exts in
  let extras = Expr.diff ext mlp.mlconc in
  let nn = {
      Llproof.conc = List.map tr_expr (extras @@ mlp.mlconc);
      Llproof.rule = Llproof.Rextension (name, tmeta, tcon, thyps);
      Llproof.hyps = subs;
    }
  in (nn, extras)
;;

let preprocess l = l;;

let postprocess p = p;;

let declare_context_coq oc = [];;

Extension.register {
  Extension.name = "tla";
  Extension.newnodes = newnodes;
  Extension.add_formula = add_formula;
  Extension.remove_formula = remove_formula;
  Extension.preprocess = preprocess;
  Extension.postprocess = postprocess;
  Extension.to_llproof = to_llproof;
  Extension.declare_context_coq = declare_context_coq;
};;
