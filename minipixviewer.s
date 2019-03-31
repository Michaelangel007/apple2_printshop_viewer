; PrintShop / MiniPix Unpacker and Viewer
; Version 5, March 31, 2019
; Copyleft Michaelangel007
; "Sharing is Caring"


; === Our Zero Page Variables ===

zSrcPtr     = $F7 ; 16-bit pointr to source packed PrintShop graphic
zSrcBits    = $F9
zSrcMask    = $FA ; counter 0 .. 7
zSrcCol     = $FB ; cache of Y reg for lda (zSrcPtr),Y

zDstPtr     = $26 ; 16-bit pointer to dest; GBASL

zDstRow     = $FC
zDstBits    = $FD
zDstColMod7 = $FE
zDstRowMod3 = $FF


; === PrintShop ===

PrintShopSprite = $5800 ; Default load adddress
;LEN            =   572 ; File size

; Dimensions
W_PIXELS = 88
W_BYTES  = 88/8     ; Source (Packed) Bytes/Row
H_PIXELS = 52

X_SCALE  = 2        ; Not actually used as hard-coded. For reference
Y_SCALE  = 3


; === Applesoft/Monitor Zero Page Variables ===

MON_GBAS  = $26     ; 16-bit Pointer to HGR scanline

HGR_COLOR = $E4     ;
HGR_HORIZ = $E5     ; X column / 7 = scanline byte offset
HGR_PAGE  = $E6     ; $20 or $40


; === I/O Softswitches ===

TXTCLR   = $C050    ; Graphics mode
TXTSET   = $C051

MIXCLR   = $C052    ; Split screen
MIXSET   = $C053    ; Full screen

PAGE1    = $C054
PAGE2    = $C055

LORES    = $C056
HIRES    = $C057


; === Applesoft/Monitor ROM ===

HGR       = $F3E2 ; Clear and View HGR with mixed text/graphics
HCLR      = $F3F2
HPOSN     = $F411 ; Set GBASL, GBASH, MON.HMASK, HGR.BITS ; uses HGR.PAGE, 
MOVE.DOWN = $F505 ; Update GBASL, GBASH
COLORTBL  = $F6F6 ; byte colors[7]
HCOLOR    = $F6E9

HOME      = $FC58

; =====================================================================

        ORG $6000

PrintShopViewer

        jsr HGR
        sta MIXCLR      ; Full screen

        ldx #>PrintShopSprite
        ldy #<PrintShopSprite
        stx zSrcPtr+1
        sty zSrcPtr+0

; Src PS 2x is 88 * 2x scaling = 176 pixels
; Dstr HGR screen is 40 columns * 7 px/col = 280 pixels
; =====================================================================

; Horz Centering: 
;    = (280 - W_PIXELS*X_SCALE)/2
;    = (280 - 88*2)/2
;    = 52 px/col
;    = 52 px / 7px/col
;    = 7.42... = scanline offset
;
; 52 px mod 7 px/byte
;    = 52 mod 7
;    = 3
CENTER_X = 52
X_MOD_7  =  1  ; Since each pixel is doubled we need to divide (52 mod 7) / 2

; Vert Centering:
;    = (192 - H_PIXELS*Y_SCALE)/2
;    = (192 - 52*3)/2
;    = (192 - 156) / 2 
;    = 18
CENTER_Y = {192 - {H_PIXELS*Y_SCALE}}/2

; DEBUG -- Same x,y as PrintShop Graphic Editor
;CENTER_Y = 23
;CENTER_X = 0


; Image will be centered on screen
; HGR does NOT need to be cleared to black as we set each byte to zero
; ==========
UnpackToScreenHGR
        lda #CENTER_Y       ; y = 18
        sta zDstRow
        ldy #0              ; HPOSN: column = Y,X
        sty HGR_COLOR       ; 0 = Black

:NextTripleY
        sty zDstRowMod3     ; Do y scaling

:NextSrcRow
        ldx #CENTER_X       ; HPOSN: column = y,X
        lda zDstRow         ; HPOSN: row = A
        jsr HPOSN + 6       ; We don't use HGR.X .. HGR.Y @ $E0 .. $E2
        tay                 ; on exit A = HGR.COLOR = 0 @ $F450
        sta zSrcCol         ; Y = zSrcCol
        sta zDstBits

        clc                 ; GBAS points to start of scanline
        lda HGR_HORIZ       ; Take X column into account
        adc zDstPtr
        sta zDstPtr

        ldx #X_MOD_7        ; LDX Can be optimized out if x mod 7 is 0
        stx zDstColMod7     ; 

:NextSrcByte
        lda #1              ; Unpack 8 bits since source = monochrome 8 bits/pix
        sta zSrcMask

        lda (zSrcPtr),y     ; Loop Invariant: Y = zSrcCol
        sta zSrcBits

:UnpackSrcBits              ; same source byte
        asl zSrcBits
        lda zDstBits
        bcs :PutOne
:PutZero                    ; 0 = white
        ora Column2ColorHGR,X
        sta zDstBits
:PutOne                     ; 1 = black
                            ; nothing to do since zDstBits initialized to zero
        inx
        cpx #4
        beq :NextDstByte
        cpx #7
        bne :SameDstByte

:NextDstByte
        sty zSrcCol         ; 65C02: PHY
        jsr PutHgrByte
        sta zDstBits
        ldy zSrcCol         ; 65C02: PLY

        inc zDstPtr + 0
        cpx #7
        bne :SameDstByte
        ldx #0
        stx zDstColMod7

:SameDstByte
        asl zSrcMask
        bcc :UnpackSrcBits  ; After 8 loops

        iny
        sty zSrcCol
        cpy #W_BYTES
        bcc :NextSrcByte

        lda zDstBits        ; 
;        ldy #0              ; Need Y=0 for :NextSrcRow --> col = Y,X
;        sta (zDstPtr),Y     ; Need last pixel on this scanline
        jsr PutHgrByte

; Repeat each src line 3 times       
        inc zDstRow
        inc zDstRowMod3
        ldx zDstRowMod3
        cpx #3
        bne :NextSrcRow     ; Y = 0 --> col = Y,X

        clc                 ; Move to next linear source row
        lda #W_BYTES
        adc zSrcPtr + 0     
        sta zSrcPtr + 0
        bcc :SameSrcPage
:NextSrcPage
        inc zSrcPtr + 1
:SameSrcPage
        
        lda zDstRow
        cmp #H_PIXELS*Y_SCALE + CENTER_Y
        bne :NextTripleY
:Done
        rts

PutHgrByte
        pha                 ; Save High Bit
        and #$7f            ; HGR = 7 bits/pixel as we don't want half-pixels
        ldy #0              ; Need Y=0 for :NextSrcRow --> col = Y,X
        sta (zDstPtr),Y     ; Need last pixel on this scanline
        pla                 ; Restore High Bit
        rol                 ; C = Bit 7 propogate
        lda #0              ; into next dst byte bit 0
        rol
        beq :NoCarry        ; if we have high bit crossing even into odd column
        cpx #4
        bne :NoCarry
        lda #3              ; then we also need to the bottom 2 bits
:NoCarry        
        rts

; Single Pixel to Double Pixel
Column2ColorHGR

         DB %00000110 ; [0] = $06 Even Column
         DB %00011000 ; [1] = $18
         DB %01100000 ; [2] = $60
         DB %10000000 ; [3] = $80
         DB %00001100 ; [4] = $0C Odd Column
         DB %00110000 ; [5] = $30
         DB %11000000 ; [6] = $C0
