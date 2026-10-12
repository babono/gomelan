//
//  GangsaPhotoPicker.swift
//  Kotek
//
//  A gangsa's photo, tap to pick another — on the setup screen and in
//  Settings. It replaced the pemade / kantilan picker: a picture says which
//  gangsa it is better than a type did, and the type drove nothing.
//
//  From the library only. The system camera screen is portrait-only, and this
//  app is landscape-locked, so presenting it is unreliable at best; a player
//  takes the photo with the Camera app and picks it here.
//

import PhotosUI
import SwiftUI

struct GangsaPhotoPicker: View {
    /// What to show: the photo just picked, or the gangsa's saved one.
    let image: UIImage?
    /// The picked photo, already made small enough to keep and sync.
    let onPick: (Data) -> Void

    var width: CGFloat = 160
    var height: CGFloat = 100

    @State private var item: PhotosPickerItem?
    @State private var loading = false

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipped()
                    Text("Change")
                        .font(.sans(12, weight: .semibold))
                        .foregroundStyle(Theme.ground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.gold, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(8)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: loading ? "hourglass" : "photo.badge.plus")
                            .font(.symbol(22))
                        Text("Add a photo")
                            .font(.sans(13, weight: .medium))
                    }
                    .foregroundStyle(Theme.gold)
                }
            }
            .frame(width: width, height: height)
            .background(Theme.deep, in: RoundedRectangle(cornerRadius: Theme.radius))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(Theme.gold.opacity(image == nil ? 0.4 : 0.2),
                                  style: StrokeStyle(lineWidth: 1, dash: image == nil ? [4, 3] : []))
            )
        }
        .buttonStyle(.kajar)
        .accessibilityLabel(image == nil ? "Add a photo of this gangsa" : "Change the photo of this gangsa")
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            loading = true
            Task {
                defer { loading = false; item = nil }
                guard let data = try? await picked.loadTransferable(type: Data.self) else { return }
                // Off the main actor: decoding and resizing a 12-megapixel
                // photo is a visible stall.
                let prepared = await Task.detached { InstrumentPhotoStore.prepare(data) }.value
                if let prepared { onPick(prepared) }
            }
        }
    }
}
