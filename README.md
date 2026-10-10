# Copland Video Tool

Reveal a still image through a shrinking pixel grid sampled at each tile's centre.
The native macOS CLI and the installable web app share the same C core for image
preparation, regions, easing, keyframes, frame sequences and image padding.
Images and videos are processed entirely on your device.

## Build offline

The only required development environment is Apple's Command Line Tools. Install
them once with `xcode-select --install`. An existing Xcode installation can also
provide the Apple tools. The normal build downloads nothing and requires neither
Python nor Node, CMake, Emscripten, FFmpeg or Homebrew.

```sh
make             # CLI and website
make cli         # only build/copland_video_tool
make web         # only build/web/
make check       # both products and automated checks
make serve       # website at http://localhost:8080/; Ctrl-C stops the server
make clean       # remove all generated products and build state
make rebuild-toolchain
```

The native CLI is a universal Intel/Apple Silicon binary for macOS 11 or later.
The linker is built for the build host. `make cli` does not require the web source
archive. `make -j` is supported; product publication is serialized. A second
concurrent build is rejected with a clear message. `clean` never interrupts an
active build.

`make clean` removes generated contents while holding the build lock at
`build/internal/build.lock` until the end. Before deleting each generated tree,
it temporarily denies the creation of files and subdirectories using a macOS ACL.
Finder therefore cannot recreate `.DS_Store` during deletion, while removing
existing entries remains permitted. Each tree is deleted once, without retries.
Symlink targets and file permissions are left untouched. Deletion errors are
reported, and surviving directories have the temporary ACL removed.
Empty build directories are then removed; the `build/` and `build/internal/`
parents may remain if Finder has populated them with metadata again.

The selected Apple SDK and compiler are used directly. An optional
`DEVELOPER_DIR` can point to a CLT directory or Xcode's `Contents/Developer`.
The compiler must support `wasm32-unknown-unknown`. An incompatible compiler
causes a build error; no additional toolchain is downloaded.

The build uses a clean environment and a macOS sandbox that blocks network
access, package manager directories and writes outside `build/`. Extracted
sources, patched working copies, tools, objects, caches, temporary files, test
products and logs are created under `build/internal/`. Only validated final
products are published under `build/`. A failure preserves the last successful
output.

## Small toolchain built from source

`vendor/toolchain/xcc/` contains exactly one unmodified upstream XCC source
archive, approximately 0.5 MB. Its filename and extension are arbitrary;
`.DS_Store` is ignored. The source and patch are documented in
[vendor/SOURCE_ARCHIVES.md](vendor/SOURCE_ARCHIVES.md). Archives are extracted
and patched only under `build/internal/`. Apple Clang compiles our C code;
the locally built `wcc` only links WASM objects. WASI, a second Clang installation
and a C++ runtime are unnecessary.

Caches compare input snapshots byte for byte using `cmp`/`diff`, without hashes.
Archive changes are detected even if filenames, sizes or timestamps remain the
same. Renaming an otherwise identical archive does not invalidate it. Unchanged
subsequent builds retain the existing release identifier. A missing or truncated
runtime file invalidates the website package.

A forcibly terminated process may leave `build/internal/build.lock` behind.
The error message identifies its owner. After verifying that no build is still
running, remove only that lock directory and retry the build. If the final
publication was interrupted, a missing website is restored from
`build/internal/web/previous` before the next build.

## Use the CLI

```sh
./build/copland_video_tool "/path/to/image.png"
./build/copland_video_tool Mac.png --duration 9 --fps 30 --bbox auto
./build/copland_video_tool Mac.png -o video.mp4 --keyframes 0:350,5:100,9:1
./build/copland_video_tool --help
```

Without an output argument, the MP4 is saved next to the image with the same base
name. A second positional output path is also supported. Defaults are a 9-second
reveal, 30 fps, a 0.1-second lead-in and a 1-second final hold. The reveal explicitly
includes its final frame: the defaults produce 304 frames and a duration of
10.133333 seconds.

`--easing linear` has a geometric finish with smooth blending. `geometric`,
`slow-then-fast` and `fast-then-slow` are also available. Keyframes replace duration
and easing and use integer tile sizes. Regions are specified as `full`, `auto`
or `x0,y0,x1,y1`. All existing CLI arguments are preserved; AVFoundation continues
to produce H.264/MP4.

The Python implementation under `python/` and `pixel_reveal.py` remains an optional
reference. Its separately installed packages from `requirements.txt` are outside
the regular build and are not used by any Make target.

## Use and deploy the web app

`make serve` starts a test server bound exclusively to loopback. Copy the complete
website from `build/web/` to a static HTTPS server, either at the domain root or in
a subdirectory. The build does not upload the website automatically.

The interface, including status, error and installation messages, uses German
when the primary browser language is German and English for all other languages.
Project documentation, source comments, build messages and test tools use English.
German text is confined to the web app's translation dictionary in `web/i18n.js`.
The page follows the system appearance: white in light mode, black in dark mode,
with matching controls, borders, text, focus indicators and shadows.
The only source icon is `web/assets/icon.svg`: uneven, solid rectangles on a
transparent background, in a blue visible on both white and black. The build generates PNG sizes for
the header, favicon and Home Screen, plus an ICO file containing multiple sizes.
All variants are generated under `build/internal/` and then published in `build/web/`.
The source SVG uses a 512px canvas and only filled `<rect>` elements. The build
helper parses these with Foundation and renders them with CoreGraphics; no SVG
library or extra tool is required.

The server must serve `.wasm` as `application/wasm` and `.js` as JavaScript.
HTML, `service-worker.js` and `offline-resources.json` should be revalidated for
new versions (`Cache-Control: no-cache`). Release directories under `releases/`
are immutable and may be cached indefinitely. The package also includes previous
release paths so active clients can continue working during updates. Deploy the
entire package.

Choose or drop an image, adjust the settings, play the preview and create the
video. Select a region using coordinates or by dragging in the preview. PNG and
JPEG are the intended inputs; other image formats supported by the browser also
work. Settings are saved locally; images and videos are not permanently archived.
"Reset" restores the defaults.

MP4/H.264 is preferred. WebM/VP8 is also available. The browser checks both encoders
with the actual image size, frame rate and a test encode. If no suitable encoder
is available, the preview remains usable. Processing runs in a worker using
WebCodecs and explicit timestamps. Slow devices take longer to process but do not
skip scheduled frames. Small custom container writers package a single silent
video track. Compressed colours and file sizes may differ from the CLI output.

The initial setup displays "Offline ready" once all files have been successfully
saved locally. Restarting, importing images, previewing and exporting videos then
work without a reachable server. Use "Install" or your browser's Share menu to add
the app to the Home Screen. Updates are prepared separately in full and activated
only by an explicit click. Older caches remain available to active clients;
browser storage management can still delete website data. If that happens,
another online download is required.

Keep the app open during export. Leaving or locking the device cancels an active
export, which can be restarted. "Cancel" immediately terminates the worker and
releases its memory. The completed video can be played, saved and shared when the
browser supports sharing.

Current limits: 4096 pixels per side, 8 megapixels, 1–120 fps, 18,000 frames,
10 minutes of total video and 512 MB of compressed output. Images are not resized
automatically. Encoders may impose tighter limits. Odd image dimensions are padded
to even dimensions using the background colour.

## Checks and verified status

`make check` runs these checks without additional installed tools:

- Native image preparation, including alpha and empty automatically detected regions.
- Default timing, invalid parameters and keyframes.
- WASM imports, versioned API, stack/data boundaries and memory growth.
- Byte comparisons of 144 complete native and WASM frames covering all easing
  modes, keyframes, regions, 29.97 fps and odd dimensions.
- A real CLI MP4 with ten frames, correct dimensions and timestamps.
- The JavaScript MP4 writer with native H.264 samples, decoded independently by
  AVFoundation; frames and timestamps match the source video.
- JavaScriptCore syntax checks of every JavaScript file.
- EN/DE language selection, complete UI/error translations and app names.

The target also creates a browser test page at
`build/internal/tests/browser/index.html`. To run it, start the built test server
with `build/internal/host-tools/server build 8082` and open
`http://localhost:8082/internal/tests/browser/`. The page checks both encoders and
writers through actual browser playback, seeking, first/last frames, odd
dimensions, keyframes and 29.97 fps. All test results and videos are stored under
`build/internal/tests/`.

On 3 October 2026, the isolated build, automated checks and WebKit browser export
were tested on this Apple Silicon Mac using Apple Clang 21 from Xcode. Restarting,
MP4 and WebM export with the server stopped, and cancellation were also tested.
A separate machine with only CLT installed, an Intel build host and physical
iPhone/iPad/Android devices were unavailable; these platforms have not yet passed
acceptance testing.

The shared implementation is in [core/](core/), the native CLI is in
[macos/main.m](macos/main.m), and the offline build recipes are in
[build-support/scripts/](build-support/scripts/). Make targets neither invoke Git
nor modify its metadata.
