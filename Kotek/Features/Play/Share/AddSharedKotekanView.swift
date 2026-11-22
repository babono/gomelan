//
//  AddSharedKotekanView.swift
//  Kotek
//
//  What a shared kotekan's link opens, over any screen from `RootView`: the
//  figure on the left, drawn as the picker draws one, and the player's gangsa
//  on the right as Choose your gangsa shows them, then Add. A guest is asked
//  to link an Apple ID first — sharing is between accounts.
//
//  The same screen copies one of the player's own figures onto another of
//  their gangsa, from the picker's card menu — the only differences are the
//  words and that a copy needs no sign-in.
//
//  It was a dialog laid out like `ConfirmDialog`, choosing the gangsa from a
//  menu of names. A full screen on the paper ground, with the cards, reads as
//  the rest of the app does, and a gangsa is known by its picture first.
//

import SwiftUI

struct AddSharedKotekanView: View {
    @Environment(AppState.self) private var app
    @State private var viewModel: AddSharedKotekanViewModel

    init(id: String, app: AppState) {
        _viewModel = State(initialValue: AddSharedKotekanViewModel(source: .shared(id), app: app))
    }

    init(copying k: Kotekan, app: AppState) {
        _viewModel = State(initialValue: AddSharedKotekanViewModel(source: .copy(k), app: app))
    }

    var body: some View {
        if !viewModel.isCopy, app.account == .guest || signInPreview {
            // A preview's Apple button only closes: the account on this phone
            // may well be linked already.
            ShareSignInView(origin: app.screen, linksAccount: !signInPreview, onClose: viewModel.close)
        } else {
            screen
        }
    }

    private var signInPreview: Bool {
        #if DEBUG
            app.sharePreview == .signIn
        #else
            false
        #endif
    }

    private var screen: some View {
        VStack(spacing: 0) {
            Group {
                if viewModel.isCopy {
                    TopBar(title: "Copy to another gangsa", subtitle: "From \(app.profile.name)", onBack: viewModel.close)
                } else {
                    TopBar(
                        title: viewModel.phase == .notFound ? "Kotekan not found" : "Add a shared kotekan",
                        subtitle: viewModel.phase == .notFound ? nil : "Someone sent you a kotekan",
                        onBack: viewModel.close
                    )
                }
            }

            // The shared card, the arrow and the chosen gangsa, centred as one
            // group. The rail starts at the chosen card and runs on to the
            // screen's edge for the next one's peek, which is left out of the
            // centring — counted in, it pushed the group off to the left.
            GeometryReader { geo in
                let cardHeight = min(InstrumentCardView.maxHeight, geo.size.height - 40)
                let group = SharedKotekanCard.width + 18 + 40 + 18 + InstrumentCardView.width
                let leading = max(24, (geo.size.width - group) / 2)
                HStack(alignment: .top, spacing: 18) {
                    if viewModel.phase == .notFound {
                        // The link leads nowhere: an empty slot where the figure
                        // would be, Kipli under it. Centred on its own.
                        VStack(spacing: 14) {
                            ShareNotFoundSlot()
                            KipliGuide(message: viewModel.kipliMessage, mood: viewModel.kipliMood)
                                .frame(maxWidth: 420)
                        }
                        .frame(width: geo.size.width - leading * 2)
                    } else {
                        SharedKotekanCard(kotekan: viewModel.kotekan, height: cardHeight)
                        ShareArrow()
                            .stroke(Theme.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .frame(width: 40, height: 20)
                            .frame(height: cardHeight)
                            .accessibilityHidden(true)
                        if viewModel.gangsa.isEmpty {
                            ShareEmptyGangsaSlot(height: cardHeight, onAdd: viewModel.addGangsa)
                        } else {
                            ShareGangsaRail(
                                gangsa: viewModel.gangsa,
                                chosen: $viewModel.chosenGangsa,
                                cardHeight: cardHeight
                            )
                            .frame(height: cardHeight + 6)
                            // Back over the arrow's gap by the leading fade, so
                            // the chosen card lands where the group centred it,
                            // and on under the trailing safe area to the edge.
                            .padding(.leading, -ShareGangsaRail.fade)
                            .ignoresSafeArea(.container, edges: .trailing)
                        }
                    }
                }
                .padding(.leading, leading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            }
            .padding(.top, 8)

            // One button, so Kipli has room; the top bar's back closes the
            // screen, so "Not now" beside Add said it twice. His bubble is
            // held to about 300pt so a line breaks in two — across the whole
            // footer it ran on in one.
            HStack(alignment: .bottom, spacing: 12) {
                // Not found: he is in the middle, under the empty slot.
                if viewModel.phase != .notFound {
                    KipliGuide(message: viewModel.kipliMessage, mood: viewModel.kipliMood)
                        .frame(maxWidth: 380, alignment: .leading)
                }
                Spacer(minLength: 0)
                footerButton
            }
            .padding(.horizontal, Theme.headerInset)
            .padding(.bottom, Theme.footerBottom)
        }
        .background { PatternBackground().ignoresSafeArea() }
        .task(id: viewModel.id) { await viewModel.load() }
    }

    @ViewBuilder private var footerButton: some View {
        switch viewModel.phase {
        case .notFound, .failed:
            AppButton(title: "Close", prominence: .primary, action: viewModel.close)
        case .loading, .ready:
            // No gangsa: the empty slot holds "Add a gangsa".
            if !viewModel.gangsa.isEmpty {
                // Just "Add": the gold card already says which gangsa.
                Group {
                    if viewModel.isCopy {
                        AppButton(
                            title: viewModel.isAdding ? "Copying…" : "Copy",
                            systemImage: "doc.on.doc",
                            prominence: .primary,
                            action: viewModel.add
                        )
                    } else {
                        AppButton(
                            title: viewModel.isAdding ? "Adding…" : "Add",
                            systemImage: "plus",
                            prominence: .primary,
                            action: viewModel.add
                        )
                    }
                }
                .disabled(!viewModel.canAdd)
            }
        }
    }
}
