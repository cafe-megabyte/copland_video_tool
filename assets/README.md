# Copland Theme

`copland-theme.m4a` was converted once from the supplied `Copland Theme.aiff`:

```sh
afconvert -f m4af -d aac -b 256000 -q 127 -s 0 "Copland Theme.aiff" copland-theme.m4a
```

AAC-LC, 256 kbit/s CBR, stereo, 44,100 Hz. No resampling, gain adjustment or
trimming was applied. The original AIFF stays outside the project.

The file contains 780 AAC packets: 795,756 valid samples, 2,112 priming samples
and 852 remainder samples. The valid duration is 18.044353741 seconds. The first
piano attack is marked at 0.878 seconds in the decoded M4A and suggests the image
reveal. The final accent onset is marked at 14.30 seconds from the source
waveform. These figures document the original asset, rather than configure the
programs. Exports preserve the AAC packet bytes.

To exchange the soundtrack, replace `copland-theme.m4a` with an AAC-LC M4A
(mono or stereo, with gapless sample metadata) and set the two audible cue times
in `core/soundtrack.h`: `COPLAND_SOUND_REVEAL_START` and
`COPLAND_SOUND_REVEAL_END`. Run `make` to rebuild both programs. The build reads
the sample rate and valid sample count on every invocation and derives the
audio end automatically, excluding encoder priming and remainder samples.
No duration, packet count or sample rate needs to be maintained by hand. The
suggested start can be overridden with CLI `--blank` or the web lead-in field;
the full-image cue and audio end remain fixed. CLI `--hold` and the web final-hold
field can extend the full image beyond audio end with a silent tail. Shorter
holds still preserve the complete audio.
