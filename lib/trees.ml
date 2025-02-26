(* tree construction tools *)
(* v1  Henri, 2023/10/16 *)

let rule_thickns = "0.5pt"
let row_width row = List.fold_left (fun w (_, s, _, _, _, _) -> w + s) 0 row
let row_nb = ref 0
let nb_rows = ref 0

(* TODO Imagek = Portrait ?? no *)
type im_type = Portrait | Imagek | Images | Vignette

type image = {
  im_type : im_type;
  filename : string;
  where : int * int * int * int; (* ch, sec, ssec, sssec*)
  image_nbr : int;
}

(* width, span, (E O Hr Hc Hl Vc Im), item, text, image *)
type c_type = E | Hc | Hr | Hl | Vr1 | Vr2 | Te | It | Im

type t_cell = {
  width : float;
  span : int;
  typ : string;
  item : string;
  txt : string;
  img : int;
}

type t_line = t_cell list
type t_table = { row : int; col : int; body : t_line list }

let test_tree_width tree =
  let rec loop first i w0 tree =
    match tree with
    | [] -> (i, w0, w0, true)
    | row :: tree ->
        let w = row_width row in
        if first then loop false (i + 1) w tree
        else if w <> w0 then (i + 1, w, w0, false) (* unballanced tree *)
        else loop false (i + 1) w0 tree
  in
  loop true 0 0 tree

(* no test on i relative to nb cols! *)
let is_empty_cell row i =
  let rec loop j row =
    match row with
    | [] -> false
    | (_, s, ty, _, _, _) :: row ->
        (* loop to column i span by span *)
        if j + s < i then loop (j + s) row
        else
          (* inch one by one to i within span *)
          let rec loop1 k =
            if j + k = i then
              ty = "E" || ty = "Hc" || ty = "Hr --" || ty = "Hr r-"
              || ty = "Hr -l"
            else loop1 (k + 1)
          in
          loop1 1
  in
  loop 0 row

let update_cols old_cols row =
  let rec loop cols i row =
    match row with
    | [] -> List.rev cols
    | (_, s, ty, _, _, _) :: row ->
        let cols1 =
          let rec loop1 cols1 j =
            let j1 = string_of_int (i + j) in
            if j = s then cols1
            else if (List.nth old_cols (i - 1)).[0] <> 'E' then
              loop1 (("F" ^ j1) :: cols1) (j + 1)
            else if
              ty = "E" || ty = "Hc" || ty = "Hr --" || ty = "Hr r-"
              || ty = "Hr -l"
            then loop1 (("E" ^ j1) :: cols1) (j + 1)
            else loop1 (("F" ^ j1) :: cols1) (j + 1)
          in
          loop1 [] 0
        in
        loop (cols1 @ cols) (i + s) row
  in
  loop [] 1 row

(* an empty column is a column with only E, Hc, Hr --, Hr r-, Hr -l *)
(* scan the whole tree row by row to determine empty columns *)
let find_empty_columns tree =
  (* i is row number *)
  let _i, width, _w0, _ok = test_tree_width tree in
  let cols =
    (* set all columns to empty *)
    let rec loop n acc = if n = 0 then acc else loop (n - 1) ("E" :: acc) in
    loop width []
  in
  let rec loop cols tree =
    match tree with
    | [] -> cols
    | row :: tree -> loop (update_cols cols row) tree
  in
  loop cols tree

let get_part lr side str =
  let str = Sutil.clean_double_back_slash str in
  let str = Sutil.suppress_trailing_sp str in
  let str = Sutil.suppress_leading_sp str in
  let str = Sutil.replace_utf8_bar str in
  let res =
    match (lr, side) with
    | 0, "left" -> String.sub str 1 (String.length str - 1)
    | 0, "right" -> String.sub str 1 (String.length str - 1)
    | 1, "left" -> String.sub str 0 (String.length str - 1)
    | 1, "right" -> String.sub str 0 (String.length str - 1)
    | _, _ -> str
  in
  res

let scan_row_for_bar row =
  let utf8_bar = String.of_seq (List.to_seq [ '\xE2'; '\x94'; '\x82' ]) in
  List.fold_left
    (fun (lr, bar) (_, _, _, te, it, _im) ->
      let i = try String.index te '|' with Not_found -> -1 in
      let j = try String.index it '|' with Not_found -> -1 in
      let k = try String.index te '\xE2' with Not_found -> -1 in
      let l = try String.index it '\xE2' with Not_found -> -1 in
      let left_right =
        if i = 0 || j = 0 || k = 0 || l = 0 then 0
        else if i = -1 && j = -1 && k = -1 && l = -1 then -1
        else 1
      in
      let bar =
        bar || String.contains te '|' || String.contains it '|'
        || Sutil.contains te utf8_bar || Sutil.contains it utf8_bar
      in
      let lr =
        match (lr, left_right) with
        | -1, 0 -> 0
        | 0, -1 -> 0
        | 0, 0 -> 0
        | -1, 1 -> 1
        | 1, -1 -> 1
        | 1, 1 -> 1
        | _, _ -> -1
      in
      (lr, bar))
    (-1, false) row

let copy_row row lr side =
  List.map
    (fun (w, s, ty, te, it, im) ->
      ( w,
        s,
        (if side = "bar" then match ty with "Te" | "It" -> "Vr2" | _ -> ty
        else ty),
        (if side = "bar" then ""
        else match ty with "Te" -> get_part lr side te | _ -> te),
        (if side = "bar" then ""
        else match ty with "It" -> get_part lr side it | _ -> it),
        if side = "bar" then ""
        else match ty with "Im" -> get_part lr side im | _ -> im ))
    row

let print_row row =
  Printf.eprintf "Row:\n";
  List.iter
    (fun (_, s, ty, te, it, im) ->
      let te = Sutil.clean_double_back_slash_2 te |> Sutil.clean_item in
      let it = Sutil.clean_double_back_slash_2 it |> Sutil.clean_item in
      Printf.eprintf "[ (%d) %s te:%s it:%s im:%s], " s ty te it im)
    row;
  Printf.eprintf "\n"

(* in fact, the extra | appears as :              *)
(* <a href ...>|</a><br><a href ...>content</a>   *)
let split_rows_with_vbar tree =
  List.fold_left
    (fun acc row ->
      let lr, bar = scan_row_for_bar row in
      (* lr = 0 -> | xxx, lr = 1 -> xxx |, lr = -1 -> xxx *)
      if bar then
        if lr = 0 then copy_row row lr "bar" :: copy_row row lr "right" :: acc
        else copy_row row lr "left" :: copy_row row lr "bar" :: acc
      else row :: acc)
    [] (List.rev tree)

let get_nb_full_col_in_span cols b s =
  let rec loop i n cols =
    match cols with
    | [] -> n
    | col :: cols ->
        if i < b then loop (i + 1) n cols
        else if i < b + s then
          if col.[0] = 'F' then loop (i + 1) (n + 1) cols
          else loop (i + 1) n cols
        else n
  in
  loop 0 0 cols

(* split trees (Desc) whose first (3) rows are a single cell *)
let split_tree tree twopages sideways split =
  let row1 = List.nth tree 0 in
  let row2 = List.nth tree 1 in
  let row3 = List.nth tree 2 in
  let desc_tree_1, desc_tree_2, desc_tree_3 =
    match (List.length row1, List.length row2, List.length row3) with
    | 1, 1, 1 -> (false, false, true)
    | 1, 1, _ -> (false, true, false)
    | 1, _, _ -> (true, false, false)
    | _ -> (false, false, false)
  in
  nb_rows :=
    if desc_tree_1 then 1
    else if desc_tree_2 then 2
    else if desc_tree_3 then 3
    else 0;
  (* define new_tree (without first three lines *)
  let new_tree =
    if desc_tree_2 || desc_tree_3 then
      if List.length tree < 4 then tree
      else
        let rec copy_tree i new_tree tree =
          match tree with
          | [] -> List.rev new_tree
          | row :: tree ->
              if i < 3 then copy_tree (i + 1) new_tree tree
              else copy_tree (i + 1) (row :: new_tree) tree
        in
        copy_tree 0 [] tree
    else tree
  in
  let cols = find_empty_columns new_tree in
  let nb_cols = List.length cols in

  (* scan from middle to find first empty col *)
  let _col_middle =
    let rec find_empty_col i =
      if i + 1 = List.length cols || (List.nth cols i).[0] = 'E' then i
      else find_empty_col (i + 1)
    in
    find_empty_col (nb_cols / 2)
  in

  let col_middle =
    (nb_cols / 2) - split - if sideways && twopages then nb_cols * 10 / 4 else 0
  in

  (* TODO see if better column *)
  let row_split _c i1 i2 row =
    let rec loop i new_row row =
      match row with
      | [] -> List.rev new_row (* done *)
      | (w, s, ty, te, it, im) :: row when i1 = 0 && i + s <= i2 ->
          (* left part *)
          loop (i + s) ((w, s, ty, te, it, im) :: new_row) row
      | (_w, s, _ty, _te, _it, _im) :: row when i1 = 0 && i > i2 ->
          (* ignore *)
          loop (i + s) new_row row
      | (w, s, ty, te, it, im) :: row when i1 = 0 && i + s > i2 ->
          (* split *)
          loop (i + s) ((w, i2 - i, ty, te, it, im) :: new_row) row
      | (w, s, ty, te, it, im) :: row when i1 <> 0 && i > i1 ->
          (* right part *)
          loop (i + s) ((w, s, ty, te, it, im) :: new_row) row
      | (_w, s, _ty, _te, _it, _im) :: row when i1 <> 0 && i + s <= i1 ->
          (* ignore *)
          loop (i + s) new_row row
      | (w, s, ty, te, it, im) :: row when i1 <> 0 && i + s > i1 ->
          (* split *)
          loop (i + s) ((w, i + s - i1, ty, te, it, im) :: new_row) row
      | (_w, s, _ty, _te, _it, _im) :: _row ->
          Printf.eprintf "Assert: i=%d, i1=%d, i2=%d, s=%d\n" i i1 i2 s;
          assert false
    in
    loop 0 [] row
  in

  let rec tree_split i i1 i2 new_tree tree =
    match tree with
    | [] -> List.rev new_tree
    | row :: tree ->
        tree_split (i + 1) i1 i2 (row_split i i1 i2 row :: new_tree) tree
  in

  let tree_left = tree_split 0 0 col_middle [] new_tree in
  let tree_right = tree_split 0 (col_middle + 1) (nb_cols - 1) [] new_tree in

  (* redefine new first rows *)
  let row_left row =
    match row with
    | [ (w, _s, ty, te, it, im) ] ->
        [ (1, 2, "E", "", "", ""); (w, col_middle - 2, ty, te, it, im) ]
    | _ -> assert false
  in
  let row_right row =
    match row with
    | [ (w, _s, ty, te, it, im) ] ->
        [
          (w, nb_cols - col_middle - 3, ty, te, it, im); (1, 2, "E", "", "", "");
        ]
    | _ -> assert false
  in
  if desc_tree_2 then
    let row1_left = row_left row1 in
    let row2_left = row_left row2 in
    let row1_right = row_right row1 in
    let row2_right = row_right row2 in
    let tree_left = [ row1_left; row2_left ] @ tree_left in
    let tree_right = [ row1_right; row2_right ] @ tree_right in
    (tree_left, tree_right)
  else if desc_tree_3 then
    let row1_left = row_left row1 in
    let row2_left = row_left row2 in
    let row3_left = row_left row3 in
    let row1_right = row_right row1 in
    let row2_right = row_right row2 in
    let row3_right = row_right row3 in
    let tree_left = [ row1_left; row2_left; row3_left ] @ tree_left in
    let tree_right = [ row1_right; row2_right; row3_right ] @ tree_right in
    (tree_left, tree_right)
  else (tree_left, tree_right)

(* <a href="base?m=IM&p=first_name&n=surname&occ=noc&k=first_name.noc.surname" *)
(* <a href="base?m=IM;s=test/filaname.jpg"> *)
(* ATTENTION assumes .jpg portrait file extension *)
(* TODO query the base for real extension ?? *)
let get_img_name base_name im =
  let _ext_l = [ ".jpg"; ".jpeg"; ".bnp" ] in
  let ext = ".jpg" in
  let where = "images" in
  (* or src *)
  let href_attrl = Hutil.split_href im in
  let k = Hutil.get_href_attr "k" href_attrl in
  let name =
    Format.sprintf "%s"
      (String.concat Filename.dir_sep [ "."; where; base_name; k ^ ext ])
  in
  Sutil.replace_str name "\\_{}" "_"

(*
  goal: split crammed rows in two
       |         |           |
   ----------    |      ----------
  |          |   |     |          |
   ----------    |      ----------
           --------------
          |              |
           --------------
- for each non empty column, add 2 extra cols (left and right)
- for col 1 and n add an extra col
- give to these cols the width txtw / nb_f_col / 3
- expand full colums to the right and left
- recompute colspan ??
*)

let expand_hrl_cells tree =
  let rec expand row new_row =
    match row with
    | (w1, s1, ty1, te1, it1, im1) :: row -> (
        match ty1 with
        | "Hl" when s1 > 1 ->
            let elts =
              if s1 / 2 * 2 = s1 then
                let rec loop acc s =
                  if s = 0 then acc
                  else if s <= s1 / 2 then
                    loop ([ (w1, 1, "E", "", "", "") ] @ acc) (s - 1)
                  else loop ([ (w1, 1, "Hc", "", "", "") ] @ acc) (s - 1)
                in
                loop [] s1
              else
                let rec loop acc s =
                  if s = 0 then acc
                  else if s < s1 / 2 then
                    loop ([ (w1, 1, "E", "", "", "") ] @ acc) (s - 1)
                  else if s = s1 / 2 then
                    loop ([ (w1, 1, "Hl", "", "", "") ] @ acc) (s - 1)
                  else loop ([ (w1, 1, "Hc", "", "", "") ] @ acc) (s - 1)
                in
                loop [] s1
            in
            expand row (elts @ new_row)
        | "Hr" when s1 > 1 ->
            let elts =
              if s1 / 2 * 2 = s1 then
                let rec loop acc s =
                  if s = 0 then acc
                  else if s <= s1 / 2 then
                    loop ([ (w1, 1, "Hc", "", "", "") ] @ acc) (s - 1)
                  else loop ([ (w1, 1, "E", "", "", "") ] @ acc) (s - 1)
                in
                loop [] s1
              else
                let rec loop acc s =
                  if s = 0 then acc
                  else if s < s1 / 2 then
                    loop ([ (w1, 1, "Hc", "", "", "") ] @ acc) (s - 1)
                  else if s = s1 / 2 then
                    loop ([ (w1, 1, "Hr", "", "", "") ] @ acc) (s - 1)
                  else loop ([ (w1, 1, "E", "", "", "") ] @ acc) (s - 1)
                in
                loop [] s1
            in
            expand row (elts @ new_row)
        | _ -> expand row ([ (w1, s1, ty1, te1, it1, im1) ] @ new_row))
    | _ -> List.rev (List.rev row @ new_row)
  in
  let tree =
    let rec loop tree new_tree =
      match tree with
      | [] -> new_tree
      | row :: tree -> loop tree (expand row [] :: new_tree)
    in
    loop tree []
  in
  List.rev tree

let expand_end_cells row =
  let row =
    match row with
    | (w1, s1, ty1, te1, it1, im1) :: (_, s2, ty2, _, _, _) :: row
      when ty2 = "E" ->
        (w1, s1 + s2, ty1, te1, it1, im1) :: row
    | _ -> row
  in
  let row = List.rev row in
  let row =
    match row with
    | (w1, s1, ty1, te1, it1, im1) :: (_, s2, ty2, _, _, _) :: row
      when ty2 = "E" ->
        (w1, s1 + s2, ty1, te1, it1, im1) :: row
    | _ -> row
  in
  List.rev row

let expand_cells tree =
  let rec expand row new_row =
    match row with
    | (w1, s1, ty1, te1, it1, im1)
      :: (w2, s2, ty2, te2, it2, im2)
      :: (w3, s3, ty3, te3, it3, im3)
      :: row -> (
        match (ty1, ty2, ty3) with
        | ty1, ty2, ty3 when ty1 = "E" && ty3 = "E" && s1 = 1 && s3 = 1 ->
            expand row ([ (w2, s2 + 2, ty2, te2, it2, im2) ] @ new_row)
        | ty1, ty2, ty3 when ty1 = "E" && ty3 = "E" && s3 = 1 ->
            expand row
              ([
                 (w1, s1 - 1, ty1, te1, it1, im1);
                 (w2, s2 + 2, ty2, te2, it2, im2);
               ]
              @ new_row)
        | ty1, ty2, ty3 when ty1 = "E" && ty3 = "E" && s1 = 1 ->
            expand row
              ([
                 (w3, s3 - 1, ty3, te3, it3, im3);
                 (w2, s2 + 2, ty2, te2, it2, im2);
               ]
              @ new_row)
        | ty1, ty2, ty3 when ty1 = "E" && ty3 = "E" ->
            expand
              ([ (w3, s3 - 1, ty3, te3, it3, im3) ] @ row)
              ([
                 (w2, s2 + 2, ty2, te2, it2, im2);
                 (w1, s1 - 1, ty1, te1, it1, im1);
               ]
              @ new_row)
        | ty1, ty2, ty3 ->
            expand
              ([ (w2, s2, ty2, te2, it2, im2); (w3, s3, ty3, te3, it3, im3) ]
              @ row)
              ([ (w1, s1, ty1, te1, it1, im1) ] @ new_row))
    | _ -> List.rev (List.rev row @ new_row)
  in
  let tree =
    let rec loop tree new_tree =
      match tree with
      | [] -> new_tree
      | row :: tree ->
          let new_row = expand_end_cells (expand row []) in
          loop tree (new_row :: new_tree)
    in
    loop tree []
  in
  List.rev tree

let merge_cells tree =
  let merge_cell cell new_row =
    if List.length new_row > 0 then
      let first_cell = List.nth new_row 0 in
      match (cell, first_cell) with
      | (_, s1, ty1, _, _, _), (_, s2, ty2, _, _, _)
        when ty1 = ty2 && (ty1 = "E" || ty1 = "Hc") ->
          (0, s1 + s2, ty1, "", "", "") :: List.tl new_row
      | _, _ -> cell :: new_row
    else cell :: new_row
  in
  let rec merge row new_row =
    match row with
    | [] -> List.rev new_row
    | cell :: row -> merge row (merge_cell cell new_row)
  in
  let rec loop tree new_tree =
    match tree with
    | [] -> List.rev new_tree
    | row :: tree -> loop tree (merge row [] :: new_tree)
  in
  loop tree []

let double_each_cell tree =
  let rec scan_tree tree new_tree =
    match tree with
    | [] -> List.rev new_tree
    | row :: tree ->
        let new_row =
          let rec scan_row row new_row =
            match row with
            | [] -> List.rev new_row
            | (a, s, typ, c, d, e) :: row when typ = "Hr" ->
                scan_row row
                  ((a, s, "Hr", c, d, e) :: (a, s, "E", c, d, e) :: new_row)
            | (a, s, typ, c, d, e) :: row when typ = "Hl" ->
                scan_row row
                  ((a, s, "E", c, d, e) :: (a, s, "Hl", c, d, e) :: new_row)
            | (a, s, typ, c, d, e) :: row ->
                scan_row row ((a, s * 2, typ, c, d, e) :: new_row)
          in
          scan_row row []
        in
        scan_tree tree (new_row :: new_tree)
  in
  scan_tree tree []

let flip_tree_h tree =
  let rec flip row new_row =
    match row with [] -> new_row | cell :: row -> flip row (cell :: new_row)
  in
  let rec loop tree new_tree =
    match tree with
    | [] -> List.rev new_tree
    | row :: tree -> loop tree (flip row [] :: new_tree)
  in
  loop tree []

let print_tree base_name tree treemode textwidth textheight _margin debug
    fontsize sideways imgwidth twopages split double =
  let i, w, w0, ok = test_tree_width tree in
  if not ok then (
    Printf.eprintf "Unbalanced tree, row %d w=%d, w0=%d\n" i w w0;
    exit 1);
  let tree = flip_tree_h tree in (* TODO fix the calling side *)
  (*let tree = split_rows_with_vbar tree in*)
  let tree = if double then double_each_cell tree else tree in
  let tree = expand_cells tree in
  let tree = merge_cells tree in
  (*let tree = expand_hrl_cells tree in*)
  let cols = find_empty_columns tree in
  Printf.eprintf "Number of columns: %d\n" (List.length cols);
  let non_empty_col_nbr =
    List.fold_left (fun a col -> if col.[0] = 'F' then a + 1 else a) 0 cols
  in
  let tabular_env =
    (* TODO fond right number of columns *)
    let rec loop s i = if i = 0 then s ^ "c" else loop (s ^ "c") (i - 1) in
    loop "" 255
  in
  let tabular_env = tabular_env ^ tabular_env in
  let cell_wid =
    (if sideways then textheight *. if twopages then 2.0 else 1.0
    else textwidth *. if twopages then 2.0 else 1.0)
    /. Float.of_int non_empty_col_nbr
  in
  let half_cell_wid = cell_wid /. 2.0 in

  (* on top of tabular, one can use tables
     \begin{table}[h!]
     \centering
     \rotatebox{90}{
       \begin{tabular}{||c c c c||}
         ......
       \end{tabular}
     }
     \caption{Table to test captions and labels.}
     \label{table:1}
     \end{table}
  *)
  let print_tree_mode_1 tree page =
    let tabular_b =
      Format.sprintf "%s\n\\begin{tabular}{%s}\n"
        (if sideways then "\\begin{sideways}" else "")
        tabular_env
    in
    let tabular_e =
      Format.sprintf "\\end{tabular}\n%s"
        (if sideways then "\\end{sideways}\n" else "")
    in

    row_nb := 0;
    tabular_b
    ^ List.fold_left
        (fun acc1 row ->
          incr row_nb;
          let _, row_str =
            List.fold_left
              (fun (col, acc2) (_, s, ty, te, it, im) ->
                let colspan_b =
                  if s > 1 then Format.sprintf "\\multicolumn{%d}{c}{" s else ""
                in
                let colspan_e = if s > 1 then "}" else "" in
                (* compute new_wid taking into account empty columns *)
                let nb_full_col = get_nb_full_col_in_span cols col s in
                let new_wid = cell_wid *. Float.of_int nb_full_col in

                (* for testing purposes, add \\fbox{ to minipage_b and } to minipage_e *)
                let fbox_b = if debug = 1 then "\\fbox{" else "" in
                let fbox_e = if debug = 1 then "}" else "" in
                let minipage_b =
                  Format.sprintf "%s\\begin{minipage}{%1.2fcm}" fbox_b new_wid
                in
                let minipage_e = Format.sprintf "\\end{minipage}%s" fbox_e in
                let font_b =
                  if fontsize = "" then "" else "\\" ^ fontsize ^ "{"
                in
                let font_e = if fontsize = "" then "" else "}" in
                (* parbox width and multicolums clash *)
                let cell_str =
                  Format.sprintf "%s%s" colspan_b minipage_b
                  (* begin of cell *)
                  ^ (match ty with
                    | "Te" | "It" -> (
                        let te =
                          Sutil.replace '\n' ' ' te |> Sutil.suppress_leading_sp
                          |> Sutil.clean_double_back_slash_2
                          |> Sutil.clean_leading_double_back_slash
                          |> Sutil.clean_item
                        in
                        let it =
                          Sutil.replace '\n' ' ' it |> Sutil.suppress_leading_sp
                          |> Sutil.clean_double_back_slash_2
                          |> Sutil.clean_leading_double_back_slash
                          |> Sutil.clean_item
                        in
                        match (te, it) with
                        | "", it when it <> "" ->
                            "\\begin{center}" ^ font_b ^ it ^ font_e
                            ^ "\\end{center}"
                        | te, "" when te <> "" ->
                            "\\begin{center}" ^ font_b ^ te ^ font_e
                            ^ "\\end{center}"
                        | te, it when te <> "" && it <> "" ->
                            "\\begin{center}" ^ font_b ^ te ^ "\\\\" ^ it
                            ^ font_e ^ "\\end{center}"
                        | "", "" -> ""
                        | _, _ ->
                            "\\begin{center}" ^ font_b ^ te ^ it ^ font_e
                            ^ "\\end{center}")
                    | "Hl" ->
                        Format.sprintf
                          "\\begin{flushleft}\\rule{%1.2fcm}{%s}\\end{flushleft}"
                          half_cell_wid rule_thickns
                    | "Hr" ->
                        Format.sprintf
                          "\\begin{flushright}\\rule{%1.2fcm}{%s}\\end{flushright}"
                          half_cell_wid rule_thickns
                    | "Hc" ->
                        Format.sprintf
                          "\\begin{center}\\rule{%1.2fcm}{%s}\\end{center}"
                          new_wid rule_thickns
                    | "Vr1" ->
                        Format.sprintf
                          "\\begin{center}\\rule{%s}{%s}\\end{center}"
                          rule_thickns "0.5cm"
                    | "Vr2" ->
                        Format.sprintf
                          "\\begin{center}\\rule{%s}{%s}\\end{center}"
                          rule_thickns "0.5cm"
                    | "E" -> ""
                    | "Im" ->
                        Format.sprintf
                          {|\\begin{center}
                          \\includegraphics[width=%1.2fcm]{%s}
                          \\end{center}|}
                          imgwidth
                          (get_img_name base_name im)
                    | _ -> "??")
                  ^ Format.sprintf "%s%s" minipage_e colspan_e
                  (* end of cell *)
                in
                (col + s, acc2 ^ cell_str ^ " &\n"))
              (0, "") row
          in
          (* somewhat of a hack to ling the two half trees *)
          let row_str =
            if twopages && page = "left" && !row_nb = !nb_rows + 1 then
              row_str ^ "> >"
            else row_str
          in
          let row_str =
            if twopages && page = "right" && !row_nb = !nb_rows + 1 then
              "" ^ row_str
            else row_str
          in
          (* Printf.eprintf "Row string: %s\n" row_str;*)
          acc1 ^ row_str ^ "\\\\\n")
        "" tree
    ^ tabular_e
  in

  let print_tree_mode_0 tree =
    let tree, _n =
      List.fold_left
        (fun (acc1, r) row ->
          let str =
            List.fold_left
              (fun acc2 (_, s, ty, te, it, im) ->
                let cell =
                  (match ty with
                  | "Te" -> "Te " ^ Sutil.clean_double_back_slash te
                  | "It" -> "It " ^ Sutil.clean_double_back_slash it
                  | "Hl" -> "Hr " ^ "-l"
                  | "Hr" -> "Hr " ^ "r-"
                  | "Hc" -> "Hr " ^ "--"
                  | "Vr1" -> "Vr1 " ^ "|"
                  | "Vr2" -> "Vr2 " ^ "|"
                  | "E" -> "E" ^ ""
                  | "Im" -> "Im " ^ im
                  | _ -> "x")
                  ^ if s > 1 then Format.sprintf "(%d)" s else ""
                in
                acc2 ^ "[" ^ cell ^ "] ")
              "" row
          in
          ( acc1 ^ Format.sprintf "Row %d: (%d) %s\\\\\n" r (List.length row) str,
            r + 1 ))
        ("", 1) tree
    in
    Format.sprintf "Interim print (%d)\\\\\n %s\n" (String.length tree) tree
  in
  if twopages then
    let tree_left, tree_right = split_tree tree twopages sideways split in
    match treemode with
    | 0 ->
        print_tree_mode_0 tree_left
        ^ "\\newpage\n"
        ^ print_tree_mode_0 tree_right
    | 1 ->
        print_tree_mode_1 tree_left "left"
        ^ "\\newpage\n"
        ^ print_tree_mode_1 tree_right "right"
    | n -> Printf.sprintf "Error: bad tree mode %d\n" n
  else
    match treemode with
    | 0 -> print_tree_mode_0 tree
    | 1 -> print_tree_mode_1 tree ""
    | n -> Printf.sprintf "Error: bad tree mode %d\n" n
