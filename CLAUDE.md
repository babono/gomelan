# Gomelan

An iPhone app that turns a real Balinese *gangsa* into a guided practice surface. The phone
sits on a stand above the instrument looking down: the camera sees which bilah you strike,
the microphone hears when, and an overlay on the live feed says what to play next.

Product name is **Gomelan**; the Xcode target, folder and bundle name are **`Kotek`**.
(Some older references in the repo use `gomelan` as the target name — that rename is done.)

`documentation/prd.md` is the spec. Source comments cite it by section (§5.1, §13.4, …), so
read it alongside the code rather than after it.

## Build

The `.xcodeproj` is **generated and gitignored**. After changing `project.yml`, or on a fresh
clone, regenerate before building:

```sh
cp Config.xcconfig.template Config.xcconfig   # fresh clone only; fill in team + bundle ID
xcodegen generate
xcodebuild -project Kotek.xcodeproj -scheme Kotek \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

Adding a file to `Kotek/` is enough — sources are globbed by `project.yml`, so there is no
project file to edit, but you do have to re-run `xcodegen generate`.

Bump `CURRENT_PROJECT_VERSION` in `project.yml` for **every** TestFlight upload; App Store
Connect rejects a build number it has already seen for the marketing version, and it does so
at the *end* of the upload.

## Conventions

- **iOS 26.5, landscape-locked, `@Observable`** (not Combine/`ObservableObject`).
- The target sets `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`. Everything is main-actor
  isolated unless it says otherwise, so `nonisolated` and `actor` in this codebase are
  always deliberate — they mark the things that must stay off the UI thread (CoreML
  inference, audio DSP, profile writes, sample decoding). Don't remove them casually.
- **Key indices, never pitches.** Songs, kotekan and overlay state all address bilah by
  index. This is what makes a figure portable across instruments — every village in Bali
  tunes differently, so no pitch or key position is hardcoded in logic; it lives in an
  `InstrumentProfile`.
- Rects are normalised 0–1 against the video buffer, top-left origin.
- Comments here explain *why*, and usually name the approach that was tried and failed.
  That history is the real documentation — preserve it when editing, and match the density.

## Architecture

The central split: **vision answers *which key*, audio answers *when*.** The camera knows
where each bilah is, so it identifies keys by location and never has to tell two pitches
apart. Sound supplies timing and confirms a strike was real. `KeyDecomposer` is the one
place audio identifies a key — as a second opinion where vision is occluded, and it never
overrides vision.

### `Kotek/Model/` — state and data

| File | Role |
|---|---|
| `AppState.swift` | The app state machine. 21 screens: welcome → permissions → choose instrument → 4-step setup (key count → framing → aligning → baseline) → kotekan → half → cycles → watch → play → results, plus settings and four dev screens. |
| `Kotekan.swift` | The domain core. Two 16-slot grids (*polos* on the beat, *sangsih* off it) over one gong cycle; `makeSong` renders the chosen half over N cycles. |
| `InstrumentProfile.swift` | Per-instrument key rects, pitches, strike baseline. |
| `Song.swift`, `Judgement.swift` | Note sequence; timing windows (deliberately generous). |
| `ProfileStore.swift` | snake_case JSON in Documents, same shape as the bundled profile. |
| `ResourceLoader.swift` | Bundled profile + songs, with an embedded fallback. |
| `Preloader.swift` | Launch-time warming behind the splash: camera graph, 13 WAV decodes, CoreML compile. Read its header before adding anything — what is *not* preloaded (the audio engine, `startRunning()`) is as deliberate as what is. |
| `Defaults.swift` | UserDefaults, detection tuning only. |

### `Kotek/Audio/` — the DSP pipeline

```
mic tap → SampleRing → 1024/256 STFT → SpectralFlux → OnsetDetector
        → (wait ~105 ms) → 4096 FFT → Fingerprinter → KeyClassifier
```

Two window sizes on purpose: 1024 for *time* precision on onsets, 4096 for *frequency*
precision on fingerprints. Strikes are reported ~105 ms late by design — the note has to
sound before it can be identified — with `hostTime` reconstructed to when the strike
actually occurred.

- `AudioEngineController.swift` — owns the chain; the one door every listening path enters by.
- `FFTProcessor.swift` — vDSP FFT matching numpy `rfft` bin-for-bin, so results can be
  diffed against the Python reference implementation.
- `Fingerprinter.swift` — 120-element spectral *shape* vector, L2-normalised so soft and
  hard hits look alike. Bronze is inharmonic (partials ≈ 1, 2.76, 5.42, 8.91×), so
  fundamental-finding does not work.
- `KeyClassifier.swift` — cosine match, 1-of-N. `KeyDecomposer.swift` + `NNLS.swift` — the
  polyphonic counterpart; bronze rings for seconds, so by note three the mic hears three
  keys and "which one key" has no answer. Self-calibrating from confident vision strikes.
- `SpectralFlux.swift` — only energy *increases* count. That clamp is why sustained notes
  don't re-trigger.
- `DSPConfig.swift` — mirror of `Config` in `algorithm/gamelan_dsp.py`, the Python reference
  implementation. Every value was measured, not guessed, and the two copies must not drift.
  Note that the Python side lives **outside this repo** — the notebook is not checked in.
- `CuePlayer.swift`, `SampleLibrary.swift`, `SplashChime.swift`, `TitleMusic.swift`,
  `AudioSessionManager.swift` (`.measurement` mode disables AGC and echo cancellation —
  do not omit it), `CalibrationFile.swift`.

### `Kotek/Capture/` + `Kotek/Detection/` — vision

- `CameraController.swift` / `CameraPreview.swift` — **one** session and **one** preview
  layer, re-parented per screen. Per-screen layers cost a measured 9 s main-thread stall.
- `FrameBuffer.swift` — rolling frame history keyed by host time, so fusion can retrieve
  the frame from 105 ms ago.
- `MalletHitClassifier.swift` — `MalletDetector.mlmodel` on a **cropped** key. Answers "is
  this region being struck", not which key; which key comes from where we cropped.
- `VisionStrikeDetector.swift` — per-key Schmitt trigger. This is the primary trigger, and
  being self-triggering is what makes it immune to background noise.
- `StrikeFusion.swift` — an `actor` (keeps CoreML off the display link) reconciling vision
  scores with the calibrated layout. All paths share `decide()`.
- `TrainingCapture.swift` — harvests labelled crops through the *same* path inference uses.
  One strike labels all keys: struck bar positive, the rest hard negatives.

### `Kotek/Calibration/`

- `CalibrationView.swift` — the baseline step: learn what a real strike on *this* gangsa
  sounds like, so a clap or a scream can be rejected. Per-bilah pitch calibration is gone.
- `BilahFinder.swift` — fits one periodic *comb* of N teeth (pitch + phase, two unknowns)
  instead of finding N bars independently. Keys on structure, not brightness or colour —
  both fail on real instruments, and colour collapses entirely on black-painted bilah.
- `KeyDetector.swift`, `ProjectionAligner.swift` — alternative localisers, **not wired into
  the shipped flow**. Alignment is manual drag.

### `Kotek/Play/` + `Kotek/UI/`

- `PlayEngine.swift` — the core loop: timing, judgement, overlay state, cue triggering,
  driven by a display link. Two modes (scored play / no-fail practice), two roles (demo,
  run).
- `OverlayView.swift` — the *primary* guidance, drawn on the bilah themselves. One `Canvas`,
  one draw pass; it reads the engine directly so per-frame invalidation stops there.
  `NotesRiver.swift` — the secondary piano-roll strip showing both halves against the cycle.
- `RootView.swift` — hosts the state machine, owns the shared camera/audio/cue services, and
  holds the single `PatternBackground` so its drift is continuous across transitions. Camera
  teardown lives here too, because this is the one place that knows what the app is showing.
- `Theme.swift` / `Components.swift` — one warm-brown ground everywhere (the app used to
  flip light/dark mid-flow), radius 14, 56 pt primary buttons, rectangles not capsules.
- Flow screens: `Welcome`, `Permissions`, `ChooseInstrument`, `KeyCount`, `Framing`,
  `Aligning`, `ChooseKotekan` / `ChooseHalf` / `ChooseCycles`, `Watch`, `Play`, `Results`,
  `Settings`, `Splash`.
- Dev screens, reachable from Settings: `AudioTest` (onset gate and noise floor),
  `MalletTest` (raw per-frame vision probabilities), `DetectionTest` (the real fused
  pipeline — debug combined detection here), `CaptureTraining`.

### Resources

`Kotek/Resources/` — ten key samples plus gong/kempur/kajar, title music, Dream Orphans
font (titles only; body type is San Francisco). `Kotek/*.mlmodel` — `MalletDetector` and its
V1/V3/V4 history, plus `BilahDetector` (present, unused at runtime).
