//
//  ControllerSetupView.swift
//  Kotek
//
//  Flow D (PRD §4): scan → connect → summary → test & remap → finish. One
//  screen with local steps rather than a route per step: they share one
//  connection and one half-built map, and backing up a step must keep both.
//

import FactoryKit
import SwiftUI

struct ControllerSetupView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ControllerSetupContent(app: app)
    }
}

/// Split from the view above so the view model can be made in `init`, where
/// `app` is already in hand. It used to be an optional made in `onAppear` on
/// an empty `Group` — which has nothing to appear, so the hook never ran and
/// the screen stayed blank, with no Back to leave it by.
private struct ControllerSetupContent: View {
    @State private var vm: ControllerSetupViewModel
    @State private var quietTooLong = false
    @State private var pinMode: ControllerPINDialog.Mode?

    init(app: AppState, sensor: GangsaSensor = Container.shared.sensorService()) {
        _vm = State(wrappedValue: ControllerSetupViewModel(app: app, sensor: sensor))
    }

    private var sensor: GangsaSensor {
        vm.sensor
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                title: "Strike controller",
                onBack: back,
                trailingText: vm.app.profile.name,
                trailingTitle: skipTitle,
                onTrailing: vm.close,
                infoAction: { vm.app.openGuide(guide) },
                infoLabel: vm.step == .test ? "How the key check works" : "How to fit the sensors"
            )
            Group {
                switch vm.step {
                case .scanning: scanning
                case .summary: summary
                case .test: test
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.bottom, Theme.footerBottom)
        }
        .onAppear {
            vm.onAppear()
            // Before any scanning matters: the sensors have to be on the
            // bilah first. Once only; the help button brings it back. A
            // re-check opens on the key check, so that is the one it gets.
            vm.app.showGuideIfFirstRun(guide)
        }
        .onChange(of: vm.step) { _, step in
            if step == .test { vm.app.showGuideIfFirstRun(.sensorCheck) }
        }
        .onDisappear { vm.onDisappear() }
        .onChange(of: sensor.info) { _, _ in vm.infoChanged() }
        // "Not now" on a locked controller's PIN hands back to the list.
        .onChange(of: sensor.target) { _, target in
            if target == .browse, vm.step == .summary { vm.step = .scanning }
        }
        .overlay {
            if let pinMode, let info = sensor.info {
                ControllerPINDialog(mode: pinMode, controllerName: info.name, sensor: sensor) {
                    self.pinMode = nil
                }
            }
        }
    }

    /// The help button explains the step you are on.
    private var guide: AppState.Guide {
        vm.step == .test ? .sensorCheck : .sensor
    }

    /// Skip sits in the trailing corner, so Back keeps the leading one.
    private var skipTitle: String? {
        vm.step != .summary && vm.app.controllerSetupIsOffer ? "Skip" : nil
    }

    private func back() {
        if vm.step == .summary || (vm.step == .test && !vm.app.controllerSetupRecheck) {
            vm.backToScan()
        } else if vm.app.controllerSetupIsOffer {
            // The offer's previous step is recording the keys.
            vm.app.openNoteCapture(setup: true)
        } else {
            vm.close()
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var problem: some View {
        if case let .unavailable(why) = sensor.status {
            VStack(alignment: .leading, spacing: 10) {
                Label(why, systemImage: "exclamationmark.triangle")
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.miss)
                AppButton(title: "Open Settings", systemImage: "gear", size: .compact) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    private var connectingLine: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Theme.gold)
            Text(sensor.status == .scanning ? "Looking for the controller…" : "Connecting…")
                .font(.sans(15, weight: .medium))
                .foregroundStyle(Theme.cream.opacity(0.75))
        }
    }

    // MARK: - 1–2 · Start + scanning

    private var scanning: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 16) {
                Text(vm.app.controllerSetupIsOffer ? "Got a strike controller?" : "Connect a controller")
                    .font(.serif(34))
                    .foregroundStyle(Theme.cream)
                // Short on purpose: fitting the sensors is the guide's job (the
                // ? button), so this only has to get the controller listed.
                Text("Turn on Bluetooth and switch the controller on. An active controller shows up on the right.")
                    .font(.sans(15))
                    .foregroundStyle(Theme.cream.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                problem
            }
            .frame(maxWidth: 360, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                // Sentence case, not `SectionLabel`'s tracked capitals.
                Text("Nearby")
                    .font(.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.gold)
                if sensor.found.isEmpty {
                    if quietTooLong {
                        Text(
                            "Nothing yet. Is it switched on? Is another phone connected to it? A controller stops showing up while it is connected to something else."
                        )
                        .font(.sans(14))
                        .foregroundStyle(Theme.cream.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        connectingLine
                    }
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(sensor.found) { found in
                            foundRow(found)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 8)
        .task {
            try? await Task.sleep(for: .seconds(10))
            quietTooLong = true
        }
    }

    private func foundRow(_ found: GangsaSensor.Found) -> some View {
        let others = vm.alsoOn(found)
        return Button {
            vm.pick(found)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.symbol(18))
                    .foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 3) {
                    Text(found.name)
                        .font(.sans(17, weight: .semibold))
                        .foregroundStyle(Theme.cream)
                    if vm.isThisGangsas(found) || !others.isEmpty {
                        Text(vm.isThisGangsas(found)
                            ? "Set up on this gangsa"
                            : "Also on \(others.joined(separator: ", "))")
                            .font(.sans(13))
                            .foregroundStyle(Theme.cream.opacity(0.55))
                    }
                }
                Spacer()
                Image(systemName: signal(found.rssi))
                    .font(.symbol(16))
                    .foregroundStyle(Theme.cream.opacity(0.6))
                    .accessibilityHidden(true)
                Image(systemName: "chevron.right")
                    .font(.symbol(14, weight: .semibold))
                    .foregroundStyle(Theme.cream.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(Theme.deep.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.radius))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.appPlain)
    }

    /// Nearest first is the sort; the bars are for telling two apart. 0 is a
    /// controller already connected, which has no fresh reading.
    private func signal(_ rssi: Int) -> String {
        if rssi == 0 { return "link" }
        if rssi >= -60 { return "cellularbars" }
        return rssi >= -75 ? "chart.bar.fill" : "chart.bar"
    }

    // MARK: - 3–4 · Connect + summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let info = sensor.info, sensor.isReady {
                Text(info.name)
                    .font(.serif(34))
                    .foregroundStyle(Theme.cream)
                HStack(alignment: .top, spacing: 36) {
                    stat("Controller inputs", "\(info.inputCount)")
                    if info.hasPlugDetect {
                        stat("Sensors plugged in", "\(info.plugged.count)", detail: inputsText(info.plugged.sorted()))
                    } else {
                        stat(
                            "Sensors plugged in",
                            "—",
                            detail: "This controller can't tell. You'll mark any key without a sensor."
                        )
                    }
                    stat("Instrument keys", "\(vm.keyCount)", detail: vm.app.profile.name)
                }
                if info.hasPlugDetect, info.plugged.isEmpty {
                    Text("No sensors plugged in yet.")
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.wrong)
                }
                pinRow(info)
                Spacer()
                HStack {
                    Spacer()
                    AppButton(title: "Test key hits", prominence: .primary, size: .large) {
                        vm.startTest()
                    }
                    .disabled(info.hasPlugDetect && info.plugged.isEmpty)
                }
            } else {
                connectingLine
                problem
                Spacer()
            }
        }
        .padding(.top, 8)
    }

    /// Protocol 2 firmware only. Open: whoever sets the first PIN owns it.
    @ViewBuilder
    private func pinRow(_ info: GangsaSensor.Info) -> some View {
        if info.supportsPIN {
            HStack(spacing: 14) {
                Image(systemName: sensor.access == .open ? "lock.open" : "lock.fill")
                    .font(.symbol(16))
                    .foregroundStyle(Theme.gold)
                Text(pinText)
                    .font(.sans(14))
                    .foregroundStyle(Theme.cream.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                switch sensor.access {
                case .open:
                    AppButton(title: "Set a PIN", systemImage: "lock", size: .compact) { pinMode = .protect }
                case .owner:
                    AppButton(title: "Change PIN", systemImage: "key", size: .compact) { pinMode = .change }
                case .locked, .user:
                    EmptyView()
                }
            }
        }
    }

    private var pinText: String {
        switch sensor.access {
        case .open: "Any phone nearby can use this controller."
        case .owner: "Protected with a PIN. You own it, so only you can change it."
        case .locked, .user: "Protected with a PIN. Only its owner can change it."
        }
    }

    private func stat(_ title: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title)
            Text(value)
                .font(.serif(44))
                .foregroundStyle(Theme.cream)
            if let detail {
                Text(detail)
                    .font(.sans(13))
                    .foregroundStyle(Theme.cream.opacity(0.55))
                    .frame(maxWidth: 220, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func inputsText(_ inputs: [Int]) -> String {
        inputs.isEmpty ? "none" : "Inputs " + inputs.map { "\($0 + 1)" }.joined(separator: ", ")
    }

    // MARK: - 5–6 · Test & remap, finish

    private var test: some View {
        VStack(spacing: 18) {
            if sensor.isReady, !vm.inputForKey.isEmpty {
                prompt
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                HStack(spacing: 8) {
                    ForEach(0 ..< vm.inputForKey.count, id: \.self) { k in
                        ControllerKeyTile(
                            key: k,
                            input: vm.inputForKey[k],
                            level: level(for: vm.inputForKey[k]),
                            isChecked: vm.checked.contains(k),
                            isCurrent: vm.current == k,
                            mixUp: mixUp(for: k),
                            litHit: vm.litKey == k ? vm.litHit : nil
                        ) {
                            vm.select(k)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                // Room kept for it whether or not it shows, so the tiles do
                // not jump while you are looking at them.
                swapArc
                    .frame(height: 36)
                    // Tucked up under the captions: the stack's 18 apart
                    // would leave the arrows pointing at nothing.
                    .padding(.top, -14)
                    .animation(.easeOut(duration: 0.25), value: vm.mismatch)
                HStack {
                    Text("\(vm.checked.count) of \(vm.sensorCount) checked · tap a key to check it again")
                        .font(.sans(13))
                        .foregroundStyle(Theme.cream.opacity(0.55))
                    Spacer()
                    AppButton(title: "Finish", systemImage: "checkmark", prominence: .primary, size: .large) {
                        vm.finish()
                    }
                    .disabled(!vm.isDone)
                }
            } else {
                connectingLine
                    .frame(maxWidth: .infinity, alignment: .leading)
                problem
                Spacer()
            }
        }
        .padding(.top, 8)
    }

    private func mixUp(for k: Int) -> ControllerKeyTile.MixUp? {
        guard let m = vm.mismatch else { return nil }
        if m.key == k { return .hit }
        return m.heardAs == k ? .heard : nil
    }

    /// Only for a swap: an input heard on no key just moves onto this one.
    @ViewBuilder
    private var swapArc: some View {
        if let m = vm.mismatch, let other = m.heardAs, let held = vm.inputForKey[m.key] {
            SwapArc(keys: (m.key, other), inputs: (held, m.input), count: vm.inputForKey.count)
                .transition(.opacity)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var prompt: some View {
        if let m = vm.mismatch {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.heardAs.map { "Key \(m.key + 1) was heard on key \($0 + 1)" }
                        ?? "Key \(m.key + 1) was heard on input \(m.input + 1)")
                        .font(.serif(28))
                        .foregroundStyle(Theme.wrong)
                    Text(m.heardAs == nil
                        ? "Remap if that's where its sensor is. Try again if you hit another bilah."
                        : "Their sensors are in each other's inputs — Remap swaps them. "
                        + "Try again if you hit another bilah.")
                        .font(.sans(14))
                        .foregroundStyle(Theme.cream.opacity(0.65))
                }
                Spacer()
                AppButton(title: "Try again", systemImage: "arrow.counterclockwise", size: .compact) { vm.tryAgain() }
                AppButton(title: "Remap", systemImage: "arrow.left.arrow.right", prominence: .primary, size: .compact) {
                    vm.remap()
                }
            }
        } else if let k = vm.current {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hit key \(k + 1)")
                        .font(.serif(34))
                        .foregroundStyle(Theme.cream)
                    Text(vm.inputForKey[k] == nil
                        ? "No sensor on this key yet — hit it and the sensor that answers is put here."
                        : "\(vm.sensorCount) sensors detected. Hit each key in turn.")
                        .font(.sans(14))
                        .foregroundStyle(Theme.cream.opacity(0.65))
                }
                Spacer()
                if vm.inputForKey[k] != nil {
                    AppButton(title: "No sensor on key \(k + 1)", systemImage: "camera", size: .compact) {
                        vm.markNoSensor()
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("All keys check out")
                    .font(.serif(34))
                    .foregroundStyle(Theme.hit)
                Text(vm.sensorCount < vm.keyCount
                    ? "Keys without a sensor use the camera and microphone."
                    : "Every key has its own sensor.")
                    .font(.sans(14))
                    .foregroundStyle(Theme.cream.opacity(0.65))
            }
        }
    }

    private func level(for input: Int?) -> Double {
        guard let input, input < sensor.levels.count else { return 0 }
        return sensor.levels[input]
    }
}
