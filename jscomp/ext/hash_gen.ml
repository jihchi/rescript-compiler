(***********************************************************************)
(*                                                                     *)
(*                                OCaml                                *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License, with    *)
(*  the special exception on linking described in file ../LICENSE.     *)
(*                                                                     *)
(***********************************************************************)

(* Hash tables *)




(* We do dynamic hashing, and resize the table and rehash the elements
   when buckets become too long. *)

type ('a, 'b) bucketlist =
  | Empty
  | Cons of {key : 'a ; data : 'b ; rest :  ('a, 'b) bucketlist}

type ('a, 'b) t =
  { mutable size: int;                        (* number of entries *)
    mutable data: ('a, 'b) bucketlist array;  (* the buckets *)
    initial_size: int;                        (* initial array size *)
  }



let create  initial_size =
  let s = Ext_util.power_2_above 16 initial_size in
  { initial_size = s; size = 0; data = Array.make s Empty }

let clear h =
  h.size <- 0;
  let len = Array.length h.data in
  for i = 0 to len - 1 do
    h.data.(i) <- Empty
  done

let reset h =
  h.size <- 0;
  h.data <- Array.make h.initial_size Empty


let length h = h.size

let resize indexfun h =
  let odata = h.data in
  let osize = Array.length odata in
  let nsize = osize * 2 in
  if nsize < Sys.max_array_length then begin
    let ndata = Array.make nsize Empty in
    h.data <- ndata;          (* so that indexfun sees the new bucket count *)
    let rec insert_bucket = function
        Empty -> ()
      | Cons l ->
        insert_bucket l.rest; (* preserve original order of elements *)
        let nidx = indexfun h l.key in
        Array.unsafe_set
          ndata nidx
          (Cons {l with 
                 rest = 
                   Array.unsafe_get ndata nidx}) in
    for i = 0 to osize - 1 do
      insert_bucket (Array.unsafe_get odata i)
    done
  end



let iter h f =
  let rec do_bucket = function
    | Empty ->
      ()
    | Cons l  ->
      f l.key l.data; do_bucket l.rest in
  let d = h.data in
  for i = 0 to Array.length d - 1 do
    do_bucket (Array.unsafe_get d i)
  done

let fold h init f =
  let rec do_bucket b accu =
    match b with
      Empty ->
      accu
    | Cons l ->
      do_bucket l.rest (f l.key l.data accu) in
  let d = h.data in
  let accu = ref init in
  for i = 0 to Array.length d - 1 do
    accu := do_bucket (Array.unsafe_get d i) !accu
  done;
  !accu

let to_list h f =
  fold h [] (fun k data acc -> f k data :: acc)  




let rec small_bucket_mem (lst : _ bucketlist) eq key  =
  match lst with 
  | Empty -> false 
  | Cons lst -> 
    eq  key lst.key ||
    match lst.rest with
    | Empty -> false 
    | Cons lst -> 
      eq key lst.key  || 
      match lst.rest with 
      | Empty -> false 
      | Cons lst -> 
        eq key lst.key  ||
        small_bucket_mem lst.rest eq key 


let rec small_bucket_opt eq key (lst : _ bucketlist) : _ option =
  match lst with 
  | Empty -> None 
  | Cons lst -> 
    if eq  key lst.key then Some lst.data else 
      match lst.rest with
      | Empty -> None 
      | Cons lst -> 
        if eq key lst.key then Some lst.data else 
          match lst.rest with 
          | Empty -> None 
          | Cons lst -> 
            if eq key lst.key  then Some lst.data else 
              small_bucket_opt eq key lst.rest


let rec small_bucket_key_opt eq key (lst : _ bucketlist) : _ option =
  match lst with 
  | Empty -> None 
  | Cons {key=k1;  rest=rest1} -> 
    if eq  key k1 then Some k1 else 
      match rest1 with
      | Empty -> None 
      | Cons {key=k2; rest=rest2} -> 
        if eq key k2 then Some k2 else 
          match rest2 with 
          | Empty -> None 
          | Cons {key=k3;  rest=rest3} -> 
            if eq key k3  then Some k3 else 
              small_bucket_key_opt eq key rest3


let rec small_bucket_default eq key default (lst : _ bucketlist) =
  match lst with 
  | Empty -> default 
  | Cons lst -> 
    if eq  key lst.key then  lst.data else 
      match lst.rest with
      | Empty -> default 
      | Cons lst -> 
        if eq key lst.key then  lst.data else 
          match lst.rest with 
          | Empty -> default 
          | Cons lst -> 
            if eq key lst.key  then lst.data else 
              small_bucket_default eq key default lst.rest


module type S = sig 
  type key
  type 'a t
  val create: int -> 'a t
  val clear: 'a t -> unit
  val reset: 'a t -> unit

  val add: 'a t -> key -> 'a -> unit
  val modify_or_init: 'a t -> key -> ('a -> unit) -> (unit -> 'a) -> unit 
  val remove: 'a t -> key -> unit
  val find_exn: 'a t -> key -> 'a
  val find_all: 'a t -> key -> 'a list
  val find_opt: 'a t -> key  -> 'a option

  (** return the key found in the hashtbl.
      Use case: when you find the key existed in hashtbl, 
      you want to use the one stored in the hashtbl. 
      (they are semantically equivlanent, but may have other information different) 
  *)
  val find_key_opt: 'a t -> key -> key option 

  val find_default: 'a t -> key -> 'a -> 'a 

  val replace: 'a t -> key -> 'a -> unit
  val mem: 'a t -> key -> bool
  val iter: 'a t -> (key -> 'a -> unit) -> unit
  val fold: 
    'a t -> 'b ->
    (key -> 'a -> 'b -> 'b) ->  'b
  val length: 'a t -> int
  (* val stats: 'a t -> Hashtbl.statistics *)
  val to_list : 'a t -> (key -> 'a -> 'c) -> 'c list
  val of_list2: key list -> 'a list -> 'a t
end



#if 0 then
let rec bucket_length accu = function
  | Empty -> accu
  | Cons l -> bucket_length (accu + 1) l.rest

let stats h =
  let mbl =
    Ext_array.fold_left h.data 0 (fun m b -> max m (bucket_length 0 b)) in
  let histo = Array.make (mbl + 1) 0 in
  Ext_array.iter h.data
    (fun b ->
       let l = bucket_length 0 b in
       histo.(l) <- histo.(l) + 1)
    ;
  {Hash.
    num_bindings = h.size;
    num_buckets = Array.length h.data;
    max_bucket_length = mbl;
    bucket_histogram = histo }
#end
