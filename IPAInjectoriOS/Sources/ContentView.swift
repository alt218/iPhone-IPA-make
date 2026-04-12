import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

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
            .navigationTitle("IPA一括生成")
            .fileImporter(
                isPresented: $viewModel.isImportingDylibs,
                allowedContentTypes: [dylibType],
                allowsMultipleSelection: true
            ) { result in
                viewModel.handleDylibSelection(result)
            }
            .sheet(isPresented: $viewModel.isSelectingIPAList) {
                ipaListSheet
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1つのIPAから複数の改変版IPAを生成")
                .font(.title2.bold())
            Text("Bundle ID を変更し、複数のdylibを注入します。")
                .foregroundStyle(.secondary)
        }
    }

    private var inputSection: some View {
        GroupBox("入力") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("IPA")
                        .font(.headline)
                    Text(viewModel.ipaLabel)
                        .foregroundStyle(viewModel.ipaURL == nil ? .secondary : .primary)
                    Button("IPAを選択") {
                        viewModel.refreshAvailableIPAs()
                        viewModel.isSelectingIPAList = true
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("dylib")
                        .font(.headline)
                    if viewModel.dylibURLs.isEmpty {
                        Text("dylibが選択されていません")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.dylibURLs, id: \.path) { url in
                            Text(url.lastPathComponent)
                                .font(.body.monospaced())
                        }
                    }

                    Button("dylibを選択") {
                        viewModel.isImportingDylibs = true
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var generationSection: some View {
        GroupBox("生成") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("モード", selection: $viewModel.mode) {
                    ForEach(GenerationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.mode == .count {
                    HStack {
                        Text("件数")
                            .frame(width: 70, alignment: .leading)
                        TextField("10", value: $viewModel.countValue, format: .number)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        Text("a1, a2, a3... を自動生成")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("サフィックス")
                        TextEditor(text: $viewModel.suffixInput)
                            .frame(minHeight: 120)
                            .padding(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.3))
                            )
                        Text("カンマ/空白/改行区切り。例: a1, a2, a3")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionSection: some View {
        GroupBox("実行") {
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
                        Text(viewModel.isProcessing ? "処理中..." : "IPAを生成")
                            .bold()
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isProcessing)

                Text("出力先: \(viewModel.outputDirectoryURL.path)")
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
        GroupBox("出力") {
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.generatedFiles.isEmpty {
                    Text("まだ出力はありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.generatedFiles, id: \.path) { url in
                        HStack {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            ShareLink(item: url) {
                                Label("共有", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logSection: some View {
        GroupBox("ログ") {
            ScrollView {
                Text(viewModel.logText.isEmpty ? "ログはここに表示されます" : viewModel.logText)
                    .font(.body.monospaced())
                    .foregroundStyle(viewModel.logText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 220)
        }
    }

    private var ipaListSheet: some View {
        NavigationStack {
            List {
                if viewModel.availableIPAs.isEmpty {
                    Text("IPAが見つかりません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.availableIPAs, id: \.path) { url in
                        Button {
                            viewModel.selectIPA(url)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                Text(url.deletingLastPathComponent().path)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle("IPA一覧")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        viewModel.isSelectingIPAList = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("更新") {
                        viewModel.refreshAvailableIPAs()
                    }
                }
            }
            .onAppear {
                viewModel.refreshAvailableIPAs()
            }
        }
    }
}
