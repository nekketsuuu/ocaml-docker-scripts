#!/usr/bin/env ocamlscript
Ocaml.packs := ["unix"; "str"; "cow"; "cow.syntax"; "cmdliner"]
--

(** All the operating system and OCaml version combinations *)
let targets =
     Sys.readdir "logs"
  |> Array.map (fun b -> if String.length b > 6 then Str.string_after b 6 else b)
  |> Array.map (Str.(split (regexp_string "-ocaml-")))
  |> Array.fold_left (fun a -> function [x;y] -> (x,y)::a |_ -> a) []

(** Concatenate all the packages together to form a sorted unique list *)
let all_packages =
     Sys.readdir "logs"
  |> Array.to_list
  |> List.map (fun d -> Sys.readdir (Printf.sprintf "logs/%s/raw/" d))
  |> List.map Array.to_list
  |> List.flatten
  |> List.filter (fun f -> not (Filename.check_suffix f ".html"))
  |> List.fold_left (fun a b -> if List.mem b a then a else b::a) []
  |> List.sort compare

(** Some helper functions *)
let gen_hashtbl fn =
  let h = Hashtbl.create 1 in
  List.iter (fn h) targets;
  h

let keys h =
  Hashtbl.fold (fun k v a -> if List.mem k a then a else k::a) h []

let rec repeat n x =
  match n with
  | 1 -> x
  | n -> (repeat (n-1) x) @ x

let with_file_input fname fn =
  let fin = open_in fname in
  try
    let r = fn fin in
    close_in fin;
    r
  with exn -> close_in fin; raise exn
let read_file_line fname = with_file_input fname input_line
let read_file fname =
  let fin = open_in fname in
  let b = Buffer.create 128 in
  (try while true do
    Buffer.add_string b (input_line fin);
    Buffer.add_char b '\n'
  done;
  with End_of_file -> ());
  close_in fin;
  Buffer.contents b

(** List of operating system and OCaml version variants *)
let os_hash = gen_hashtbl (fun h (os,ver) -> Hashtbl.add h os ver)
let versions_hash = gen_hashtbl (fun h (os,ver) -> Hashtbl.add h ver os)
let versions = keys versions_hash
let num_versions = List.length versions
let os = keys os_hash
let num_os = List.length os
let opam_repo_rev = read_file_line "opam-repo-rev"
let opam_repo_rev_short = String.sub opam_repo_rev 0 8
let opam_build_date = read_file_line "opam-build-date"

(** Package database *)
let dir ty os ver pkg = Printf.sprintf "logs/local-%s-ocaml-%s/%s/%s" os ver ty pkg
let dirlink os ver pkg = dir "raw" os ver pkg ^ ".html"
let is_ok os ver pkg = Sys.file_exists (dir "ok" os ver pkg)
let is_err os ver pkg = Sys.file_exists (dir "err" os ver pkg)
let package_map pkg fn =
  List.flatten (List.map (fun os -> List.map (fun v -> fn os v pkg) versions) os)
let package_status pkg =
  let num_success =
     List.fold_left (fun a b -> if b then a+1 else a) 0 (package_map pkg is_ok) in
  let num_fails =
     List.fold_left (fun a b -> if b then a+1 else a) 0 (package_map pkg is_err) in
  if num_success > 0 && num_fails = 0 then "fullsuccess" else 
  if num_success > 0 && num_fails > 0 then "somesuccess" else
  if num_success = 0 && num_fails > 0 then "allfail" else
  "notbuilt"
let buildtime os ver pkg =
  let fname = dir "meta" os ver pkg ^ ".buildtime" in
  if Sys.file_exists fname then
    Some (read_file_line fname |> int_of_string)
  else None

(** HTML output functions *)
let html ~title body =
  <:html<<html>
    <head>
     <meta charset="UTF-8" /><link rel="stylesheet" type="text/css" href="theme.css"/>
     <title>$str:title$</title></head>
     <body>$body$</body></html>&>>

let cell_ok os ver pkg =
  <:html<<td class="ok"><a href=$str:dirlink os ver pkg$>✔</a></td>&>>
let cell_err os ver pkg =
  <:html<<td class="err"><a href=$str:dirlink os ver pkg$>✘</a></td>&>>
let cell_unknown os ver pkg = <:html<<td class="unknown">●</td>&>>
let cell_space = <:html<<td></td>&>>

let link_pkgname pkg =
  let fin = Unix.open_process_in (Printf.sprintf "opam show %s -f homepage" pkg) in
  let h = try match input_line fin with "" -> None | h -> Some h with End_of_file -> None in
  ignore(Unix.close_process_in fin);
  match h with
  | None -> <:html<$str:pkg$>>
  | Some h -> <:html<<a href=$str:h$>$str:pkg$</a>&>>
  
let pkg_ents pkg =
  let by_os =
    List.map (fun os ->
      List.map (fun ver ->
        if is_ok os ver pkg then cell_ok os ver pkg
        else if is_err os ver pkg then cell_err os ver pkg
        else cell_unknown os ver pkg
      ) versions
    ) os in
  let by_ver =
    List.map (fun ver ->
      List.map (fun os ->
        if is_ok os ver pkg then cell_ok os ver pkg
        else if is_err os ver pkg then cell_err os ver pkg
        else cell_unknown os ver pkg
      ) os
    ) versions in
  <:html<$list:List.flatten by_os$<td></td>$list:List.flatten by_ver$>>

let results =
   let os_headers cl cs =
     List.map (fun os ->
       <:html<<th class=$str:cl$ colspan=$int:cs$>$str:os$</th>&>>) os in
   let version_headers cl cs =
     List.map (fun v ->
       <:html<<th class=$str:cl$ colspan=$int:cs$>$str:v$</th>&>>) versions in
   let pkg_row pkg =
      let pkg_link = link_pkgname pkg in
      <:html<<tr class="pkgrow">
        <td class=$str:package_status pkg$><b>$pkg_link$</b></td>
        $pkg_ents pkg$
        <td class=$str:package_status pkg$><b>$pkg_link$</b></td>
        </tr>&>> in
   let os_colgroups =
     List.map (fun os ->
       <:html<<colgroup class="results">
         <col span=$int:num_versions$ /></colgroup>&>>) os in
   let ver_colgroups =
     List.map (fun os ->
       <:html<<colgroup class="results">
         <col span=$int:num_os$ /></colgroup>&>>) os in
   <:html<
      <table>
        <colgroup><col class="firstpkg"/></colgroup>
        $list:os_colgroups$
        <colgroup><col class="spacing" /></colgroup>
        $list:ver_colgroups$
        <colgroup><col class="lastpkg"/></colgroup>
        <tr>
          <th class="filler"><b>OPAM Bulk Builds</b></th>
          <th class="sortrow" colspan=$int:num_versions * num_os$>Sort by OS</th>
          <th class="filler"></th>
          <th class="sortrow" colspan=$int:num_versions * num_os$>Sort by Version</th>
          <th class="filler"></th>
        </tr>
        <tr>
          <th class="filler">$str:opam_build_date$</th>
          $list:os_headers "secondrow" num_versions$
          <th class="filler"></th>
          $list:version_headers "secondrow" num_os$
          <th class="filler"></th>
        </tr>
        <tr>
          <th class="filler">
            <a href="https://github.com/ocaml/opam-repository">opam-repository</a> 
            <a href=$str:"https://github.com/ocaml/opam-repository/tree/"^opam_repo_rev$>$str:opam_repo_rev_short$</a>
          </th>
          $list:repeat num_os (version_headers "thirdrow" 1)$
          <th class="filler"></th>
          $list:repeat num_versions (os_headers "thirdrow" 1)$
          <th class="filler"></th></tr>
          $list:List.map pkg_row all_packages$
      </table>
   >>

let process_file fin fn =
    let rec aux acc =
      try
        input_line fin
        |> fn acc
        |> aux
      with End_of_file -> acc
    in aux []

let rewrite_log_as_html os ver pkg =
  let logfile = dir "raw" os ver pkg in
  let ologfile = dirlink os ver pkg in
  let fout = open_out ologfile in
  Printf.eprintf "Generating: %s\n%!" ologfile;
  let fin = open_in logfile in
  let title = Printf.sprintf "Build %s on %s / OCaml %s" pkg os ver in
  let body = List.rev_map (fun b -> <:html<<pre>$str:b$</pre>&>>) (process_file fin (fun a l -> l :: a)) in
  close_in fin;
  let status =
    if is_ok os ver pkg then <:html<<b>Build Status:</b> <span class="buildok">Success</span>&>>
    else if is_err os ver pkg then <:html<<b>Build Status:</b> <span class="buildfail">Failure</span>&>>
    else <:html<<b>Build Status:</b> <span class="buildunknown">Unknown</span>&>> in
  let buildtime =
    let b = match buildtime os ver pkg with Some s -> <:html<$int:s$ seconds>> | None -> <:html<unknown>> in
    <:html<<b>Build Time:</b> $b$>> in
  let actions =
    let f = read_file (dir "meta" os ver pkg ^ ".actions") in
    <:html<<pre>$str:f$</pre>&>> in
  let out = <:html<
    <html><head>
     <meta charset="UTF-8" /><link rel="stylesheet" type="text/css" href="../../../theme.css"/>
     <title>$str:title$</title></head>
     <body><h1>$str:title$</h1>
       <h2>$status$</h2>
       <h2>$buildtime$</h2>
       <ul>
         <li><a href="#bottom">Jump to End of Log</a></li>
         <li><a href="../../../index.html">Return to Index</a></li>
       </ul>
       <hr />
       <h2><b>Build Actions:</b></h2>
       $actions$
       <hr />
       $list:body$
       <a name="bottom"> </a>
       </body></html>&>> in
  Printf.fprintf fout "%s" (Cow.Html.to_string out);
  close_out fout

let generate_logs () = 
  List.iter (fun os ->
    List.iter (fun ver ->
      List.iter (fun pkg ->
        if Sys.file_exists (dir "raw" os ver pkg) then
          rewrite_log_as_html os ver pkg
        else Printf.eprintf "Skipping: %s\n%!" (dir "raw" os ver pkg)
      ) all_packages
    ) versions
  ) os

let generate_index () =
  let b =
    html ~title:"OCaml and OPAM Bulk Build Results" results
    |> Cow.Html.to_string in
  Printf.eprintf "Generating: index.html\n%!";
  let fout = open_out "index.html" in
  Printf.fprintf fout "%s" b;
  close_out fout

open Cmdliner

let run logs =
  generate_index ();
  if logs then generate_logs ()

let cmd =
  let gen_logs =
    let doc = "Generate HTML logfiles." in
    Arg.(value & flag & info ["g";"generate-logs"] ~doc)
  in
  let doc = "Generate HTML documentation for OPAM logs" in
  let man = [
    `S "DESCRIPTION";
    `P "This command generates a static HTML frontend to OPAM logfiles.
        The option will also process the logfiles themselves
        which is quite timeconsuming for large builds.";
    `S "BUGS";
    `P "Report them to <opam-devel@lists.ocaml.org>"; ]
  in
  Term.(pure run $ gen_logs),
  Term.info "generate-opam-html" ~version:"1.0.0" ~doc ~man

let () = match Term.eval cmd with `Error _ -> exit 1 | _ -> exit 0

