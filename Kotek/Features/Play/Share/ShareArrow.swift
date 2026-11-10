//
//  ShareArrow.swift
//  Kotek
//
//  The arrow from the shared figure to the gangsa it will go on. Drawn, not
//  `arrow.right`: the symbol is as wide as it is tall, and at a size that read
//  across the gap it was a heavy blob. Laid out 40 x 20, in the gap the mockup
//  left between the two cards; 60 was too long, the symbol too short.
//

import SwiftUI

struct ShareArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let head = rect.height * 0.5
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.midY))
        path.move(to: CGPoint(x: rect.maxX - 1 - head, y: rect.midY - head * 0.75))
        path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 1 - head, y: rect.midY + head * 0.75))
        return path
    }
}
