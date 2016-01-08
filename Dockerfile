FROM ocaml/opam:debian-7_ocaml-4.00.1
RUN sudo -u opam sh -c "opam depext async_ssl jenga cohttp cryptokit menhir core_bench yojson core_extended" && \
  sudo -u opam sh -c "opam install -j 2 -y -v async_ssl jenga cohttp cryptokit menhir core_bench yojson core_extended"