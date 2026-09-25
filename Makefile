CC := xcrun clang
CFLAGS := -O3 -std=c11 -Wall -Wextra -fobjc-arc -mmacosx-version-min=11.0
ARCHS := -arch arm64 -arch x86_64
FRAMEWORKS := -framework Foundation -framework CoreGraphics -framework ImageIO -framework CoreVideo -framework CoreMedia -framework AVFoundation

.PHONY: all clean

all: copland_video_tool

copland_video_tool: core/reveal.c core/reveal.h macos/main.m
	$(CC) $(CFLAGS) $(ARCHS) core/reveal.c macos/main.m $(FRAMEWORKS) -lm -o $@

clean:
	rm -f copland_video_tool
