import SwiftUI

/// The system blur behind the waterfall's title: the notes run up to the top
/// of the screen, and the title's text over them needs something to sit on.
/// A plain material strip ended in a hard edge across the lanes, so the mask
/// fades it out along its bottom, and it runs up through the safe area so
/// there is no seam above it. It takes no touches (the screen's tap pauses).
struct TitleBlur: View {
    /// The bar's own height, which the blur fully covers before it fades.
    var barHeight: CGFloat = Theme.headerBand
    var fade: CGFloat = 24

    var body: some View {
        Color.clear
            .frame(height: barHeight + fade)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: barHeight / (barHeight + fade)),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea(edges: [.top, .horizontal])
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
