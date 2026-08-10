# Gomelan — Product Requirements Document

**Version:** 0.5 (v1 scaffold implemented; reconciled with the codebase)
**Platform:** iOS 17+, iPhone only
**Instrument:** Gangsa (gong kebyar family) — single mallet, monophonic, one bundled profile
**Status:** Implemented and running end-to-end on placeholder data — awaiting the physical instrument for real calibration values

---

## 0. Implementation Status (as of v0.5)

The full v1 architecture described in this document is built and compiles clean. The app runs the entire flow — welcome → permissions → framing → alignment → song list → play/practice → results — against a bundled placeholder profile. What remains is real instrument data and a handful of Phase 5 items.

**Built and working:**
- App state machine (`Model/AppState.swift`), models, `ProfileStore` persistence to Documents (snake_case JSON, round-trips with the bundled shape)
- Camera capture with focus/exposure lock (`Capture/CameraController.swift`)
- Real-time audio pipeline: spectral-flux `OnsetDetector` + FFT `KeyClassifier` via a `FFTProcessor` (vDSP), fed by `AudioEngineController`
- `PlayEngine` — play + practice modes, timing/judgement, approach track, damp hints, cue triggering
- Peripheral `OverlayView`, all screens, `CuePlayer` (synthesized cues)
- **In-app pitch calibration** (`Calibration/CalibrationView.swift`), reachable from Settings — see §2 note; this went from "dev-only" to shipped
- Manual drag/resize key alignment (`UI/AligningView.swift`)

**Placeholder — needs the physical instrument:**
- Bundled profile is a **10-key** placeholder (`Model/ResourceLoader.swift`): lower five fundamentals use the §6.3 measured pelog intervals, keys 5–9 an octave up; rects are graduated tall→short with ~1cm gaps. Real pitches/rects come from calibrating on the instrument.
- **Two** placeholder songs, not one: "First Run" (5 keys, §13.6) and "Full Run — All Keys" (10-key up-down run, doubles as the §6.3 all-keys detection check). Real first exercise still to come from Mekar Bhuana (§11 Q1).
- Cue tones are synthesized sines; should be replaced by the instrument's own calibration samples (§5.4/§7). Calibration currently records **pitch only** — no `.caf` sample capture, no harmonic/decay re-measurement.

**Known gaps / deferred:**
- Output ducking around strike windows (§5.4) is a TODO hook only
- Overlay maps normalized rects straight to view bounds (assumes aspect-fill; no perspective correction — §3.4 deferred as intended)
- Exhibition/kiosk auto-reset mode not built (Phase 5)
- `Calibration/KeyDetector.swift` (Vision rectangle detection, §6.4) exists but is **not wired into the runtime flow** — alignment is manual drag from the bundled rects

## 1. Purpose

**Challenge statement:**
> Empower young Balinese who want to relearn gamelan by turning a real instrument into something they can approach alone — guided, before there's a teacher or a community to join.

**What this app does:**
Gomelan is an iPhone app that turns a real gangsa into a guided learning surface. The phone is mounted on a stand above the instrument, looking down. The app overlays visual guidance onto the live camera feed — showing which key to strike and when — and listens through the microphone to judge whether the user hit the right key at the right time.

**Positioning line:** *Play gamelan anywhere — no sekaa required.*

**Platform decision (v0.2):** an earlier draft used a Mac app with iPhone Continuity Camera Desk View. This was dropped. Desk View captures a fixed desk region that a large instrument may not fit, offers no control over framing, and does not expose the feed to ARKit or the full Vision stack. A phone on a stand solves all three, and reduces the exhibition setup from three objects to one.

**Why this addresses the research:**

Interviews with young Balinese converged on a consistent picture: they still want gamelan, they hear it only at ceremonies, and the barrier is not desire.

- **Time is the primary barrier.** The conventional route in is joining a neighbourhood *sekaa* — a standing commitment of regular rehearsals tied to a place and a ceremonial calendar. Working young people can't take it on, and no smaller commitment exists. **The product's core answer: learn on your own schedule, in short sessions, with no group required.**
- **Access** — instruments are expensive and community-gated. At the exhibition the instrument is simply there; no ownership, no membership.
- **Knowledge** — nothing about gamelan was written down, so there is no visible way to begin. Guidance is shown on the instrument itself rather than read from notation.
- **Fear of being a beginner in public** — guided solo practice removes the risk of being bad in front of people who already know.

**Design constraint (from the founder interview):**
Technology stays in a support role. This app helps someone take a first step; it does not replace a teacher, and the product language should never imply that it does. The framing is *before* a teacher, not *instead of* one.

---

## 2. Scope

### In scope (v1)
- Live camera capture with instrument in frame
- **One bundled instrument profile** — our gangsa, calibrated ahead of time and shipped with the app
- Re-alignment step (drag key rectangles if the phone or instrument is knocked)
- Song library with 3–5 short patterns
- Rhythm-matching core loop with visual overlay guidance
- Audio cue layer (so the user is not dependent on the screen — see §5.4)
- Post-song score and retry
- Practice mode (no scoring, no fail state)

### Out of scope (v1)
- macOS app of any kind
- **Vision-based key-rectangle detection at runtime** — `KeyDetector` (§6.4) exists but is not wired in; alignment is manual drag from the bundled rects
- Virtual/sampled gamelan playback as an instrument substitute
- Apple Music integration or arbitrary song transcription
- Multiplayer / interlocking two-player mode (see §11 — strong v2 candidate)
- Recording, sharing, accounts, cloud sync
- iPad layout (build iPhone-only; add iPad later if the larger screen proves needed)

### Single-instrument decision (v0.4)

v1 supports exactly one instrument: the gangsa we own.

**Build the calibration path anyway.** Do not hardcode key positions or pitch values. Run the calibration once on our instrument, save the resulting profile, and bundle it as the app default. Consequences:

- First-run setup drops to "frame the instrument, confirm alignment" — roughly 15 seconds
- Supporting a second instrument later becomes a data task, not a code change
- The claim "the system calibrates to whatever instrument it is pointed at" stays true — we have simply pre-run it

**Implementation note (v0.5):** the calibration path is not just for us — a **pitch-recording calibration** is shipped in the app (Settings → "Record key pitches"). It records 3 strikes per key, takes the median, discards >50-cent outliers, warns on <60-cent similarity between keys, and saves the result over the bundled default via `ProfileStore`. It records fundamentals only; it does not (yet) re-measure harmonics/decay or capture reference samples. Key **positions** are set by manual drag/resize in the alignment step, not by Vision detection.

**How to frame this externally:** the architecture is per-instrument by design, because every village in Bali tunes differently (see the measured intervals in §6.3). v1 ships one profile because we own one gangsa. That is a scope decision, not an architectural limitation — and it is worth stating that way, since village-specific tuning is a central research finding.

### Explicit non-goals
- Teaching full traditional repertoire
- Replacing human instruction
- Assuming a fixed scale or standard tuning

---

## 3. Hardware & Environment

### 3.1 Setup requirements

| Item | Requirement | Notes |
|---|---|---|
| iPhone | iPhone 12 or later, iOS 17+ | Needs adequate compute for real-time FFT + Vision |
| Stand | Adjustable tripod or gooseneck mount, phone in landscape | Positioned above and slightly behind the instrument, angled down |
| Instrument | **Gangsa** (gong kebyar family) — bronze keys suspended over individual bamboo resonators, in a carved wooden frame | Played seated on the floor; playing surface ~30–40cm high |
| Mallet | Single hard wooden *panggul*, right hand | Left hand damps; see §5.5 |
| Audio | Built-in mic acceptable in a quiet room; external/lavalier preferred for the exhibition | See §6.3 |
| Lighting | Even, no hard shadow across the keys | Affects key detection |
| Optional | Lightning/USB-C to HDMI, or AirPlay to a screen | Exhibition only — mirrors the guidance to a larger display |

**One device, one app.** No Mac, no second app, no Continuity Camera dependency. Camera, microphone, processing, and display all live on the phone.

### 3.2 Framing

Mount height and angle are user-controlled, which is the main advantage over the previous design. Target framing:

- All calibrated keys visible with ~10% margin on each side
- Phone positioned so the user's hands and mallets do not occlude the keys from the camera's viewpoint — above and slightly *behind* the instrument (from the player's side) works better than directly overhead
- The app should provide an on-screen framing guide during setup and refuse to proceed until all detected keys sit inside it

**Gangsa-specific physical notes:**

- **Low playing height.** The gangsa is played seated on the floor. The mount must be a floor-standing tripod or gooseneck, not a desk tripod. At the exhibition, either provide floor cushions (correct posture) or place the instrument on a low table (incorrect but workable for a first touch).
- **Polished bronze is reflective.** Keys will blow out under direct overhead lighting and break rectangle detection. Diffuse, even light matters more here than with a matte instrument — a likely and easily-misdiagnosed cause of detection failure.
- **The carved, gilded frame is visually busy** and may generate false rectangles. Manual drag-adjust during calibration is not optional polish; expect users to need it.
- **Keys are thick with visible gaps between them**, which is favourable for detection compared to instruments whose keys sit flush.
- **The instrument is heavy.** Once positioned at the exhibition it stays. Set the camera to the instrument, not the reverse.

### 3.4 Perspective correction (optional, deferred)

Desk View's top-down effect is just a homography applied to an angled feed. The same is achievable with `CIPerspectiveCorrection`, using four corner points captured during calibration.

**Not needed for v1.** The overlay is drawn onto the image, not measured in world space, so a slightly trapezoidal instrument is fully usable. Rectification costs GPU per frame and adds an alignment failure mode for a mostly aesthetic gain.

Add it only if the mount test shows the phone must sit at a shallow angle that compresses the far keys to the point of illegibility.

### 3.5 Exhibition display

For the exhibition, mirror the phone to a larger screen. **Wired QuickTime capture is preferred over AirPlay** — connect the iPhone by cable, open QuickTime on a Mac, File → New Movie Recording, select the iPhone as source. No latency, no dependence on venue Wi-Fi, and it records simultaneously, which gives clean demo footage without filming a phone screen.

### 3.3 The screen visibility problem

This is the primary UX risk of the iOS-only design and must be designed for, not discovered.

A player standing over a large instrument cannot comfortably read a 6-inch screen positioned near that instrument. Mitigations, in priority order:

1. **Design the overlay to be legible peripherally** — large shapes, strong colour, no text, no fine detail during play. The user should be able to read state from a glance in their lower peripheral vision.
2. **Audio cues carry the timing** (§5.4). If the audio layer is good enough, the screen becomes confirmation rather than instruction.
3. **Mount the phone at eyeline where possible** — higher and further back than a "camera" instinct suggests.
4. **Exhibition: mirror to an external display.** AirPlay or a cable to a monitor behind the instrument. Cheap, and it removes the problem entirely for the demo that matters most.

Playtest this specifically in Phase 1. If users can't follow the overlay, the fix is more audio, not more visuals.

---

## 4. Core Flows

### Flow A — Setup & Calibration (first run, or new instrument)

```
1. Welcome screen → "Set up your instrument"
2. Camera permission + live preview → prompt to mount the phone on a stand
3. Framing guide → outline overlay; user adjusts stand until all keys sit inside it
4. Key detection → app detects key rectangles; user confirms or adjusts
5. Audio calibration → app prompts strike of each key, left to right, one at a time
6. Confirmation → app plays back detected order; user confirms
7. Saved as an instrument profile
```

**Calibration details:**
- Prompt one key at a time with a visual highlight on the detected key in the video feed
- Require 3 clean strikes per key; discard outliers
- Store: fundamental frequency, first 3 harmonic ratios, decay envelope, onset sharpness
- If two keys fingerprint too similarly (< threshold distance), warn and re-prompt
- Whole calibration should take under 3 minutes for a 10-key gender

**Why per-instrument calibration is mandatory:** every village in Bali tunes its gamelan differently. There is no standard pitch set to hard-code against. Calibration is what makes the app work with *this* instrument rather than an imagined generic one.

**As-built note (v0.5):** the shipping *first-run* is the short path — framing → manual alignment (steps 1–4 collapse to "frame, then drag the bundled rects onto the keys"). The richer calibration above is split: **pitch recording** is available on demand from Settings (steps 5–6, pitch only), and Vision rectangle detection (step 4's auto-detect) is written but not wired in. Sample capture, harmonic/decay measurement, and the "plays back detected order" confirmation are not yet implemented.

### Flow B — Song Selection

```
1. Song list → title, difficulty, length, key count required
2. Song detail → preview audio, pattern visualisation, "Practice" / "Play"
3. Mode select → Practice (no scoring) or Play (scored)
```

Songs must be filtered against the calibrated instrument: hide or grey out songs requiring more keys than the profile has.

### Flow C — Play & Learn (core loop)

```
1. Countdown (3-2-1) over live video feed
2. Loop:
   a. Upcoming note approaches on the timeline
   b. Corresponding key highlights on the video overlay
   c. User strikes
   d. Audio engine detects onset + identifies key
   e. Judgement rendered (timing accuracy + correct key)
3. Song ends → results screen → retry / next / back
```

---

## 5. Core Mechanic Specification

### 5.1 Timing model

Notes are defined as `(key_index, time_ms, duration_ms)`.

**Judgement windows** (tune during playtesting; these are starting values):

| Result | Window | Score |
|---|---|---|
| Perfect | ±60ms | 100 |
| Good | ±120ms | 70 |
| Late/Early | ±200ms | 30 |
| Miss | outside ±200ms, or no strike | 0 |
| Wrong key | correct timing, wrong key | 0, distinct feedback |

Gamelan is played at moderate tempi and beginners are slow. Start generous (windows above are already looser than a typical rhythm game) and tighten only if playtesting shows it feels trivial.

### 5.2 Visual guidance (the overlay)

Drawn as a 2D layer on top of the live camera feed:

- **Idle key** — thin outline, low opacity
- **Upcoming (approaching)** — outline fills progressively as the note approaches; acts as a countdown
- **Strike now** — solid highlight, brief pulse
- **Hit correctly** — green flash, fades over ~300ms
- **Missed** — red flash
- **Wrong key struck** — amber flash on the key actually struck, plus the correct key stays highlighted

Include a secondary timeline element (a horizontal bar or approach track) at the screen edge, so the user has advance warning beyond the key-fill animation. Users cannot look at the screen and their hands simultaneously — the overlay must be legible peripherally.

### 5.3 Practice mode

- No fail, no score
- Waits for the correct key indefinitely before advancing
- Optional: slow-tempo setting (50%, 75%, 100%)
- This is the mode that serves the "fear of being wrong" barrier; make it the default for first-time users

### 5.4 Audio cue layer

Because the screen is small and the player is standing over the instrument (§3.3), audio carries as much of the guidance as vision does.

- **Metronome click** on the beat, subtle, toggleable
- **Reference tone** — the calibrated sample of the upcoming key, played quietly one beat ahead. This is the closest digital equivalent to learning by ear, which is how gamelan is actually transmitted.
- **Hit/miss feedback** — short distinct sounds, not speech
- Route through the device speaker; must not be loud enough to interfere with onset detection of the real instrument. Test the feedback loop early — the app's own audio output entering its own mic is a real failure mode. Consider ducking output for ~50ms around expected strike times.

**Design note:** if the audio layer works well, a user could follow a pattern with the screen barely in view. That is the ideal outcome, and it aligns with how the music is traditionally taught — by listening and imitating, not by reading.

### 5.5 Damping (gangsa-specific)

On gangsa, the right hand strikes with the mallet and the **left hand damps the previous key** — pinching it with thumb and index finger. Without damping, every key rings for seconds and a run turns to mush. This is not optional technique; it is half of how the instrument is played.

**v1 decision: teach it, don't score it.**

- Practice mode shows a secondary damp indicator on the *previous* key at the moment the next note is struck
- The judgement engine ignores damping entirely — strikes are scored, damping is not
- Rationale: damping is a two-hand coordination skill that takes real practice. Failing beginners on it would reintroduce exactly the "I'm bad at this" barrier the product exists to remove.

Make this an explicit, stated decision rather than an omission. A reviewer familiar with gamelan will notice if damping is absent; "we teach it without scoring it, deliberately" is a good answer, silence is not.

**v2 possibility:** damping is detectable — an abrupt truncation of a ringing key's decay envelope is a distinctive audio signature. Worth exploring once the core loop is stable.

---

## 6. Technical Architecture

### 6.1 Stack

- **Language:** Swift
- **Target:** iOS 17+, iPhone only, landscape-locked during play
- **UI:** SwiftUI, with a `UIViewRepresentable` hosting the preview layer and a Core Animation or Canvas overlay above it
- **Capture:** AVFoundation (`AVCaptureSession`, back wide camera)
- **Audio analysis:** AVAudioEngine + Accelerate (vDSP) for FFT
- **Vision:** Vision framework for rectangle detection
- **Persistence:** local JSON or SwiftData; no backend in v1

#### Tech stack (as-built, v0.5)

Entirely Apple first-party frameworks — **no third-party dependencies**.

| Layer | Framework / API | Where |
|---|---|---|
| Language & platform | Swift, iOS 17+, iPhone-only, landscape-locked | `gomelanApp.swift`, `AppDelegate` |
| UI | SwiftUI | all of `UI/`, `Play/OverlayView.swift` |
| State | Observation (`@Observable`, `@Environment`) — **not** Combine | `Model/AppState.swift` |
| Camera preview | AVFoundation via `UIViewRepresentable` | `Capture/CameraPreview.swift` |
| Camera capture | AVFoundation (`AVCaptureSession`, back wide camera, focus/exposure lock) | `Capture/CameraController.swift` |
| Audio I/O | AVAudioEngine (mic tap + cue playback) | `Audio/AudioEngineController.swift`, `Audio/CuePlayer.swift` |
| Audio session | AVAudioSession (`.playAndRecord` / `.measurement`) | `Audio/AudioSessionManager.swift` |
| DSP | Accelerate / vDSP (FFT magnitude spectrum) | `Audio/FFTProcessor.swift` |
| Detection | Custom spectral-flux onset + nearest-neighbour pitch classifier | `Audio/OnsetDetector.swift`, `Audio/KeyClassifier.swift` |
| Vision | Vision (`VNDetectRectanglesRequest`) — present, **not wired into runtime** | `Calibration/KeyDetector.swift` |
| Play-loop timing | `CADisplayLink` (QuartzCore) | `Play/DisplayLink.swift`, `Play/PlayEngine.swift` |
| Persistence | `Codable` + JSON to Documents (snake_case) — no SwiftData / Core Data / backend | `Model/ProfileStore.swift`, `Model/ResourceLoader.swift` |
| Concurrency | Swift `async`/`await`, `Task` (Combine deliberately avoided) | throughout |

**Deltas from the bullet list above:** the overlay is pure SwiftUI shapes (not Core Animation or Canvas); persistence landed as plain JSON (not SwiftData); and Vision rectangle detection is built but not invoked at runtime — key positions come from the bundled rects, adjusted by manual drag in the alignment step.

### 6.2 Camera capture

Standard `AVCaptureSession` with the back wide-angle camera. Notes:

- **Lock focus and exposure after calibration.** Autofocus hunting will shift key positions between frames and can cause the overlay to drift out of alignment. Use `AVCaptureDevice.focusMode = .locked` once the instrument is framed.
- **Set a fixed video orientation** — landscape — and lock the app's interface orientation during play.
- Preview at whatever resolution renders smoothly; run rectangle detection on a single still frame at higher resolution during calibration only.
- **Configure the audio session for `.playAndRecord`** with measurement mode, so mic capture and cue playback coexist. This is the single most fiddly piece of iOS plumbing in the project — get it working before building anything on top of it.

### 6.3 Audio detection pipeline

```
Mic input (device sample rate, typ. 44.1/48kHz)
  → Sliding accumulator, 4096-sample FFT window, 1024-sample hop
  → Onset detection (spectral flux normalised by frame energy,
      + dynamic ambient-energy floor, + refractory period)
  → On onset: classify the same window's magnitude spectrum
  → Peak-pick fundamental in the search band (parabolic interpolation)
  → Nearest-neighbour match on fundamental, measured in cents
  → Emit (key_index, hostTime, confidence)
```

**As-built note:** the shipping detector classifies the onset window directly rather than re-analysing at onset + 20ms (the offset is not applied). The onset detector also adds a dynamic noise floor: it averages ambient energy over the first few frames after reset and raises the minimum-energy gate to `max(1.8, ambient × 2.2)`, so a noisy room self-calibrates. Confidence is derived from the cents distance to the nearest key (1.0 at a perfect match, decaying to 0 at ~120 cents).

**Known difficulties, and how to handle them:**

- **Long decay.** Metallophone keys ring for seconds. Onset detection (spectral flux) rather than amplitude thresholding handles this; a previous note's sustain won't trigger a false onset.
- **Overlapping notes.** If the previous key is still ringing, the new FFT contains both. Mitigate by comparing against a spectral *difference* from the pre-onset frame, not the raw spectrum.
- **Ombak / paired detuning.** Gamelan instruments are often tuned in pairs slightly apart to produce an intentional beating effect. If you're using a single instrument this doesn't arise. If a paired instrument is used, calibrate them as separate profiles or separate key entries.
- **Room noise at the exhibition.** A crowded room is the worst case. Use a directional or contact mic mounted near the instrument if at all possible. Test in a noisy environment before the exhibition, not on the day.

**Latency budget:** total audio-to-feedback under 100ms. Above that, judgement will feel unfair.

**Validated against a real recording (Aug 2026).** An 11.8s clip of the actual gangsa was analysed offline with this exact pipeline:

| Measure | Result |
|---|---|
| Strikes detected | 32 / 32, no false positives from ring-out |
| Distinct pitches identified | 5 |
| Closest separation between keys | 126 cents (need ~60 to be safe) |
| Widest separation | 407 cents |
| Pitch spread within a single key | 0.0% — identical fundamental every strike |
| Mean spectral-fingerprint distance | 0.56 (cosine); same-key pairs cluster below 0.15 |

**Conclusions:** monophonic onset detection works on this instrument. Spectral flux correctly ignores decay tails. Keys are reliably separable by fundamental alone; the harmonic profile is available as a tiebreaker but wasn't needed.

**Offline-validated starting values (Aug 2026):** FFT window 4096, analysis offset +20ms after onset, flux threshold 0.18 normalised, refractory period 80ms, fundamental search band 150–1400Hz.

**Values as tuned in code (v0.5), pending live re-validation on the instrument:** FFT window 4096, hop 1024; no analysis offset (onset window classified directly); normalised-flux threshold 0.28 with a dynamic ambient-energy floor; refractory period 150ms; fundamental search band **275–3500Hz** (raised low bound to reject ~245Hz AC/mic rumble; raised high bound to cover the upper octave and Kantilan-range keys), with a peak-prominence gate (≥2× the in-band average) and a mild high-frequency weighting so metallic partials aren't swamped by low rumble. These drifted from the offline values during dry-room testing without the real instrument; re-check against a live run before locking.

**Still to validate:** the test clip only exercised 5 keys. Record a slow left-to-right run across all keys and re-run before locking the pipeline.

**Note on tuning:** the measured intervals (147 / 407 / 126 / 196 cents) are markedly uneven and unlike equal temperament — consistent with a real pelog tuning. This is direct evidence for the per-instrument calibration requirement, and worth citing in the project presentation.

### 6.4 Key position detection (vision)

- Run `VNDetectRectanglesRequest` on a still frame during calibration
- Filter by expected aspect ratio and minimum size
- Sort left-to-right by centroid x
- Present detected rectangles to the user for confirmation, with manual drag-adjust as fallback
- **Detect once at calibration, then freeze.** Do not run detection per-frame — it's expensive and the instrument doesn't move. Offer a "re-detect" button if the instrument is bumped.

---

## 7. Data Model

### Instrument profile

```json
{
  "id": "gangsa-exhibition-unit",
  "name": "Gangsa — Exhibition Unit",
  "key_count": 10,
  "created_at": "2026-08-02T10:00:00Z",
  "keys": [
    {
      "index": 0,
      "rect": { "x": 0.12, "y": 0.44, "w": 0.06, "h": 0.18 },
      "fundamental_hz": 293.4,
      "harmonics": [2.31, 4.08, 5.92],
      "decay_ms": 1800,
      "confidence": 0.94,
      "sample_path": "samples/{profile_id}/key_00.caf"
    }
  ]
}
```

Rect coordinates normalised 0–1 against the video frame, so the overlay survives resolution and orientation changes.

**Store the calibration recordings.** The clean strike captured during calibration doubles as the reference tone for the audio cue layer (§5.4). Keep one clean sample per key rather than discarding the audio after fingerprinting — it costs almost nothing and it means the cue tones are in the instrument's own tuning rather than a generic sampled set.

**As-built note (v0.5):** `sample_path` is present in the model but the in-app calibration does not yet capture samples — `sample_path` is `null` and cue tones are synthesized sines. Capturing one clean `.caf` per key is still the intended step.

### Song

```json
{
  "id": "uuid",
  "title": "Pattern One",
  "difficulty": "beginner",
  "bpm": 80,
  "required_keys": 5,
  "duration_ms": 24000,
  "notes": [
    { "key_index": 0, "time_ms": 0,    "duration_ms": 500 },
    { "key_index": 2, "time_ms": 750,  "duration_ms": 500 }
  ]
}
```

**Critical design decision:** notes reference **key index**, never pitch or note name. This is what makes songs portable across differently-tuned instruments — the same pattern plays on any calibrated gamelan and sounds correct in that instrument's own tuning. Do not be tempted to store frequencies here.

---

## 8. Screens

As built, screens map 1:1 to `AppState.Screen` cases and are hosted by `RootView`.

| Screen | State case | Purpose | Key states |
|---|---|---|---|
| Welcome | `.welcome` | Entry, setup prompt | First-run vs returning |
| Permissions | `.checkingPermissions` / `.permissionsBlocked` | Request camera + mic; live preview | Requesting / granted / blocked (links to Settings) |
| Framing | `.framing` | Position instrument | Outside guide / inside guide |
| Alignment | `.aligning` | Drag/resize bundled key rects onto real keys; confirm locks focus/exposure | Adjusting / confirmed |
| Song list | `.songList` | Browse | Filtered by key count |
| Song detail | `.songDetail` | Preview, mode select | — |
| Play | `.countdown` / `.playing` | Core loop (one screen) | Countdown / playing / paused |
| Results | `.results` | Score, accuracy, retry | — |
| Settings | `.settings` | Re-align, record pitches, tempo, audio-cue toggles | — |
| Calibration | `.calibrating` | Record 3 strikes per key to capture pitches | Awaiting strike / captured / retry / similarity-clash / done |

There is no standalone Vision "key detection" screen in v1 — key positions come from the bundled rects, adjusted by hand in Alignment. Calibration is reached from Settings, not the first-run path.

---

## 9. Build Phases

**Phase 0 — Feasibility** *(partially complete)*
- ~~Confirm keys are spectrally distinguishable~~ **PASSED** on a 5-key sample (§6.3). Remaining: record a slow run across all keys and re-verify.
- Find a workable floor-level mount position: all keys in frame, hands not occluding keys, no blown-out reflections off the bronze
- Confirm total key count on the instrument and update `required_keys` filtering accordingly

**Phase 1 — Capture & overlay** *(built)*
- Camera preview, locked focus, landscape lock ✓
- Static overlay rectangles drawn over the feed in correct alignment ✓
- **Mount-and-look test:** still owed — requires the physical instrument and mount

**Phase 2 — Calibration** *(partial)*
- Manual drag/resize alignment ✓; Vision rectangle detection written but not wired in
- Pitch fingerprinting + profile persistence ✓; sample capture and harmonic/decay re-measurement not done

**Phase 3 — Detection** *(built, needs live validation)*
- Audio session (`.playAndRecord` / `.measurement`) configured ✓
- Onset detection + key identification ✓ (validated offline; live re-check owed)
- Debug HUD showing detected key + confidence in real time ✓ (in `PlayView`)

**Phase 4 — Core loop** *(built)*
- Song playback, timing judgement, overlay guidance, audio cues, results ✓

**Phase 5 — Polish** *(partial)*
- Practice mode ✓, tempo control ✓
- Exhibition/kiosk mode (auto-reset, no settings access) — not built
- Cue output ducking around strike windows — not built

Phases 0 and 3 carry nearly all the technical risk; Phase 1's mount test carries the main UX risk. The code is past Phase 4 on placeholder data, but the two remaining risk items — the mount-and-look test and live detection validation — cannot be closed without the instrument.

---

## 10. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Keys not spectrally distinguishable | Breaks core mechanic | **Largely resolved** — validated on 5 keys (§6.3); confirm remaining keys |
| Bronze glare breaks key detection | Calibration fails, hard to diagnose | Diffuse lighting; manual drag-adjust fallback; test under exhibition lighting |
| Floor-level mount unstable or badly angled | Overlay unusable | Weighted floor tripod; test posture and angle in Phase 0 |
| Screen unreadable while playing | Core UX failure | Peripheral-legible overlay, audio cue layer, eyeline mount, wired mirror to external display at exhibition |
| Cue audio bleeds into mic and triggers false onsets | Corrupts judgement | Duck output around strike windows; test with speaker at realistic volume |
| Exhibition room noise breaks detection | Fails in the demo | External/contact mic; test in a noisy room, not on the day |
| Autofocus shifts framing mid-session | Overlay drifts off the keys | Lock focus and exposure after calibration |
| Detection latency > 100ms | Feels unfair, unfun | Profile early; reduce FFT window; test on the oldest target device |
| Calibration too tedious | Users quit at setup | Pre-calibrate the exhibition unit and ship its profile bundled |
| Phone knocked during exhibition | Alignment lost mid-use | One-tap re-detect; sturdy weighted stand |

---

## 11. Open Questions

1. **Which songs?** Undecided, and the highest-value question to resolve. **Ask Mekar Bhuana what a beginner gangsa player is actually given as a first exercise** — their answer becomes song one, it's defensible in a review in a way "we picked something simple" is not, and it keeps them involved as collaborators rather than a source cited once. Avoid Western melodies: a diatonic tune forced onto a pelog instrument will sound wrong, and it inverts the principle that adaptation flows toward the gamelan, never away from it.
2. **Two-player *kotekan*?** Interlocking *polos* and *sangsih* parts are the defining technique of gong kebyar gangsa playing — not a bolt-on multiplayer mode but the thing the instrument exists to do. It also directly answers the "no one to play with" barrier that single-player cannot. Strong v2 candidate; consider whether a minimal two-phone version fits v1.
3. **Exhibition flow.** Does the app need an unattended kiosk mode — auto-reset, no settings access, attract screen?
4. **What happens after the song?** If a user finishes and enjoys it, where do they go? A pointer toward real teaching (Mekar Bhuana, a local *sekaa*) would honour the "support, don't replace" constraint and give the product an honest ending.

---

## 12. Success Criteria

**v1 is successful if:**
- A first-time user is playing within 30 seconds of opening the app (framing + alignment confirm only)
- Key detection accuracy exceeds 95% in a quiet room
- A user with no gamelan experience completes a beginner pattern within 3 attempts
- At the exhibition, users voluntarily play more than once

---

## 13. Build Spec

Everything below is implementation detail a developer needs before opening Xcode.

### 13.1 Project setup

| Setting | Value |
|---|---|
| Project name | Gomelan |
| Bundle ID | `com.{team}.gomelan` |
| Minimum deployment | iOS 17.0 |
| Devices | iPhone only |
| Interface | SwiftUI |
| Supported orientations | Landscape Left, Landscape Right only |

**Info.plist keys (required — the app crashes without them):**

```xml
<key>NSCameraUsageDescription</key>
<string>Gomelan uses the camera to see your gangsa and show you which key to play.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Gomelan listens to your gangsa so it can tell which key you played.</string>
```

**Capabilities:** none required. No network, no accounts, no HealthKit.

### 13.2 Audio session

Configure once at launch, before any capture. This is the fiddliest part of the project — get it working and verified before building anything on top.

```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playAndRecord,
                        mode: .measurement,
                        options: [.defaultToSpeaker, .allowBluetoothA2DP])
try session.setPreferredSampleRate(44100)
try session.setPreferredIOBufferDuration(0.005)
try session.setActive(true)
```

`.measurement` mode disables the system's automatic gain control and echo cancellation. Both would corrupt onset detection and pitch analysis. Do not omit it.

**Known trap:** cue-tone playback through the speaker enters the mic and can trigger false onsets. Duck output around expected strike windows, and verify at realistic exhibition volume.

### 13.3 Module structure

As built:

```
gomelan/
├─ gomelanApp.swift               // @main App + AppDelegate (landscape lock), audio session config
├─ Capture/
│  ├─ CameraController.swift      // AVCaptureSession, focus/exposure lock
│  └─ CameraPreview.swift         // UIViewRepresentable
├─ Audio/
│  ├─ AudioSessionManager.swift   // .playAndRecord / .measurement
│  ├─ AudioEngineController.swift // mic tap → FFT → onset → classify → strike
│  ├─ FFTProcessor.swift          // vDSP magnitude spectrum, bin↔frequency
│  ├─ OnsetDetector.swift         // spectral flux + dynamic noise floor
│  ├─ KeyClassifier.swift         // peak-pick fundamental + nearest-neighbour (cents)
│  └─ CuePlayer.swift             // metronome, reference tones, hit/miss (synth)
├─ Calibration/
│  ├─ KeyDetector.swift           // VNDetectRectanglesRequest — present, not wired in
│  └─ CalibrationView.swift       // shipped pitch calibration (reached from Settings)
├─ Model/
│  ├─ AppState.swift              // state machine (§13.4)
│  ├─ InstrumentProfile.swift
│  ├─ Song.swift
│  ├─ Judgement.swift
│  ├─ ProfileStore.swift          // persist profile to Documents
│  └─ ResourceLoader.swift        // bundled profile + songs, with embedded fallback
├─ Play/
│  ├─ PlayEngine.swift            // timing, scoring, state
│  ├─ OverlayView.swift           // key highlights + approach track
│  └─ DisplayLink.swift           // CADisplayLink frame driver
└─ UI/
   ├─ RootView.swift              // hosts state machine + shared services
   ├─ WelcomeView / PermissionsView / FramingView / AligningView
   ├─ SongListView / SongDetailView / PlayView / ResultsView / SettingsView
   ├─ Components.swift / Theme.swift
   └─ (CalibrationView lives under Calibration/)
```

The bundled profile and songs are currently embedded as string fallbacks in `ResourceLoader`; the loader still prefers `profiles/gangsa_default.json` and `songs/*.json` from the bundle if present, so the exported real calibration can be dropped in without code changes.

### 13.4 State machine

As built, `AppState.Screen`:

```
launch → .welcome
  → .welcome
      begin → .checkingPermissions
  → .checkingPermissions
      denied  → .permissionsBlocked (terminal, links to Settings)
      granted → .framing
  → .framing              // live preview + guide outline
      user confirms → .aligning
  → .aligning             // bundled key rects overlaid, draggable/resizable
      user confirms (locks focus/exposure) → .songList
  → .songList             // filtered by profile key count
      select song → .songDetail
      open settings → .settings
  → .songDetail
      start(mode) → .countdown
  → .countdown / .playing // one screen (PlayView); pause is a local overlay, not a state
      complete → .results (play) | → .songList (practice)
  → .results
      retry → .countdown | back → .songList
  → .settings
      re-align → .aligning | record pitches → .calibrating | done → .songList
  → .calibrating
      save / cancel → .songList
```

There is no dedicated `.ready` or `.paused` case: the song list *is* the ready state, and pause is handled by local `@State` inside `PlayView`. Re-alignment is reached from Settings ("Re-align keys"), which is the persistent "keys misaligned?" affordance — used often at the exhibition.

### 13.5 Overlay visual tokens

Peripheral legibility is the constraint (§3.3). Large shapes, high contrast, no text during play.

| Token | Value |
|---|---|
| Key outline width | 3pt |
| Key corner radius | 4pt |
| Idle | white, 25% opacity, outline only |
| Upcoming | fills from bottom, cyan `#00D4FF`, 60% opacity; fill duration = time until strike |
| Strike now | solid cyan, 90% opacity, 1.06× scale pulse over 120ms |
| Hit | solid green `#00E676`, fades to idle over 300ms |
| Miss | solid red `#FF3B30`, fades over 300ms |
| Wrong key | amber `#FFB300` on the struck key, 300ms; correct key stays highlighted |
| Damp hint (practice) | dashed white outline on the previous key, 2pt |

**Approach track:** horizontal bar pinned to the bottom edge, 44pt tall, showing the next ~3 seconds. Notes travel right to left toward a fixed strike line at 15% from the left. This is the peripheral cue — it must be readable without focusing on it.

**Animation timing:** drive everything from `CADisplayLink` or SwiftUI's `TimelineView`, not `Timer`. Frame-accurate timing matters for a rhythm game.

### 13.6 Placeholder song

Use this to unblock Phase 4 before the real first exercise is confirmed with Mekar Bhuana. It is a plain ascending-descending run — deliberately not a real composition.

**As-built (v0.5):** the app ships two placeholders — this "First Run" (5 keys) and a "Full Run — All Keys" (10-key up-and-down run at 50 bpm) that doubles as the §6.3 all-keys detection check made playable. Both are embedded in `ResourceLoader`.

```json
{
  "id": "placeholder-run",
  "title": "First Run",
  "difficulty": "beginner",
  "bpm": 60,
  "required_keys": 5,
  "duration_ms": 20000,
  "notes": [
    { "key_index": 0, "time_ms": 0,     "duration_ms": 900 },
    { "key_index": 1, "time_ms": 1000,  "duration_ms": 900 },
    { "key_index": 2, "time_ms": 2000,  "duration_ms": 900 },
    { "key_index": 3, "time_ms": 3000,  "duration_ms": 900 },
    { "key_index": 4, "time_ms": 4000,  "duration_ms": 900 },
    { "key_index": 3, "time_ms": 5000,  "duration_ms": 900 },
    { "key_index": 2, "time_ms": 6000,  "duration_ms": 900 },
    { "key_index": 1, "time_ms": 7000,  "duration_ms": 900 },
    { "key_index": 0, "time_ms": 8000,  "duration_ms": 1800 },
    { "key_index": 0, "time_ms": 10000, "duration_ms": 900 },
    { "key_index": 2, "time_ms": 11000, "duration_ms": 900 },
    { "key_index": 4, "time_ms": 12000, "duration_ms": 900 },
    { "key_index": 2, "time_ms": 13000, "duration_ms": 900 },
    { "key_index": 0, "time_ms": 14000, "duration_ms": 1800 }
  ]
}
```

**Replace this.** Ask Mekar Bhuana what a beginner gangsa player is actually given first. That answer is worth more than any pattern we invent, and it keeps them involved as collaborators.

### 13.7 Build order for a developer

1. Camera preview rendering, landscape-locked, focus lock verified
2. Audio session configured; confirm mic input is unprocessed (no AGC)
3. Onset detector ported using the validated parameters in §6.3 — verify against the existing recording before testing live
4. Key classifier + debug view showing detected index and confidence live
5. Static overlay from bundled profile, aligned over real keys
6. **Stop and playtest:** stand at the instrument, check the overlay is readable peripherally
7. Play engine: timing, judgement, results
8. Cue audio, practice mode, exhibition mode

Steps 3 and 4 are the technical risk. Step 6 is the UX risk. Do not build past step 6 without doing it.
