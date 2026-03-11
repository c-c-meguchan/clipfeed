# GitHub Releases で ClipFeed を配布する

## 構造

このリポジトリ（ClipFeed 本体）で GitHub Releases を管理します。

```
GitHub リポジトリ (c-c-meguchan/clipfeed)
 ├ Source code（main ブランチなど）
 └ Releases
      ├ v1.0.0  ← ここに ClipFeed.dmg を添付
      ├ v1.0.1
      └ v1.1.0
```

- **Releases** = バージョンごとの「配布パッケージ」を置く場所
- 各リリースに **ClipFeed.dmg** を添付すると、ユーザーはその URL からダウンロードできる
- アプリ内「アップデートを確認」は、この本体リポジトリの「最新リリース」と現在のバージョンを比較し、新しい場合はそのリリースの .dmg を開く

## メリット

| やりたいこと     | やり方 |
|------------------|--------|
| ユーザー配布     | リリースページの URL を共有するか、.dmg を直接ダウンロードさせる |
| アップデート管理 | アプリが「最新リリース」を取得し、バージョン比較 → 新しければ「ダウンロード」で .dmg を開く |
| 履歴管理         | 過去のリリース（v1.0.0, v1.0.1...）が一覧で残る |

---

## リリースの作り方（手順）

### 1. Xcode でバージョン番号を更新する

1. Xcode でプロジェクトを開く
2. 左のナビゲータで **プロジェクト名（ClipboardHistory）** を選択
3. **TARGETS → ClipFeed** を選択
4. **General** タブを開く
5. **Identity** セクションの **Version** を新しいバージョン（例: `1.0.1`）に変更する

### 2. .dmg を用意する

- Xcode で **Product → Archive** からアーカイブを作成
- **Distribute App** で **Copy App** を選び、.app を保存
- 必要なら **ディスクユーティリティ** などで .app を .dmg にまとめる  
  （または「Developer ID」で公証して .dmg を配布）

### 3. Git タグを打つ（ローカル）

ターミナル（Cursor のターミナルでも可）でプロジェクトのディレクトリに移動して実行：

```bash
# 現在の最新コミットにタグを付ける
git tag v1.0.1

# 過去のコミットにタグを付けたい場合はハッシュを指定
git tag v1.0.0 536518f

# タグの一覧を確認
git tag -l

# タグをリモート（GitHub）に送る
git push origin v1.0.1

# 全タグをまとめて送る場合
git push origin --tags
```

**ポイント**:
- タグは「このコミットがこのバージョンです」という目印
- あとから `git diff v1.0.0..v1.0.1` で差分を確認できるようになる
- Cursor のターミナル（画面下部の `Terminal` パネル）から実行できる

### 4. GitHub でリリースを作成

1. リポジトリの **Releases** を開く（右サイドの "Releases" → "Create a new release"）
2. **Choose a tag**: 先ほど push したタグ（例: `v1.0.1`）を選択
3. **Release title**: 例）`v1.0.1` または `ClipFeed 1.0.1`
4. **Describe**: 変更内容（リリースノート）
5. **Attach binaries**: **ClipFeed.dmg** をドラッグ＆ドロップ
6. **Publish release** をクリック

### 5. 以降のバージョン（v1.0.2, v1.1.0 など）

同じ手順（バージョン更新 → Archive → タグ → push → GitHub Release）を繰り返す

---

## バージョン間の差分を確認する

```bash
# v1.0.0 から v1.0.1 の間の変更コミット一覧
git log --oneline v1.0.0..v1.0.1

# v1.0.0 から v1.0.1 の間のファイル変更統計
git diff --stat v1.0.0..v1.0.1

# v1.0.0 から v1.0.1 の間の詳細な差分
git diff v1.0.0..v1.0.1
```

---

## アプリ側の「アップデート確認」について

このリポジトリでは、**GitHub の「最新リリース」API** を使ってバージョン比較とダウンロード URL を取得するようにしてあります。

- **確認先**: `https://api.github.com/repos/<owner>/<repo>/releases/latest`
- **比較**: リリースの `tag_name`（例: v1.0.0）とアプリの `CFBundleShortVersionString` を比較
- **ダウンロード**: そのリリースに添付した **.dmg の URL** をブラウザで開く

`App/UpdateChecker.swift` 内の `githubRepository`（owner/repo）を、自分のリポジトリ名（例: `c-c-meguchan/clipfeed`）に合わせて変更してください。
