# IPAInjectoriOS

1つのIPAから、改変版IPAをまとめて生成するiPhoneアプリです。

## 機能

- 1つのIPAから複数の改変版IPAを生成
- 各サフィックスごとに `CFBundleIdentifier` を変更
- 複数の `dylib` を `App.app/dylibs` に配置
- メイン実行ファイルに `LC_LOAD_DYLIB` を注入
- アプリ内で処理ログを表示
- 生成したIPAをそのまま共有
- メニューから機能のON/OFFを切り替え
- インストール済みアプリの一覧取得（LSApplicationWorkspace）
- rootless / hide 環境でのアプリ一覧表示と追加スキャン
- 一括吸い出し（複数アプリを連続でIPA化）
- 出力先フォルダの変更
- 出力ファイル名テンプレート（`{name}` `{bundle}` `{date}` `{id}`）
- dylibプリセットの保存・適用
- 吸い出し履歴の保存と再表示
- 吸い出し時のスキップ一覧ログ出力
- IPA検証（Payload/Info.plist/実行ファイルの存在チェック）
- アイコン差し替え用の画像インポート（準備中）

##　サポート環境
- IOS15以上
- rootless roothide 未脱獄

## 技術スタック

- UI: SwiftUI
- ZIP: ZIPFoundation
- Mach-O編集: Swiftによる独自実装
- プロジェクト生成: XcodeGen

## ローカルセットアップ

```bash
brew install xcodegen
xcodegen generate
open IPAInjectoriOS.xcodeproj
```

## GitHub Actions

`.github/workflows/build-ios.yml` では、macOSランナー上で次の処理を行います。

1. `xcodegen generate` を実行
2. `iphoneos` 向けにReleaseビルド
3. `Payload/*.app` を `.ipa` にパッケージ
4. 生成したIPAをArtifactとしてアップロード
5. AppIcon用の画像をビルド時に正規化

## 注意事項

- コード署名やプロビジョニングは行いません
- 生成されるIPAはTrollStore向けの利用を想定しています
- Mach-O注入の対象は64-bit Mach-Oスライスです
- 元のバイナリに十分なヘッダ余白がない場合、注入は失敗します
- hide環境などで `.app` が読めない場合は root コピー用ヘルパーが必要です

## root コピー用ヘルパー

`hide` 環境などで `.app` が読み取り不可な場合、iOSアプリ単体ではコピーできません。  
その場合は root 権限で `.app` をコピーするヘルパーを使ってください。

### 使い方（例）

1. アプリ側のログに `rootコピー要求: .../RootCopyRequests/<id>.txt` が出たら、そのパスを確認
2. root でヘルパーを起動

```bash
sh tools/root-copy-helper.sh \
  /var/mobile/Containers/Data/Application/<APP-UUID>/Documents/RootCopyRequests \
  /var/mobile/Containers/Data/Application/<APP-UUID>/Documents/RootCopyResults
```

ヘルパーが `RootCopyRequests` を監視し、見つけた要求を root で `cp -a` します。  
完了すると `RootCopyResults/<id>.txt` が生成され、アプリは続きを実行します。
