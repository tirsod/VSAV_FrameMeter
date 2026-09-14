# 共同開発者向け差分

この文書は v11.4.2 です。

基は v11.4 です。

実行時の恒久名は `scripts_v11.4.1` です。

HUD の版表示は `v11.4.2` です。

内部の実験番号、カットした試作、メニューのテンキー表記は入れていません。

v11.3.2 までの差分は、共同開発者向けフォルダの `COLLABORATOR_CHANGES.md` です。

## Knockdown Logger をオフにしたときの停止

もともとオンオフしていたものは次です。

- `reversal_logs/kd_cXX_sNN.json`（リカバリトレース。キャラ別リング）
- `reversal_logs/kd_cXX_mNN.json`（マークしたリカバリトレース。キャラ別リング）
- `reversal_logs/p1_manual_NN.json`（P1 手動入力の監視。最大 8 件）
- トレースへ書く `mark_queue`、`mark_poke`、`mark_hold`、`mark_write`

オフでも動いていたものは次です。今回止めました。

- `reversal_logs/hw_input_probe.json`（P1 と P2 の押下が変わるたびに上書き）
- `reversal_logs/p1_encoding.json`（P1 の新しい組み合わせ、またはレバー／ボタン RAM の変化）
- `reversal_logs/rb_freq.json`（`registerBefore` 600 回ごと）
- `reversal_logs/rev4_freq.json`（リバーサル窓の書き込み回数）
- `reversal_logs/code_dump.json`（試合開始の最初の 1 回、ROM `0x26800` から 16384 バイト）
- `memory.registerexec` の `0x26D00` から `0x26D90` の掃引（起き上がり判定ブロック付近）
- 個別の `memory.registerexec`（`0x26D7A`、`0x29854`、`0x26D5C`、`0x26D36`、`0x02D3F2`、`0x024F02`）
- 個別の `memory.registerwrite`（`0xFF89A7`、`0xFF8922`、`0xFF8925`、`0xFF8806`）

オフなら、上の両方とも止まります。

オンなら、トレースと監査の両方が動きます。

## ガード後リバーサルの積み直し

対象は `guardCancel.lua` です。

表示フレームごとに走るガード硬直の武装処理です。

`BLK.episode` と `0xFF8958` と `0xFF8806` を検索すると、3 箇所が並んでいます。

### 残す既存の動き

複数ヒットのガードでは、前のヒット用に積んだ入力を着弾フリーズ（impact freeze）で捨てます。

`$06` こと `0xFF8806` が `0x00` のとき、`hs_armed` を下ろし、`pending_input_sequence` を `hs_request_flush` して `nil` にします。

この捨て処理は残します。

ヒット硬直用の再武装は、`0xFF8940` が `0x00` または `0x04` のときだけです。

ガード中は `0xFF8940` が `0x02` または `0x12` なので、ヒット硬直側では積み直しません。

ガード側の積み直しは `BLK.episode` が下りたあと、`_blk_ready` で武装する経路だけです。

武装の条件（`_in_stun`、`$05 == 0x02`、`_blk140`、`_blk_ready`、`_kd == 0`）は外しません。

### 壊れていた条件

接触タイマー `0xFF8958` は着弾で 14 になり、1 tick ずつ減ります。

積み直しの合図が「値がちょうど 14、かつ前回が 14 でない」だったので、表示フレームが 14 を逃すと `BLK.episode` が下りませんでした。

同じ関数の中では、武装の判定が先、`$06 == 0x00` での捨てが後です。

2 ヒット目のフリーズ中に `_blk_ready` が立っていると、フリーズ中に武装して積み、残りのフリーズ表示フレームでまた捨てます。

そのとき `BLK.episode` は立ったままなので、フリーズ明けにも積み直しません。

スクロール入力には何も残りません。

Game Speed 1 でも欠けます。

1 ヒットだけのガードと、2 ヒット目が空振りの連打キャンセルは、2 回目のフリーズが来ないので欠けません。

3 箇所を揃えて直します。

どれか一つだけだと、フリーズ中に積んで捨てるか、14 を逃したまま武装済みが残ります。

### 接触タイマーの再セットでエピソードを外す

`0xFF8958` を 1 回読み、局所変数にします。

ゼロエッジ（前回が 0 より大きく、今回が 0）も、その値を使います。

次を、

```lua
if memory.readbyte(0xFF8958) == 14 and BLK.prev158 ~= 14 then
	BLK.episode = false
	BLK.zero_lg = nil
	BLK.lead = nil
end
if memory.readbyte(0xFF8958) == 0 and BLK.prev158 > 0 then
	BLK.zero_lg = memory.readbyte(0xFF8081)
end
```

次にします。

```lua
local _s158 = memory.readbyte(0xFF8958)
if _s158 > BLK.prev158 then
	BLK.episode = false
	BLK.zero_lg = nil
	BLK.lead = nil
end
if _s158 == 0 and BLK.prev158 > 0 then
	BLK.zero_lg = memory.readbyte(0xFF8081)
end
```

14 を逃して 13 を見たときも、前回より増えていれば再セットとみなします。

`BLK.prev158` の更新位置は、武装判定のあとです。

ここは変えません。

### 着弾フリーズ中は武装しない

`BLK.episode` が false のときの武装条件に、次を足します。

```lua
and memory.readbyte(0xFF8806) ~= 0x00
```

他の条件は残します。

同じ表示フレームで、この武装のあとに `$06 == 0x00` の捨てが走ります。

フリーズ中に武装すると、積んだ直後の捨てと、続くフリーズ表示フレームの捨てで空になります。

### 着弾フリーズでエピソードも外す

次の塊を、

```lua
if _in_stun and memory.readbyte(0xFF8806) == 0x00 then
	hs_armed = false
	hs_countdown = nil
	hs_0c_armed = false
	hs_0c_lg = nil
	hs_throw_armed = false
	hs_ready = false
	local _stale = _d and _d.pending_input_sequence
	if _stale ~= nil and _stale.hold_last and not _stale.released then
		hs_request_flush(_stale)
		_d.pending_input_sequence = nil
	end
end
```

次にします。

```lua
if _in_stun and memory.readbyte(0xFF8806) == 0x00 then
	hs_armed = false
	hs_countdown = nil
	hs_0c_armed = false
	hs_0c_lg = nil
	hs_throw_armed = false
	hs_ready = false
	BLK.episode = false
	local _stale = _d and _d.pending_input_sequence
	if _stale ~= nil and _stale.hold_last and not _stale.released then
		hs_request_flush(_stale)
		_d.pending_input_sequence = nil
	end
end
```

足すのは `BLK.episode = false` だけです。

捨て処理は残します。

14 を見逃しても、フリーズ中はエピソードが下り続け、フリーズ明けの `_blk_ready` で積み直せます。

ヒット硬直中もこの行は走りますが、`_blk140` が false ならもともと `BLK.episode` は false です。


## 見てほしいファイル

- `scripts_v11.4.1/debugKnockdown.lua`
- `scripts_v11.4.1/menu.lua`
- `scripts_v11.4.1/guardCancel.lua`

## 含めていないもの

- 実験番号付きのコメントとログ版名
- 個人用の `training_settings.json`
- v11.3.2 への同一修正

## 確認してほしいこと

Etc 欄の Knockdown Logger がオフのとき、`hw_input_probe.json`、`p1_encoding.json`、`rb_freq.json`、`rev4_freq.json`、`code_dump.json` が増えないこと。

モリガンのしゃがみ小Kをガードさせ、連打せず硬直を最後まで見たとき、指定したリバーサル入力が出ること。

連打キャンセルして 2 ヒット目を空振りしたとき、指定したリバーサル入力が出ること。

連打キャンセルして 2 ヒット目もガードさせたとき、指定したリバーサル入力が出ること。

## 差分許容

FBNeo は常に `scripts\vsav_training_master_script.lua` を読む。

ROM、セーブ、実行ファイルは共有する。版の差は `scripts` だけに置く。

この更新の恒久名は `scripts_v11.4.1` である。

起動は `run_vsav_training_v11.4.1.bat` である。

`scripts` がある状態で別の版を載せるときは、`scripts` を `scripts_active_suspend` に退避する。

Lua の差し替えは Fightcade と FBNeo の完全終了が要る。
