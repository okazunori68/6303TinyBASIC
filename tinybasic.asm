;
; * Tiny BASIC for SBC6303
; *
; * Copyright (c) 2023 okazunori
; * Released under the MIT license
; * http://opensource.org/licenses/mit-license.php
; *
; * Use SB-Assembler
; * https://github.com/sbprojects/sbasm3
;
        .cr     6301
        .tf     tinybasic.s19,s19
        .lf     tinybasic

; ********************************************************************
;   HD6303R Internal Registers
; ********************************************************************
        .in     ./HD6303R_chip.def

; ***********************************************************************
;   ジャンプテーブル Service routine jump table
; ********************************************************************
init_sbc6303            .eq     $ffa0
mon_main                .eq     $ffa3
read_char               .eq     $ffa6
read_line               .eq     $ffa9
write_char              .eq     $ffac
write_line              .eq     $ffaf
write_crlf              .eq     $ffb2
write_space             .eq     $ffb5
write_byte              .eq     $ffb8
write_word              .eq     $ffbb
is_alphabetic_char      .eq     $ffbe
is_decimal_char         .eq     $ffc1
is_hexadecimal_char     .eq     $ffc4

; ***********************************************************************
;   定数 Constants
; ***********************************************************************
NUL             .eq     $00     ; NUL
BS              .eq     $08     ; Backspace
SPACE           .eq     $20     ; Space
CR              .eq     $0d     ; Carriage Return
LF              .eq     $0a     ; Line Feed
DEL             .eq     $7f     ; Delete

RAM_START       .eq     $0020
RAM_END         .eq     $1fff
ROM_START       .eq     $e000
ROM_END         .eq     $ffff
STACK           .eq     $0fff

PROGRAM_START   .eq     $1000
Rx_BUFFER       .eq     $0100   ; SCI Rx Buffer ($0100-0148,73byte)
Rx_BUFFER_END   .eq     $0148   ; 73byte（72character）
CSTACK          .eq     $0149   ; 計算スタック (Calculate stack, 40byte)
VARIABLE        .eq     $01c2   ; 変数26文字 ($01c2-01f5, 52byte)

; ***********************************************************************
;   システム変数 System variables
; ***********************************************************************
        .sm     RAM
        .or     $20

; Interrupt Vector Hooking
VEC_TRAP        .bs     3
VEC_SCI         .bs     3
VEC_TOF         .bs     3
VEC_OCF         .bs     3
VEC_ICF         .bs     3
VEC_IRQ         .bs     3
VEC_SWI         .bs     3
VEC_NMI         .bs     3
BreakPointFlag  .bs     1
; General-Purpose Registers
R0              .bs     2
R1              .bs     2

; ***********************************************************************
;   変数 Variables
; ***********************************************************************
        .sm     RAM
        .or     $80

StackPointer    .bs     2       ; スタックポインタ初期値の退避用
CStackPtr       .bs     2       ; 計算スタック（Calculate stack）ポインタ
SignFlag        .bs     1       ; 符号フラグ '+' = 0, '-' = 1
QuoSignFlag     .bs     1       ; 商（Quotient）の符号フラグ '+' = 0, '-' = 1
RemSignFlag     .bs     1       ; 剰余（Remainder）の符号フラグ '+' = 0, '-' = 1
Divisor         .bs     2       ; 除数
Remainder       .bs     2       ; 剰余
VariableAddr    .bs     2       ; 変数のアドレス
ExePointer      .bs     2       ; 実行位置（Execute address）ポインタ

; General-Purpose Registers
UR0             *
UR0H            .bs     1
UR0L            .bs     1
UR1             *
UR1H            .bs     1
UR1L            .bs     1
; Work area
COMPARE         .bs     6       ; 文字列比較用バッファ

; ***********************************************************************
;   Program Start
; ***********************************************************************
        .sm     CODE
        .or     PROGRAM_START

init_tinybasic:
        tsx
        stx     <StackPointer

tb_main:
        ldab    #'>'
        jsr     write_char
        jsr     read_line
        ldx     #Rx_BUFFER      ; 実行位置アドレスをセット
        jmp     exe_line


; -----------------------------------------------------------------------
; 一行実行
; Execute one line
;【引数】X:実行位置アドレス
;【使用】A, B, X
;【返値】なし
; -----------------------------------------------------------------------
exe_line:
        jsr     skip_space
        beq     :end            ; 終端文字（$00）ならば終了
      ; // 代入文のチェック
        jsr     is_variable     ; 変数か？
        bcc     :cmd            ; No. テーブル検索へ
        ldaa    #VARIABLE>>8    ; Yes. A = 変数領域の上位バイト
        aslb                    ; B = 変数領域の下位バイト
        std     <VariableAddr   ; 変数アドレスを保存
        jsr     skip_space      ; Yes. 代入文か？
        cmpb    #'='
        bne     :err00          ; No. エラー処理へ
        inx                     ; Yes. 代入実行
        jmp     exe_let
.cmd    ldd     0,x             ; 6文字を文字列比較用バッファに転送しておく
        std     <COMPARE
        ldd     2,x
        std     <COMPARE+2
        ldd     4,x
        std     <COMPARE+4
        stx     <ExePointer     ; 実行位置アドレスを退避
        ldx     #SMT_TABLE      ; 文字列テーブルアドレスをセット
        jsr     search_table    ; テーブル検索実行
        bcc     :err00
.end    jmp     tb_main

.err00  clra                    ; syntax error.
        jmp     write_err_msg


; -----------------------------------------------------------------------
; 式を評価する
; Evaluate the expression
;【引数】B:アスキーコード X:実行位置アドレス
;【使用】A, B, X （下位ルーチンでUR0, UR1）
;【返値】真(C=1) / D:Integer X:次の実行位置アドレス
;        偽(C=0) / X:現在の実行位置アドレス
; -----------------------------------------------------------------------
eval_expression:
      ; // 計算スタックの初期化
        ldd     #CSTACK+40+1    ; 40byte分
        std     <CStackPtr
      ; // 式評価開始
        bsr     expr_3rd
      ; // 計算結果をスタックトップから取り出す
        pshx
        ldx     <CStackPtr
        ldd     0,x
        pulx
        sec                     ; true:C=1
        rts

expr_3rd:
        bsr     expr_2nd
.loop   jsr     skip_space
        cmpb    #'+'
        bne     :minus
        inx
        bsr     expr_2nd
        jsr     CS_add
        bra     :loop
.minus  cmpb    #'-'
        bne     :end
        inx
        bsr     expr_2nd
        jsr     CS_sub
        bra     :loop
.end    rts

expr_2nd:
        bsr     expr_1st
.loop   jsr     skip_space
        cmpb    #'*'
        bne     :div
        inx
        bsr     expr_1st
        jsr     CS_mul
        bra     :loop
.div    cmpb    #'/'
        bne     :mod
        inx
        bsr     expr_1st
        jsr     CS_div
        bra     :loop
.mod    cmpb    #'%'
        bne     :end
        inx
        bsr     expr_1st
        jsr     CS_mod
        bra     :loop
.end    rts

expr_1st:
        jsr     skip_space
        jsr     get_int_from_decimal    ; 数字チェックと取得
        bcc     :var            ; 数字でなければ変数のチェックへ
        bra     :push           ; 数字であればスタックにプッシュ
.var    jsr     is_variable     ; 変数か？
        bcc     :paren          ; 変数でなければカッコのチェックへ
      ; // 変数値の取得
        pshx                    ; 実行位置アドレスを退避
        ldaa    #VARIABLE>>8    ; A = 変数領域の上位バイト
        aslb                    ; B = 変数領域の下位バイト
        xgdx                    ; X = 変数のアドレス
        ldd     0,x             ; D <- 変数の値
        pulx                    ; 実行位置アドレスを復帰
        bra     :push           ; 変数の値をスタックにプッシュ
.paren  cmpb    #'('
        bne     :err04
        inx
        bsr     expr_3rd
        cmpb    #')'
        bne     :err04
        inx
        rts
.push   pshx                    ; 実行位置アドレスを退避
        ldx     <CStackPtr      ; X <- 計算スタックポインタ
        dex
        dex
        cpx     #CSTACK-2       ; スタックオーバーフローのチェック
        bcs     :err06
        std     0,x
        stx     <CStackPtr
        pulx                    ; 実行位置アドレスを復帰
        rts
.err04  ldaa    #4              ; "Illegal expression"
        jmp     write_err_msg
.err06  ldaa    #6              ; "Calculate stack overflow"
        jmp     write_err_msg

;
; Arithmetic operator
;
CS_store:
        inx
        inx
        std     0,x
        stx     <CStackPtr      ; 計算スタックポインタを保存
        pulx                    ; 実行位置アドレスを復帰
        rts

CS_add: pshx                    ; 実行位置アドレスを退避
        ldx     <CStackPtr      ; X <- 計算スタックポインタ
        ldd     2,x
        addd    0,x
        bra     CS_store

CS_sub: pshx                    ; 実行位置アドレスを退避
        ldx     <CStackPtr      ; X <- 計算スタックポインタ
        ldd     2,x
        subd    0,x
        bra     CS_store

CS_mul:
.Result         .eq     UR0
        pshx                    ; 実行位置アドレスを退避
        ldx     <CStackPtr      ; X <- 計算スタックポインタ
        ; B * D
        ldaa    3,x             ;「B」をAレジスタに代入
        ldab    1,x             ;「D」をBレジスタに代入
        mul                     ; B * D
        std     <:Result        ;「B*D」を保存
        ; A * D
        ldd     1,x             ;「D」をAレジスタに、「A」をBレジスタに同時に代入
        mul                     ; A * D
        addb    <:Result        ;「A*D」の下位8bitをResultの上位8bitに加算
        stab    <:Result        ; Resultの上位8bitを保存
        ; C * B
        ldaa    0,x             ;「C」をAレジスタに代入
        ldab    3,x             ;「B」をBレジスタに代入
        mul                     ; C * B
        addb    <:Result        ;「C*B」の下位8bitをResultの上位8bitに加算
        tba                     ; Resultの上位8bitをAレジスタに転送
        ldab    <:Result+1      ; Resultの下位8bitをBレジスタに転送
        bra     CS_store

;
; 符号付き割り算の考え方
; ・剰余は除数の符号と同一
;   ・ 7 / 3  = 商  2、剰余  1
;   ・-7 / 3  = 商 -3、剰余  2
;   ・ 7 / -3 = 商 -3、剰余 -2
;   ・-7 / -3 = 商  2、剰余 -1
;  商 ：1.被除数の符号と序数の符号が一致していないときには1足して符号反転する
;       2.ただし、除数がゼロの場合は1は足さない
; 剰余：1.被除数の符号と序数の符号が一致していないときには
;         除数の絶対値から剰余の絶対値を引く
;       2.その結果を除数と同じ符号にする
;       3.ただし、除数がゼロの場合は剰余もゼロ
;
CS_div: pshx                    ; 実行位置アドレスを退避
        ldx     <CStackPtr      ; X <- 計算スタックポインタ
        bsr     div_uint        ; 除算実行
        xgdx                    ; D <- 商（Quotient） X <- 剰余（Remainder）
        tst     <QuoSignFlag    ; 商の符号チェック
        beq     :end            ; '+'なら終了
        cpx     #0              ; 剰余はゼロか？
        beq     :sign
        addd    #1              ; ゼロでなければ商に1を足す
.sign   coma                    ; Dレジスタの値を2の補数にする
        comb
        addd    #1
.end    ldx     <CStackPtr      ; X <- 計算スタックポインタ
        bra     CS_store

CS_mod: pshx                    ; 実行位置アドレスを退避
        ldx     <CStackPtr      ; X <- 計算スタックポインタ
        bsr     div_uint        ; 除算実行。D = 剰余
        std     <Remainder      ; 剰余はゼロか？
        beq     :end            ; ゼロであれば終了
        tst     <QuoSignFlag    ; 被除数・除数の符号一致チェック
        beq     :sign           ; 0なら一致しているので剰余の符号チェック
        ldd     <Divisor        ; 1なら一致していないので除数 - 剰余
        subd    <Remainder
.sign   tst     <RemSignFlag    ; 剰余の符号チェック
        beq     :end            ; '+'なら終了
        coma                    ; '-'なら2の補数にする
        comb
        addd    #1
.end    ldx     <CStackPtr      ; X <- 計算スタックポインタ
        bra     CS_store

div_uint: 
.Counter        .eq     UR0H
        ldd     0,x             ; ゼロ除算チェック
        beq     :err08          ; 除数がゼロならエラー
        clrb
        stab    <QuoSignFlag    ; 商の符号フラグを初期化
        stab    <RemSignFlag    ; 剰余の符号フラグを初期化
        ldab    #16             ; ループカウンターをセット（16bit分）
        stab    <:Counter
        ; // 剰余の符号フラグの設定
        ldd     0,x             ; Dレジスタに除数を代入
        bpl     :1              ; 除数が正であれば剰余の符号は正（0）
        inc     <RemSignFlag    ; 除数が負であれば剰余の符号は負（1）
        ; // 商の符号フラグの設定
.1      eora    2,x             ; 被除数の符号と除数の符号のXORを取る
        bpl     :2              ; 被除数と除数の符号が同じなら商の符号は正（0）
        inc     <QuoSignFlag    ; 被除数と除数の符号が違えば商の符号は負（1）
        ; // 除数を絶対値にする
.2      ldd     0,x             ; D <- 除数
        bpl     :3
        coma                    ; 除数が負なら絶対値にする
        comb
        addd    #1
.3      std     <Divisor        ; 除数を保存
        ; // 非除数を絶対値にする
        ldd     2,x             ; D <- 被除数
        bpl     :4
        coma                    ; 被除数が負なら絶対値にする
        comb
        addd    #1
        ; // 除算実行
.4      xgdx                    ; X <- 被除数
        clra                    ; D（WORK）をクリア
        clrb
.loop   xgdx                    ; X（被除数）を左シフト
        asld
        xgdx
        rolb                    ; 被除数のMSBをWORKのLSBに代入
        rola
        subd    <Divisor        ; WORK - 除数
        inx                     ; XレジスタのLSBを1にセットしておく
        bcc     :5              ; WORKから除数を引けた？
        addd    <Divisor        ; 引けなければ除数を足して...
        dex                     ; XレジスタのLSBを0に戻す
.5      dec     <:Counter       ; ループカウンターを1引く
        bne     :loop
        rts
.err08  ldaa    #8              ; "Zero Divide"
        jmp     write_err_msg


; -----------------------------------------------------------------------
; テキストバッファの10進文字列から数値を取得する
; Get a integer from a decimal string in a text buffer
;【引数】X:バッファアドレス
;【使用】A, B, X, UR0, UR1
;【返値】真(C=1) / D:Integer X:次のバッファアドレス
;        偽(C=0) / B:現在の位置のアスキーコード X:現在のバッファアドレス
; -----------------------------------------------------------------------
get_int_from_decimal:
.RetValue       .eq     UR0     ; Return Value
.TempValue      .eq     UR1     ; Temporary Value
        clra
        clrb
        std     <:RetValue
        staa    <:TempValue
        staa    <SignFlag
        ldab    0,x             ; 1文字取得
        cmpb    #'-'            ; マイナス記号か？
        bne     :1
        inc     <SignFlag       ; Yes. 符号フラグをセット
        bra     :next
.1      cmpb    #'+'            ; プラス記号か？
        beq     :next
        jsr     is_decimal_char ; 数字か？
        bcc     :false          ; No. C=1で終了
        bra     :first
.next   inx                     ; 符号の次の1文字を取得
        ldab    0,x
        jsr     is_decimal_char ; 数字か？
        bcc     :err04          ; No. エラー処理へ
        bra     :first          ; Yes. これが最初の数字
.loop   std     <:RetValue      ; 結果を退避
        ldab    0,x             ; 1文字取得
        jsr     is_decimal_char ; 数字か？
        bcc     :end
.first  subb    #$30            ; アスキーコードを数値にする
        stab    <:TempValue+1
      ; // RetValue * 10 + TempValue
        ldd     <:RetValue
        asld                    ; * 2
        asld                    ; * 4
        addd    <:RetValue      ; * 5
        asld                    ; * 10
        addd    <:TempValue     ; += TempValue
        inx                     ; ポインタを進める
        bcs     :err02          ; addd <:TempValue でC=1になったら桁が大きすぎ
        bmi     :overflow       ; 同じくN=1なら-32,768かどうか判定
        bra     :loop
.end    ldd     <:RetValue      ; D <- 結果の数値（Integer）
        tst     <SignFlag       ; 符号チェック
        beq     :true
        coma                    ; 負なら2の補数に
        comb
        addd    #1
.true   sec
.false  rts

.overflow
      ; // -32,768かどうかの判定
        xgdx
        cpx     #$8000          ; 数値は$8000 （-32,768）か？
        xgdx
        bne     :err02          ; No. 範囲外
        tst     <SignFlag       ; 符号チェック
        beq     :err02          ; 正ならば範囲外
        bra     :loop           ; 負ならば-32,768で範囲内なので元に戻る

.err02  ldaa    #2              ; "Out of range"
        jmp     write_err_msg
.err04  ldaa    #4              ; "Illegal expression"
        jmp     write_err_msg


; -----------------------------------------------------------------------
; Dレジスタの数値をコンソールに出力する
; Write Decimal Character converted from Integer
;【引数】D:Integer
;【使用】A, B, X
;【返値】なし
; -----------------------------------------------------------------------
write_integer:
.ZeroSuppress   .eq     UR0H    ; ゼロサプレスフラグ
.Counter        .eq     UR0L    ; 桁カウンター
        bpl     :plus           ; 符号判定
        pshb                    ; 負数なら'-'を出力する
        ldab    #'-'
        jsr     write_char
        pulb
        coma                    ; 絶対値にする（2の補数にする）
        comb
        addd    #1
.plus   clr     <:ZeroSuppress
        ldx     #:CONST
.loop   clr     <:Counter
.digit  subd    0,x             ; Dレジスタから桁ごとの数値を引く
        bcs     :write
        inc     <:Counter       ; 引けた回数をカウントする
        bra     :digit
        
.write  addd    0,x             ; Dレジスタから引きすぎた分を戻す
        pshb
        ldab    <:Counter
        beq     :1              ; この桁はゼロか？
        inc     <:ZeroSuppress  ; No. ゼロサプレスフラグをセットする
.1      tst     <:ZeroSuppress  ; セロサプレスフラグが立っている？
        beq     :2              ; No. この桁は表示しない
        addb    #$30            ; Yes. この桁を表示する
        jsr     write_char
.2      pulb
        inx                     ; 次の引く数へ
        inx
        cpx     #:CONST+8
        bne     :loop
        addb    #$30            ; 一の桁の数値を表示
        jmp     write_char
; Dから引いていく数
.CONST  .dw     $2710           ; 10,000
        .dw     $03e8           ; 1,000
        .dw     $0064           ; 100
        .dw     $000a           ; 10


; -----------------------------------------------------------------------
; テキストバッファの英文字が変数か判定する
; Is a character retrieved from a text buffer a variable?
;【引数】X:バッファアドレス
;【使用】A, B, X
;【返値】真(C=1) / B:変数のアスキーコード X:次のバッファアドレス
;        偽(C=0) / B:現在の位置のアスキーコード X:現在のバッファアドレス
; -----------------------------------------------------------------------
is_variable:
        ldab    0,x
        jsr     is_alphabetic_char
        bcc     :end
        tba                             ; 1文字目のアスキーコードを退避
        ldab    1,x                     ; 2文字目を取得
        jsr     is_alphabetic_char      ; 2文字もアルファベットか？
        tab                             ; 1文字目のアスキーコードを復帰
        bcc     :var                    ; No. 英文字1字なので変数である
        clc                             ; Yes. 変数ではない。C=0
        rts
.var    inx                             ; ポインタを進める
        sec                             ; C=1
.end    rts


; -----------------------------------------------------------------------
; 空白を読み飛ばす
; Skip Space
;【引数】X:実行位置アドレス
;【使用】B, X
;【返値】B:アスキーコード（$00の時Z=1）
;        X:実行位置アドレス
; -----------------------------------------------------------------------
skip_space: 
        ldab    0,x
        beq     :end
        cmpb    #SPACE
        bhi     :end
        inx
        bra     skip_space
.end    rts


; -----------------------------------------------------------------------
; 式を評価して変数に値を代入する
; Evaluate an expression and assign a value to a variable
;【引数】X:実行位置アドレス *VarAddress:変数のアドレス
;【使用】A, B, X（関連ルーチンでUR0, UR1）
;【返値】D:Integer X:次の実行位置アドレス
; -----------------------------------------------------------------------
exe_let:
        jsr     skip_space
        jsr     eval_expression
        bcc     :err04
        pshx                    ; 実行位置アドレスを退避
        ldx     <VariableAddr
        std     0,x             ; 変数に結果を保存
        pulx                    ; 実行位置アドレスを復帰
        jmp     tb_main
.err04  ldaa    #4              ; "Illegal expression"
        jmp     write_err_msg


; -----------------------------------------------------------------------
; 引用符付きの文字列を出力する
; Write Quoted Stirng
;【引数】B:アスキーコード X:実行位置アドレス
;【使用】A, B, X
;【返値】真(C=1) / X:次の実行位置アドレス
;        偽：引用符がない(C=0) / X:現在の実行位置アドレス
; -----------------------------------------------------------------------
write_quoted_str:
        cmpb    #$22            ; 一重引用符か？
        beq     :1
        cmpb    #$27            ; 二重引用符か？
        bne     :false          ; 引用符がなければC=0にしてリターン
.1      tba                     ; Aレジスタに引用符の種類を保存しておく
      ; // 終端の引用符をチェック
        pshx
.check  inx
        ldab    0,x
        beq     :err10          ; 終端文字なら"Print Statement Error"
        cba
        bne     :check
        pulx
      ; // 文字列の出力
.loop   inx
        ldab    0,x
        cba                     ; 保存した引用符との比較
        beq     :true           ; 文字列前後の引用符が一致すれば終了処理
        jsr     write_char
        bra     :loop
.true   inx
        sec
        rts
.false  clc
        rts
.err10  ldaa    #10             ; "Print statement error"
        jmp     write_err_msg


; -----------------------------------------------------------------------
; Print文を実行する
; Execute 'print' statement
;【引数】X:実行位置アドレス
;【使用】B, X（下位ルーチンでA）
;【返値】なし
; -----------------------------------------------------------------------
exe_print:
        jsr     skip_space
        jsr     write_quoted_str ; 引用符があれば文字列を出力する
        bcc     :err00
        jsr     write_crlf
        jmp     tb_main
.err00  clra                    ; "Syntax error"
        jmp     write_err_msg


; -----------------------------------------------------------------------
; input文を実行する
; Execute 'input' statement
; -----------------------------------------------------------------------
exe_input:
        pshx
        ldx     #:MSG
        jsr     write_line
        pulx
        jmp     tb_main
.MSG    .az     "Execute 'input' statement",#CR,#LF


; -----------------------------------------------------------------------
; if文を実行する
; Execute 'if' statement
; -----------------------------------------------------------------------
exe_if:
        pshx
        ldx     #:MSG
        jsr     write_line
        pulx
        jmp     tb_main
.MSG    .az     "Execute 'if' statement",#CR,#LF


; -----------------------------------------------------------------------
; テーブル検索
; Search the keyword table
;【引数】X:テーブルの先頭アドレス, *ExePointer:実行位置アドレス
;【使用】A, B, X
;【結果】真(C=1) / 命令文実行. X:次の実行位置アドレス
;        偽(C=0) / 何もせずにリターン X:引数*ExePointer（実行位置アドレス）
; -----------------------------------------------------------------------
search_table:
.top    ldd     5,x             ; キーワードの初めの2文字をDレジスタに
        cmpa    <COMPARE        ; 1文字目を比較
        bne     :false
        cmpb    <COMPARE+1      ; 2文字目を比較
        bne     :false
        ldd     7,x             ; 次の2文字をDレジスタに
        tsta                    ; $00（終端記号）か？
        beq     :true
        cmpa    <COMPARE+2      ; 3文字目を比較
        bne     :false
        tstb                    ; $00（終端記号）か？
        beq     :true
        cmpb    <COMPARE+3      ; 4文字目を比較
        bne     :false
        ldd     9,x             ; 次の2文字をDレジスタに
        tsta                    ; $00（終端記号）か？
        beq     :true
        cmpa    <COMPARE+4      ; 5文字目を比較
        bne     :false
        tstb                    ; $00（終端記号）か？
        beq     :true
        cmpb    <COMPARE+5      ; 6文字目を比較
        bne     :false
.true   ldab    2,x             ; B = 語長
        ldx     3,x             ; X = 命令ルーチンのアドレス
        ins                     ; 元のリターンアドレスを削除
        ins
        pshx                    ; スタックトップにリターンアドレスを積む
        ldx     <ExePointer
        abx                     ; 実行位置アドレスを文字数分プラスする
        rts                     ; 命令ルーチンにジャンプ
.false  ldx     0,x             ; リンクポインタを読み込み、次のキーワードに
        bne     :top
        ldx     <ExePointer     ; マッチしなければ実行位置ポインタを元に戻す
        clc                     ; false: C=0
        rts


; ***********************************************************************
;   キーワードテーブル Keyword table
; ***********************************************************************
; レコードの構造 Record structure
; +--------+--------+--------+--------+--------+------+-~-+------+--------+
; | リンクポインタ  |  語長  |命令ルーチン位置 |   キーワード    |  終端  |
; |   Link pointer  | Length |Execution address|     Keyword     |  $00   |
; +--------+--------+--------+--------+--------+------+-~-+------+--------+
; キーワードは2文字以上6文字以下
SMT_TABLE:      .eq     *
.print          .dw     :input
                .db     5
                .dw     exe_print
                .az     "print"
.input          .dw     :if
                .db     5
                .dw     exe_input
                .az     "input"
.if             .dw     :bottom
                .db     2
                .dw     exe_if
                .az     "if"
.bottom         .dw     $0000           ; リンクポインタ$0000はテーブルの終端


; -----------------------------------------------------------------------
; エラーメッセージを表示する
; Write Error Messege
;【引数】A: エラーコード
;【使用】A, B, X
;【返値】なし
; -----------------------------------------------------------------------
write_err_msg:
        ldx     #ERRMSG
        jsr     write_line
        tab
        ldx     #ERRCODE
        abx
        ldx     0,x
        jsr     write_line
        jsr     write_crlf
        ldx     <StackPointer
        txs
        jmp     tb_main

ERRMSG  .az     "ERROR: "
ERRCODE .dw     .err00
        .dw     .err02
        .dw     .err04
        .dw     .err06
        .dw     .err08
        .dw     .err10
.err00  .az     "Syntax error"
.err02  .az     "Out of range value"
.err04  .az     "Illegal expression"
.err06  .az     "Calculate stack overflow"
.err08  .az     "Zero Divide"
.err10  .az     "Print statement error"


; ***********************************************************************
;   デバック用ルーチン Debugging routines
; ***********************************************************************
; -----------------------------------------------------------------------
; ユーザーレジスタを表示する
; Display user registers
; -----------------------------------------------------------------------
PUTUR:  psha
        pshb
        pshx
        ldx     #:MSGUR0
        jsr     write_line
        ldd     <UR0
        jsr     write_word
        ldx     #:MSGUR1
        jsr     write_line
        ldd     <UR1
        jsr     write_word
        jsr     write_crlf
        pulx
        pulb
        pula
        rts
.MSGUR0          .az     "UR0="
.MSGUR1          .az     " UR1="
