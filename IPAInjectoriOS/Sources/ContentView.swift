import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isShowingMenu = false
    private let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    mainContent
                }
            } else {
                NavigationView {
                    mainContent
                }
                .navigationViewStyle(.stack)
            }
        }
    }

    private var mainContent: some View {
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("メニュー") {
                    isShowingMenu = true
                }
            }
        }
        .sheet(isPresented: $viewModel.isImportingDylibs) {
            DylibFilePicker { result in
                viewModel.isImportingDylibs = false
                viewModel.handleDylibSelection(result)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $viewModel.isImportingIPA) {
            IPAFilePicker { result in
                viewModel.isImportingIPA = false
                viewModel.handleIPAImport(result)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $viewModel.isImportingIcon) {
            IconFilePicker { result in
                viewModel.isImportingIcon = false
                viewModel.handleIconSelection(result)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $viewModel.isSelectingIPAList) {
            ipaListSheet
        }
        .sheet(isPresented: $viewModel.isSelectingInstalledApps) {
            installedAppsSheet
        }
        .sheet(isPresented: $isShowingMenu) {
            menuSheet
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
                    HStack {
                        Button("IPA一覧") {
                            viewModel.refreshAvailableIPAs()
                            viewModel.isSelectingIPAList = true
                        }
                        Button("アプリ一覧") {
                            viewModel.refreshInstalledApps()
                            viewModel.isSelectingInstalledApps = true
                        }
                    }
                    Button("ファイルから追加") {
                        viewModel.startIPAImport()
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("インポート済みIPA")
                        .font(.headline)
                    if viewModel.availableIPAs.isEmpty {
                        Text("まだありません")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.availableIPAs.prefix(3), id: \.path) { url in
                            Text(url.lastPathComponent)
                                .font(.body.monospaced())
                                .lineLimit(1)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("dylib（任意）")
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
                            if #available(iOS 16.0, *) {
                                ShareLink(item: url) {
                                    Label("共有", systemImage: "square.and.arrow.up")
                                }
                            } else {
                                Button {
                                    ActivityPresenter.shared.share(url: url)
                                } label: {
                                    Label("共有", systemImage: "square.and.arrow.up")
                                }
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
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    ipaListContent
                }
            } else {
                NavigationView {
                    ipaListContent
                }
            }
        }
    }

    private var ipaListContent: some View {
        List {
            if viewModel.availableIPAs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("IPAが見つかりません")
                        .foregroundStyle(.secondary)
                    Button("ファイルから追加") {
                        viewModel.startIPAImportFromSheet()
                    }
                }
            } else {
                ForEach(viewModel.availableIPAs, id: \.path) { url in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Text(url.deletingLastPathComponent().path)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("削除") {
                            viewModel.requestDeleteIPA(url)
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectIPA(url)
                    }
                }
            }
        }
        .navigationTitle("IPA一覧")
        .confirmationDialog(
            "削除しますか？",
            isPresented: $viewModel.isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                viewModel.confirmDeleteIPA()
            }
            Button("キャンセル", role: .cancel) {
                viewModel.cancelDeleteIPA()
            }
        } message: {
            if let url = viewModel.pendingDeleteIPA {
                Text(url.lastPathComponent)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("閉じる") {
                    viewModel.isSelectingIPAList = false
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("追加") {
                    viewModel.startIPAImportFromSheet()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("更新") {
                    viewModel.refreshAvailableIPAs()
                }
            }
        }
        .onAppear {
            viewModel.cancelDeleteIPA()
            viewModel.refreshAvailableIPAs()
        }
    }

    private var installedAppsSheet: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    installedAppsContent
                }
            } else {
                NavigationView {
                    installedAppsContent
                }
            }
        }
    }

    private var menuSheet: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    menuContent
                }
            } else {
                NavigationView {
                    menuContent
                }
            }
        }
    }

    private var menuContent: some View {
        List {
            Section("機能") {
                Toggle("作業履歴ビュー", isOn: $viewModel.enableHistory)
                Toggle("フィルタ／並び替え", isOn: $viewModel.enableFilters)
                Toggle("バッチ吸い出し", isOn: $viewModel.enableBatchExport)
                Toggle("スキップ一覧の自動解析", isOn: $viewModel.enableSkipAnalysis)
                Toggle("ZIP検証とIPA検証", isOn: $viewModel.enableValidation)
                Toggle("出力先のカスタム", isOn: $viewModel.enableOutputFolder)
                Toggle("dylibのプリセット", isOn: $viewModel.enableDylibPresets)
                Toggle("アイコン・表示名の上書き", isOn: $viewModel.enableNameIconOverride)
            }

            Section("出力先") {
                TextField("保存先フォルダ名", text: $viewModel.outputFolderName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.enableOutputFolder)
                TextField("命名ルール（{name} / {bundle} / {date}）", text: $viewModel.outputNameTemplate)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.enableOutputFolder)
                Text("例: {name}-{date}")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("並び替え") {
                Picker("順序", selection: $viewModel.installedAppSort) {
                    ForEach(AppSortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!viewModel.enableFilters)
            }

            Section("dylibプリセット") {
                if viewModel.dylibPresets.isEmpty {
                    Text("プリセットはまだありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.dylibPresets) { preset in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(preset.name)
                                Text("\(preset.paths.count) 件")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("適用") {
                                viewModel.applyDylibPreset(preset)
                            }
                            Button("削除") {
                                viewModel.deleteDylibPreset(preset)
                            }
                        }
                    }
                }
                HStack {
                    TextField("プリセット名", text: $viewModel.newPresetName)
                        .textFieldStyle(.roundedBorder)
                    Button("保存") {
                        viewModel.saveDylibPreset()
                    }
                }
                .disabled(!viewModel.enableDylibPresets)
            }

            Section("表示名・アイコン") {
                TextField("表示名の上書き", text: $viewModel.overrideDisplayName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.enableNameIconOverride)
                HStack {
                    Text(viewModel.overrideIconURL?.lastPathComponent ?? "アイコン未選択")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("選択") {
                        viewModel.startIconImport()
                    }
                    .disabled(!viewModel.enableNameIconOverride)
                    if viewModel.overrideIconURL != nil {
                        Button("クリア") {
                            viewModel.overrideIconURL = nil
                        }
                        .disabled(!viewModel.enableNameIconOverride)
                    }
                }
                Text("表示名・アイコンの上書きは今後の実装予定です")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if viewModel.enableHistory {
                Section("作業履歴") {
                    if viewModel.historyItems.isEmpty {
                        Text("履歴はまだありません")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.historyItems) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.message)
                                    .foregroundStyle(item.isError ? .red : .primary)
                                if let detail = item.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Text(historyDateFormatter.string(from: item.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !item.relatedURLs.isEmpty {
                                    ForEach(item.relatedURLs, id: \.path) { url in
                                        Text(url.lastPathComponent)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("メニュー")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("閉じる") {
                    isShowingMenu = false
                }
            }
        }
    }

    private var installedAppsContent: some View {
        List {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("検索（アプリ名 / Bundle ID）", text: $viewModel.installedAppsQuery)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.vertical, 4)

            if viewModel.enableFilters {
                Picker("並び替え", selection: $viewModel.installedAppSort) {
                    ForEach(AppSortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.segmented)
            }

            if viewModel.installedApps.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("アプリ一覧を取得できません")
                        .foregroundStyle(.secondary)
                    Text("脱獄環境でのみ表示されます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("再読み込み") {
                        viewModel.refreshInstalledApps()
                    }
                }
            } else {
                ForEach(viewModel.filteredInstalledApps()) { app in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if viewModel.enableBatchExport {
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { viewModel.selectedInstalledAppIDs.contains(app.id) },
                                        set: { newValue in
                                            if newValue {
                                                viewModel.selectedInstalledAppIDs.insert(app.id)
                                            } else {
                                                viewModel.selectedInstalledAppIDs.remove(app.id)
                                            }
                                        }
                                    )
                                )
                                .labelsHidden()
                            }
                            Text(app.name)
                                .lineLimit(1)
                        }
                        Text(app.bundleId)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Button("IPAとして吸い出す") {
                            viewModel.exportInstalledAppToIPA(app)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("インストール済みアプリ")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("閉じる") {
                    viewModel.isSelectingInstalledApps = false
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("一括吸い出し") {
                    viewModel.exportSelectedAppsToIPA()
                }
                .disabled(!viewModel.enableBatchExport)
                .opacity(viewModel.enableBatchExport ? 1 : 0)
                .accessibilityHidden(!viewModel.enableBatchExport)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("更新") {
                    viewModel.refreshInstalledApps()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("ファイルから追加") {
                    viewModel.startIPAImportFromSheet()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("診断") {
                    viewModel.appendInstalledAppsDiagnostics()
                }
            }
        }
        .onAppear {
            viewModel.refreshInstalledApps()
        }
        .overlay {
            if viewModel.isExportingIPA {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(viewModel.exportStatus.isEmpty ? "吸い出し中..." : viewModel.exportStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

private struct IPAFilePicker: UIViewControllerRepresentable {
    let onPick: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (Result<[URL], Error>) -> Void

        init(onPick: @escaping (Result<[URL], Error>) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(.success([]))
        }
    }
}

private struct DylibFilePicker: UIViewControllerRepresentable {
    let onPick: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let dylibType = UTType(filenameExtension: "dylib") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [dylibType], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (Result<[URL], Error>) -> Void

        init(onPick: @escaping (Result<[URL], Error>) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(.success([]))
        }
    }
}

private struct IconFilePicker: UIViewControllerRepresentable {
    let onPick: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (Result<[URL], Error>) -> Void

        init(onPick: @escaping (Result<[URL], Error>) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(.success([]))
        }
    }
}

private final class ActivityPresenter {
    static let shared = ActivityPresenter()
    private init() {}

    func share(url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = UIApplication.shared.windows.first
        UIApplication.shared.windows.first?.rootViewController?.present(controller, animated: true)
    }
}
