# Offline recipes use only macOS system tools and Apple Command Line Tools.
.PHONY: all cli web check serve clean rebuild-toolchain
.NOTPARALLEL:
all cli web check serve clean rebuild-toolchain:
	@/bin/sh build-support/scripts/build.sh $@
