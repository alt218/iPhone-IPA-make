import Foundation
import ZIPFoundation

struct GenerationResult {
    let outputURLs: [URL]
}

enum IPAProcessorError: LocalizedError {
    case appBundleNotFound
    case executableNotFound
    case bundleIdentifierMissing

    var errorDescription: String? {
        switch self {
        case .appBundleNotFound:
            return "IPA内に Payload/App.app が見つかりません。"
        case .executableNotFound:
            return "メイン実行ファイルが見つかりません。"
        case .bundleIdentifierMissing:
            return "Info.plist に CFBundleIdentifier がありません。"
        }
    }
}

final class IPAProcessor {
    private let fileManager = FileManager.default
    private let injector = MachOInjector()

    func generateVariants(
        ipaURL: URL,
        dylibURLs: [URL],
        suffixes: [String],
        outputDirectoryURL: URL,
        log: @escaping @Sendable (String) async -> Void
    ) async throws -> GenerationResult {
        try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let sessionOutputURL = outputDirectoryURL.appendingPathComponent(timestamp, isDirectory: true)
        try fileManager.createDirectory(at: sessionOutputURL, withIntermediateDirectories: true, attributes: nil)

        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("IPAInjectoriOS-\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? fileManager.removeItem(at: tempRoot) }

        let baseExtractURL = tempRoot.appendingPathComponent("base", isDirectory: true)
        try fileManager.createDirectory(at: baseExtractURL, withIntermediateDirectories: true, attributes: nil)

        await log("IPAを展開中: \(ipaURL.lastPathComponent)")
        try fileManager.unzipItem(at: ipaURL, to: baseExtractURL)

        let appBundleURL = try findAppBundle(in: baseExtractURL)
        let infoPlistURL = appBundleURL.appendingPathComponent("Info.plist")
        let originalInfo = try loadPlist(at: infoPlistURL)
        guard let originalBundleID = originalInfo["CFBundleIdentifier"] as? String else {
            throw IPAProcessorError.bundleIdentifierMissing
        }

        let executableName = try resolveExecutableName(info: originalInfo)
        let baseName = ipaURL.deletingPathExtension().lastPathComponent
        var outputs: [URL] = []

        await log("元のBundle ID: \(originalBundleID)")
        await log("実行ファイル: \(executableName)")

        for (index, rawSuffix) in suffixes.enumerated() {
            let suffix = sanitizeSuffix(rawSuffix)
            let variantRootURL = tempRoot.appendingPathComponent("variant-\(index)", isDirectory: true)
            try fileManager.copyItem(at: baseExtractURL, to: variantRootURL)

            let variantAppURL = try findAppBundle(in: variantRootURL)
            let variantInfoURL = variantAppURL.appendingPathComponent("Info.plist")
            var variantInfo = try loadPlist(at: variantInfoURL)

            let bundleID = "\(originalBundleID).\(suffix)"
            variantInfo["CFBundleIdentifier"] = bundleID
            try savePlist(variantInfo, to: variantInfoURL)
            await log("[\(suffix)] Bundle ID -> \(bundleID)")

            let dylibDirectoryURL = variantAppURL.appendingPathComponent("dylibs", isDirectory: true)
            try fileManager.createDirectory(at: dylibDirectoryURL, withIntermediateDirectories: true, attributes: nil)

            let executableURL = variantAppURL.appendingPathComponent(executableName)
            guard fileManager.fileExists(atPath: executableURL.path) else {
                throw IPAProcessorError.executableNotFound
            }

            for dylibURL in dylibURLs {
                let copiedURL = dylibDirectoryURL.appendingPathComponent(dylibURL.lastPathComponent)
                try fileManager.copyItem(at: dylibURL, to: copiedURL)
                let installPath = "@executable_path/dylibs/\(dylibURL.lastPathComponent)"
                try injector.injectDylib(at: executableURL, loadPath: installPath)
                await log("[\(suffix)] コピー&注入: \(dylibURL.lastPathComponent)")
            }

            let outputURL = sessionOutputURL.appendingPathComponent("\(baseName)-\(suffix).ipa")
            if fileManager.fileExists(atPath: outputURL.path) {
                try fileManager.removeItem(at: outputURL)
            }

            await log("[\(suffix)] IPAを再パック中")
            try fileManager.zipItem(
                at: variantRootURL,
                to: outputURL,
                shouldKeepParent: false,
                compressionMethod: .deflate
            )
            outputs.append(outputURL)
        }

        return GenerationResult(outputURLs: outputs)
    }

    private func findAppBundle(in extractedRoot: URL) throws -> URL {
        let payloadURL = extractedRoot.appendingPathComponent("Payload", isDirectory: true)
        guard let enumerator = fileManager.enumerator(at: payloadURL, includingPropertiesForKeys: nil) else {
            throw IPAProcessorError.appBundleNotFound
        }

        for case let url as URL in enumerator where url.pathExtension == "app" {
            return url
        }

        throw IPAProcessorError.appBundleNotFound
    }

    private func loadPlist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return plist as? [String: Any] ?? [:]
    }

    private func savePlist(_ plist: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try data.write(to: url)
    }

    private func resolveExecutableName(info: [String: Any]) throws -> String {
        guard let executableName = info["CFBundleExecutable"] as? String, !executableName.isEmpty else {
            throw IPAProcessorError.executableNotFound
        }
        return executableName
    }

    private func sanitizeSuffix(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        let cleaned = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("_") }
        let suffix = String(cleaned)
        return suffix.isEmpty ? UUID().uuidString : suffix
    }
}
