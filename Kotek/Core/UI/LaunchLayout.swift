//
//  LaunchLayout.swift
//  Kotek
//
//  The redesign's one unit of scale.
//

import SwiftUI

/// The redesign's one scale — the launch screens' first, now the background's
/// too (`PatternBackground`). The designs are drawn at 1x on an
/// 874 x 402 landscape phone, and every piece — mascot, gate, gangsa,
/// wordmark — is bottom- or centre-anchored, so scaling by HEIGHT keeps them
/// in the same relation on a 375-tall SE and a 440-tall Pro Max. On iPad,
/// `PadScale` lays the app out at the phone's 874 wide, which leaves it taller
/// for its width (574 on an iPad mini), so this is about 1.4 there.
enum LaunchLayout {
    static let referenceHeight: CGFloat = 402

    static func unit(in size: CGSize) -> CGFloat {
        size.height / referenceHeight
    }
}
