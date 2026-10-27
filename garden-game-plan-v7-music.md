# Garden music v7: our own handpan, curated pieces, garden notes, lots of silence

Status: Phase 0 passed 2026-10-27. The user prefers the modelled handpan (ModalInstrument, first take, unchanged) over the recorded FreePats CC0 hang, and the sound is locked as is. Phase 1 passed 2026-10-27: Improviser + `GardenRender batch` built; the user heard six excerpts of batch1 (20 pieces, seeds 1–4 per mood, `--start-seed 1 --minutes 4`) and was happy with all of them, so all 20 are the Japanese library. Phase 2 (app wiring) committed (ae84f73, d99ec87). Phase 3 sound approved 2026-10-28 after a softening pass ("yeah thats nicer"): kalimba, felt piano and tines committed as ee99f9c, previews in music-previews/phase3-soft. Next: render each theme's library and wire it into the app. Replaces the generative score (MusicComposer + GeneralUser GS).
Constraint: **everything is made inside Claude Code on this Mac.** No outside music services and no accounts.
Claude writes the code, the Mac renders the audio, the user listens to previews sent in chat and says what's
working and what isn't.

## Why the old music failed

1. **Timbre:** General MIDI SoundFont instruments sound like a SoundFont.
2. **Style:** a steady beat and chord progressions, the opposite of the reference (Malte Marten, solo handpan),
   which has one fixed scale, free time, long ringing decays and lots of silence.
3. **Always on:** even good music grates if it never stops.

## The idea

- **One instrument, modelled properly.** Each theme gets an instrument built by **modal (physical) synthesis**:
  handpan for Japanese, kalimba for Farm, felt piano for Rural UK, Rhodes-like tines for Urban. These are struck
  idiophones made of a few resonant modes, which is exactly what modal synthesis reproduces well. It's nothing like
  the old FM e-piano.
- **Pieces rendered offline and curated (idea 5).** A renderer on the Mac improvises free-time pieces with the
  instrument and renders them at high quality (expensive models are fine offline). The user approves the
  keepers, and **the game only ever plays pieces the user has heard and liked.**
- **Garden notes (idea 4).** The same instrument plays single notes live when things happen in the garden. It's
  literally the same model, so notes and pieces always match in sound and key.
- **Silence (idea 7).** Subtle by default: one piece, then several minutes of just ambience.

## Phase 0: the instrument spike (gate for everything else)

Nothing else gets built until the handpan sounds good to the user.

**0a. Look for free recordings first (30 min, needs the user's OK to download).** Search for CC0 or public-domain
handpan / hang drum one-shot notes (Wikimedia Commons, archive.org, other CC0 sample sites that need no login).
If a clean set of the D Kurd notes exists, real samples beat any model: use them for both pieces and notes.
Show the user the source and licence before downloading anything.

**0b. Otherwise (or as well), the modal handpan.** In `DharmaGardenCore/Instruments/ModalInstrument.swift`:

- Per note, 6–10 modes: fundamental, octave, compound fifth (the handpan's three tuned partials), plus
  weaker untuned shell modes. Each mode is a **pair of slightly detuned resonators**, which gives the slow
  shimmer or beating real handpans have.
- Each mode decays on its own (high modes die fast, the fundamental rings 4–8 s).
- Strike model: a short soft-mallet noise burst through the modes, brightness rising with strength.
- **Sympathetic ring:** striking one note excites the shared modes of the others very slightly. This is a big
  part of the handpan "halo".
- A small amount of body resonance (the "ding" cavity, a low Helmholtz hum around 90–110 Hz).
- Room: a **convolution reverb** from an impulse response we synthesise ourselves (a decaying noise tail with
  early reflections), so it doesn't need downloads.

**Spike deliverables, sent with SendUserFile:**
1. `handpan-notes.wav`: each of the 9 notes, soft then medium.
2. `handpan-60s.wav`: one minute of free-time improvisation.
3. A spectrogram PNG with the note decays, which Claude checks visually against the expected decay shapes.

**Gate:** the user says "yes, that's the sound" or gives notes ("too metallic", "too short", "too clangy"), and we
iterate. Usually 2–4 rounds. If it never gets there, stop and rethink before touching the app.

## Part A: the pieces (idea 5)

### Instruments and scales (all in D)

| Theme | Instrument | Scale |
|---|---|---|
| Japanese (pilot) | handpan | D Kurd: D3 A3 Bb3 C4 D4 E4 F4 G4 A4 |
| Farm | kalimba | D major pentatonic |
| Rural UK | felt piano (modal: hammer + string partials, soft) | D dorian |
| Urban | Rhodes-like tines, very sparse | D dorian |

### The improviser (`DharmaGardenCore/Music/Improviser.swift`, pure and tested)

How a handpan player actually plays, not bars and chords:
- **Phrases** of 3–9 notes with breathing gaps of 2–8 s between them. There's no metre, but notes inside a phrase
  sit on a loose pulse (60–75 bpm, with ±20 ms of human timing).
- Mostly stepwise motion around the ring. Occasional leaps to the ding (D3) for an anchor. Phrases often
  return to D or A.
- Motifs repeat with small variations, so pieces feel intentional rather than random.
- Gentle dynamics, an overall arc (sparse opening, a fuller middle, a sparse ending), 3–5 minutes.
- Mood changes the settings: dawn is sparse and high, day is a little fuller, dusk is lower and slower, night is
  rare and soft, rain is slower and lower.

### The renderer (`tools/music`, a Swift executable target in the package, not shipped)

`swift run GardenRender --theme japanese --mood dawn --seed 42 --minutes 4 --out …`

- It renders through the same `ModalInstrument` at 48 kHz, then convolution reverb, fade-in/out, about -24 LUFS
  loudness, and a gentle 6–7 kHz low-pass. Output is AAC `.m4a`.
- A batch command renders about 20 candidates per theme, plus a contact sheet: a PNG of waveform thumbnails with
  seed and mood.

### Curation loop (inside Claude)

1. Claude renders candidates and does a first cut automatically: rejects pieces with clipping, too-dense passages,
   long dead spots or a repetitive pitch histogram.
2. Claude sends the user about 6 previews at a time (60 s excerpts) with SendUserFile.
3. The user replies "keep 2, 5", "dawn is too busy" and so on. Claude adjusts the improviser's settings and re-renders.
4. Kept seeds are written to `music-library.json`. The final files go to `App/Sounds/Music/<theme>/<mood>-<n>.m4a`.

Target: about 12 kept pieces per theme (2 per mood, plus 2 rain variants). At about 1 MB per minute that's roughly
50 MB per theme. The 31 MB SoundFont is deleted.

## Part B: garden notes (idea 4)

`GardenNotes` (core, pure, tested) maps existing events to at most one note:

| Event | Note |
|---|---|
| `.plant` | low (D3 ding or A3) |
| `.water` / sprinkle | 2–3 rising notes, spread out |
| `.pick` (harvest) | D4 |
| `.spot` (visitor) | a random upper note |
| flower opens (growth stage change) | one upper note, rare |
| rain begins | 3-note falling run, once |

- Notes use the current theme's scale only. Rate limit: 6 s on Subtle, 3 s on Often. A rake drag gives one note.
- Velocity 0.15–0.35, softer at night. Pan comes from the event's screen x position. No same pitch twice in a row.
- Played live by `ModalInstrument` (the same model as the pieces), or by the CC0 samples if 0a finds good ones.
- Live performance budget: at most 6 voices at once, with modes trimmed for real time. Tested to render faster
  than real time in release builds.

## Part C: the scheduler (idea 7)

`MusicDirector` (core, pure, tested): `silent(until:)` → `playing(piece, endsAt:)` → `silent` …

| Setting | Gap after a piece | Notes |
|---|---|---|
| Off | nothing plays | garden notes still follow their own toggle |
| **Subtle (default)** | 6–12 min | at most 1 every 6 s |
| Often | 1–3 min | at most 1 every 3 s |

- The first piece waits 45–90 s after launch. The next piece matches the mood, never repeats the last 3, and uses a
  rain take when it's raining. No piece starts between 22:00 and 06:00 (notes only).
- A theme change fades out over 3 s, then goes silent. Ambience ducks about 3 dB while a piece plays.
- The app plays pieces through an `AVAudioPlayerNode` on the existing `.music` bus in `GardenAudio`.
- Settings: Music (Off / Subtle / Often), Garden notes (on/off), volume (default 0.35). Old `musicEnabled`
  saves map to Off or Subtle.

## What gets deleted

`MusicComposer.swift` and its tests, `App/GardenSampler.swift`, `GeneralUser-GS.sf2` and its licence,
`music-compare/`, and the old music voices in `GardenSynth` (keep whatever the ambient fallback still uses).
The test suite loses about 100 s of offline music renders.

## Phases

| # | What | Who | Gate |
|---|---|---|---|
| 0 | CC0 search (with the user's OK) + modal handpan spike, previews sent | agent + Claude | **User likes the handpan** |
| 1 | Improviser + renderer, curation rounds for Japanese | agent + user listening | 12 Japanese pieces kept |
| 2 | App: `MusicDirector`, `GardenNotes`, live instrument, settings, ducking, delete old code | agent | build + tests, user listens in app |
| 3 | Kalimba, felt piano, tines: instrument spike + curation per theme | agent + user | each instrument approved |
| 4 | Inline Opus read-only review, fix the confirmed findings | Claude | — |

## Agents

**One Sonnet subagent at a time, one per phase, with Claude as project manager.** Claude runs builds and tests,
checks spectrograms, sends previews and relays the user's reactions.

- **Why one:** the phases depend on each other (no improviser before the instrument is approved, no app wiring before
  the library exists). The app changes all touch the same five files, and other sessions edit this folder. The
  bottleneck is the user's listening rounds, not typing speed.
- **Why Sonnet:** DSP (modal resonators, convolution, real-time voice limits) and audio-thread safety are easy to
  get subtly wrong. Haiku is likely to produce something that compiles and sounds bad.
- **Where Haiku fits (optional):** the batch render and auto-reject pass in Phase 1 (run the CLI over 20 seeds,
  tabulate loudness, clipping and density). It's mechanical and easy to verify.
- **Listening rounds stay with Claude, not an agent,** so the user's feedback keeps its context between rounds.

## Risks

- **The modal handpan may not convince.** Mitigated by Phase 0's gate and the CC0 search. Synthesis gets close for
  struck metal. Felt piano is the hardest of the four, so it's last and could be swapped for music box or vibraphone.
- **Claude can't hear.** Quality checks are numeric and visual; taste is the user's. Expect several short listening
  rounds.
- **Bundle size** of about 200 MB for all four themes. Could ship Japanese and render the rest on first use
  (the renderer could live in the app), but that's later.
