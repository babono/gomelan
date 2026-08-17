//
//  Defaults.swift
//  gomelan
//
//  Tiny UserDefaults wrapper for the handful of settings that must survive a
//  relaunch. Deliberately not a general preferences system: only detection
//  tuning uses it, because only detection tuning is calibrated against a
//  specific model and instrument and is expensive to rediscover.
//
//  `nonisolated` so it can be read from AppState's property initialisers, which
//  run before the main actor is established.
//

import Foundation

nonisolated enum Defaults {
    static func double(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }
    static func bool(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }
    static func int(_ key: String, _ fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }
    static func set(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
