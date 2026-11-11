//
//  KotekanLink.swift
//  Kotek
//
//  The link a shared kotekan travels as. Share sends the web one,
//  https://www.kotek.app/share/<id>: a universal link (the site's
//  apple-app-site-association claims /share/*), so with the app installed it
//  opens here, and without it the page offers the App Store. That page's
//  "Open in Kotek" button is the other form, kotek://k/<id>. Both land in
//  `AddSharedKotekanView`.
//

import Foundation

enum KotekanLink {
    /// www, not the bare domain: Vercel redirects kotek.app to it, and iOS
    /// does not follow a redirect when it fetches apple-app-site-association.
    static let webBase = URL(string: "https://www.kotek.app")!
    /// The bare domain too, for a link someone typed or pasted without www.
    private static let webHosts = ["www.kotek.app", "kotek.app"]
    static let scheme = "kotek"

    static func url(for id: String) -> URL {
        webBase.appending(path: "share").appending(path: id)
    }

    /// The kotekan id in `kotek://k/<id>` or `https://[www.]kotek.app/share/<id>`;
    /// nil for any other link.
    static func id(from url: URL) -> String? {
        let parts: [String]
        let prefix: String
        switch url.scheme {
        case scheme:
            // The host is the first part: kotek://k/<id>.
            parts = [url.host() ?? ""] + url.pathComponents.filter { $0 != "/" }
            prefix = "k"
        case "https" where webHosts.contains(url.host() ?? ""):
            parts = url.pathComponents.filter { $0 != "/" }
            prefix = "share"
        default:
            return nil
        }
        guard parts.count == 2, parts[0] == prefix, !parts[1].isEmpty else { return nil }
        return parts[1]
    }

    #if DEBUG
        static func selfCheck() {
            let id = "3f2c9a1e-0b7d-4c55-9e1a-2d6f8b4c7a10"
            assert(url(for: id).absoluteString == "https://www.kotek.app/share/\(id)")
            assert(Self.id(from: URL(string: "https://kotek.app/share/\(id)")!) == id)
            assert(Self.id(from: url(for: id)) == id)
            assert(Self.id(from: URL(string: "kotek://k/\(id)")!) == id)
            assert(Self.id(from: URL(string: "kotek://k/")!) == nil)
            assert(Self.id(from: URL(string: "https://kotek.app/k/\(id)")!) == nil)
            assert(Self.id(from: URL(string: "https://example.com/share/\(id)")!) == nil)
            assert(Self.id(from: URL(string: "kotek://x/\(id)")!) == nil)
        }
    #endif
}
