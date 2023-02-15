# 6303 Tiny BASIC
## It's still under development
Tiny BASIC for the [SBC6303](https://vintagechips.wordpress.com/2018/04/26/sbc6303ルーズキット/).  
The SBC6303 is a single board computer operating with the Hitachi HD6303.

## 概要
[SBC6303ルーズキット](https://vintagechips.wordpress.com/2018/04/26/sbc6303ルーズキット/)用Tiny BASICの自作を目指しています。いまだ開発中です。

現在は下記の機能を実装しています。

- ダイレクトモードのみ
- `:`でマルチステートメント
- 四則演算。`%`で剰余（mod）
  - 数値は16bit符号付き整数のみ。オーバーフロー判定は行わない
- 単純変数への代入と参照。aからzの26文字のみ
- print文
  - `print 式または変数`
  - `;`を付けると改行なし
  - `,`を付けると8文字おきに出力する
- input文
  - `input 変数`
  - `input "文字列";変数`

## 使い方
上記URLの[SBC6303技術資料](http://www.amy.hi-ho.ne.jp/officetetsu/storage/sbc6303_techdata.pdf)を参考に簡易モニタ（monitor.hex）をROMに書き込んでください。  
SBC6303を起動し、プログラム（tinybasic.s19）を'l'コマンドで読み込ませてください。  
**$0000〜$1fffまでのRAM（8Kバイト）が必要です。**

## 開発環境
- macOS Monterey
- [SB-Assembler](https://www.sbprojects.net/sbasm/) - Macro Cross Assembler
- [minipro](https://gitlab.com/DavidGriffith/minipro.git) - TL866xx controller
