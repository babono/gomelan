//
//  BilahBarsView.swift
//  Kotek
//
//  Created by Dimas Nugraha on 06/10/26.
//

import SwiftUI

/// The graduated bar preview — tallest/lowest on the left, echoing the gangsa
/// layout so the number has a shape, not just a digit.
struct BilahBarsView: View {
    let count: Int
    /// The tallest (lowest) bar.
    var height: CGFloat = 72

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(0 ..< count, id: \.self) { i in
                let t = count > 1 ? Double(i) / Double(count - 1) : 0
                // Garis, as the design system draws them; gold is for a reward.
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.hairline)
                    .frame(width: 18, height: height * (1.0 - 0.3 * t))
            }
        }
        .animation(.snappy(duration: 0.2), value: count)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
