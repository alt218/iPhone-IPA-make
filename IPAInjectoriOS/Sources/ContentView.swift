import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    private let ipaType = UTType(filenameExtension: "ipa") ?? .data
    private let dylibType = UTType(filenameExtension: "dylib") ?? .data

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    inputSection
                    generationSection
                    actionSection
                    outputSection
                    logSection
                }
                .padding(16)
            }
            .navigationTitle("IPA Multi Generator")
            .fileImporter(
                isPresented: $viewModel.isImportingIPA,
                allowedContentTypes: [ipaType],
                allowsMultipleSelection: false
            ) { result in
                viewModel.handleIPASelection(result)
            }
            .fileImporter(
                isPresented: $viewModel.isImportingDylibs,
                allowedContentTypes: [dylibType],
                allowsMultipleSelection: true
            ) { result in
                viewModel.handleDylibSelection(result)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generate multiple modified IPA files from one base IPA")
                .font(.title2.bold())
            Text("Change the bundle identifier and inject multiple dylibs into each variant.")
                .foregroundStyle(.secondary)
        }
    }

    private var inputSection: some View {
        GroupBox("Input") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("IPA")
                        .font(.headline)
                    Text(viewModel.ipaLabel)
                        .foregroundStyle(viewModel.ipaURL == nil ? .secondary : .primary)
                    Button("Select IPA") {
                        viewModel.isImportingIPA = true
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("dylibs")
                        .font(.headline)
                    if viewModel.dylibURLs.isEmpty {
                        Text("No dylib selected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.dylibURLs, id: \.path) { url in
                            Text(url.lastPathComponent)
                                .font(.body.monospaced())
                        }
                    }

                    Button("Select dylibs") {
                        viewModel.isImportingDylibs = true
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var generationSection: some View {
        GroupBox("Generation") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Mode", selection: $viewModel.mode) {
                    ForEach(GenerationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.mode == .count {
                    HStack {
                        Text("Count")
                            .frame(width: 60, alignment: .leading)
                        TextField("10", value: $viewModel.countValue, format: .number)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        Text("Auto generates a1, a2, a3...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("suffix")
                        TextEditor(text: $viewModel.suffixInput)
                            .frame(minHeight: 120)
                            .padding(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.3))
                            )
                        Text("Comma, whitespace, or newline separated. Example: a1, a2, a3")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionSection: some View {
        GroupBox("Run") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    viewModel.run()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isProcessing {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(viewModel.isProcessing ? "Processing..." : "Build IPA Variants")
                            .bold()
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isProcessing)

                Text("Output: \(viewModel.outputDirectoryURL.path)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var outputSection: some View {
        GroupBox("Output") {
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.generatedFiles.isEmpty {
                    Text("No output yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.generatedFiles, id: \.path) { url in
                        HStack {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            ShareLink(item: url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logSection: some View {
        GroupBox("Log") {
            ScrollView {
                Text(viewModel.logText.isEmpty ? "Logs will appear here" : viewModel.logText)
                    .font(.body.monospaced())
                    .foregroundStyle(viewModel.logText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 220)
        }
    }
}
