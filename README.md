# Time Machine Viewer

macOS の Time Machine バックアップの進み具合を、標準の設定画面より詳しく表示するアプリです。

`tmutil status` で段階と全体の進捗を2秒おきに読み、あわせて backupd が統合ログ (`com.apple.TimeMachine`) に書く記録を `log stream` で受け取ります。ログには約1分おきに、いま処理中のファイルのパス、転送速度、容量や項目数ごとの進み、変更検出の進み具合が出るため、それをもとに次のものを表示します。

- 概要: 段階、進捗、残り時間、いま処理中のパスとそこに留まっている時間、backupd のエラー
- ディレクトリ: どのディレクトリで時間を使ったかの一覧 (区切る階層は変えられます)
- 推移: 転送速度、処理速度、進捗のグラフ
- ログ: backupd のログ (頻繁に出るだけの行は省いています)

管理者権限は要りません。

## ビルド

Xcode 16 以降と macOS 15 以降が必要です。

```sh
swift test               # 解析部のテスト
swift run                # そのまま起動
./scripts/bundle.sh      # build/Time Machine Viewer.app を作る
```
