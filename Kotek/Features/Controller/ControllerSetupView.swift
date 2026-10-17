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
                backTitle: backTitle,
                onBack: back,
                trailingText: vm.app.profile.name
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
            .padding(.bottom, 20)
        }
        .onAppear { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
        .onChange(of: sensor.info) { _, _ in vm.infoChanged() }
    }

    /// nil is the plain back chevron; only Skip is spelled out.
    private var backTitle: String? {
        if vm.step == .summary { return nil }
        return vm.app.controllerSetupIsOffer ? "Skip" : nil
    }

    private func back() {
        if vm.step == .summary || (vm.step == .test && !vm.app.controllerSetupRecheck) {
            vm.backToScan()
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
                SecondaryButton(title: "Open Settings", systemImage: "gear") {
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
                Text(
                    "Switch the controller on, clip a sensor onto each bilah, and plug them in. It talks to this iPhone over Bluetooth — no Wi‑Fi, no pairing in Settings."
                )
                .font(.sans(15))
                .foregroundStyle(Theme.cream.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                Text("You do this once for each gangsa. One controller can be set up on as many gangsa as you like.")
                    .font(.sans(13))
                    .foregroundStyle(Theme.cream.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                problem
            }
            .frame(maxWidth: 360, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Nearby")
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
        .buttonStyle(.kajar)
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
                Spacer()
                HStack {
                    Spacer()
                    PillButton(title: "Test key hits", style: .filled) {
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
                            isMismatched: vm.mismatch?.key == k,
                            litHit: vm.litKey == k ? vm.litHit : nil
                        ) {
                            vm.select(k)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                HStack {
                    Text("\(vm.checked.count) of \(vm.sensorCount) checked · tap a key to check it again")
                        .font(.sans(13))
                        .foregroundStyle(Theme.cream.opacity(0.55))
                    Spacer()
                    PillButton(title: "Finish", systemImage: "checkmark", style: .filled) {
                        vm.finish()
                    }
                    .disabled(!vm.isDone)
                    .opacity(vm.isDone ? 1 : 0.4)
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

    @ViewBuilder
    private var prompt: some View {
        if let m = vm.mismatch {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.heardAs.map { "Key \(m.key + 1) was heard as key \($0 + 1)" }
                        ?? "Key \(m.key + 1) was heard on input \(m.input + 1)")
                        .font(.serif(28))
                        .foregroundStyle(Theme.wrong)
                    Text("Remap if that's where its sensor is. Try again if you hit another bilah.")
                        .font(.sans(14))
                        .foregroundStyle(Theme.cream.opacity(0.65))
                }
                Spacer()
                SecondaryButton(title: "Try again", systemImage: "arrow.counterclockwise") { vm.tryAgain() }
                PillButton(title: "Remap", systemImage: "arrow.left.arrow.right", style: .filled, compact: true) {
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
                    SecondaryButton(title: "No sensor on key \(k + 1)", systemImage: "camera") {
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

/// One bilah in the key check: which input is on it, whether it has been
/// confirmed, and a flash whenever a stroke lands on it.
private struct ControllerKeyTile: View {
    let key: Int
    let input: Int?
    let level: Double
    let isChecked: Bool
    let isCurrent: Bool
    let isMismatched: Bool
    let litHit: UUID?
    let onTap: () -> Void

    @State private var glow = 0.0

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Text("\(key + 1)")
                    .font(.serif(26))
                    .foregroundStyle(Theme.cream)
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                        .fill(fill)
                    // Raw vibration on this key's input — the sensor's own view,
                    // whether or not the stroke matched.
                    RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                        .fill(Theme.gold.opacity(0.35))
                        .scaleEffect(x: 1, y: level, anchor: .bottom)
                    RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                        .fill(Theme.cream.opacity(0.7 * glow))
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.symbol(22, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.bottom, 12)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                        .strokeBorder(border, lineWidth: isCurrent || isMismatched ? 3 : 1)
                )
                .frame(maxHeight: .infinity)
                Text(input.map { "Input \($0 + 1)" } ?? "No sensor")
                    .font(.sans(11, weight: .semibold))
                    .foregroundStyle(Theme.cream.opacity(input == nil ? 0.4 : 0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.kajar)
        .opacity(input == nil && !isCurrent ? 0.5 : 1)
        .accessibilityLabel(accessibilityText)
        .onChange(of: litHit) { _, id in
            guard id != nil else { return }
            glow = 1
            withAnimation(.easeOut(duration: 0.45)) { glow = 0 }
        }
    }

    private var fill: Color {
        if isChecked { return Theme.hit }
        return Theme.bronze.opacity(input == nil ? 0.08 : 0.2)
    }

    private var border: Color {
        if isMismatched { return Theme.wrong }
        if isCurrent { return Theme.cream }
        return Theme.gold.opacity(0.35)
    }

    private var accessibilityText: String {
        var parts = ["Key \(key + 1)"]
        parts.append(input.map { "input \($0 + 1)" } ?? "no sensor, camera and microphone")
        if isChecked { parts.append("checked") }
        if isCurrent { parts.append("hit this key now") }
        return parts.joined(separator: ", ")
    }
}
