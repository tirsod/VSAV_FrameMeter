# 共同開発者向け差分

このフォルダは v11.3.2 です。

基は `VSAV_Training-fc2_v11.3.1` です。

内部の実験番号、カットした試作、メニューのテンキー表記は入れていません。

起き上がりの詳細は [wakeup_reversal_behavior.md](wakeup_reversal_behavior.md) です。

同じ内容の一覧は [COLLABORATOR_CHANGES.html](COLLABORATOR_CHANGES.html) です。

## メニューの操作速度

左右のたびに JSON を書いていたヒッチをやめました。

値はメモリへ即時反映します。

ディスクへ書くのはメニューを閉じたとき、またはスクリプト終了時だけです。

## 起き上がり挙動（無敵）

`poke_special()` は `+0x147` に `1` を書きません。

ダウンリバーサルでは、リバーサル+1 で `+0x11E` / `+0x143` / `+0x134` を 0 にします。

`+0x147` は書きません。

通常無敵がない必殺は、ダウンリバーサル中に被弾します。

無敵がある技は、ゲームが載せた本来の無敵が残ります。

## 起き上がり挙動（投げのセルフディレクション）

Character Specific はコマンド認識を通らないので、投げにセルフディレクションが付きませんでした。

poke 時に向きバイト `0xFF880B` を相手向きにします。

打撃必殺は技側で向きが付きます。

## 見てほしいファイル

- `scripts/utilities.lua`
- `scripts/menu.lua`
- `scripts/vsav_training_master_script.lua`
- `scripts/guardCancel.lua`
- [wakeup_reversal_behavior.md](wakeup_reversal_behavior.md)

## 含めていないもの

- 実験番号付きのコメントとログ版名
- 技ごとの無敵表
- poke フレームの `+0x147 = 1`
- リスト送りを速くした試作（初期待ち 8、毎フレーム送り）
- `Reversal/Counter Input Motion` のテンキー表示（QCF / QCB のまま）
- 個人用の `training_settings.json`

## 確認してほしいこと

メニューで Reversal/Counter Button を左右したとき、値がすぐに送れること。

メニューを閉じて再起動したあと、選んだ値が残っていること。

通常無敵がない必殺のダウンリバーサル中に被弾すること。

起き上がり投げにセルフディレクションが付くこと。

1 フレーム発生のコマンド投げが、ソウルフィストなどの弾重ねに勝つこと。

## 差分許容

FBNeo は常に `scripts\vsav_training_master_script.lua` を読む。

ROM、セーブ、実行ファイルは共有する。版の差は `scripts` だけに置く。

この更新の恒久名は `scripts_v11.3.2` である。

起動は `run_vsav_training_v11.3.2.bat` である。

`scripts` がある状態で別の版を載せるときは、`scripts` を `scripts_active_suspend` に退避する。

Lua の差し替えは Fightcade と FBNeo の完全終了が要る。
