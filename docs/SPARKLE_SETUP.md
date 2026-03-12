# Sparkle による自動更新の導入・運用

ClipFeed は [Sparkle](https://sparkle-project.org/) でアプリ内から更新チェック・ダウンロード・インストールまで行います。

---

## 初回のみ：EdDSA 鍵の生成と Info.plist の設定

### 1. 公開鍵を生成する

1. Xcode でプロジェクトを開く
2. 左ナビゲータで **Package Dependencies** を開く
3. **Sparkle** を右クリック → **Show Package in Finder**
4. Finder で `Sparkle/` の**親**フォルダに移動し、  
   `artifacts/sparkle/Sparkle/bin/` を開く（または SPM の checkouts の場合は `checkouts/Sparkle/` 内の `Sparkle/bin/` を探す）
5. ターミナルでその `bin` フォルダに移動し、次を実行：

   ```bash
   ./generate_keys
   ```

6. **表示された公開鍵（base64 の長い文字列）をコピー**する。秘密鍵は Mac のキーチェーンに保存される（再表示はできないので、バックアップが必要な場合は `-x` オプションでエクスポートを検討）

### 2. Info.plist に反映する

1. プロジェクトの **Info.plist** を開く
2. **SUPublicEDKey** の値が `REPLACE_WITH_PUBLIC_KEY` のままなら、**コピーした公開鍵**に差し替える
3. **SUFeedURL** は Appcast を置く URL。例：
   - GitHub Pages を使う場合: `https://<username>.github.io/clipfeed/appcast.xml`
   - リポジトリの `gh-pages` ブランチで Raw を参照する場合:  
     `https://raw.githubusercontent.com/c-c-meguchan/clipfeed/gh-pages/appcast.xml`
4. 保存してビルド

これでアプリは Sparkle で更新チェックできる状態になります。**実際に更新が動くには、次節の「リリース手順」で Appcast を生成・配置する必要があります。**

---

## リリース手順（新バージョンごと）

### 1. バージョン番号を上げる

- Xcode: **TARGETS → ClipFeed → General** の **Version**（例: `1.0.2`）と **Build**（`CURRENT_PROJECT_VERSION`、整数）を更新する  
- Sparkle は **CFBundleVersion**（Build）が増えているかで「新しい版」かどうかを判断するため、**毎リリースで Build を 1 以上増やす**必要があります。

### 2. Archive と DMG を作成

- **Product → Archive** でアーカイブを作成
- **Distribute App** で **Developer ID** を選び、公証済みの .app を出力
- 必要に応じて **ディスクユーティリティ** などで .app を **DMG** にまとめる（Sparkle は .dmg / .zip などに対応）

### 3. Appcast を生成する

1. **Sparkle の `generate_appcast`** を使う。場所は上記「鍵の生成」と同じく、Sparkle パッケージ内の `bin/`（例: `artifacts/sparkle/Sparkle/bin/` または `checkouts/Sparkle/Sparkle/bin/`）
2. **更新用アーカイブ（.dmg や .zip）を 1 つ入れたフォルダ**を用意する。例：

   ```
   ~/clipfeed-releases/
     ClipFeed-1.0.2.dmg
   ```

3. ターミナルでそのフォルダの**親**に移動し、次を実行（パスは環境に合わせて変更）：

   ```bash
   /path/to/Sparkle/bin/generate_appcast ~/clipfeed-releases
   ```

4. キーチェーンアクセスを求められたら、**generate_keys で使った秘密鍵が入っている Mac のログインキーチェーン**を許可する
5. 同じフォルダに **appcast.xml**（と、オプションで delta 用ファイル）が生成される

### 4. Appcast をホストする

- **SUFeedURL** で指定した URL から **appcast.xml** が HTTPS で取得できるようにする。
- **GitHub Pages** を使う場合の例：
  1. リポジトリで `gh-pages` ブランチを作成
  2. そのブランチのルートに **appcast.xml** を置く（手動コミットまたは CI でアップロード）
  3. **SUFeedURL** を `https://c-c-meguchan.github.io/clipfeed/appcast.xml` のように設定

- **Raw で配信する場合**  
  `https://raw.githubusercontent.com/c-c-meguchan/clipfeed/gh-pages/appcast.xml` のように、`appcast.xml` を置いたブランチ・パスを指定する。

### 5. GitHub Release（任意）

- 配布用に **GitHub Releases** も使う場合は、同じバージョンのタグ（例: `v1.0.2`）でリリースを作成し、**同じ DMG** を添付する。
- ユーザーが「更新を確認」したときは **Sparkle が Appcast の URL から DMG を取得**するため、GitHub Release の URL と Appcast 内の URL が一致している必要はありません（Appcast 内のリンクが指す場所に DMG を置けばよい）。

---

## 動作確認のヒント

- **「更新を確認」が有効にならない**  
  - Info.plist の **SUFeedURL** が正しいか、**SUPublicEDKey** を正しく設定したか確認
  - Appcast が実際にその URL で読めるか、ブラウザや `curl` で確認
- **更新が「見つからない」**  
  - Appcast 内の `<enclosure>` の **version** や **sparkle:version** が、アプリの **CFBundleVersion** より大きいか確認
  - `generate_appcast` を実行した DMG のバージョンが、現在動かしているアプリより新しいか確認
- **署名エラー**  
  - 同じ EdDSA 鍵ペアで `generate_keys`（公開鍵）と `generate_appcast`（秘密鍵）が使われているか確認
  - 開発時は「最後に更新チェックした時刻」をリセットして再試行:  
    `defaults delete jp.c-c-meguchan.clipfeed SULastCheckTime`

---

## 参考

- [Sparkle 公式ドキュメント](https://sparkle-project.org/documentation/)
- [Publishing an update](https://sparkle-project.org/documentation/publishing/)
