(*
Copyright (c) 2015, Guillaume Bury
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)

exception Expected_root of string * Hierarchy.cgroup
exception Subsystem_not_available of CGSubsystem.t
exception Subsystem_not_attached of CGSubsystem.t * Hierarchy.cgroup

type ('ty, 'attr) t = {
  name : string;
  subsystem : CGSubsystem.t option;

  reset_value : string;
  from_string : string -> 'ty;
  to_string : 'ty -> string;

  check : Hierarchy.cgroup -> unit;
}

let check sub_opt =
  match sub_opt with
  | None -> assert false
  | Some sub ->
    (fun g ->
       if not sub.CGSubsystem.available then
         raise (Subsystem_not_available sub)
       else if not (List.mem sub (Hierarchy.subsys g)) then
         raise (Subsystem_not_attached (sub, g))
    )

let mk subsystem name from_string
    ?(reset_value = "") ?(to_string = (fun _ -> ""))
    ?(check=(check subsystem)) () =
  { name; subsystem; reset_value; from_string; to_string; check; }

(* Cgroup tunable parameters *)
let notify_on_release = mk None "notify_on_release" Util.Get.bool
    ~to_string:Util.Set.bool ~check:(fun _ -> ()) ()

let release_agent = mk None "release_agent" Util.Get.string
    ~to_string:Util.Set.string ~check:(fun g ->
        if not (Hierarchy.is_root g) then
          raise (Expected_root ("release_agent", g))
      ) ()

(* Attribute creation *)
let mk_get sub name from_string = mk (Some sub) name from_string ()

let mk_set sub name from_string to_string = mk (Some sub) name from_string ~to_string ()

let mk_reset sub name from_string reset_value = mk (Some sub) name from_string ~reset_value ()

(* Low-level Accessors *)
let file t =
  match t.subsystem with
  | None -> Format.asprintf "%s" t.name
  | Some sub -> Format.asprintf "%s.%s" sub.CGSubsystem.name t.name

let raw_get attr path =
  let f = Filename.concat path (file attr) in
  let rec aux ch acc =
    match input_line ch with
    | exception End_of_file -> acc
    | s -> aux ch (s :: acc)
  in
  let ch = open_in f in
  let res = String.concat "\n" (List.rev (aux ch [])) in
  close_in ch;
  res

let raw_set attr path value =
  let f = Filename.concat path (file attr) in
  let ch = open_out f in
  output_string ch value;
  close_out ch

(* High-level accessors *)

let get t g =
  t.check g;
  t.from_string (raw_get t (Hierarchy.path g))

let set t g value =
  t.check g;
  raw_set t (Hierarchy.path g) (t.to_string value)

let reset t g =
  t.check g;
  raw_set t (Hierarchy.path g) t.reset_value

