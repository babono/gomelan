# Gomelan — Product Requirements Document

**Version:** 0.6 (adds the strike controller — 14 inputs, shared between gangsa, stored on Supabase: §3.6, Flows D–E, §7, §8, §13.5)
**Platform:** iOS 17+, iPhone only
**Instrument:** Gangsa (gong kebyar family) — single mallet, monophonic, one bundled profile
**Status:** Implemented and running end-to-end on placeholder data — awaiting the physical instrument for real calibration values

---

## 0. Implementation Status (as of v0.5)

The full v1 architecture described in this document is built and compiles clean. The app runs the entire flow — welcome → permissions → framing → alignment → song list → play/practice → results — against a bundled placeholder profile. What remains is real instrument data and a handful of Phase 5 items.

**Built and working:**
- App state machine (`Kotek/Core/Models/AppState.swift`), models, `ProfileStore` persistence to Documents (snake_case JSON, round-trips with the bundled shape)
- Camera capture with focus/exposure lock (`Kotek/Core/Vision/CameraController.swift`)
- Real-time audio pipeline: spectral-flux `OnsetDetector` + FFT `KeyClassifier` via `FFTProcessor` (vDSP), fed by `AudioEngineController` (`Kotek/Core/Audio/DSP/`)
- `PlayEngine` (`Kotek/Features/Play/PlayEngine.swift`) — play + practice modes, timing/judgement, approach track, damp hints, cue triggering
- Peripheral `OverlayView` (`Kotek/Features/Play/OverlayView.swift`), all screens, `CuePlayer` (`Kotek/Core/Audio/Playback/CuePlayer.swift`) (synthesized cues)
- **In-app pitch calibration / baseline** (`Kotek/Features/Calibration/CalibrationView.swift`), reachable from Settings — see §2 note; this went from "dev-only" to shipped
- Manual drag/resize key alignment (`Kotek/Features/Calibration/AligningView.swift`)

**Placeholder — needs the physical instrument:**
- Bundled profile is a **10-key** placeholder (`Kotek/Core/Models/ResourceLoader.swift`): lower five fundamentals use the §6.3 measured pelog intervals, keys 5–9 an octave up; rects are graduated tall→short with ~1cm gaps. Real pitches/rects come from calibrating on the instrument.
- **Two** placeholder songs, not one: "First Run" (5 keys, §13.6) and "Full Run — All Keys" (10-key up-down run, doubles as the §6.3 all-keys detection check). Real first exercise still to come from Mekar Bhuana (§11 Q1).
- Cue tones are synthesized sines; should be replaced by the instrument's own calibration samples (§5.4/§7). Calibration currently records **pitch only** — no `.caf` sample capture, no harmonic/decay re-measurement.

**Known gaps / deferred:**
- Output ducking around strike windows (§5.4) is a TODO hook only
- Overlay maps normalized rects straight to view bounds (assumes aspect-fill; no perspective correction — §3.4 deferred as intended)
- Exhibition/kiosk auto-reset mode not built (Phase 5)
- `Kotek/Core/Vision/KeyDetector.swift` (Vision rectangle detection, §6.4) exists but is **not wired into the runtime flow** — alignment is manual drag from the bundled rects

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
| Optional | Strike controller — ESP32, Bluetooth LE, plug-in piezo sensors (one per bilah) | One controller can serve several gangsa; set up once per gangsa, reconnects by itself. See §3.6 |

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

### 3.6 Strike controller (optional, shared between gangsa)

Two parts:

- **Controller** — one small box: an ESP32 with Bluetooth LE and **14 numbered inputs** (jacks), 1…14 (0…13 on the wire). Fourteen covers every gangsa size in scope (pemade and kantilan are 10 keys). The app reads the count from the controller rather than assuming 14, so a later board with more inputs needs no app change.
- **Sensors** — piezo discs, each on a lead, clipped one per bilah and plugged into an input. Sensors can be added or taken away: plug in five for a 5-key gangsa, ten for a 10-key one.

The controller does the hit detection itself — threshold, ring-down rejection, a 4 ms loudest-wins window against crosstalk between neighbouring bilah — and sends only results to the phone: *which input, how hard, and when on its own clock*. It answers both of the questions vision and audio split between them (§6), with no camera and no microphone, so it is immune to room noise and to a hand hiding the key.

**One controller, many gangsa.** A controller isn't tied to an instrument. Clip its sensors onto gangsa A today and gangsa B tomorrow. Each gangsa remembers its own setup with that controller (which input sits on which key), so moving between them doesn't need setup again (Flow E). Physically it's on one gangsa at a time, and the phone uses the app's **active instrument** to decide which gangsa's map applies.

The prototype exists (`Kotek/Features/Detection/Sensor/GangsaSensor.swift`, Settings → Sensor Test). It is hardcoded to 3 inputs, has no idea what is plugged in, and connects to *any* device named "Gangsa…". This section specifies what turns it into something a player sets up once per gangsa and then forgets.

**Transport: Bluetooth LE only. No Wi‑Fi, at setup or ever.**

| | BLE (chosen) | Wi‑Fi |
|---|---|---|
| Setup cost | None — the phone finds the controller by itself | A provisioning step: type the network password into the app, push it to the ESP32 (SoftAP or BLE provisioning), retry when it's wrong |
| Works in a *banjar* hall / outdoors / at the exhibition | Yes — phone ↔ controller directly, no router | Only where there is a network the user knows the password of |
| Moving the controller to another gangsa | Nothing to do | Nothing, unless the other gangsa is in another building on another network — then provisioning again |
| Timing | Hits are stamped on the ESP32's clock (§3.6.3), so BLE's 7.5–30 ms connection-interval jitter never reaches judgement | Same, but buys nothing extra |
| What it would be for | — | Cloud upload or firmware updates over the air. Neither is in scope; the phone is the only consumer of hits |

So setup is **scan → connect → check keys**, nothing else. "Set up" in this document means *the app remembering a controller and its key map for a gangsa* — not iOS system pairing/bonding. No PIN, no Settings → Bluetooth step.

#### 3.6.1 Identity — why the app can't just remember "the controller"

- **CoreBluetooth's peripheral `identifier` is per-phone.** The same controller has a different UUID on a second iPhone, so it cannot be the thing synced with the instrument across devices. It is kept only as a local cache, for a fast reconnect on the phone that already knows it.
- **The stable identity is the ESP32's hardware ID** (its factory eFuse MAC, 6 bytes). The firmware exposes it two ways:
  - in the advertised name as a suffix, `Gangsa-Sensor-E5F6` (last 2 bytes), so controllers can be told apart in the scan list *before* connecting;
  - in full, in a readable **INFO** characteristic.
- The full hardware ID is what is stored on each gangsa set up with it (§7), and synced. On a new phone, the app scans for the name suffix, connects, reads INFO, checks the full ID, and only then caches that phone's `identifier`.

A room with a whole *gamelan* in it can have several controllers. Connecting to the first thing named "Gangsa…" — the prototype's behaviour — would steal a neighbour's. Once set up, the app connects **only** to the hardware ID the active gangsa was set up with.

#### 3.6.2 Controllers and gangsa

- **A controller → many gangsa.** Any number of the user's gangsa can be set up with the same controller. Setting it up on gangsa B never touches gangsa A's map.
- **A gangsa → one controller.** Each gangsa remembers one. Setting up a different controller on it replaces the old one (for that gangsa only).
- **One phone at a time.** The ESP32 stops advertising while connected, so a second phone can't take it mid-session. Nothing needs to enforce that across accounts.

#### 3.6.3 Which inputs are plugged in

**The controller is the only source of this.** It detects which inputs have a sensor in them and sends that to the app; the app never guesses it from hits. Plug detection is a **later hardware revision** (a plug-detect pin on each jack), so the spec has two stages:

| | Now — no plug detect | Later — plug-detect jacks |
|---|---|---|
| What the controller sends | INFO says *plug detect: no*; no INPUTS notifications | INFO says *plug detect: yes* and the plugged-in bitmask (bit n = input n has a sensor); INPUTS notifies on every plug / unplug |
| Hits on empty inputs | Can't tell they're empty — sent like any other | Ignored by the controller (a loose lead flapping against the frame can't fire) |
| Setup (Flow D) starting map | Inputs 1…N → keys 1…N; the player marks any key with no sensor ("No sensor here") | The k-th *plugged-in* input → key k; keys past the last sensor start as "no sensor" |
| Re-check (Flow E) | Never automatic — "Check keys" in Settings only | Automatic when the plugged-in set differs from the one saved for this gangsa |
| `instruments.controller_inputs` (§7) | `null` | the plugged-in set at setup |

Same app build for both: it branches on the INFO flag, so the new board needs no app update, and gangsa set up before it simply get their `controller_inputs` filled in at their next re-check.

With plug detect, the app compares the set with the one the active gangsa was set up with. **Different set → the saved map can't be trusted → ask for a re-check** (Flow E). Same set → trust it. Comparing the set rather than just the count also catches the same five sensors moved to different jacks — which changes every key, but not the count.

#### 3.6.4 Firmware protocol (changes from the prototype)

Service `7A1F0001-…` unchanged. Characteristics:

| Char | Dir | Payload | Status |
|---|---|---|---|
| `…0002` EVENT | notify | 8 bytes: `[0]` type (1 = hit, 2 = damp, reserved) · `[1]` **input** 0…13 · `[2–3]` strength 0…4095 LE · `[4–7]` ESP32 `millis()` LE | exists; byte 1 is now an *input*, not a key (§3.6.5) |
| `…0003` LEVEL | notify | 14 bytes (one per input), 0…255 vibration level, 50 Hz; empty inputs read 0 once plug detect exists | exists; length becomes the input count instead of a fixed 3 |
| `…0004` INFO | read | `[0–5]` hardware ID · `[6]` input count (14) · `[7]` flags, bit 0 = has plug detect · `[8–11]` plugged-in bitmask LE (0 without plug detect) · `[12]` protocol version · `[13…]` firmware version string | **new** — needed now |
| `…0005` INPUTS | notify | 4 bytes, plugged-in bitmask LE — sent on every plug / unplug | **new** — with the plug-detect board |

The app reads the input count and the plugged-in set instead of the hardcoded `barCount = 3`. The bitmask is 32 bits so a bigger board fits without a protocol change.

#### 3.6.5 Inputs are not keys

The firmware only knows *input 3 fired*. Which bilah that sensor is clipped to is the player's doing, and it differs per gangsa. The **input → key index map** is checked in setup (Flow D) and stored **per gangsa** — that is what lets one controller serve many instruments. Everything downstream still addresses bilah by key index (the rule in §7: key indices, never pitches — and now never inputs either).

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

### Flow D — Controller setup (once per gangsa)

Reached two ways: as an optional last step when registering a new gangsa ("Got a strike controller? Connect it now · Skip"), and any time later from the gangsa's row in Settings → Instruments ("Connect controller"). Optional either way — a gangsa without one works exactly as before, on camera + mic. Prerequisite: the instrument exists, so its key count is known.

Run once for each gangsa a controller is used on. The same screen, from step 5, is the **re-check** that Flow E opens when the plugged-in sensors change.

```
1. Start        → "Switch the controller on, clip a sensor onto each bilah and plug them in"
2. Scanning     → list of nearby controllers by name (Gangsa-Sensor-E5F6), nearest first (RSSI);
                  ones already set up with your other gangsa say so ("Also on Gangsa Pemade") —
                  information only, using it here takes nothing away from them
3. Connect      → user taps one → connect → read INFO
4. Summary      → controller inputs  : 14
                  sensors plugged in : 5 (inputs 1–5)   live — only with plug detect (§3.6.3)
                  instrument keys    : 5 keys           (from the profile)
                  [Test key hits]
5. Test & remap → "5 sensors detected — hit the key"
                  a row of tiles, one per bilah, in key order (1 … N), plus [Finish]
                  Starting map: input k → key k — with plug detect, the k-th *plugged-in* input
                  (§3.6.3) — i.e. the order the sensors are meant to be clipped on. On a re-check, the saved map instead,
                  with removed inputs cleared and new ones filled into keys without a sensor.
                  a. the app highlights the next unchecked key, say key 3
                  b. the player hits that bilah; input i fires
                  c. map[i] = key 3 → match: tile 3 turns green ✓, move on to key 4
                  d. map[i] = key 5 → mismatch: tile 5 lights instead, tile 3 shows
                     "Heard as key 5" and offers [Remap] · [Try again]
                       Remap     → swap: input i moves to key 3, and key 3's old input
                                   (if any) moves to key 5. Tile 3 turns green; tile 5 goes
                                   back to unchecked, to be confirmed when its turn comes.
                       Try again → nothing changes (the stroke was meant for another bilah)
                  e. tap any tile to re-check it, or mark it "No sensor here" (camera + mic);
                     without plug detect this is how a key with no sensor is said
                  f. with plug detect, a sensor plugged in mid-test joins the next key without one, unchecked;
                     one pulled out leaves its key without a sensor
6. Finish       → enabled when every key is green or marked "No sensor here".
                  Saves the controller, its plugged-in set and the map on *this* gangsa — to
                  Supabase (§7), and to the phone for offline play.
```

**Why assume, then check.** The sensors are meant to be clipped on in input order, so most of the time the starting map is right and the player is only confirming it — hit 1, 2, 3, 4, 5, done. A mismatch shows exactly what went wrong ("key 3 was heard as key 5"), which also points at a lead in the wrong jack. Remapping is a swap rather than a reassign, so the map can never end up with one input on two keys.

**Sensors ≠ keys.**
- More sensors than keys: the extras start unmapped; their hits are ignored, except that a hit from one during the test offers [Remap] onto the key being tested.
- Fewer sensors than keys: Finish is allowed. The keys left without a sensor are shown greyed ("camera + mic") and fall back to camera + mic in Play. Plug more in later and the re-check (Flow E) picks them up.

**Errors.** Bluetooth off / permission denied → the existing `GangsaSensor.Status.unavailable` message with a Settings link. Nothing found after ~10 s → "Is it switched on? Is another phone connected to it?" (the ESP32 stops advertising while connected). With plug detect, no sensors plugged in → step 4 says so and holds. Disconnect mid-test → keep the keys checked and remapped so far, resume when it comes back.

### Flow E — Automatic reconnect (every session after setup)

No UI in the happy path — the controller simply is connected whenever a gangsa set up with it is the active instrument.

```
1. App foregrounds, or the active instrument changes
2. Active gangsa has a controller?
     no  → disconnect any controller; camera + mic as today
     yes, and it's the one already connected → keep the connection, swap in this gangsa's map
          (A → B with the same controller is instant: no reconnect)
     yes, a different one → disconnect the current one, go on
3. This phone has a cached CoreBluetooth identifier for that hardware ID?
     yes → retrievePeripherals(withIdentifiers:) → connect
     no  → scan for Gangsa-Sensor-<suffix> → connect → read INFO → hardware ID matches?
             yes → cache the identifier for next time
             no  → disconnect, keep scanning
4. Controller has plug detect (INFO flag)?
     no  → ready, with the saved map (re-check is manual: Settings → "Check keys")
     yes → compare the plugged-in set with the one saved on this gangsa (`controller_inputs`)
           same      → ready
           different → banner: "Sensors changed since Gangsa A was set up (5 → 6) · Check keys"
                       → Flow D step 5 as a re-check. Until it's done, Play uses the saved map for
                         inputs that are still plugged in; other keys fall back to camera + mic.
           none saved (set up before plug detect) → the same banner, once, to record the set
5. Connected → small status dot (Play, Settings): connected · searching · off
6. INPUTS notification (sensor plugged / pulled; plug-detect board only) → step 4 again
7. Dropped   → connect() again immediately. A pending CoreBluetooth connect never times out,
               so the controller rejoins on its own the moment it is back in range or powered on.
```

**The app can't see which gangsa the controller is clipped onto** — only the active instrument says so. Same set of sensors on gangsa B while A is active → A's map is used. Mitigation: the active gangsa's name is next to the status dot, and Settings has "Check keys" for any gangsa. ponytail: no detection beyond that until it proves to be a real mistake.

Foreground only — the app is a landscape practice surface with no reason to hold the controller in the background, so no `bluetooth-central` background mode and no state restoration. ponytail: add them only if a reconnect on foreground proves too slow.

Settings → Instruments → the gangsa: "Check keys" (Flow D step 5 on demand), "Forget controller" (this gangsa only — others using it keep theirs), and "Connect controller" again to switch to a different one.

### Controller in Play

When the active gangsa's controller is **connected**, it replaces camera + mic as the strike source:

- A new `AppState.DetectionMode` case, **Sensor**, selected automatically while connected and handed back to the player's previous mode when it drops. The Settings picker shows it, disabled, when nothing is connected.
- Each EVENT hit → `map[input]` → `PlayEngine.registerStrike(keyIndex:hostTime:confidence: 1)`, with `hostTime` from the controller-clock offset `GangsaSensor` already estimates. Hits from unmapped inputs are dropped.
- Keys with no sensor keep using camera + mic for **those keys only**. If every key has a sensor, the camera and mic detection paths are not started at all — the camera feed stays as the overlay's background.
- A drop mid-session falls back to camera + mic without stopping play; the status dot (Flow E step 5) says so. A sensor plugged in or pulled out mid-session does the same for the affected key, and the re-check banner waits for the end of the session.

`GangsaSensor` moves from `Features/Detection/Sensor/` to `Core/` when this lands — its own ponytail note says to, once `PlayView` takes sensor strikes.

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
| Language & platform | Swift, iOS 26.5, iPhone-only, landscape-locked | `Kotek/App/KotekApp.swift`, `AppDelegate` |
| UI | SwiftUI | all of `Kotek/Features/`, `Kotek/Core/UI/`, `Kotek/App/RootView.swift` |
| State | Observation (`@Observable`, `@Environment`) — **not** Combine | `Kotek/Core/Models/AppState.swift` |
| Camera preview | AVFoundation via `UIViewRepresentable` | `Kotek/Core/Vision/CameraPreview.swift` |
| Camera capture | AVFoundation (`AVCaptureSession`, back wide camera, focus/exposure lock) | `Kotek/Core/Vision/CameraController.swift` |
| Audio I/O | AVAudioEngine (mic tap + cue playback) | `Kotek/Core/Audio/DSP/AudioEngineController.swift`, `Kotek/Core/Audio/Playback/CuePlayer.swift` |
| Audio session | AVAudioSession (`.playAndRecord` / `.measurement`) | `Kotek/Core/Audio/Session/AudioSessionManager.swift` |
| DSP | Accelerate / vDSP (FFT magnitude spectrum) | `Kotek/Core/Audio/DSP/FFTProcessor.swift` |
| Detection | Custom spectral-flux onset + nearest-neighbour / decompose | `Kotek/Core/Audio/DSP/OnsetDetector.swift`, `KeyClassifier.swift`, `KeyDecomposer.swift` |
| Vision & ML | CoreML + Vision (`MalletDetector.mlmodel`, `BilahFinder`, `StrikeFusion`) | `Kotek/Core/Vision/` |
| Play-loop timing | `CADisplayLink` (QuartzCore) | `Kotek/Features/Play/DisplayLink.swift`, `Kotek/Features/Play/PlayEngine.swift` |
| Persistence | `Codable` + JSON to Documents (snake_case) — no SwiftData / Core Data / backend | `Kotek/Core/Models/ProfileStore.swift`, `Kotek/Core/Models/ResourceLoader.swift` |
| Concurrency | Swift `async`/`await`, `Task`, `actor` (Combine deliberately avoided) | throughout |
| Animation / Lottie | Lottie iOS (interlocking dotLottie player) | `Kotek/Features/Onboarding/` |

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

**Strike controller (§3.6, Flow D) — stored on Supabase.** Controllers, which gangsa uses which, and each gangsa's input → key map live in real tables and columns, not in the `profile` jsonb. They are what a second phone, or a second gangsa, reads back. Three pieces, matching the three relationships:

| Relationship | Where | Why there |
|---|---|---|
| A controller exists, and it's yours | new table `controllers`, one row per (user, hardware ID) | Shared by many gangsa, so it can't live on any one of them |
| This gangsa uses that controller (many gangsa → one controller; one controller per gangsa) | `instruments.controller_id` → `controllers.id` | A foreign key is exactly "at most one per gangsa, shared freely" — no join table needed |
| On this gangsa, input 3 is on key 0 | `instrument_keys.sensor_input` | The map is per key *and* per gangsa, which is what that table already is |

```sql
-- Additive and re-runnable, like the other migrations: v1 clients are live.
create table if not exists public.controllers (
    id               uuid primary key default gen_random_uuid(),
    user_id          uuid not null references auth.users (id) on delete cascade,
    hardware_id      text not null,              -- ESP32 eFuse MAC, 12 hex chars, uppercase
    name             text not null,              -- as advertised: Gangsa-Sensor-E5F6
    input_count      smallint not null default 14,
    has_plug_detect  boolean not null default false,
    firmware_version text,
    created_at       timestamptz not null default now(),
    unique (user_id, hardware_id)
);
alter table public.controllers enable row level security;
create policy "controllers: owner" on public.controllers
    for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

alter table public.instruments
    add column if not exists controller_id uuid references public.controllers (id) on delete set null,
    add column if not exists controller_inputs smallint[],      -- plugged-in set at setup; null = no plug detect
    add column if not exists controller_set_up_at timestamptz;

alter table public.instrument_keys
    add column if not exists sensor_input smallint check (sensor_input between 0 and 31);  -- null = no sensor
```

- **Saving (Flow D Finish):** upsert `controllers` on `(user_id, hardware_id)` → its `id` → update the instrument's three `controller_*` columns → upsert `instrument_keys.sensor_input` for every key, `null` included. The keys upsert sends an explicit null for the same reason `InstrumentKeyRow` already does for `base_hz`. `input_count`, `has_plug_detect` and `firmware_version` are refreshed from INFO on every save, so moving to the plug-detect board updates the row.
- **Restoring (second phone):** `fetchInstruments` also selects `controller_id`, `controller_inputs`, the joined `controllers.hardware_id` / `name`, and each key's `sensor_input`. The hardware ID is what Flow E scans for.
- **Offline:** the phone keeps a copy in its local profile so a session works with no network. Supabase is the record; the local copy is overwritten by what comes back. Saves made offline go up on the next sync, as instrument saves do today.
- **Forget controller** (one gangsa): `controller_id`, `controller_inputs`, `controller_set_up_at` → null, and every key's `sensor_input` → null. The `controllers` row stays — the controller is still yours, other gangsa may use it, and the next scan still labels it.
- **Deleting a gangsa** leaves its controller alone, for the same reason. **Deleting the account** removes `controllers` too: add it to the `delete-account` Edge Function and give `service_role` `select, delete` on it, as `20261012020000_service_role_delete_grants.sql` does for the other tables.
- **`instrument_keys.sensor_id`** (the hand-made column `InstrumentKeyRow` already avoids) is left unused rather than renamed: its type was never recorded, and v1 clients are live. `sensor_threshold` stays reserved too — thresholds live in the firmware for now *(open question — §11)*.
- **Not on Supabase:** the phone's CoreBluetooth `identifier`. It differs per phone (§3.6.1), so it is cached in `UserDefaults`, keyed by hardware ID. One entry serves every gangsa that controller is used with.

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

As built, screens map 1:1 to `AppState.Screen` cases and are hosted by `RootView` (`Kotek/App/RootView.swift`).

| Screen | State case | Module Location | Purpose |
|---|---|---|---|
| Welcome | `.welcome` | `Kotek/Features/Onboarding/WelcomeView.swift` | Entry, setup prompt, first-run introduction |
| Permissions | `.checkingPermissions` / `.permissionsBlocked` | `Kotek/Features/Onboarding/PermissionsView.swift` | Request camera + microphone permissions; live preview |
| Choose Instrument | `.chooseInstrument` | `Kotek/Features/Settings/ChooseInstrumentView.swift` | Select or switch instrument profiles |
| Key Count | `.choosingKeyCount` | `Kotek/Features/Calibration/KeyCountView.swift` | Setup step 1/4: specify number of bilah (keys) |
| Framing | `.framing` | `Kotek/Features/Calibration/FramingView.swift` | Setup step 2/4: position gangsa inside guide overlay |
| Alignment | `.aligning` | `Kotek/Features/Calibration/AligningView.swift` | Setup step 3/4: drag/resize key rects over real bilah |
| Acoustic Baseline | `.calibrating` / `.baseline` | `Kotek/Features/Calibration/CalibrationView.swift` | Setup step 4/4: acoustic baseline strike learning |
| Choose Kotekan | `.chooseKotekan` | `Kotek/Features/Play/ChooseKotekanView.swift` | Select kotekan figure to practice |
| Play / Practice | `.countdown` / `.playing` | `Kotek/Features/Play/PlayView.swift` | The core loop: live feed, overlay guidance, timing, tempo & voice muting |
| Results | `.results` | `Kotek/Features/Play/ResultsView.swift` | Performance summary: score, streak, accuracy, landed notes |
| Settings | `.settings` | `Kotek/Features/Settings/SettingsView.swift` | Calibration triggers, options, links to diagnostic screens |
| Audio Test | `.audioTest` | `Kotek/Features/Detection/AudioTestView.swift` | Diagnostic: onset gate and acoustic noise floor |
| Mallet Test | `.malletTest` | `Kotek/Features/Detection/MalletTestView.swift` | Diagnostic: raw vision mallet probability per key |
| Detection Test | `.detectionTest` | `Kotek/Features/Detection/DetectionTestView.swift` | Diagnostic: fused multi-modal strike detection pipeline |
| Capture Training | `.captureTraining` | `Kotek/Features/Detection/CaptureTrainingView.swift` | Diagnostic: record labelled key strike frames for ML training |
| Sensor Test | `.sensorTest` | `Kotek/Features/Detection/Sensor/SensorPlayView.swift` | Diagnostic: the BLE piezo prototype driving a kotekan with no camera |
| Controller Setup *(planned)* | `.controllerSetup` | `Kotek/Features/Controller/` | Flow D: scan → connect → summary → test & remap input→key map → finish; also the Flow E re-check |

Global overlays hosted in `RootView`:
- `SplashView`: Launch animation masking background warming.
- `OnboardingView`: Carousel introducing Balinese gamelan with Lottie animations.
- `GuideView`: Contextual pop-up guidance.

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
5. **Strike controller (§3.6, Flow D/E)** — still open:
   - **a. Thresholds.** Per-key sensitivity stays in firmware for now. If one bilah keeps missing light strokes, setup could record strength per key and write a threshold back over a CONFIG characteristic (`instrument_keys.sensor_threshold` is already reserved).
   - **b. Firmware owner.** Who adds the INFO characteristic, the hardware-ID name suffix and 14 inputs to the firmware now, and INPUTS with the plug-detect board later (§3.6.3–3.6.4)? 14 inputs is a working assumption — confirm when the board is final.
   - **c. Wrong gangsa, same sensors.** The app trusts the active instrument (Flow E). If players often forget to switch it, add a one-tap "Playing on Gangsa A?" confirm when the controller connects — only if it turns out to happen.
   - **d. Damp events.** EVENT type 2 is reserved. Once the firmware sends it, it could drive §5.5's damping judgement.

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

The project is organized into four main layers following MVVM, DRY, and SOLID principles. `Kotek/Core/` is reserved strictly for shared domain models, headless hardware/audio/vision services, and common UI tokens. If a class, struct, enum, ViewModel, or helper is used by only one view or feature, it belongs in that feature module (`Kotek/Features/<Feature>/`), never in `Core/`.

```
Kotek/
├── App/
│   ├── KotekApp.swift          // @main App, audio session init, landscape AppDelegate
│   ├── RootView.swift          // Hosts AppState, shared services, and continuous background
│   ├── Info.plist
│   ├── Kotek.entitlements
│   └── PrivacyInfo.xcprivacy
├── Core/
│   ├── Audio/
│   │   ├── DSP/                // Low-level signal processing
│   │   │   ├── AudioEngineController.swift // Mic tap, FFT trigger, strike emission
│   │   │   ├── CalibrationFile.swift       // Strike/pitch calibration serialization
│   │   │   ├── DSPConfig.swift             // Measured DSP thresholds
│   │   │   ├── FFTProcessor.swift          // vDSP FFT (numpy-identical rfft)
│   │   │   ├── Fingerprinter.swift         // 120-bin spectral shape vector
│   │   │   ├── KeyClassifier.swift         // Cosine matching for strike pitch
│   │   │   ├── KeyDecomposer.swift         // Polyphonic bronze strike decomposition
│   │   │   ├── NNLS.swift                  // Non-negative least squares solver
│   │   │   ├── OnsetDetector.swift         // Dynamic threshold spectral flux
│   │   │   ├── SampleRing.swift            // Lock-free ring buffer
│   │   │   └── SpectralFlux.swift          // Energy-increase onset flux
│   │   ├── Playback/           // Audio playback and cue triggers
│   │   │   ├── CuePlayer.swift             // Metronome, reference tones, audio feedback
│   │   │   ├── KajarTick.swift             // Button/toggle tick audio pool (.kajar)
│   │   │   ├── PCMWav.swift, SampleLibrary.swift, SplashChime.swift, TitleMusic.swift
│   │   └── Session/
│   │       └── AudioSessionManager.swift   // Hardware session (.measurement / playback)
│   ├── Models/
│   │   ├── AppState.swift          // Global observable state machine & session config
│   │   ├── Defaults.swift          // UserDefaults detection parameters
│   │   ├── InstrumentProfile.swift // Per-instrument bilah geometry, rects, pitches
│   │   ├── Judgement.swift         // Strike accuracy windows and scoring
│   │   ├── Kotekan.swift           // Domain core: 16-slot polos/sangsih figures
│   │   ├── Preloader.swift         // Launch warm-up (camera, WAV decodes, CoreML)
│   │   ├── ProfileStore.swift      // Documents directory JSON persistence
│   │   ├── ResourceLoader.swift    // Bundled fallback JSON loader
│   │   └── Song.swift              // Rendered note sequences
│   ├── UI/
│   │   ├── Components.swift        // Shared controls & .kajar button/toggle styles
│   │   ├── PatternBackground.swift // Persistent continuous drifting canvas
│   │   └── Theme.swift             // Warm-brown ground, typography, and geometry tokens
│   └── Vision/
│       ├── BilahDetector.mlmodel, BilahFinder.swift
│       ├── CameraController.swift  // Single AVCaptureSession, focus/exposure lock
│       ├── CameraPreview.swift     // Shared UIViewRepresentable preview layer
│       ├── FrameBuffer.swift       // Time-indexed rolling video frames
│       ├── KeyDetector.swift, ProjectionAligner.swift
│       ├── MalletDetector.mlmodel (V1, V3, V4), MalletHitClassifier.swift
│       ├── MarkerTracker.swift, MarkerFusion.swift
│       ├── StrikeFusion.swift      // Actor reconciling vision and audio off UI thread
│       └── VisionStrikeDetector.swift // Per-key Schmitt trigger
├── Features/
│   ├── Calibration/
│   │   ├── AligningView.swift      // Step 3/4: drag & resize key rects
│   │   ├── CalibrationView.swift   // Step 4/4: learn instrument voice / baseline
│   │   ├── FramingView.swift       // Step 2/4: camera positioning guide
│   │   └── KeyCountView.swift      // Step 1/4: bilah count selection
│   ├── Detection/                  // Diagnostic & training tools
│   │   ├── AudioTestView.swift, MalletTestView.swift, DetectionTestView.swift
│   │   ├── CaptureTrainingView.swift, TrainingCapture.swift
│   ├── Onboarding/
│   │   ├── GuideView.swift, OnboardingView.swift, PermissionsView.swift
│   │   ├── SplashView.swift, WelcomeView.swift
│   ├── Play/
│   │   ├── ChooseKotekanView.swift // Kotekan figure selection
│   │   ├── DisplayLink.swift       // CADisplayLink frame driver
│   │   ├── NotesRiver.swift        // Secondary piano roll strip
│   │   ├── OverlayView.swift       // Primary on-bilah visual guidance
│   │   ├── PlayEngine.swift        // Practice loop, timing, cues, scoring engine
│   │   ├── PlayView.swift          // Live practice/play screen with camera & overlay
│   │   ├── PracticeCoach.swift     // Interactive control coach
│   │   └── ResultsView.swift       // Post-session summary
│   └── Settings/
│       ├── ChooseInstrumentView.swift // Instrument profile switcher
│       └── SettingsView.swift         // App preferences & calibration triggers
└── Resources/
    ├── Assets.xcassets, bgm.m4a, font/, *.wav, logo-kotek.icon, lottie/
```

### 13.4 Architectural principles & standards

- **MVVM Pattern**:
  - **Models (`Kotek/Core/Models/`)**: Independent state representations, domain entities (`Song`, `Kotekan`, `InstrumentProfile`, `Judgement`), global observable state machine (`AppState`), and serialization/persistence (`ProfileStore`) without UI dependencies.
  - **Views (`Kotek/Features/*/`, `Kotek/App/RootView.swift`)**: Declarative SwiftUI views handling layout, rendering, and direct user gestures. Views stay thin and bind directly to observable models (`@Environment(AppState.self)`) or feature ViewModels.
  - **ViewModels (`Kotek/Features/*/`)**: Feature-scoped presentation state coordinators (e.g., `PlayEngine.swift` acting as the ViewModel/local engine for `PlayView`). ViewModels live inside their feature modules—never in `Core/`—and transform domain data and service outputs into render-ready view states. Per the **Ponytail philosophy**, ViewModels are YAGNI for simple screens; views bind directly to `@Observable` models (`AppState`) unless complex local UI state, high-frequency frame loops (CADisplayLink), or multi-service orchestration demands one.
  - **Services (`Kotek/Core/Audio/`, `Kotek/Core/Vision/`)**: Headless hardware, audio, and vision infrastructure services (`CameraController`, `AudioEngineController`, `AudioSessionManager`, `CuePlayer`, `StrikeFusion`). They manage hardware capture sessions, mic taps, audio buffers, FFT/DSP pipelines, CoreML inference, and multi-modal fusion off the UI thread. Services are UI-agnostic, owned/initialized at the root level (`RootView`), and injected into views or feature engines.
- **Scope & Placement (Core vs. Features)**:
  - **`Core/` is strictly for shared types**: Classes, structs, enums, domain models, headless services, and UI styling in `Kotek/Core/` must be genuinely shared across multiple screens or features.
  - **Single-view types belong in `Features/`**: If a class, struct, enum, ViewModel, or helper is used by only one view or feature (e.g., `KeyRenderState`, `CycleNote`, `Floater`, `CoachStep` in `Features/Play/`), keep it strictly within that feature module. Never pollute `Core/` with single-use types or premature abstractions.
- **DRY Principle**:
  - Single source of truth for global state (`AppState`) and hardware sessions (`CameraController`, `AudioEngineController`).
  - Shared design tokens, styles, and controls in `Kotek/Core/UI/` (`Theme.swift`, `Components.swift`, `PatternBackground.swift`).
  - Core DSP algorithms and vision detection/fusion are centralized and reused across features.
- **SOLID Principles**:
  - **Single Responsibility**: Each module, class, actor, and view has a single well-defined task (e.g., `FFTProcessor` only computes FFT; `OnsetDetector` handles spectral flux; `StrikeFusion` actor handles multi-modal decision; Views only render).
  - **Open/Closed**: Features and profiles are extensible without altering existing core logic (e.g. instrument tuning agnostic via `InstrumentProfile`; kotekan figures are data-driven).
  - **Liskov Substitution**: Protocols and types are strictly substitutable across asynchronous and actor boundaries.
  - **Interface Segregation**: Lean, cohesive interfaces (e.g. separate playback vs. capture session vs. DSP analysis).
  - **Dependency Inversion**: Feature views depend on injected dependencies (`camera`, `audio`, `cue`, `@Environment(AppState.self)`) passed from `RootView`.
- **Ponytail Philosophy (YAGNI)**:
  - Build the minimum that works cleanly without unrequested abstractions or ceremonial boilerplate. Mark deliberate simplifications with `// ponytail: ...`.
  - Single-use classes, structs, enums, and ViewModels stay co-located with their view in `Features/`; do not promote them to `Core/` until a second feature actually requires them.

### 13.5 State machine

As built, `AppState.Screen`:

```
launch → .welcome
  → .welcome
      begin → .checkingPermissions
  → .checkingPermissions
      denied  → .permissionsBlocked (terminal, links to Settings)
      granted → .choosingKeyCount
  → .choosingKeyCount     // setup 1/4: select bilah count
      next → .framing
  → .framing              // setup 2/4: live preview + guide outline
      user confirms → .aligning
  → .aligning             // setup 3/4: drag/resize key rects over bilah
      user confirms → .calibrating / .baseline
  → .calibrating          // setup 4/4: acoustic baseline strike learning
      complete → .chooseKotekan
  → .chooseKotekan        // select kotekan figure
      start → .countdown
  → .countdown / .playing // PlayView: continuous loop, in-place voice/tempo toggles
      finish → .results
  → .results
      replay → .countdown | done → .chooseKotekan
  → .settings             // reached from navigation bar
      choose instrument → .chooseInstrument
      re-align → .aligning
      diagnostics → .audioTest, .malletTest, .detectionTest, .captureTraining, .sensorTest
      instrument → connect controller | check keys → .controllerSetup   (planned, Flow D)
  new gangsa registered → "Connect a controller?" → .controllerSetup | skip → as today
  re-check banner (Flow E) → .controllerSetup at step 5
  → .controllerSetup          // scanning / connecting / summary / mapping are local
                          // steps of one screen, not Route cases
      finish | cancel → back to where it was opened from (Settings, or the end of new-gangsa setup)
```

Reconnect (Flow E) is not a screen: a controller service owned by `RootView` watches the active instrument and connects or disconnects in the background of whatever screen is showing.

There is no dedicated `.ready` or `.paused` case: the kotekan selection screen *is* the ready state, and pause is handled by local `@State` inside `PlayView`. Re-alignment is reached from Settings or setup, which is the persistent "keys misaligned?" affordance.

### 13.6 Overlay visual tokens

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

### 13.7 Placeholder song

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

### 13.8 Build order for a developer

1. Camera preview rendering, landscape-locked, focus lock verified
2. Audio session configured; confirm mic input is unprocessed (no AGC)
3. Onset detector ported using the validated parameters in §6.3 — verify against the existing recording before testing live
4. Key classifier + debug view showing detected index and confidence live
5. Static overlay from bundled profile, aligned over real keys
6. **Stop and playtest:** stand at the instrument, check the overlay is readable peripherally
7. Play engine: timing, judgement, results
8. Cue audio, practice mode, exhibition mode

Steps 3 and 4 are the technical risk. Step 6 is the UX risk. Do not build past step 6 without doing it.
