# Offline recipes use only macOS system tools and Apple Command Line Tools.
.PHONY: all cli web check serve clean rebuild-toolchain icon-check check-icons
.NOTPARALLEL:
all cli web check serve rebuild-toolchain check-icons:
	@/bin/sh build-support/scripts/build.sh $@

icon-check:
	@/bin/sh build-support/scripts/build.sh icon-check "$(MANDELBROT_WEB)"

clean:
	@for attempt in 1 2 3; do \
		/bin/sh build-support/scripts/build.sh clean; \
	done
