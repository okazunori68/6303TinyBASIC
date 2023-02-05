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
SignFlag        .bs     1       ; 符号フラグ '+' = 0, '-' = 1

; General-Purpose Registers
UR0             *
UR0H            .bs     1
UR0L            .bs     1
UR1             *
UR1H            .bs     1
UR1L            .bs     1

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
        ldx     #Rx_BUFFER
        jsr     skip_space
        jsr     get_int_from_decimal
        bcs     :1
        bra     :err
.1      jsr     write_integer
        jsr     write_crlf
        bra     tb_main

.err    ldx     #MSG
        jsr     write_line
        bra     tb_main

MSG     .az     "It isn't a decimal number.",#CR,#LF


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
ERRCODE .dw     .0
        .dw     .2
        .dw     .4
.0      .az     "Syntax error"
.2      .az     "Out of range value"
.4      .az     "Illegal expression"


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
