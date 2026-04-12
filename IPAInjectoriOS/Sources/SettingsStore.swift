import Foundation

struct SettingsSnapshot {
    let mode: GenerationMode
    let count: Int
    let suffixInput: String
    let outputFolderName: String
    let outputNameTemplate: String
    let installedAppSort: String
    let dylibPresetsData: Data?
    let enableHistory: Bool
    let enableFilters: Bool
    let enableBatchExport: Bool
    let enableSkipAnalysis: Bool
    let enableValidation: Bool
    let enableOutputFolder: Bool
    let enableDylibPresets: Bool
    let enableNameIconOverride: Bool
    let overrideDisplayName: String
    let overrideIconPath: String?
}

final class SettingsStore {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let mode = "mode"
        static let count = "count"
        static let suffixInput = "suffixInput"
        static let outputFolderName = "outputFolderName"
        static let outputNameTemplate = "outputNameTemplate"
        static let installedAppSort = "installedAppSort"
        static let dylibPresetsData = "dylibPresetsData"
        static let enableHistory = "enableHistory"
        static let enableFilters = "enableFilters"
        static let enableBatchExport = "enableBatchExport"
        static let enableSkipAnalysis = "enableSkipAnalysis"
        static let enableValidation = "enableValidation"
        static let enableOutputFolder = "enableOutputFolder"
        static let enableDylibPresets = "enableDylibPresets"
        static let enableNameIconOverride = "enableNameIconOverride"
        static let overrideDisplayName = "overrideDisplayName"
        static let overrideIconPath = "overrideIconPath"
    }

    func load() -> SettingsSnapshot {
        let count = defaults.object(forKey: Key.count) as? Int ?? 10
        let mode = GenerationMode(rawValue: defaults.string(forKey: Key.mode) ?? GenerationMode.count.rawValue) ?? .count
        let suffixInput = defaults.string(forKey: Key.suffixInput) ?? "a1, a2, a3"
        let outputFolderName = defaults.string(forKey: Key.outputFolderName) ?? "GeneratedIPAs"
        let outputNameTemplate = defaults.string(forKey: Key.outputNameTemplate) ?? "{name}"
        let installedAppSort = defaults.string(forKey: Key.installedAppSort) ?? "name"
        let dylibPresetsData = defaults.data(forKey: Key.dylibPresetsData)
        let enableHistory = defaults.object(forKey: Key.enableHistory) as? Bool ?? true
        let enableFilters = defaults.object(forKey: Key.enableFilters) as? Bool ?? true
        let enableBatchExport = defaults.object(forKey: Key.enableBatchExport) as? Bool ?? true
        let enableSkipAnalysis = defaults.object(forKey: Key.enableSkipAnalysis) as? Bool ?? true
        let enableValidation = defaults.object(forKey: Key.enableValidation) as? Bool ?? true
        let enableOutputFolder = defaults.object(forKey: Key.enableOutputFolder) as? Bool ?? true
        let enableDylibPresets = defaults.object(forKey: Key.enableDylibPresets) as? Bool ?? true
        let enableNameIconOverride = defaults.object(forKey: Key.enableNameIconOverride) as? Bool ?? true
        let overrideDisplayName = defaults.string(forKey: Key.overrideDisplayName) ?? ""
        let overrideIconPath = defaults.string(forKey: Key.overrideIconPath)
        return SettingsSnapshot(
            mode: mode,
            count: max(count, 1),
            suffixInput: suffixInput,
            outputFolderName: outputFolderName,
            outputNameTemplate: outputNameTemplate,
            installedAppSort: installedAppSort,
            dylibPresetsData: dylibPresetsData,
            enableHistory: enableHistory,
            enableFilters: enableFilters,
            enableBatchExport: enableBatchExport,
            enableSkipAnalysis: enableSkipAnalysis,
            enableValidation: enableValidation,
            enableOutputFolder: enableOutputFolder,
            enableDylibPresets: enableDylibPresets,
            enableNameIconOverride: enableNameIconOverride,
            overrideDisplayName: overrideDisplayName,
            overrideIconPath: overrideIconPath
        )
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

    func saveOutputFolderName(_ value: String) {
        defaults.set(value, forKey: Key.outputFolderName)
    }

    func saveOutputNameTemplate(_ value: String) {
        defaults.set(value, forKey: Key.outputNameTemplate)
    }

    func saveInstalledAppSort(_ value: String) {
        defaults.set(value, forKey: Key.installedAppSort)
    }

    func saveDylibPresetsData(_ value: Data?) {
        defaults.set(value, forKey: Key.dylibPresetsData)
    }

    func saveFeatureFlag(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func saveOverrideDisplayName(_ value: String) {
        defaults.set(value, forKey: Key.overrideDisplayName)
    }

    func saveOverrideIconPath(_ value: String?) {
        defaults.set(value, forKey: Key.overrideIconPath)
    }
}
