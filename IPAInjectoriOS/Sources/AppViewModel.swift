import Foundation
import SwiftUI

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
    @Published var ipaURL: URL?
    @Published var dylibURLs: [URL] = []
    @Published var availableIPAs: [URL] = []
    @Published var mode: GenerationMode = .count {
        didSet { settings.save(mode: mode) }
    }
    @Published var countValue: Int = 10 {
        didSet { settings.save(count: countValue) }
    }
    @Published var suffixInput: String = "a1, a2, a3" {
        didSet { settings.save(suffixInput: suffixInput) }
    }
    @Published var isSelectingIPAList = false
    @Published var isImportingDylibs = false
    @Published var isProcessing = false
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
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let ipaFiles = collectIPAFiles(in: documents)
        availableIPAs = ipaFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func selectIPA(_ url: URL) {
        ipaURL = url
        isSelectingIPAList = false
    }

    func handleDylibSelection(_ result: Result<[URL], Error>) {
        do {
            dylibURLs = try result.get().sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            errorMessage = error.localizedDescription
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

        guard !dylibURLs.isEmpty else {
            errorMessage = "dylibを1つ以上選択してください。"
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

    private func appendLog(_ line: String) {
        if logText.isEmpty {
            logText = line
        } else {
            logText += "\n" + line
        }
    }
}
