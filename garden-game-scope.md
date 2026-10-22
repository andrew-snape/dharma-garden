# Garden Game: Scope (Version 1)

A small, cosy garden game for macOS. You check in once a day to plant seeds, water, pull weeds and pick flowers. Plants grow in real time, and the garden responds to the real weather where you live.

---

## 1. Core Idea

- One small garden plot, viewed from a single fixed scene
- Real time growth: a flower takes a few real days to bloom
- Real local weather affects the garden: rain waters it, heat dries it out, frost can damage tender plants
- Designed for a 2 to 5 minute visit each day, with no penalty harsh enough to make it stressful

---

## 2. Player Actions

| Action | What happens |
|---|---|
| Plant | Choose a seed from your packet and tap an empty bed |
| Water | Tap a plant with the watering can; soil darkens and moisture fills |
| Weed | Tap a weed to pull it out |
| Harvest | Tap a blooming flower to pick it; it goes into your collection |
| Buy seeds | Spend coins earned from harvested flowers on new seed packets |

---

## 3. Growth Rules

**Stages:** Seed, Sprout, Bud, Bloom

**Timing:** Each flower type has its own growth time (roughly 2 to 5 real days to bloom).

**Moisture:**
- Each bed has a moisture level from 0 to 100
- Moisture drops steadily over time (faster on hot or windy days)
- Growth pauses when moisture is below 20
- A plant wilts after about 48 hours fully dry, and dies after about 96 hours
- Wilted plants recover if watered in time

**Weeds:**
- A weed has a small chance of appearing in an empty or planted bed each few hours
- Each weed next to a plant slows its growth slightly
- Weeds never kill plants, they just slow them down

**Offline calculation:**
- No timer runs in the background
- The app saves timestamps and recalculates the whole garden each time it opens, using the weather history since your last visit

---

## 4. Weather Link

**Source:** Open-Meteo (free, no account or API key needed). Hourly history and forecast.

**Location:** Uses Mac location services, or a manually entered town (default: Mount Duneed, VIC).

| Real weather | Effect in game |
|---|---|
| Rain | Refills moisture (more rain, more moisture) |
| Above 30°C | Moisture drains about twice as fast |
| Strong wind | Moisture drains a little faster |
| Below 2°C overnight | Tender flowers may get frost damage (slower growth for a day) |
| Cloud / sun / night | Changes the sky, light and mood of the scene |

---

## 5. Starting Flowers (Version 1)

| Flower | Days to bloom | Notes |
|---|---|---|
| Sunflower | 5 | Loves heat, slower in cold |
| Daisy | 2 | Easy starter flower |
| Lavender | 4 | Tolerates dry spells better |
| Poppy | 3 | Frost tender |

---

## 6. Visual Style: Decision Needed

Two big choices: how realistic the garden looks, and the colour model.

### 6a. Realism Level

| Option | Look | Pros | Cons |
|---|---|---|---|
| **A. Pixel art** | Chunky retro sprites, like Stardew Valley | Charming, easy to animate growth stages, very forgiving | Can feel "gamey"; needs consistent pixel scale |
| **B. Flat illustrated** | Clean shapes, soft shading, like a picture book | Calm, modern, scales well on Retina screens | Needs good shape design to feel alive |
| **C. Soft realistic / painterly** | Watercolour or hand painted textures | Beautiful and relaxing | Hardest to make; each growth stage needs real art |
| **D. Low poly 3D** | Simple 3D garden, gentle camera | Weather lighting looks great | Much bigger build, overkill for Version 1 |

**Recommendation:** B (flat illustrated). It is the quickest to make look polished, weather effects (rain, light changes) layer on easily, and every flower stage can be built from simple shapes in SwiftUI without needing an artist.

### 6b. Colour Model

| Option | Feel | Palette idea |
|---|---|---|
| **1. Natural / earthy** | Calm, grounded, real garden | Soil browns, sage and olive greens, muted flower colours |
| **2. Pastel / cosy** | Soft, gentle, relaxing | Cream, mint, peach, lilac, pale sky blue |
| **3. Bright / saturated** | Cheerful, playful | Strong greens, vivid petals, bold blue sky |
| **4. Time-of-day driven** | Palette shifts with real time and weather | Warm golden mornings, bright midday, dusky purple evenings, grey on rainy days |

**Recommendation:** Option 1 or 2 as the base, combined with Option 4 so the scene tints to match the real time and weather. This makes the weather link feel real without needing realistic art. Flowers stay the brightest thing on screen so they always stand out.

### 6c. Quick Test Before Deciding

Build one bed with one daisy in all four growth stages, in two styles side by side (for example B + Pastel and B + Earthy). Look at it at morning, midday and evening tints, then choose.

---

## 7. Tech

- **App:** SwiftUI, macOS
- **Storage:** SwiftData (saved locally on the Mac)
- **Weather:** Open-Meteo REST API, fetched on launch
- **Location:** CoreLocation, with manual fallback
- **Notifications:** Optional daily reminder (for example "Your daisies are thirsty")
- **Art:** Built in SwiftUI shapes for Version 1, swappable for image assets later

---

## 8. Version 1 Includes

- 4×4 garden grid
- 4 flower types with 4 growth stages each
- Watering, weeding, harvesting
- Real weather effects and sky changes
- Saved progress and offline catch-up
- Simple seed shop with coins

## 9. Later Ideas (Not Version 1)

- Real seasons (southern hemisphere aware) affecting which seeds grow best
- Bigger garden and unlockable beds
- Garden decorations (pots, paths, birdbath)
- Bees and butterflies that visit blooming flowers
- Flower collection book
- Menu bar widget showing garden status at a glance
