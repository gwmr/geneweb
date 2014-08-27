(*
   Copyright 2009, 2010, 2011 Anton Lavrik

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*)

(* Runtime support for JSON-XML-Protobuf-Piq serialization
 *
 * This module is used by OCaml modules generated by "piqic ocaml-ext" Piqi
 * compiler.
 *)


open Piqi_common


type input_format = [ `piq | `json | `xml | `pb | `wire ]

type output_format = [ input_format | `json_pretty | `xml_pretty ]

type piqtype = T.piqtype

type options = Piqi_convert.options


let _ =
  Piqilib.init ();
  Piqi_convert.init ()


let add_piqi (piqi_bin: string) =
  let buf = Piqirun.init_from_string piqi_bin in
  let _piqi = Piq.piqi_of_wire buf ~cache:true in
  (* reset location db to allow GC to collect previously read objects *)
  Piqloc.reset ();
  ()


let seen = ref []

let init_piqi piqi_list =
  if not (List.memq piqi_list !seen)
  then (
    seen:= piqi_list :: !seen;
    List.iter add_piqi piqi_list
  )


let find_piqtype (typename :string) :piqtype =
  Piqi_convert.find_piqtype typename


(* preallocate default convert options *)
let default_options = Piqi_convert.make_options ()

let default_options_no_pp =
  {
    default_options with
    Piqi_convert.pretty_print = false
  }


let make_options = Piqi_convert.make_options


let convert
        ?opts
        (piqtype :piqtype)
        (input_format :input_format)
        (output_format :output_format)
        (data :string) :string =
  if output_format = (input_format :> output_format)
  then data
  else
    let output_format, default_opts =
      match output_format with
        | `json_pretty -> `json, default_options
        | `xml_pretty -> `xml, default_options
        | (#input_format as x) -> x, default_options_no_pp
    in
    let opts =
      match opts with
        | None -> default_opts
        | Some x -> x
    in
    let res = Piqi_convert.convert_piqtype
      piqtype input_format output_format data ~opts
    in
    (* reset location db to allow GC to collect previously read objects *)
    Piqloc.reset ();
    res

