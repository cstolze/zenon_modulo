(*  Copyright 1997 INRIA  *)
(*  $Id: misc.mli,v 1.7 2006-02-16 09:22:46 doligez Exp $  *)

val index : int -> 'a -> 'a list -> int;;
val ( @@ ) : 'a list -> 'a list -> 'a list;;
val list_init : int -> (unit -> 'a) -> 'a list;;
val list_last : 'a list -> 'a;;
val list_iteri : (int -> 'a -> unit) -> 'a list -> unit;;
val occurs : string -> string -> bool;;
val isalnum : char -> bool;;
val debug : ('a, out_channel, unit) format -> 'a;;
