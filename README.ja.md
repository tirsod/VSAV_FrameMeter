# VSAV_Training - The Warlord's Secret

See what the Warlord sees, and practice what the Warlord practices, in VSAV training mode for Fightcade 2.

[English](README.md) | 日本語

**内部フレーム（Tick）単位の制御で相手の動きを正確に再現し、GC・AG・空中ガードからの割り込みを練習する、Fightcade 2／FBNeo用トレーニングモードです。**

入力や攻防のタイミングを細かく可視化することで、失敗したときも改善点を見つけ、上達の指標にできます。

[フォーク元のVSAV_Training（fc2）](https://github.com/NBeing/VSAV_Training/tree/fc2)を基に、ダミーの制御と練習表示を拡張したv11シリーズです。このREADMEは **v11.7.17** の機能を説明しています。

**[日本語プレイヤーマニュアル](docs/PLAYER_MANUAL.ja.md)** · [日本語リリースノート](RELEASE_NOTES.ja.md) · [Release notes (English)](RELEASE_NOTES.md)

## 本フォークの特徴

### 内部フレーム単位で、相手の動きを再現する

ヴァンパイア セイヴァーのTickは、ゲームの内部フレームです。

| ゲーム速度 | 表示フレームと内部フレームの関係 |
|---|---|
| ノーマル | 表示1フレーム＝1 Tick |
| ターボ3 | 表示3フレーム＝4 Tick |

本フォークはこの内部フレームに合わせて入力を制御し、フォーク元で制約のあった反撃タイミングの再現を改良しています。起き上がり・ガード後・着地後に、必殺技のリバーサルだけでなく、**小技や投げによる暴れ、ジャンプ、ダッシュ**も行わせられます。

自分の連係が最速暴れに勝つか、起き攻めから逃げられるか、着地後にどちらが先に動けるか。相手の行動を指定して、実際の攻防で確かめるための土台です。

### Action Stepsで、複雑な連係やコンボを組み立てる

**Action Steps**では「いつ、何をするか」を一つずつ並べ、内部フレーム単位の動作を定義できます。通常技・必殺技・投げ・ジャンプ・ダッシュを組み合わせ、単発の反撃から複雑な連係まで再現できます。バレッタやビシャモンの永久コンボを完遂するような定義も可能です。

**Action Patterns**では、作成した動きを名前付きで保存し、複数候補からのランダム実行やファイルでの共有ができます。

着地後の行動では、待ち方も選べます。

- **After**：行動可能になってからコマンド入力を開始します。先行入力を行わないため、ダッシュはコマンド完成まで遅れます。
- **Landing**：着地に入力完成を合わせるよう、必要なコマンドを着地前から先行入力できます。

着地予測が得られない場合など、Landingでも常に最速になるとは限りません。具体的な設定と条件は[Action Stepsの説明](docs/PLAYER_MANUAL.ja.md#06-steps)を参照してください。

### 再現した攻めに対し、守りを練習する

| 練習 | 可視化すること |
|---|---|
| **AG（アドバンシングガード）** | 受付内でなるべく遅らせ、6回の有効入力を収められたか。入力タイミング、同時押し、受付終了後の入力も確認。PB Statsで平均と成功率も確認 |
| **GC（ガードキャンセル）** | ゲームが受け付けた方向とボタン、その間隔、コマンドや受付の失効、ガードポーズ持続中の接触 |
| **空中ガードからの割り込み** | 連続ガードに見える空中チェーンの隙間、実際に押したタイミング、反撃が当たるまでの時間 |
| **空中ガード後の着地** | ジャンプ攻撃・空中ダッシュ攻撃をいつ空中ガードしたか、着地後にどちらが何Tick先に動けるか |

AGカウンターは、**AG成立後の入力も含めて数えます**。途中で成立しても手を止めず、毎回6回を入力し切る練習のための仕様です。成立後の入力と、受付終了後の入力を示す`LateMash`は区別します。

英語UIではAGを **Push Block／PB** と表記しています。

### 技の性能を内部フレームで測る

従来のFrame Dataは表示フレーム単位の測定だったため、ターボ時には測定値が安定しませんでした。本フォークの**Tick Data**は内部フレーム単位で測定し、ターボフレームによる数値の揺れを抑えています。さらに、**発生・持続・戻り・有利不利の数え方・考え方を攻略サイトのフレームデータに合わせています**。個々の掲載値との一致を保証するものではなく、比較時には技の条件や数え方も確認してください。

**Tick DataのAction History**では一連の行動履歴を表示し、単発技だけでなく、セットプレイ全体に何Tickかかるかも調べられます。技ごとの性能と一連の流れの所要時間を、内部フレーム単位で確認できます。

たとえば、**起き攻めで何Tick消費すれば狙ったタイミングに攻撃を重ねられるか**、**15表示フレーム（ターボ3では20 Tick）以内に歩き投げを仕掛けるには、どの距離から開始できるか**といった、実戦的な連係を検証できます。Action Historyで所要時間を確認し、開始距離を変えて実際の結果と照らし合わせます。

### 測定と反復練習を支援する

- **Tick Data／Action Timeline**：技の発生・持続・硬直・有利不利と、行動の流れを内部フレームで確認。
- **Recording Wizard（本フォークで追加）**：操作開始から操作終了までを簡単に録画するための機能。最初の入力で録画を開始し、操作を終えると自動で終了。確認再生してから保存できます。
- **録画のループ・ランダム再生**：複数の攻めを繰り返し練習。対応する録画では、周回ごとに録画時の間合いへ復帰。
- **位置ショートカット**：中央・画面端・左右の配置を素早く戻して反復。

録画・再生は表示フレーム単位であり、Tick単位の入力タイミングを正確に再現するものではありません。特にターボ時の細かなタイミングを指定する練習には、Action Stepsを使ってください。

フォーク元にも録画、反撃設定、AGカウンター、GC受付表示などがあります。本フォークでは、それらを土台に**動作再現の精度と、入力・攻防を振り返る情報の詳しさ**を拡張しています。詳しい比較は[マニュアル冒頭](docs/PLAYER_MANUAL.ja.md)を参照してください。

## 導入前に：Run-aheadは必ずOFF

**Run-aheadがONのままでは、トレーニングスクリプトの挙動が不正になります。**

Fightcadeで対戦もする場合は、設定の切り替え忘れを防ぐため、**`emulator/fbneo`フォルダー以下を丸ごと複製し、トレーニング専用環境を作ってください。** 複製先でRun-aheadをOFFにし、対戦用と練習用の起動先・設定を分けます。

| 用途 | 起動方法 |
|---|---|
| 対戦 | 通常のFightcadeから起動 |
| トレーニング | 複製先の`run_vsav_training.bat`から起動。Run-aheadはOFF |

## Windowsでの導入

対象ゲームは **Vampire Savior - the lord of vampire（970519 Japan／`vsavj`）** です。

**ROMは含まれません。各自で用意し、先にFBNeoでゲームが起動できる状態にしてください。**

1. FightcadeとFBNeoを終了します。
2. Fightcadeの`emulator/fbneo`フォルダー全体を、別の場所へコピーします。例：`C:/VSAV_Training/fbneo`。
3. 本プロジェクトをダウンロードして展開し、`run_vsav_training.bat`と`scripts`フォルダー全体を、**複製先のfbneoフォルダー**へ配置します。バッチファイルは`fcadefbneo.exe`と同じ階層に置きます。
4. 複製先の`run_vsav_training.bat`を起動し、**Run-aheadをOFF**にします。元の設定もコピーされるため、複製するだけではOFFになりません。
5. FBNeoを完全終了して同じバッチから再起動し、Run-aheadがOFFのままであることを確認します。
6. `Input > Map Game Inputs`でゲーム操作と下表の機能を割り当てます。P2側のゲーム入力も設定してください。

配置先は、空白や日本語を含まない短いパスを使用してください。既存環境を更新する場合は、先に[バックアップ](#更新とバックアップ)を行います。

### 基本操作

| FBNeoの入力項目 | 機能 |
|---|---|
| `Lua Hotkey 1` | トレーニングメニューを開閉 |
| `Lua Hotkey 2` | レバーとの組み合わせで位置を戻す |
| `Lua Hotkey 3` | 録画のループ再生を切り替える |
| `Lua Hotkey 4` | キャラクター選択へ戻る |
| `Volume Up` | 通常録画の開始・終了 |
| `Volume Down` | 録画の再生・停止 |
| `P1 Coin` | 試合中は操作側を切り替え。キャラ選択中はステージ選択 |

`Volume Up / Down`はFBNeoの入力項目名です。アーケードコントローラーなどのボタンにも割り当てられます。

### 最初に試すこと

キャラクターを選んで試合開始後、`Lua Hotkey 1`でメニューを開きます。

- ダミーにガードさせる：`Dummy > Guard = All Guard`と`Random Guard % = 100%`を設定。
- 攻撃を録画する：`Recording > Recording Wizard`を開き、画面の案内に従って録画・確認・保存。
- 反撃やAction Stepsを実行させる：`Guard Action Type`を選び、まず`Random Guard Action % = 100%`で確認。

`Random Guard %`・`Random Guard Action %`が`0%`なら、その行動は実行されません（行がオレンジ色になります）。ここでは**現在のUI名**を記載しています。

### ROMパッチ（任意）

配布zipの `support/ips` にIPSパッチが入っています。`vsavj` 用は `No-BGM`、`No-TechHit`、`Only-One-TechHit`～`Only-Six-TechHit` です。

1. `support` フォルダを複製したfbneoフォルダに置き、バッチファイルから起動します。
2. `F6` を押すか、`Game > Load Game...` を選びます。
3. `Vampire Savior - the lord of vampire (970519 Japan)` を選び、右下の `IPS Manager` を開きます。
4. 使うパッチにチェックを入れて `OK` を押します。
5. `IPS Manager` ボタンの上の `Apply Patch` にチェックを入れ、`Play` を押します。

パッチなしに戻すときは、エミュレーターを閉じて起動し直します。

## マニュアル

**[日本語プレイヤーマニュアル](docs/PLAYER_MANUAL.ja.md)** に、操作・設定・表示の読み方をまとめています。

- [ダミーのガード・受け身・反撃](docs/PLAYER_MANUAL.ja.md#04-dummy)
- [録画とループ再生](docs/PLAYER_MANUAL.ja.md#05-recording)
- [Action Steps](docs/PLAYER_MANUAL.ja.md#06-steps)／[Action Patterns](docs/PLAYER_MANUAL.ja.md#07-patterns)
- [AG練習](docs/PLAYER_MANUAL.ja.md#08-pb)／[GC練習](docs/PLAYER_MANUAL.ja.md#09-gc)
- [Tick Data・空中ガードの分析](docs/PLAYER_MANUAL.ja.md#10-data)
- [目的別の練習レシピ](docs/PLAYER_MANUAL.ja.md#11-drills)
- [困ったとき](docs/PLAYER_MANUAL.ja.md#14-troubleshooting)

### 対応範囲

このREADMEの導入手順はWindows向けです。Linux用の起動スクリプトも同梱していますが、本フォークの全機能についてLinux／macOSで動作することは、このREADMEの作成時には確認していません。Action Patternsの名前入力・ファイル選択はWindows向けの実装です。

時間表示には、内部フレームを使うものと表示フレームを使うものがあります。ダッシュ系の既存トレーナーなども含め、すべての表示がTickに統一されているわけではありません。単位は[マニュアル](docs/PLAYER_MANUAL.ja.md#10-data)を確認してください。

## 更新とバックアップ

FBNeoを終了する前に編集内容を保存し、次のファイルをバックアップしてください。

| 内容 | 保存先 |
|---|---|
| 設定・Action Steps・Action Patterns | `scripts/training_settings.json` |
| 録画 | `scripts/macro`フォルダー全体 |

更新はトレーニング専用の複製先へ行います。配布物に録画ファイルが含まれる場合があるため、自分の録画を不用意に上書きしないでください。更新後はFBNeoを完全に再起動し、Run-aheadがOFFであることも確認します。

## 変更履歴・不具合報告

- [日本語リリースノート](RELEASE_NOTES.ja.md)
- [Release notes (English)](RELEASE_NOTES.md)
- [このフォークのIssues](https://github.com/vampiresavior001/VSAV_Training/issues)

不具合を報告する際は、バージョン、P1／P2キャラクター、左右配置、設定画面、再現手順を添えてください。トレーニング用FBNeoのRun-aheadがOFFであることも確認してください。

## フォーク元・クレジット

本プロジェクトは、[VSAV_Trainingのfc2ブランチ](https://github.com/NBeing/VSAV_Training/tree/fc2)を基にしています。基盤となるトレーニングモードと、各スクリプトを作成・改善してきた貢献者、VSAVコミュニティに感謝します。

<details>
<summary>フォーク元READMEのクレジット</summary>

Shoutouts to: Dammit and Jed for their wizardry, Grouflon (Stole their 3s training mode menu, and settings workflow!) and the VSAV Community.

BIGGEST SHOUTOUT to KyleW! This definitely would not have happened or continued without you.

`N-Bee`

</details>
