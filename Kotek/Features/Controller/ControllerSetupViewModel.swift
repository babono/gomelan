//
//  ControllerSetupViewModel.swift
//  Kotek
//
//  Flow D (PRD §4): find the strike controller, connect, then check which
//  input's sensor sits on each bilah of THIS gangsa. Also the Flow E re-check,
//  which starts straight at the key check with the saved map.
//
//  The check assumes the sensors are clipped on in input order and has the
//  player confirm it: hit key 1, 2, 3… A key heard as another is a swap away
//  from right. The swap, rather than a plain reassign, is what keeps one input
//  from ever ending up on two keys.
//

import Foundation
import Observation

@Observable
@MainActor
final class ControllerSetupViewModel {
    enum Step { case scanning, summary, test }

    /// A hit on the key being checked that belongs to another one.
    struct Mismatch: Equatable {
        let key: Int
        let input: Int
        /// The key that input is on now, nil when it is on none.
        let heardAs: Int?
    }

    let app: AppState
    let sensor: GangsaSensor

    var step: Step = .scanning
    /// The input on each key, by key index (§3.6.5). Nil: no sensor, the key
    /// falls back to camera + mic.
    private(set) var inputForKey: [Int?] = []
    private(set) var checked: Set<Int> = []
    /// The key the player is asked to hit.
    private(set) var current: Int?
    private(set) var mismatch: Mismatch?
    /// The tile the last hit lit, whichever key was being asked for — so a
    /// stroke always shows where it landed.
    private(set) var litKey: Int?
    private(set) var litHit: UUID?

    /// The controller the map was built for. A reconnect to the same one keeps
    /// the progress; another controller starts over.
    private var mapFor: String?

    init(app: AppState, sensor: GangsaSensor) {
        self.app = app
        self.sensor = sensor
    }

    var keyCount: Int {
        app.profile.keyCount
    }

    /// Every key with a sensor has been confirmed.
    var isDone: Bool {
        !inputForKey.isEmpty
            && inputForKey.indices.allSatisfy { inputForKey[$0] == nil || checked.contains($0) }
    }

    var sensorCount: Int {
        inputForKey.compactMap(\.self).count
    }

    /// The other gangsa a controller in the list is already set up on. Matched
    /// by the advertised name, since the hardware ID is only known after
    /// connecting.
    func alsoOn(_ found: GangsaSensor.Found) -> [String] {
        app.savedProfiles
            .filter { $0.id != app.profile.id && $0.controller?.name == found.name }
            .map(\.name)
    }

    func isThisGangsas(_ found: GangsaSensor.Found) -> Bool {
        app.profile.controller?.name == found.name
    }

    // MARK: - Lifecycle

    func onAppear() {
        sensor.onHit = { [weak self] hit in self?.handle(hit) }
        if app.controllerSetupRecheck, let link = app.profile.controller {
            step = .test
            sensor.use(.hardware(link.hardwareId))
        } else {
            sensor.use(.browse)
        }
        infoChanged()
    }

    func onDisappear() {
        sensor.onHit = nil
        // Not `use(.none)`: RootView hands the controller back to the active
        // gangsa as this screen goes, and may already have.
    }

    // MARK: - Steps

    func pick(_ found: GangsaSensor.Found) {
        sensor.connect(found)
        step = .summary
    }

    /// Summary → the list again. The connection is kept and listed; picking
    /// another one is what drops it.
    func backToScan() {
        step = .scanning
        sensor.use(.browse)
    }

    func startTest() {
        step = .test
        infoChanged()
    }

    /// INFO arrived, or the plugged-in set changed.
    func infoChanged() {
        guard step == .test, let info = sensor.info else { return }
        if mapFor != info.hardwareID {
            buildMap(info)
        } else if info.hasPlugDetect {
            follow(plugged: info.plugged)
        }
    }

    private func buildMap(_ info: GangsaSensor.Info) {
        mapFor = info.hardwareID
        checked = []
        mismatch = nil
        let available = info.availableInputs
        if app.profile.controller?.hardwareId == info.hardwareID {
            // A re-check starts from what was saved, not from scratch.
            inputForKey = app.profile.keys.map { key in
                key.sensorInput.flatMap { available.contains($0) ? $0 : nil }
            }
            if info.hasPlugDetect { follow(plugged: info.plugged) }
        } else {
            // Input order = key order: the k-th available input on key k.
            inputForKey = (0 ..< keyCount).map { $0 < available.count ? available[$0] : nil }
        }
        current = nextKey(after: nil)
    }

    /// A sensor plugged in or pulled out mid-check (plug-detect boards only):
    /// one pulled out leaves its key without a sensor; a new one joins the
    /// first key without one, unchecked.
    private func follow(plugged: Set<Int>) {
        for k in inputForKey.indices {
            if let input = inputForKey[k], !plugged.contains(input) {
                inputForKey[k] = nil
                checked.remove(k)
            }
        }
        let used = Set(inputForKey.compactMap(\.self))
        var fresh = plugged.subtracting(used).sorted()
        for k in inputForKey.indices where inputForKey[k] == nil && !fresh.isEmpty {
            inputForKey[k] = fresh.removeFirst()
        }
        if current.map({ inputForKey[$0] == nil || checked.contains($0) }) ?? true {
            current = nextKey(after: current)
        }
    }

    // MARK: - Checking keys

    private func key(for input: Int) -> Int? {
        inputForKey.firstIndex { $0 == input }
    }

    private func handle(_ hit: GangsaSensor.Hit) {
        guard step == .test, sensor.info?.hardwareID == mapFor else { return }
        litKey = key(for: hit.input)
        litHit = hit.id
        // While the mismatch is up, the player is choosing — a stray stroke
        // must not answer for them.
        guard mismatch == nil, let k = current else { return }

        if inputForKey[k] == hit.input {
            check(k)
        } else if inputForKey[k] == nil, key(for: hit.input) == nil {
            // A key with no sensor yet, and a sensor on no key: that is the
            // answer, there is nothing to swap.
            inputForKey[k] = hit.input
            check(k)
        } else {
            mismatch = Mismatch(key: k, input: hit.input, heardAs: key(for: hit.input))
        }
    }

    /// Key `k` heard right — on to the next unchecked one, in key order.
    private func check(_ k: Int) {
        checked.insert(k)
        mismatch = nil
        current = nextKey(after: k)
    }

    private func nextKey(after k: Int?) -> Int? {
        let start = (k ?? -1) + 1
        let order = Array(start ..< inputForKey.count) + Array(0 ..< min(start, inputForKey.count))
        return order.first { inputForKey[$0] != nil && !checked.contains($0) }
    }

    /// Swap: the input that fired moves onto the key being checked, and that
    /// key's old input moves to where the fired one was. That key goes back to
    /// unchecked, to be confirmed in its turn.
    func remap() {
        guard let m = mismatch else { return }
        let old = inputForKey[m.key]
        inputForKey[m.key] = m.input
        if let other = m.heardAs {
            inputForKey[other] = old
            checked.remove(other)
        }
        check(m.key)
    }

    /// The stroke was meant for another bilah. Nothing changes.
    func tryAgain() {
        mismatch = nil
    }

    /// Tap a tile: check that key (again).
    func select(_ k: Int) {
        mismatch = nil
        checked.remove(k)
        current = k
    }

    /// The key being asked for has no sensor — it stays on camera + mic. The
    /// only way to say so without plug detect, which would have known.
    func markNoSensor() {
        guard let k = current else { return }
        inputForKey[k] = nil
        checked.remove(k)
        mismatch = nil
        current = nextKey(after: k)
    }

    func finish() {
        guard isDone, let info = sensor.info, info.hardwareID == mapFor else { return }
        let link = ControllerLink(
            hardwareId: info.hardwareID,
            name: info.name,
            inputCount: info.inputCount,
            hasPlugDetect: info.hasPlugDetect,
            firmware: info.firmware,
            inputs: info.hasPlugDetect ? info.plugged.sorted() : nil,
            setUpAt: InstrumentProfile.nowISO()
        )
        app.saveControllerSetup(link, inputForKey: inputForKey)
    }

    func close() {
        app.closeControllerSetup()
    }
}
