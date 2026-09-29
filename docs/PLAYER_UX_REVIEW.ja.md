# プレイヤー視点でのUI・説明改善候補

[English](PLAYER_UX_REVIEW.en.md) | 日本語

対象：v11.7.16、コミット `351e31034a3e4eb067e60c4f74f17ec59277ca20`。確認日：2026-09-29。

マニュアル作成時のソース確認に基づく指摘。以下の変更は提案であり、ゲームやUIへの実装は行っていない。操作確認はエミュレーター上では未実施。

## 実装状況（2026-09-29）

v11.7.16.1の後に、1・2・3・4（表示のみ）・5・9と、AGの6回の記述を実装した。6・7・8は提案のまま。プレイヤーマニュアルとREADMEは新しい名前に合わせた。

- 1：起動時のコンソール表示を Lua Hotkey 1～4 の案内にし、StartとAltの記述を外した。
- 2：Tick Dataの説明に `4 + 3 + 7 - 1 = 13` と、Totalがヒット間の隙間を含むことを書いた。
- 3：説明の名前を `Reversal - Action Steps` と `Reversal Action Steps` にした。
- 4・9：`Random Guard %`、`Random Guard Action %`、`Random Throw Tech %` に改名し、Noneを `0%` と表示する。選んだガードやガードアクションを0%が止めているときは、その行をオレンジ色にし、最下行に理由を出す。保存値と初期値は変えていない。Analysisタブの `Guard Action Frequency Check` は `Random Guard Action % Check` になった。
- 5：Waitの選択肢ごとに、一覧の下へ1行の説明を出す。
- AG：ROM `0x028D50` の確率表を実行中に読み、1～2回目は0%、3～5回目は25/50/75%、6回目以降は100%と確認した。説明は「6回目で必ず成立」にそろえた。

## 優先度1：説明と実際の動作が違う

### 1. メニューを開くボタンの案内が古い

- 確認事項：起動時に `Press Start open the training menu` と出るが、controller.luaのStartによるメニュー開閉処理はコメントアウトされている。実際の登録はLua Hotkey 1。
- 影響：初回導入でメニューへ到達できない。割り当てを間違えたと考えてしまう。
- 提案：起動メッセージを `Lua Hotkey 1` に統一し、`Input > Map Game Inputs` での割り当ても案内する。Alt+3／4も固定キーとして扱わず、まずLua Hotkey 3／4の機能名を案内する。
- 確認箇所：[vsav_training_master_script.lua](../scripts/vsav_training_master_script.lua)、[controller.lua](../scripts/controller.lua)。

### 2. Tick Dataの説明が計算方法と一致していない

- 確認事項：メニュー説明は発生・持続・硬直について `They add up to Total` と書いている。一方、計算処理では発生と持続が最初の攻撃判定の1 Tickを共有する。単発の基本例は `4 + 3 + 7 - 1 = 13`。
- 影響：正しい表示でも計算ミスに見える。多段技では途中の隙間もあるため、単純加算の説明はさらに誤解を招く。
- 提案：説明文を実際の数え方に合わせる。単発の式と、多段の隙間をTotalへ含むことを明記する。
- 確認箇所：[menu.lua](../scripts/menu.lua)のTick Data、[tickData.lua](../scripts/tickData.lua)の測定結果生成。

### 3. 存在しない旧項目名が残っている

- 確認事項：Action Stepsへの案内に `Reversal - Sequence` や `Reversal Sequence` が残っているが、現在の選択肢は `Reversal - Action Steps`、編集項目は `Reversal Action Steps`。
- 影響：説明に従っても該当項目が見つからない。
- 提案：現在の画面名に揃える。画面名を変更するときは説明内の参照も同時に点検する。
- 確認箇所：[actionSequenceEditor.lua](../scripts/actionSequenceEditor.lua)のparent_item、[menu.lua](../scripts/menu.lua)のGuard Action Type説明。

## 優先度2：設定の意味を取り違えやすい

### 4. ガードや反撃を有効にしても頻度Noneのまま動かない

- 確認事項：ガード方法とは別に `P2 Random Guard %` があり、初期値はNone。反撃にも別の `Guard Action Frequency` があり、初期値はNone。Steps／Patternsには頻度Noneの警告が既にある。
- 影響：All Guardや反撃の種類を選んだ時点で有効になったと考え、実際には何も起きない。
- 推奨：保存値を勝手に変えず、ガードと反撃のそれぞれに「実行確率0%のため無効」と常時表示する。Steps／Patterns以外にも同じ警告を適用する。表示名とNoneの変更は提案9に合わせる。
- 別案：初回選択時に100%を提案する。ただし既存の練習設定へ影響するため、単なる表示修正とは分けて検討する。
- 確認箇所：[config.lua](../scripts/config.lua)、[menu.lua](../scripts/menu.lua)、[actionSequenceEditor.lua](../scripts/actionSequenceEditor.lua)。

### 5. AfterとLandingが「どちらも最速のAuto」に見える

- 確認事項：Afterは行動可能になってから入力開始。地上ダッシュは接地も待つ。Landingは着地を予測し、最後の入力が着地に合うよう先行入力する。編集画面の一般説明 `Auto is the earliest` では、この違いが伝わらない。
- 影響：Afterで組んだダッシュを最速だと考え、連係や割り込みの結論を誤る。
- 提案：説明に `After: start inputs after recovery; no pre-input` と `Landing: pre-input to finish on landing` 相当の区別を出す。予測が得られず着地後開始へ切り替わった場合も、可能なら結果側へ表示する。
- 補足：全Autoを一律に改名すると、ダッシュ後の測定済みAutoなど別の意味まで変わる。AfterとLandingの説明から直すのが小さい変更。
- 確認箇所：[actionSequenceRunner.lua](../scripts/actionSequenceRunner.lua)のlanding_ready、step.auto分岐、LOOP_AUTO、[actionSequenceEditor.lua](../scripts/actionSequenceEditor.lua)のHELP.wait。

### 6. Guard Action Delayが「反撃全体の開始を遅らせる」に見える

- 確認事項：Specifiedでは、基本的にモーション後のボタンまでの待ち。ダッシュそのものの開始を遅らせる設定ではない。GCには別の `GC Input Delay (Ticks)` がある。
- 影響：遅らせダッシュと遅らせダッシュ攻撃を混同する。
- 提案：Specifiedの画面では `Button Delay after Motion (Ticks)` 相当の名前にする。ほかのGuard Action Typeでも同じ設定を参照するため、全種類を一括改名せず用途別に表示名を検討する。
- 確認箇所：[menu.lua](../scripts/menu.lua)のguard_action_delay_menu_item、gc_input_delay_menu_item。

### 7. Waitの選択名と結果表示が異なり、0も数値として出ない

- 確認事項：選択画面はAfter、Landing、Fixed Ticksなど、一覧はAuto (After)、Auto (Landing)、+Ntなど。1歩目の最小値はFixed Ticksの中でAuto (Fastest)と表示される。Holdの長さは次のステップのWaitで決まる。
- 影響：最速を選びたいのにFixed Ticksを開く必要があること、Waitがその行動の継続時間ではないことが分かりにくい。
- 提案：1歩目にFastestを独立した選択肢として出す。Waitの補足は「この行動までの待ち」、Holdは「次のステップまで方向保持」とする。現行の `+Nt` と `Hold Nt` 表示は残す。
- 確認箇所：[actionSequenceEditor.lua](../scripts/actionSequenceEditor.lua)のwait_label、Wait画面、detail_items。

### 8. 時間表示の単位が混在する

- 確認事項：Tick DataやStepsは内部フレーム、ダッシュ系トレーナーや録画・再生、録画間隔は表示フレーム。IAD Trainerは高さを表示する。
- 影響：同じ数値でも意味が異なり、直接比較してしまう。
- 提案：時間の結果には `t` または `display f` を常に付ける。Game Speedの説明に「Normal: 1 display frame = 1 Tick / Turbo 3: 3 display frames = 4 Ticks」を出す。高さは時間と区別して表示する。
- 確認箇所：[menu.lua](../scripts/menu.lua)の各トレーナー説明、[hud.lua](../scripts/hud.lua)。

### 9. Dummyタブの確率設定の表記を統一する

現行UIで、プレイヤーがパーセントを指定する設定は以下の3項目。Dummyタブ内では対象が明らかなため、P2の接頭辞を省く。日本語話者にも意味を取りやすいRandomと%の表記に揃え、Chanceへの改名は行わない。

| 現在の項目名 | 提案する項目名 | 指定するもの |
|---|---|---|
| `P2 Random Guard %` | `Random Guard %` | ガードする確率 |
| `Guard Action Frequency` | `Random Guard Action %` | 設定したガードアクションを実行する確率 |
| `Tech Throws` | `Random Throw Tech %` | 投げ抜けする確率 |

3項目の選択肢はすべて `0% / 25% / 50% / 75% / 100%` とする。現在のNoneは0%へ表示だけを変更する。`Guard Action Type = None`、方向・ボタンのNoneなど、「何もしない／入力しない」を選ぶ項目はそのまま残す。

#### 変更の範囲と確認点

- 内部の設定キー、保存された選択肢の番号、初期値、抽選処理は変更しない。既存の保存データの意味を保つ。
- `Guard Action Type` の名前は維持する。行動内容と、その行動の実行確率は別項目として示す。
- メニュー説明、Steps／Patternsの頻度None警告、`Show GC Frequency Counter` の説明文など、旧項目名を参照する案内も揃える。カウンターは実測表示であり、確率を指定する4番目の設定ではない。
- 名称変更後の列幅・説明枠への収まりを確認する。
- UI実装後にプレイヤーマニュアルの項目名と操作手順を更新する。未実装の現時点では、マニュアル本文は実際のUI名を保持する。

#### 今回の3項目とは別のランダム設定

`Wakeup` のRandom、録画スロットのランダム再生、Action Patternsの使用候補、`Pit of Blame` のRandom、`Gloomy Puppet Show` の0＝Randomは、候補をランダムに選ぶ設定であり、プレイヤーが確率をパーセント指定する項目ではない。これらの0やNoneを、一括で0%へ変換しない。

また、ソースには `counter_attack_random_upback` の確率一覧と初期設定が残るが、現在のメニューにはこの設定の行が登録されていないため、現行UIの対象3項目には含めない。

- 確認箇所：[menu.lua](../scripts/menu.lua)の確率一覧・メニュー行・get_menu、[config.lua](../scripts/config.lua)、[actionSequenceEditor.lua](../scripts/actionSequenceEditor.lua)の警告表示。

## AGカウントは現状の仕様を維持する

成立後の入力を含めることへの分離提案は撤回する。これは誤解を招く不備ではなく、毎回6回を入力し切る練習を可視化するための設計である。途中でAGが成立しても、そこで手を止める必要はない。

- 練習目標：受付内でなるべく遅らせ、6回の有効入力を収める。
- 表示の役割：成立結果、入力タイミング、一連の入力回数を確認する。
- LateMash：成立後ではなく受付終了後の入力。受付内で成立後も押す練習とは区別する。
- 根拠：[timers.lua](../scripts/timers.lua)の `THE PUSH BLOCK COUNT IS A TRAINING NUMBER: PRESSES MADE` と、開発者からの設計意図の説明。

なお、menu.luaなどには「8回で確定」という説明が残る一方、timers.luaには「6回で確定」「6回を練習目標」と記載されている。プレイヤー向け説明は6回を基準に揃える。8回の比較分岐があることだけでは、それ未満の確率テーブルで6回が100%になる可能性を否定できない。ROMの確率テーブル自体は今回未検証のため、内部解析コメントを訂正する際はそこまで確認する。

## 推奨する修正順

1. 起動案内、Tick Dataの説明、旧項目名を訂正する。
2. 確率3項目の名称・0%表示・警告を統一し、After／Landingの説明を揃える。
3. Delay・Wait・単位表示を改善する。
4. AGカウントの現行仕様を維持し、遅らせ6回入力という練習目的と、成功回数の説明を揃える。

1は動作を変えない訂正。2以降は表示・UIに関わるため、変更内容を確認してから実装する。初期値変更や自動補正は、既存設定を変える可能性があるので別件として扱う。
