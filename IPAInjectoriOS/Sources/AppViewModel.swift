import Foundation
import SwiftUI

enum GenerationMode: String, CaseIterable, Identifiable {
    case count
    case suffixes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .count:
            return "Count"
        case .suffixes:
            return "Suffixes"
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var ipaURL: URL?
    @Published var dylibURLs: [URL] = []
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
        ipaURL?.lastPathComponent ?? "No IPA selected"
    }

    func handleIPASelection(_ result: Result<[URL], Error>) {
        do {
            ipaURL = try result.get().first
        } catch {
            errorMessage = error.localizedDescription
        }
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
            errorMessage = "Select an IPA file."
            return
        }

        guard !dylibURLs.isEmpty else {
            errorMessage = "Select at least one dylib file."
            return
        }

        let suffixes: [String]
        switch mode {
        case .count:
            guard countValue > 0 else {
                errorMessage = "Count must be greater than 0."
                return
            }
            suffixes = (1...countValue).map { "a\($0)" }
        case .suffixes:
            suffixes = suffixInput
                .components(separatedBy: CharacterSet(charactersIn: ", \n\t"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !suffixes.isEmpty else {
                errorMessage = "Enter at least one suffix."
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
                    self.appendLog("Completed: generated \(result.outputURLs.count) IPA files")
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.appendLog("Error: \(error.localizedDescription)")
                    self.isProcessing = false
                }
            }
        }
    }

    private func appendLog(_ line: String) {
        if logText.isEmpty {
            logText = line
        } else {
            logText += "\n" + line
        }
    }
}
