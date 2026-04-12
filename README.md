# IPAInjectoriOS

1つのIPAから、改変版IPAをまとめて生成するiPhoneアプリです。

## 機能

- 1つのIPAから複数の改変版IPAを生成
- 各サフィックスごとに `CFBundleIdentifier` を変更
- 複数の `dylib` を `App.app/dylibs` に配置
- メイン実行ファイルに `LC_LOAD_DYLIB` を注入
- アプリ内で処理ログを表示
- 生成したIPAをそのまま共有

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

## 注意事項

- コード署名やプロビジョニングは行いません
- 生成されるIPAはTrollStore向けの利用を想定しています
- Mach-O注入の対象は64-bit Mach-Oスライスです
- 元のバイナリに十分なヘッダ余白がない場合、注入は失敗します
