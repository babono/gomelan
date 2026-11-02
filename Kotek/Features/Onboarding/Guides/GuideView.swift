//
//  GuideView.swift
//  Kotek
//
//  The explainer panels: what a gangsa card keeps, what a kotekan is, where
//  the strike controller's sensors go and how to check them. Each is reached
//  by ASKING for it — a help button in a top bar. (The sensor pair also open
//  once by themselves, the first time their step comes up.) Who we made this
//  with — Mekar Bhuana, a slide deck off the landing screen's corner — was
//  taken out in November 2026.
//

import SwiftUI

struct GuideView: View {
    let guide: AppState.Guide
    var onClose: () -> Void

    var body: some View {
        switch guide {
        case .app:
            GuidePanel(title: "Your gangsa", onClose: onClose) {
                AppGuideView()
            }
        case .kotekan:
            GuidePanel(title: "Kotekan", onClose: onClose) {
                KotekanGuideView()
            }
        case .sensor:
            GuidePanel(title: "Fitting the sensors", onClose: onClose, scrolls: false) {
                SensorGuideView()
            }
        case .sensorCheck:
            GuidePanel(title: "Checking the sensors", onClose: onClose, scrolls: false) {
                SensorCheckGuideView()
            }
        }
    }
}
