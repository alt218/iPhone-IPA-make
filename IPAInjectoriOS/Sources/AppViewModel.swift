import Foundation
import SwiftUI
import ZIPFoundation

enum GenerationMode: String, CaseIterable, Identifiable {
    case count
    case suffixes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .count:
            return "件数"
        case .suffixes:
            return "サフィックス"
        }
    }
}

enum AppSortOrder: String, CaseIterable, Identifiable {
    case name
    case recent
    case size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "名前順"
        case .recent: return "最近起動"
        case .size: return "容量"
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    struct HistoryItem: Identifiable {
        let id = UUID()
        let date: Date
        let message: String
        let detail: String?
        let relatedURLs: [URL]
        let isError: Bool
    }

    struct InstalledApp: Identifiable {
        let id: String
        let name: String
        let bundleId: String
        let appURL: URL
        let lastModified: Date?
        let sizeBytes: Int64?
    }

    struct DylibPreset: Identifiable, Codable, Hashable {
        let id: UUID
        var name: String
        var paths: [String]

        init(id: UUID = UUID(), name: String, paths: [String]) {
            self.id = id
            self.name = name
            self.paths = paths
        }
    }

    @Published var ipaURL: URL?
    @Published var dylibURLs: [URL] = []
    @Published var availableIPAs: [URL] = []
    @Published var installedApps: [InstalledApp] = []
    @Published var installedAppsQuery: String = ""
    @Published var installedAppSort: AppSortOrder = .name {
        didSet { settings.saveInstalledAppSort(installedAppSort.rawValue) }
    }
    @Published var enableHistory = true {
        didSet { settings.saveFeatureFlag(enableHistory, forKey: "enableHistory") }
    }
    @Published var enableFilters = true {
        didSet { settings.saveFeatureFlag(enableFilters, forKey: "enableFilters") }
    }
    @Published var enableBatchExport = true {
        didSet { settings.saveFeatureFlag(enableBatchExport, forKey: "enableBatchExport") }
    }
    @Published var enableSkipAnalysis = true {
        didSet { settings.saveFeatureFlag(enableSkipAnalysis, forKey: "enableSkipAnalysis") }
    }
    @Published var enableValidation = true {
        didSet { settings.saveFeatureFlag(enableValidation, forKey: "enableValidation") }
    }
    @Published var enableOutputFolder = true {
        didSet { settings.saveFeatureFlag(enableOutputFolder, forKey: "enableOutputFolder") }
    }
    @Published var enableDylibPresets = true {
        didSet { settings.saveFeatureFlag(enableDylibPresets, forKey: "enableDylibPresets") }
    }
    @Published var enableNameIconOverride = true {
        didSet { settings.saveFeatureFlag(enableNameIconOverride, forKey: "enableNameIconOverride") }
    }
    @Published var outputFolderName: String = "GeneratedIPAs" {
        didSet {
            settings.saveOutputFolderName(outputFolderName)
            outputDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(outputFolderName, isDirectory: true)
        }
    }
    @Published var outputNameTemplate: String = "{name}" {
        didSet { settings.saveOutputNameTemplate(outputNameTemplate) }
    }
    @Published var overrideDisplayName: String = "" {
        didSet { settings.saveOverrideDisplayName(overrideDisplayName) }
    }
    @Published var overrideIconURL: URL? {
        didSet { settings.saveOverrideIconPath(overrideIconURL?.path) }
    }
    @Published var mode: GenerationMode = .count {
        didSet { settings.save(mode: mode) }
    }
    @Published var countValue: Int = 10 {
        didSet { settings.save(count: countValue) }
    }
    @Published var suffixInput: String = "a1, a2, a3" {
        didSet { settings.save(suffixInput: suffixInput) }
    }
    @Published var isImportingIPA = false
    @Published var isSelectingIPAList = false
    @Published var isSelectingInstalledApps = false
    @Published var isImportingDylibs = false
    @Published var isImportingIcon = false
    @Published var isProcessing = false
    @Published var isExportingIPA = false
    @Published var exportStatus = ""
    @Published var isConfirmingDelete = false
    @Published var pendingDeleteIPA: URL?
    @Published var historyItems: [HistoryItem] = []
    @Published var errorMessage: String?
    @Published var logText = ""
    @Published var generatedFiles: [URL] = []
    @Published var selectedInstalledAppIDs: Set<String> = []
    @Published var isSelectingMultipleApps = false
    @Published var dylibPresets: [DylibPreset] = []
    @Published var selectedDylibPresetID: UUID?
    @Published var newPresetName: String = ""
    @Published var menuSearch: String = ""

    var outputDirectoryURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GeneratedIPAs", isDirectory: true)

    private let settings = SettingsStore()

    init() {
        let snapshot = settings.load()
        mode = snapshot.mode
        countValue = snapshot.count
        suffixInput = snapshot.suffixInput
        outputNameTemplate = snapshot.outputNameTemplate
        installedAppSort = AppSortOrder(rawValue: snapshot.installedAppSort) ?? .name
        enableHistory = snapshot.enableHistory
        enableFilters = snapshot.enableFilters
        enableBatchExport = snapshot.enableBatchExport
        enableSkipAnalysis = snapshot.enableSkipAnalysis
        enableValidation = snapshot.enableValidation
        enableOutputFolder = snapshot.enableOutputFolder
        enableDylibPresets = snapshot.enableDylibPresets
        enableNameIconOverride = snapshot.enableNameIconOverride
        outputFolderName = snapshot.outputFolderName
        overrideDisplayName = snapshot.overrideDisplayName
        if let path = snapshot.overrideIconPath {
            overrideIconURL = URL(fileURLWithPath: path)
        }
        if let data = snapshot.dylibPresetsData,
           let presets = try? JSONDecoder().decode([DylibPreset].self, from: data) {
            dylibPresets = presets
        }
        outputDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(outputFolderName, isDirectory: true)
    }

    var ipaLabel: String {
        ipaURL?.lastPathComponent ?? "IPAが選択されていません"
    }

    func refreshAvailableIPAs() {
        let ipaFiles = ipaStorageDirectories().flatMap { collectIPAFiles(in: $0) }
        availableIPAs = ipaFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func selectIPA(_ url: URL) {
        ipaURL = url
        pendingDeleteIPA = nil
        isConfirmingDelete = false
        isSelectingIPAList = false
    }

    func handleIPAImport(_ result: Result<[URL], Error>) {
        do {
            guard let sourceURL = try result.get().first else { return }
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            let destDir = ipaStorageDirectory()
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
            let destURL = uniqueDestinationURL(in: destDir, name: sourceURL.lastPathComponent)
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            refreshAvailableIPAs()
            selectIPA(destURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startIPAImportFromSheet() {
        isSelectingIPAList = false
        isSelectingInstalledApps = false
        pendingDeleteIPA = nil
        isConfirmingDelete = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isImportingIPA = true
        }
    }

    func startIPAImport() {
        isImportingIPA = false
        DispatchQueue.main.async {
            self.isImportingIPA = true
        }
    }

    func startIconImport() {
        isImportingIcon = false
        DispatchQueue.main.async {
            self.isImportingIcon = true
        }
    }

    func refreshInstalledApps() {
        installedApps = []
        installedAppsQuery = ""

        let workspaceApps = fetchAppsViaLSApplicationWorkspace()
        if !workspaceApps.isEmpty {
            installedApps = workspaceApps
            appendLog("LSApplicationWorkspace: \(installedApps.count) 件")
            return
        }

        let rootlessContainers = [
            URL(fileURLWithPath: "/var/containers/Bundle/Application", isDirectory: true),
            URL(fileURLWithPath: "/private/var/containers/Bundle/Application", isDirectory: true)
        ]
        var rootlessContainerApps: [InstalledApp] = []
        for root in rootlessContainers {
            rootlessContainerApps.append(contentsOf: scanApps(in: root))
            rootlessContainerApps.append(contentsOf: scanAppsOneLevel(in: root))
        }

        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/var/containers/Bundle/Application", isDirectory: true),
            URL(fileURLWithPath: "/private/var/containers/Bundle/Application", isDirectory: true),
            URL(fileURLWithPath: "/var/mobile/Containers/Bundle/Application", isDirectory: true),
            URL(fileURLWithPath: "/private/var/mobile/Containers/Bundle/Application", isDirectory: true),
            URL(fileURLWithPath: "/var/jb/Applications", isDirectory: true),
            URL(fileURLWithPath: "/var/jb/containers/Bundle/Application", isDirectory: true),
            URL(fileURLWithPath: "/var/jb/Containers/Bundle/Application", isDirectory: true),
            URL(fileURLWithPath: "/private/var/jb/Applications", isDirectory: true),
            URL(fileURLWithPath: "/private/var/jb/containers/Bundle/Application", isDirectory: true),
            URL(fileURLWithPath: "/private/var/jb/Containers/Bundle/Application", isDirectory: true),
            URL(fileURLWithPath: "/var/jb/var/containers/Bundle/Application", isDirectory: true),
            URL(fileURLWithPath: "/private/var/jb/var/containers/Bundle/Application", isDirectory: true),
            URL(fileURLWithPath: "/var/jb/var/mobile/Containers/Bundle/Application", isDirectory: true),
            URL(fileURLWithPath: "/private/var/jb/var/mobile/Containers/Bundle/Application", isDirectory: true)
        ]

        var apps: [InstalledApp] = []
        for root in roots {
            apps.append(contentsOf: scanApps(in: root))
            apps.append(contentsOf: scanAppsOneLevel(in: root))
        }

        let storeApps = apps.filter { isAppStoreApp($0.appURL) }
        let base: [InstalledApp]
        if isRootlessEnvironment() {
            base = apps
        } else {
            base = storeApps.isEmpty ? apps : storeApps
        }
        let mergeSource = isRootlessEnvironment() ? (base + rootlessContainerApps) : base
        let unique = Dictionary(grouping: mergeSource, by: { $0.bundleId })
            .compactMap { $0.value.first }
            .sorted { $0.name < $1.name }

        installedApps = unique
        if isRootlessEnvironment() {
            let containerCount = rootlessContainerApps.count
            appendLog("rootless環境: 全アプリを表示中: \(installedApps.count) 件（/var/containers: \(containerCount) 件）")
        } else if storeApps.isEmpty {
            appendLog("App Store判定ができないため、全アプリを表示中: \(installedApps.count) 件")
        } else {
            appendLog("App Storeアプリ: \(installedApps.count) 件")
        }
    }

    func appendInstalledAppsDiagnostics() {
        let roots = [
            "/Applications",
            "/var/containers/Bundle/Application",
            "/private/var/containers/Bundle/Application",
            "/var/mobile/Containers/Bundle/Application",
            "/private/var/mobile/Containers/Bundle/Application",
            "/var/jb/Applications",
            "/var/jb/containers/Bundle/Application",
            "/var/jb/Containers/Bundle/Application",
            "/private/var/jb/Applications",
            "/private/var/jb/containers/Bundle/Application",
            "/private/var/jb/Containers/Bundle/Application",
            "/var/jb/var/containers/Bundle/Application",
            "/private/var/jb/var/containers/Bundle/Application",
            "/var/jb/var/mobile/Containers/Bundle/Application",
            "/private/var/jb/var/mobile/Containers/Bundle/Application"
        ]

        for path in roots {
            let exists = FileManager.default.fileExists(atPath: path)
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: path) {
                appendLog("スキャン: \(path) exists=\(exists) count=\(contents.count)")
            } else {
                appendLog("スキャン: \(path) exists=\(exists) count=0 (読み取り不可)")
            }
        }
        if isLikelyRootlessOnly(apps: installedApps) {
            appendLog("診断: rootless の可能性が高いです")
        }
    }

    func exportInstalledAppToIPA(_ app: InstalledApp) {
        do {
            isExportingIPA = true
            exportStatus = "吸い出し開始: \(app.name)"
            appendLog(exportStatus)
            let destDir = ipaStorageDirectory()
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
            let fileName = outputFileName(for: app)
            let destURL = uniqueDestinationURL(in: destDir, name: fileName)

            let tempRoot = destDir.appendingPathComponent("ExportWork-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
            defer { try? FileManager.default.removeItem(at: tempRoot) }

            let payloadURL = tempRoot.appendingPathComponent("Payload", isDirectory: true)
            try FileManager.default.createDirectory(at: payloadURL, withIntermediateDirectories: true, attributes: nil)
            let candidatePaths = appURLCandidates(from: app.appURL.path)
            let destAppURL = payloadURL.appendingPathComponent(app.appURL.lastPathComponent)
            exportStatus = "アプリをコピー中..."
            appendLog(exportStatus)
            appendLog("コピー先: \(destAppURL.path)")
            let fallbackExecutable = URL(fileURLWithPath: candidatePaths.first ?? app.appURL.path)
                .deletingPathExtension()
                .lastPathComponent
            let workspaceExecutable = resolveExecutableNameFromWorkspace(bundleId: app.bundleId)
            if let workspaceExecutable {
                appendLog("実行ファイル(LS): \(workspaceExecutable)")
            }
            let scannedExecutable = resolveExecutableNameByScanning(candidates: candidatePaths)
            if let scannedExecutable {
                appendLog("実行ファイル(スキャン): \(scannedExecutable)")
            }
            let expectedExecutable = workspaceExecutable
                ?? resolveExecutableName(fromCandidates: candidatePaths)
                ?? scannedExecutable
                ?? fallbackExecutable
            if let hidePath = candidatePaths.first(where: { $0.contains("/var/containers/Bundle/Application") || $0.contains("/private/var/containers/Bundle/Application") }) {
                appendLog("hide環境の可能性: \(hidePath)")
            }
            let copyResult = try copyAppBundleWithFallback(
                fromCandidates: candidatePaths,
                to: destAppURL,
                expectedExecutable: expectedExecutable
            )
            let skipped = copyResult.skippedFiles
            let detectedExecutable = copyResult.detectedExecutable ?? expectedExecutable
            if !ensureInfoPlist(for: destAppURL, fromCandidates: candidatePaths) {
                if writeFallbackInfoPlist(for: destAppURL, app: app, executableName: detectedExecutable) {
                    appendLog("Info.plist を暫定生成しました")
                } else {
                    appendLog("警告: Info.plist を取得できませんでした")
                }
            }
            if !ensureExecutable(for: destAppURL, fromCandidates: candidatePaths, expectedExecutable: detectedExecutable) {
                appendLog("警告: 実行ファイルをコピーできませんでした: \(detectedExecutable)")
            }
            var skippedLogURL: URL?
            if !skipped.isEmpty {
                let logURL = try writeSkippedFilesLog(for: app.name, skipped: skipped, in: destDir)
                skippedLogURL = logURL
                appendLog("スキップ一覧を書き出しました: \(logURL.lastPathComponent)")
                if enableSkipAnalysis {
                    let warnings = analyzeSkippedFiles(skipped, in: destAppURL)
                    if !warnings.isEmpty {
                        appendLog("スキップ解析: 警告 \(warnings.count) 件")
                        for warning in warnings {
                            appendLog("警告: \(warning)")
                        }
                    } else {
                        appendLog("スキップ解析: 重大な警告はありません")
                    }
                }
            }

            exportStatus = "IPAを作成中..."
            appendLog(exportStatus)
            try FileManager.default.zipItem(
                at: payloadURL,
                to: destURL,
                shouldKeepParent: true,
                compressionMethod: .deflate
            )

            refreshAvailableIPAs()
            selectIPA(destURL)
            if enableValidation {
                let warnings = validateIPA(at: destURL, expectedExecutable: detectedExecutable)
                if warnings.isEmpty {
                    appendLog("IPA検証: OK")
                } else {
                    appendLog("IPA検証: 警告 \(warnings.count) 件")
                    for warning in warnings {
                        appendLog("警告: \(warning)")
                    }
                }
            }

            let logURL = writeOperationLog(for: app.name, in: destDir)
            recordHistory(
                message: "吸い出し完了: \(app.name)",
                detail: app.bundleId,
                relatedURLs: [destURL, logURL, skippedLogURL].compactMap { $0 },
                isError: false
            )
            exportStatus = "吸い出し完了: \(destURL.lastPathComponent)"
            appendLog(exportStatus)
            isExportingIPA = false
        } catch {
            errorMessage = error.localizedDescription
            exportStatus = "吸い出し失敗: \(error.localizedDescription)"
            appendLog(exportStatus)
            let nsError = error as NSError
            appendLog("エラー詳細: domain=\(nsError.domain) code=\(nsError.code)")
            let logURL = writeOperationLog(for: app.name, in: ipaStorageDirectory())
            recordHistory(
                message: "吸い出し失敗: \(app.name)",
                detail: error.localizedDescription,
                relatedURLs: [logURL].compactMap { $0 },
                isError: true
            )
            isExportingIPA = false
        }
    }

    func exportSelectedAppsToIPA() {
        let targets = installedApps.filter { selectedInstalledAppIDs.contains($0.id) }
        guard !targets.isEmpty else {
            appendLog("一括吸い出し: 対象がありません")
            return
        }
        appendLog("一括吸い出し開始: \(targets.count) 件")
        Task {
            for app in targets {
                await MainActor.run {
                    self.exportInstalledAppToIPA(app)
                }
            }
            await MainActor.run {
                self.appendLog("一括吸い出し完了")
            }
        }
    }

    func requestDeleteIPA(_ url: URL) {
        pendingDeleteIPA = url
        isConfirmingDelete = true
    }

    func confirmDeleteIPA() {
        guard let url = pendingDeleteIPA else { return }
        pendingDeleteIPA = nil
        isConfirmingDelete = false
        deleteIPA(url)
    }

    func cancelDeleteIPA() {
        pendingDeleteIPA = nil
        isConfirmingDelete = false
    }

    func deleteIPA(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            if ipaURL == url {
                ipaURL = nil
            }
            refreshAvailableIPAs()
            appendLog("削除: \(url.lastPathComponent)")
        } catch {
            errorMessage = error.localizedDescription
            appendLog("削除失敗: \(error.localizedDescription)")
        }
    }

    func handleDylibSelection(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            if urls.isEmpty {
                dylibURLs = []
                appendLog("dylib選択: 0件")
                return
            }
            let destDir = dylibStorageDirectory()
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
            var copied: [URL] = []
            for url in urls {
                guard url.pathExtension.lowercased() == "dylib" else { continue }
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let destURL = uniqueDestinationURL(in: destDir, name: url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: destURL)
                copied.append(destURL)
            }
            dylibURLs = copied.sorted { $0.lastPathComponent < $1.lastPathComponent }
            appendLog("dylib追加: \(dylibURLs.count) 件")
        } catch {
            errorMessage = error.localizedDescription
            appendLog("dylib追加失敗: \(error.localizedDescription)")
        }
    }

    func handleIconSelection(_ result: Result<[URL], Error>) {
        do {
            guard let sourceURL = try result.get().first else { return }
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            let destDir = iconStorageDirectory()
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
            let destURL = uniqueDestinationURL(in: destDir, name: sourceURL.lastPathComponent)
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            overrideIconURL = destURL
            appendLog("アイコン上書き: \(destURL.lastPathComponent)")
        } catch {
            errorMessage = error.localizedDescription
            appendLog("アイコン上書き失敗: \(error.localizedDescription)")
        }
    }

    func filteredInstalledApps() -> [InstalledApp] {
        let query = installedAppsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [InstalledApp]
        if query.isEmpty {
            filtered = installedApps
        } else {
            filtered = installedApps.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleId.localizedCaseInsensitiveContains(query)
            }
        }
        return sortApps(filtered)
    }

    private func sortApps(_ apps: [InstalledApp]) -> [InstalledApp] {
        switch installedAppSort {
        case .name:
            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recent:
            return apps.sorted {
                let lhs = $0.lastModified ?? .distantPast
                let rhs = $1.lastModified ?? .distantPast
                return lhs > rhs
            }
        case .size:
            return apps.sorted {
                let lhs = $0.sizeBytes ?? directorySize(for: $0.appURL)
                let rhs = $1.sizeBytes ?? directorySize(for: $1.appURL)
                return lhs > rhs
            }
        }
    }

    func run() {
        guard !isProcessing else { return }
        errorMessage = nil
        generatedFiles = []
        logText = ""

        guard let ipaURL else {
            errorMessage = "IPAを選択してください。"
            return
        }

        let suffixes: [String]
        switch mode {
        case .count:
            guard countValue > 0 else {
                errorMessage = "件数は1以上にしてください。"
                return
            }
            suffixes = (1...countValue).map { "a\($0)" }
        case .suffixes:
            suffixes = suffixInput
                .components(separatedBy: CharacterSet(charactersIn: ", \n\t"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !suffixes.isEmpty else {
                errorMessage = "suffixを1つ以上入力してください。"
                return
            }
        }

        isProcessing = true
        let scopedURLs = [ipaURL] + dylibURLs
        let accessed = scopedURLs.filter { $0.startAccessingSecurityScopedResource() }

        Task {
            defer {
                accessed.forEach { $0.stopAccessingSecurityScopedResource() }
            }

            do {
                let processor = IPAProcessor()
                let result = try await processor.generateVariants(
                    ipaURL: ipaURL,
                    dylibURLs: dylibURLs,
                    suffixes: suffixes,
                    outputDirectoryURL: outputDirectoryURL
                ) { [weak self] line in
                    await MainActor.run {
                        self?.appendLog(line)
                    }
                }

                await MainActor.run {
                    self.generatedFiles = result.outputURLs
                    self.appendLog("完了: \(result.outputURLs.count) 個のIPAを生成しました")
                    let logURL = self.writeOperationLog(for: "生成", in: self.outputDirectoryURL)
                    self.recordHistory(
                        message: "生成完了: \(result.outputURLs.count) 件",
                        detail: self.ipaURL?.lastPathComponent,
                        relatedURLs: (result.outputURLs + [logURL]).compactMap { $0 },
                        isError: false
                    )
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.appendLog("エラー: \(error.localizedDescription)")
                    let logURL = self.writeOperationLog(for: "生成", in: self.outputDirectoryURL)
                    self.recordHistory(
                        message: "生成失敗",
                        detail: error.localizedDescription,
                        relatedURLs: [logURL].compactMap { $0 },
                        isError: true
                    )
                    self.isProcessing = false
                }
            }
        }
    }

    private func collectIPAFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "ipa" {
                results.append(url)
            }
        }
        return results
    }

    private func ipaStorageDirectories() -> [URL] {
        var dirs: [URL] = []
        dirs.append(ipaStorageDirectory())
        let fallback = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedIPAs", isDirectory: true)
        if fallback != dirs.first {
            dirs.append(fallback)
        }
        return dirs
    }

    private func scanApps(in root: URL) -> [InstalledApp] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [InstalledApp] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "app" {
                if let app = makeInstalledApp(from: url) {
                    results.append(app)
                }
                enumerator.skipDescendants()
            }
        }
        return results
    }

    private func scanAppsOneLevel(in root: URL) -> [InstalledApp] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        guard let top = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [InstalledApp] = []
        for url in top {
            if url.pathExtension == "app" {
                if let app = makeInstalledApp(from: url) {
                    results.append(app)
                }
                continue
            }
            if let children = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for child in children where child.pathExtension == "app" {
                    if let app = makeInstalledApp(from: child) {
                        results.append(app)
                    }
                }
            }
        }
        return results
    }

    private func isAppStoreApp(_ appURL: URL) -> Bool {
        let path = appURL.path
        if path.hasPrefix("/var/jb/Applications") || path.hasPrefix("/private/var/jb/Applications") {
            return false
        }
        if path.contains("/Containers/Bundle/Application") || path.contains("/containers/Bundle/Application") {
            if isRootlessEnvironment() {
                return false
            }
            return true
        }
        if path.contains("/var/mobile/Containers/Bundle/Application") || path.contains("/private/var/mobile/Containers/Bundle/Application") {
            return true
        }
        if path.contains("/var/jb/var/containers/Bundle/Application") || path.contains("/private/var/jb/var/containers/Bundle/Application") {
            return true
        }
        if path.contains("/var/containers/Bundle/Application") || path.contains("/private/var/containers/Bundle/Application") {
            return true
        }
        let receiptURL = appURL.appendingPathComponent("StoreKit/receipt")
        let masReceiptURL = appURL.appendingPathComponent("_MASReceipt/receipt")
        let scInfoURL = appURL.appendingPathComponent("SC_Info")
        return FileManager.default.fileExists(atPath: receiptURL.path)
            || FileManager.default.fileExists(atPath: masReceiptURL.path)
            || FileManager.default.fileExists(atPath: scInfoURL.path)
    }

    private func isRootlessEnvironment() -> Bool {
        return FileManager.default.fileExists(atPath: "/var/jb/Applications")
            || FileManager.default.fileExists(atPath: "/private/var/jb/Applications")
    }

    private func isLikelyRootlessOnly(apps: [InstalledApp]) -> Bool {
        guard !apps.isEmpty else { return false }
        if isRootlessEnvironment() {
            return true
        }
        let jbApps = apps.filter {
            let path = $0.appURL.path
            return path.hasPrefix("/var/jb/Applications") || path.hasPrefix("/private/var/jb/Applications")
        }
        let containerApps = apps.filter {
            let path = $0.appURL.path
            return path.contains("/containers/Bundle/Application") || path.contains("/Containers/Bundle/Application")
        }
        return !jbApps.isEmpty && containerApps.isEmpty
    }

    private func makeInstalledApp(from appURL: URL) -> InstalledApp? {
        let infoURL = appURL.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoURL) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        guard let bundleId = plist["CFBundleIdentifier"] as? String else { return nil }
        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        let lastModified = (try? appURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        return InstalledApp(
            id: bundleId,
            name: name,
            bundleId: bundleId,
            appURL: appURL,
            lastModified: lastModified,
            sizeBytes: nil
        )
    }

    private func ipaStorageDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if enableOutputFolder {
            return documents.appendingPathComponent(outputFolderName, isDirectory: true)
        }
        return documents.appendingPathComponent("ImportedIPAs", isDirectory: true)
    }

    private func dylibStorageDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ImportedDylibs", isDirectory: true)
    }

    private func iconStorageDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ImportedIcons", isDirectory: true)
    }

    private func uniqueDestinationURL(in directory: URL, name: String) -> URL {
        let baseURL = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: baseURL.path) {
            return baseURL
        }
        let stem = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension
        var index = 1
        while true {
            let candidate = directory.appendingPathComponent("\(stem)-\(index).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func appURLCandidates(from path: String) -> [String] {
        var results: [String] = [path]
        let mappings: [(String, String)] = [
            ("/private/var/containers/Bundle/Application", "/var/containers/Bundle/Application"),
            ("/var/containers/Bundle/Application", "/private/var/containers/Bundle/Application"),
            ("/private/var/containers/Bundle/Application", "/private/var/jb/var/containers/Bundle/Application"),
            ("/var/containers/Bundle/Application", "/var/jb/var/containers/Bundle/Application"),
            ("/private/var/mobile/Containers/Bundle/Application", "/var/mobile/Containers/Bundle/Application"),
            ("/var/mobile/Containers/Bundle/Application", "/private/var/mobile/Containers/Bundle/Application"),
            ("/private/var/mobile/Containers/Bundle/Application", "/private/var/jb/var/mobile/Containers/Bundle/Application"),
            ("/var/mobile/Containers/Bundle/Application", "/var/jb/var/mobile/Containers/Bundle/Application"),
            ("/Applications", "/var/jb/Applications"),
            ("/private/var/Applications", "/private/var/jb/Applications")
        ]
        for (src, dst) in mappings where path.hasPrefix(src) {
            let replaced = path.replacingOccurrences(of: src, with: dst)
            results.append(replaced)
        }
        return results
    }

    private func copyAppBundleWithFallback(
        fromCandidates candidates: [String],
        to destination: URL,
        expectedExecutable: String?
    ) throws -> (skippedFiles: [String], detectedExecutable: String?) {
        var lastError: Error?
        var skippedFiles: [String] = []
        var detectedExecutable: String?
        for candidatePath in candidates {
            let sourceURL = URL(fileURLWithPath: candidatePath, isDirectory: true)
            appendLog("コピー元: \(candidatePath)")
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                detectedExecutable = guessExecutableName(in: sourceURL)
                return (skippedFiles, detectedExecutable)
            } catch {
                lastError = error
                appendLog("コピー失敗（直コピー）: \(error.localizedDescription)")
                do {
                    skippedFiles = try copyDirectorySkippingUnreadable(
                        from: sourceURL,
                        to: destination,
                        expectedExecutable: expectedExecutable
                    )
                    detectedExecutable = guessExecutableName(in: sourceURL)
                    appendLog("コピー完了（スキップあり）")
                    return (skippedFiles, detectedExecutable)
                } catch {
                    lastError = error
                    appendLog("コピー失敗（スキップ方式）: \(error.localizedDescription)")
                }
            }
        }
        if let lastError {
            throw lastError
        }
        return (skippedFiles, detectedExecutable)
    }

    private func copyDirectorySkippingUnreadable(
        from source: URL,
        to destination: URL,
        expectedExecutable: String?
    ) throws -> [String] {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: nil)
        guard let enumerator = FileManager.default.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var skipped: [String] = []
        for case let itemURL as URL in enumerator {
            let relative = relativePath(from: source, to: itemURL)
            let targetURL = destination.appendingPathComponent(relative)
            if itemURL.hasDirectoryPath {
                try? FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
                continue
            }
            do {
                try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                try FileManager.default.copyItem(at: itemURL, to: targetURL)
            } catch {
                if copyFileDataOnly(from: itemURL, to: targetURL) {
                    appendLog("コピー(データのみ): \(relative)")
                    continue
                }
                if let expectedExecutable,
                   itemURL.lastPathComponent.lowercased() == expectedExecutable.lowercased(),
                   let data = try? Data(contentsOf: itemURL) {
                    do {
                        try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                        try data.write(to: targetURL)
                        appendLog("実行ファイルを復元: \(expectedExecutable)")
                        continue
                    } catch {
                        appendLog("実行ファイル復元失敗: \(error.localizedDescription)")
                    }
                }
                appendLog("スキップ: \(relative)")
                skipped.append(relative)
            }
        }
        return skipped
    }

    private func relativePath(from base: URL, to item: URL) -> String {
        let basePath = base.path
        let itemPath = item.path
        if itemPath == basePath {
            return ""
        }
        if itemPath.hasPrefix(basePath + "/") {
            let start = itemPath.index(itemPath.startIndex, offsetBy: basePath.count + 1)
            return String(itemPath[start...])
        }
        return item.lastPathComponent
    }

    private func ensureInfoPlist(for destAppURL: URL, fromCandidates candidates: [String]) -> Bool {
        let destInfoURL = destAppURL.appendingPathComponent("Info.plist")
        if FileManager.default.fileExists(atPath: destInfoURL.path) {
            return true
        }
        for candidatePath in candidates {
            let sourceInfoURL = URL(fileURLWithPath: candidatePath, isDirectory: true).appendingPathComponent("Info.plist")
            if let data = try? Data(contentsOf: sourceInfoURL) {
                do {
                    try FileManager.default.createDirectory(
                        at: destInfoURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                    try data.write(to: destInfoURL)
                    appendLog("Info.plist を復元しました")
                    return true
                } catch {
                    appendLog("Info.plist 復元失敗: \(error.localizedDescription)")
                }
            }
        }
        return false
    }

    private func ensureExecutable(
        for destAppURL: URL,
        fromCandidates candidates: [String],
        expectedExecutable: String
    ) -> Bool {
        let destExecURL = destAppURL.appendingPathComponent(expectedExecutable)
        if FileManager.default.fileExists(atPath: destExecURL.path) {
            return true
        }
        if copyExecutableNamed(expectedExecutable, fromCandidates: candidates, to: destExecURL) {
            return true
        }
        for candidatePath in candidates {
            let appURL = URL(fileURLWithPath: candidatePath, isDirectory: true)
            let fallbackNames = executableCandidates(in: appURL).filter { $0.lowercased() != expectedExecutable.lowercased() }
            for name in fallbackNames {
                let fallbackDest = destAppURL.appendingPathComponent(name)
                if copyExecutableNamed(name, fromCandidates: [candidatePath], to: fallbackDest) {
                    appendLog("実行ファイルを代替コピー: \(name)")
                    return true
                }
            }
        }
        return false
    }

    private func writeFallbackInfoPlist(for destAppURL: URL, app: InstalledApp, executableName: String?) -> Bool {
        let destInfoURL = destAppURL.appendingPathComponent("Info.plist")
        if FileManager.default.fileExists(atPath: destInfoURL.path) {
            return true
        }
        let resolvedExecutable = executableName
            ?? guessExecutableName(in: destAppURL)
            ?? destAppURL.deletingPathExtension().lastPathComponent
        let plist: [String: Any] = [
            "CFBundleIdentifier": app.bundleId,
            "CFBundleExecutable": resolvedExecutable,
            "CFBundleName": app.name,
            "CFBundleDisplayName": app.name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1"
        ]
        do {
            try FileManager.default.createDirectory(
                at: destInfoURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
            try data.write(to: destInfoURL)
            return true
        } catch {
            appendLog("Info.plist 暫定生成失敗: \(error.localizedDescription)")
            return false
        }
    }

    private func guessExecutableName(in appURL: URL) -> String? {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: appURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for item in items {
            if item.lastPathComponent == "Info.plist" { continue }
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory { continue }
            if item.pathExtension.isEmpty {
                return item.lastPathComponent
            }
        }
        return nil
    }

    private func resolveExecutableName(fromCandidates candidates: [String]) -> String? {
        for candidatePath in candidates {
            let appURL = URL(fileURLWithPath: candidatePath, isDirectory: true)
            let infoURL = appURL.appendingPathComponent("Info.plist")
            if let data = try? Data(contentsOf: infoURL),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let executable = plist["CFBundleExecutable"] as? String,
               !executable.isEmpty {
                return executable
            }
        }
        return nil
    }

    private func resolveExecutableNameByScanning(candidates: [String]) -> String? {
        for candidatePath in candidates {
            let appURL = URL(fileURLWithPath: candidatePath, isDirectory: true)
            let names = executableCandidates(in: appURL)
            if let name = names.first {
                return name
            }
        }
        return nil
    }

    private func resolveExecutableNameFromWorkspace(bundleId: String) -> String? {
        guard let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else {
            return nil
        }
        let selector = NSSelectorFromString("defaultWorkspace")
        guard workspaceClass.responds(to: selector) else { return nil }
        guard let workspace = workspaceClass.perform(selector)?.takeUnretainedValue() as? NSObject else {
            return nil
        }
        let proxySelector = NSSelectorFromString("applicationProxyForIdentifier:")
        guard workspace.responds(to: proxySelector) else { return nil }
        guard let proxy = workspace.perform(proxySelector, with: bundleId)?.takeUnretainedValue() as? NSObject else {
            return nil
        }
        let execSelector = NSSelectorFromString("bundleExecutable")
        if proxy.responds(to: execSelector),
           let exec = proxy.perform(execSelector)?.takeUnretainedValue() as? String,
           !exec.isEmpty {
            return exec
        }
        if let exec = proxy.value(forKey: "bundleExecutable") as? String, !exec.isEmpty {
            return exec
        }
        return nil
    }

    private func executableCandidates(in appURL: URL) -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: appURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isExecutableKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var results: [String] = []
        for item in items {
            let name = item.lastPathComponent
            if name == "Info.plist" || name == "PkgInfo" { continue }
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isExecutableKey])
            if values?.isDirectory == true { continue }
            if values?.isRegularFile == false { continue }
            if !name.contains(".") {
                if values?.isExecutable == true || values?.isExecutable == nil {
                    results.append(name)
                }
            }
        }
        return results
    }

    private func copyExecutableNamed(_ name: String, fromCandidates candidates: [String], to destExecURL: URL) -> Bool {
        for candidatePath in candidates {
            let sourceExecURL = URL(fileURLWithPath: candidatePath, isDirectory: true).appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: sourceExecURL.path) {
                continue
            }
            if !FileManager.default.isReadableFile(atPath: sourceExecURL.path) {
                appendLog("実行ファイル読み取り不可: \(sourceExecURL.path)")
            }
            do {
                try FileManager.default.createDirectory(
                    at: destExecURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                try FileManager.default.copyItem(at: sourceExecURL, to: destExecURL)
                appendLog("実行ファイルをコピー: \(name)")
                return true
            } catch {
                if copyFileDataOnly(from: sourceExecURL, to: destExecURL) {
                    appendLog("実行ファイルをコピー(データのみ): \(name)")
                    return true
                }
                if let data = try? Data(contentsOf: sourceExecURL) {
                    do {
                        try data.write(to: destExecURL)
                        appendLog("実行ファイルを復元: \(name)")
                        return true
                    } catch {
                        appendLog("実行ファイル復元失敗: \(error.localizedDescription)")
                    }
                }
            }
        }
        return false
    }

    private func copyFileDataOnly(from source: URL, to destination: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            return false
        }
        let result = copyfile(source.path, destination.path, nil, copyfile_flags_t(COPYFILE_DATA))
        return result == 0
    }

    private func writeSkippedFilesLog(for appName: String, skipped: [String], in directory: URL) throws -> URL {
        let safeName = appName.replacingOccurrences(of: "/", with: "_")
        let fileName = "skipped-\(safeName)-\(Int(Date().timeIntervalSince1970)).txt"
        let url = directory.appendingPathComponent(fileName)
        let body = skipped.joined(separator: "\n")
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func analyzeSkippedFiles(_ skipped: [String], in appURL: URL) -> [String] {
        var warnings: [String] = []
        let lowercased = skipped.map { $0.lowercased() }
        if lowercased.contains(where: { $0.hasSuffix("info.plist") }) {
            warnings.append("Info.plist がコピーできていません")
        }
        if lowercased.contains(where: { $0.contains("/frameworks/") || $0.contains("\\frameworks\\") }) {
            warnings.append("Frameworks 内のファイルがスキップされています")
        }
        if lowercased.contains(where: { $0.contains("/plugins/") || $0.contains("/plug-ins/") }) {
            warnings.append("PlugIns 内のファイルがスキップされています")
        }
        if lowercased.contains(where: { $0.contains("embedded.mobileprovision") }) {
            warnings.append("embedded.mobileprovision がコピーできていません")
        }
        if let executable = guessExecutableName(in: appURL) {
            if lowercased.contains(where: { $0.hasSuffix("/\(executable.lowercased())") || $0 == executable.lowercased() }) {
                warnings.append("実行ファイルがスキップされています")
            }
        }
        return warnings
    }

    private func validateIPA(at url: URL, expectedExecutable: String?) -> [String] {
        var warnings: [String] = []
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("IPAValidate-\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
            try fileManager.unzipItem(at: url, to: tempRoot)
            let payloadURL = tempRoot.appendingPathComponent("Payload", isDirectory: true)
            guard let enumerator = fileManager.enumerator(at: payloadURL, includingPropertiesForKeys: nil) else {
                warnings.append("Payload が見つかりません")
                return warnings
            }
            var appURL: URL?
            for case let itemURL as URL in enumerator where itemURL.pathExtension == "app" {
                appURL = itemURL
                break
            }
            guard let appURL else {
                warnings.append("Payload 内に .app がありません")
                return warnings
            }
            let infoURL = appURL.appendingPathComponent("Info.plist")
            guard fileManager.fileExists(atPath: infoURL.path) else {
                warnings.append("Info.plist がありません")
                return warnings
            }
            let data = try Data(contentsOf: infoURL)
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            guard let info = plist else {
                warnings.append("Info.plist が読み取れません")
                return warnings
            }
            if info["CFBundleIdentifier"] == nil {
                warnings.append("CFBundleIdentifier がありません")
            }
            if let executable = info["CFBundleExecutable"] as? String {
                let exeURL = appURL.appendingPathComponent(executable)
                if !fileManager.fileExists(atPath: exeURL.path) {
                    warnings.append("実行ファイルが見つかりません")
                }
            } else {
                warnings.append("CFBundleExecutable がありません")
            }
            if let expectedExecutable, !expectedExecutable.isEmpty {
                let expectedURL = appURL.appendingPathComponent(expectedExecutable)
                if !fileManager.fileExists(atPath: expectedURL.path) {
                    warnings.append("期待した実行ファイルが見つかりません: \(expectedExecutable)")
                }
            }
        } catch {
            warnings.append("検証失敗: \(error.localizedDescription)")
        }
        try? fileManager.removeItem(at: tempRoot)
        return warnings
    }

    private func directorySize(for url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { continue }
            guard values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func outputFileName(for app: InstalledApp) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let date = formatter.string(from: Date())
        let template = outputNameTemplate.isEmpty ? "{name}" : outputNameTemplate
        let replaced = template
            .replacingOccurrences(of: "{name}", with: app.name)
            .replacingOccurrences(of: "{bundle}", with: app.bundleId)
            .replacingOccurrences(of: "{date}", with: date)
            .replacingOccurrences(of: "{id}", with: app.id)
        let safe = sanitizeFileName(replaced)
        return safe.hasSuffix(".ipa") ? safe : "\(safe).ipa"
    }

    private func sanitizeFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?\"<>|")
        let sanitized = value.components(separatedBy: invalid).joined(separator: "_")
        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func writeOperationLog(for label: String, in directory: URL) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeLabel = sanitizeFileName(label)
        let fileName = "log-\(safeLabel)-\(formatter.string(from: Date())).txt"
        let url = directory.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            try logText.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            appendLog("ログ保存失敗: \(error.localizedDescription)")
            return nil
        }
    }

    private func recordHistory(message: String, detail: String?, relatedURLs: [URL], isError: Bool) {
        guard enableHistory else { return }
        let item = HistoryItem(date: Date(), message: message, detail: detail, relatedURLs: relatedURLs, isError: isError)
        historyItems.insert(item, at: 0)
    }

    func saveDylibPreset() {
        let trimmed = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            appendLog("プリセット名を入力してください")
            return
        }
        let paths = dylibURLs.map { $0.path }
        guard !paths.isEmpty else {
            appendLog("プリセットに登録するdylibがありません")
            return
        }
        let preset = DylibPreset(name: trimmed, paths: paths)
        dylibPresets.append(preset)
        persistDylibPresets()
        newPresetName = ""
        appendLog("プリセット保存: \(preset.name)")
    }

    func applyDylibPreset(_ preset: DylibPreset) {
        let urls = preset.paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        dylibURLs = urls
        selectedDylibPresetID = preset.id
        appendLog("プリセット適用: \(preset.name)")
    }

    func deleteDylibPreset(_ preset: DylibPreset) {
        dylibPresets.removeAll { $0.id == preset.id }
        if selectedDylibPresetID == preset.id {
            selectedDylibPresetID = nil
        }
        persistDylibPresets()
        appendLog("プリセット削除: \(preset.name)")
    }

    private func persistDylibPresets() {
        if let data = try? JSONEncoder().encode(dylibPresets) {
            settings.saveDylibPresetsData(data)
        }
    }

    private func fetchAppsViaLSApplicationWorkspace() -> [InstalledApp] {
        guard let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else {
            return []
        }
        let selector = NSSelectorFromString("defaultWorkspace")
        guard workspaceClass.responds(to: selector) else { return [] }
        guard let workspace = workspaceClass.perform(selector)?.takeUnretainedValue() as? NSObject else {
            return []
        }
        let allSelector = NSSelectorFromString("allApplications")
        guard workspace.responds(to: allSelector) else { return [] }
        guard let appList = workspace.perform(allSelector)?.takeUnretainedValue() as? [NSObject] else {
            return []
        }

        var results: [InstalledApp] = []
        for app in appList {
            let idSel = NSSelectorFromString("applicationIdentifier")
            let nameSel = NSSelectorFromString("localizedName")
            let urlSel = NSSelectorFromString("bundleURL")

            guard let bundleId = app.perform(idSel)?.takeUnretainedValue() as? String else { continue }
            let name = (app.perform(nameSel)?.takeUnretainedValue() as? String) ?? bundleId
            guard let bundleURL = app.perform(urlSel)?.takeUnretainedValue() as? URL else { continue }
            let lastModified = (try? bundleURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            results.append(
                InstalledApp(
                    id: bundleId,
                    name: name,
                    bundleId: bundleId,
                    appURL: bundleURL,
                    lastModified: lastModified,
                    sizeBytes: nil
                )
            )
        }

        return results.sorted { $0.name < $1.name }
    }

    private func appendLog(_ line: String) {
        if logText.isEmpty {
            logText = line
        } else {
            logText += "\n" + line
        }
    }
}
