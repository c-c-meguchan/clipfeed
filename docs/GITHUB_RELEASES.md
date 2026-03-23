# GitHub Releases で ClipFeed を配布する

## 構造

```
GitHub リポジトリ (c-c-meguchan/clipfeed)
 ├ main ブランチ（ソースコード）
 ├ gh-pages ブランチ（appcast.xml）
 └ Releases
      ├ v1.0.2  ← ClipFeed-1.0.2.dmg を添付
      └ v1.0.3
```

- 各リリースに **ClipFeed-x.x.x.dmg**（Notarize 済み）を添付する
- リリースを publish すると GitHub Actions が自動で **appcast.xml** を更新する
- Sparkle がアプリ内から appcast.xml を参照し、自動アップデートを提供する

---

## リリース手順

### 1. バージョン番号を更新する

Xcode でプロジェクトを開き、**TARGETS → ClipboardHistory → General**：
- **Version**（MARKETING_VERSION）: 例 `1.0.4`
- **Build**（CURRENT_PROJECT_VERSION）: 例 `4`

変更をコミット・タグを打つ：

```bash
git add ClipboardHistory.xcodeproj/project.pbxproj
git commit -m "Bump version to 1.0.4"
git tag v1.0.4
git push origin main
git push origin v1.0.4
```

### 2. Archive してアプリを Notarize する

1. Xcode → **Product → Archive**
2. Organizer が開いたら **Distribute App**
3. **Direct Distribution** を選択 → **Distribute**
4. 保存先を `ReleaseArtifacts/ClipFeed-x.x.x/` に指定してエクスポート

> Xcode が自動で Apple の Notary Service に提出し、承認後に Notarize 済みの `.app` が保存される。

### 3. DMG を作成して staple する

```bash
# DMG 作成
hdiutil create -volname "ClipFeed" -srcfolder "ReleaseArtifacts/ClipFeed-1.0.4/ClipFeed.app" -ov -format UDZO "ReleaseArtifacts/ClipFeed-1.0.4/ClipFeed-1.0.4.dmg"

# DMG を notarize に提出
xcrun notarytool submit "ReleaseArtifacts/ClipFeed-1.0.4/ClipFeed-1.0.4.dmg" \
  --apple-id "your@email.com" \
  --team-id "49DPFSUDS9" \
  --password "xxxx-xxxx-xxxx-xxxx" \
  --wait

# チケットを staple
xcrun stapler staple "ReleaseArtifacts/ClipFeed-1.0.4/ClipFeed-1.0.4.dmg"

# 署名確認
spctl -a -vvv "ReleaseArtifacts/ClipFeed-1.0.4/ClipFeed.app"
# → "accepted" "source=Notarized Developer ID" が出れば OK
```

### 4. GitHub Release を作成する

```bash
gh release create v1.0.4 \
  "ReleaseArtifacts/ClipFeed-1.0.4/ClipFeed-1.0.4.dmg" \
  --title "v1.0.4" \
  --notes "変更内容をここに書く"
```

Release が publish されると GitHub Actions（`update-appcast.yml`）が自動で起動し、`gh-pages` ブランチの `appcast.xml` を更新する。

---

## appcast.xml の自動更新について

`.github/workflows/update-appcast.yml` が以下を自動で行う：

1. Sparkle の `generate_appcast` ツールをダウンロード
2. リリースに添付された DMG をダウンロード
3. `appcast.xml` を生成して `gh-pages` ブランチに push

**手動で再実行したい場合**（失敗時など）：

GitHub → Actions → **Update Sparkle appcast** → **Run workflow** → tag に `v1.0.4` を入力

---

## アップデートの仕組み

- Sparkle が `Info.plist` の `SUFeedURL` を参照して appcast.xml をチェック
- appcast.xml に新バージョンがあればユーザーに通知・ダウンロード

---

## バージョン間の差分を確認する

```bash
git log --oneline v1.0.3..v1.0.4
git diff --stat v1.0.3..v1.0.4
```
