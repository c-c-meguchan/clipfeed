# GitHub Releases で ClipFeed を配布する

## 構造

```
GitHub リポジトリ
 ├ Source code（main ブランチなど）
 └ Releases
      ├ v1.0.0  ← ここに ClipFeed.dmg を添付
      ├ v1.0.1
      └ v1.1.0
```

- **Releases** = バージョンごとの「配布パッケージ」を置く場所
- 各リリースに **ClipFeed.dmg** を添付すると、ユーザーはその URL からダウンロードできる
- アプリ内「アップデートを確認」は、GitHub の「最新リリース」と現在のバージョンを比較し、新しい場合はそのリリースの .dmg を開く

## メリット

| やりたいこと     | やり方 |
|------------------|--------|
| ユーザー配布     | リリースページの URL を共有するか、.dmg を直接ダウンロードさせる |
| アップデート管理 | アプリが「最新リリース」を取得し、バージョン比較 → 新しければ「ダウンロード」で .dmg を開く |
| 履歴管理         | 過去のリリース（v1.0.0, v1.0.1...）が一覧で残る |

---

## リリースの作り方（手順）

### 1. .dmg を用意する

- Xcode で **Product → Archive** からアーカイブを作成
- **Distribute App** で **Copy App** を選び、.app を保存
- 必要なら **ディスクユーティリティ** などで .app を .dmg にまとめる  
  （または「Developer ID」で公証して .dmg を配布）

### 2. GitHub でリリースを作成

1. リポジトリの **Releases** を開く（右サイドの "Releases" → "Create a new release"）
2. **Choose a tag**: 新規なら "v1.0.0" のように入力して "Create new tag"
3. **Release title**: 例）`v1.0.0` または `ClipFeed 1.0.0`
4. **Describe**: 変更内容（リリースノート）。アプリの「アップデートがあります」で表示される
5. **Attach binaries**: **ClipFeed.dmg** をドラッグ＆ドロップ
6. **Publish release** をクリック

### 3. 以降のバージョン（v1.0.1, v1.1.0 など）

- 同じ手順で新しいタグ（例: v1.0.1）でリリースを作成
- そのリリースに新しい ClipFeed.dmg を添付

---

## アプリ側の「アップデート確認」について

このリポジトリでは、**GitHub の「最新リリース」API** を使ってバージョン比較とダウンロード URL を取得するようにしてあります。

- **確認先**: `https://api.github.com/repos/<owner>/<repo>/releases/latest`
- **比較**: リリースの `tag_name`（例: v1.0.0）とアプリの `CFBundleShortVersionString` を比較
- **ダウンロード**: そのリリースに添付した **.dmg の URL** をブラウザで開く

`UpdateChecker.swift` 内の `githubRepository`（owner/repo）を、自分のリポジトリ名に合わせて変更してください。
