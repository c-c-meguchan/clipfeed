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
- アプリ内「更新を確認」は **Sparkle** により、**Appcast** を参照して更新の有無を判定し、あればダウンロード・インストールまで行う（詳細は [Sparkle 導入・運用](SPARKLE_SETUP.md) を参照）

## メリット

| やりたいこと     | やり方 |
|------------------|--------|
| ユーザー配布     | リリースページの URL を共有するか、.dmg を直接ダウンロードさせる |
| アップデート管理 | Sparkle が Appcast を参照し、新バージョンがあればダウンロード・インストールを案内 |
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
git tag v1.0.2

# 過去のコミットにタグを付けたい場合はハッシュを指定
git tag v1.0.0 536518f

# タグの一覧を確認
git tag -l

# タグをリモート（GitHub）に送る
git push origin v1.0.2

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

### 5. 以降のバージョン（v1.0.2, v1.1.0 など）—「いつもやること」のチェックリスト

1. **Xcode で Version / Build を上げる**  
2. **Archive → Copy App** で .app を取り出し、.dmg を 1つ作る  
3. 作った .dmg を、バージョンごとのフォルダ（例: `ReleaseArtifacts/1.0.2/`）に置く  
4. Sparkle の `generate_appcast` で、そのフォルダに対して **`appcast.xml` を生成**する  
5. 生成された `appcast.xml` をプロジェクトルートに移動し、`gh-pages` ブランチに commit & push（`SUFeedURL` から参照される）  
6. 同じ .dmg を **GitHub Releases の vX.Y.Z リリースに添付して Publish** する  

Appcast の生成コマンドや `gh-pages` ブランチ運用の詳細は [SPARKLE_SETUP.md](SPARKLE_SETUP.md) を参照。

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

## アプリ側の「更新を確認」について

このリポジトリでは **Sparkle** を使って更新チェック・ダウンロード・インストールを行います。

- **確認先**: アプリの **Info.plist** の **SUFeedURL** で指定した Appcast（RSS 形式の XML）の URL
- **比較**: Appcast 内のバージョンとアプリの **CFBundleVersion** / **CFBundleShortVersionString** を比較
- **インストール**: 新しい版の .dmg（または .zip 等）を Sparkle がダウンロードし、ユーザーが「インストール」を選ぶとアプリを置き換える

初回セットアップ（EdDSA 鍵の生成・SUFeedURL の設定）とリリース時の Appcast 生成手順は [SPARKLE_SETUP.md](SPARKLE_SETUP.md) を参照してください。

---

## （一時）アーカイブ済みリポジトリにリリースを追加する場合（1.0.2 への橋渡し用）

旧体制で直接 .dmg を渡したユーザーを、一度だけ「アップデート確認」で新体制ビルド（Sparkle 対応版）へ誘導したいとき、**clipfeed-site** がアーカイブ済みだと新規リリースは追加できない。その場合は一時的に Unarchive してから作業する。

1. **Unarchive**
   - GitHub で `clipfeed-site` を開く
   - 上部の「This repository has been archived」バナーから **Unarchive** をクリック

2. **リリースを作成**
   - **Releases** → **Draft a new release**
   - Tag: 旧ビルドより新しいバージョン（例: `v1.0.1`）
   - Title / Describe: 任意（例: `ClipFeed 1.0.1 (migration release)`）
   - **Attach binaries**: 本体リポジトリでビルドした**新体制の** ClipFeed.dmg を添付（Sparkle の Appcast を向いているビルド）
   - **Publish release**

3. **再アーカイブ**
   - **Settings** → **Danger Zone** → **Archive this repository** で再度アーカイブする

この手順は **旧版 → 1.0.2 への橋渡しのときだけ必要**。作業が完了したら、このセクションは削除してよい。
