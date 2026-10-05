//
//  RectMaskView.swift
//  Kotek
//
//  Created by Dimas Nugraha on 05/10/26.
//

import SwiftUI

/// An axis-aligned rectangular bilah mask.
/// Drag the body to move the rectangle; drag any edge handle to adjust its size while
/// keeping edges axis-aligned. The magnifier shows while dragging an edge handle.
struct RectMaskView: View {
    enum Edge: CaseIterable {
        case top, right, bottom, left
    }

    @Binding var rect: NormalizedRect
    let viewSize: CGSize
    let label: String
    let isSelected: Bool
    var onSelect: () -> Void = {}
    /// The edge handle being dragged (overlay-normalised), or nil when not.
    var onResizeFocus: (CGPoint?) -> Void = { _ in }

    @State private var moveStartRect: NormalizedRect?
    @State private var resizeStartRect: NormalizedRect?

    private var frameRect: CGRect {
        rect.rect(in: viewSize)
    }

    var body: some View {
        let w = max(10, frameRect.width)
        let h = max(10, frameRect.height)

        ZStack {
            // Main key rectangle shape
            RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.keyCornerRadius)
                        .strokeBorder(
                            isSelected ? Theme.cream : Theme.terracotta,
                            lineWidth: isSelected
                                ? Theme.keyOutlineWidth + 1
                                : Theme.keyOutlineWidth
                        )
                )
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
                .gesture(moveGesture)

            Text(label)
                .font(.sans(13, weight: .bold))
                .foregroundStyle(Theme.cream)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.terracotta, in: Capsule())
                .allowsHitTesting(false)

            ForEach(Edge.allCases, id: \.self) { edge in
                edgeHandle(edge, w: w, h: h)
            }
        }
        .frame(width: w, height: h)
        .position(x: frameRect.midX, y: frameRect.midY)
        .shadow(color: .black.opacity(0.5), radius: 2)
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if moveStartRect == nil {
                    onSelect()
                    moveStartRect = rect
                }
                guard let start = moveStartRect, viewSize.width > 0,
                    viewSize.height > 0
                else { return }
                let dx = value.translation.width / viewSize.width
                let dy = value.translation.height / viewSize.height
                let newX = max(-0.1, min(1.0, start.x + dx))
                let newY = max(-0.1, min(1.0, start.y + dy))
                rect = NormalizedRect(x: newX, y: newY, w: start.w, h: start.h)
            }
            .onEnded { _ in moveStartRect = nil }
    }

    private func edgeHandle(_ edge: Edge, w: CGFloat, h: CGFloat) -> some View {
        let isHorizontal = (edge == .top || edge == .bottom)
        let handlePos: CGPoint = {
            switch edge {
            case .top: return CGPoint(x: w / 2, y: 0)
            case .right: return CGPoint(x: w, y: h / 2)
            case .bottom: return CGPoint(x: w / 2, y: h)
            case .left: return CGPoint(x: 0, y: h / 2)
            }
        }()

        return Capsule()
            .fill(Theme.terracotta)
            .overlay(
                Capsule().strokeBorder(Theme.cream.opacity(0.8), lineWidth: 1.5)
            )
            .frame(width: isHorizontal ? 24 : 8, height: isHorizontal ? 8 : 24)
            .frame(width: 44, height: 44)  // Generous touch target
            .contentShape(Rectangle())
            .position(handlePos)
            .highPriorityGesture(edgeGesture(edge))
    }

    private func edgeGesture(_ edge: Edge) -> some Gesture {
        let minSize = 0.02
        return DragGesture()
            .onChanged { value in
                if resizeStartRect == nil {
                    onSelect()
                    resizeStartRect = rect
                }
                guard let s = resizeStartRect, viewSize.width > 0,
                    viewSize.height > 0
                else { return }
                let dx = value.translation.width / viewSize.width
                let dy = value.translation.height / viewSize.height

                var focusPoint = CGPoint.zero

                switch edge {
                case .top:
                    let newY = min(s.y + s.h - minSize, max(0, s.y + dy))
                    let newH = (s.y + s.h) - newY
                    rect = NormalizedRect(x: s.x, y: newY, w: s.w, h: newH)
                    focusPoint = CGPoint(x: s.x + s.w / 2, y: newY)
                case .right:
                    let newW = max(minSize, min(1.0 - s.x, s.w + dx))
                    rect = NormalizedRect(x: s.x, y: s.y, w: newW, h: s.h)
                    focusPoint = CGPoint(x: s.x + newW, y: s.y + s.h / 2)
                case .bottom:
                    let newH = max(minSize, min(1.0 - s.y, s.h + dy))
                    rect = NormalizedRect(x: s.x, y: s.y, w: s.w, h: newH)
                    focusPoint = CGPoint(x: s.x + s.w / 2, y: s.y + newH)
                case .left:
                    let newX = min(s.x + s.w - minSize, max(0, s.x + dx))
                    let newW = (s.x + s.w) - newX
                    rect = NormalizedRect(x: newX, y: s.y, w: newW, h: s.h)
                    focusPoint = CGPoint(x: newX, y: s.y + s.h / 2)
                }
                onResizeFocus(focusPoint)
            }
            .onEnded { _ in
                resizeStartRect = nil
                onResizeFocus(nil)
            }
    }
}
