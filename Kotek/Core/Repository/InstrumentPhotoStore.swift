//
//  InstrumentPhotoStore.swift
//  Kotek
//
//  Gangsa photos on this phone: Documents/instrument-photos/<id>-<version>.jpg.
//  The version (`InstrumentProfile.photoVersion`) is in the name so a phone
//  can tell a stale copy from the current one by looking for the file, and
//  so the Storage object of the same name is never mistaken for an older one.
//

import UIKit

nonisolated enum InstrumentPhotoStore {
    private static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("instrument-photos", isDirectory: true)
    }

    /// Also the Storage object's name — see `InstrumentRemoteRepository`.
    static func fileName(id: String, version: String) -> String {
        "\(id.lowercased())-\(version.lowercased()).jpg"
    }

    private static func url(id: String, version: String) -> URL {
        directory.appendingPathComponent(fileName(id: id, version: version))
    }

    static func has(id: String, version: String) -> Bool {
        FileManager.default.fileExists(atPath: url(id: id, version: version).path)
    }

    /// Decoded images, so a card redrawing does not read and decode the file
    /// again. Keyed by file name, which changes with every new photo.
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    static func image(for profile: InstrumentProfile) -> UIImage? {
        guard let version = profile.photoVersion else { return nil }
        let key = fileName(id: profile.id, version: version) as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(contentsOfFile: url(id: profile.id, version: version).path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func data(id: String, version: String) -> Data? {
        try? Data(contentsOf: url(id: id, version: version))
    }

    /// Writes this version and drops any other this gangsa had.
    static func save(_ jpeg: Data, id: String, version: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpeg.write(to: url(id: id, version: version), options: .atomic)
        removeAll(id: id, except: version)
    }

    static func delete(id: String) {
        removeAll(id: id, except: nil)
    }

    static func reset() {
        try? FileManager.default.removeItem(at: directory)
        cache.removeAllObjects()
    }

    private static func removeAll(id: String, except version: String?) {
        let keep = version.map { fileName(id: id, version: $0) }
        let prefix = id.lowercased() + "-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(prefix) && name != keep {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// A picked photo, made fit to keep: no longer side over 1280 points and
    /// JPEG at 0.8 — a few hundred kilobytes, where a phone's own photo is
    /// several megabytes and would be uploaded and downloaded on every device.
    static func prepare(_ picked: Data) -> Data? {
        guard let image = UIImage(data: picked) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1280 / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
