# Copland Theme

`copland-theme.m4a` was converted once from the supplied `Copland Theme.aiff`:

```sh
afconvert -f m4af -d aac -b 256000 -q 127 -s 0 "Copland Theme.aiff" copland-theme.m4a
```

AAC-LC, 256 kbit/s CBR, stereo, 44,100 Hz. No resampling, gain adjustment or
trimming was applied. The original AIFF stays outside the project.

The file contains 780 AAC packets: 795,756 valid samples, 2,112 priming samples
and 852 remainder samples. The valid duration is 18.044353741 seconds. The third
piano attack is marked at 2.48 seconds in the decoded M4A and starts the image
reveal. The final accent onset is marked at 14.30 seconds from the source
waveform. Timing constants live in the shared C timeline; exports preserve the
AAC packet bytes.
