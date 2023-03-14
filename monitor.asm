;
; * Monitor for SBC6303
; *
; * Copyright (c) 2023 okazunori
; * Released under the MIT license
; * http://opensource.org/licenses/mit-license.php
; *
; * Use SB-Assembler
; * https://github.com/sbprojects/sbasm3
;
        .cr     6301            ; HD6301 Cross Overlay
        .tf     monitor.hex,int ; Target File Name
        .lf     monitor         ; List File Name

; ***********************************************************************
;   HD6303R Internal Registers
; ***********************************************************************
        .in     ./HD6303R_chip.def

; ***********************************************************************
;   定数 Constants
; ***********************************************************************
NUL             .eq     $00     ; NUL
BS              .eq     $08     ; Backspace
SPACE           .eq     $20     ; Space
CR              .eq     $0d     ; Carriage Return
LF              .eq     $0a     ; Line Feed
DEL             .eq     $7f     ; Delete
XON             .eq     $11     ; DC1
XOFF            .eq     $13     ; DC3

RAM_START       .eq     $0020
RAM_END         .eq     $1fff
ROM_START       .eq     $e000
ROM_END         .eq     $ffff
PROGRAM_START   .eq     $1000   ; プログラム開始アドレス
STACK           .eq     $0fff

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
TabCount        .bs     1       ; タブ用の文字数カウンタ
RxBffrQty       .bs     1       ; 受信バッファデータ数
RxBffrReadPtr   .bs     2       ; 受信バッファ読み込みポインタ
RxBffrWritePtr  .bs     2       ; 受信バッファ書き込みポインタ
; General-Purpose Registers
R0              .bs     2
R1              .bs     2

; ***********************************************************************
;   システムワークエリア System work area
; ***********************************************************************
        .sm     RAM
        .or     $0100
; 各種バッファ
Rx_BUFFER       .bs     64      ; 受信バッファ（$0100-$013f）
Rx_BUFFER_END   .eq     *-1
Rx_BFFR_SIZE    .eq     Rx_BUFFER_END-Rx_BUFFER+1
TEXT_BFFR       .bs     73      ; テキストバッファ（$0140-$188: 73byte）
TEXT_BFFR_END   .eq     *-1
TEXT_BFFR_SIZE  .eq     TEXT_BFFR_END-TEXT_BFFR+1

; ***********************************************************************
;   初期化 Initialize
; ***********************************************************************
        .sm     CODE
        .or     ROM_START

init_sbc6303:
      ; // 割り込み禁止
        sei
      ; // スタックポインタ設定
        lds     #STACK
      ; // PORT設定
        ldab    #$ff            ; 全ポート -> 出力
        stab    <DDR1
      ; // 内蔵RAM無効
        aim     #~RAME,<RAMCR
      ; // SCI設定
        ldab    #E128|NRZIN     ; 9,600bps
        stab    <RMCR
        ldab    #TE|RE|RIE      ; SCIおよび受信割り込み有効化
        stab    <TRCSR
        ldab    <RDR            ; 空読み
      ; // Interrupt Vector Hooking設定
      ; // Swi,Trapはレジスタ値表示後、モニタに戻る
        ldaa    #$7e            ; '$7e' = jmp
        ldx     #trap_routine
        staa    <VEC_TRAP
        stx     <VEC_TRAP+1
        ldx     #swi_routine
        staa    <VEC_SWI
        stx     <VEC_SWI+1
      ; // SCIは受信のみ割り込み処理
        ldx     #rx_interrupt
        staa    <VEC_SCI
        stx     <VEC_SCI+1
      ; // その他の割り込みはそのままrti
        ldaa    #$3d            ; '$3d' = rti
        staa    <VEC_TOF
        staa    <VEC_OCF
        staa    <VEC_ICF
        staa    <VEC_IRQ
        staa    <VEC_NMI
      ; // 各種ポインタ、フラグ初期化
        clra
        staa    <BreakPointFlag
        staa    <RxBffrQty
        ldx     #Rx_BUFFER
        stx     <RxBffrReadPtr
        stx     <RxBffrWritePtr
      ; // 割り込み許可
        cli
      ; // スタートメッセージ出力
        ldx     #MSG_START
        jsr     write_line
        bra     mon_main

; -----------------------------------------------------------------------
; rコマンド：Break Pointフラグ（SWI,TRAP）が立っている場合のみrti
; -----------------------------------------------------------------------
return_program:
        tst     <BreakPointFlag
        beq     mon_main:retry
        clr     <BreakPointFlag
        pshb
        ldab    #'r'
        jsr     write_char
        jsr     write_crlf
        pulb
        rti

; ***********************************************************************
;   メインルーチン Main Routine
; ***********************************************************************
mon_main:
        ldx     #MSG_MON_COMMAND
        jsr     write_line
        tst     <BreakPointFlag
        beq     :1
        ldx     #MSG_MON_RTI
        jsr     write_line
.1      ldx     #MSG_MON_PROMPT ; プロンプト表示
        jsr     write_line
.retry  jsr     read_char       ; 一文字入力
        cmpb    #'r'
        beq     return_program
        jsr     is_hexadecimal_char     ; 16進数文字であればメモリダンプ
        bcs     dump_memory
        cmpb    #'l'
        beq     load_srecord
        bra     :retry

; -----------------------------------------------------------------------
; dコマンド：メモリダンプ（0x00-0xff）
; -----------------------------------------------------------------------
dump_memory:
.DumpAddress    .eq     R0
.DumpColCount   .eq     R1
        jsr     write_char      ; echo
      ; // ヘッダー出力
        tba                     ; コマンド(0-f)をAレジスタに移動
        ldx     #MSG_DUMP_HEAD
        jsr     write_line

        ldab    #$10
        stab    <:DumpColCount  ; Column ループカウンタ設定

      ; // アドレス計算
        cmpa    #'a'
        bcs     :0_9
        suba    #$27            ; "a-f"ならば$27を引く
.0_9    suba    #$30            ; 数値に変換 = 上位8bit
        clrb                    ; 下位8bit = 0
        xgdx                    ; X = Dump Address
      ; // アドレス出力
.col    stx     <:DumpAddress
        xgdx                    ; D <- DumpAddress
        jsr     write_word
        ldx     #MSG_DUMP_COLON
        jsr     write_line
      ; // データ出力
        ldaa    #$10            ; Row ループカウンタ設定
        ldx     <:DumpAddress
.data   ldab    0,x
        jsr     write_byte
        jsr     write_space
        inx
        deca                    ; ループカウンタ - 1
        bne     :data
        ldab    #'|'
        jsr     write_char
        jsr     write_space
      ; // アスキー出力
        ldaa    #$10            ; Row ループカウンタ設定
        ldx     <:DumpAddress
.ascii  ldab    0,x
        cmpb    #SPACE
        bcs     :dot
        cmpb    #DEL
        bcs     :str
.dot    ldab    #'.'
.str    jsr     write_char
        inx
        deca                    ; ループカウンタ - 1
        bne     :ascii
      ; // 一行終了
        jsr     write_crlf
        dec     <:DumpColCount
        bne     :col
      ; // 終了処理
        jsr     write_crlf
        jmp     mon_main

; -----------------------------------------------------------------------
; lコマンド：Sレコードを読み込む
; -----------------------------------------------------------------------
load_srecord:
.CheckSum       .eq     R0      ; Sレコードチェックサム
.ByteCount      .eq     R0+1    ; 転送バイト数
.LoadAddress    .eq     R1      ; 転送アドレス
        ldx     #MSG_LOAD_S19
        jsr     write_line
        bra     :reload
.loop   ldab    #'.'
        jsr     write_char
.reload jsr     read_char
        cmpb    #'S'
        bne     :reload         ; 一文字目が"S"でないならもう一度
      ; // レコードタイプの確認
        jsr     read_char
        cmpb    #'9'
        beq     :end            ; レコードタイプ"S9"ならば終了処理
        cmpb    #'1'
        bne     :reload         ; レコードタイプが"S1"でないなら再度読み込み
      ; // バイト数の確認
        bsr     :read_srecord
        stab    <:CheckSum      ; check_sum = byte_count
        subb    #3              ; アドレスとチェックサム分の3バイトを引く
        stab    <:ByteCount      ; 転送するバイト数
      ; // アドレスの確認
        bsr     :read_srecord   ; 上位アドレスを受信
        stab    <:LoadAddress
        bsr     :read_srecord   ; 下位アドレスを受信
        stab    <:LoadAddress+1
        ldx     <:LoadAddress
        ldab    <:CheckSum      ; チェックサムの計算
        addb    <:LoadAddress
        addb    <:LoadAddress+1
        stab    <:CheckSum
      ; // データ転送
.data   bsr     :read_srecord
        stab    0,x
        addb    <:CheckSum      ; チェックサムの計算
        stab    <:CheckSum
        inx
        dec     :ByteCount
        bne     :data
      ; // チェックサム確認
      ; // チェックサムは各バイト合計の1の補数
      ; // チェックサムまで全部足すと$ffになる。
        bsr     :read_srecord   ; チェックサムの受信
        addb    <:CheckSum
        incb                    ; 問題なければ $ff + 1 = $00 となるはず
        beq     :loop           ; $00なら次の行を読む
        jsr     write_crlf      ; そうでなければエラーメッセージ表示
        ldx     #ERR_BAD_RECORD
        jsr     write_line
        jmp     mon_main
      ; // 終了処理
.end    jsr     read_char
        cmpb    #LF             ; "LF"まで受信を続ける
        bne     :end
        ldx     #MSG_LOAD_OK
        jsr     write_line
        jmp     PROGRAM_START   ; PROGRAM_STARTに実行を移す
      ; // 1バイト受信する
      ; // 受信する内容は[0-9A-F]でないとならない
      ; // 大文字でないとならない（チェックしない）
.read_srecord
        jsr     read_char
        cmpb    #'A'
        bcs     :1
        subb    #7              ; "A-F"ならば$7を引く
.1      subb    #$30            ; 数値に変換
        aslb
        aslb
        aslb
        aslb
        tba                     ; Aレジスタに上位4bitをコピー
        jsr     read_char
        cmpb    #'A'
        bcs     :2
        subb    #7              ; "A-F"ならば$7を引く
.2      subb    #$30            ; 数値に変換
        aba                     ; 上位4bitと下位4bitを加算
        tab                     ; A -> B
        rts

; -----------------------------------------------------------------------
; SWI,TRAP割り込み：
; 各レジスタ値を表示後、Break Pointフラグを立ててモニタに戻る
; -----------------------------------------------------------------------
swi_routine:
        ldx     #MSG_SWI
        bra     *+5
trap_routine:
        ldx     #MSG_TRAP
        jsr     write_line
        ldx     #MSG_REG_AB     ; A:B
        jsr     write_line
        tsx
        ldaa    2,x
        ldab    1,x
        jsr     write_word
        ldx     #MSG_REG_X      ; X
        jsr     write_line
        tsx
        ldd     3,x
        jsr     write_word
        ldx     #MSG_REG_PC     ; PC
        jsr     write_line
        tsx
        ldd     5,x
        jsr     write_word
        ldx     #MSG_REG_SP     ; SP
        jsr     write_line
        tsx
        xgdx
        addd    #6
        jsr     write_word
        ldx     #MSG_REG_SP2    ; Current SP
        jsr     write_line
        tsx
        dex
        xgdx
        jsr     write_word
        ldx     #MSG_REG_CCR    ; CCR
        jsr     write_line
        tsx
        ldab    0,x
        tba                     ; Reg.A <- Reg.B
        jsr     write_byte
        ldx     #MSG_REG_FLAGS  ; Flags
        jsr     write_line
        rola
        rola
        ldx     #MSG_HINZVC
.loop   ldab    0,x
        rola
        bcs     :1
        orab    #$20            ; convert to lowercase
.1      jsr     write_char
        inx
        cpx     #MSG_HINZVC+6
        bne     :loop
        ldx     #MSG_REG_END
        jsr     write_line
        oim     #$ff,<BreakPointFlag
        cli                     ; 割り込み許可してからmainに戻る
        jmp     mon_main

; ------------------------------------------------
; SCIから一文字受信してバッファに書き込む（エラー処理はしない）
; Read one character from SCI and write it to the receive buffer
; TRCSR = RDRF|ORFE|TDRE|RIE|RE|TIE|TE|WU
;           0    0  = 受信データなし
;           1    0  = 受信データあり
;           0    1  = フレーミングエラー
;           1    1  = オーバーランエラー
; ------------------------------------------------
rx_interrupt:
        tim     #ORFE,<TRCSR            ; SCIステータスレジスタのORFEフラグ確認
        beq     :read
        ldab    <RDR                    ; 空読み（ORFEフラグのクリア）
        bra     :end
.read   ldaa    <RDR                    ; **Aレジスタ**に読み込んだデータを保存しておく
      ; // バッファオーバーフローの確認
        ldab    <RxBffrQty
        cmpb    #Rx_BFFR_SIZE
        beq     :end
      ; // リングバッファの残りの確認
        incb                            ; データ数 +1
        stab    <RxBffrQty
        cmpb    #Rx_BFFR_SIZE-16        ; リングバッファの残りバイトは16以下か？
        bne     :write                  ; No. データ書き込み
        ldab    #XOFF                   ; Yes. XOFF送出
        jsr     write_char
      ; // 受信データの書き込み
.write  ldx     <RxBffrWritePtr
        staa    0,x
        inx
        xgdx                            ; Ring buffer write pointer の下位8bitを$39でマスク
        andb    #Rx_BFFR_SIZE-1
        xgdx
        stx     <RxBffrWritePtr
.end    rti

; ***********************************************************************
;   サービスルーチン Service Routine
; ***********************************************************************

; ------------------------------------------------
; 受信バッファから一文字読み出す
; Read one character from the receive buffer
;【引数】なし
;【使用】B, X
;【返値】B:アスキーコード
; ------------------------------------------------
read_char:
        pshx
.loop   ldab    <RxBffrQty              ; データ数が1以上になるまでループ
        beq     :loop
        sei
        ldab    <RxBffrQty              ; 再度データ数を読み込み
        decb                            ; データ数 -1
        stab    <RxBffrQty
        cli
        cmpb    #16                     ; リングバッファのデータ数は16以下か？
        bne     :read                   ; No. データ書き込み
        ldab    #XON                    ; Yes. XON送出
        bsr     write_char
.read   ldx     <RxBffrReadPtr
        ldab    0,x
        inx
        xgdx                            ; buffer Read pointer の下位8bitを$39でマスク
        andb    #Rx_BFFR_SIZE-1
        xgdx
        stx     <RxBffrReadPtr
        pulx
        rts

; ------------------------------------------------
; 受信バッファから一行分の文字列をテキストバッファに読み出す（終端記号$00）
; エコー、改行付き。改行コードは「CRLF」または「LF」
; Read a string from the receive buffer and write it to the text buffer
;【引数】なし
;【使用】B, X
;【返値】B:Null, X:テキストバッファ終了位置
; ------------------------------------------------
read_line:
        ldx     #TEXT_BFFR
.loop   bsr     read_char
        cmpb    #BS             ; 入力文字がBSならば…
        beq     :bs             ; バックスペース処理へ
        cmpb    #LF             ; LF?
        beq     :end
        cmpb    #DEL            ; b >= DEL ?
        bcc     :loop           ; なにもしない
        cmpb    #SPACE          ; b < SPACE ?
        bcs     :loop           ; なにもしない
        cpx     #TEXT_BFFR_END  ; バッファ終端チェック
        beq     :loop           ; 73文字目ならなにもしない
        bsr     write_char      ; echo
        stab    0,x             ; バッファに文字を収納
        inx                     ; ポインタを進める
        bra     :loop           ; 次の文字入力
      ; // バックスペース処理
.bs     cpx     #TEXT_BFFR      ; ポインタ位置が一文字目ならば…
        beq     :loop           ; なにもしない
        bsr     write_char      ; 一文字後退
        ldab    #SPACE          ; 空白を表示（文字を消去）
        bsr     write_char
        dex                     ; バッファポインタ-
        ldab    #BS             ; 一文字後退（カーソルを戻す）
        bsr     write_char
        bra     :loop
      ; // 終端処理
      ; // 文字数が72文字の時、次のアドレスを指していない
      ; // その場合はポインタを+1する。
.end    cpx     #TEXT_BFFR_END-1
        bne     :noinc
        inx
.noinc  clrb                    ; $00:終端記号
        stab    0,x
        jmp     write_crlf      ; 改行してrts

; -----------------------------------------------------------------------
; SCIに一文字送信する
; Write one character to SCI
;【引数】B:アスキーコード
;【返値】B:元のアスキーコード
; -----------------------------------------------------------------------
write_char:
.top    tim     #TDRE,<TRCSR
        beq     :top            ; TDRE=0だったら出力を待つ
        stab    <TDR
        inc     <TabCount       ; タブ文字カウンタを+1する
        cmpb    #LF             ; 改行（LF）ならカウンタをクリア
        bne     :end
        clr     <TabCount
.end    rts


; -----------------------------------------------------------------------
; SCIに文字列を送信する（終端記号$00）
; Write a string to SCI
;【引数】X:文字列の開始アドレス
;【使用】B, X
;【返値】B:Null, X:文字列の終了アドレス
; -----------------------------------------------------------------------
write_line:
.top    ldab    0,x
        beq     :end            ; nullだったら終了
        bsr     write_char
        inx
        bra     :top
.end    rts

; -----------------------------------------------------------------------
; SCIにCRLFを送信する
; Write CRLF to SCI
;【引数】なし
;【使用】B
;【返値】なし
; -----------------------------------------------------------------------
write_crlf:
        ldab    #CR
        bsr     write_char
        ldab    #LF
        bra     write_char        ; 飛び先でrts

; -----------------------------------------------------------------------
; SCIにSPを送信する
; Write a space character to SCI
;【引数】なし
;【使用】B
;【返値】なし
; -----------------------------------------------------------------------
write_space:
        ldab    #SPACE
        bra     write_char      ; 飛び先でrts

; -----------------------------------------------------------------------
; バイナリ数値(8bit)を16進数字としてSCIに送信する
; Write 8bit binary number as hexadecimal character to SCI
;【引数】B:uint8(Byte)
;【返値】なし
; -----------------------------------------------------------------------
write_byte:
      ; // 上位4ビットの出力
        pshb
        bsr     high_nibble_to_char
        bsr     write_char
      ; // 下位4ビットの出力
        pulb
        bsr     low_nibble_to_char
        bra     write_char      ; 飛び先でrts

; -----------------------------------------------------------------------
; バイナリ数値(16bit)を16進数字としてSCIに送信する
; Write 16bit binary number as hexadecimal character to SCI
;【引数】D:uint16(Word)
;【使用】A, B
;【返値】なし
; -----------------------------------------------------------------------
write_word:
        pshb
        tab
        bsr     write_byte
        pulb
        bra     write_byte      ; 飛び先でrts

; -----------------------------------------------------------------------
; バイナリ数値の上位4bitを16進文字に変換する
; Convert the upper 4 bits of a binary number to a hexadecimal character
;【引数】B:16進値
;【返値】B:アスキーコード
; -----------------------------------------------------------------------
high_nibble_to_char:
        lsrb
        lsrb
        lsrb
        lsrb
        ; continue to low_nibble_to_char
; -----------------------------------------------------------------------
; バイナリ数値の下位4bitを16進文字に変換する
; Convert the lower 4 bits of a binary number to a hexadecimal character
;【引数】B:16進値
;【返値】B:アスキーコード
; -----------------------------------------------------------------------
low_nibble_to_char:
        andb    #$0f           ; 上位4bitをマスクする
        addb    #$30           ; 数値をアスキーコードに変換する
        cmpb    #$3a
        bcs     :end
        addb    #$27           ; a-fだったらさらに$27を足して変換する
.end    rts

; -----------------------------------------------------------------------
; "a"-"z"（アスキーコード）かどうか判定
; 小文字に変換済みのこと
; Is an alphabetic charactor?
;【引数】B:アスキーコード（小文字に変換済みであること）
;【返値】真(C=1)、偽(C=0)
;        B:元のアスキーコード
; -----------------------------------------------------------------------
is_alphabetic_char:
        cmpb    #$7b    ; "z"より大きければC=0、"z"以下であればC=1。
        bcc     :end
        subb    #$61
        subb    #$9f
.end    rts

; -----------------------------------------------------------------------
; 10進数字（アスキーコード）かどうか判定
; Is a decimal character?
;【引数】B:アスキーコード
;【返値】真(C=1)、偽(C=0)
;        B:元のアスキーコード
; -----------------------------------------------------------------------
is_decimal_char:
        cmpb    #$3a    ; "9"より大きければC=0、"9"以下であればC=1。
        bcc     :end
        subb    #$30    ; -$30-$d0(-$100)で一回りさせると元の値でCフラグの挙動が変わる。
        subb    #$d0    ; "0−9"ならばC=1、それ以下のコードであればC=0。
.end    rts

; -----------------------------------------------------------------------
; 16進数字（アスキーコード）かどうか判定
; 小文字に変換済みのこと
; Is a hexaecimal character?
;【引数】B:アスキーコード（小文字に変換済みであること）
;【返値】真(C=1)、偽(C=0)
;        B:元のアスキーコード
; -----------------------------------------------------------------------
is_hexadecimal_char:
        cmpb    #$67    ; "f"より大きければC=0、"f"以下であればC=1。
        bcc     :end
        subb    #$61
        subb    #$9f
        bcs     :end
        bra     is_decimal_char
.end    rts

; ***********************************************************************
;   文字列 Strings
; ***********************************************************************
MSG_START       .az     "Tiny monitor for SBC6303",#CR,#LF,#CR,#LF
MSG_MON_COMMAND .az     "0-f:Dump l:Load"
MSG_MON_RTI     .az     " r:Return"
MSG_MON_PROMPT  .az     " > "
MSG_LOAD_S19    .az     "l",#CR,#LF,"Please send the S19 file.",#CR,#LF
MSG_LOAD_OK     .az     " Loading O.K.",#CR,#LF,"Execute the program.",#CR,#LF,#CR,#LF
MSG_DUMP_HEAD   .az     #CR,#LF,#CR,#LF,"Addr | +0 +1 +2 +3 +4 +5 +6 +7 +8 +9 +a +b +c +d +e +f | 0123456789abcdef",#CR,#LF,"-----+-------------------------------------------------+-----------------",#CR,#LF
MSG_DUMP_COLON  .az     " | "
MSG_SWI         .az     #CR,#LF,#CR,#LF,"Swi!"
MSG_TRAP        .az     #CR,#LF,#CR,#LF,"Trap!"
MSG_REG_AB      .az     #CR,#LF,"A:B="
MSG_REG_X       .az     "  X="
MSG_REG_PC      .az     "  PC="
MSG_REG_SP      .az     "  SP="
MSG_REG_SP2     .az     "(Current:"
MSG_REG_CCR     .az     ")  CCR="
MSG_REG_FLAGS   .az     "[11"
MSG_REG_END     .az     "]",#CR,#LF,#CR,#LF
MSG_HINZVC      .as     "HINZVC"
ERR_BAD_RECORD  .az     "Invalid record format.",#CR,#LF,#CR,#LF

; ***********************************************************************
;   ジャンプテーブル Service routine jump table
; ***********************************************************************
        .or     $ffa0
        jmp     init_sbc6303            ; $ffa0
        jmp     mon_main                ; $ffa3
        jmp     read_char               ; $ffa6
        jmp     read_line               ; $ffa9
        jmp     write_char              ; $ffac
        jmp     write_line              ; $ffaf
        jmp     write_crlf              ; $ffb2
        jmp     write_space             ; $ffb5
        jmp     write_byte              ; $ffb8
        jmp     write_word              ; $ffbb
        jmp     is_alphabetic_char      ; $ffbe
        jmp     is_decimal_char         ; $ffc1
        jmp     is_hexadecimal_char     ; $ffe4

; ***********************************************************************
;   割り込みベクタ Interrupt vectors
; ***********************************************************************
        .or     $ffee
        .dw     VEC_TRAP        ; Trap
        .dw     VEC_SCI         ; sci
        .dw     VEC_TOF         ; tof
        .dw     VEC_OCF         ; ocf
        .dw     VEC_ICF         ; icf
        .dw     VEC_IRQ         ; irq
        .dw     VEC_SWI         ; swi
        .dw     VEC_NMI         ; nmi
        .dw     init_sbc6303    ; Reset Vector
