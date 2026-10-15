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
./build/copland_video_tool Mac.png --sound --fps 30
./build/copland_video_tool Mac.png --no-sound --fps 30
./build/copland_video_tool --help
```

Without an output argument, the MP4 is saved next to the image with the same base
name. A second positional output path is also supported. Sound is enabled by
default at 60 fps. Specifying `--duration` or `--keyframes` automatically selects
silent mode and prints the triggering option(s) to standard error, regardless
of argument order. `--blank`, `--hold`, FPS and image settings keep sound enabled.
Use `--no-sound` to explicitly choose silent mode. Explicit `--sound` conflicts
with `--duration`, `--keyframes` or `--no-sound` and exits with code 2.

Silent defaults are a 9-second reveal, 60 fps, a 0.1-second lead-in and a 1-second
final hold. The reveal explicitly includes its final frame: these silent defaults
produce 607 frames and a duration of 10.116667 seconds.

`--easing linear` has a geometric finish with smooth blending. `geometric`,
`slow-then-fast` and `fast-then-slow` are also available. Keyframes replace duration
and easing and use integer tile sizes. Regions are specified as `full`, `auto`
or `x0,y0,x1,y1`. All existing CLI arguments are preserved; AVFoundation continues
to produce H.264/MP4.

Sound mode embeds the bundled Copland Theme without re-encoding its AAC packets.
The sound starts at zero; by default the image waits for the first piano attack at
0.878 seconds (rounded to the nearest frame) before the reveal begins. The full
image appears on the final accent at 14.30 seconds (rounded to the nearest
frame), then stays at least until the measured audio end. The final video sample is
shortened as needed. `--blank SECONDS` overrides the suggested image start without
moving the full-image cue or audio end, in either argument order. It must leave
at least one frame interval for the reveal before the cue. `--hold SECONDS` sets
the total final-image hold from the cue: longer values extend the video with a
silent tail; shorter values still preserve the complete audio. With no explicit
hold, the video ends with the audio. Explicit `--duration` and `--keyframes`
are errors with `--sound`, even when their values equal the defaults. Frame rate
(at least 1 fps), easing, tile size, region and background remain configurable.
The M4A is embedded in the executable; it works from any directory without
additional runtime files.

Sound mode analyzes the prepared image and skips only the initially invisible
part of the selected raster/easing sequence. A rendered RGB channel must differ
from the background by at least 8/255 to count as visible. The first such state
is placed at the configured image start; the remaining portion of the original
curve is stretched to the fixed full-image cue. The centre-sampled renderer,
requested FPS, frame count, lead-in, audio and final hold are unchanged. Later
invisible grids are not removed. Already-visible starts and images below the
contrast threshold are unchanged. If low FPS or a late lead-in skips every
visible intermediate grid, the analysis finds one between the original frames.
CLI, web preview and web export use the same C analysis after applying the
selected region and background. Silent mode does not apply this adjustment.

To replace the soundtrack, replace `assets/copland-theme.m4a` with an AAC-LC M4A
and adjust only `COPLAND_SOUND_REVEAL_START` and `COPLAND_SOUND_REVEAL_END` in
`core/soundtrack.h` (suggested image start and fixed full-image cue, in seconds
from the audible start), then run `make`.
Every build measures the valid audio samples and sample rate, including builds
that reuse cached products. AAC priming and end padding are excluded. The
generated `build/internal/generated/soundtrack-audio.h` supplies the same exact
audio end to the CLI and WASM; do not edit it. All frame counts, reveal durations,
final holds and UI timing displays are derived from these values. Audio or cue
changes invalidate both product caches and the versioned offline web package.

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

Image import does not wait for audio playback readiness. The preview player is
created and started directly by the Play button, so deferred media preloading
cannot block image import. Encoder support checks and test encodes each time out
after 5 seconds; an unresponsive encoder is closed and skipped, leaving the image
preview available. Image decoding times out after 30 seconds and worker requests
outside export after 60 seconds. A failed or unresponsive worker is terminated;
choosing the image again or changing settings creates a new worker and reloads
the image. A full app restart is not required. These limits apply while browser
JavaScript is running; suspended pages handle expired timers when resumed.

"With sound" is checked by default and enables the same theme in the preview
and exported MP4. A saved sound selection, including an explicit silent choice,
takes precedence on restart. Audio is
the preview's playback clock, including pause, seeking and restart. The suggested
lead-in is editable and saved separately from the silent-mode lead-in. Changing
it adjusts the reveal duration while keeping the full-image cue and audio end
fixed. The final hold is also editable and saved separately. It counts from the
full-image cue and holds at least to audio end; longer values extend the video
and preview with a silent tail. Duration and keyframes are locked while enabled. Disabling sound
restores the previous manual settings and format preference. Reset enables
sound and clears the custom sound lead-in and final hold. The M4A is included in the complete offline package.

MP4/H.264 is preferred. WebM/VP8 is also available. On every image import, the
worker checks the encoders with the actual padded video size, current frame rate
and a test encode. If the size is unsupported, it tries smaller sizes and refines
the largest working size to whole pixels while preserving the aspect ratio.
Sound mode checks MP4 only. The search takes at most 25 seconds, including stalled
codec checks. If no working size is found, the image keeps its memory-limited
preview size. Changing settings also rechecks the encoder at the loaded size;
reopening the image repeats the size search with the new settings.
Processing runs in a worker using
WebCodecs and explicit timestamps. Slow devices take longer to process but do not
skip scheduled frames. Small custom container writers package a single silent
video track, plus the original AAC track when sound is enabled. Sound exports
use MP4 only; WebM remains available for silent exports. AAC priming and padding
are excluded from playback without altering the compressed packets. Compressed
colours and file sizes may differ from the CLI output.

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

The web app automatically reduces images larger than 4096 pixels per side or
8,847,360 pixels in total to fit both limits, preserving their aspect ratio with
whole-pixel rounding. It then reduces the size further if required by the
browser's video encoder at the selected frame rate and sound setting. Images
already supported at their memory-limited size remain unchanged. The image info
shows the original and reduced sizes. Regions and pixel sizes refer to the
reduced image; the original file is unchanged. Resizing uses the browser's
high-quality image smoothing, draws directly from the original decoded image at
the final supported size, and preserves transparency. The browser still needs
to decode the source image, so exceptionally large files can exhaust device memory
before resizing. The native CLI does not impose these fixed image limits or resize
images automatically. UHD (3840 × 2160) and DCI 4K (4096 × 2160) images remain
at their original resolution, including portrait orientations, for 4K video
output when the device's video encoder supports it.

These web limits bound processing memory and rendering time: the WASM image
buffers use approximately 20 bytes per pixel (168.75 MiB at the pixel limit), in
addition to browser image, canvas and encoder memory. The side limit also keeps
output sizes within a more widely supported range for video encoders. Encoders
may impose tighter limits, which the app fits to on each image import. Other web
limits are 1–120 fps, 18,000 frames, 10 minutes of total video
and 512 MB of compressed output. Odd image dimensions are padded to even
dimensions using the background colour.

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
- Sound timelines and all native/WASM frames at 1, 24, 29.97, 30, 60 and 120 fps,
  including the suggested piano onset, zero lead-in and custom lead-in.
- Automatic visible starts against independently rendered reference frames in
  134 configurations, including transparent centres, contrast thresholds,
  smooth grids, all easing modes, regions, backgrounds and repeated preparation;
  native/WASM frame hashes and decoded CLI starts/timestamps are checked.
- Both MP4 paths preserve the AAC packets and all 795,756 decoded audio samples,
  including correct priming, remainder, start time and exact movie duration.
- Custom CLI sound lead-ins in either argument order, invalid lead-ins and
  conflicts with the remaining fixed sound settings.
- Sound enabled by default, automatic silent mode with the triggering options,
  explicit `--no-sound`, and conflicting sound flags in either order.
- Adjustable sound holds, unchanged audio samples and audible presentation interval,
  extended video duration and full final image during the silent tail.
- Preview clock synchronization, transition to the silent tail and seeking/resume.
- JavaScriptCore syntax checks of every JavaScript file.
- EN/DE language selection, complete UI/error translations and app names.
- Image import sizing at side and pixel limits, aspect ratio and unchanged small images.
- Dynamic encoder sizing, padded dimensions, frame rates, MP4 with sound,
  failures during test encoding, fresh checks per image and unchanged preview
  size when no encoder is available.
- Import recovery with stalled encoder checks/flushes, stalled image decoding,
  late bitmap cleanup, silent worker loss, retrying the same image without a
  reload, deferred audio preloading and preview without encoders. These checks
  inject failures with simulated time; they do not reproduce a physical device's
  browser or operating-system failure.

The target also creates a browser test page at
`build/internal/tests/browser/index.html`. To run it, start the built test server
with `build/internal/host-tools/server build 8082` and open
`http://localhost:8082/internal/tests/browser/`. The page checks both encoders and
writers through actual browser playback, seeking, first/last frames, odd
dimensions, keyframes and 29.97 fps. All test results and videos are stored under
`build/internal/tests/`.

The companion `build/internal/tests/browser/sound-ui.html` checks the actual web
interface for the suggested start, editable lead-ins and final holds, silent-tail
preview and seeking/pause/end, validation, independent silent/sound settings,
reload and reset.

The companion `build/internal/tests/browser/image-import.html` checks real PNG
decoding and resizing, transparency, WASM rendering and actual app imports,
including the resize notice and region coordinates. It also verifies UHD and DCI
4K MP4 export at 30 and 60 fps through actual video decoding on the test device.

On 3 October 2026, the isolated build, automated checks and WebKit browser export
were tested on this Apple Silicon Mac using Apple Clang 21 from Xcode. Restarting,
MP4 and WebM export with the server stopped, and cancellation were also tested.
A separate machine with only CLT installed, an Intel build host and physical
iPhone/iPad/Android devices were unavailable; these platforms have not yet passed
acceptance testing.

On 13 October 2026, the sound mode passed the automated native/WASM and audio
checks on this Mac, plus WebKit playback and decoding at 1, 24, 29.97, 30 and
120 fps. The web interface was also checked for setting restoration, persisted
sound selection, reset, preview pause/restart, cancellation, explicit offline
update activation and a complete offline restart/import/export with the server
stopped. Chromium was not available for this acceptance run.

On 14 October 2026, automatic image reduction passed real PNG import,
transparency, region and WASM checks on this Mac. UHD (3840 × 2160)
and DCI 4K (4096 × 2160) remained at their original resolutions and passed
WebKit MP4 export and decoded-frame checks at 30 and 60 fps. These 4K checks
used short silent clips; physical mobile devices were not tested.

The shared implementation is in [core/](core/), the native CLI is in
[macos/main.m](macos/main.m), and the offline build recipes are in
[build-support/scripts/](build-support/scripts/). Make targets neither invoke Git
nor modify its metadata.
