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
- 配列変数への代入と参照。変数名は@のみです
  - `@(添字)`
  - 添字は0から32,767までの数値または式です。
  - 配列はBASICプログラム終端直後から添字順に保存されます
  - 添字の最大値は残りRAMに依存します。これを超えると"Subscript is out of range"エラーとなります
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
  - 複数の変数には対応していません
- if文
  - `if 条件式 命令文`
  - `then`は使用しません
- goto文
  - `goto 行番号または式`
  - 指定した、または数式評価された行番号に実行を移します
- gosub文
  - `gosub 行番号または式`
  - 行番号または式で指定したサブルーチンを呼び出します
- return文
  - パラメータはありません
  - 呼び出したgosub文の直後に実行を移します
- end文
  - パラメータはありません
  - プログラムの実行を終了します
- trunc文
  - パラメータはありません。剰余演算を「0への切捨て除算」に設定します
  - 0への切捨て除算はCやGO、Swift、MSX-BASICなど大半の言語で使われている方法です
  - 例：-3 / 2 = 1.5 ですが、0に近い方に切り捨てられ -1 となります
  - **プログラム実行時はこちらがデフォルトです**
- floor文
  - パラメータはありません。剰余演算を「負の無限大への切捨て除算」に設定します
  - 負の無限大への切捨て除算はMathematicaやR、Python、Rubyで使われている方法です
  - 例：-3 / 2 = 1.5 ですが、負の無限大に近い方に切り捨てられ -2 となります
- rnd関数
  - `rnd(数値または式)`
  - 0〜指定した数値の間の乱数を返します
  - 指定できる数値（引数）は1から32,767までです。負の数には対応していません

## 使い方
上記URLの[SBC6303技術資料](http://www.amy.hi-ho.ne.jp/officetetsu/storage/sbc6303_techdata.pdf)を参考に簡易モニタ（monitor.hex）をROMに書き込んでください。  
SBC6303を起動し、プログラム（tinybasic.s19）を'l'コマンドで読み込ませてください。  
**$0000〜$1fffまでのRAM（8Kバイト）が必要です。**  

XON/XOFFフロー制御を実装しています。  
ターミナルソフトのソフトウェアフロー制御を有効にしてください。  
テキスト貼り付け時の遅延は不要です

<img src="https://user-images.githubusercontent.com/71197813/222955274-b7882104-1cb3-44aa-a13e-ca898f8a2c41.png" width="500">
<img src="https://user-images.githubusercontent.com/71197813/222955303-f1ad71e8-6ac7-4971-a552-dbfc27dbfb9d.png" width="500">
<img src="https://user-images.githubusercontent.com/71197813/222435459-4208a819-0e17-4004-9b11-5b69cd56a0ba.png">
<img src="https://user-images.githubusercontent.com/71197813/222435482-cddbb36f-da3f-491e-a950-f9972f95333c.png">

## 開発環境
- macOS Monterey
- [SB-Assembler](https://www.sbprojects.net/sbasm/) - Macro Cross Assembler
- [minipro](https://gitlab.com/DavidGriffith/minipro.git) - TL866xx controller
