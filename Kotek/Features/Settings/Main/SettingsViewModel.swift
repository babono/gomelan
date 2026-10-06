//
//  SettingsViewModel.swift
//  Kotek
//
//  ViewModel coordinating the scroll-spy rail, draft naming, and instrument actions.
//

import CoreGraphics
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class SettingsViewModel {
    let app: AppState

    var draftName: String = ""
    var showDeleteConfirm = false

    var metrics = SectionMetrics()
    var active: SettingsSection = .instrument
    var tailInset: CGFloat = 22
    var viewport: CGFloat = 0
    var jumpTarget: SettingsSection?
    private var jumpToken = 0

    nonisolated static let scrollSpace = "settingsScroll"
    static func chipID(_ id: SettingsSection) -> String { "chip-" + id.rawValue }
    static let activeThreshold: CGFloat = 40

    init(app: AppState) {
        self.app = app
        self.draftName = app.profile.name
    }

    var activeSection: SettingsSection { jumpTarget ?? active }

    func updateActiveProfileId() {
        draftName = app.profile.name
    }

    func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftName = app.profile.name
            return
        }
        guard trimmed != app.profile.name else { return }
        var updated = app.profile
        updated.name = trimmed
        app.profile = updated
        app.saveInstrument(updated)
    }

    func deleteInstrument() {
        app.deleteInstrument(app.profile.id)
        app.openChooseInstrument()
    }

    func spy() {
        let passed = SettingsSection.allCases.filter {
            (metrics.frames[$0]?.minY ?? .greatestFiniteMagnitude) <= Self.activeThreshold
        }
        let next = passed.last ?? .instrument
        if next != active { active = next }

        if let last = SettingsSection.allCases.last,
           let frame = metrics.frames[last], viewport > 0 {
            let wanted = max(22, viewport - frame.height - 22)
            if abs(wanted - tailInset) > 0.5 { tailInset = wanted }
        }
    }

    func jump(to id: SettingsSection, using scroll: ScrollViewProxy) {
        jumpTarget = id
        jumpToken += 1
        let token = jumpToken
        withAnimation(.snappy(duration: 0.35)) { scroll.scrollTo(id, anchor: .top) }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            if self.jumpToken == token { self.jumpTarget = nil }
        }
    }

    func heading(for id: SettingsSection) -> String {
        id == .instrument ? app.profile.name : id.title
    }

    func chipLabel(for id: SettingsSection) -> String {
        id == .instrument ? app.profile.name : id.chip
    }
}
