# Gomelan

An iPhone app that turns a real Balinese *gangsa* into a guided practice surface. Notes fall
onto a drawn gangsa (the waterfall) and say what to play next; a strike controller — a sensor
under each bilah — reports which bilah you struck and when, and that is what is scored.

It started as a camera app: the phone on a stand above the instrument, vision naming the
bilah and the microphone timing it, an overlay on the live feed. That camera play mode — its
setup screens, its tests, the vision pipeline and its Core ML models — was taken out in
November 2026. Comments that mention it are history; there is no camera in the app.

Product name is **Gomelan**; the Xcode target, folder and bundle name are **`Kotek`**.
(Some older references in the repo use `gomelan` as the target name — that rename is done.)

`documentation/prd.md` is the spec. Source comments cite it by section (§5.1, §13.4, …), so
read it alongside the code rather than after it.

## Build

The `.xcodeproj` is **generated and gitignored**. After changing `project.yml`, or on a fresh
clone, regenerate before building:

On a fresh clone, also run `scripts/bootstrap.sh` first. It resolves BuildTools and installs the
Claude Code hook (format, then `scripts/check.sh`, after every `xcodegen generate`) into
`.claude/settings.json` if it's missing. That folder is gitignored, so the hook can't be committed.

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

### Localization

English is the source language; Indonesian (`id`) ships alongside it. UI text lives in
`Kotek/Localizable.xcstrings`, permission prompts in `Kotek/App/InfoPlist.xcstrings`.
Build in **Xcode** to sync new strings into the catalog — `xcodebuild` on the command line
extracts them but does not write the catalog. `scripts/check-strings.sh` (run by
`scripts/check.sh`) fails on any string that is missing from the catalog or has no `id`.

- **A literal is only translated if it lands in a localizable type.** A `String`
  parameter, an untyped array (`["Watch", "Polos"]` is `[String]`) or a `String` property
  all skip the catalog silently, at extraction and at runtime.
- **In a view parameter, take `LocalizedStringKey`** (`AppButton`, `TopBar`,
  `SectionLabel`…). Callers pass literals; data (a gangsa or song name) is wrapped as
  `LocalizedStringKey(name)` so it shows as typed.
- **Outside a view** — models, services, enums, ViewModels — keep `String` and write
  `String(localized: "…")` where the text is made. Use `LocalizedStringResource` when the
  value must stay unresolved until shown but can't import SwiftUI.
- **Never interpolate a `LocalizedStringKey` into a string.** It compiles and shows
  `LocalizedStringKey(key: "…", …)` — once into a VoiceOver label. Resolve to `String` first.
- **One sentence, one literal.** Never build a sentence with `+`; put the moving parts in
  with `\(…)` so a translator can reorder them.
- **Plurals** go in the catalog (Vary by Plural) when the number is in the string. When it
  is drawn apart from its label, use two keys ("Cycle" / "Cycles").
- **Numbers** go through `.formatted()` — `Theme.percentLabel`, `Theme.tempoLabel` — never
  `"\(n)%"` or `String(format:)`, so the decimal mark follows the language.
- **One word, two meanings** gets its own key with a default value:
  `String(localized: "DampGuide.off", defaultValue: "Off")`.
- **Content is not UI.** Kotekan names and descriptions, gangsa names and anything stored
  in Supabase stay `String` and never pass through the catalog.
- Translate the meaning in context, not word for word. The `id` voice is a warm,
  encouraging teaching assistant who calls the player *kamu*; gamelan terms (gangsa, bilah,
  polos, sangsih, kajar, panggul) stay as they are.

### Architectural Principles

- **MVVM Pattern**: Clean separation of concerns with SwiftUI + Observation (`@Observable`):
  - **Model (`Kotek/Core/Models/`)**: Pure domain models (`Song`, `Kotekan`, `InstrumentProfile`, `Judgement`), global state machine (`AppState`), and persistence (`ProfileStore`). Independent of any UI framework.
  - **View (`Kotek/Features/*/`, `Kotek/App/RootView.swift`)**: Declarative SwiftUI views responsible solely for presentation, layout, visual feedback, and user interactions. Views stay thin and bind directly to observable models (`@Environment(AppState.self)`) or feature ViewModels.
  - **ViewModel (`Kotek/Features/*/`)**: Feature-scoped presentation state coordinators (e.g. `PlayEngine.swift` acting as the engine for `WaterfallPlayView`). Co-located with their features—never in `Core/`. Per Ponytail, trivial views bind directly to `@Observable` models; ViewModels are created only when complex presentation state, high-frequency frame drivers (CADisplayLink), or multi-service orchestration requires one.
  - **Services (`Kotek/Core/Audio/`, `Kotek/Core/Sensor/`)**: Headless hardware and audio infrastructure services (`AudioEngineController`, `AudioSessionManager`, `CuePlayer`, `GangsaSensor`). Manage the strike controller's Bluetooth link, mic taps and FFT/DSP pipelines off the UI thread; injected from `RootView`.
- **Scope & Placement (Core vs. Features)**:
  - **`Core/` is strictly for shared types**: Classes, structs, enums, domain models, headless services, and UI styling in `Kotek/Core/` must be genuinely shared across multiple screens or features.
  - **Single-view types belong in `Features/`**: If a class, struct, enum, ViewModel, or helper is used by only one view or feature (e.g. `KeyRenderState`, `CycleNote`, `Floater` in `Features/Play/`), keep it strictly within that feature module. Never pollute `Core/` with single-use types or premature abstractions.
- **DRY Principle (Don't Repeat Yourself)**:
  - Single source of truth for app state (`AppState`), the strike controller's connection (`RootView` / `GangsaSensor`), and audio routing (`AudioSessionManager`).
  - Shared design tokens, styles, and controls live in `Kotek/Core/UI/` (`Theme.swift`, `Components.swift`, `PatternBackground.swift`) to eliminate visual and behavioral redundancy.
  - Core DSP algorithms (`Kotek/Core/Audio/DSP/`) are shared, centralized services — never re-implemented inside feature screens.
- **SOLID Principles**:
  - **Single Responsibility**: Each class, actor, and view has a single well-defined job. E.g., `FFTProcessor` only computes FFT magnitudes; `OnsetDetector` identifies spectral flux peaks; `NoteClipCapture` records one bilah's sound; Views only describe UI.
  - **Open/Closed**: Open for extension without modifying core logic. Instrument tuning is profile-driven (`InstrumentProfile`), kotekan figures are data-driven, and new feature views can be added without altering the audio engine.
  - **Liskov Substitution**: Protocols and polymorphic types remain strictly substitutable and honor their contracts across asynchronous and actor boundaries.
  - **Interface Segregation**: Lean, cohesive interfaces (e.g. separate playback vs. sensor link vs. DSP analysis; no bloated "god" objects).
  - **Dependency Inversion**: Feature views depend on injected controllers and services (`audio`, `cue`, `sensor`, `@Environment(AppState.self)`) passed down from `RootView`, rather than hardcoded global singletons.
- **Ponytail Philosophy (Pragmatic Senior Dev / YAGNI)**:
  - Build the minimum that works cleanly. Before adding code: does it need to exist at all? Does the standard library or SwiftUI native feature do it? Can it be one line?
  - No unrequested abstractions, no ceremonial protocols with only one implementation, no boilerplate ViewModels for trivial views.
  - Single-use classes, structs, enums, and ViewModels stay co-located with their view in `Features/`; do not promote them to `Core/` until a second feature actually requires them.
  - Mark intentional simplifications with a `// ponytail:` comment.

## Architecture

The strike controller answers both questions — **which key, and when**: each sensor sits under
one bilah (`InstrumentKey.sensorInput`), so a strike arrives already named and timed, and
`PlayEngine` judges it against the pattern. A key without a sensor is never heard, so its notes
count as missed. (The camera
era's split — vision for *which key*, audio for *when*, `StrikeFusion` reconciling them — went
with the camera. The audio key-identification it leaned on, `KeyDecomposer` and the
strike-sound baseline in `AudioEngineController`, has no caller left.) The microphone's job
now is recording each bilah's own sound (`NoteClipCapture`) and voice commands.

The codebase is organized into four main directories:

```
Kotek/
├── App/          # Application entry point, window management, and root container
├── Core/         # Shared domain models, audio DSP/playback, the strike controller, and UI styling (strictly shared types)
├── Features/     # Feature-oriented UI modules (Views, feature logic, local engines, and single-view types)
└── Resources/    # Static assets: images, audio samples, fonts, and lottie animations
```

### `Kotek/App/` — application lifecycle and root container

- `KotekApp.swift` — `@main` application struct, initializes audio session for playback at launch, and configures landscape-locked `AppDelegate`.
- `RootView.swift` — hosts the `AppState` state machine, owns shared services (`audio`, `cue`, `preloader`), renders the persistent `PatternBackground`, manages overlays (`GuideView`, `OnboardingView`, `SplashView`), and points the strike controller at the active gangsa.
- `Info.plist`, `Kotek.entitlements`, `PrivacyInfo.xcprivacy`.

### `Kotek/Core/Models/` — domain models, state, and persistence

| File | Role |
|---|---|
| `AppState.swift` | The app state machine (`AppState.Screen`), profile selection, kotekan session configuration, practice parameters, and result tracking. |
| `Kotekan.swift` | The domain core. Two 16-slot grids (*polos* on the beat, *sangsih* off it) over one gong cycle; `makeSong` renders the chosen half over N cycles. |
| `InstrumentProfile.swift` | Per-instrument keys: sensor inputs, recorded sounds, pitches. (Key rects and the strike baseline are still stored — old profiles round-trip — but nothing reads them since the camera went.) |
| `Song.swift`, `Judgement.swift` | Note sequence; timing windows and strike evaluation logic. |
| `ProfileStore.swift` | snake_case JSON persistence in Documents, round-tripping with the bundled profile format. |
| `ResourceLoader.swift` | Bundled profile and songs loader with embedded fallback strings. |
| `Preloader.swift` | Launch-time warming behind the splash: 13 WAV decodes. What is *not* preloaded (the audio engine) is deliberate. |
| `Defaults.swift` | UserDefaults storage for settings. |

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
  - `KeyDecomposer.swift` + `NNLS.swift` — polyphonic counterpart solving ringing bronze superposition; it calibrated itself from confident vision strikes, and has had no caller since the camera went.
  - `SpectralFlux.swift` — half-wave rectified spectral flux (energy increases only) preventing sustained notes from re-triggering.
  - `OnsetDetector.swift` — dynamic threshold peak detector with noise-floor tracking.
  - `SampleRing.swift` — lock-free ring buffer holding audio history.
  - `DSPConfig.swift` — mirrors `Config` in the reference gamelan DSP implementation.
  - `CalibrationFile.swift` — binary format for pitch/strike calibration recordings.
- **`Playback/`**:
  - `CuePlayer.swift` — metronome, reference tones, hit/miss synthesis.
  - `KajarTick.swift` — dedicated low-latency `AVAudioPlayer` pool for button feedback (`AppButtonStyle`, `AppToggleStyle`).
  - `SampleLibrary.swift`, `PCMWav.swift`, `SplashChime.swift`, `TitleMusic.swift`.
- **`Session/`**:
  - `AudioSessionManager.swift` — hardware session configuration (`.measurement` mode disables AGC and echo cancellation).

### `Kotek/Core/UI/` — design system and shared visual components

- `Theme.swift` — the palette is **Nawa Sanga** (the designer's design system, Nov 2026), each colour an asset named in Balinese: `Merah` #E14B2F (`primary`: the one way on per screen, and polos), `Kuning` #F5B331 (`secondary`/`gold`: reward, a hit, what is selected — a fill, never type; gold words use `goldText`), `Ireng` #1E2435 (`tertiary`: text, headings, the selected chip, damp), `Putih` #FBF6EE (the canvas), `SangsihBlue`, `Pandan` (`ok`: sensor on, switches), `Kayu` (bilah tiles), `MerahTua` (the primary's tactile edge, `destructive`, misses), `Krem` (`deep`: quiet surfaces), `Garis` (`hairline`: outlines, the secondary's edge), plus `Surface` white for raised things. Old token names (`cream` = body text, `copper` = gold, …) are kept and repointed. Also corner radiuses, typography (Katibeh headings, SF Pro Rounded body), button metrics.
- `Buttons/` — every control, one type per file: `AppButton` (labelled), `AppIconButton` (one symbol), `AppSwitcher`, `AppMenuPicker`, `AppStepper`, plus `AppButtonSize` (the one size/type scale) and `AppControlSurface` (the surface: SOLID and TACTILE, no Liquid Glass, so the design builds on Android too). Four prominences: `.primary` Merah on a Merah tua edge (one per screen), `.secondary` white outlined and edged in Garis, `.quiet` flat Krem (stepper ±, a tool that is off), `.selected` flat Ireng (the chip/tool that is on). An edged control sinks onto its base while pressed — `AppButtonStyle` passes the press down as `controlPressed`; `.tactile(...)` is the same face-on-a-base look for anything else. A circle is `size.height` square whatever glyph it holds. One `AppButtonSize` per bar (footers/headers `.regular`, strips over the camera `.compact`, `.large` only for a lone hero button). `AppSwitcher` has two looks: `.toggle` (a white thumb on a Krem track) and `.pills` (chips, the chosen one `.selected`). Switches are drawn by `AppToggleStyle` (Pandan on, Garis off). Use `.appPlain` for what you tap that is not a control (cards, grid cells).
- `Components.swift` — toggle style, top bar, dialogs, and typography helpers.
- `KipliGuide.swift` — Kipli the mascot as the app's guide: face + the outlined speech bubble (white, ringed in Ireng, on a Garis edge), `.hint` (bottom-left, the default), `.intro` (empty states), `.quiet` (a small face; the bubble opens at his right, over the layout, and closes itself — the kotekan picker, under its header, and the waterfall's top-left corner in Learn and free play), `.drop` (bubble below — Learn's Watch header). Moods happy / sad / angry (`KipliFace`), his mouth working while the words type out; sad in the delete, sign-out and switch-account dialogs (`confirm(kipli:)`) and on a low score. What he says on the waterfall, and when, is `WaterfallPlayViewModel.kipli` (see its MARK: Kipli). The words type themselves out (`Typewriter`, a `TextRenderer` drawing a glyph at a time, so the bubble never resizes). Screens explain through him, in his voice. The face is the one place an animated Kipli will plug in.
- `SetupHeader.swift` — "Step N of 3" header for adding a gangsa (key count → note capture → sensors); bars fill Merah up to the current step.
- `PickerCard.swift` — `.pickerCard(selected:)`, the gangsa and kotekan rails' card: white; selected is ringed in gold on a deeper gold edge with tumpal triangles along the top, clipped by its corners (only the selected card wears them; a big red tooth inside each on a gangsa card, a fleck on a kotekan card).
- `LaunchLayout.swift` — the redesign's unit: mockups are 1x on 874 x 402, scaled by height.
- `PatternBackground.swift` — the ground: cream, with the launch gate's silhouette (`pura-gate` in beige) reaching in from each side. Still — the redesign has no ambient motion.

### `Kotek/Features/` — feature-oriented UI modules

- **`Calibration/`**:
  - `KeyCountView.swift` — adding a gangsa, step 1/3: name, photo, bilah count.
- **`Detection/`**:
  - `Capture/NoteCaptureView.swift` — adding a gangsa, step 2/3: record each bilah's own sound.
  - `Sensor/SensorPlayView.swift` — Debug: the strike controller's raw strikes against a pattern.
- **`Controller/`**: `ControllerSetupView` — adding a gangsa, step 3/3: pair the strike controller and check each key's sensor.
- **`Create/`**: the piano-roll composer. Its tools (colotomic instruments, eraser) are named chips in the top row beside the Polos / Sangsih pills; snap and the typed BPM sit in the bottom transport.
- **`Onboarding/`**:
  - `WelcomeView.swift` — landing screen and flow entry. `Penjor.swift` — the bamboo pole arching in from each gate post (`janur-pole`) with its sampian (`janur-hang`) swinging from the tip; laid out at the landing's camera, so the gate reveals it. Easter egg: `HangTilt` (Core Motion gravity, no permission) keeps each sampian hanging towards the real ground as the device tilts, and a sideways jolt swings it.
  - `SplashView.swift` — launch animation masking preloader warm-up: Kipli chomping (`KipliMascot`) before the turning nawa sanga rose (`nawasanga`; Core Animation while loading, SwiftUI from the pan, on one clock), a camera pan past it over a strip of bare paper down to a distant split gate (`PuraGate`), and a walk up to it as it opens on the landing screen.
  - `OnboardingView.swift` — introduction carousel with Lottie animations.
  - `GuideView.swift` — contextual help cards.
- **`Play/`** (The Core Practice Loop):
  - `ChooseKotekanView.swift` — select kotekan figure.
  - `Waterfall/WaterfallPlayView.swift` — notes falling onto the drawn gangsa; scored from the strike controller. `WaterfallCanvas` draws each note as the designer's pills: a short stroke pill in the voice colour, a cream stem as long as the note, outlined in beige and capped where it ends with a short beige damp block, the stem's width; all land on the gangsa's rail, the one hit line, and a hit glows gold up its lane.
  - `Learn/LearnView.swift`, `Coop/` — a pattern taught in steps; two players, one screen.
  - `PlayEngine.swift` — display-link-driven timing loop, judgement windows, and cue firing.
  - `Components/NotesRiver.swift` — piano-roll strip of both halves against the cycle (the sensor test's).
  - `Results/ResultsView.swift` — the session's result: cycles, time and accuracy (or top tempo with no sensor), Kipli giving the Apple Intelligence feedback. `Results/Polish/` — "Where to polish": the late, early, wrong-bilah and missed strokes on one pass of the roll, each explained by Kipli.
  - `DisplayLink.swift` — `CADisplayLink` frame driver.
- **`Settings/`**:
  - `SettingsView.swift` — a sidebar of pages: the gangsa in play only (sounds, controller; another is edited by switching to it), Practice, Account, Debug.
  - `ChooseInstrumentView.swift` — multi-instrument profile picker.

### `Kotek/Resources/` — static assets

- `Assets.xcassets` — colors, ornaments, photos, wordmark, and logo.
- Audio: `gong.wav`, `kajar.wav`, `kempur.wav`, `key0.wav`–`key9.wav`, `bgm.m4a`.
- Fonts: `Katibeh` (headers/titles, one weight; body uses SF). Colours are in the asset catalog under their Nawa Sanga names (`Merah`, `Kuning`, `Ireng`, `Putih`, `SangsihBlue`, `Pandan`, `Kayu`, `MerahTua`, `Krem`, `Garis`) plus `Surface`, `PatternBackground`, `DescriptionText`, `BrandRed` (the wordmark's own red) and the landing gangsa's `KeyHighlight`/`KeyDampened`, read by `Theme`. Mascot: `kipli-head` + `kipli-mouth` (splash); the guide's moods, each shut and open (`kipli-happy`, `kipli-sad`, `kipli-angry`, plus `-open`).
- Lottie: `polos.lottie`, `sangsih.lottie` (interlocking figure visualizers).
- App Icon: `logo-kotek.icon`.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
