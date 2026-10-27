# Changelog

Versions are `MAJOR.MINOR.PATCH`. Each phase bumps the minor number, fixes bump the patch, and the build number goes up on every release build.

## 1.1.0 (build 2) – 28 Oct 2026

- Menu bar garden: a leaf in the menu bar opens a compact, clickable garden that shares the main window's garden, with "Open Garden window" and "Quit". Turn it off with "Show in menu bar" in Settings.
- Gardener's name in Settings: the header and window title read "<Name>'s Garden", or "My Garden" when empty.
- A chevron (key H) hides and shows the bottom tool bar, and remembers the choice.
- Carrots replace coins as the currency, with a drawn carrot icon.
- Drawn tool icons: a hand weeder for Weed and a garden fork for Fork.
- Pick-up watering can: click the can on the lawn (or choose Water) and it follows the pointer and pours where you click or drag. Click its spot again, pick another tool or press Escape to put it down.
- Garden speed in Settings (1x, 2x or 4x): plants, weeds and soil move faster while the clock, weather and seasons stay real.
- "Show in Dock" in Settings: off makes the garden a menu bar only app (the menu bar leaf stays on).
- Cheaper supplies: seeds cost 1 carrot (2 for slow crops), Seasol 1, Fertiliser 2.
- Sundial on the lawn in every theme, reading true local solar time.
- Accurate sun: NOAA solar position from the garden's latitude and longitude; plants and props (chair, sundial, can, hoist, urban props, lantern, cottage) all cast shadows that follow it.
- One watering can: the can on the lawn is the one that pours, drawn above walls and planter boxes.
- Version shown in Settings.

## 1.0.0

Built up over 20–28 October 2026 (dates are local time; the first commit was made on 22 Oct). Each build is one step in the history, newest first. Items marked (unheard) or (unseen) were built and tested but not yet confirmed by the player.

### 1.0.0 (15) – 28 Oct
- Performance plan written for later (hover, backdrop layers, Release build). No behaviour change.

### 1.0.0 (14) – 28 Oct
- Farm, Rural UK and Urban get their own music: kalimba, felt piano and tines, eight pieces each (dawn, day, dusk, night, rain) plus matching garden notes. (unheard in the app)

### 1.0.0 (13) – 28 Oct
- Kalimba, felt piano and tines instruments, plus a spare music box, added to the music renderer. Softened after the first takes sounded sharp.

### 1.0.0 (12) – 27 Oct
- Fix: the debug note run no longer stops the audio engine part-way.

### 1.0.0 (11) – 27 Oct
- New music: a modelled handpan plays curated, mostly quiet pieces with long silences, and single notes when things happen in the garden. Replaces the SoundFont and beat-and-chords score.
- Music setting: Off, Subtle or Often.

### 1.0.0 (10) – 23 Oct
- Music rewritten on a steady beat with chord progressions for each theme and season. (replaced in build 11)

### 1.0.0 (9) – 23 Oct
- Garden music played from a SoundFont. (replaced in build 11)
- Default location is Melbourne.
- Privacy policy added, in the app and as PRIVACY.md: no analytics, nothing tracked. Settings menu built out with an About section.

### 1.0.0 (8) – 22 Oct
- Recorded birdsong, crickets and rain loops replace the synthesised ambience. (unheard)
- Fix: crash when weeding with the rake sound.
- Xcode project regenerated.

### 1.0.0 (7) – 22 Oct
- All garden audio plays through one engine with three volume groups. Settings gets effects and ambient volume sliders. (unheard)

### 1.0.0 (6) – 22 Oct
- Reading shelf gains Meditations, Dhammapada, Enchiridion and Song Celestial.
- Xcode signing and app references updated.

### 1.0.0 (5) – 22 Oct
- Tool sounds were too harsh and sharp, so ambience was made much softer; birds and crickets quieter, rain darker. (unheard)
- Raking and sprinkling now play looping sounds while you drag; the water sound is rebuilt to sound more like water. (unheard)

### 1.0.0 (4) – 22 Oct
- App renamed Dharma Garden.

### 1.0.0 (3) – 22 Oct
- Smaller ripple when pulling weeds and picking flowers.
- The build scheme points at the Garden app.

### 1.0.0 (2) – 22 Oct
- Reading chair on the lawn opens a shelf of 16 public-domain books with a reader that remembers your place.
- Side chores: feed the birds, deadhead, compost.
- "Welcome back" card after a few hours away.
- Full-window scene with floating header and bottom bar.
- Pulled and picked plants hop; scene runs at 60 fps while you act, 30 otherwise, and pauses when the app is inactive.
- Ambient bird, cricket and rain sounds with a settings toggle.

### 1.0.0 (1) – 20–22 Oct
- First release, started 20 Oct as a plan for a cosy, Bluey-style flat-art garden: planting, watering, weeding, picking, forking, Seasol and fertiliser, with live weather, seasons and day and night for the player's town.
- Plants grow in real time over weeks, with small changes visible day to day; self-sowing on a four-month calendar.
- Plants researched for Geelong 3217 (native and non-native flowers and vegetables), then 19 more added on 22 Oct from seed-supplier sowing information (beetroot, broccoli, carrot, alyssum, calendula and others), 30 in all.
- Seeds can be planted anywhere on the soil (replaced the original grid); settings, location (asked once) and daily reminders.
- First-person and backyard views, four bed styles (soil patch, mounds, grid, planter boxes).
- Four themes: Farm, Japanese, Rural UK and Urban, each with scenery, ambient touches and music.
- Visitors to spot, garden book with milestones, achievements and Game Center goals.
- Gentle camera drift. Saves are written safely and an unreadable save is backed up.
