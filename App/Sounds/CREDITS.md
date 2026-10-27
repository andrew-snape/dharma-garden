# Ambient recordings

Seamless loops cut from CC0 (public domain) field recordings by Joseph Sardin, BigSoundBank. Each was trimmed, crossfaded into a loop, levelled to the same loudness and encoded as 96 kbps AAC.

- `ambient-birds.m4a`: Birds in the City #2, https://bigsoundbank.com/birds-in-the-city-2-s3576.html (from 0:05, 80 s)
- `ambient-crickets.m4a`: Campaign at Night #4, https://bigsoundbank.com/campaign-at-night-4-s1880.html (from 3:35, 75 s)
- `ambient-rain.m4a`: Summer Rain on Terrace, https://bigsoundbank.com/summer-rain-on-terrace-s1019.html (from 0:02, 75 s)

# Music

`Music/<theme>-<mood>-<n>.m4a` (20 Japanese handpan pieces; 8 each for Farm kalimba, Rural UK felt piano and Urban electric-piano tines) and `Music/notes/<prefix>-<index>-<soft|medium>.m4a` (18 single notes per instrument; the handpan's prefix is `note`, the others `<instrument>-note`) are generated in-house by the `GardenRender` tool in DharmaGardenCore: modal synthesis of each instrument, a free-time improviser and a synthesised room. No third-party audio or samples are used. Render a theme's pieces with `GardenRender batch --instrument <name>` and its notes with `GardenRender notes --instrument <name> --out App/Sounds/Music/notes --calibrate <dir of that theme's pieces>`.
