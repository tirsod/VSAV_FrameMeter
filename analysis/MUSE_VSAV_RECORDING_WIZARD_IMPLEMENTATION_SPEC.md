# Muse Code向け実装指示書

## VSAV Recording Wizard

作成日: 2026-08-24  
対象: `VSAV_Training-fc2_v11.3.1`  
実行主体: Muse Code / Muse Spark 1.2  
目的: 既存のMacroLua録画・再生・Savestate・操作対象切替を活用し、追加ボタンなしで録画から保存確認までを完結するRecording Wizardを実装する。

---

# 1. 最初に実行する指示

Muse Codeでは、最初にこの設計書を読み、次の順に実行すること。

```text
/plan
↓
/grill
↓
承認済み範囲内で実装
↓
全テスト
↓
批判的レビュー
↓
問題修正
↓
全テストを最初から再実行
```

一度に完成版へ飛ばず、後述のStage A～Cを独立パッチとして実装すること。

---

# 2. 目的

現在の録画操作はVolume Upキー等に依存している。新しいRecording Wizardでは、専用ボタンを追加せず、通常メニューから録画を開始し、次の一連の操作を自動化する。

```text
録画スロット選択
↓
録画開始状態を一時Savestateへ保存
↓
通常メニューを一時的に非表示
↓
操作対象をP2へ切替
↓
最初のゲーム入力を待機
↓
最初の入力から録画
↓
120フレーム連続未操作で自動完了
↓
先頭・末尾の未操作部分を除外
↓
開始Savestateをロード
↓
録画内容を1回だけ自動再生
↓
保存確認（Yesをデフォルト選択）
↓
Yesなら正式スロットへ保存
Noなら破棄し、既存スロットを変更しない
↓
元の操作対象と通常メニューを復元
```

---

# 3. 完成条件

## 3.1 機能

- 通常メニューのRecordingページからWizardを起動できる。
- 新しいゲーム入力ボタンや新しいFBNeoホットキーを要求しない。
- Wizard起動中は通常メニューを描画せず、通常メニューへ入力を渡さない。
- 5つの既存録画スロットから保存先候補を選択できる。
- 正式スロットは保存確認でYesを選ぶまで変更しない。
- 録画開始状態を一時Savestateへ保存する。
- 操作対象をP2へ自動的に切り替える。
- 最初の有効なゲーム入力から録画を開始する。
- 録画開始前に10秒間入力がなければ自動キャンセルする。
- 録画開始後に120フレーム連続で有効入力がなければ自動完了する。
- 120フレームはハードコードし、設定項目を追加しない。
- 内部の未操作フレームは残す。
- 先頭・末尾の連続未操作だけを保存対象から除外する。
- タメ方向、ボタン保持、ボタン離しを欠落させない。
- 録画終了後、一時Savestateをロードして録画を1回だけプレビュー再生する。
- プレビュー完了後に `SAVE THIS RECORDING?` を表示する。
- `Yes`を初期選択にする。
- Yesで`.mis`と対応Savestateを正式スロットへ保存する。
- Noで一時録画と一時Savestateを破棄する。
- Noを選んでも既存録画スロットを上書きしない。
- 保存、破棄、キャンセル、タイムアウト、エラーの全経路で、元の操作対象と通常メニューを復元する。

## 3.2 非機能

- 既存MacroLuaの録画・finalize・再生処理を可能な限り再利用する。
- 既存の`Use Savestate Upon Recording`のゲーム状態保存・復元方法を再利用する。
- 既存の`registerSave`／`registerLoad`処理へWizard固有状態を追加しない。
- Wizard状態はSavestateへ永続化せず、Savestate load前後に明示的に初期化する。
- 旧Volume Up／Volume Down操作は、初期段階では削除せず互換機能として残す。
- Run-ahead対応は行わない。
- 未確認のRAMアドレスや内部状態を推測しない。
- UIは現行VSAVメニューと同程度の文字中心表示にする。
- カード、アイコン、アニメーション、新しい画像フォントは追加しない。

---

# 4. UI仕様

## 4.1 通常メニュー

Recordingページへ次の1項目を追加する。

```text
Recording Wizard
```

LPでWizardを開く。

## 4.2 Wizard表示

Wizard起動中は通常メニューを非表示にし、画面上部中央へ通常より大きめの英語メッセージを表示する。

使用するメッセージ:

```text
SELECT RECORDING SLOT
START MOVING TO RECORD!
RECORDING...
RECORDING COMPLETE!
PLAYBACK CHECK
SAVE THIS RECORDING?
RECORDING SAVED
RECORDING DISCARDED
RECORDING CANCELLED
PLAYBACK FAILED
```

既存のFBNeo bitmap textと現行配色を使用する。

推奨色:

```text
通常文字       既存text_default_color
選択／案内     text_selected_color
録画中         赤または既存警告色
補足           text_disabled_color
```

## 4.3 スロット選択

```text
SELECT RECORDING SLOT

< Slot 1 : Empty >
  Slot 2 : 76F
  Slot 3 : 48F
  Slot 4 : Empty
  Slot 5 : 91F

LP: Continue   MP: Cancel
```

既存スロットの場合も、この時点では上書きしない。

## 4.4 入力待機

```text
START MOVING TO RECORD!

Slot : 1
Start state : Saved
Control : P2
Recording starts with first input.
No input for 10 sec : Cancel
```

## 4.5 録画中

```text
RECORDING...

Slot : 1
Raw frames : 84
Neutral : 37 / 120
Auto-complete after 120 neutral frames.
```

## 4.6 録画完了とプレビュー

```text
RECORDING COMPLETE!
Loading recorded start state...
```

ロード後:

```text
PLAYBACK CHECK
Playing recorded action...
```

## 4.7 保存確認

```text
SAVE THIS RECORDING?

< Yes >
  No

LP: Confirm   Up/Down: Select
```

初期選択は必ずYes。

---

# 5. 状態機械

推奨状態:

```text
IDLE
SELECT_SLOT
CAPTURE_START_STATE
ARMED
RECORDING
FINALIZING
LOAD_PREVIEW_STATE
WAIT_PREVIEW_LOAD
PREVIEW_PLAYING
CONFIRM_SAVE
COMMITTING
DISCARDING
COMPLETED
CANCELLED
ERROR
```

## 5.1 遷移

```text
IDLE
  → SELECT_SLOT

SELECT_SLOT
  LP → CAPTURE_START_STATE
  MP → CANCELLED

CAPTURE_START_STATE
  success → ARMED
  failure → ERROR

ARMED
  first valid input → RECORDING
  600 frames with no valid input → CANCELLED
  MP/menu cancel → CANCELLED

RECORDING
  valid input → reset neutral counter
  neutral frame → increment neutral counter
  neutral counter >= 120 → FINALIZING
  cancel → CANCELLED

FINALIZING
  normalized recording valid → LOAD_PREVIEW_STATE
  empty/invalid → ERROR

LOAD_PREVIEW_STATE
  reset wizard playback-sensitive state
  load temporary savestate
  → WAIT_PREVIEW_LOAD

WAIT_PREVIEW_LOAD
  load complete and stable → PREVIEW_PLAYING
  timeout/failure → ERROR

PREVIEW_PLAYING
  playback complete → CONFIRM_SAVE
  playback failure → ERROR

CONFIRM_SAVE
  Yes → COMMITTING
  No → DISCARDING

COMMITTING
  commit success → COMPLETED
  commit failure → ERROR

DISCARDING
  remove temporary artifacts → COMPLETED

COMPLETED / CANCELLED / ERROR
  common cleanup → IDLE
```

---

# 6. 録画判定

## 6.1 有効入力

有効入力とは、録画対象プレイヤーに対する次のゲーム入力である。

```text
Up
Down
Left
Right
LP
MP
HP
LK
MK
HK
```

次は録画開始判定および録画データから除外する。

```text
Coin
Start
Volume Up
Volume Down
Lua Hotkeys
Menu navigation controls
Wizard controls
```

## 6.2 Neutral

上記録画対象入力がすべてOFFのフレームをNeutralとする。

## 6.3 自動停止

```lua
local RECORDING_AUTO_STOP_NEUTRAL_FRAMES = 120
local RECORDING_ARM_TIMEOUT_FRAMES = 600
```

- `ARMED`中の600F無入力はキャンセル。
- `RECORDING`中の120F連続Neutralは完了。
- 120Fは守備練習の戦略上必要な待機ではないため、設定化しない。

## 6.4 トリミング

- 最初の有効入力より前を除外。
- 最後の有効入力状態変化より後を除外。
- 録画途中のNeutralは維持。
- 方向保持は有効入力として維持。
- ボタン保持とreleaseがMacroLuaの`finalize()`で正しく完結するようにする。

---

# 7. Savestate設計

## 7.1 方針

座標だけを新しく保存するのではなく、既存のFBNeo Savestateを使用する。

保存タイミング:

```text
スロット選択完了
↓
MacroLuaをrecording状態にする前
↓
一時Savestateを保存
```

これにより位置、向き、カメラ、キャラクター状態などをまとめて復元する。

## 7.2 一時領域と正式領域

保存確認前:

```text
temporary_recording.mis
temporary_recording.fs
```

保存確認後:

```text
slot_1.mis
recording_slot_1.fs
```

キャラクター別スロットでは既存の安全なキャラクターキーをパスへ使用する。

## 7.3 既存スロット保護

正式スロットへ直接録画しない。

コミット手順:

```text
一時.misと一時Savestateの存在・検証
↓
既存正式ファイルを必要ならバックアップ
↓
一時ファイルを正式名へ原子的に置換
↓
両方成功後にバックアップ削除
```

片方だけ失敗した場合は既存スロットを復元する。

## 7.4 Savestate load後

Savestate load直後に録画再生を開始しない。

```text
load要求
↓
registerLoad完了
↓
最低1フレーム、または状態安定を確認
↓
プレビュー開始
```

Wizard固有状態はSavestateへ保存しない。load前後に必要な値をWizard側で再構築する。

---

# 8. 既存コードの再利用

調査して次を再利用すること。

```text
scripts/macro.lua
  reccontrol
  recinputstream
  recframe
  finalize
  playcontrol
  character-specific slot path
  registerSave/registerLoadとの既存整合

scripts/controller.lua
  Volume Up/Down録画・再生処理
  current_recording savestate処理
  Coin操作対象切替

scripts/menu.lua
  既存menu item factories
  show_menu
  draw/input ownership

scripts/position.lua
  位置に関する既存知識
  ただしWizardでは原則Savestateを優先
```

既存local関数を無理に直接参照するためグローバル化しない。必要最小限の公開APIをMacroLua moduleへ追加する。

推奨公開API:

```lua
macroLuaModule.begin_temporary_recording(options)
macroLuaModule.stop_temporary_recording()
macroLuaModule.finalize_temporary_recording()
macroLuaModule.begin_temporary_playback()
macroLuaModule.commit_temporary_recording(slot)
macroLuaModule.discard_temporary_recording()
macroLuaModule.get_recording_status()
```

操作対象切替はCoinを疑似入力せず、明示APIへする。

```lua
controllerModule.get_controlling_target()
controllerModule.set_controlling_target(target)
```

---

# 9. モジュール設計

新規モジュールを推奨する。

```text
scripts/recordingWizard.lua
```

責務:

- Wizard状態機械
- UI文字列
- メニュー描画抑止
- Wizard入力
- MacroLua API呼出し
- 操作対象保存・復元
- timeout
- 一時録画のcommit/discard
- 共通cleanup

責務外:

- Macro入力形式の再実装
- `.mis`serializerの再実装
- Savestate内部形式
- Character Specific入力
- Run-ahead
- RAMタイミング解析

---

# 10. エラーとCleanup

全終了経路は1つのcleanup関数を通す。

```lua
recordingWizard.cleanup(reason)
```

必須処理:

```text
MacroLua録画停止
MacroLua再生停止
一時入力解放
一時状態の破棄または保持判断
以前の操作対象を復元
通常メニュー表示を復元
Wizardの排他入力を解除
カウンター初期化
```

対象となる理由:

```text
saved
discarded
cancelled
arm_timeout
playback_failed
savestate_failed
script_exit
match_transition
character_transition
unexpected_error
```

---

# 11. 実装段階

## Stage A: Wizardと録画自動完了

変更:

- `recordingWizard.lua`追加
- menu項目追加
- 通常メニュー一時非表示
- 操作対象切替API
- 最初の入力から録画
- 120F Neutral完了
- 10秒未入力キャンセル
- 外側Neutral除去
- 一時`.mis`生成
- Cleanup

この段階ではプレビューと正式保存を行わない。デバッグ用一時録画まで。

## Stage B: Savestateとプレビュー

変更:

- 一時Savestate保存
- load後の安定待ち
- 一時録画の1回再生
- playback failure処理

## Stage C: 保存確認と正式コミット

変更:

- `SAVE THIS RECORDING?`
- Yes初期選択
- 原子的commit
- No破棄
- 既存スロット保護

各Stageを独立パッチにし、前Stage適用済みソースを基準にする。

---

# 12. 自動テスト

## 12.1 Lua 5.1

各Stageで全Luaに`luac -p`を実行する。

## 12.2 純粋状態機械

エミュレーターAPIをスタブ化し、次をテストする。

```text
slot selection
ARMEDで最初の入力まで録画しない
最初の入力でRECORDINGへ移行
入力でneutral counter reset
120 neutralでFINALIZING
119 neutralでは終了しない
600F無入力でCANCELLED
599Fではキャンセルしない
内部Neutral保持
外側Neutral削除
Yes初期選択
Noで既存スロット不変
全異常経路で操作対象とmenu復元
```

## 12.3 Savestateスタブ

```text
save成功
save失敗
load成功
load timeout
load後に即再生しない
load完了後だけ再生
Wizard状態がSavestateから復元されない
```

## 12.4 ファイル操作

```text
一時録画作成
Yesで正式保存
Noで一時削除
既存スロット上書き前の保護
mis成功／fs失敗時のrollback
fs成功／mis失敗時のrollback
```

## 12.5 回帰

```text
旧Volume Up録画が引き続き動く
旧Volume Down再生が引き続き動く
通常メニュー操作がWizard外で変わらない
Use Character Specific Slotsが維持される
Random/Loop playbackが壊れない
既存registerSave/registerLoadが壊れない
```

---

# 13. Fightcade受入項目

次は自動テストだけでPASSにしない。結果は`PENDING`として残す。

```text
Wizard表示が元メニューと同程度に読める
通常メニューがWizard中に見えない
P2操作切替が自然
最初の実入力から録画される
120F後に自動完了する
録画内ディレイとタメが維持される
Savestateで位置・向き・画面が戻る
プレビューが1回だけ再生される
P1はプレビュー中に守備操作できる
Yesで保存される
Noで既存録画が残る
キャラクター別スロットが衝突しない
ループ／ランダム再生が後から保存録画を利用できる
```

---

# 14. 批判的レビュー項目

各Stageの完了前に`/grill`で次を確認する。

```text
録画確認前に正式スロットを上書きしていないか
SavestateへWizardの途中状態を保存していないか
load後に録画状態へ巻き戻っていないか
キャンセル後もP2操作のまま残らないか
通常メニューが再表示されない経路がないか
120F末尾Neutralが保存されていないか
内部Neutralまで削除していないか
方向タメをNeutral扱いしていないか
ボタンreleaseを削除していないか
既存MacroLuaを複製実装していないか
Volumeキー互換を壊していないか
Fightcade未確認をPASSと表現していないか
```

問題を修正した場合、パッチ生成・実適用・完全比較・逆適用・Lua 5.1検査・テスト・批判的レビューを最初から再実行する。

---

# 15. Muse Codeへ渡すマスタープロンプト

```text
あなたはVSAV Training ModeのRecording Wizard実装担当です。
添付のMUSE_VSAV_RECORDING_WIZARD_IMPLEMENTATION_SPEC.mdを唯一の機能仕様として扱ってください。

最初に基準ソース、scripts/macro.lua、scripts/controller.lua、scripts/menu.lua、scripts/position.lua、既存テストと段階受入ルールを読んでください。

/planでStage Aの実装計画を作ってください。
/grillで、既存録画の破壊、正式スロットの早期上書き、SavestateによるWizard状態巻戻り、Cleanup漏れ、内部Neutralの誤削除、旧Volumeキー回帰を重点的に批判してください。

最初はStage Aだけを実装してください。Stage B/Cを先取りしないでください。

厳守事項:
- Run-ahead対応は行わない。
- 新しいゲームボタンや新しいFBNeoホットキーを追加しない。
- UIは既存VSAVメニュー相当の文字表示にする。
- 120 Neutral Framesと600 Armed Timeout Framesはハードコードする。
- 既存MacroLuaの録画、finalize、再生、ファイル形式を再利用する。
- 旧Volume Up/Down操作を削除しない。
- 未確認RAMアドレスを推測しない。
- Fightcadeでしか確認できない項目をPASSにしない。
- 全LuaをLua 5.1で構文検査する。
- 失敗系テストを実装する。
- パッチをクリーンコピーへ実適用し、期待状態と完全比較する。
- 逆適用して基準へ完全復元する。
- 問題修正後は全検証を最初から実行する。

Stage A成果物:
- 差分パッチ
- 変更後ソース
- unit/stub tests
- Lua 5.1結果
- apply/reverse結果
- TEST_PLAN.md
- TEST_RESULT.md
- CRITICAL_REVIEW.md
- Fightcade PENDING一覧

Stage AのGateを満たしたら停止し、Stage Bへ進まず結果を報告してください。
```

---

# 16. Stage AのGate

Museは次がすべてPASSした場合のみStage Aを完成扱いする。

```text
[PASS] パッチcheck
[PASS] 実適用
[PASS] 対象外差分なし
[PASS] Lua 5.1全構文
[PASS] Wizard純粋状態機械テスト
[PASS] 120F/600F境界値テスト
[PASS] Neutral trimmingテスト
[PASS] Cleanup全経路テスト
[PASS] 旧Volumeキー静的回帰
[PASS] 逆適用
[PASS] 基準への完全復元
[PASS] 批判的レビュー
[PENDING] Fightcade受入
```

以上。
