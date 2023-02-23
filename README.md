# 6303 Tiny BASIC
## It's still under development
Tiny BASIC for the [SBC6303](https://vintagechips.wordpress.com/2018/04/26/sbc6303ルーズキット/).  
The SBC6303 is a single board computer operating with the Hitachi HD6303.

## 概要
[SBC6303ルーズキット](https://vintagechips.wordpress.com/2018/04/26/sbc6303ルーズキット/)用Tiny BASICの自作を目指しています。いまだ開発中です。

現在は下記の機能を実装しています。

- 四則演算。`%`で剰余（mod）
  - 数値は16bit符号付き整数のみ。オーバーフロー判定は行いません
  - 四則演算の優先順位に対応しています
  - 括弧も使えます
- 比較演算。演算子は`=, <>, <, <=, >, >=`の6種類
- `:`でマルチステートメント
- 単純変数への代入と参照。aからzの26文字のみです
- listコマンド
  - パラメータはありません。保存されたプログラムを全行表示します
- runコマンド
  - パラメータはありません。保存されたプログラムを先頭から実行します
  - 実行前に変数領域をゼロクリアします
- newコマンド
  - パラメータはありません。保存されたプログラムを消去し、変数を初期化します
- print文
  - `print 式または変数`
  - `;`を付けると改行なしになります
  - `,`を付けると8文字おきに出力します
- input文
  - `input 変数`
  - `input "文字列";変数`
- if文
  - `if 条件式 命令分`
  - `then`は使用しません
  - 複数の変数には対応していません

## 使い方
上記URLの[SBC6303技術資料](http://www.amy.hi-ho.ne.jp/officetetsu/storage/sbc6303_techdata.pdf)を参考に簡易モニタ（monitor.hex）をROMに書き込んでください。  
SBC6303を起動し、プログラム（tinybasic.s19）を'l'コマンドで読み込ませてください。  
**$0000〜$1fffまでのRAM（8Kバイト）が必要です。**

## 開発環境
- macOS Monterey
- [SB-Assembler](https://www.sbprojects.net/sbasm/) - Macro Cross Assembler
- [minipro](https://gitlab.com/DavidGriffith/minipro.git) - TL866xx controller
