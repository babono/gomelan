//
//  DetectioinService.swift
//  gomelan
//
//  Created by Dimas Nugraha on 10/08/26.
//

import Vision
import ImageIO

final class DetectionService {
    private var previousFrame: [UInt8]?
    private var previousWidth = 0

    func detectMallet(in pixelBuffer: CVPixelBuffer) -> DetectedMallet? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let buffer = base.assumingMemoryBound(to: UInt8.self)

        var current = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                current[y * width + x] = buffer[y * bytesPerRow + x]
            }
        }

        defer { previousFrame = current; previousWidth = width }
        guard let prev = previousFrame, previousWidth == width else { return nil } // first frame: no motion yet

        // ponytail: peak-diff pixel, not centroid/blob — add if single point proves too jittery
        var maxDiff = 0
        var maxIdx = 0
        for i in 0..<current.count {
            let diff = abs(Int(current[i]) - Int(prev[i]))
            if diff > maxDiff { maxDiff = diff; maxIdx = i }
        }
        guard maxDiff > 25 else { return nil } // ponytail: fixed threshold, calibrate against real lighting

        return DetectedMallet(position: CGPoint(x: maxIdx % width, y: maxIdx / width))
    }
}
