// Gangsa strike controller: multi-piezo hit detection + plug detection +
// Bluetooth LE to the Gomelan iOS app (PRD §3.6).
// Board: ESP32 Dev Module, Upload Speed 115200
//
// What changed from gangsa_ble.ino:
//   - Plug detection: every input jack has a detect switch, so the controller
//     knows which inputs have a sensor in them. Hits on empty inputs are
//     ignored, and the app is told whenever a sensor is plugged in or pulled
//     out (INPUTS characteristic).
//   - INFO characteristic: hardware ID, input count, plug-detect flag and the
//     plugged-in set, so the app can tell controllers apart and reconnect to
//     the right one.
//   - The advertised name ends with the last 2 bytes of the hardware ID
//     ("Gangsa-Sensor-E5F6"), so a room with several controllers can be told
//     apart before connecting.
//   - Byte [1] of EVENT is now an INPUT number. Which bilah that input's sensor
//     sits on is the app's business (it learns it per gangsa during setup).
//   - Up to 16 inputs through two CD74HC4067 multiplexers (USE_MUX = 1), or a
//     few inputs wired straight to GPIOs (USE_MUX = 0, the default — the
//     current 3-sensor breadboard plus 3 detect wires).
//   - A 4-digit PIN (protocol 2). With none set the controller is open, as
//     before. The first phone to set one becomes its OWNER: it also hands the
//     controller a random 32-byte owner key, kept in that phone's iCloud
//     Keychain. After that a connection gets no hits, levels or plug changes
//     until it proves it knows the PIN (or the owner key), and only an owner
//     connection may change the PIN. Hold BOOT for 10 s to forget both.
//
// BLE layout (custom service 7a1f0001-…):
//   EVENT  (…0002, notify) - 8 bytes per hit:
//     [0] type        1 = hit (2 = damp, reserved for later)
//     [1] input       0 … NUM_CH-1
//     [2..3] strength uint16 LE (0-4095)
//     [4..7] time     uint32 ms since ESP32 boot, LE
//   LEVEL  (…0003, notify) - NUM_CH bytes, one 0-255 level per input, 50x/s.
//                            Empty inputs read 0.
//   INFO   (…0004, read)   - [0..5]  hardware ID (Bluetooth MAC)
//                            [6]     input count (NUM_CH)
//                            [7]     flags, bit 0 = has plug detect
//                            [8..11] plugged-in bitmask LE (bit n = input n)
//                            [12]    protocol version
//                            [13..]  firmware version, UTF-8
//   INPUTS (…0005, notify) - 4 bytes, plugged-in bitmask LE, sent on every
//                            plug / unplug (and readable any time).
//   AUTH   (…0006, read/write/notify) - the lock. Read or notified:
//                            [0]     access 0 = open (no PIN), 1 = locked,
//                                    2 = unlocked with the PIN, 3 = owner
//                            [1]     result of the last write: 0 = ok,
//                                    1 = wrong, 2 = too many tries, 3 = not
//                                    allowed
//                            [2..17] challenge, fresh per connection and after
//                                    every wrong answer
//                            [18]    seconds left of a lockout
//                          Written:
//                            01 PIN[4] OWNERKEY[32]  claim, only while open
//                            02 HMAC[32]             unlock with the PIN
//                            03 HMAC[32]             unlock as the owner
//                            04 PIN[4]               change the PIN, owner only
//                          HMAC = HMAC-SHA256(key = the 4 ASCII PIN digits or
//                          the owner key, message = the challenge), so neither
//                          secret crosses the air after it is set. Setting one
//                          does send it in the clear, once — acceptable for
//                          keeping other students off a controller, not for
//                          anything worth sniffing for.
//   INFO [7] bit 1 = a PIN is set, so the app knows to ask before it waits.
//
// ---------------------------------------------------------------------------
// Plug-detect wiring
//
// Use jacks with an ISOLATED switch contact (e.g. 3.5 mm PJ-307 / 5-pin
// "switched" jacks), so the detect line never touches the piezo signal:
//
//   detect pin (INPUT_PULLUP) ── jack switch lug
//   jack switch other lug ────── GND
//
// With the jack EMPTY the switch is closed → the pin reads LOW.
// A plug lifts the switch → the pin is pulled HIGH → "plugged".
// If your jacks work the other way round, flip PLUGGED_LEVEL below.
//
// GPIO 34, 35, 36, 39 have no internal pull-ups — never use them for detect
// lines without an external 10k pull-up to 3.3 V.
//
// Each piezo still needs its own 1M resistor to GND at the ADC side (as on
// the current breadboard), so an input does not float.
// ---------------------------------------------------------------------------

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Preferences.h>
#include <mbedtls/md.h>
#if __has_include(<esp_mac.h>)
#include <esp_mac.h>      // arduino-esp32 3.x
#include <esp_random.h>
#else
#include <esp_system.h>   // arduino-esp32 2.x
#endif

#define FIRMWARE_VERSION "2.1.0"
#define PROTOCOL_VERSION 2
#define DEVICE_PREFIX    "Gangsa-Sensor-"
#define SERVICE_UUID "7a1f0001-5c3e-4b8e-9d2a-6e0b1c2d3e4f"
#define EVENT_UUID   "7a1f0002-5c3e-4b8e-9d2a-6e0b1c2d3e4f"
#define LEVEL_UUID   "7a1f0003-5c3e-4b8e-9d2a-6e0b1c2d3e4f"
#define INFO_UUID    "7a1f0004-5c3e-4b8e-9d2a-6e0b1c2d3e4f"
#define INPUTS_UUID  "7a1f0005-5c3e-4b8e-9d2a-6e0b1c2d3e4f"
#define AUTH_UUID    "7a1f0006-5c3e-4b8e-9d2a-6e0b1c2d3e4f"

// ---------- Board wiring ----------

// 0 = sensors and detect switches wired straight to GPIOs (a few inputs).
// 1 = 14 inputs through two CD74HC4067 16-channel multiplexers sharing one
//     select bus: one analog mux for the piezos, one for the detect switches.
//     The ESP32 has only 6 usable ADC1 pins, so 14 inputs need the mux.
#define USE_MUX 0

// 1 = this board has detect switches on its jacks. 0 = every input counts as
// plugged in, INFO says "no plug detect", and the app falls back to letting
// the player mark keys without a sensor.
#define HAS_PLUG_DETECT 1

// Level the detect pin reads when a plug IS inserted (see wiring note above).
const int PLUGGED_LEVEL = HIGH;

#if USE_MUX
const int NUM_CH = 14;                         // inputs 1-14 = mux channels 0-13
const int MUX_SELECT[4] = {18, 19, 21, 22};    // S0..S3, shared by both muxes
const int MUX_PIEZO_SIG = 34;                  // analog mux SIG → ADC1 pin
const int MUX_DETECT_SIG = 27;                 // detect mux SIG → pin with pull-up
#else
const int NUM_CH = 3;
const int PIEZO_PINS[NUM_CH] = {34, 35, 32};   // input 1 = D34, 2 = D35, 3 = D32 (all ADC1)
const int DETECT_PINS[NUM_CH] = {25, 26, 27};  // detect switch per jack (pull-up capable)
#endif

const int LED_PIN = 2;                  // built-in LED
const int RESET_PIN = 0;                // the BOOT button, LOW while pressed
const unsigned long LED_MS = 80;
const unsigned long LEVEL_EVERY_MS = 20;   // 50 level updates per second

// ---------- Detection settings ----------
const int THRESHOLD = 150;              // raw ADC units (0-4095). Raise if you get false hits.
const unsigned long ARB_MS = 4;         // after a trigger, compare all inputs this long, loudest wins
const unsigned long MASK_MS = 50;       // same input can't re-trigger sooner than this
const unsigned long GLOBAL_MASK_MS = 30; // no input can trigger this soon after any hit (crosstalk)
const float RETRIGGER_RATIO = 1.4f;     // a new hit must be 1.4x the input's recent ringing level
const float ENV_DECAY_PER_MS = 0.993f;  // ringing envelope halves in about 100 ms

// ---------- Plug detection settings ----------
const unsigned long PLUG_SCAN_MS = 10;     // how often the detect switches are read
const int PLUG_STABLE_SCANS = 5;           // a change must hold this many scans (~50 ms) to count
// Pushing a jack in makes a big spike on the piezo line. Ignore the input for
// this long after it is plugged in, so the plug itself is never a "hit".
const unsigned long PLUG_SETTLE_MS = 300;

// ---------- PIN settings ----------
// A locked connection is dropped after this long. The ESP32 stops advertising
// while anything is connected, so a phone that never unlocks would otherwise
// keep the owner out. Long enough to type four digits.
const unsigned long AUTH_TIMEOUT_MS = 60000;
// 10 000 PINs: without a limit a script tries them all in minutes.
const int MAX_TRIES = 5;
const unsigned long LOCKOUT_MS = 30000;
// Held this long, BOOT forgets the PIN and the owner. Long, because the
// button is also how the board is flashed and it is easy to brush.
const unsigned long RESET_HOLD_MS = 10000;

struct Channel {
  float env = 0;            // envelope of recent vibration on this input
  float envHist[8] = {0};   // envelope history, one entry per ms
  int windowMax = 0;        // loudest reading since the last level report
  int arbPeak = 0;          // loudest reading during the current comparison window
  unsigned long lastHit = 0;
  bool plugged = !HAS_PLUG_DETECT;   // without plug detect, every input is live
  unsigned long pluggedAt = 0;
  int pending = -1;          // detect reading waiting to become stable
  int pendingScans = 0;
};
Channel ch[NUM_CH];
unsigned long envMs = 0, arbStart = 0, lastHitAny = 0, lastPlugScan = 0;
bool arbOpen = false;

uint8_t hardwareId[6];

BLECharacteristic *eventChar = nullptr;
BLECharacteristic *levelChar = nullptr;
BLECharacteristic *infoChar = nullptr;
BLECharacteristic *inputsChar = nullptr;
BLECharacteristic *authChar = nullptr;
BLEServer *bleServer = nullptr;
volatile bool bleConnected = false;
unsigned long lastLevelSent = 0, ledOnAt = 0;
bool ledOn = false;

void onHit(int input, int strength, unsigned long timeMs);   // defined below
void publishInputs();                                         // defined below
void updateInfo();                                            // defined below

// ---------- PIN ----------

enum Access : uint8_t { ACCESS_OPEN = 0, ACCESS_LOCKED = 1, ACCESS_USER = 2, ACCESS_OWNER = 3 };
enum Result : uint8_t { RESULT_OK = 0, RESULT_WRONG = 1, RESULT_LOCKED_OUT = 2, RESULT_NOT_ALLOWED = 3 };

Preferences prefs;
bool hasPin = false;
uint8_t pin[4];
uint8_t ownerKey[32];
// Per connection. Written from the BLE task, read by loop(): single bytes,
// and the worst a torn read can do is send one packet late or early.
volatile uint8_t sessionAccess = ACCESS_OPEN;
uint8_t lastResult = RESULT_OK;
uint8_t challenge[16];
int wrongTries = 0;
// Survives reconnecting, so dropping the link does not reset the count.
// A power cycle does — but whoever can do that can also hold BOOT.
unsigned long lockedUntil = 0;
unsigned long connectedAt = 0;
unsigned long resetPressedAt = 0;

void loadPin() {
  prefs.begin("auth", false);
  hasPin = prefs.getBytes("pin", pin, 4) == 4 && prefs.getBytes("owner", ownerKey, 32) == 32;
}

void forgetPin() {
  prefs.clear();
  hasPin = false;
}

// Hits, levels and plug changes go out only to an unlocked connection.
bool streaming() {
  return sessionAccess != ACCESS_LOCKED;
}

bool validPin(const uint8_t *p) {
  for (int i = 0; i < 4; i++) if (p[i] < '0' || p[i] > '9') return false;
  return true;
}

void publishAuth() {
  unsigned long now = millis();
  uint8_t v[19];
  v[0] = sessionAccess;
  v[1] = lastResult;
  memcpy(v + 2, challenge, 16);
  v[18] = lockedUntil > now ? (uint8_t)min((lockedUntil - now + 999) / 1000, 255UL) : 0;
  authChar->setValue(v, sizeof(v));
  if (bleConnected) authChar->notify();
}

// Compared in constant time: an early exit would say how many bytes were right.
bool proves(const uint8_t *key, size_t keyLen, const uint8_t *mac) {
  uint8_t expect[32];
  mbedtls_md_hmac(mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), key, keyLen,
                  challenge, sizeof(challenge), expect);
  uint8_t diff = 0;
  for (int i = 0; i < 32; i++) diff |= expect[i] ^ mac[i];
  return diff == 0;
}

void unlock(uint8_t role, const uint8_t *key, size_t keyLen, const uint8_t *mac) {
  unsigned long now = millis();
  if (lockedUntil > now) { lastResult = RESULT_LOCKED_OUT; return; }
  if (proves(key, keyLen, mac)) {
    sessionAccess = role; lastResult = RESULT_OK; wrongTries = 0;
    Serial.println(role == ACCESS_OWNER ? "Unlocked as owner" : "Unlocked with PIN");
    return;
  }
  // A new challenge, so a wrong answer cannot simply be replayed with tweaks.
  esp_fill_random(challenge, sizeof(challenge));
  lastResult = RESULT_WRONG;
  if (++wrongTries >= MAX_TRIES) {
    wrongTries = 0;
    lockedUntil = now + LOCKOUT_MS;
    lastResult = RESULT_LOCKED_OUT;
  }
  Serial.println("Wrong PIN");
}

class AuthCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    const uint8_t *d = c->getData();
    size_t n = c->getLength();
    lastResult = RESULT_NOT_ALLOWED;
    if (n == 37 && d[0] == 0x01 && !hasPin && validPin(d + 1)) {
      memcpy(pin, d + 1, 4);
      memcpy(ownerKey, d + 5, 32);
      prefs.putBytes("pin", pin, 4);
      prefs.putBytes("owner", ownerKey, 32);
      hasPin = true;
      sessionAccess = ACCESS_OWNER;
      lastResult = RESULT_OK;
      updateInfo();
      Serial.println("PIN set, this phone is the owner");
    } else if (n == 33 && d[0] == 0x02 && hasPin) {
      unlock(ACCESS_USER, pin, 4, d + 1);
    } else if (n == 33 && d[0] == 0x03 && hasPin) {
      unlock(ACCESS_OWNER, ownerKey, 32, d + 1);
    } else if (n == 5 && d[0] == 0x04 && sessionAccess == ACCESS_OWNER && validPin(d + 1)) {
      memcpy(pin, d + 1, 4);
      prefs.putBytes("pin", pin, 4);
      lastResult = RESULT_OK;
      Serial.println("PIN changed");
    }
    publishAuth();
  }
};

// Hold BOOT for RESET_HOLD_MS: the PIN and the owner are forgotten and the
// controller restarts open, for a lost owner phone or a forgotten PIN. The
// LED stays on while it is held, so you can tell it is counting.
void checkResetButton(unsigned long now) {
  if (digitalRead(RESET_PIN) != LOW) {
    if (resetPressedAt) digitalWrite(LED_PIN, LOW);
    resetPressedAt = 0;
    return;
  }
  if (!resetPressedAt) { resetPressedAt = now; return; }
  if (now - resetPressedAt > 1000) digitalWrite(LED_PIN, HIGH);
  if (now - resetPressedAt < RESET_HOLD_MS) return;
  forgetPin();
  Serial.println("PIN and owner forgotten, restarting");
  for (int i = 0; i < 10; i++) {
    digitalWrite(LED_PIN, HIGH); delay(50);
    digitalWrite(LED_PIN, LOW);  delay(50);
  }
  ESP.restart();
}

// ---------- Reading the hardware ----------

#if USE_MUX
int selectedMux = -1;

void selectMux(int channel) {
  if (channel == selectedMux) return;
  for (int b = 0; b < 4; b++) digitalWrite(MUX_SELECT[b], (channel >> b) & 1);
  selectedMux = channel;
  delayMicroseconds(5);   // let the mux and the ADC's sample capacitor settle
}
#endif

int readPiezo(int i) {
#if USE_MUX
  selectMux(i);
  return analogRead(MUX_PIEZO_SIG);
#else
  return analogRead(PIEZO_PINS[i]);
#endif
}

bool readPlugged(int i) {
#if !HAS_PLUG_DETECT
  return true;
#elif USE_MUX
  selectMux(i);
  return digitalRead(MUX_DETECT_SIG) == PLUGGED_LEVEL;
#else
  return digitalRead(DETECT_PINS[i]) == PLUGGED_LEVEL;
#endif
}

uint32_t pluggedMask() {
  if (!HAS_PLUG_DETECT) return 0;    // INFO's flag says the mask means nothing
  uint32_t mask = 0;
  for (int i = 0; i < NUM_CH; i++) if (ch[i].plugged) mask |= (1UL << i);
  return mask;
}

// Whether an input may produce hits right now.
bool live(const Channel &c, unsigned long now) {
  return c.plugged && now - c.pluggedAt >= PLUG_SETTLE_MS;
}

// ---------- Plug detection ----------

// Debounced: a jack going in or out chatters for a few ms, and a half-seated
// plug can flicker. Only a reading that holds for PLUG_STABLE_SCANS counts.
void scanPlugs(unsigned long now) {
  if (!HAS_PLUG_DETECT || now - lastPlugScan < PLUG_SCAN_MS) return;
  lastPlugScan = now;
  bool changed = false;

  for (int i = 0; i < NUM_CH; i++) {
    Channel &c = ch[i];
    int reading = readPlugged(i) ? 1 : 0;
    if (reading == (c.plugged ? 1 : 0)) {   // matches what we already believe
      c.pending = -1; c.pendingScans = 0;
      continue;
    }
    if (reading != c.pending) { c.pending = reading; c.pendingScans = 0; }
    if (++c.pendingScans < PLUG_STABLE_SCANS) continue;

    c.plugged = reading == 1;
    c.pending = -1; c.pendingScans = 0;
    // A fresh start either way: no envelope or level carried across a re-plug.
    c.env = 0; c.windowMax = 0; c.arbPeak = 0;
    for (int k = 0; k < 8; k++) c.envHist[k] = 0;
    if (c.plugged) c.pluggedAt = now;
    changed = true;
    Serial.printf("Input %d %s\n", i + 1, c.plugged ? "plugged in" : "unplugged");
  }

  if (changed) publishInputs();
}

// Read the switches once at boot, without the debounce, so INFO is right from
// the first connection instead of claiming everything is empty for 50 ms.
void initPlugs() {
  for (int i = 0; i < NUM_CH; i++) {
    ch[i].plugged = readPlugged(i);
    ch[i].pluggedAt = 0;   // already in at boot: no settle time needed
  }
}

// ---------- Hit detection ----------

// Read every live input once, detect hits, and pick the loudest input when
// several react together.
void processChannels(unsigned long now) {
  // Let every envelope decay once per elapsed millisecond
  while (envMs < now) {
    envMs++;
    for (int i = 0; i < NUM_CH; i++) {
      ch[i].env *= ENV_DECAY_PER_MS;
      ch[i].envHist[envMs % 8] = ch[i].env;
    }
  }

  for (int i = 0; i < NUM_CH; i++) {
    Channel &c = ch[i];
    if (!live(c, now)) continue;            // empty or just plugged in: not read at all
    int v = readPiezo(i);
    if (v > c.windowMax) c.windowMax = v;

    float ref = c.envHist[(now - 5) % 8];   // this input's envelope ~5 ms ago
    bool triggered = v > THRESHOLD && v > ref * RETRIGGER_RATIO
                     && now - c.lastHit > MASK_MS && now - lastHitAny > GLOBAL_MASK_MS;

    if (!arbOpen && triggered) {            // first input to react opens a comparison window
      arbOpen = true; arbStart = now;
      for (int k = 0; k < NUM_CH; k++) ch[k].arbPeak = 0;
    }
    if (arbOpen && v > c.arbPeak) c.arbPeak = v;
    if (v > c.env) c.env = v;
  }

  // Window over: the loudest input is the one that was struck; the others were crosstalk
  if (arbOpen && now - arbStart >= ARB_MS) {
    arbOpen = false;
    int win = -1;
    for (int i = 0; i < NUM_CH; i++) {
      if (!live(ch[i], now)) continue;      // pulled out mid-window
      if (win < 0 || ch[i].arbPeak > ch[win].arbPeak) win = i;
    }
    if (win < 0) return;
    ch[win].lastHit = now; lastHitAny = now;
    onHit(win, ch[win].arbPeak, arbStart);
  }
}

// ---------- BLE ----------

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    sessionAccess = hasPin ? ACCESS_LOCKED : ACCESS_OPEN;
    lastResult = RESULT_OK;
    esp_fill_random(challenge, sizeof(challenge));
    connectedAt = millis();
    bleConnected = true;
    publishAuth();
    Serial.println(hasPin ? "Phone connected, waiting for the PIN" : "Phone connected");
  }
  void onDisconnect(BLEServer *server) override {
    bleConnected = false;
    sessionAccess = hasPin ? ACCESS_LOCKED : ACCESS_OPEN;
    Serial.println("Phone disconnected, advertising again");
    BLEDevice::startAdvertising();
  }
};

// INFO is read, not notified: kept current so a read always tells the truth.
void updateInfo() {
  const char *fw = FIRMWARE_VERSION;
  size_t fwLen = strlen(fw);
  if (fwLen > 16) fwLen = 16;
  uint8_t info[13 + 16];
  uint32_t mask = pluggedMask();
  memcpy(info, hardwareId, 6);
  info[6] = NUM_CH;
  info[7] = (HAS_PLUG_DETECT ? 0x01 : 0x00) | (hasPin ? 0x02 : 0x00);
  info[8] = (uint8_t)mask; info[9] = (uint8_t)(mask >> 8);
  info[10] = (uint8_t)(mask >> 16); info[11] = (uint8_t)(mask >> 24);
  info[12] = PROTOCOL_VERSION;
  memcpy(info + 13, fw, fwLen);
  infoChar->setValue(info, 13 + fwLen);
}

// A sensor went in or out: INFO stays current, and a connected app is told.
void publishInputs() {
  updateInfo();
  uint32_t mask = pluggedMask();
  uint8_t p[4] = {(uint8_t)mask, (uint8_t)(mask >> 8), (uint8_t)(mask >> 16), (uint8_t)(mask >> 24)};
  inputsChar->setValue(p, sizeof(p));
  if (bleConnected && streaming()) inputsChar->notify();
}

void setupBLE() {
  // The name carries the last 2 bytes of the hardware ID, e.g. Gangsa-Sensor-E5F6.
  char name[32];
  snprintf(name, sizeof(name), DEVICE_PREFIX "%02X%02X", hardwareId[4], hardwareId[5]);
  BLEDevice::init(name);
  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new ServerCallbacks());

  // 5 characteristics with descriptors need more handles than the default 15.
  BLEService *service = bleServer->createService(BLEUUID(SERVICE_UUID), 24);

  eventChar = service->createCharacteristic(
      EVENT_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  eventChar->addDescriptor(new BLE2902());

  levelChar = service->createCharacteristic(
      LEVEL_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  levelChar->addDescriptor(new BLE2902());

  infoChar = service->createCharacteristic(INFO_UUID, BLECharacteristic::PROPERTY_READ);

  inputsChar = service->createCharacteristic(
      INPUTS_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  inputsChar->addDescriptor(new BLE2902());

  authChar = service->createCharacteristic(
      AUTH_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY);
  authChar->addDescriptor(new BLE2902());
  authChar->setCallbacks(new AuthCallbacks());
  publishAuth();

  publishInputs();   // fills INFO and INPUTS before anyone can read them
  service->start();

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);   // the 128-bit UUID and the name don't both fit in 31 bytes
  BLEDevice::startAdvertising();
  Serial.printf("Advertising as %s\n", name);
}

void onHit(int input, int strength, unsigned long timeMs) {
  digitalWrite(LED_PIN, HIGH); ledOn = true; ledOnAt = millis();
  Serial.printf("HIT input=%d strength=%d t=%lu\n", input + 1, strength, timeMs);
  if (!bleConnected || !streaming()) return;
  uint32_t t = (uint32_t)timeMs;
  uint16_t s = (uint16_t)strength;
  uint8_t p[8] = {
    1, (uint8_t)input,
    (uint8_t)(s & 0xFF), (uint8_t)(s >> 8),
    (uint8_t)(t), (uint8_t)(t >> 8), (uint8_t)(t >> 16), (uint8_t)(t >> 24)
  };
  eventChar->setValue(p, sizeof(p));
  eventChar->notify();
}

void sendLevels() {
  uint8_t lv[NUM_CH];
  for (int i = 0; i < NUM_CH; i++) {
    lv[i] = ch[i].plugged ? (uint8_t)min(ch[i].windowMax >> 4, 255) : 0;  // 0-4095 -> 0-255
  }
  levelChar->setValue(lv, NUM_CH);
  levelChar->notify();
}

// ---------- Main ----------

void setup() {
  Serial.begin(115200);
  analogReadResolution(12);
  pinMode(LED_PIN, OUTPUT);
  pinMode(RESET_PIN, INPUT_PULLUP);
  loadPin();

#if USE_MUX
  for (int b = 0; b < 4; b++) pinMode(MUX_SELECT[b], OUTPUT);
  pinMode(MUX_DETECT_SIG, INPUT_PULLUP);
#else
  for (int i = 0; i < NUM_CH; i++) pinMode(DETECT_PINS[i], INPUT_PULLUP);
#endif

  esp_read_mac(hardwareId, ESP_MAC_BT);
  Serial.printf("Hardware ID %02X%02X%02X%02X%02X%02X, %d inputs, plug detect %s\n",
                hardwareId[0], hardwareId[1], hardwareId[2],
                hardwareId[3], hardwareId[4], hardwareId[5],
                NUM_CH, HAS_PLUG_DETECT ? "on" : "off");
  Serial.println(hasPin ? "PIN set: locked until a phone unlocks it" : "No PIN: open to any phone");

  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_PIN, HIGH); delay(150);
    digitalWrite(LED_PIN, LOW);  delay(150);
  }
  if (HAS_PLUG_DETECT) initPlugs();
  setupBLE();
}

void loop() {
  unsigned long now = millis();
  checkResetButton(now);
  scanPlugs(now);

  if (bleConnected && sessionAccess == ACCESS_LOCKED && now - connectedAt > AUTH_TIMEOUT_MS) {
    Serial.println("No PIN in time, dropping the phone");
    bleServer->disconnect(bleServer->getConnId());
    connectedAt = now;   // once: onDisconnect follows
  }
  processChannels(now);

  if (ledOn && now - ledOnAt >= LED_MS) { digitalWrite(LED_PIN, LOW); ledOn = false; }

  if (now - lastLevelSent >= LEVEL_EVERY_MS) {
    if (bleConnected && streaming()) sendLevels();
    for (int i = 0; i < NUM_CH; i++) ch[i].windowMax = 0;
    lastLevelSent = now;
  }
}
