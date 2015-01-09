#!/usr/bin/env ocamlscript
Ocaml.packs := ["dockerfile"]
--
open Dockerfile
open Printf

let header (img,tag) =
  comment "Autogenerated by OCaml-Dockerfile scripts" @@
  from ~tag img @@
  maintainer "Anil Madhavapeddy <anil@recoil.org>"

(** RPM rules *)
module RPM = struct

  let base_packages =
    Linux.RPM.dev_packages ()

  let opensuse_repo = function
  | `CentOS7 ->
      let url = "http://download.opensuse.org/repositories/home:ocaml/CentOS_7/home:ocaml.repo" in
      run "curl -o /etc/yum.repos.d/home:ocaml.repo -OL %s" url @@
      run "yum -y upgrade"
  | `CentOS6 ->
      let url = "http://download.opensuse.org/repositories/home:ocaml/CentOS_6/home:ocaml.repo" in
      run "curl -o /etc/yum.repos.d/home:ocaml.repo -OL %s" url @@
      run "yum -y upgrade"

  let system_ocaml =
    Linux.RPM.install "ocaml ocaml-camlp4-devel ocaml-ocamldoc"

  let system_opam = function
  | `CentOS7 -> Linux.RPM.install "opam aspcud"
  | `CentOS6 -> Linux.RPM.install "opam"
end

(** Debian rules *)
module Apt = struct

  let base_packages =
    Linux.Apt.update @@
    Linux.Apt.install "sudo pkg-config git build-essential m4 software-properties-common unzip curl libx11-dev"
 
  let system_ocaml =
    Linux.Apt.install "ocaml ocaml-native-compilers camlp4-extra"

  let system_opam =
    Linux.Apt.install "opam aspcud"

  let opensuse_repo =
    let url = "http://download.opensuse.org/repositories/home:/ocaml/" in
    function
    | `Ubuntu v ->
        let version = match v with `V14_04 -> "14.04" | `V14_10 -> "14.10" in
        let repo = sprintf "deb %s/xUbuntu_%s/ /" url version in
        run "echo %S > /etc/apt/sources.list.d/opam.list" repo @@
        run "curl -OL %s/xUbuntu_%s/Release.key" url version @@
        run "apt-key add - < Release.key" @@
        Linux.Apt.update @@
        run "apt-get -y dist-upgrade"
    | `Debian v ->
        let version = match v with `Stable -> "7.0" | `Testing -> "8.0" in
        let repo = sprintf "deb %s/Debian_%s/ /" url version in
        run "echo %S > /etc/apt/sources.list.d/opam.list" repo @@
        run "curl -OL %s/Debian_%s/Release.key" url version @@
        run "apt-key add - < Release.key" @@
        Linux.Apt.update @@
        run "apt-get -y dist-upgrade"
end

module Opam = struct

  let run_as_opam fmt = Linux.run_as_user "opam" fmt
  let opamhome = "/home/opam"

  let opam_init
    ?(repo="git://github.com/ocaml/opam-repository") 
    ?compiler_version () =
    env ["OPAMYES","1"] @@
    run_as_opam "git clone %s" repo @@
    run_as_opam "opam init -a -y %s/opam-repository" opamhome @@
    maybe (run_as_opam "opam switch -y %s") compiler_version @@
    workdir "%s/opam-repository" opamhome @@
    run_as_opam "opam config exec -- ocaml -version" @@
    run_as_opam "opam --version" @@
    onbuild (run_as_opam "cd %s/opam-repository && git pull && opam update -u -y" opamhome)

  let source_opam =
    run "git clone -b 1.2 git://github.com/ocaml/opam" @@
    Linux.run_sh "cd opam && make cold && make install"

  let install_ext_plugin =
    Linux.run_sh "%s %s %s"
           "git clone git://github.com/avsm/opam-installext &&"
           "cd opam-installext && make &&"
           "make PREFIX=/usr install && cd .. && rm -rf opam-installext"
end

let gen_dockerfiles subdir =
  List.iter (fun (name, docker) ->
    printf "Generating: %s/%s/Dockerfile\n" subdir name;
    (match Sys.command (sprintf "mkdir -p %s/%s" subdir name) with
    | 0 -> () | _ -> raise (Failure (sprintf "mkdir -p %s/%s" subdir name)));
    let fout = open_out (subdir^"/"^name^"/Dockerfile") in
    output_string fout (string_of_t docker))

let _ =
  (* Generate OCaml base images with particular revisions of OCaml and OPAM *)
  let apt_base (base,tag) = 
    header (base,tag) @@
    Apt.(base_packages @@ system_ocaml @@ Linux.Git.init ()) in
  let rpm_base (base,tag) =
    header (base,tag) @@
    RPM.(base_packages @@ system_ocaml @@ Linux.Git.init ()) in
  gen_dockerfiles "docker-ocaml-build" [
     "ubuntu-14.04", apt_base ("ubuntu", "trusty");
     "ubuntu-14.10", apt_base ("ubuntu", "utopic");
     "ubuntu-15.04", apt_base ("ubuntu", "vivid");
     "debian-stable", apt_base ("debian", "stable");
     "debian-testing", apt_base ("debian", "testing");
     "centos-7", rpm_base ("centos", "centos7");
     "centos-6", rpm_base ("centos", "centos6");
     "fedora-21", rpm_base ("fedora", "21");
    ];
  (* Now build the OPAM distributions from the OCaml base *)
  let add_comment ?compiler_version ?(ppa=`None) tag =
    comment "OPAM for %s with %s%s" tag
     (match compiler_version with
      | None -> "system OCaml compiler"
      | Some v -> "local switch of OCaml " ^ v)
     (match ppa with
      | `SUSE -> " and OpenSUSE PPA"
      | `None -> "")
  in
  let apt_opam ?compiler_version ?(ppa=`None) distro =
    let tag =
      match distro with
      |`Ubuntu `V14_04 -> "ubuntu-14.04"
      |`Ubuntu `V14_10 -> "ubuntu-14.10"
      |`Debian `Stable -> "debian-stable"
      |`Debian `Testing -> "debian-testing"
    in
    add_comment ?compiler_version ~ppa tag @@
    header ("avsm/docker-ocaml-build", tag) @@
    Opam.install_ext_plugin @@
    (match ppa with
     | `SUSE -> Apt.opensuse_repo distro @@ Apt.system_opam
     | `None -> Opam.source_opam) @@
    Linux.Apt.add_user ~sudo:true "opam" @@
    Opam.opam_init ?compiler_version ()
  in
  let yum_opam ?compiler_version ?(ppa=`None) distro =
    let tag =
      match distro with 
      |`CentOS6 -> "centos-6"
      |`CentOS7 -> "centos-7"
    in
    add_comment ?compiler_version ~ppa tag @@
    header ("avsm/docker-ocaml-build", tag) @@
    Linux.Git.init () @@
    Opam.install_ext_plugin @@
    (match ppa with
     | `SUSE -> RPM.opensuse_repo distro @@ RPM.system_opam distro
     | `None -> Opam.source_opam) @@
    run "sed -i.bak '/LC_TIME LC_ALL LANGUAGE/aDefaults    env_keep += \"OPAMYES OPAMJOBS OPAMVERBOSE\"' /etc/sudoers" @@
    Linux.RPM.add_user ~sudo:true "opam" @@
    Opam.opam_init ?compiler_version ()
  in
  gen_dockerfiles "docker-opam-build" [
    "ubuntu-14.04-ocaml-4.01.0-system",   apt_opam (`Ubuntu `V14_04);
    "ubuntu-14.04-ocaml-4.01.0-local",    apt_opam ~compiler_version:"4.01.0" (`Ubuntu `V14_04);
    "ubuntu-14.04-ocaml-4.02.1-local",    apt_opam ~compiler_version:"4.02.1" (`Ubuntu `V14_04);
    "ubuntu-14.04-ocaml-4.02.1-system",   apt_opam ~ppa:`SUSE (`Ubuntu `V14_04);
    "debian-stable-ocaml-4.01.0-system",  apt_opam ~compiler_version:"4.01.0" (`Debian `Stable);
    "debian-testing-ocaml-4.01.0-system", apt_opam (`Debian `Testing);
    "debian-stable-ocaml-4.02.1-system",  apt_opam ~ppa:`SUSE (`Debian `Stable);
    "debian-testing-ocaml-4.02.1-local",  apt_opam ~compiler_version:"4.02.1" (`Debian `Testing);
    "centos-6-ocaml-4.02.1-system",       yum_opam ~ppa:`SUSE `CentOS6;
    "centos-7-ocaml-4.02.1-system",       yum_opam ~ppa:`SUSE `CentOS7;
    "centos-7-ocaml-4.01.0-local",        yum_opam ~ppa:`SUSE ~compiler_version:"4.01.0" `CentOS7;
  ];
  (* Now install Core/Async distributions from the OPAM base *)
  let core tag =
    header ("avsm/docker-opam-build", tag) @@
    Opam.run_as_opam "env OPAMYES=1 OPAMJOBS=2 opam installext async_ssl jenga cohttp cryptokit menhir core_bench yojson core_extended"
  in
  gen_dockerfiles "docker-opam-core-build" [
    "ubuntu-14.04-ocaml-4.02.1-core", core "ubuntu-14.04-ocaml-4.02.1-local";
    "debian-stable-ocaml-4.02.1-core", core "debian-stable-ocaml-4.02.1-system";
    "centos-7-ocaml-4.02.1-system", core "centos-7-ocaml-4.02.1-system";
  ];
  (* Generate an archive HTTP server that can be used to serve the archive files from *)
  let opam_archive =
    header ("avsm/docker-opam-build", "ubuntu-14.04-ocaml-4.02.1-system") @@
    Opam.run_as_opam "OPAMYES=1 OPAMJOBS=2 opam installext lwt tls cohttp" @@
    Opam.run_as_opam "cd /home/opam/opam-repository && git pull && opam-admin make" @@
    onbuild (Opam.run_as_opam "cd /home/opam/opam-repository && git pull && opam-admin make")
  in
  gen_dockerfiles "docker-opam-archive" [ "opam-archive", opam_archive ];
  (* For bulk builds, generate a local Dockerfile set so ONBUILD triggers are hit
     and the opam-repository git checkout is refreshed.  This also causes the
     default opam remote to be pointed to a container called opam-archive. *)
  let local_build tag =
    header ("avsm/docker-opam-build", tag) in
  let local_archive =
    header ("avsm/docker-opam-archive", "latest") @@
    Opam.run_as_opam "opam update -u -y" in
  gen_dockerfiles "bulk-build/containers" [
    "local-ubuntu-14.04-ocaml-4.01.0", local_build "ubuntu-14.04-ocaml-4.01.0";
    "local-ubuntu-14.04-ocaml-4.02.1", local_build "ubuntu-14.04-ocaml-4.02.1";
    "local-debian-stable-ocaml-4.01.0", local_build "debian-stable-ocaml-4.01.0";
    "local-debian-stable-ocaml-4.02.1", local_build "debian-stable-ocaml-4.02.1";
    "local-centos-7-ocaml-4.02.1", local_build "centos-7-ocaml-4.02.1";
    "opam-archive", local_archive
  ];
