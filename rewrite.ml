(*  Copyright 2003 INRIA  *)
Version.add "$Id$";;



open Expr;;
open Print;;
open Node;;
open Mlproof;;
open Phrase;;


let printer e = expr_soft (Chan stdout) e;;

let rec find_first_sym t =
  match t with
 (*   | Evar (sym, _) -> sym *)
    | Eapp (Evar(sym, _), _, _) -> sym
    | Enot (t1, _) -> find_first_sym t1
    | _ -> ""
;;

(* new assoc and mem_assoc functions
   with the Expr.equal equality
   replacing =
*)

let rec assoc_expr x = function
  | [] -> raise Not_found
  | (a,b)::l -> if (Expr.equal a x) then b else assoc_expr x l
;;

let rec mem_assoc_expr x = function
  | [] -> false
  | (a, b)::l -> (Expr.equal a x) || mem_assoc_expr x l
;;

let rec mem_expr x = function
  | [] -> false
  | a :: l -> (Expr.equal a x) || mem_expr x l
;;

exception Unif_failed;;

let rec unif_aux l e1 e2 =
  match e1, e2 with
    | Evar (_, _), _ ->
      if  not(mem_assoc_expr e1 l) then (e1, e2)::l
      else if (Expr.equal (assoc_expr e1 l) e2) then l
      else raise Unif_failed

    | Eapp (f1, args1, _), Eapp (f2, args2, _) when (Expr.equal f1 f2)
         -> (try
	      List.fold_left2 unif_aux l args1 args2
	     with
	       | Invalid_argument _ -> raise Unif_failed)

    | Enot (x1, _), Enot (y1, _)
      -> unif_aux l x1 y1
    | Eand (x1, x2, _), Eand (y1, y2, _)
      -> List.fold_left2 unif_aux l [x1;x2] [y1;y2]
    | Eor (x1, x2, _), Eor (y1, y2, _)
      -> List.fold_left2 unif_aux l [x1;x2] [y1;y2]
    | Eimply (x1, x2, _), Eimply (y1, y2, _)
      -> List.fold_left2 unif_aux l [x1;x2] [y1;y2]
    | Eequiv (x1, x2, _), Eequiv (y1, y2, _)
      -> List.fold_left2 unif_aux l [x1;x2] [y1;y2]

    | _, _ when (Expr.equal e1 e2) -> (e1, e2)::l
    | _, _ -> raise Unif_failed
;;

let unif t1 t2 = unif_aux [] t1 t2;;

let rec unif_st_aux l e1 e2 =
  match e2 with
  | Evar _ -> l
  | Eapp (v, args, _) ->
     let l' =
       begin
         try unif_aux l e1 e2
         with
         | Unif_failed -> l
       end
     in
     List.fold_left (fun x y -> unif_st_aux x e1 y) l' args
  | _ -> l
;;

let unif_st e1 e2 =
  match e1 with
  | Eapp _ -> unif_st_aux [] e1 e2
  | _ -> assert false
;;

let rec unif_sf_aux l e1 e2 =
  match e2 with
  | Eapp _ ->
     begin
       try unif_aux l e1 e2
       with
       | Unif_failed -> l
     end
  | Enot (e, _) ->
     unif_sf_aux l e1 e
  | Eand (e, e', _) ->
     List.fold_left (fun x y -> unif_sf_aux x e1 y) l [e; e']
  | Eor (e, e', _) ->
     List.fold_left (fun x y -> unif_sf_aux x e1 y) l [e; e']
  | Eimply (e, e', _) ->
     List.fold_left (fun x y -> unif_sf_aux x e1 y) l [e; e']
  | Eequiv (e, e', _) ->
     List.fold_left (fun x y -> unif_sf_aux x e1 y) l [e; e']
  | Eall (_, e, _) ->
     unif_sf_aux l e1 e
  | Eex (_, e, _) ->
     unif_sf_aux l e1 e
  | _ -> l
;;

let unif_sf e1 e2 =
  match e1 with
  | Eapp _ -> unif_sf_aux [] e1 e2
  | _ -> assert false
;;

let not_unif_subform e1 e2 =
  Log.debug 1 " | not unif subform %a ~ %a"
            Print.pp_expr e1
            Print.pp_expr e2;
  let l = unif_sf e1 e2 in
  match l with
  | [] ->
     Log.debug 1 " | true";
     true
  | _ ->
     begin
       Log.debug 1 " | false";
       List.iter
         (fun (x, y) -> Log.debug 1 " |     %a ~ %a"
                                  Print.pp_expr x Print.pp_expr y)
         l;
       false
     end
;;

let not_unif_subterm e1 e2 =
  Log.debug 1 " | not unif subterm %a ~ %a"
            Print.pp_expr e1
            Print.pp_expr e2;
  let l = unif_st e1 e2 in
  match l with
  | [] ->
     Log.debug 1 " | true";
     true
  | _ ->
     Log.debug 1 " | false";
     false
;;

let rec find_best_match incr left_rule fm =
  match left_rule, fm with
  | Evar _ , Evar _
    -> let new_incr = incr + 1 in
       new_incr
  | Eapp (Evar(sym1, _), args1, _), Eapp (Evar(sym2, _), args2, _)
       when sym1 = sym2 && List.length args1 = List.length args2
    -> let new_incr = incr + 3 in
       List.fold_left2 find_best_match new_incr args1 args2
  | Eapp _, _
    -> let new_incr = incr - 1 in
       new_incr
  | _, _ -> incr
;;

let ordering_two fm (l1, r1) (l2, r2) =
  match fm with
  | Enot (r_fm, _)
    ->
     begin
       if find_best_match 0 l1 r_fm = find_best_match 0 l2 r_fm
       then 0
       else if find_best_match 0 l1 r_fm < find_best_match 0 l2 r_fm
       then 1
       else -1
     end
  | _  ->
     begin
       if find_best_match 0 l1 fm = find_best_match 0 l2 fm
       then 0
       else if find_best_match 0 l1 fm < find_best_match 0 l2 fm
       then 1
       else -1
     end
;;

 let ordering (l1, r1) (l2, r2) =
  let fv_l1 = get_fv l1 in
  let fv_l2 = get_fv l2 in
  if List.length fv_l1 = List.length fv_l2 then 0
  else if List.length fv_l1 > List.length fv_l2 then 1
  else -1
;;

let nb_rewrite_term = ref 0
let nb_rewrite_prop = ref 0
let nb_rewrite () = (!nb_rewrite_term, !nb_rewrite_prop)

let rec rewrite_prop (l, r) p =
  try
    let subst = unif l p in
    begin
      nb_rewrite_prop := !nb_rewrite_prop + 1;
      Expr.substitute subst r
    end
  with
  | Unif_failed ->
    (match p with
      | Enot (p2, _) ->
	enot (rewrite_prop (l, r) p2)
      | _ -> p)
;;

let rec norm_prop_aux rules fm =
  match rules with
    | [] -> fm
    | (l, r) :: tl ->
      begin
	let new_fm = rewrite_prop (l, r) fm in
	if (Expr.equal fm new_fm)
	then norm_prop_aux tl fm
	else
	  begin
            Log.debug 1 "rewrite prop";
            Log.debug 1 "## %a --> %a" Print.pp_expr fm
                      Print.pp_expr new_fm;
	    new_fm
	  end
      end
;;

let norm_prop fm =
  let rules = Hashtbl.find_all !Expr.tbl_prop (find_first_sym fm) in
  (*let rules = List.sort (ordering_two fm) rules in*)
  norm_prop_aux rules fm
;;

let rec rewrite_term (l, r) p =
  try
    let subst = unif l p in
    begin
      nb_rewrite_term := !nb_rewrite_term + 1;
      Expr.substitute subst r
    end
  with
  | Unif_failed -> p
;;

let rec norm_term_aux rules t =
  match rules with
    | [] -> t
    | (l, r) :: tl ->
      norm_term_aux tl (rewrite_term (l, r) t)
;;

let rec norm_term t =
  let rules = Hashtbl.find_all !Expr.tbl_term (find_first_sym t) in
  let new_t = norm_term_aux rules t in
  if not (Expr.equal t new_t)
  then
    begin
      Log.debug 1 "rewrite term";
      Log.debug 1 "## %a --> %a" Print.pp_expr t Print.pp_expr new_t;
      norm_term new_t
    end
  else
    begin
      match t with
      | Eapp (f, args, _) ->
	eapp (f, (List.map norm_term args))
      | Enot (t1, _) ->
	enot (norm_term t1)
      | Eand (t1, t2, _) ->
	eand (norm_term t1, norm_term t2)
      | Eor (t1, t2, _) ->
	eor (norm_term t1, norm_term t2)
      | Eimply (t1, t2, _) ->
	eimply (norm_term t1, norm_term t2)
      | Eequiv (t1, t2, _) ->
	eequiv (norm_term t1, norm_term t2)

      | _ -> t
    end
;;

let is_literal fm =
  match fm with
  | Eapp(Evar _, _, _) -> true
  | Enot(Eapp(Evar _, _, _), _) -> true
  | _ -> false
;;

let rec normalize_fm fm =
  if is_literal fm then
    begin
      let fm_t = norm_term fm in
      let fm_p = norm_prop fm_t in
      if (Expr.equal fm_p fm)
      then fm
      else
        begin
          Log.debug 2 "norm fm";
          Log.debug 2 "# %a --> %a" Print.pp_expr fm Print.pp_expr fm_p;
          normalize_fm fm_p
        end
    end
  else
    fm
;;

let rec normalize_list_aux accu list =
  match list with
  | [] -> List.rev accu
  | h :: t ->
    let accu = (normalize_fm h) :: accu in
    normalize_list_aux accu t
;;

let normalize_list list =
  normalize_list_aux [] list
;;


(* heuristic *)

let is_commut_term body =
  match body with
  | Eapp (Evar("=", _), [t1; t2], _) ->
     begin
      match t1, t2 with
      | Eapp (Evar(sym1, _), [e11; e12], _), Eapp (Evar(sym2, _), [e21; e22], _)
	  when
	    (sym1 = sym2)
	    && (Expr.equal e11 e22)
	    && (Expr.equal e12 e21)
	    -> true
      | _ -> false
    end

  | _ -> false
;;

let is_assoc_term body =
  match body with
  | Eapp (Evar("=", _), [t1; t2], _) ->
    begin
      match t1, t2 with
      | Eapp (Evar(sym11, _), [e11; Eapp (Evar(sym12, _), [e12; e13], _)], _),
        Eapp (Evar(sym21, _), [Eapp (Evar(sym22, _), [e21; e22], _); e23], _)
	  when
	    (sym11 = sym12)
	    && (sym12 = sym21)
	    && (sym21 = sym22)
	    && (Expr.equal e11 e21)
	    && (Expr.equal e12 e22)
	    && (Expr.equal e13 e23)
	    -> true
      | Eapp (Evar(sym11, _), [Eapp (Evar(sym12, _), [e11; e12], _); e13], _),
	Eapp (Evar(sym21, _), [e21; Eapp (Evar(sym22, _), [e22; e23], _)], _)
	  when
	    (sym11 = sym12)
	    && (sym12 = sym21)
	    && (sym21 = sym22)
	    && (Expr.equal e11 e21)
	    && (Expr.equal e12 e22)
	    && (Expr.equal e13 e23)
	    -> true
      | _ -> false
    end
  | _ -> false
;;

let rec test_fv l1 l2 =
  match l2 with
  | [] -> true
  | h :: tl when List.mem h l1 -> test_fv l1 tl
  | _ -> false
;;

let is_pos_literal_noteq body =
  match body with
  | Eapp(Evar(sym, _), _, _) when (sym <> "=") -> true
  | _ -> false
;;

let is_neg_literal_noteq body =
  match body with
  | Enot(Eapp(Evar(sym, _), _, _), _) when (sym <> "=")-> true
  | _ -> false
;;

let is_literal_noteq body =
  match body with
  | Eapp(Evar(sym, _), _, _) when (sym <> "=") -> true
  | Enot(Eapp(Evar(sym, _), _, _), _) when (sym <> "=")-> true
  | _ -> false
;;

let is_literal_eq body =
  match body with
  | Eapp(Evar(sym, _), _, _)  -> true
  | Enot(Eapp(Evar(sym, _), _, _), _)  -> true
  | _ -> false
;;

let rec is_equal_term body =
  match body with
  | Eapp (Evar("=", _), [t1; t2], _)
      when not (is_commut_term body) ->
     begin
       match t1, t2 with
       | Eapp _, _ -> test_fv (get_fv t1) (get_fv t2)
       | _, Eapp _ -> test_fv (get_fv t2) (get_fv t1)
       | _, _ -> false
     end
  | _ -> false
;;

(*let rec is_conj_term body =
  match body with
  | Eand (e1, e2, _) -> is_conj_term e1 && is_conj_term e2
  | _ -> is_equal_term body
;;*)

let is_empty_list l =
  match l with
  | [] -> true
  | _ -> false
;;

let rec is_sym_subexpr s e =
  match e with
  | Evar(s', _) ->
     s = s'
  | Emeta _ ->
     false
  | Eapp(Evar(s', _), args, _) ->
     (s' = s) || (List.exists (is_sym_subexpr s) args)
  | Earrow _ ->
     false
  | Enot(e, _) ->
     is_sym_subexpr s e
  | Eand(e, e', _) ->
     (is_sym_subexpr s e) || (is_sym_subexpr s e')
  | Eor(e, e', _) ->
     (is_sym_subexpr s e) || (is_sym_subexpr s e')
  | Eimply(e, e', _) ->
     (is_sym_subexpr s e) || (is_sym_subexpr s e')
  | Eequiv(e, e', _) ->
     (is_sym_subexpr s e) || (is_sym_subexpr s e')
  | Etrue ->
     false
  | Efalse ->
     false
  | Eall(_, e, _) ->
     is_sym_subexpr s e
  | Eex (_, e, _) ->
     is_sym_subexpr s e
  | Etau _ ->
     false
  | Elam _ ->
     false
  | _ -> assert false
;;

let is_good_rwrt_term_aux body =
  match body with
  | Eapp (Evar ("=", _), [t1; t2], _)
       when not (is_commut_term body)
            && not (Expr.equal t1 t2) ->
     begin
       match t1, t2 with
       | Eapp _, _ ->
          test_fv (get_fv t1) (get_fv t2)
       (*&& not (is_empty_list (get_fv t1))*)
       | _, _ -> false
     end
  | _ -> false
;;

let rec is_good_rwrt_term body =
  match body with
  | Eall (_, pred, _) -> is_good_rwrt_term pred
  | _ -> is_good_rwrt_term_aux body
;;

let rec is_good_rwrt_prop_aux body =
  if is_literal_noteq body
  then true
  else
    begin
      match body with
      | Eequiv (e1, e2, _) ->
	 is_literal_noteq e1
	 && test_fv (get_fv e1) (get_fv e2)
      (* && not (is_empty_list (get_fv e1))*)
      | _ -> false
    end
;;

let rec is_good_rwrt_prop body =
  match body with
  | Eall (_, pred, _) -> is_good_rwrt_prop pred
  | _ -> is_good_rwrt_prop_aux body
;;

let is_heuri_rwrt_term_aux body =
  match body with
  | Eapp (Evar ("=", _), [t1; t2], _) ->
     begin
       match t1, t2 with
       | Eapp _, _ ->
          test_fv (get_fv t1) (get_fv t2)
          && not_unif_subterm t1 t2
          && not (is_empty_list (get_fv t1))
       | _, _ -> false
     end
  | _ -> false
;;

let rec is_heuri_rwrt_term body =
  Log.debug 1 " | is_heuri Ax : %a" Print.pp_expr body;
  match body with
  | Eall (_, pred, _) -> is_heuri_rwrt_term pred
  | _ -> is_heuri_rwrt_term_aux body
;;

let rec is_heuri_rwrt_prop_aux body =
  if (is_literal_noteq body)
     && not (is_empty_list (get_fv body))
  then true
  else
    begin
      match body with
      | Eequiv (e1, e2, _) ->
	 is_pos_literal_noteq e1
         && not_unif_subform e1 e2
         && test_fv (get_fv e1) (get_fv e2)
         && not (is_empty_list (get_fv e1))
      | _ -> false
    end
;;

let rec is_heuri_rwrt_prop body =
  Log.debug 1 " | is_heuri Ax : %a" Print.pp_expr body;
  match body with
  | Eall (_, pred, _) -> is_heuri_rwrt_prop pred
  | _ -> is_heuri_rwrt_prop_aux body
;;


let is_heuri_rwrt_term2_aux body =
  match body with
  | Eapp (Evar ("=", _), [t1; t2], _)
       when not (is_commut_term body)
            && not (Expr.equal t1 t2) ->
     begin
       match t1, t2 with
       | Eapp _, _ ->
          test_fv (get_fv t1) (get_fv t2)
          && not (is_empty_list (get_fv t1))
       | _, _ -> false
     end
  | _ -> false
;;

let rec is_heuri_rwrt_term2 body =
  match body with
  | Eall (_, pred, _) -> is_heuri_rwrt_term2 pred
  | _ -> is_heuri_rwrt_term2_aux body
;;

let rec is_heuri_rwrt_prop2_aux body =
  if (is_literal_noteq body)
     && not (is_empty_list (get_fv body))
  then true
  else
    begin
      match body with
      | Eequiv (e1, e2, _) ->
	 is_literal_noteq e1
         && test_fv (get_fv e1) (get_fv e2)
         && not (is_empty_list (get_fv e1))
      | _ -> false
    end
;;

let rec is_heuri_rwrt_prop2 body =
  match body with
  | Eall (_, pred, _) -> is_heuri_rwrt_prop2 pred
  | _ -> is_heuri_rwrt_prop2_aux body
;;

let split_to_prop_rule body =
  let parse_equiv body =
    match body with
    | Eequiv (expr1, expr2, _)
	 when is_pos_literal_noteq expr1
	      && test_fv (get_fv expr1) (get_fv expr2)
      -> (expr1, expr2)
    | Eequiv (expr1, expr2, _)
	 when is_neg_literal_noteq expr1
	      && test_fv (get_fv expr1) (get_fv expr2)
      -> begin
         match expr1 with
         | Enot(Eapp _ as new_e1, _)
           -> (new_e1, enot(expr2))
         | _ -> assert false
       end
    | Eapp (Evar(sym, _), _, _) as expr
	 when sym <> "="
      -> (expr, etrue)
    | Enot (Eapp (Evar(sym, _), _, _) as expr, _)
	 when sym <> "="
      -> (expr, efalse)
    | _ -> assert false
  in
  let rec parse body =
    match body with
    | Eall (_, expr, _) -> parse expr
    | _ -> parse_equiv body
  in
  parse body
;;

let split_to_term_rule body =
  let parse_equal body =
    match body with
    | Eapp (Evar(sym, _), [expr1; expr2], _)
	 when sym = "="
      ->
       begin
	 match expr1, expr2 with
	 | Eapp _, _ when test_fv (get_fv expr1) (get_fv expr2)
	   -> (expr1, expr2)
	 | _, Eapp _ when test_fv (get_fv expr2) (get_fv expr1)
	   -> (expr2, expr1)
	 | _, _ -> assert false
       end
    | _ -> assert false
  in
  let rec parse body =
    match body with
    | Eall (_, expr, _) -> parse expr
    | _ -> parse_equal body
  in
  parse body
;;

let add_rwrt_term name body  =
  let (x, y) = split_to_term_rule body in
  Log.debug 4 "+ rwrt_term %s: %a --> %a" name
            Print.pp_expr x
            Print.pp_expr y;
  Hashtbl.add !Expr.tbl_term (find_first_sym x) (x, y)
;;

let add_rwrt_prop name body =
  let (x, y) = split_to_prop_rule body in
  Log.debug 4 "+ rwrt_prop %s: %a --> %a" name
            Print.pp_expr x
            Print.pp_expr y;
  Hashtbl.add !Expr.tbl_prop (find_first_sym x) (x, y)
;;

let get_rwrt_from_def = function
  | DefReal (name, id, ty, args, body, _) ->
     (name, eeq (eapp (tvar id ty, args)) body)
  | DefPseudo (_, id, ty, args, body) ->
     ("pseudoDef_"^id, eeq (eapp (tvar id ty, args)) body)
  | DefRec _ -> assert false   (* This case has been filtered out in select_rwrt_rules_aux *)
;;

exception Bad_Rewrite_Rule of string * expr;;

let rec select_rwrt_rules_aux accu phrase =
  match phrase with
  | Rew (name, body, flag)
       when (flag = 2) || (flag = 1)
    ->
     assert !Globals.modulo;
     if is_good_rwrt_prop body
     then
       begin
         Log.debug 1 "|- adding rewrite prop %s: %a" name Print.pp_expr body;
         add_rwrt_prop name body;
         Rew (name, body, 1) :: accu
       end
     else if is_good_rwrt_term body
     then
       begin
         Log.debug 1 "|- adding rewrite term %s: %a" name Print.pp_expr body;
         add_rwrt_term name body;
         Rew (name, body, 0) :: accu
       end
     else raise (Bad_Rewrite_Rule (name, body))
  | Hyp (name, body, flag)
       when (flag = 2) || (flag = 1) (*|| (flag = 12) || (flag = 11) *)
    ->
     if !Globals.modulo_heuri_simple
	&& is_heuri_rwrt_prop2 body
     then
       begin
         Log.debug 1 "|- adding rewrite prop %s: %a" name Print.pp_expr body;
         add_rwrt_prop name body;
         Rew (name, body, 1) :: accu
       end
     else if !Globals.modulo_heuri_simple
             && is_heuri_rwrt_term2 body
     then
       begin
         Log.debug 1 "|- adding rewrite term %s: %a" name Print.pp_expr body;
         add_rwrt_term name body;
         Rew (name, body, 0) :: accu
       end
     else if !Globals.modulo_heuri
	     && is_heuri_rwrt_prop body
     then
       begin
         Log.debug 1 "|- adding rewrite prop %s: %a" name Print.pp_expr body;
         add_rwrt_prop name body;
         Rew (name, body, 1) :: accu
       end
     else if !Globals.modulo_heuri
             && is_heuri_rwrt_term body
     then
       begin
         Log.debug 1 "|- adding rewrite term %s: %a" name Print.pp_expr body;
         add_rwrt_term name body;
         Rew (name, body, 0) :: accu
       end
     else phrase :: accu;
  | Def (DefRec _) ->
     (* Recursive definitions are not turned into rewrite-rules (yet) *)
     phrase :: accu
  | Def d ->
     let (name, body) = get_rwrt_from_def d in
     add_rwrt_term name body;
     phrase :: accu
  | _ -> phrase :: accu
;;

let select_rwrt_rules phrases =
  Log.debug 1 "====================";
  Log.debug 1 "Select Rewrite Rules";
  List.rev (List.fold_left select_rwrt_rules_aux [] phrases)
;;
