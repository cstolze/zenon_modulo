(*  Copyright 2004 INRIA  *)
Version.add "$Id$";;

open Printf;;

open Expr;;
open Phrase;;
open Namespace;;

let report_error lexbuf msg =
  Error.errpos (Lexing.lexeme_start_p lexbuf) msg;
  exit 2;
;;

(* Mapping from TPTP identifiers to coq expressions. *)
let trans_table = Hashtbl.create 35;;

(* Names of formula that have to be treated as (real) definitions. *)
let eq_defs = ref [];;

(* Theorem name according to annotations. *)
let annot_thm_name = ref "";;

(* Theorem name according to TPTP syntax. *)
let tptp_thm_name = ref "";;

(* Names of formulas that should be omitted. *)
let to_ignore = ref [];;

let add_ignore_directive ext fname =
  if ext = "core" || Extension.is_active ext
  then to_ignore := fname :: !to_ignore;
;;

let keep form =
  match form with
  | Rew (name, _, _)
  | Hyp (name, _, _) -> not (List.mem name !to_ignore)
  | Def _
  | Sig _
  | Inductive _
    -> assert false
;;

let add_annotation s =
  try
    let annot_key = String.sub s 0 (String.index s ' ') in
    match annot_key with
      | "coq_binding" ->
          Scanf.sscanf s "coq_binding %s is %s" (Hashtbl.add trans_table)
      | "eq_def" ->
          Scanf.sscanf s "eq_def %s" (fun x -> eq_defs := x :: !eq_defs)
      | "thm_name" ->
          Scanf.sscanf s "thm_name %s" (fun x -> annot_thm_name := x)
      | "zenon_ignore" ->
          Scanf.sscanf s "zenon_ignore %s %s" add_ignore_directive
      | _ -> ()
  with
    | Scanf.Scan_failure _ -> ()
    | End_of_file -> ()
    | Not_found -> ()
;;

let tptp_to_coq s = try Hashtbl.find trans_table s with Not_found -> s;;

let rec make_annot_expr e =
  match e with
  | Evar _ -> e
  | Emeta _  -> e
  | e when (List.exists (Expr.equal e)
                        [type_type; type_prop; type_iota; type_none]) -> e
  | Eapp (Evar("#", _), _, _) -> e
  | Eapp (Evar(s,_) as v, l, _) ->
     let s = tptp_to_coq s in
     let l = List.map make_annot_expr l in
     eapp (tvar s (get_type v), l)
  | Eapp(_) -> assert false
  | Earrow _ -> e
  | Enot (e,_) -> enot (make_annot_expr e)
  | Eand (e1,e2,_) -> eand (make_annot_expr e1, make_annot_expr e2)
  | Eor (e1,e2,_) -> eor (make_annot_expr e1, make_annot_expr e2)
  | Eimply (e1,e2,_) -> eimply (make_annot_expr e1, make_annot_expr e2)
  | Eequiv (e1,e2,_) -> eequiv (make_annot_expr e1, make_annot_expr e2)
  | Etrue | Efalse -> e
  | Eall (x,e,_) -> eall (x, make_annot_expr e)
  | Eex (x,e,_) -> eex (x, make_annot_expr e)
  | Etau (x,e,_) -> etau (x, make_annot_expr e)
  | Elam (x,e,_) -> elam (x, make_annot_expr e)
;;

let make_definition name form body p =
  try Def (Phrase.change_to_def (Extension.predef ()) body)
  with Invalid_argument _ ->
    let msg = sprintf "annotated formula %s is not a definition" name in
    Error.warn msg;
    form
;;

let process_annotations forms =
  let process_one form =
    match form with
    (*    | Hyp (name, _, _) when name = "bool"
			    || name = "uninterpreted_type"
			    || name = "enum_POSITION" -> form
     *)
    | Hyp (name, body, kind) ->
       Log.debug 15 "Process Annotation '%a'" Print.pp_expr body;
       if List.mem name !eq_defs then
         make_definition name form (make_annot_expr body) kind
       else
         Hyp (tptp_to_coq name, make_annot_expr body, kind)
    | Rew (name, body, kind) ->
       Log.debug 15 "Process Annotation '%a'" Print.pp_expr body;
       if List.mem name !eq_defs then
         make_definition name form (make_annot_expr body) kind
       else
         Rew (tptp_to_coq name, make_annot_expr body, kind)
    | Def _
    | Sig _
    | Inductive _
      -> assert false
  in
  List.rev (List.rev_map process_one (List.filter keep forms))
;;

let rec translate_one dirs accu p =
  match p with
  | Include (f, None) -> try_incl dirs f accu
  | Include (f, Some _) ->
      (* FIXME change try_incl and incl to implement selective include *)
      (* for the moment, we just ignore the include *)
      accu
  | Annotation s -> add_annotation s; accu
  | Formula (name, ("axiom" | "definition"), body, None) ->
      Hyp (name, body, 2) :: accu
  | Formula (name, "hypothesis", body, None) ->
      Hyp (name, body, 1) :: accu
  | Formula (name, ("lemma"|"theorem"), body, None) ->
      Hyp (name, body, 1) :: accu
  | Formula (name, "conjecture", body, None) ->
      tptp_thm_name := name;
      Hyp (goal_name, enot (body), 0) :: accu
  | Formula (name, "negated_conjecture", body, None) ->
      tptp_thm_name := "negation_of_" ^ name;
      Hyp (name, body, 0) :: accu
  (* TFF formulas *)
  | Formula (name, "tff_type", body, None) ->
      Hyp (name, body, 13) :: accu
  | Formula (name, ("tff_axiom" | "tff_definition"), body, None) ->
      Hyp (name, body, 12) :: accu
  | Formula (name, "tff_hypothesis", body, None) ->
      Hyp (name, body, 11) :: accu
  | Formula (name, ("tff_axiom" | "tff_definition"), body, Some "rewrite") ->
     if !Globals.modulo then Rew (name, body, 12) :: accu
     else Hyp (name, body, 12) :: accu
  | Formula (name, "tff_hypothesis", body, Some "rewrite") ->
     if !Globals.modulo then Rew (name, body, 11) :: accu
     else Hyp (name, body, 11) :: accu
  | Formula (name, ("tff_lemma"|"tff_theorem"), body, None) ->
      Hyp (name, body, 11) :: accu
  | Formula (name, "tff_conjecture", body, None) ->
      tptp_thm_name := name;
      Hyp (goal_name, enot (body), 10) :: accu
  | Formula (name, "tff_negated_conjecture", body, None) ->
      Hyp (name, body, 10) :: accu
  (* Fallback *)
  | Formula (name, k, body, _) ->
      Error.warn ("unknown formula kind: " ^ k);
      Hyp (name, body, 1) :: accu

and xtranslate dirs ps accu =
  List.fold_left (translate_one dirs) accu ps

and try_incl dirs f accu =
  let rec loop = function
    | [] ->
        let msg = sprintf "file %s not found in include path" f in
        Error.err msg;
        raise Error.Abort;
    | h::t -> begin
        try incl dirs (Filename.concat h f) accu
        with Sys_error _ -> loop t
      end
  in
  loop dirs

and incl dir name accu =
  let chan = open_in name in
  let lexbuf = Lexing.from_channel chan in
  lexbuf.Lexing.lex_curr_p <- {
    Lexing.pos_fname = name;
    Lexing.pos_lnum = 1;
    Lexing.pos_bol = 0;
    Lexing.pos_cnum = 0;
  };
  try
    let tpphrases = Parsetptp.file Lextptp.token lexbuf in
    close_in chan;
    xtranslate dir tpphrases accu;
  with
  | Parsing.Parse_error -> report_error lexbuf "syntax error."
  | Error.Lex_error msg -> report_error lexbuf msg
;;

let translate dirs ps =
  let raw = List.rev (xtranslate dirs ps []) in
  let cooked = process_annotations raw in
  let name = if !annot_thm_name <> "" then !annot_thm_name
             else if !tptp_thm_name <> "" then !tptp_thm_name
             else thm_default_name
  in
  (cooked, name)
;;
