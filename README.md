# IPAInjectoriOS

1つのベース IPA から複数の改変版 IPA を生成するための iPhone アプリです。

## 機能

- 1つの IPA から複数の改変版 IPA を生成
- 各 suffix ごとに `CFBundleIdentifier` を変更
- 複数の `dylib` ファイルを `App.app/dylibs` に配置
- メイン実行ファイルへ `LC_LOAD_DYLIB` を注入
- アプリ内でログを表示
- 処理後に生成された IPA を共有可能

## 技術スタック

- UI: SwiftUI
- ZIP: ZIPFoundation
- Mach-O 編集: Swift による独自実装
- プロジェクト生成: XcodeGen

## ローカルセットアップ

```bash
brew install xcodegen
xcodegen generate
open IPAInjectoriOS.xcodeproj
```

## GitHub Actions

`.github/workflows/build-ios.yml` では、macOS ランナー上で次の処理を行います。

1. `xcodegen generate` を実行
2. `iphoneos` 向けに Release ビルド
3. `Payload/*.app` を `.ipa` にパッケージ
4. 生成した IPA を Artifact としてアップロード

## 注意事項

- コード署名やプロビジョニングは行いません
- 生成される IPA は TrollStore 向けの利用を想定しています
- Mach-O 注入の対象は 64-bit Mach-O スライスです
- 元のバイナリに十分なヘッダ余白がない場合、注入は失敗します
