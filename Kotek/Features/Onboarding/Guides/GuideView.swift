//
//  GuideView.swift
//  Kotek
//
//  The explainer panels: what the grade on a card means, what a kotekan is, and
//  who we made this with. Each is reached by ASKING for it — a help button in a
//  top bar, or the Mekar Bhuana mark in the corner of the landing screen.
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
        case .mekarBhuana:
            GuidePanel(
                title: "Mekar Bhuana",
                titleImage: "logo-mekarbhuana",
                onClose: onClose,
                scrolls: false
            ) {
                GuideSlides(slides: MekarBhuanaDeck.slides)
            }
        }
    }
}
