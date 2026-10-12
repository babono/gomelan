# Gomelan v2 — Product Requirements Document

**Version:** 2.0 draft (for team review)
**Platform:** iOS 26.5+, iPhone and iPad, landscape
**Instrument:** Gangsa (gong kebyar family), fitted with vibration sensors
**Release:** App version 2.0

`documentation/prd.md` stays as the **v1 record**. Source comments cite its sections (§5.1, §13.4, …), so it is not rewritten. This document supersedes it wherever they disagree. Section numbers here are prefixed **v2-** when cited from code (e.g. `v2-§7.2`).

---

## 0. Status

| Area | Where | State |
|---|---|---|
| Accounts, profile, sync, history, deletion, guest prompt | `main` (PRs #8–#12) | **Shipped to main**, tested on device |
| Waterfall play screen | `play-screen-waterfall` | In progress |
| Sensor integration | `play-screen-waterfall` (`GangsaSensor`) | In progress — 3-bar prototype, not yet wired to every bilah |
| Kotek Studio (make your own kotekan) | — | Not started; storage already exists (§v2-6.5) |
| Coop mode | this document (§v2-6.6) | Specified, not built |
| Design revamp | design files | In progress |
| Camera + microphone detection | `main` | **Being retired** (§v2-10) |

---

## 1. Purpose

**Challenge statement** (unchanged from v1):
> Empower young Balinese who want to relearn gamelan by turning a real instrument into something they can approach alone — guided, before there's a teacher or a community to join.

**Positioning:** *Play gamelan anywhere — no sekaa required.*

**What v2 is:** Gomelan reads the strikes on a real gangsa through vibration sensors and shows the kotekan as a **waterfall** — notes falling onto a drawn gangsa, the way players already read notation. You can learn either half alone, **play the interlock with a partner**, **write your own figures** in Kotek Studio, and keep your progress across devices with an account.

**Design constraint** (unchanged): technology stays in a support role. The app helps someone take a first step; it does not replace a teacher. The framing is *before* a teacher, not *instead of* one.

---

## 2. What changed since v1, and why

| v1 | v2 | Why |
|---|---|---|
| Phone on a stand looking down; overlay on the live camera feed | **Waterfall** on a drawn gangsa; the device sits anywhere it can be seen | Research: players want the notation. Camera setup — stand, framing, lighting, aligning masks — was the biggest source of friction. |
| Camera says *which key*, microphone says *when* | **Vibration sensors** say both | A sensor on each bilah is exact, needs no calibration against the room, and cannot be fooled by another instrument. |
| Four-step setup (key count, framing, alignment, acoustic baseline) | **Name, key count, pair sensors, strike each bilah once** | Most of the setup existed to serve the camera. |
| One player; the app plays the other half | **Coop** — two people, one kotekan | The interlock is the instrument's reason to exist (v1 §11 Q2). |
| Built-in figures only | **Kotek Studio** — write, record and keep your own | Players learn figures from teachers and from each other; the app should hold those too. |
| No accounts; one phone | **Accounts (optional), sync, history** | Progress should survive a new phone. |
| iPhone only | **iPhone and iPad** | The iPad is the natural shared screen for coop. |

---

## 3. Scope

### In scope (v2)
- Optional accounts: guest or Sign in with Apple; profile; sync; history; deletion (**shipped**)
- Instrument setup with sensors: pairing, bilah mapping, latency calibration
- Waterfall play screen, solo, with practice and scored play
- **Play-along mode** without sensors
- Kotek Studio: create, record, edit, delete your own kotekan
- Coop: **one-screen** and **two-device**
- Design revamp across every screen
- iPad layout

### Out of scope (v2)
- Live camera guidance, Vision/CoreML detection, microphone strike detection (retired — §v2-10)
- Coop over the internet; more than two players
- Public kotekan library / share links
- Scoring damping (still taught, not scored — v1 §5.5)
- Android

### Explicit non-goals (unchanged)
- Teaching full traditional repertoire
- Replacing human instruction
- Assuming a fixed scale or standard tuning — every bilah is addressed by **key index**, never pitch

---

## 4. Hardware & setup

| Item | Requirement | Notes |
|---|---|---|
| Device | iPhone or iPad, iOS 26.5+ | No stand needed; anywhere the player can see it. iPad recommended for coop. |
| Sensor kit | ESP32 with **one piezo per bilah**, BLE (`Gangsa-Sensor`) | Does detection on-device: threshold, ring-down rejection, crosstalk window. |
| Instrument | Gangsa, any tuning, any key count up to 14 | Sensors map to key indices per instrument. |
| Mallet | Single *panggul*, right hand; left hand damps | Unchanged (v1 §5.5). |

**Without a sensor kit** the app still works as a play-along (§v2-6.4). This is also what App Store review uses (§v2-12).

---

## 5. Core flows

### 5.1 First run
```
Splash → Welcome: [Continue with Apple] [Continue as guest]
       → (Apple, first time) Profile step: name + avatar
       → Onboarding (once)
       → Instrument setup (§5.2) — or "Play along without sensors"
       → Home
```

### 5.2 Instrument setup
```
1. Name + gangsa type + key count
2. Pair sensor kit (Bluetooth)
3. Map: strike each bilah once, low to high → sensor channel ↔ key index
4. Timing check: tap along to the gong a few times → latency offset
5. Saved to the instrument profile (and synced, if signed in)
```
Target: under 2 minutes for a 10-key gangsa. Re-pairing and re-mapping are reachable from Settings.

### 5.3 Solo practice
```
Home → choose instrument → Solo → choose kotekan (built-in or your own) → half + tempo
     → count-in → waterfall → end → results → retry / another / back
```

### 5.4 Coop
```
Choose instrument → Coop on this screen  → player 2 setup → figure, tempo, halves → play → shared results
                  → Coop with another phone → host / join → lobby → synced start → play → shared results
```
Details: §v2-6.6.

### 5.5 Kotek Studio
```
Home → Kotek Studio → New → write (tap the grid) or record (play it on the sensors)
     → preview → name, level, tempo → save → appears in the kotekan picker
```
Details: §v2-6.5.

---

## 6. Features

### 6.1 Accounts, profile and sync — *shipped*

Built in PRs #8–#12; recorded here as requirements.

- **Welcome** offers *Continue with Apple* and *Continue as guest* as equals. Guest progress stays on the device; the hint says so.
- **Guest** = an anonymous Supabase user, created lazily. **Apple** = Sign in with Apple via the native sheet; **name only, never email**.
- **Linking** (Settings, or the results prompt): attaches the Apple ID to the guest, keeping the same user id and every uploaded row. If the Apple ID already has an account, the player is asked to **switch**; switching wipes this device's guest progress. No merging.
- **Profile step** after the first Apple sign-in: name (prefilled from Apple, which sends it only once) and one of ten **preset avatars**. Skippable. Stored in the account's user metadata. *Edit profile* in Settings.
- **Sync** (Apple accounts): the full instrument profile uploads on every save and downloads on launch and sign-in; per instrument, **the most recently changed copy wins**; an instrument deleted on one device disappears from the others.
- **History**: Settings → instrument → History lists past sessions from the server, newest first.
- **Sign out** wipes local data and returns to Welcome. **Delete account** re-confirms with Apple, then the `delete-account` Edge Function revokes the Apple token and deletes every row and the user.
- **Guest prompt**: once ever, after a guest's first record (or third session), the results screen offers to keep their progress with an Apple ID.
- **v2 reset**: the first v2 launch clears v1's local data (decided: v1 progress is not migrated).

### 6.2 Instrument setup with sensors

- **Pairing:** scan for `Gangsa-Sensor` devices; show signal and battery if the kit reports it; remember the kit per instrument and reconnect automatically.
- **Mapping:** strike each bilah once, lowest to highest. The app records which sensor channel fired and stores `sensorMap: [channel: keyIndex]`. A bilah that fires two channels, or a channel that never fires, is flagged before saving.
- **Latency calibration:** the player taps any bilah along with eight gong strokes; the median difference becomes the instrument's `latencyOffsetMs`, applied to every hit. Hits also carry the ESP32's own clock (`Hit.intervalMs`), which removes BLE jitter between strokes.
- **Connection state** is always visible during play (connected / reconnecting / lost). A dropout mid-session pauses judging, not the music.
- The v1 setup screens — framing, aligning, acoustic baseline — are removed from the flow.

### 6.3 Waterfall play screen

Built on the same `PlayEngine` as v1: the count-in, judging, partner half, records and session filing are unchanged; only the display and the strike source are new.

- **The gangsa is drawn** with the instrument's key count; bilah the figure uses are full strength, the rest dimmed.
- **Notes fall** onto their bilah and land exactly when due — positions come from the engine's clock, not a scrolling page.
- **Two views:** flat (top-down) and tilted towards the player; swipe to switch; remembered.
- **Damp cue** beside each stroke: the bilah the left hand should pinch (the previous stroke). Taught, not scored (v1 §5.5).
- **Beat rules** across the waterfall, strong every four beats on the kajar.
- **Partner half** shown faintly beside your notes — **never hidden behind them**: where both halves strike the same bilah at once, the two blocks sit side by side.
- **Feedback** on each bilah as it is struck: hit, early/late, wrong key, miss — judged from the sensors.
- **Practice mode** (default for first-timers) and **scored play**; tempo 50 / 75 / 100 %; voice toggles for your half and the partner half — as v1.
- **Results**: accuracy over the best window, streak, personal record per figure, half and tempo; average accuracy of each stroke across the cycle, pooled into quarters, with the weakest quarter named; an on-device AI overview of the session (§v2-6.8). The rank ladder (Paria → Brahmana) is **removed**; a gangsa card shows notes landed instead.

### 6.4 Play-along without sensors

- Available from Welcome and the kotekan picker whenever no kit is connected.
- The waterfall, gong layer and guide voice all run; **nothing is judged**, no records, no session filed.
- Clearly labelled ("Play along — connect sensors to be scored"), with a path to pairing.
- Serves people without the hardware, people reading the notation away from an instrument, and App Store review.

### 6.5 Kotek Studio

Write your own kotekan and keep it. Storage already exists: `kotekan` and `kotekan_hits` tables, `KotekanRepository.saveKotekan`, and `KotekanSource.manual` / `.automatic`; the catalogue already shows a user's own figures after the built-ins.

- **Write (manual):** a grid of 8, 16 or 32 slots per gong cycle, one row per bilah, two lanes — polos and sangsih. Tap a cell to place a stroke; a slot holds at most one stroke per half. Polos and sangsih may share a slot, including the same key (§v2-6.6.4).
- **Record (automatic):** set slots and tempo, play the figure on the sensors over a metronome; strokes are quantised to the nearest slot and land in the grid for editing. Each half is recorded separately.
- **Preview:** loop the figure with both halves audible, solo either half, at any tempo.
- **Details:** name, level (1–3, or *melody*), tempo (`strokeMs`), an optional one-line description.
- **Validation before saving:** at least one stroke in each half; key indices within the instrument's key count (the figure's `requiredKeys` is derived, as for built-ins).
- **Saving:** to the player's account (guest or Apple) — private to them. Appears in the kotekan picker with a *mine* marker; playable solo and in coop like any figure.
- **Edit / duplicate / delete** from the picker or the Studio list. Deleting a figure keeps its past sessions in History (shown as "deleted figure").
- **Records** for your own figures work exactly like built-ins.

### 6.6 Coop

Kotekan is two interlocking halves that only become the figure when two players lock together. Coop puts two people, each at their own gangsa, into the same kotekan at the same moment — the app keeping time between them the way a kendang player would. Two players in v2.

#### 6.6.1 Two modes

**One screen** — one device (an iPad, ideally) between the two gangsa, connected to **both** sensor kits, showing **both halves** side by side. One device, one clock, one gong.

**Two devices** — each player has their own device and kit and their own waterfall. The devices find each other nearby, synchronise clocks and start together.

| | One screen | Two devices |
|---|---|---|
| Devices | 1 | 2 |
| Sensor kits per device | **2** | 1 |
| Networking | **None** | Discovery, lobby, messages |
| Keeping in time | **Free** — one clock | Clock sync ≤ 10 ms, drift correction |
| Gong / metronome | The one device | Host only |
| Kotekan available | Everything on the device | Host's catalogue, sent to the guest |
| Seeing the interlock | **Both halves together**, shared notes linked | Partner's notes faint beside yours |
| Accounts | Filed under the device's account; partner named | Each device files to its own |
| Build effort | **Small** | Large |

**Order:** one screen first — it delivers the whole experience with none of the networking or timing risk, and its lanes, second kit, interlock score and coop data are reused by two-device coop.

#### 6.6.2 Shared by both modes
- **Choosing:** only figures playable on **both** gangsa — `requiredKeys ≤ min(keyCountA, keyCountB)`. Tempo 50 / 75 / 100 %. Player 1 polos, player 2 sangsih by default; one tap swaps. Tempo and halves are locked once playing.
- **Ready:** each player's kit is connected and has registered a test strike; start is enabled when both are ready.
- **No partner voice** — the partner is real. Guide voices default off.
- **Results:** both players' headline numbers and the **interlock score** (§v2-6.6.5) as the headline.

#### 6.6.3 One-screen coop
- `GangsaSensor` holds **two** kit connections and tags each hit with which gangsa it came from.
- Player 2 picks one of the device's instruments or quick-adds theirs (§v2-5.2 steps 1–4), and enters a name ("Player 2" by default) — no second account.
- **Display: two lanes side by side**, one per gangsa, each a full drawn gangsa in that half's colour (`Theme.polosVoice` / `Theme.sangsihVoice`). Lane order matches where the players sit; one tap swaps.
- **One `PlayEngine` per player**, both on the same display link and start time — they cannot drift.
- Each player gets a session row under the device's account, with `mode`, `partner_name` and the shared interlock score.

#### 6.6.4 Shared notes
Polos and sangsih often strike together, sometimes on the same key. In the bundled figures:

| Figure | Slots per cycle | Both strike together | …same key |
|---|---|---|---|
| Ubitan Nyendok | 8 | 2 | 2 |
| Kabelet | 8 | 3 | 0 |
| Ngecog | 16 | 2 | 2 |
| Babaru | 32 | 8 | 8 |

These unisons are the anchors the interlock hangs from. On one screen, **a thin band joins the two notes across the lanes** at that moment, brighter for the same key. In two-device mode the partner's block sits **beside** yours within the bilah. Neither display may ever hide one player's note behind the other's.

#### 6.6.5 Interlock score
- Per completed cycle, take every slot with a note in *either* half.
- A slot counts if the player responsible **landed** it (right key, on the beat). A unison slot needs **both**.
- **Interlock = slots landed ÷ slots due**, over the best scoring window, same window rule as solo.

#### 6.6.6 Two-device coop
- **Host / join** nearby: the host advertises under their name; the lobby lists who joined — name, avatar, gangsa, key count. First use triggers iOS's Local Network permission.
- **Sharing the host's kotekan:** whenever the host picks a figure, the host sends **the figure itself** (name, both grids, `strokeMs`, level), not an id. The guest plays it without fetching anything — works for guests, offline, and for figures private to the host (including Kotek Studio figures). After the session the guest may **Save to my kotekan**: a **copy** under their own account, new id, credited *"from <host name>"*. The host's row is never touched.
- **Clock sync** on `CACurrentMediaTime()`: guest `ping(t0)` → host `pong(t0, t1, t2)` → guest notes `t3`; `offset = ((t1 − t0) + (t2 − t3)) / 2`; ~20 samples, keep the lowest round-trip. Strokes are 125–250 ms apart and the interlock smears beyond ~15–20 ms — **target ≤ 10 ms**.
- **Scheduled start:** host sends `start(atHostTime: T)`, T ≈ now + 3 s; guest sets `startHostTime = T − offset`. Engine change: `PlayEngine.start(at:)` beside `start()`.
- **Drift:** up to ~30 ms over ten minutes; the guest re-measures and nudges `startHostTime` **at gong boundaries**.
- **Sound:** gong and metronome on the **host only**; the guest is silent (guide voice: earphones only). Warn if the host's output is Bluetooth (+150–250 ms).
- **Leaving:** guest leaves → host continues with the partner voice switched on. Host leaves → session ends for the guest, result kept. Backgrounded / locked = leaving.
- **Transport:** Network.framework — `NWListener` / `NWBrowser` over Bonjour, `includePeerToPeer = true`, TCP `noDelay`; JSON messages, versioned: `hello`, `lobby{kotekan, tempo, hostHalf}`, `ready`, `ping`/`pong`, `start{atHostTime}`, `pause`, `resume`, `end`, `result{judgements, summary}`. Each device sends its per-note judgements at the end so both compute the same interlock score.

### 6.7 Design revamp

Every screen is redrawn to the new design (the *Sangsih* design system begun in v1.x: one warm ground, cream type, gold accents). Specifics live in the design files; this PRD fixes the requirements the design must meet:

- **Readable from the instrument:** during play, the waterfall and feedback must read at a glance from a seated player 1–2 m away. No text needed mid-play.
- **iPad:** every screen has an iPad layout; the coop two-lane screen is designed iPad-first.
- **Light-on-dark only**, landscape only, Dynamic Type for all non-play text, VoiceOver labels on every control.
- **One set of components** (`Core/UI`): buttons, dialogs, cards, avatar, sensor status — no per-screen variants.
- **Motion** keeps time with the music where it can (the home screen already plays itself); never on the play screen outside the falling notes.

---

## 7. Timing & judgement

Notes are `(key_index, time_ms, duration_ms)`; figures are grids of key indices per slot. Judgement windows carry over from v1 §5.1 (Perfect ±60 ms, Good ±120 ms, Late/Early ±200 ms, Miss, Wrong key) and are scaled by the leniency setting. Strike time = sensor hit time on the `CACurrentMediaTime` clock − the instrument's `latencyOffsetMs`. Only completed passes are scored (v1 behaviour).

---

## 8. Sound

- **Gong layer** (gong, kempur, kajar) under every session; never optional.
- **Metronome**, **guide voice** (your half) and **partner voice** (the other half), each toggleable — as v1.
- Samples: the bundled gangsa set (`key0–9.wav`, `gong`, `kempur`, `kajar`).
- No microphone is used in v2, so the v1 risk of cue audio bleeding into detection is gone.
- Coop sound rules: §v2-6.6.

---

## 9. Data

### 9.1 Instrument profile
Unchanged shape (snake_case JSON on device and in `instruments.profile`), with:

| Field | Type | Meaning |
|---|---|---|
| `sensor_kit_id` | string? | The paired kit's identifier |
| `sensor_map` | `{channel: key_index}` | From §v2-6.2 mapping |
| `latency_offset_ms` | number? | From §v2-6.2 timing check |

Camera-era fields (`rect`, `corners`, `strike_baseline`, `fingerprint`, `linear_template`) become unused; they stay decodable so v1-era files and rows still load, and are dropped in the cleanup (§v2-10).

### 9.2 Supabase

| Table | Purpose | v2 changes |
|---|---|---|
| `instruments`, `instrument_keys` | Instruments; `profile` jsonb holds the full profile | — (shipped) |
| `kotekan`, `kotekan_hits` | Built-in and user figures | `copied_from`, `author_name` (coop copies) |
| `practice_session` | One row per player per session | `mode` (`solo` / `coop_screen` / `coop_devices`), `partner_name`, `interlock_accuracy` |
| `auth.users` user metadata | `display_name`, `avatar` | — (shipped) |

- All schema changes are **migration files in `supabase/migrations/`**, additive while older versions are live, applied in the SQL Editor. The pre-existing schema was hand-made and revoked default grants from `anon` **and** `service_role` — expect `42501` and grant explicitly.
- Edge Function `delete-account` lives in `supabase/functions/`; the deployed copy is whatever was last pasted into the dashboard.
- User-made kotekan and all sessions are private to their owner (RLS).

---

## 10. Architecture

**Vision answers *which key*, audio answers *when*** — the v1 central split — is replaced by: **the sensor answers both**. `PlayEngine.registerStrike(keyIndex:hostTime:confidence:)` is the single entry point, now fed by `GangsaSensor`.

| Area | v2 |
|---|---|
| `Core/Sensor/GangsaSensor` | BLE central; one **or two** kits; hits tagged by kit; reconnect |
| `Features/Play/Waterfall` | Solo and coop play screens |
| `Features/Studio` | Kotek Studio |
| `Features/Coop` | Mode choice, player 2 setup, lobby, coop results; `Core/Coop` for the two-device transport and clock sync |
| `Core/Repository` | Supabase repositories (shipped) |
| `Core/Audio/Playback` | Kept — cues, gong, samples |

**Retired** (removed from the flow in v2, deleted in one cleanup PR once the waterfall ships):
`Core/Vision` (camera, frame buffer, BilahFinder, mallet and bilah CoreML models — ~6.6 MB), `Core/Audio/DSP` detection pipeline (onset, FFT, fingerprinting, classifier, decomposer), the camera play screen and overlay, the framing / aligning / acoustic calibration screens, and the detection diagnostics. **Camera and microphone permissions are removed** with them (§v2-12). `CLAUDE.md`'s architecture section is rewritten in the same PR.

---

## 11. Screens

| Screen | Notes |
|---|---|
| Splash, Welcome | Welcome carries the Apple / guest choice (shipped) |
| Profile step / Edit profile | Shipped |
| Onboarding, guides | Redesigned |
| Home | Instruments, Solo, Coop, Studio entry points |
| Instrument setup | Name / type / key count → pair → map → timing check |
| Kotekan picker | Built-ins and your own; play-along when no kit |
| Waterfall (solo) | §v2-6.3 |
| Kotek Studio | List, grid editor, recorder, preview, details |
| Coop: mode, player 2, lobby | §v2-6.6 |
| Waterfall (coop, one screen) | Two lanes |
| Results (solo / coop) | Guest save prompt on solo results (shipped) |
| Settings | Account (shipped), instrument, sensors, history (shipped), audio, judging |

Removed: Permissions (camera/mic), Framing, Aligning, Calibration, Strike baseline, camera Play, Mallet / Detection / Audio / Capture-training diagnostics.

---

## 12. App Store & release

- **Version 2.0**; bump `CURRENT_PROJECT_VERSION` for every TestFlight upload.
- **Permissions:** Bluetooth (sensors), Local Network (two-device coop). Camera and microphone strings removed with the features.
- **Privacy:** manifest declares User ID, Name, Other User Content (linked, not tracking, app functionality). App Store Connect answers must match.
- **Review notes:** sign-in is optional (*Continue as guest*); account deletion is at Settings → Account; the app works with an **external sensor kit** — include a **demo video** of a sensor session, and note the **play-along mode** that works without it.
- **Hardware:** state in the description that scoring needs the Gomelan sensor kit, and how to get one.

---

## 13. Build plan

| # | Milestone | Depends on | Done when |
|---|---|---|---|
| 1 | Accounts, sync, history, deletion | — | **Done** (PRs #8–#12) |
| 2 | Sensor kit: one piezo per bilah; `GangsaSensor` mapping, reconnect, latency offset | Hardware | A full figure is judged from sensors on a 10-key gangsa |
| 3 | Waterfall solo + play-along; new setup flow | 2 | `play-screen-waterfall` merged; camera flow unreachable |
| 4 | Design revamp | 3 (play screen) | Every screen on the new components; iPad layouts |
| 5 | Kotek Studio | 3 | Write, record, preview, save, edit, delete; own figures playable |
| 6 | One-screen coop | 2, 3 | Two kits on one device; two lanes; interlock; coop sessions in History |
| 7 | Two-device coop | 6 | Timing spike passes (one gong heard, ≤ 10 ms, at start and after 10 min); lobby, figure sharing, leaving |
| 8 | Cleanup | 3 | Vision/DSP code, models, camera/mic permissions removed; `CLAUDE.md` rewritten |
| 9 | Release | all | App Store privacy answers, review notes + demo video, TestFlight |

Two-device coop (7) can slip to a v2.x without affecting the rest.

---

## 14. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Users without a sensor kit | Most installs can't be scored | Play-along mode; clear hardware messaging |
| App Store review without hardware | Rejection | Demo video + play-along mode in review notes |
| Sensor crosstalk through floor or stand (coop) | Strikes register on the wrong gangsa | Test two gangsa side by side early; per-kit thresholds |
| BLE dropouts mid-session | Missed strikes judged as misses | Visible connection state; pause judging on dropout |
| BLE latency differs per device | Unfair timing | Per-instrument latency calibration; ESP32 clock for intervals |
| One screen unreadable from two gangsa | One-screen coop fails | iPad-first; paper/prototype test of the two-lane layout |
| Two-device clock drift | Interlock smears | Re-sync at gong boundaries; timing spike before building UI |
| Kotek Studio records sloppy figures | Unplayable user figures | Quantise to slots; edit in the grid before saving |
| Large v2 merges from parallel branches | Conflicts, regressions | Land milestones in order; one feature per PR |

---

## 15. Open questions

1. **Sensor kit distribution:** sold, lent, or exhibition-only? This decides how prominent play-along is.
2. **Kotek Studio scope:** are melodies (one part, no halves) written here too, or only kotekan?
3. **Coop layout:** two lanes (recommended) or one merged gangsa with split blocks — settle with a paper test.
4. **Coop screen size:** is one-screen coop iPad-only, or must an iPhone work from two gangsa?
5. **Player 2's account** in one-screen coop: is a typed name enough, or should player 2 be able to claim the session on their own device later?
6. **Tempo lead:** add a kendang layer, or is the gong enough to play against?
7. **Exhibition:** two sensor-fitted gangsa and an iPad would make one-screen coop the demo. Does that reorder §13?
8. **What happens after the song?** (v1 §11 Q4) — still open: a pointer to real teaching (Mekar Bhuana, a local *sekaa*).

---

## 16. Success criteria

**v2 is successful if:**
- A first-time user with a sensor kit is scored on their first figure within **2 minutes** of opening the app.
- Sensor detection is **≥ 99 %** of strikes on the right bilah, with no strikes from a neighbouring gangsa.
- Two players complete a kotekan in one-screen coop and see an interlock score, on their first try.
- A player writes a figure in Kotek Studio and plays it within 5 minutes.
- Progress survives deleting and reinstalling the app (Apple account).
- At the exhibition, pairs of visitors choose to play coop more than once.
