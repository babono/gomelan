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

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(0 ..< count, id: \.self) { i in
                let t = count > 1 ? Double(i) / Double(count - 1) : 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.charcoal.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(Theme.charcoal.opacity(0.3), lineWidth: 1)
                    )
                    .frame(width: 14, height: 72 * (1.0 - 0.55 * t))
            }
        }
        .animation(.snappy(duration: 0.2), value: count)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
