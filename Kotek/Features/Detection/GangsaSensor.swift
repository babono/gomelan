//
//  GangsaSensor.swift
//  Kotek
//
//  BLE central for the piezo prototype: an ESP32 ("Gangsa-Sensor") with one
//  piezo disc per bilah does the hit detection itself — threshold, ring-down
//  rejection, 4 ms loudest-wins crosstalk window — and pushes only results.
//
//  EVENT (…0002…) · 8 bytes per hit:
//    [0] type (1 = hit, 2 = damp, reserved)  [1] bar 0…2
//    [2–3] peak strength 0…4095 LE          [4–7] ESP32 millis() LE
//  LEVEL (…0003…) · 3 bytes, one 0…255 vibration level per bar, 50 Hz.
//
//  The sensor answers WHICH bar and WHEN with no camera at all, which is what
//  `SensorPlayView` exists to show. It does not yet join the vision/audio
//  fusion in `PlayView`.
//
//  ponytail: lives beside its only screen. Promote to `Core/` when PlayView
//  starts taking sensor strikes.
//

import CoreBluetooth
import QuartzCore

@Observable
final class GangsaSensor: NSObject {
    enum Status: Equatable {
        case off, scanning, connecting, connected
        case unavailable(String)
    }

    struct Hit: Identifiable, Equatable {
        let id = UUID()
        let bar: Int
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
    static let barCount = 3
    static let deviceName = "Gangsa-Sensor"

    private(set) var status: Status = .off
    private(set) var levels: [Double] = Array(repeating: 0, count: barCount)
    private(set) var hits: [Hit] = []
    /// Hits per bar since the last `clearHits`. The log scrolls; these do not.
    private(set) var hitCounts: [Int] = Array(repeating: 0, count: barCount)
    /// Raw packet tallies, so a silent screen can be told apart from a silent
    /// sensor: levels climbing with no events means the ESP32's threshold is
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

    func start() {
        // Main queue: the delegate callbacks land where the UI state lives.
        if central == nil { central = CBCentralManager(delegate: self, queue: nil) }
        else { scan() }
    }

    func stop() {
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        central?.stopScan()
        peripheral = nil
        central = nil
        status = .off
        levels = Array(repeating: 0, count: Self.barCount)
    }

    func clearHits() {
        hits = []
        hitCounts = Array(repeating: 0, count: Self.barCount)
        lastSensorMs = nil
    }

    private func scan() {
        guard let central, central.state == .poweredOn else { return }
        //R Already connected to the system — by the standalone prototype app,
        //R or a connection iOS kept up after it closed. The ESP32 stops
        //R advertising while connected, so a scan alone would wait forever;
        //R iOS shares the link, so we can simply connect to it as well.
        if let existing = central.retrieveConnectedPeripherals(withServices: [Self.service]).first {
            connect(existing)
            return
        }
        status = .scanning
        seenDevices = []
        //R Unfiltered, matched by hand in `didDiscover`. Filtering on the
        //R service UUID found nothing: a 128-bit UUID plus the name does not
        //R fit the 31-byte advertisement, so the ESP32 Arduino stack moves the
        //R UUID into the scan response, which iOS's service filter can miss.
        //R The name is in the primary packet.
        //R
        //R Duplicates ON: unfiltered, iOS reports each device once, and if that
        //R one report predates the scan response there is nothing to match and
        //R the ESP32 is never offered again. Fine for a foreground dev screen.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    private func connect(_ peripheral: CBPeripheral) {
        central?.stopScan()
        self.peripheral = peripheral   // must be retained or CB drops it
        peripheral.delegate = self
        status = .connecting
        central?.connect(peripheral)
    }

    private func ingestEvent(_ data: Data) {
        let b = [UInt8](data)
        eventPackets += 1
        guard b.count >= 8, b[0] == 1, Int(b[1]) < Self.barCount else {
            rejectedPackets += 1
            return
        }
        let strength = Int(b[2]) | Int(b[3]) << 8
        let ms = UInt32(b[4]) | UInt32(b[5]) << 8 | UInt32(b[6]) << 16 | UInt32(b[7]) << 24

        let sent = Double(ms) / 1000
        let offset = min(clockOffset ?? .infinity, CACurrentMediaTime() - sent)
        clockOffset = offset

        let hit = Hit(bar: Int(b[1]), strength: strength, sensorMs: ms,
                      hostTime: sent + offset,
                      intervalMs: lastSensorMs.map { Int(ms &- $0) })
        lastSensorMs = ms
        hitCounts[hit.bar] += 1
        onHit?(hit)
        hits.insert(hit, at: 0)
        if hits.count > 40 { hits.removeLast() }
    }

    private func ingestLevels(_ data: Data) {
        let b = [UInt8](data)
        levelPackets += 1
        guard b.count >= Self.barCount else { return }
        levels = b.prefix(Self.barCount).map { Double($0) / 255 }
    }
}

// CoreBluetooth calls these on the queue the manager was made with — main, see
// `start()` — so hopping onto the main actor is an assertion, not a dispatch.
extension GangsaSensor: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn: scan()
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
        MainActor.assumeIsolated {
            guard status == .scanning else { return }
            //R Loose on the name: firmware gets renamed ("Gangsa-Sensor-3",
            //R "GangsaSensor") far more often than the service UUID changes.
            if services.contains(Self.service)
                || name?.localizedCaseInsensitiveContains("gangsa") == true {
                connect(peripheral)
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
        MainActor.assumeIsolated { scan() }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            self.peripheral = nil
            levels = Array(repeating: 0, count: Self.barCount)
            scan()   // the ESP32 re-advertises on its own
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else { return }
            peripheral.discoverCharacteristics([Self.eventChar, Self.levelChar], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for c in service.characteristics ?? [] { peripheral.setNotifyValue(true, for: c) }
            status = .connected
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard let data = characteristic.value else { return }
            switch characteristic.uuid {
            case Self.eventChar: ingestEvent(data)
            case Self.levelChar: ingestLevels(data)
            default: break
            }
        }
    }
}
