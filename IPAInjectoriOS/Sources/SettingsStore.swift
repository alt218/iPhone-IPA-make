import Foundation

struct SettingsSnapshot {
    let mode: GenerationMode
    let count: Int
    let suffixInput: String
}

final class SettingsStore {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let mode = "mode"
        static let count = "count"
        static let suffixInput = "suffixInput"
    }

    func load() -> SettingsSnapshot {
        let count = defaults.object(forKey: Key.count) as? Int ?? 10
        let mode = GenerationMode(rawValue: defaults.string(forKey: Key.mode) ?? GenerationMode.count.rawValue) ?? .count
        let suffixInput = defaults.string(forKey: Key.suffixInput) ?? "a1, a2, a3"
        return SettingsSnapshot(mode: mode, count: max(count, 1), suffixInput: suffixInput)
    }

    func save(mode: GenerationMode) {
        defaults.set(mode.rawValue, forKey: Key.mode)
    }

    func save(count: Int) {
        defaults.set(count, forKey: Key.count)
    }

    func save(suffixInput: String) {
        defaults.set(suffixInput, forKey: Key.suffixInput)
    }
}
