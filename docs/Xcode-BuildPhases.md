# Xcode で Build Phases を開く方法

## 1. タブで探す（一般的な Xcode）

1. 左の **プロジェクトナビゲータ** で、一番上の **青いプロジェクトアイコン**「ClipboardHistory」をクリック
2. 中央上部の **TARGETS** 一覧で **「ClipboardHistory」**（アプリのターゲット）をクリック
3. その右のエリアの**上端**に、次のようなタブが並んでいることがあります：
   - **General**
   - **Signing & Capabilities**
   - **Resource Tags**
   - **Info**
   - **Build Settings**
   - **Build Phases**  ← ここをクリック
   - **Build Rules**

※ 表示されているタブが少ない場合は、**横スクロール**できることがあります。右端までスクロールして「Build Phases」を探してください。

---

## 2. 左の一覧で探す（レイアウトによっては）

ターゲットを選択したとき、**中央エリアの左端**に「General」「Signing & Capabilities」「Build Settings」「**Build Phases**」などの**縦一覧**が出ている場合があります。  
その一覧の **「Build Phases」** をクリックすると、Copy Bundle Resources などが表示されます。

---

## 3. メニューから開く（Xcode のバージョンによる）

- **Editor** メニューに **「Build Phases」** や **「Build Settings」** がないか確認
- またはターゲット名の上で **右クリック** し、一覧に **Build Phases** がないか確認

---

## 4. どうしても見つからない場合

プロジェクトの設定は `ClipboardHistory.xcodeproj/project.pbxproj` に書かれています。  
Localizable.strings はすでに **Resources** に含まれているので、ビルドは通っているはずです。  
Build Phases は「リソースがバンドルにコピーされているか」を**確認するため**のもので、必須の操作ではありません。

---

## 「Localization ?」のクエスチョンマークについて

ナビゲータで **Localization** の横に **?** が出ている場合、Xcode が「そのパスにファイルが見つからない」と判断している状態です。

### 対処手順（参照の作り直し）

1. 左のナビゲータで **「Localization」（? 付き）** を右クリック
2. **「Delete」** を選ぶ → **「Remove Reference」** を選ぶ（ファイル自体は削除しない）
3. **App** フォルダを右クリック → **「Add Files to "ClipboardHistory"...」**
4. 開いたダイアログで **`App/Localization.swift`** を選ぶ
5. 次のように設定して **Add**：
   - **Copy items if needed**: オフでOK（すでにプロジェクト内にあるため）
   - **Add to targets**: **ClipboardHistory** にチェックを入れる
6. ナビゲータで **Localization.swift** の ? が消えているか確認

これで参照が正しくなり、ビルド時に Localization.swift が確実にコンパイルされます。

**補足:** プロジェクト（project.pbxproj）で Localization.swift の参照を **App グループの直下**に置き、path を `Localization.swift`（App からの相対）にしている場合も ? が解消することがあります。ナビゲータでは **App** を展開すると **Localization.swift** が表示されます。

---

## Project の Location（プロジェクトのパス）を確認する

**いま開いている「Info」タブには Location はありません。** Info は Configurations と Localizations の設定用です。

**Location を確認する手順：**

1. 左の **プロジェクトナビゲータ**（フォルダ一覧）で、**一番上の青いアイコン「ClipboardHistory」**（プロジェクト名）を **1回クリック** して選択する。
2. Xcode の**右側**に **インスペクタ（Utilities）** が出ているか確認する。  
   出ていない場合：メニュー **View → Inspectors → File**（または **View → Inspectors → Show File Inspector**）、または **⌥⌘1** で開く。
3. **File Inspector** の一番上あたりに **「Location」** という行がある。  
   - **Relative to Group** や **Relative to Project** などと表示され、その横に **「ClipboardHistory.xcodeproj」** を含むパス（例: `Desktop/.../Clipboard History`）が出る。
4. そのパスのフォルダを開くと、その中に **App** フォルダと **ClipboardHistory.xcodeproj** がある状態が正しい。

※ 右側のインスペクタが閉じていると Location は見えません。**View → Inspectors → File** で右パネルを出してください。
