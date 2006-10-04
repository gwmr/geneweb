(* $Id: gutil.ml,v 5.36 2006-10-04 21:26:12 ddr Exp $ *)
(* Copyright (c) 1998-2006 INRIA *)

open Def;
open Gwdb;
open Mutil;

value lindex s c =
  pos 0 where rec pos i =
    if i == String.length s then None
    else if s.[i] == c then Some i
    else pos (i + 1)
;

value list_iter_first f al =
  let _ =
    List.fold_left (fun first a -> let () = f first a in False) True al
  in
  ()
;

value string_sub s i len =
  let i = min (String.length s) (max 0 i) in
  let len = min (String.length s - i) (max 0 len) in String.sub s i len
;

value utf_8_intern_byte c =
  utf_8_db.val && Char.code c >= 0x80 && Char.code c < 0xC0;

value designation base p =
  let first_name = p_first_name base p in
  let nom = p_surname base p in
  iso_8859_1_of_utf_8
    (first_name ^ "." ^ string_of_int (get_occ p) ^ " " ^ nom)
;

value father = Adef.father;
value mother = Adef.mother;
value couple multi fath moth =
  if not multi then Adef.couple fath moth else Adef.multi_couple fath moth
;
value parent multi parent =
  if not multi then Adef.parent parent else Adef.multi_parent parent
;
value parent_array = Adef.parent_array;

value no_ascend () =
  ascend_of_gen_ascend {parents = None; consang = Adef.fix (-1)}
;

value spouse ip cpl =
  if ip == get_father cpl then get_mother cpl
  else get_father cpl
;

value person_ht_add base s ip = patch_name base s ip;

value person_is_key base p k =
  let k = Name.crush_lower k in
  if k = Name.crush_lower (p_first_name base p ^ " " ^ p_surname base p) then
    True
  else if
    List.exists (fun x -> k = Name.crush_lower x)
      (person_misc_names base p get_titles)
  then
    True
  else False
;

value person_ht_find_unique base first_name surname occ =
  if first_name = "?" || surname = "?" then raise Not_found
  else
    let first_name = nominative first_name in
    let surname = nominative surname in
    let ipl = persons_of_name base (first_name ^ " " ^ surname) in
    let first_name = Name.lower first_name in
    let surname = Name.lower surname in
    let rec find =
      fun
      [ [ip :: ipl] ->
          let p = poi base ip in
          if occ == get_occ p &&
             first_name = Name.lower (p_first_name base p) &&
             surname = Name.lower (p_surname base p)
          then
            get_key_index p
          else find ipl
      | _ -> raise Not_found ]
    in
    find ipl
;

value find_num s i =
  loop i i where rec loop start i =
    if i == String.length s then None
    else
      match s.[i] with
      [ '0'..'9' -> loop start (i + 1)
      | c ->
          if i == start then
            if c = ' ' then loop (start + 1) (start + 1) else None
          else Some (int_of_string (String.sub s start (i - start)), i) ]
;

value split_key s =
  match lindex s '.' with
  [ Some i ->
      match find_num s (i + 1) with
      [ Some (occ, j) ->
          let first_name = String.sub s 0 i in
          let surname = String.sub s j (String.length s - j) in
          (first_name, occ, surname)
      | None -> raise Not_found ]
  | None -> raise Not_found ]
;

value person_of_key base s =
  try
    let (first_name, occ, surname) = split_key s in
    Some (person_ht_find_unique base first_name surname occ)
  with
  [ Not_found -> None ]
;

value person_ht_find_all base s =
  match person_of_key base s with
  [ Some p ->
      [p]
  | _ ->
      let ipl = persons_of_name base s in
      let rec select =
        fun
        [ [ip :: ipl] ->
            if person_is_key base (poi base ip) s then
              let ipl = select ipl in
              if List.mem ip ipl then ipl else [ip :: ipl]
            else select ipl
        | [] -> [] ]
      in
      select ipl ]
;

value find_same_name base p =
  let f = p_first_name base p in
  let s = p_surname base p in
  let ipl = person_ht_find_all base (f ^ " " ^ s) in
  let f = Name.strip_lower f in
  let s = Name.strip_lower s in
  let pl =
    List.fold_left
      (fun pl ip ->
         let p = poi base ip in
         if Name.strip_lower (p_first_name base p) = f &&
            Name.strip_lower (p_surname base p) = s then
           [p :: pl]
         else pl)
      [] ipl
  in
  List.sort (fun p1 p2 -> compare (get_occ p1) (get_occ p2)) pl
;

value is_deleted_family fam = get_fam_index fam = Adef.ifam_of_int (-1);

value gen_strip_spaces strip_heading str =
  let start =
    if strip_heading then
      loop 0 where rec loop i =
        if i == String.length str then i
        else
          match str.[i] with
          [ ' ' | '\r' | '\n' | '\t' -> loop (i + 1)
          | _ -> i ]
    else 0
  in
  let stop =
    loop (String.length str - 1) where rec loop i =
      if i == -1 then i + 1
      else
        match str.[i] with
        [ ' ' | '\r' | '\n' | '\t' -> loop (i - 1)
        | _ -> i + 1 ]
  in
  if start == 0 && stop == String.length str then str
  else if start > stop then ""
  else String.sub str start (stop - start)
;

value strip_spaces = gen_strip_spaces True;

value alphabetic_utf_8 n1 n2 =
  let rec loop i1 i2 =
    if i1 >= String.length n1 && i2 >= String.length n2 then i1 - i2
    else if i1 >= String.length n1 then -1
    else if i2 >= String.length n2 then 1
    else
      let (cv1, ii1) = Name.unaccent_utf_8 False n1 i1 in
      let (cv2, ii2) = Name.unaccent_utf_8 False n2 i2 in
      let c =
        if cv1 = cv2 then
          compare (String.sub n1 i1 (ii1 - i1)) (String.sub n2 i2 (ii2 - i2))
        else compare cv1 cv2
      in
      if c = 0 then loop ii1 ii2 else c
  in
  if n1 = n2 then 0 else loop 0 0
;

value alphabetic_value =
  let tab = Array.create 256 0 in
  do {
    for i = 0 to 255 do { tab.(i) := 10 * i };
    tab.(Char.code '�') := tab.(Char.code 'a') + 1;
    tab.(Char.code '�') := tab.(Char.code 'a') + 2;
    tab.(Char.code '�') := tab.(Char.code 'a') + 3;
    tab.(Char.code '�') := tab.(Char.code 'e') + 1;
    tab.(Char.code '�') := tab.(Char.code 'e') + 2;
    tab.(Char.code '�') := tab.(Char.code 'e') + 3;
    tab.(Char.code '�') := tab.(Char.code 'e') + 4;
    tab.(Char.code '�') := tab.(Char.code 'o') + 1;
    tab.(Char.code '�') := tab.(Char.code 'A') + 2;
    tab.(Char.code '�') := tab.(Char.code 'A') + 5;
    tab.(Char.code '�') := tab.(Char.code 'E') + 1;
    tab.(Char.code '�') := tab.(Char.code 'E') + 2;
    tab.(Char.code '�') := tab.(Char.code 'O') + 4;
    tab.(Char.code '?') := 3000;
    fun x -> tab.(Char.code x)
  }
;

value alphabetic_iso_8859_1 n1 n2 =
  let rec loop i1 i2 =
    if i1 == String.length n1 && i2 == String.length n2 then i1 - i2
    else if i1 == String.length n1 then -1
    else if i2 == String.length n2 then 1
    else
      let c1 = n1.[i1] in
      let c2 = n2.[i2] in
      if alphabetic_value c1 < alphabetic_value c2 then -1
      else if alphabetic_value c1 > alphabetic_value c2 then 1
      else loop (succ i1) (succ i2)
  in
  if n1 = n2 then 0 else loop (initial n1) (initial n2)
;

value alphabetic n1 n2 =
(*
  if utf_8_db.val then alphabetic_utf_8 n1 n2 else alphabetic_iso_8859_1 n1 n2
*)
  alphabetic_iso_8859_1 n1 n2
(**)
;

value alphabetic_order n1 n2 =
  if utf_8_db.val then alphabetic_utf_8 n1 n2 else alphabetic_iso_8859_1 n1 n2
;

value map_title_strings f t =
  let t_name =
    match t.t_name with
    [ Tmain -> Tmain
    | Tname s -> Tname (f s)
    | Tnone -> Tnone ]
  in
  let t_ident = f t.t_ident in
  let t_place = f t.t_place in
  {t_name = t_name; t_ident = t_ident; t_place = t_place;
   t_date_start = t.t_date_start; t_date_end = t.t_date_end; t_nth = t.t_nth}
;

value map_relation_ps fp fs r =
  {r_type = r.r_type;
   r_fath =
     match r.r_fath with
     [ Some x -> Some (fp x)
     | None -> None ];
   r_moth =
     match r.r_moth with
     [ Some x -> Some (fp x)
     | None -> None ];
   r_sources = fs r.r_sources}
;

value map_person_ps fp fs p =
  {first_name = fs p.first_name; surname = fs p.surname; occ = p.occ;
   image = fs p.image;
   first_names_aliases = List.map fs p.first_names_aliases;
   surnames_aliases = List.map fs p.surnames_aliases;
   public_name = fs p.public_name; qualifiers = List.map fs p.qualifiers;
   titles = List.map (map_title_strings fs) p.titles;
   rparents = List.map (map_relation_ps fp fs) p.rparents;
   related = p.related; aliases = List.map fs p.aliases;
   occupation = fs p.occupation; sex = p.sex; access = p.access;
   birth = p.birth; birth_place = fs p.birth_place;
   birth_src = fs p.birth_src; baptism = p.baptism;
   baptism_place = fs p.baptism_place; baptism_src = fs p.baptism_src;
   death = p.death; death_place = fs p.death_place;
   death_src = fs p.death_src; burial = p.burial;
   burial_place = fs p.burial_place; burial_src = fs p.burial_src;
   notes = fs p.notes; psources = fs p.psources; key_index = p.key_index}
;

value map_family_ps fp fs fam =
  {marriage = fam.marriage; marriage_place = fs fam.marriage_place;
   marriage_src = fs fam.marriage_src; witnesses = Array.map fp fam.witnesses;
   relation = fam.relation; divorce = fam.divorce; comment = fs fam.comment;
   origin_file = fs fam.origin_file; fsources = fs fam.fsources;
   fam_index = fam.fam_index}
;

value map_couple_p multi_parents fp cpl =
  parent multi_parents (Array.map fp (parent_array cpl))
;

value map_descend_p fp des = {children = Array.map fp des.children};

value arg_list_of_string line =
  loop [] 0 0 None where rec loop list i len quote =
    if i == String.length line then
      if len == 0 then List.rev list else List.rev [Buff.get len :: list]
    else
      match (quote, line.[i]) with
      [ (Some c1, c2) ->
          if c1 == c2 then loop list (i + 1) len None
          else loop list (i + 1) (Buff.store len c2) quote
      | (None, ' ') ->
          let list = if len == 0 then list else [Buff.get len :: list] in
          loop list (i + 1) 0 quote
      | (None, ('"' | ''' as c)) -> loop list (i + 1) 0 (Some c)
      | (None, c) -> loop list (i + 1) (Buff.store len c) None ]
;

value sort_person_list base pl =
  List.sort
    (fun p1 p2 ->
       match
         (Adef.od_of_codate (get_birth p1), get_death p1,
          Adef.od_of_codate (get_birth p2), get_death p2)
       with
       [ (Some d1, _, Some d2, _) ->
           if CheckItem.strictly_before d1 d2 then -1 else 1
       | (Some d1, _, _, Death _ d2) ->
           if CheckItem.strictly_before d1 (Adef.date_of_cdate d2) then -1
           else 1
       | (_, Death _ d1, Some d2, _) ->
           if CheckItem.strictly_before (Adef.date_of_cdate d1) d2 then -1
           else 1
       | (_, Death _ d1, _, Death _ d2) ->
           if CheckItem.strictly_before (Adef.date_of_cdate d1)
                (Adef.date_of_cdate d2)
           then -1
           else 1
       | (Some _, _, _, _) -> 1
       | (_, Death _ _, _, _) -> 1
       | (_, _, Some _, _) -> -1
       | (_, _, _, Death _ _) -> -1
       | _ ->
           let c = alphabetic (p_surname base p1) (p_surname base p2) in
           if c == 0 then
             let c =
               alphabetic (p_first_name base p1) (p_first_name base p2)
             in
             if c == 0 then compare (get_occ p1) (get_occ p2) else c
           else c ])
    pl
;

value find_free_occ base f s i =
  let ipl = persons_of_name base (f ^ " " ^ s) in
  let first_name = Name.lower f in
  let surname = Name.lower s in
  let list_occ =
    loop [] ipl where rec loop list =
      fun
      [ [ip :: ipl] ->
          let p = poi base ip in
          if not (List.mem (get_occ p) list) &&
             first_name = Name.lower (p_first_name base p) &&
             surname = Name.lower (p_surname base p) then
            loop [get_occ p :: list] ipl
          else loop list ipl
      | [] -> list ]
  in
  let list_occ = List.sort compare list_occ in
  loop 0 list_occ where rec loop cnt1 =
    fun
    [ [cnt2 :: list] ->
        if cnt1 = cnt2 then loop (cnt1 + 1) list else cnt1
    | [] -> cnt1 ]
;

value input_lexicon lang ht open_fname =
  try
    let ic = open_fname () in
    let derived_lang =
      match lindex lang '-' with
      [ Some i -> String.sub lang 0 i
      | _ -> "" ]
    in
    try
      do {
        try
          while True do {
            let k =
              find_key (input_line ic) where rec find_key line =
                if String.length line < 4 then find_key (input_line ic)
                else if String.sub line 0 4 <> "    " then
                  find_key (input_line ic)
                else line
            in
            let k = String.sub k 4 (String.length k - 4) in
            let rec loop line =
              match lindex line ':' with
              [ Some i ->
                  let line_lang = String.sub line 0 i in
                  do {
                    if line_lang = lang ||
                       line_lang = derived_lang && not (Hashtbl.mem ht k) then
                      let v =
                        if i + 1 = String.length line then ""
                        else
                          String.sub line (i + 2) (String.length line - i - 2)
                      in
                      Hashtbl.add ht k v
                    else ();
                    loop (input_line ic)
                  }
              | None -> () ]
            in
            loop (input_line ic)
          }
        with
        [ End_of_file -> () ];
        close_in ic;
      }
    with e ->
      do { close_in ic; raise e }
  with
  [ Sys_error _ -> () ]
;

value open_base bname = Gwdb.base_of_dsk_base (Iobase.input bname);
value close_base base = Gwdb.base_cleanup base;
