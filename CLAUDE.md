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

### Architectural Principles

- **MVVM Pattern**: Clean separation of concerns with SwiftUI + Observation (`@Observable`):
  - **Model (`Kotek/Core/Models/`)**: Pure domain models (`Song`, `Kotekan`, `InstrumentProfile`, `Judgement`), global state machine (`AppState`), and persistence (`ProfileStore`). Independent of any UI framework.
  - **View (`Kotek/Features/*/`, `Kotek/App/RootView.swift`)**: Declarative SwiftUI views responsible solely for presentation, layout, visual feedback, and user interactions. Views stay thin and bind to observable state or view models.
  - **ViewModel / Controller / Engine (`Kotek/Core/Vision/`, `Kotek/Core/Audio/`, `Kotek/Features/Play/PlayEngine.swift`, feature ViewModels)**: Dedicated logic coordinators managing mutable state, hardware capture/audio lifecycle, and business rules, insulating Views from complex domain and signal logic.
- **DRY Principle (Don't Repeat Yourself)**:
  - Single source of truth for app state (`AppState`), camera session lifecycle (`RootView` / `CameraController`), and audio routing (`AudioSessionManager`).
  - Shared design tokens, styles, and controls live in `Kotek/Core/UI/` (`Theme.swift`, `Components.swift`, `PatternBackground.swift`) to eliminate visual and behavioral redundancy.
  - Core DSP algorithms (`Kotek/Core/Audio/DSP/`) and vision models/heuristics (`Kotek/Core/Vision/`) are shared, centralized services — never re-implemented inside feature screens.
- **SOLID Principles**:
  - **Single Responsibility**: Each class, actor, and view has a single well-defined job. E.g., `FFTProcessor` only computes FFT magnitudes; `OnsetDetector` identifies spectral flux peaks; `StrikeFusion` actor reconciles multi-modal detection off the UI thread; Views only describe UI.
  - **Open/Closed**: Open for extension without modifying core logic. Instrument tuning is profile-driven (`InstrumentProfile`), kotekan figures are data-driven, and new feature views can be added without altering audio/vision engines.
  - **Liskov Substitution**: Protocols and polymorphic types remain strictly substitutable and honor their contracts across asynchronous and actor boundaries.
  - **Interface Segregation**: Lean, cohesive interfaces (e.g. separate playback vs. capture session vs. DSP analysis; no bloated "god" objects).
  - **Dependency Inversion**: Feature views depend on injected controllers and services (`camera`, `audio`, `cue`, `@Environment(AppState.self)`) passed down from `RootView`, rather than hardcoded global singletons.
- **Ponytail Philosophy (Pragmatic Senior Dev / YAGNI)**:
  - Build the minimum that works cleanly. Before adding code: does it need to exist at all? Does the standard library or SwiftUI native feature do it? Can it be one line?
  - No unrequested abstractions, no ceremonial protocols with only one implementation, no boilerplate ViewModels for trivial views.
  - Mark intentional simplifications with a `// ponytail:` comment.

## Architecture

The central split: **vision answers *which key*, audio answers *when*.** The camera knows
where each bilah is, so it identifies keys by location and never has to tell two pitches
apart. Sound supplies timing and confirms a strike was real. `KeyDecomposer` is the one
place audio identifies a key — as a second opinion where vision is occluded, and it never
overrides vision.

The codebase is organized into four main directories:

```
Kotek/
├── App/          # Application entry point, window management, and root container
├── Core/         # Shared domain models, audio DSP/playback, vision pipeline, and UI styling
├── Features/     # Feature-oriented UI modules (Views, feature logic, and local engines)
└── Resources/    # Static assets: images, audio samples, fonts, and lottie animations
```

### `Kotek/App/` — application lifecycle and root container

- `KotekApp.swift` — `@main` application struct, initializes audio session for playback at launch, and configures landscape-locked `AppDelegate`.
- `RootView.swift` — hosts the `AppState` state machine, owns shared services (`camera`, `audio`, `cue`, `preloader`), renders the persistent continuous `PatternBackground`, manages overlays (`GuideView`, `OnboardingView`, `SplashView`), and tears down the camera when leaving camera screens.
- `Info.plist`, `Kotek.entitlements`, `PrivacyInfo.xcprivacy`.

### `Kotek/Core/Models/` — domain models, state, and persistence

| File | Role |
|---|---|
| `AppState.swift` | The app state machine (`AppState.Screen`), profile selection, kotekan session configuration, practice parameters, and result tracking. |
| `Kotekan.swift` | The domain core. Two 16-slot grids (*polos* on the beat, *sangsih* off it) over one gong cycle; `makeSong` renders the chosen half over N cycles. |
| `InstrumentProfile.swift` | Per-instrument key rects, pitches, strike baseline, and geometry. |
| `Song.swift`, `Judgement.swift` | Note sequence; timing windows and strike evaluation logic. |
| `ProfileStore.swift` | snake_case JSON persistence in Documents, round-tripping with the bundled profile format. |
| `ResourceLoader.swift` | Bundled profile and songs loader with embedded fallback strings. |
| `Preloader.swift` | Launch-time warming behind the splash: camera graph, 13 WAV decodes, CoreML compile. What is *not* preloaded (audio engine, `startRunning()`) is deliberate. |
| `Defaults.swift` | UserDefaults storage for detection tuning. |

### `Kotek/Core/Audio/` — DSP, playback, and session

```
mic tap → SampleRing → 1024/256 STFT → SpectralFlux → OnsetDetector
        → (wait ~105 ms) → 4096 FFT → Fingerprinter → KeyClassifier
```

- **`DSP/`**:
  - `AudioEngineController.swift` — owns the audio engine and mic tap; the single entry point for all listening paths.
  - `FFTProcessor.swift` — vDSP FFT matching numpy `rfft` bin-for-bin for validation against the Python reference.
  - `Fingerprinter.swift` — 120-element spectral shape vector, L2-normalised so hit dynamics don't skew identification. Bronze is inharmonic (partials ≈ 1, 2.76, 5.42, 8.91×).
  - `KeyClassifier.swift` — cosine match, 1-of-N.
  - `KeyDecomposer.swift` + `NNLS.swift` — polyphonic counterpart solving ringing bronze superposition; self-calibrating from confident vision strikes.
  - `SpectralFlux.swift` — half-wave rectified spectral flux (energy increases only) preventing sustained notes from re-triggering.
  - `OnsetDetector.swift` — dynamic threshold peak detector with noise-floor tracking.
  - `SampleRing.swift` — lock-free ring buffer holding audio history.
  - `DSPConfig.swift` — mirrors `Config` in the reference gamelan DSP implementation.
  - `CalibrationFile.swift` — binary format for pitch/strike calibration recordings.
- **`Playback/`**:
  - `CuePlayer.swift` — metronome, reference tones, hit/miss synthesis.
  - `KajarTick.swift` — dedicated low-latency `AVAudioPlayer` pool for button feedback (`.buttonStyle(.kajar)` / `.toggleStyle(.kajar)`).
  - `SampleLibrary.swift`, `PCMWav.swift`, `SplashChime.swift`, `TitleMusic.swift`.
- **`Session/`**:
  - `AudioSessionManager.swift` — hardware session configuration (`.measurement` mode disables AGC and echo cancellation).

### `Kotek/Core/Vision/` — camera capture, detection, and fusion

- `CameraController.swift` / `CameraPreview.swift` — **one** shared capture session and preview layer re-parented across screens (avoids main-thread stalls).
- `FrameBuffer.swift` — rolling frame history keyed by host time for 105 ms lookback.
- `BilahFinder.swift` — fits a periodic comb of N teeth (pitch + phase) instead of detecting N independent bars; robust against lighting and key color.
- `KeyDetector.swift`, `ProjectionAligner.swift` — alternative localisers.
- `MalletHitClassifier.swift` — runs `MalletDetector.mlmodel` on cropped key regions.
- `VisionStrikeDetector.swift` — per-key Schmitt trigger; primary trigger immune to acoustic noise.
- `StrikeFusion.swift` — an `actor` reconciling vision scores with audio timing off the display link.
- `MarkerTracker.swift`, `MarkerFusion.swift` — marker-based tracking alternatives.
- CoreML models: `MalletDetector.mlmodel` (and V1/V3/V4), `BilahDetector.mlmodel`.

### `Kotek/Core/UI/` — design system and shared visual components

- `Theme.swift` — unified warm-brown palette (`Theme.ground`), corner radiuses, typography, and button metrics.
- `Components.swift` — shared button and toggle styles (`.kajar`), custom controls, and typography helpers.
- `PatternBackground.swift` — single animated canvas providing continuous background drift across view transitions.

### `Kotek/Features/` — feature-oriented UI modules

- **`Calibration/`**:
  - `KeyCountView.swift` — step 1/4: select instrument key count.
  - `FramingView.swift` — step 2/4: live preview framing guide.
  - `AligningView.swift` — step 3/4: drag and resize key rectangles over real bilah.
  - `CalibrationView.swift` — step 4/4: acoustic baseline learning (voice profile).
- **`Detection/`** (Diagnostics & Training):
  - `AudioTestView.swift` — onset gate and acoustic noise floor test.
  - `MalletTestView.swift` — raw per-frame vision hit probabilities.
  - `DetectionTestView.swift` — real-time fused vision + audio pipeline test.
  - `CaptureTrainingView.swift` / `TrainingCapture.swift` — harvest labelled crops through the inference path.
- **`Onboarding/`**:
  - `WelcomeView.swift` — landing screen and flow entry.
  - `PermissionsView.swift` — camera and microphone authorization.
  - `SplashView.swift` — launch animation masking preloader warm-up.
  - `OnboardingView.swift` — introduction carousel with Lottie animations.
  - `GuideView.swift` — contextual help cards.
- **`Play/`** (The Core Practice Loop):
  - `ChooseKotekanView.swift` — select kotekan figure.
  - `PlayView.swift` — live camera feed + overlay, scoring, tempo controls, and voice muting.
  - `PlayEngine.swift` — display-link-driven timing loop, judgement windows, and cue firing.
  - `OverlayView.swift` — primary guidance drawn on the bilah via single `Canvas`.
  - `NotesRiver.swift` — secondary piano-roll strip showing both halves against the cycle.
  - `PracticeCoach.swift` — in-session interactive feature tour.
  - `ResultsView.swift` — post-session accuracy score, streak, and landed notes.
  - `DisplayLink.swift` — `CADisplayLink` frame driver.
- **`Settings/`**:
  - `SettingsView.swift` — options, calibration triggers, diagnostic screen navigation.
  - `ChooseInstrumentView.swift` — multi-instrument profile picker.

### `Kotek/Resources/` — static assets

- `Assets.xcassets` — colors, ornaments, photos, wordmark, and logo.
- Audio: `gong.wav`, `kajar.wav`, `kempur.wav`, `key0.wav`–`key9.wav`, `bgm.m4a`.
- Fonts: `Dream Orphans` font family (headers/titles; body uses SF).
- Lottie: `polos.lottie`, `sangsih.lottie` (interlocking figure visualizers).
- App Icon: `logo-kotek.icon`.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
