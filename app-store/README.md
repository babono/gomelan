# App Store submission — v2.0.0

Everything App Store Connect asks for, in the order it asks. v1.0 is live; this
is the 2.0.0 update, iPhone **and iPad**, build 9 (uploaded 2026-11-09). Copy
is ready to paste; the limits are noted beside each field.

## 1. Version and build

- In App Store Connect → the app → **+ Version**: `2.0.0`, iOS.
- Build: **2.0.0 (9)**. The next upload must be build 10 — bump
  `CURRENT_PROJECT_VERSION` in `project.yml` first.
- Archive and upload (no CI workflow; Xcode's signed-in account does the auth):

```sh
xcodegen generate
xcodebuild -project Kotek.xcodeproj -scheme Kotek -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Kotek.xcarchive \
  -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/Kotek.xcarchive \
  -exportOptionsPlist <plist with method app-store-connect, destination upload,
  teamID U96VKD93X4> -exportPath build/export -allowProvisioningUpdates
```

`scripts/ExportOptions.plist` is that plist without `destination` (it exports
an .ipa); add `<key>destination</key><string>upload</string>` to upload
straight from the export. Its team was `QHL64K2LPL` before 2.0.1, not the
signing team.

## 2. Screenshots

Both sets are landscape. App Store Connect scales the 6.9" set to every smaller
iPhone and the 13" set to every smaller iPad, so these two slots are all that
is needed.

**Upload the captioned frames** (first three show in search, so the order
matters):

| # | iPhone 6.9" — `screenshots/highlights-6.9/` (2868 × 1320) | iPad 13" — `screenshots/highlights-ipad-13/` (2752 × 2064) |
|---|---|---|
| 1 | `01-your-gangsa-guided.jpg` — free play | same name |
| 2 | `02-one-note-at-a-time.jpg` — Learn, note by note | same name |
| 3 | `03-two-halves.jpg` — Watch, polos and sangsih | same name |
| 4 | `04-slow-to-full-speed.jpg` — Build up | same name |
| 5 | `05-kotek-studio.jpg` — the composer | same name |
| 6 | `06-two-players.jpg` — coop | same name |

**Smaller slots**, if App Store Connect asks for them by hand: the same frames
resized in `screenshots/highlights-6.3/` (2622 × 1206), `highlights-6.1/`
(2556 × 1179) and `highlights-ipad-12.9/` (2732 × 2048).

**Product page header, search result, universal** — PNG and JPEG of each
(`.jpg` was refused as an invalid extension):

- Header: `screenshots/header/header-3840x1646.png`
- Search result: `screenshots/search/search-3840x2560.png` or `search-1920x1280.png`
- Or one universal asset for both: `screenshots/universal/universal-5244x2950.png`

Art only, inside the "Art Safe Area" of Apple's creative assets template
(`creative_assets-templates.fig`): the store crops these and lays the app's
name and subtitle over the rest, so there is no type. Header and universal:
Kipli on the gangsa. Search: an iPad on Watch and an iPhone on note by note.
The welcome screen's split gate frames the edges. Rendered from
`marketing/assets.html` by `marketing/render-assets.sh` (`SAFE=1` outlines the
safe area).

Rendered from `marketing/frames.html` (copy in `FRAMES` at the bottom) by
`marketing/render.sh`, from the raw captures below.

**Raw captures**, if you'd rather add plain screens after the frames (up to 10
per slot): `screenshots/iphone-6.9/` and `screenshots/ipad-13/` — play, note by
note, two halves, build up, studio, coop, choose kotekan, welcome, kotekan
guide. Retake them with `capture-screenshots.sh` (DEBUG `-screenshot` scenes,
iOS 26.5 simulators). The simulator iPad can't be turned landscape, so its
captures are cut out of the letterbox and scaled 4:3 — slightly soft at 100%,
fine at store size.

No results screen: in the simulator Kipli's Apple Intelligence overview never
finishes. A real capture from an iPhone with Apple Intelligence would make a
good 7th frame ("Kipli tells you where to polish").

## 3. Listing copy — English (primary)

**Name** (≤ 30): keep v1's name.

**Subtitle** (≤ 30): `Learn gangsa, note by note` (26)

**Promotional text** (≤ 170, editable any time without a build):

> New in 2.0: Learn mode with Kipli, the waterfall, strike sensors, Kotek
> Studio for your own patterns, and two-player coop — on iPhone and iPad.

(143)

**Description** (≤ 4000):

> Kotek turns your Balinese gangsa into a guided practice partner.
>
> Notes fall onto a drawn gangsa and land on the bilah to strike next, so you
> always know what comes and when. Play along on your real instrument, at your
> own tempo, as many cycles as you like.
>
> Learn with Kipli
> Kipli, the barong who guides you through the app, teaches every pattern in
> steps. Watch both halves weave together. Listen to your part once. Then play
> it note by note — he waits on each one until you strike the bilah that
> glows. When it sits in your hands, build it up from half speed to full speed,
> one clean pass at a time.
>
> Two halves, one melody
> Kotekan is one melody split between two players: polos on the beat, sangsih
> in between. Kotek plays the half you are not playing, so the interlock is
> always there, even when you practise alone. Switch halves whenever you like.
>
> Every hit, felt
> Add the Kotek strike controller — a sensor under each bilah — and every
> stroke is scored for timing: early, late, the wrong bar or missed. After
> each session Kipli looks back over it and points you to the spots to polish.
> No sensors? Free play still runs, and the bars play along with you.
>
> Your gangsa, not a generic one
> Every gamelan in Bali is tuned differently. Record your own bilah once, just
> by hitting each one, and Kotek plays your instrument's sound back to you.
>
> Kotek Studio
> Write your own kotekan on a piano roll: draw polos and sangsih, mark where
> to damp, set the tempo, and practise it like any other pattern.
>
> Play together
> Two players, one screen: one on polos, one on sangsih, with the moments your
> halves meet lit up between you.
>
> Hands busy?
> Say "slower", "faster" or "pause" and Kotek does it, while both hands stay on
> the panggul.
>
> Also
> • Kotekan patterns across levels, from Ubitan Nyendok upwards
> • A damping guide that shows when the left hand stops each bilah
> • Guides to kotekan, polos and sangsih, and fitting the sensors
> • Works on iPhone and iPad, in English and Bahasa Indonesia
> • Play as a guest, or sign in with Apple to keep your gangsa, patterns and
>   records on all your devices
>
> Kotek needs a gangsa (pemade or kantilan) to play along with. The strike
> controller is optional.

**What's New in This Version** (≤ 4000):

> Kotek 2.0 is a new app.
>
> • Learn mode: Kipli teaches each pattern in steps — watch, listen, note by
>   note, then build up to full speed
> • The waterfall: notes fall onto a drawn gangsa, with the mallet and damping
>   hand shown on the bars
> • Strike controller support: a sensor under each bilah scores every hit
> • Session feedback from Kipli, with "Where to polish"
> • Kotek Studio: write and save your own kotekan
> • Two-player coop on one screen
> • Record your own gangsa's sounds, hands-free
> • Voice commands while you play
> • Sign in with Apple to sync across devices, or play as a guest
> • A fresh look, on iPhone and iPad
>
> Coming from 1.0? 2.0 starts fresh: set up your gangsa again once and you're
> playing.

**Keywords** (≤ 100, no spaces; don't repeat name or subtitle words):

`gamelan,bali,balinese,kotekan,polos,sangsih,pemade,kantilan,metallophone,indonesia,percussion,ubit`
(98)

**Category**: Music (primary), Education (secondary).

**Copyright**: `2026 <your name or studio>`

## 4. Listing copy — Indonesian (add the `Indonesian` localization)

**Subtitle**: `Belajar gangsa, nada demi nada` (30)

**Promotional text**:

> Baru di 2.0: mode Belajar bersama Kipli, air terjun nada, sensor pukulan,
> Kotek Studio untuk pola buatanmu, dan main berdua — di iPhone dan iPad.

**Description**:

> Kotek mengubah gangsa Bali-mu menjadi teman latihan yang membimbing.
>
> Nada-nada jatuh ke gangsa di layar dan mendarat di bilah yang harus kamu
> pukul berikutnya, jadi kamu selalu tahu apa yang datang dan kapan. Mainkan
> bersama di instrumen aslimu, dengan tempomu sendiri, sebanyak putaran yang
> kamu mau.
>
> Belajar bersama Kipli
> Kipli, barong yang menemanimu di aplikasi ini, mengajarkan setiap pola
> langkah demi langkah. Lihat kedua bagian saling mengisi. Dengarkan bagianmu
> sekali. Lalu mainkan nada demi nada — Kipli menunggu sampai kamu memukul
> bilah yang menyala. Setelah terasa di tangan, naikkan dari setengah
> kecepatan sampai tempo penuh, satu putaran bersih demi satu putaran.
>
> Dua bagian, satu melodi
> Kotekan adalah satu melodi yang dibagi dua pemain: polos di ketukan, sangsih
> di sela-selanya. Kotek memainkan bagian yang tidak kamu mainkan, jadi
> jalinannya selalu ada, bahkan saat kamu berlatih sendiri.
>
> Setiap pukulan terasa
> Pasang pengontrol pukulan Kotek — sensor di bawah setiap bilah — dan setiap
> pukulan dinilai ketepatannya: terlalu cepat, terlambat, salah bilah, atau
> terlewat. Setelah sesi, Kipli melihat kembali permainanmu dan menunjukkan
> bagian yang perlu dipoles. Tanpa sensor? Main bebas tetap jalan, dan bilah
> ikut berbunyi bersamamu.
>
> Gangsamu sendiri
> Setiap gamelan di Bali punya laras berbeda. Rekam bilahmu sekali, cukup
> dengan memukulnya satu per satu, dan Kotek memutar suara instrumenmu sendiri.
>
> Kotek Studio
> Tulis kotekanmu sendiri di piano roll: gambar polos dan sangsih, tandai
> tempat menekep, atur tempo, lalu latih seperti pola lainnya.
>
> Main berdua
> Dua pemain, satu layar: satu di polos, satu di sangsih, dan setiap titik
> pertemuan kedua bagian menyala di antara kalian.
>
> Tangan sibuk?
> Bilang "pelan", "cepat", atau "jeda" dan Kotek menurutinya, sementara kedua
> tanganmu tetap memegang panggul.
>
> Juga
> • Pola kotekan dari berbagai tingkat, mulai dari Ubitan Nyendok
> • Panduan tekep yang menunjukkan kapan tangan kiri menghentikan bilah
> • Panduan tentang kotekan, polos dan sangsih, dan cara memasang sensor
> • Untuk iPhone dan iPad, dalam Bahasa Indonesia dan Inggris
> • Main sebagai tamu, atau masuk dengan Apple untuk menyimpan gangsa, pola,
>   dan rekormu di semua perangkat
>
> Kotek membutuhkan gangsa (pemade atau kantilan) untuk dimainkan bersama.
> Pengontrol pukulan bersifat opsional.

**Keywords**:
`gamelan,bali,kotekan,polos,sangsih,pemade,kantilan,metalofon,indonesia,perkusi,musik,ubit`

## 5. App Privacy (changed since v1 — v1 said "no data collected")

**Data is collected** for signed-in players only (Sign in with Apple; guests
keep everything on the device). Not used for tracking. For each type below:
*linked to the user*, purpose **App Functionality** only.

| Category | Type | What it is |
|---|---|---|
| Contact Info | **Name** | From Sign in with Apple, if shared |
| Identifiers | **User ID** | The account ID |
| User Content | **Photos or Videos** | The gangsa's photo |
| User Content | **Audio Data** | Each bilah's recorded sound |
| User Content | **Other User Content** | Gangsa setups, Studio patterns, practice records |

Not collected: the microphone for voice commands is processed on the
device (speech recognition runs on-device); the session
overview is written by Apple Intelligence on the device.

`PrivacyInfo.xcprivacy` lists all five from 2.0.1 (10). Build 9 (2.0.0) left
out **Photos or Videos** and **Audio Data**; App Store Connect's answers are
what the label shows, so 2.0.0's label was already right.

**Privacy policy** (must be at a public URL; update v1's):

> Kotek works without an account. As a guest, everything — your gangsa, its
> photo and recorded sounds, your patterns and practice records — stays on
> your device and is deleted with the app.
>
> If you sign in with Apple, Kotek stores your account ID, the name you
> choose to share, and that same data (gangsa setups, photos, recorded bilah
> sounds, patterns and practice records) on our server (Supabase), so it is
> there on all your devices. It is used only to run the app: no analytics,
> no advertising, no tracking, and it is never sold or shared.
>
> The microphone is used to record your bilah when you add a gangsa, and
> while you play to hear voice commands. Speech is recognised on your device; only
> the bilah recordings you save are uploaded. Bluetooth connects the Kotek
> strike controller. Session feedback is written on your device by Apple
> Intelligence.
>
> Delete your account any time in Settings → Account → Delete account: your
> data is removed from our server and your Sign in with Apple link is
> revoked. Questions: <your email>.

## 6. Sign-in and age rating

- **Sign-In Information**: not required — the reviewer can tap *Continue as
  guest*. Untick "Sign-in required".
- **Age rating**: answer *None* to every content question → **4+**. No
  user-generated content is shared between users (each player's gangsa and
  patterns are visible only to them).

## 7. App Review notes

> Kotek is a practice app for the Balinese gangsa, a bronze metallophone.
> v2 replaces the camera of v1 with an optional Bluetooth strike controller
> (a sensor under each bar) and a "waterfall" of notes on a drawn gangsa.
>
> No instrument or hardware is needed to review it:
> 1. Tap "Continue as guest" (Sign in with Apple is optional).
> 2. Add a gangsa: name it, choose 10 bilah. On the recording step tap Skip;
>    on the sensor step tap Skip.
> 3. Choose a kotekan → Learn: Watch, Listen, Note by note (tap the screen
>    for each note), Build up. Or Free play — without sensors it runs
>    unscored and the bars play themselves.
> 4. Studio: the + on the kotekan picker opens the composer.
> 5. Coop: the Solo menu on the kotekan picker.
>
> Scoring needs the strike controller, which is optional hardware; a video of
> a session with it on a real gangsa: <link to an unlisted video>.
>
> Account deletion: Settings → Account → Delete account (signed-in users).
> Microphone: recording each bilah's sound when adding a gangsa, and voice
> commands, processed on the device. Bluetooth: the strike controller.
