# Offline recipes use only macOS system tools and Apple Command Line Tools.
.PHONY: all cli web check serve clean rebuild-toolchain
.NOTPARALLEL:
all cli web check serve rebuild-toolchain:
	@/bin/sh build-support/scripts/build.sh $@

clean:
	@for attempt in 1 2 3; do \
		/bin/sh build-support/scripts/build.sh clean; \
	done
