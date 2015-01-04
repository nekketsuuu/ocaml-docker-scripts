.PHONY: all depend sync add-submodules diff clean
all:
	./generate.ml

depend:
	opam install -y ocamlscript dockerfile

sync:
	git submodule foreach 'git add .'
	git submodule foreach 'git commit -m sync -a || true'
	git submodule foreach 'git push || true'
	git commit -a -m 'sync submodules' || true

add-submodules:
	git submodule add git@github.com:avsm/docker-ocaml-build
	git submodule add git@github.com:avsm/docker-opam-build
	git submodule add git@github.com:avsm/docker-opam-core-build
	git submodule add git@github.com:avsm/docker-opam-archive

diff:
	git diff
	git submodule foreach git diff

clean:
	rm -f generate.ml.exe
