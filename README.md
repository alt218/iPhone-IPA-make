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

## バグ修正
- roothideではメインバイナリをうまく取得できずIPAを吸い出せません。
- rootlessではアプリ一覧がうまく取得できず一部のアプリしか吸い出せません

##　サポート環境
- IOS15以上
- rootless roothide 未脱獄

## 技術スタック

- UI: SwiftUI
- ZIP: ZIPFoundation
- Mach-O編集: Swiftによる独自実装
- プロジェクト生成: XcodeGen

## 注意事項

- コード署名やプロビジョニングは行いません
- 生成されるIPAはTrollStore向けの利用を想定しています
- Mach-O注入の対象は64-bit Mach-Oスライスです
- 元のバイナリに十分なヘッダ余白がない場合、注入は失敗します
