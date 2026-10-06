//
//  MekarBhuanaDeck.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// What fills a slide's picture half.
enum GuideArt {
    case none
    case photo(String)
    /// A figure drawn from its own data, in the colours the score uses.
    case figure(Kotekan)
}

/// One topic, one picture.
struct GuideSlide: Identifiable {
    let id = UUID()
    var art: GuideArt = .none
    var title: String
    var text: String
    /// Somewhere to go next. Only ever the LAST slide.
    var link: URL? = nil
}

/// A panel that pages instead of scrolling.
struct GuideSlides: View {
    let slides: [GuideSlide]
    @State private var index = 0

    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $index) {
                ForEach(slides.indices, id: \.self) { i in
                    slide(slides[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            PageDots(count: slides.count, index: $index)
        }
    }

    @ViewBuilder
    private func slide(_ slide: GuideSlide) -> some View {
        if case .none = slide.art {
            text(slide)
                .frame(maxWidth: 520, alignment: .topLeading)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
        } else {
            HStack(alignment: .top, spacing: 24) {
                art(slide.art).frame(maxWidth: .infinity, maxHeight: .infinity)

                text(slide)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
            }
        }
    }

    @ViewBuilder
    private func art(_ art: GuideArt) -> some View {
        switch art {
        case .none:
            EmptyView()

        case .photo(let name):
            Color.clear
                .overlay(
                    Image(name).resizable().aspectRatio(contentMode: .fill)
                )
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .strokeBorder(Theme.cream.opacity(0.12), lineWidth: 1)
                )
                .accessibilityHidden(true)

        case .figure(let kotekan):
            VStack {
                Spacer(minLength: 0)
                KotekanMiniScore(kotekan: kotekan).frame(height: 92)
                Spacer(minLength: 0)
            }
            .padding(18)
            .background(
                Theme.ground.opacity(0.5),
                in: RoundedRectangle(cornerRadius: Theme.radius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(Theme.cream.opacity(0.12), lineWidth: 1)
            )
            .accessibilityHidden(true)
        }
    }

    private func text(_ slide: GuideSlide) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(slide.title)
                .font(.serif(24))
                .foregroundStyle(Theme.cream)
                .fixedSize(horizontal: false, vertical: true)

            Text(slide.text)
                .font(.sans(14))
                .foregroundStyle(Theme.cream.opacity(0.78))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let link = slide.link { linkButton(link) }
        }
    }

    private func linkButton(_ link: URL) -> some View {
        Link(destination: link) {
            HStack(spacing: 5) {
                Text(
                    (link.host() ?? "Open").replacingOccurrences(
                        of: "www.",
                        with: ""
                    )
                )
                .font(.sans(13))
                .italic()
                .underline()
                Image(systemName: "arrow.up.right")
                    .font(.symbol(11, weight: .semibold))
            }
            .foregroundStyle(Theme.buttonFill)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Visit \(link.host() ?? "the website")")
    }
}

// MARK: - Mekar Bhuana Deck Data

enum MekarBhuanaDeck {
    static let slides: [GuideSlide] = [
        GuideSlide(
            art: .photo("photo-mekarbhuana"),
            title: "To blossom around the world",
            text:
                "That is what Mekar Bhuana means, and it is the hope behind it: that Bali's oldest music and dance become known again, at home and beyond it."
        ),
        GuideSlide(
            art: .photo("photo-founder"),
            title: "The centre",
            text:
                "A family-run centre in Denpasar that documents, reconstructs and repatriates endangered classical gamelan. Vaughan Hatch founded it in 2000 around an antique Semara Pagulingan he restored, having found how few classical ensembles were ever recorded. Putu Evie Suyadnyani, a Legong dancer, brought the dance in 2004."
        ),
        GuideSlide(
            art: .photo("photo-collection"),
            title: "Collection",
            text:
                "Twenty-seven gamelan sets: twenty-two in Bali, five at Mekar Bhuana Aotearoa in New Zealand. Among them a Semara Patangian in the old key order that exists nowhere else outside Bali, and Semara Kirang, an Angklung set from Lombok restored in 2019."
        ),
        GuideSlide(
            art: .photo("photo-centre"),
            title: "Visiting",
            text:
                "Lessons, workshops and cultural immersion, led by English-speaking experts including a native-speaking ethnomusicologist. The centre is a family home, so there are no walk-ins — book by email two weeks ahead.",
            link: URL(string: "https://balimusicanddance.com")
        ),
    ]
}
