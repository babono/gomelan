//
//  GangsaSensor.swift
//  Kotek
//
//  BLE central for the strike controller (PRD §3.6): an ESP32 with up to 14
//  inputs, one piezo sensor per bilah plugged into them. The controller does
//  the hit detection itself — threshold, ring-down rejection, 4 ms
//  loudest-wins crosstalk window — and pushes only results.
//
//  EVENT (…0002…) · 8 bytes per hit:
//    [0] type (1 = hit, 2 = damp, reserved)  [1] input 0…N-1
//    [2–3] peak strength 0…4095 LE          [4–7] ESP32 millis() LE
//  LEVEL (…0003…) · N bytes, one 0…255 vibration level per input, 50 Hz.
//  INFO (…0004…) · read: [0–5] hardware ID · [6] input count · [7] flags
//    (bit 0 = plug detect) · [8–11] plugged-in bitmask LE · [12] protocol
//    version · [13…] firmware version, UTF-8.
//  INPUTS (…0005…) · notify: 4-byte plugged-in bitmask LE, on every plug /
//    unplug. Only the plug-detect board sends it.
//
//  One controller is shared between gangsa, so this knows nothing about keys:
//  it reports INPUTS. Which bilah an input's sensor sits on is per gangsa and
//  lives on the profile (`InstrumentKey.sensorInput`).
//
//  One instance for the app (see `Container.sensorService`). Whoever is on
//  screen says what it wants with `use(_:)`: RootView follows the active
//  gangsa's controller, the setup screen browses, the sensor test takes any.
//

import CoreBluetooth
import QuartzCore

@Observable
final class GangsaSensor: NSObject {
    enum Status: Equatable {
        case off, scanning, connecting, connected
        case unavailable(String)
    }

    /// What the screen on top wants from Bluetooth.
    enum Target: Equatable {
        case none
        /// The first controller that turns up — the sensor test's prototype mode.
        case any
        /// Scan and list, connect to nothing: the setup screen's scanning step.
        case browse
        /// The one the player tapped in the list.
        case picked(UUID)
        /// The one a gangsa was set up with, by its hardware ID (§3.6.1).
        case hardware(String)
    }

    /// What the controller says about itself, from INFO.
    struct Info: Equatable {
        var hardwareID: String
        var name: String
        var inputCount: Int
        var hasPlugDetect: Bool
        /// Inputs with a sensor in them. Empty without plug detect.
        var plugged: Set<Int>
        var firmware: String?

        /// The inputs a sensor can be on: the plugged-in ones when the
        /// controller can tell, otherwise all of them.
        var availableInputs: [Int] {
            hasPlugDetect ? plugged.sorted() : Array(0 ..< inputCount)
        }
    }

    /// A controller heard in the scan.
    struct Found: Identifiable, Equatable {
        let id: UUID
        var name: String
        var rssi: Int
    }

    struct Hit: Identifiable, Equatable {
        let id = UUID()
        let input: Int
        let strength: Int
        let sensorMs: UInt32
        /// On the `CACurrentMediaTime` clock, so it can go straight into
        /// `PlayEngine.registerStrike`.
        let hostTime: Double
        /// Measured on the ESP32's clock — exact, whatever BLE did in between.
        let intervalMs: Int?
    }

    static let service = CBUUID(string: "7A1F0001-5C3E-4B8E-9D2A-6E0B1C2D3E4F")
    static let eventChar = CBUUID(string: "7A1F0002-5C3E-4B8E-9D2A-6E0B1C2D3E4F")
    static let levelChar = CBUUID(string: "7A1F0003-5C3E-4B8E-9D2A-6E0B1C2D3E4F")
    static let infoChar = CBUUID(string: "7A1F0004-5C3E-4B8E-9D2A-6E0B1C2D3E4F")
    static let inputsChar = CBUUID(string: "7A1F0005-5C3E-4B8E-9D2A-6E0B1C2D3E4F")
    /// What the prototype firmware, which has no INFO, is wired with.
    static let legacyInputCount = 3
    static let legacyPrefix = "LEGACY-"

    private(set) var target: Target = .none
    private(set) var status: Status = .off
    /// Nil until INFO has been read — `status` only says `.connected` after.
    private(set) var info: Info?
    /// Controllers heard while browsing, strongest signal first.
    private(set) var found: [Found] = []
    private(set) var levels: [Double] = []
    private(set) var hits: [Hit] = []
    /// Hits per input since the last `clearHits`. The log scrolls; these do not.
    private(set) var hitCounts: [Int] = []
    /// Raw packet tallies, so a silent screen can be told apart from a silent
    /// controller: levels climbing with no events means the ESP32's threshold is
    /// too high; rejected climbing means the packet format disagrees.
    private(set) var eventPackets = 0
    private(set) var levelPackets = 0
    private(set) var rejectedPackets = 0
    /// Names of everything the scan has heard, for when it never finds ours:
    /// an empty list means the phone hears nothing at all; a list without
    /// Gangsa-Sensor means the ESP32 is not advertising (or is already
    /// connected to something else — it stops advertising while it is).
    private(set) var seenDevices: [String] = []
    /// Main-actor callback for every hit, before it is appended to `hits`.
    var onHit: ((Hit) -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var lastSensorMs: UInt32?
    /// Controllers that answered INFO with the wrong hardware ID during this
    /// search, so the scan stops offering them.
    private var rejected: Set<UUID> = []

    /// Sensor clock → host clock. Each packet's arrival bounds the offset from
    /// above (it cannot arrive before it was sent), so the SMALLEST
    /// arrival − sent seen is the closest to the true offset: BLE jitter only
    /// ever adds delay. Taking the latest instead would carry each packet's
    /// connection-interval jitter (7.5–30 ms) straight into the judged time,
    /// and the whole point of the ESP32 stamping hits is to keep that out.
    ///
    /// ponytail: never re-estimated, so the two crystals drift apart over a
    /// long session (tens of ppm — a few ms an hour). Reset on reconnect.
    private var clockOffset: Double?

    var isReady: Bool {
        status == .connected && info != nil
    }

    /// Ready, and the controller this gangsa was set up with.
    func isConnected(to hardwareID: String) -> Bool {
        isReady && info?.hardwareID == hardwareID
    }

    // MARK: - Control

    /// Switch what Bluetooth is doing. Keeps the current connection whenever it
    /// already satisfies the new target — gangsa A → B on the same controller,
    /// or browsing while connected (the ESP32 stops advertising while it is, so
    /// dropping it to browse would make it vanish from the list).
    func use(_ next: Target) {
        guard next != target else { return }
        target = next
        rejected = []
        if next == .none {
            teardown()
            return
        }
        if central == nil {
            // Main queue: the delegate callbacks land where the UI state lives.
            // `centralManagerDidUpdateState` carries on from here.
            central = CBCentralManager(delegate: self, queue: nil)
            return
        }
        if let peripheral, satisfies(peripheral) {
            central?.stopScan()
            if next == .browse {
                // Keep it, list it, and look for the others too.
                listConnected()
                startScan()
            }
            return
        }
        disconnect()
        search()
    }

    /// Browse → the row the player tapped.
    func connect(_ found: Found) {
        use(.picked(found.id))
    }

    func clearHits() {
        hits = []
        hitCounts = Array(repeating: 0, count: hitCounts.count)
        lastSensorMs = nil
    }

    private func teardown() {
        disconnect()
        central?.stopScan()
        central = nil
        status = .off
        found = []
    }

    private func disconnect() {
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        info = nil
        levels = []
    }

    private func satisfies(_ p: CBPeripheral) -> Bool {
        switch target {
        case .none: false
        case .any, .browse: true
        case .picked(let id): p.identifier == id
        // Before INFO is in, an in-flight connection to the cached peripheral
        // counts; INFO settles it either way.
        case .hardware(let hw): info.map { $0.hardwareID == hw } ?? (p.identifier == Self.cachedPeripheral(for: hw))
        }
    }

    private func search() {
        guard let central, central.state == .poweredOn else { return }
        switch target {
        case .none:
            return
        case .picked(let id):
            if let p = central.retrievePeripherals(withIdentifiers: [id]).first {
                connect(p)
                return
            }
        case .hardware(let hw):
            // The fast path, on a phone that has met this controller: a pending
            // connect never times out, so it lands the moment the controller is
            // powered on or back in range.
            if let id = Self.cachedPeripheral(for: hw),
               let p = central.retrievePeripherals(withIdentifiers: [id]).first
            {
                connect(p)
                return
            }
        case .any, .browse:
            break
        }
        //R Already connected to the system — by the standalone prototype app,
        //R or a connection iOS kept up after it closed. The ESP32 stops
        //R advertising while connected, so a scan alone would wait forever;
        //R iOS shares the link, so we can simply connect to it as well.
        let system = central.retrieveConnectedPeripherals(withServices: [Self.service])
        if target == .any, let existing = system.first {
            connect(existing)
            return
        }
        if target == .browse {
            found = system.map { Found(id: $0.identifier, name: $0.name ?? "Gangsa-Sensor", rssi: 0) }
        }
        status = .scanning
        startScan()
    }

    private func startScan() {
        seenDevices = []
        //R Unfiltered, matched by hand in `didDiscover`. Filtering on the
        //R service UUID found nothing: a 128-bit UUID plus the name does not
        //R fit the 31-byte advertisement, so the ESP32 Arduino stack moves the
        //R UUID into the scan response, which iOS's service filter can miss.
        //R The name is in the primary packet.
        //R
        //R Duplicates ON: unfiltered, iOS reports each device once, and if that
        //R one report predates the scan response there is nothing to match and
        //R the ESP32 is never offered again. Fine for foreground screens.
        central?.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    /// While browsing, the controller we are already connected to is not
    /// advertising — list it anyway, or it looks switched off.
    private func listConnected() {
        guard let peripheral else { return }
        let name = info?.name ?? peripheral.name ?? "Gangsa-Sensor"
        if !found.contains(where: { $0.id == peripheral.identifier }) {
            found.insert(Found(id: peripheral.identifier, name: name, rssi: 0), at: 0)
        }
    }

    private func connect(_ p: CBPeripheral) {
        central?.stopScan()
        peripheral = p   // must be retained or CB drops it
        p.delegate = self
        info = nil
        status = .connecting
        central?.connect(p)
    }

    /// Whether an advertised name could be the controller we are looking for.
    private func matches(name: String?, services: [CBUUID], id: UUID) -> Bool {
        guard !rejected.contains(id) else { return false }
        //R Loose on the name: firmware gets renamed ("Gangsa-Sensor-3",
        //R "GangsaSensor") far more often than the service UUID changes.
        let isController = services.contains(Self.service)
            || name?.localizedCaseInsensitiveContains("gangsa") == true
        guard isController else { return false }
        switch target {
        case .any, .browse: return true
        case .picked(let picked): return id == picked
        case .hardware(let hw):
            // The name carries the last 2 bytes of the hardware ID (§3.6.1), so
            // a room full of controllers is narrowed down before connecting.
            // INFO is the real check — this only saves connecting to each.
            guard let name, !hw.hasPrefix(Self.legacyPrefix) else { return false }
            return name.uppercased().hasSuffix(String(hw.suffix(4)))
        case .none: return false
        }
    }

    // MARK: - Peripheral cache

    /// CoreBluetooth's identifier is per phone, so it is cached here and never
    /// synced: keyed by hardware ID, one entry serves every gangsa sharing the
    /// controller.
    static func cachedPeripheral(for hardwareID: String) -> UUID? {
        if hardwareID.hasPrefix(legacyPrefix) {
            return UUID(uuidString: String(hardwareID.dropFirst(legacyPrefix.count)))
        }
        return Defaults.string("controllerPeripheral.\(hardwareID)").flatMap(UUID.init)
    }

    private static func cache(_ id: UUID, for hardwareID: String) {
        guard !hardwareID.hasPrefix(legacyPrefix) else { return }
        Defaults.set("controllerPeripheral.\(hardwareID)", id.uuidString)
    }

    // MARK: - Packets

    private func ingestInfo(_ data: Data, from p: CBPeripheral) {
        let b = [UInt8](data)
        guard b.count >= 13 else {
            rejectedPackets += 1
            return
        }
        let hw = b[0 ..< 6].map { String(format: "%02X", $0) }.joined()
        let mask = UInt32(b[8]) | UInt32(b[9]) << 8 | UInt32(b[10]) << 16 | UInt32(b[11]) << 24
        let plugDetect = b[7] & 1 != 0
        let firmware = b.count > 13 ? String(bytes: b[13...], encoding: .utf8) : nil
        ready(Info(
            hardwareID: hw,
            name: p.name ?? "Gangsa-Sensor-\(hw.suffix(4))",
            inputCount: Int(b[6]),
            hasPlugDetect: plugDetect,
            plugged: plugDetect ? Self.inputs(in: mask) : [],
            firmware: firmware
        ), from: p)
    }

    /// The prototype firmware has no INFO. It is identified by this phone's
    /// own identifier for it instead — so it can be set up and reconnects
    /// here, but a second phone cannot find it.
    ///
    /// ponytail: drop once every controller runs the INFO firmware.
    private func legacyInfo(for p: CBPeripheral) {
        ready(Info(
            hardwareID: Self.legacyPrefix + p.identifier.uuidString,
            name: p.name ?? "Gangsa-Sensor",
            inputCount: Self.legacyInputCount,
            hasPlugDetect: false,
            plugged: [],
            firmware: nil
        ), from: p)
    }

    private func ready(_ next: Info, from p: CBPeripheral) {
        if case .hardware(let hw) = target, next.hardwareID != hw {
            // Someone else's controller with a matching name suffix.
            rejected.insert(p.identifier)
            disconnect()
            search()
            return
        }
        Self.cache(p.identifier, for: next.hardwareID)
        info = next
        levels = Array(repeating: 0, count: next.inputCount)
        if hitCounts.count != next.inputCount { hitCounts = Array(repeating: 0, count: next.inputCount) }
        status = .connected
        if target == .browse { listConnected() }
    }

    private static func inputs(in mask: UInt32) -> Set<Int> {
        Set((0 ..< 32).filter { mask & (1 << $0) != 0 })
    }

    private func ingestInputs(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= 4, info?.hasPlugDetect == true else { return }
        let mask = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
        info?.plugged = Self.inputs(in: mask)
    }

    private func ingestEvent(_ data: Data) {
        let b = [UInt8](data)
        eventPackets += 1
        guard let info, b.count >= 8, b[0] == 1, Int(b[1]) < info.inputCount else {
            rejectedPackets += 1
            return
        }
        let strength = Int(b[2]) | Int(b[3]) << 8
        let ms = UInt32(b[4]) | UInt32(b[5]) << 8 | UInt32(b[6]) << 16 | UInt32(b[7]) << 24

        let sent = Double(ms) / 1000
        let offset = min(clockOffset ?? .infinity, CACurrentMediaTime() - sent)
        clockOffset = offset

        let hit = Hit(input: Int(b[1]), strength: strength, sensorMs: ms,
                      hostTime: sent + offset,
                      intervalMs: lastSensorMs.map { Int(ms &- $0) })
        lastSensorMs = ms
        hitCounts[hit.input] += 1
        onHit?(hit)
        hits.insert(hit, at: 0)
        if hits.count > 40 { hits.removeLast() }
    }

    private func ingestLevels(_ data: Data) {
        let b = [UInt8](data)
        levelPackets += 1
        guard !levels.isEmpty else { return }
        levels = (0 ..< levels.count).map { $0 < b.count ? Double(b[$0]) / 255 : 0 }
    }
}

// CoreBluetooth calls these on the queue the manager was made with — main, see
// `use(_:)` — so hopping onto the main actor is an assertion, not a dispatch.
extension GangsaSensor: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn: search()
            case .unauthorized: status = .unavailable("Bluetooth permission denied")
            case .poweredOff: status = .unavailable("Bluetooth is off")
            case .unsupported: status = .unavailable("No Bluetooth LE")
            default: status = .off
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let rssi = RSSI.intValue
        MainActor.assumeIsolated {
            guard target != .none else { return }
            if matches(name: name, services: services, id: peripheral.identifier) {
                guard target == .browse else {
                    // Advertisements already queued behind the one we took.
                    if self.peripheral == nil { connect(peripheral) }
                    return
                }
                // 127 is CoreBluetooth's "no reading".
                guard rssi != 127 else { return }
                if let i = found.firstIndex(where: { $0.id == peripheral.identifier }) {
                    // Only a real change re-sorts the list: with duplicates on,
                    // every advertisement lands here, and a list reshuffling
                    // under a finger is a list that gets mis-tapped.
                    guard abs(found[i].rssi - rssi) >= 6 else { return }
                    found[i].rssi = rssi
                } else {
                    found.append(Found(id: peripheral.identifier, name: name ?? "Gangsa-Sensor", rssi: rssi))
                }
                found.sort { $0.rssi > $1.rssi }
                return
            }
            //R Nameless devices are listed by their advertised services, so an
            //R ESP32 that drops its name — or carries a mistyped UUID — shows up
            //R here instead of being invisible.
            let label = name ?? services.first.map { "? " + $0.uuidString.prefix(8) }
            if let label, !seenDevices.contains(label) { seenDevices.append(label) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            clockOffset = nil
            lastSensorMs = nil
            peripheral.discoverServices([Self.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            self.peripheral = nil
            search()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            // Our own `disconnect()` already let go of it.
            guard self.peripheral?.identifier == peripheral.identifier else { return }
            self.peripheral = nil
            info = nil
            levels = []
            found.removeAll { $0.id == peripheral.identifier }
            // The ESP32 re-advertises on its own; for a known controller a
            // pending connect is the cheaper wait.
            search()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else { return }
            peripheral.discoverCharacteristics(
                [Self.eventChar, Self.levelChar, Self.infoChar, Self.inputsChar], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            let chars = service.characteristics ?? []
            for c in chars where c.uuid != Self.infoChar { peripheral.setNotifyValue(true, for: c) }
            if let infoChar = chars.first(where: { $0.uuid == Self.infoChar }) {
                peripheral.readValue(for: infoChar)
            } else {
                legacyInfo(for: peripheral)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard let data = characteristic.value else { return }
            switch characteristic.uuid {
            case Self.eventChar: ingestEvent(data)
            case Self.levelChar: ingestLevels(data)
            case Self.infoChar: ingestInfo(data, from: peripheral)
            case Self.inputsChar: ingestInputs(data)
            default: break
            }
        }
    }
}
