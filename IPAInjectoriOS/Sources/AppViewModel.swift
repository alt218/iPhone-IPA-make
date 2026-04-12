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

@MainActor
final class AppViewModel: ObservableObject {
    struct InstalledApp: Identifiable {
        let id: String
        let name: String
        let bundleId: String
        let appURL: URL
    }

    @Published var ipaURL: URL?
    @Published var dylibURLs: [URL] = []
    @Published var availableIPAs: [URL] = []
    @Published var installedApps: [InstalledApp] = []
    @Published var installedAppsQuery: String = ""
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
    @Published var isProcessing = false
    @Published var isExportingIPA = false
    @Published var exportStatus = ""
    @Published var isConfirmingDelete = false
    @Published var pendingDeleteIPA: URL?
    @Published var errorMessage: String?
    @Published var logText = ""
    @Published var generatedFiles: [URL] = []

    let outputDirectoryURL: URL

    private let settings = SettingsStore()

    init() {
        let snapshot = settings.load()
        mode = snapshot.mode
        countValue = snapshot.count
        suffixInput = snapshot.suffixInput
        outputDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GeneratedIPAs", isDirectory: true)
    }

    var ipaLabel: String {
        ipaURL?.lastPathComponent ?? "IPAが選択されていません"
    }

    func refreshAvailableIPAs() {
        let ipaFiles = collectIPAFiles(in: ipaStorageDirectory())
        availableIPAs = ipaFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func selectIPA(_ url: URL) {
        ipaURL = url
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

    func refreshInstalledApps() {
        installedApps = []
        installedAppsQuery = ""

        let workspaceApps = fetchAppsViaLSApplicationWorkspace()
        if !workspaceApps.isEmpty {
            installedApps = workspaceApps
            appendLog("LSApplicationWorkspace: \(installedApps.count) 件")
            return
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
        let base = storeApps.isEmpty ? apps : storeApps
        let unique = Dictionary(grouping: base, by: { $0.bundleId })
            .compactMap { $0.value.first }
            .sorted { $0.name < $1.name }

        installedApps = unique
        if storeApps.isEmpty {
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
    }

    func exportInstalledAppToIPA(_ app: InstalledApp) {
        do {
            isExportingIPA = true
            exportStatus = "吸い出し開始: \(app.name)"
            appendLog(exportStatus)
            let destDir = ipaStorageDirectory()
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
            let fileName = "\(app.name).ipa"
            let destURL = uniqueDestinationURL(in: destDir, name: fileName)

            let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("IPAExtract-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
            defer { try? FileManager.default.removeItem(at: tempRoot) }

            let payloadURL = tempRoot.appendingPathComponent("Payload", isDirectory: true)
            try FileManager.default.createDirectory(at: payloadURL, withIntermediateDirectories: true, attributes: nil)
            let destAppURL = payloadURL.appendingPathComponent(app.appURL.lastPathComponent)
            exportStatus = "アプリをコピー中..."
            appendLog(exportStatus)
            try FileManager.default.copyItem(at: app.appURL, to: destAppURL)

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
            exportStatus = "吸い出し完了: \(destURL.lastPathComponent)"
            appendLog(exportStatus)
            isExportingIPA = false
        } catch {
            errorMessage = error.localizedDescription
            exportStatus = "吸い出し失敗: \(error.localizedDescription)"
            appendLog(exportStatus)
            isExportingIPA = false
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

    func filteredInstalledApps() -> [InstalledApp] {
        let query = installedAppsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return installedApps
        }
        return installedApps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
            || $0.bundleId.localizedCaseInsensitiveContains(query)
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
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.appendLog("エラー: \(error.localizedDescription)")
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
        if path.contains("/Containers/Bundle/Application") || path.contains("/containers/Bundle/Application") {
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
        return InstalledApp(id: bundleId, name: name, bundleId: bundleId, appURL: appURL)
    }

    private func ipaStorageDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ImportedIPAs", isDirectory: true)
    }

    private func dylibStorageDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("ImportedDylibs", isDirectory: true)
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
            results.append(InstalledApp(id: bundleId, name: name, bundleId: bundleId, appURL: bundleURL))
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
