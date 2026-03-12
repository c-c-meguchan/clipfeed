# Sparkle 導入 — 次にやること

コード上の Sparkle 導入は一通り完了しています。**次の2つを済ませると、更新機能が使える状態になります。**

---

## 1. 公開鍵を設定する（必須）

まだ **Info.plist** の **SUPublicEDKey** が `REPLACE_WITH_PUBLIC_KEY` のままの場合、本番では更新が動きません。

1. **Xcode** でプロジェクトを開く
2. 左ナビゲータで **Package Dependencies** を開き、**Sparkle** を右クリック → **Show Package in Finder**
3. Finder で **Sparkle** パッケージ内の **Sparkle/bin/** に移動する  
   （パス例: `…/SourcePackages/checkouts/Sparkle/Sparkle/bin/` または `…/artifacts/sparkle/Sparkle/bin/`）
4. **ターミナル**でその `bin` フォルダに移動し、次を実行：
   ```bash
   ./generate_keys
   ```
5. 表示された **公開鍵（base64 の長い文字列）** をコピーする
6. プロジェクトの **Info.plist** を開き、**SUPublicEDKey** の値を、コピーした公開鍵に**置き換えて保存**

秘密鍵は Mac のキーチェーンに保存されます。**紛失すると同じ鍵で署名した更新を出せなくなる**ので、必要なら Sparkle のドキュメントにある `-x` オプションでエクスポート・バックアップを検討してください。

---

## 2. ビルドして動作確認

1. **Xcode** で **Product → Build**（⌘B）でビルド
2. 起動し、**設定 → アプリバージョン** の **「更新を確認」** を押す
3. **SUPublicEDKey** をまだ入れていない場合: 「更新を確認できません」などのエラーになることがあります → 上記の公開鍵設定を完了させる
4. **SUFeedURL** の先にまだ Appcast を置いていない場合: 「最新です」または「更新が見つかりません」と出れば、Sparkle の通信までは動いています

実際に「更新あり」と表示するには、**Appcast の配置**と**リリース手順**が必要です。手順は [SPARKLE_SETUP.md](SPARKLE_SETUP.md) にまとめてあります。

---

## 変更内容のまとめ

| 内容 | 場所 |
|------|------|
| Sparkle を Swift Package で追加 | `project.pbxproj` |
| 更新チェック用の URL と鍵のキーを追加 | **Info.plist**（SUFeedURL, SUPublicEDKey） |
| 起動時に Sparkle を開始 | **App/AppDelegate.swift**（`updaterController` / `startUpdater()`） |
| 設定の「更新を確認」を Sparkle に変更 | **Views/SettingsView.swift** |
| 旧「更新を確認」用コードを削除 | **App/UpdateChecker.swift**, **Models/VersionInfo.swift** を削除 |
| バージョン表示用の Bundle 拡張を残す | **App/Bundle+AppInfo.swift** を新規作成 |
| リリース・Appcast 手順 | **docs/SPARKLE_SETUP.md** を新規作成、**docs/GITHUB_RELEASES.md** を更新 |

---

## トラブル時

- **ビルドで「XCFramework が見つからない」**  
  → Xcode で **File → Packages → Reset Package Caches** のあと、もう一度 **Build** してみてください。
- **「更新を確認」でエラー**  
  → Info.plist の **SUFeedURL** が HTTPS で開ける URL か、**SUPublicEDKey** を正しく入れているか確認してください。
- **Appcast の作り方・置き場所**  
  → [SPARKLE_SETUP.md](SPARKLE_SETUP.md) の「リリース手順」「Appcast をホストする」を参照してください。

ここまでできれば、Sparkle による自動更新の導入は完了です。
