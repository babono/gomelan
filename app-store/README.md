# App Store submission

Everything App Store Connect asks for, in the order it asks, with what is done
and what still needs a decision. Copy is a draft — edit freely, the limits are
noted beside each field.

## 1. Before you upload

- [ ] **Decide the store name.** The app calls itself **Kotek** everywhere a
      player sees it (home screen, wordmark, onboarding, permission prompts),
      while the repo docs call the product *Gomelan*. The store name should
      match the home-screen name, or review flags it (guideline 2.3.7) and
      players can't find what they just installed. Check that the name is free
      in App Store Connect → *New App* before committing to it.
- [ ] **Bump `CURRENT_PROJECT_VERSION`** in `project.yml` (currently `6`) if
      build 6 has already gone up to TestFlight, then `xcodegen generate`.
- [ ] **Privacy policy URL** — required for every app, even one that collects
      nothing. A one-page site is enough; draft text is in §5.
- [ ] **Permission from Mekar Bhuana in writing** for their name, mark and
      photos (the landing-screen panel). Review can ask for it (guideline 5.2.1).
- [ ] **Check the Dream Orphans font licence** covers embedding in an app.
- [ ] **Record a demo video** of a real session for the reviewer — see §6.
      This matters more than anything else on this list.

Archive and upload:

```sh
xcodegen generate
xcodebuild -project Kotek.xcodeproj -scheme Kotek -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Kotek.xcarchive archive
xcodebuild -exportArchive -archivePath build/Kotek.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export
# then upload build/export/Kotek.ipa with Transporter, or Xcode → Organizer
```

Already in place: `PrivacyInfo.xcprivacy`, camera/microphone usage strings,
`ITSAppUsesNonExemptEncryption = NO` (no export-compliance question), app icon,
iPhone-only (`TARGETED_DEVICE_FAMILY: "1"`, so no iPad screenshots needed).

## 2. Screenshots

**Upload these:** `screenshots/highlights/` — four captioned frames, 2868 × 1320
JPEG, for the **6.9" Display** slot, in this order:

| # | File | Headline |
|---|---|---|
| 1 | `01-two-halves.jpg` | Two halves. One melody. — polos and sangsih |
| 2 | `02-follow-the-light.jpg` | Follow the light — the practice set-up |
| 3 | `03-tighter-every-cycle.jpg` | Tighter every cycle — scoring and records |
| 4 | `04-grow.jpg` | Grow with your gangsa — the rank ladder |

App Store Connect only accepts each slot's own sizes, so the same four frames
are also exported for the smaller slots: `highlights-6.3/` (2622 × 1206) and
`highlights-6.1/` (2556 × 1179). iPad gets its own layout, copy on top and
phone below: `highlights-ipad-13/` (2752 × 2064) and `highlights-ipad-12.9/`
(2732 × 2048). Those are only needed while the uploaded build still declares
iPad — see §1.

They are rendered from `marketing/frames.html` (copy lives in `FRAMES` at the
bottom) by `marketing/render.sh`. Frame 2 currently shows the onboarding's
tracking illustration; save a real practice-screen capture as
`marketing/practice.jpg` and re-render, and it takes its place.

### Raw captures

`screenshots/iphone-6.9/` — 2868 × 1320, landscape, JPEG without alpha, ready to
drag into the **6.9" Display** slot. App Store Connect scales them for every
smaller iPhone. Up to 10 are allowed; the first three show in search results,
so the order matters.

| # | File | Shows |
|---|---|---|
| 1 | `01-welcome.jpg` | Landing screen — the wordmark and the gangsa |
| 2 | *(take on a phone — see below)* | **Practice screen over a real gangsa** |
| 3 | `02-interlock.jpg` | Polos and sangsih — what you are learning |
| 4 | `03-tracking.jpg` | The phone-on-a-stand setup |
| 5 | `04-choose-kotekan.jpg` | The songbook |
| 6 | `05-results.jpg` | A finished session: accuracy, the cycle chart, the grade |
| 7 | `06-your-gangsa.jpg` | Saved instruments with their ranks |
| 8 | `07-kotekan-guide.jpg` | The in-app explanation of kotekan |
| — | `alt-welcome-onboarding.jpg` | Spare: onboarding slide 1 |

**The missing one is the most important.** Every simulator screenshot shows
the app *around* the experience; none shows the bilah lighting up under the
camera, because the simulator has no camera. Take it on the stand, mid-session,
with the overlay lit and ideally a hand and mallet in frame. Use a
**6.9" phone** (16/17 Pro Max: 2868 × 1320; 15 Pro Max/Plus, 16 Plus: 2796 × 1290,
also accepted in that slot). Press side + volume-up. Hide the practice coach
first. Put it second in the order.

Retake the simulator set any time with `app-store/capture-screenshots.sh`. It
opens each screen with sample data through the DEBUG-only `-screenshot` hook in
`Kotek/Model/ScreenshotScenes.swift`, which is compiled out of release builds.

App preview video (optional, up to 30 s, landscape 1920 × 886 for 6.9"): the
single most persuasive asset for an app like this is 15 seconds of a real
kotekan being played with the overlay keeping up.

## 3. Listing copy

**Name** (≤ 30): `Kotek` — or `Kotek: Learn Kotekan` (20) if plain `Kotek` is
taken; the extra words also count toward search.

**Subtitle** (≤ 30): `Learn gangsa with your camera` (29)

**Promotional text** (≤ 170, editable without a new build):

> Put your phone on a stand above your gangsa. Kotek watches which bilah you
> strike, listens for when, and lights the next note on the instrument itself.

**Description** (≤ 4000):

> Kotek turns a real Balinese gangsa into a guided practice partner.
>
> Set your iPhone on a stand above the instrument. The camera sees which bilah
> you strike, the microphone hears when, and the next note lights up right on
> the keys in front of you — so your eyes stay on the instrument, not on a
> score.
>
> LEARN THE INTERLOCK
> Kotekan is one melody split between two players: polos on the beat, sangsih
> in between. Kotek plays the half you are not playing, so the interlock is
> there even when you practise alone — and when you are ready, switch sides
> without stopping.
>
> YOUR INSTRUMENT, NOT A GENERIC ONE
> Every gamelan in Bali is tuned differently. Kotek learns yours: how many keys
> it has, where they sit, and what a real strike sounds like, so a clap or a
> voice in the room is not mistaken for a note. Save more than one gangsa and
> pick up where you left off on each.
>
> PRACTISE THE WAY IT IS TAUGHT
> Hear the figure first, then play along with it, then mute it and play alone.
> Slow the tempo down while the pattern settles into your hands. Every gong
> cycle is scored, and your best run is kept.
>
> GROW WITH THE INSTRUMENT
> Each gangsa earns a rank as you land notes on it — from Paria, finding the
> keys, to Brahmana, when the weave is yours.
>
> INCLUDES
> • Kotekan figures across three levels, from Ubitan Nyendok upwards
> • Lagu dolanan melodies to play in unison
> • In-app guides to kotekan, polos and sangsih, and the gangsa itself
>
> Made with Sanggar Mekar Bhuana in Bali.
>
> Kotek needs a gangsa (pemade or kantilan) and a way to hold your iPhone above
> it. Everything stays on your phone: nothing is uploaded, and there are no
> accounts.

**Keywords** (≤ 100, comma-separated, no spaces needed; don't repeat words
already in the name or subtitle):

`gamelan,bali,balinese,kotekan,polos,sangsih,pemade,kantilan,metallophone,indonesia,percussion`
(93)

**Category**: Music (primary), Education (secondary)

**Support URL**: required — the same small site as the privacy policy works.
**Marketing URL**: optional.

**Copyright**: `2026 <your name or studio>`

## 4. Age rating

Answer *None* to every content question → **4+**. No web browsing inside the
app (the Mekar Bhuana link opens Safari), no user-generated content, no
gambling, no contests.

## 5. App Privacy

**Data collection: "No, we do not collect data from this app."** The camera and
microphone are processed on the device, and nothing leaves it — that matches
`PrivacyInfo.xcprivacy` (`NSPrivacyCollectedDataTypes` empty, no tracking).
Lottie, the only dependency, ships its own manifest and collects nothing.

Privacy policy draft:

> Kotek does not collect, store on any server, or share any personal data.
> The camera and microphone are used only while you practise, to see which
> keys you strike and hear when; the images and sound are processed on your
> iPhone and are never recorded or uploaded. Instrument settings and your
> practice history are saved only on your device and are deleted when you
> delete the app. Kotek has no accounts, no analytics, and no advertising.
> Questions: <your email>.

## 6. App Review notes

The reviewer almost certainly has no gangsa. An app whose core feature they
cannot exercise risks a 2.1 (*App Completeness*) rejection, so tell them up
front what it needs, what they *can* try, and show them the rest:

> Kotek is a practice tool for the Balinese gangsa, a bronze metallophone. Its
> core feature needs the physical instrument: the phone sits on a stand above
> it, the camera locates the keys and sees which one is struck, and the
> microphone confirms the strike.
>
> A video of a full session on a real gangsa — setup, practice, results — is
> here: <link to an unlisted video>
>
> Without an instrument you can still: go through the introduction; open
> "Choose your gangsa" → Add a gangsa, and follow setup up to the framing step;
> browse and listen to every kotekan in the songbook; and read the guides (the
> ? buttons).
>
> Camera and microphone are processed on the device only. No account is
> needed.
