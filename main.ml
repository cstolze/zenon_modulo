(*  Copyright 1997 INRIA  *)
Version.add "$Id$";;

open Printf;;

open Globals;;
open Namespace;;
open Expr;;

type proof_level =
  | Proof_none
  | Proof_h of int
  | Proof_m
  | Proof_l
  | Proof_lx
  | Proof_coq
  | Proof_coqterm
  | Proof_isar
  | Proof_dot of bool * int
  | Proof_dk
  | Proof_dkterm
  | Proof_lp
  | Proof_lpterm
;;

let proof_level = ref Proof_none;;
let default_depth = 100;;

type open_level =
    | Open_none
    | Open_all
    | Open_first of int
    | Open_last of int
;;

let keep_open = ref Open_none;;

type input_format =
  | I_zenon
  | I_focal
  | I_tptp
  | I_dk
;;

let input_format = ref I_zenon;;

let include_path = ref [Config.libdir];;

let opt_level = ref 1;;

let int_arg r arg =
  let l = String.length arg in
  let multiplier m =
    let arg1 = String.sub arg 0 (l-1) in
    r := m *. (float_of_string arg1)
  in
  if l = 0 then raise (Arg.Bad "bad numeric argument")
  else
    try
      match arg.[l-1] with
      | 'k' -> multiplier 1e3
      | 'M' -> multiplier 1e6
      | 'G' -> multiplier 1e9
      | 'T' -> multiplier 1e12
      | 's' -> multiplier 1.
      | 'm' -> multiplier 60.
      | 'h' -> multiplier 3600.
      | 'd' -> multiplier 86400.
      | '0'..'9' -> r := float_of_string arg
      | _ -> raise (Arg.Bad "bad numeric argument")
    with Failure x when x = "float_of_string" -> raise (Arg.Bad "bad numeric argument")
;;

let parse_size_time s =
  let l = String.length s in
  let rec loop i =
    if i >= l then raise (Arg.Bad "bad size/time specification");
    if s.[i] = '/' then begin
      int_arg size_limit (String.sub s 0 i);
      int_arg time_limit (String.sub s (i+1) (l-i-1));
    end else begin
      loop (i+1);
    end;
  in
  loop 0;
;;

let short_version () =
  printf "zenon_modulo version %s\n" Versionnum.full;
  exit 0;
;;

let cvs_version () =
  printf "zenon_modulo version %s\n" Versionnum.full;
  Version.print_cvs stdout;
  printf "source checksum: %s\n" Checksum.v;
  exit 0;
;;

let files = ref [];;
let input_file s = files := s :: !files;;

let set_random seed =
  random_flag := true;
  random_seed := seed;
;;

let print_libdir () = Printf.printf "%s\n%!" Config.libdir; exit 0

let usage_msg = "Usage: zenon_modulo [options] <file>";;

let argspec = [
  "-", Arg.Unit (fun () -> input_file "-"),
    "                  read input from stdin";
  "-context", Arg.Set ctx_flag,
           "           provide context for checking the proof independently";
  "-d", Arg.Unit (fun () -> Globals.debug_flag := true;
                            Progress.level := Progress.No),
     "                 debug mode";
  "-errmsg", Arg.String Error.set_header,
          "<message>   prefix warnings and errors with <message>";
  "-I", Arg.String (fun x -> include_path := x :: !include_path),
     " <dir>           add <dir> to the include path";
  "-I-", Arg.Unit (fun () -> include_path := []),
      "                clear the include path";
  "-icoq", Arg.Unit (fun () -> input_format := I_focal),
        "              read input file in Coq format";
  "-idk", Arg.Unit (fun () -> input_format := I_dk),
            "          read input file in Dedukti format";
  "-ifocal", Arg.Unit (fun () -> input_format := I_focal),
          "            read input file in Focal format";
  "-itptp", Arg.Unit (fun () -> input_format := I_tptp),
         "             read input file in TPTP format";
  "-iz", Arg.Unit (fun () -> input_format := I_zenon),
      "                read input file in Zenon format (default)";
  "-k", Arg.Unit (fun () -> keep_open := Open_last 0),
     "                 use incomplete proof attempts to instanciate";
  "-kall", Arg.Unit (fun () -> keep_open := Open_all),
        "              keep all incomplete proof attempts";
  "-kf", Arg.Int (fun n -> keep_open := Open_first n),
      "<n>             keep the first <n> proof attempts";
  "-kl", Arg.Int (fun n -> keep_open := Open_last n),
      "<n>             keep the last <n> proof attempts";
  "-loadpath", Arg.Set_string load_path,
    sprintf "          path to Zenon's coq libraries (default %s)"
            Config.libdir;
  "-max", Arg.String parse_size_time,
       "<s>[kMGT]/<i>[kMGT]/<t>[smhd] set size, step, and time limits"
       ^ " (see below)";
  "-max-size", Arg.String (int_arg size_limit),
            "<s>[kMGT] limit heap size to <s> kilo/mega/giga/tera byte"
            ^ " (1G)";
  "-max-step", Arg.String (int_arg step_limit),
            "<i>[kMGT] limit number of steps to <i> kilo/mega/giga/tera"
            ^ " (10k)";
  "-max-time", Arg.String (int_arg time_limit),
            "<t>[smhd] limit CPU time to <t> second/minute/hour/day"
            ^ " (5m)";
  "-ocoq", Arg.Unit (fun () -> namespace_flag := true; proof_level := Proof_coq),
        "              print the proof in Coq script format (force -rename)";
  "-ocoqterm", Arg.Unit (fun () -> proof_level := Proof_coqterm),
            "          print the proof in Coq term format";
  "-odk", Arg.Unit (fun () -> namespace_flag := true;
                              quiet_flag := true;
			      proof_level := Proof_dk;
			      opt_level := 0;
			      Globals.output_dk := true),
        "               print the proof in Dk script format (force -rename)";
  "-sig", Arg.String (fun s -> Globals.signature_name := s),
              "              print the proof using a signature name for each symbol";
  "-odkterm", Arg.Unit (fun () -> proof_level := Proof_dkterm;
				  opt_level := 0;
				  Globals.output_dk := true),
            "           print the proof in DK term format";
  "-olp", Arg.Unit (fun () -> namespace_flag := true;
                              quiet_flag := true;
			      proof_level := Proof_lp;
			      opt_level := 0;
			      Globals.output_lp := true),
        "               print the proof in lambdapi script format (force -rename)";
  "-olpterm", Arg.Unit (fun () -> proof_level := Proof_lpterm;
				  opt_level := 0;
				  Globals.output_lp := true),
            "           print the proof in lambdapi term format";
  "-neg-conj", Arg.String (fun s -> Globals.neg_conj := s),
      "<n>             set the negated conjecture name";
  "-check-axiom", Arg.Unit (fun () -> Globals.check_axiom := true),
      "<n>             indicate whether this is a GDV leaf problem";
  "-oh", Arg.Int (fun n -> proof_level := Proof_h n),
      "<n>             print the proof in high-level format up to depth <n>";
  "-oisar", Arg.Unit (fun () -> proof_level := Proof_isar),
         "             print the proof in Isar format";
  "-ol", Arg.Unit (fun () -> proof_level := Proof_l),
      "                print the proof in low-level format";
  "-olx", Arg.Unit (fun () -> proof_level := Proof_lx),
       "               print the proof in raw low-level format";
  "-om", Arg.Unit (fun () -> proof_level := Proof_m),
      "                print the proof in middle-level format";
  "-onone", Arg.Unit (fun () -> proof_level := Proof_none),
         "             do not print the proof (default)";
  "-odot", Arg.Unit (fun () -> proof_level := Proof_dot (true, default_depth)),
        "              print the proof in dot format (use with -q option)";
  "-odotd", Arg.Int (fun n -> proof_level := Proof_dot (true, n)),
         "             print the proof in dot format (use with -q option)(less verbose)";
  "-odotl", Arg.Int (fun n -> proof_level := Proof_dot (false, n)),
         "             print the proof in dot format (use with -q option)(less verbose)";
  "-opt0", Arg.Unit (fun () -> opt_level := 0),
        "              do not optimise the proof";
  "-opt1", Arg.Unit (fun () -> opt_level := 1),
        "              do peephole optimisation of the proof (default)";
  "-p0", Arg.Unit (fun () -> Progress.level := Progress.No),
      "                turn off progress bar and progress messages";
  "-p1", Arg.Unit (fun () -> Progress.level := Progress.Bar),
      "                display progress bar (default)";
  "-p2", Arg.Unit (fun () -> Progress.level := Progress.Msg),
      "                display progress messages";
  "-q", Arg.Set quiet_flag,
     "                 suppress proof-found/no-proof/begin-proof/end-proof";
  "-rename", Arg.Set namespace_flag,
          "            prefix all input symbols to avoid clashes";
  "-rnd", Arg.Int set_random,
       "<seed>         randomize proof search";
  "-stats", Arg.Set stats_flag,
         "             print statistics";
  "-short", Arg.Set short_flag,
         "             output a less detailed proof";
  "-use-all", Arg.Set use_all_flag,
           "           output a proof that uses all the hypotheses";
  "-v", Arg.Unit short_version,
     "                 print version string and exit";
  "-vv", Arg.Int Log.set_debug,
      "                set the verbose level for debug output (default 0)";
  "-versions", Arg.Unit cvs_version,
            "          print CVS version strings and exit";
  "-w", Arg.Clear Error.warnings_flag,
     "                 suppress warnings";
  "-where", Arg.Unit print_libdir,
         "             print the location of the zenon library and exit";
  "-wout", Arg.Set_string Error.err_file,
        "<file>        output errors and warnings to <file> instead of stderr";
  "-x", Arg.String Extension.activate,
     "<ext>            activate extension <ext>";
  "-modulo", Arg.Set modulo,
     "             build the rewrite system from TPTP meta info";
  "-modulo-heuri", Arg.Set modulo_heuri,
     "             build the rewrite system from heuristic";
  "-modulo-heuri-simple", Arg.Set modulo_heuri_simple,
     "             build the rewrite system from heuristic simple";
  "-dbg-rwrt", Arg.Set debug_rwrt,
     "             debug mode for rewriting"
];;

let print_usage () =
  Arg.usage argspec usage_msg;
  eprintf "The default include path is the following:\n";
  List.iter (fun x -> eprintf "  %s\n" x) !include_path;
  exit 0;
;;

let do_exit code = exit (code + if !Error.got_warning then 100 else 0);;

let report_error lexbuf msg =
  let p = Lexing.lexeme_start_p lexbuf in
  Error.errpos p msg;
  do_exit 3;
;;

let make_lexbuf stdin_opt f =
  let (name, chan, close) =
    match f with
    | "-" when stdin_opt -> ("", stdin, ignore)
    | _ -> (f, open_in f, close_in)
  in
  let lexbuf = Lexing.from_channel chan in
  lexbuf.Lexing.lex_curr_p <- {
     Lexing.pos_fname = name;
     Lexing.pos_lnum = 1;
     Lexing.pos_bol = 0;
     Lexing.pos_cnum = 0;
  };
  (lexbuf, fun () -> close chan)
;;

let zparse_file f =
  let (lexbuf, closer) = make_lexbuf false f in
  let result = Parsezen.file Lexzen.token lexbuf in
  closer ();
  result
;;

let rec expand_includes incpath zphrases =
  let exp p =
    match p with
    | Phrase.Zhyp (s, e, i) -> [Phrase.Hyp (s, e, i)]
    | Phrase.Zdef (d) -> [Phrase.Def (d)]
    | Phrase.Zsig (s, l, t) -> [Phrase.Sig (s, l, t)]
    | Phrase.Zinductive (s, a, l, sc) -> [Phrase.Inductive (s, a, l, sc)]
    | Phrase.Zinclude f ->
       begin
         let rec loop l =
           match l with
           | [] ->
              eprintf "include file not found: %s\n" f;
              do_exit 15;
           | h::t ->
              let pf = try Some (zparse_file (Filename.concat h f))
                       with _ -> None
              in
              match pf with
              | Some p -> expand_includes incpath p
              | None -> loop t
         in
         loop incpath
       end
  in
  List.concat (List.map exp zphrases)
;;

let parse_file f =
  try
    let (lexbuf, closer) = make_lexbuf true f in
    try
      match !input_format with
      | I_tptp ->
          let tpphrases = Parsetptp.file Lextptp.token lexbuf in
          closer ();
          let d = Filename.dirname f in
          let pp = Filename.parent_dir_name in
          let upup = Filename.concat (Filename.concat d pp) pp in
          begin
            try
              let tptp_env = Sys.getenv "TPTP" in
              let incpath = List.rev (tptp_env :: upup :: d :: !include_path) in
              let (forms, name) = Tptp.translate incpath tpphrases in
              let forms = Typetptp.typecheck forms in
	      (name, List.map (fun x -> (x, false)) forms)
            with Not_found ->
              let incpath = List.rev (upup :: d :: !include_path) in
              let (forms, name) = Tptp.translate incpath tpphrases in
              let forms = Typetptp.typecheck forms in
	      (name, List.map (fun x -> (x, false)) forms)
          end
      | I_focal ->
          let (name, result) = Parsecoq.file Lexcoq.token lexbuf in
          closer ();
          let typer_options =
            { Typer.default_type = Expr.type_none;
              Typer.scope_warnings = true;
              Typer.undeclared_functions_warning = false;
              Typer.register_new_constants = true;
              Typer.fully_type = false }
          in
          (name, Typer.phrasebl typer_options result)
      | I_dk ->
          let (name, result) = Parsedk.file Lexdk.token lexbuf in
          closer ();
          let typer_options =
            { Typer.default_type = Expr.type_none;
              Typer.scope_warnings = true;
              Typer.undeclared_functions_warning = true;
              Typer.register_new_constants = false;
              Typer.fully_type = true }
          in
          (name, Typer.phrasebl typer_options result)
      | I_zenon ->
          let zphrases = Parsezen.file Lexzen.token lexbuf in
          closer ();
          let incpath = List.rev (Filename.dirname f :: !include_path) in
          let phrases = expand_includes incpath zphrases in
          let result = List.map (fun x -> (x, false)) phrases in
          let is_goal = function
            | (Phrase.Hyp (name, _, _), _) -> name = goal_name
            | _ -> false
          in
          let goal_found = List.exists is_goal result in
          if not goal_found then Error.warn "no goal given";
          let typer_options =
            { Typer.default_type = Expr.type_iota;
              Typer.scope_warnings = false;
              Typer.undeclared_functions_warning = false;
              Typer.register_new_constants = false;
              Typer.fully_type = false }
          in
          (thm_default_name, Typer.phrasebl typer_options result)
    with
    | Parsing.Parse_error -> report_error lexbuf "syntax error."
    | Error.Lex_error msg -> report_error lexbuf msg
  with Sys_error (msg) -> Error.err msg; do_exit 4;
;;

let rec extract_strong accu phr_dep =
  match phr_dep with
  | [] -> accu
  | (p, true) :: t -> extract_strong (p::accu) t
  | (_, false) :: t -> extract_strong accu t
;;

let optim p =
  match !opt_level with
  | 0 -> p
  | 1 -> Llproof.optimise p
  | _ -> assert false
;;

let main () =
  Gc.set {(Gc.get ()) with
          Gc.minor_heap_size = 1_000_000;
          Gc.major_heap_increment = 1_000_000;
         };
  let file = match !files with
             | [f] -> f
             | _ -> Arg.usage argspec usage_msg; exit 2
  in
  Extension.predecl ();
  let (th_name, phrases_dep) = parse_file file in
  begin match !proof_level with
  | Proof_coq | Proof_coqterm -> Watch.warn_unused_var phrases_dep;
  | _ -> ()
  end;
  let retcode = ref 0 in
  begin try
    let phrases = List.map fst phrases_dep in
    let phrases = Rewrite.select_rwrt_rules phrases in
    let ppphrases = Extension.preprocess phrases in
    List.iter Extension.add_phrase ppphrases;
    if !Globals.debug_rwrt
    then
      begin
	Print.print_tbl_term (Print.Chan stdout) !tbl_term;
	Print.print_tbl_prop (Print.Chan stdout) !tbl_prop;
      end;
    let (defs, hyps) = Phrase.separate (Extension.predef ()) ppphrases in
    List.iter (fun (fm, _) -> Eqrel.analyse fm) hyps;
    let hyps = List.filter (fun (fm, _) -> not (Eqrel.subsumed fm)) hyps in
    if !debug_flag then begin
      let ph_defs = List.map (fun x -> Phrase.Def x) defs in
      let ph_hyps = List.map (fun (x, y) -> Phrase.Hyp ("", x, y)) hyps in
      eprintf "initial formulas:\n";
      List.iter (Print.phrase (Print.Chan stderr)) (ph_defs @ ph_hyps);
      eprintf "relations: ";
      Eqrel.print_rels stderr;
      eprintf "\n";
      eprintf "typing declarations: ";
      eprintf "\n";
      Typer.print_constant_decls stderr;
      eprintf "----\n";
      flush stderr;
      Gc.set {(Gc.get ()) with Gc.verbose = 0x010};
    end;
    let params = match !keep_open with
        | Open_none -> Prove.default_params
        | Open_all -> Prove.open_params None
        | Open_first n -> Prove.open_params (Some n)
        | Open_last n -> Prove.open_params (Some (-n))
    in
    let proofs = Prove.prove params defs hyps in
    let proof= List.hd proofs in
    let is_open = Mlproof.is_open_proof proof in
    if is_open then
        retcode := 12;
    if not !quiet_flag then begin
      if is_open then
        if !Globals.signature_name <> "" then ()
        else printf "%s" (begin_comment() ^ " NO-PROOF " ^ end_comment() ^ "\n")
      else
        if !Globals.signature_name <> "" then ()
        else printf "%s" (begin_comment() ^ " PROOF-FOUND " ^ end_comment() ^ "\n");
      flush stdout
      end;
    let llp = lazy (optim (Extension.postprocess
                             (Mltoll.translate th_name ppphrases proof)))
    in
    begin match !proof_level with
    | Proof_none -> ()
    | Proof_h n -> Print.hlproof (Print.Chan stdout) n proof;
    | Proof_m -> Print.mlproof (Print.Chan stdout) proof;
    | Proof_lx ->
        let lxp = Mltoll.translate th_name ppphrases proof in
        Print.llproof (Print.Chan stdout) lxp;
    | Proof_l -> Print.llproof (Print.Chan stdout) (Lazy.force llp);
    | Proof_coq ->
        let u = Lltocoq.output stdout phrases ppphrases (Lazy.force llp) in
        Watch.warn phrases_dep llp u;
    | Proof_coqterm ->
        let (p, u) = Coqterm.trproof phrases ppphrases (Lazy.force llp) in
        Coqterm.print stdout p;
        Watch.warn phrases_dep llp u;
    | Proof_dk ->
        let u = Lltodk.output stdout phrases (Lazy.force llp) in
        Watch.warn phrases_dep llp u;
    | Proof_dkterm ->
       let u = Lltodk.output_term stdout phrases ppphrases (Lazy.force llp) in
       Watch.warn phrases_dep llp u;
    | Proof_lp ->
        let u = Lltolp.output stdout phrases (Lazy.force llp) in
        Watch.warn phrases_dep llp u;
    | Proof_lpterm ->
       let u = Lltolp.output_term stdout phrases ppphrases (Lazy.force llp) in
       Watch.warn phrases_dep llp u;
    | Proof_isar ->
        let u = Lltoisar.output stdout phrases ppphrases (Lazy.force llp) in
        Watch.warn phrases_dep llp u;
    | Proof_dot (b, n) ->
        Print.dots ~full_output:b ~max_depth:n (Print.Chan stdout) (List.rev proofs);
    end;
  with
  | Prove.NoProof ->
     retcode := 12;
     if not !quiet_flag then (if !Globals.signature_name <> "" then () else printf "(* NO-PROOF *)\n");
  | Prove.LimitsExceeded ->
     retcode := 13;
     if not !quiet_flag then (if !Globals.signature_name <> "" then () else printf "(* NO-PROOF *)\n");
  end;
  if !stats_flag then begin
    eprintf "nodes searched: %d\n" !Globals.inferences;
    eprintf "max branch formulas: %d\n" !Globals.top_num_forms;
    eprintf "proof nodes created: %d\n" !Globals.proof_nodes;
    eprintf "formulas created: %d\n" !Globals.num_expr;
    eprintf "\n";
    (*Gc.print_stat stderr;*)
  end;
  let nb_term, nb_prop = Rewrite.nb_rewrite () in
  printf "Number of rewrites on terms: %d\nNumber of rewrites on props: %d\n" nb_term nb_prop;
  do_exit !retcode
;;

let parse_command_line argspec =
  try Arg.parse argspec input_file usage_msg
  with Not_found -> exit 2
;;

let do_main () =
  try main ()
  with
  | Error.Abort -> do_exit 11;
  | Expr.Type_Mismatch (t, t', f) ->
          let s = Printexc.get_backtrace () in
          Format.eprintf "Mismatched type : expected '%s' but instead received '%s' (in %s)@\nBacktrace :@\n%s@."
          (Print.sexpr t) (Print.sexpr t') f s;
          do_exit 11;
 | Expr.Ill_typed_substitution (map) ->
          let s = Printexc.get_backtrace () in
          Format.eprintf "Ill-typed substitution [%s].@\nBacktrace :@\n%s@."
                        (String.concat
                           "; "
                           (List.map (fun (x, y) ->
                                      Printf.sprintf "%s ↦ %s"
                                                     (Print.sexpr_t x)
                                                     (Print.sexpr_t y))
                                     map))
                        s;
          do_exit 11;

  (*
  | e -> eprintf "Zenon error: uncaught exception %s\n" (Printexc.to_string e);
         do_exit 14; *)
;;
