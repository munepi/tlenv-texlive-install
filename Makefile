release_version := $(shell grep "^TEXLIVE_INSTALL_VERSION" bin/texlive-install | cut -d\" -f2)

share/man/man1/%.1: share/man/man1/%.1.adoc bin/texlive-install
	which asciidoctor || gem install asciidoctor
	asciidoctor -b manpage -a version=$(release_version:v%=%) -o $@ $<
