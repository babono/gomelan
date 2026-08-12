//
//  ResourceLoader.swift
//  gomelan
//
//  Loads the bundled instrument profile and songs. Prefers JSON in the app
//  bundle (Resources/, PRD §13.3); falls back to an embedded copy so the app is
//  never left without its single calibrated profile.
//
//  The embedded profile is a stand-in for the real pre-run calibration of our
//  gangsa. Positions and pitches are placeholders until the calibration flow is
//  run on the physical instrument and its exported JSON dropped in here.
//

import Foundation

enum ResourceLoader {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static func defaultProfile() -> InstrumentProfile {
        if let profile = load(InstrumentProfile.self, resource: "gangsa_default", subdirectory: "profiles") {
            return profile
        }
        // Fallback: decode the embedded placeholder.
        return (try? decoder.decode(InstrumentProfile.self, from: Data(embeddedProfileJSON.utf8)))
            ?? InstrumentProfile(id: "fallback", name: "Gangsa", keyCount: 0, createdAt: "", keys: [])
    }

    static func bundledSongs() -> [Song] {
        // Try the bundle first.
        if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "songs"),
           !urls.isEmpty {
            let songs = urls.compactMap { url -> Song? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Song.self, from: data)
            }
            if !songs.isEmpty { return songs.sorted { $0.title < $1.title } }
        }
        // Fallback: the embedded placeholders (§13.6).
        return [embeddedSongJSON, embeddedFullRunJSON].compactMap {
            try? decoder.decode(Song.self, from: Data($0.utf8))
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, resource: String, subdirectory: String) -> T? {
        let url = Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: resource, withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}

// MARK: - Embedded placeholders

private extension ResourceLoader {
    /// Placeholder profile for the user's 10-key gangsa. Keys run left-to-right
    /// from longest/lowest (index 0) to shortest/highest (index 9), heights
    /// graduated accordingly, with narrow ~1cm gaps between keys (gap ≈ 20% of
    /// key width). Lower five fundamentals use the uneven pelog-like intervals
    /// measured in §6.3 (147/407/126/196 cents); keys 5–9 sit an octave above —
    /// the usual two-octave gangsa layout. Real values come from running the
    /// in-app pitch calibration on the instrument itself.
    static var embeddedProfileJSON: String {
        """
        {
          "id": "gangsa-exhibition-unit",
          "name": "Gangsa — Exhibition Unit",
          "key_count": 10,
          "created_at": "2026-08-02T10:00:00Z",
          "keys": [
            { "index": 0, "rect": { "x": 0.050, "y": 0.330, "w": 0.076, "h": 0.44 }, "fundamental_hz": 293.4, "harmonics": [2.31, 4.08, 5.92], "decay_ms": 1800, "confidence": 0.94, "sample_path": null },
            { "index": 1, "rect": { "x": 0.142, "y": 0.340, "w": 0.076, "h": 0.42 }, "fundamental_hz": 319.5, "harmonics": [2.30, 4.05, 5.90], "decay_ms": 1800, "confidence": 0.93, "sample_path": null },
            { "index": 2, "rect": { "x": 0.233, "y": 0.350, "w": 0.076, "h": 0.40 }, "fundamental_hz": 404.6, "harmonics": [2.29, 4.02, 5.88], "decay_ms": 1750, "confidence": 0.95, "sample_path": null },
            { "index": 3, "rect": { "x": 0.325, "y": 0.360, "w": 0.076, "h": 0.38 }, "fundamental_hz": 435.6, "harmonics": [2.28, 4.00, 5.85], "decay_ms": 1700, "confidence": 0.92, "sample_path": null },
            { "index": 4, "rect": { "x": 0.416, "y": 0.370, "w": 0.076, "h": 0.36 }, "fundamental_hz": 488.4, "harmonics": [2.27, 3.98, 5.82], "decay_ms": 1650, "confidence": 0.91, "sample_path": null },
            { "index": 5, "rect": { "x": 0.508, "y": 0.380, "w": 0.076, "h": 0.34 }, "fundamental_hz": 586.8, "harmonics": [2.26, 3.96, 5.80], "decay_ms": 1550, "confidence": 0.92, "sample_path": null },
            { "index": 6, "rect": { "x": 0.600, "y": 0.390, "w": 0.076, "h": 0.32 }, "fundamental_hz": 639.0, "harmonics": [2.25, 3.94, 5.78], "decay_ms": 1500, "confidence": 0.92, "sample_path": null },
            { "index": 7, "rect": { "x": 0.691, "y": 0.400, "w": 0.076, "h": 0.30 }, "fundamental_hz": 809.2, "harmonics": [2.24, 3.92, 5.75], "decay_ms": 1400, "confidence": 0.93, "sample_path": null },
            { "index": 8, "rect": { "x": 0.783, "y": 0.410, "w": 0.076, "h": 0.28 }, "fundamental_hz": 871.2, "harmonics": [2.23, 3.90, 5.72], "decay_ms": 1350, "confidence": 0.92, "sample_path": null },
            { "index": 9, "rect": { "x": 0.874, "y": 0.420, "w": 0.076, "h": 0.26 }, "fundamental_hz": 976.8, "harmonics": [2.22, 3.88, 5.70], "decay_ms": 1300, "confidence": 0.91, "sample_path": null }
          ]
        }
        """
    }

    /// "Pattern 1 · 1 2" — the first real exercise, transcribed from the
    /// reference video. A steady 4→5 ostinato at 64 BPM over the colotomic
    /// cycle; this is the standard pattern the play session demonstrates and
    /// then hands over for "Your turn".
    static var embeddedSongJSON: String {
        """
        {
          "id": "video-pattern-1-2",
          "title": "Pattern 1 · 1 2",
          "difficulty": "beginner",
          "bpm": 64,
          "required_keys": 6,
          "duration_ms": 16875,
          "notes": [
            { "key_index": 4, "time_ms": 0, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 469, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 703, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 1172, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 1641, "duration_ms": 180 },

            { "key_index": 4, "time_ms": 1875, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 2344, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 2578, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 3047, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 3516, "duration_ms": 180 },

            { "key_index": 4, "time_ms": 3750, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 4219, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 4453, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 4922, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 5391, "duration_ms": 180 },

            { "key_index": 4, "time_ms": 5625, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 6094, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 6328, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 6797, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 7266, "duration_ms": 180 },

            { "key_index": 4, "time_ms": 7500, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 7969, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 8203, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 8672, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 9141, "duration_ms": 180 },

            { "key_index": 4, "time_ms": 9375, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 9844, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 10078, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 10547, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 11016, "duration_ms": 180 },

            { "key_index": 4, "time_ms": 11250, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 11719, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 11953, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 12422, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 12891, "duration_ms": 180 },

            { "key_index": 4, "time_ms": 13125, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 13594, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 13828, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 14297, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 14766, "duration_ms": 180 },

            { "key_index": 4, "time_ms": 15000, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 15469, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 15703, "duration_ms": 180 },
            { "key_index": 4, "time_ms": 16172, "duration_ms": 180 },
            { "key_index": 5, "time_ms": 16641, "duration_ms": 180 }
          ]
        }
        """
    }

    /// A slow up-and-down run across all 10 keys. Doubles as the §6.3
    /// "slow left-to-right run across all keys" detection check, made playable.
    static var embeddedFullRunJSON: String {
        """
        {
          "id": "placeholder-full-run",
          "title": "Full Run — All Keys",
          "difficulty": "beginner",
          "bpm": 50,
          "required_keys": 10,
          "duration_ms": 24000,
          "notes": [
            { "key_index": 0, "time_ms": 0,     "duration_ms": 1000 },
            { "key_index": 1, "time_ms": 1200,  "duration_ms": 1000 },
            { "key_index": 2, "time_ms": 2400,  "duration_ms": 1000 },
            { "key_index": 3, "time_ms": 3600,  "duration_ms": 1000 },
            { "key_index": 4, "time_ms": 4800,  "duration_ms": 1000 },
            { "key_index": 5, "time_ms": 6000,  "duration_ms": 1000 },
            { "key_index": 6, "time_ms": 7200,  "duration_ms": 1000 },
            { "key_index": 7, "time_ms": 8400,  "duration_ms": 1000 },
            { "key_index": 8, "time_ms": 9600,  "duration_ms": 1000 },
            { "key_index": 9, "time_ms": 10800, "duration_ms": 1000 },
            { "key_index": 8, "time_ms": 12000, "duration_ms": 1000 },
            { "key_index": 7, "time_ms": 13200, "duration_ms": 1000 },
            { "key_index": 6, "time_ms": 14400, "duration_ms": 1000 },
            { "key_index": 5, "time_ms": 15600, "duration_ms": 1000 },
            { "key_index": 4, "time_ms": 16800, "duration_ms": 1000 },
            { "key_index": 3, "time_ms": 18000, "duration_ms": 1000 },
            { "key_index": 2, "time_ms": 19200, "duration_ms": 1000 },
            { "key_index": 1, "time_ms": 20400, "duration_ms": 1000 },
            { "key_index": 0, "time_ms": 21600, "duration_ms": 2000 }
          ]
        }
        """
    }
}
