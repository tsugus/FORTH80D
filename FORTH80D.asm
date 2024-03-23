; **************************************************************
; *                                                            *
; *                    F O R T H ' 7 9 +                       *
; *                                                            *
; *                    for 8086 & MS-DOS                       *
; *                    in MASM Assembly                        *
; *                                                            *
; *                      Version 0.4.2                         *
; *                                                            *
; *                                            2023  Tsugu N.  *
; *                                                            *
; *                                                            *
; *  The source materials are as follows.                      *
; *  1. "Hyo^zyun FORTH" by Toshio Inoue.                      *
; *  2. fig-FORTH by Forth Interest Group.                     *
; *                                                            *
; *  I, who am the direct writer of this program, don't claim  *
; *  this copyright.                                           *
; *                                                            *
; **************************************************************

; 				FORTH	8086
; Instruction Pointer		IP	SI
; (parameter) Stack Pointer	SP	SP
; Return stack Pointer		RP	BP
; Working register		W	DX

; stack 	:	|[INITS0-2] ... [SI+4] [SI+2] [SI]
; return stack :	|[INITR0-2] ... [BP+4] [BP+2] [BP]

; ***** Memory Map *****
;
;               |=======|
;        ORIG ->| 0100H |     program start
;               |   .   |
;               |   .   |
;               |=======|
;       LIT-6 ->| 01B2H |     start of dictionary
;               |   .   |
;               |   .   |
;      INITDP ->| ????H |     initial position of DP
;               |   .   |
;               |   .   |
;               | ----- |----
;          DP  v|   x   |  |  dictionary pointer (go under)
;               |   .   |  |  "WORD" buffer (44H bytes)
;               |   .   |  |
;               | ----- | temporary buffer area (80H bytes)
;         PAD  v| x+44H |  |
;               |   :   |  |  text buffer (36H bytes)
;               | x+79H |  |
;               | ----- |----
;               |   .   |
;               |   .   |
;               | ----- |
;          SP  ^|   .   |     stack pointer (go upper)
;               |   .   |
;               | 7B16H |     bottom of stack
;               |=======|
; INITS0, TIB ->| 7B18H |     terminal input buffer
;               |   .   |
;               |   .   |
;               | ----- |
;          BP  ^|   .   |     return stack pointer (go upper)
;               |   .   |
;               | 7BB6H |     bottom of return stack
;               |=======|
; I NITR0, UP ->| 7BB8H |     top of user variables area
;               |   :   |
;               |=======|
;       FIRST ->| 7BF8H |     top of disk buffers
;               |   :   |
;               | 7FFEH |     bottom of disk buffers
;               |=======|
;       LIMIT ->| 8000H |     out of area

; ***** Disk Buffer's Structure *****
;
;               |===========| p: update flag
;       FIRST ->| p |   n   | n: block number (15 bit)
;               |-----------| -----
;               |           |   |
;               |           |   |
;               |           |   |
;       buffer1 |    DATA   |  512 bytes
;               ~           ~   |
;               ~           ~   |
;               |           |   |
;               |-----------| -----
;               | 00H | 00H | double null charcters
;               |===========|
;               | p |   n   |
;               |-----------| -----
;               |           |   |
;               |           |   |
;               |           |   |
;       buffer2 |    DATA   |  512 bytes
;               ~           ~   |
;               ~           ~   |
;               |           |   |
;               |-----------| -----
;               | 00H | 00H |
;               |===========|
;       LIMIT ->

; ***** System Memory Configuration *****

_ORIG	EQU	100H
_BBUF	EQU	200H		; bytes per buffer
_BSCR	EQU	2		; blocks per screen
_BFLEN	EQU	_BBUF + 4	; buffer tags length = 4
_LIMIT	EQU	8000H
_NUMBUF	EQU	2		; number of disk block buffers
_FIRST	EQU	_LIMIT - _BFLEN * _NUMBUF
UP	EQU	_FIRST - 40H	; user variables area size = 40H
INITR0	EQU	UP
INITS0	EQU	INITR0 - 0A0H	; return stack size = A0H
_DRSIZ	EQU	720		; asume 720KB floppy disk

; ***************************************

codeSeg SEGMENT
	ASSUME	CS:codeSeg, DS:codeSeg
; ---------------------------------------
	ORG	100H

ORIG:	NOP
	JMP	CLD_
	NOP
	JMP	WRM

; ***** COLD & WARM *****

; COLD START

CLD_:	MOV	AX,CS
	MOV	DS,AX
	MOV	ES,AX
	MOV	SS,AX
	CLD
	MOV	SI,OFFSET CLD1		; Initialize IP.
	MOV	SP,WORD PTR UVR+6	; Initialize SP.
	MOV	BP,WORD PTR UVR+8	; Initialize RP.
	JMP	NEXT
CLD1	DW	COLD

; WARM START

WRM:	MOV	SI,OFFSET WRM1
	JMP	NEXT
WRM1	DW	WARM

; ***** USER VARIABLES *****

UVR	DW	0		; not used
	DW	0		; not used
	DW	0		; not used
	DW	INITS0		; S0
	DW	INITR0		; R0
	DW	INITS0		; TIB
	DW	31		; WIDTH
	DW	0		; WARNING
	DW	INITDP		; FENCE
	DW	INITDP		; DP
	DW	ASSEM+6		; VOC-LINK
	DW	0		; BLK
	DW	0		; >IN
	DW	0		; OUT
	DW	0		; SCR
	DW	0		; OFFSET
	DW	FORTH+4		; CONTEXT
	DW	FORTH+4		; CURRENT
	DW	0		; STATE
	DW	10		; BASE
	DW	-1		; DPL
	DW	0		; FLD
	DW	0		; CSP
	DW	0		; R#
	DW	0		; HLD
	DW	0		; PFLAG

; ***** INTERFACE (for MS-DOS) *****
; take a type-state of keybord
CTST	DW	$+2
	MOV	AH,0BH	; Is Type Ahead Buffer empty? Or not?
	INT	21H	; AL=00H or FFH
	AND	AX,1
	JMP	APUSH
; input one character from keybord
CIN	DW	$+2
	MOV	AH,7
	INT	21H
	XOR	AH,AH
	JMP	APUSH
; output one character to console
COUT	DW	$+2
	POP	DX
	MOV	AH,2
	INT	21H
	JMP	NEXT
; output one character to printer (no used)
POUT	DW	$+2
	POP	DX
	MOV	AH,5
	INT	21H
	JMP	NEXT
; read one sector on a disk
READ	DW	$+2
	POP	DX	; starting logical sector
	MOV	CX,1	; number of sectors
	POP	BX	; address of buffer
	POP	AX	; drive number
	PUSH	BP
	PUSH	SI
	INT	25H	; absolute read
	POP	CX	; drop
	POP	SI
	POP	BP
	JMP	APUSH
; write one sector on a disk
WRITE	DW	$+2
	POP	DX	; starting logical sector
	MOV	CX,1	; number of sectors
	POP	BX	; address of buffer
	POP	AX	; drive number
	PUSH	BP
	PUSH	SI
	INT	26H	; absolute write
	POP	CX	; drop
	POP	SI
	POP	BP
	JMP	APUSH

; ***** FORTH INNER INTERPRETER *****

; DPUSH		( --- DX AX )
; APUSH		( --- AX )
; NEXT		( --- )
; NEXT1		( --- )

DPUSH:	PUSH	DX		; Push DX to the (parameter) stack.
APUSH:	PUSH	AX
NEXT:	LODSW			; AX=[SI]; SI+=2
	MOV	BX,AX		; BX=AX
NEXT1:	MOV	DX,BX		; DX=BX
	INC	DX		; DX++
	JMP	WORD PTR [BX]	; goto [BX]

; ***** Word's Structure *****

;                       |=========|
;    Name Field Address |100|00100| 1 cf sf | len
;                       |---------| cf: compilation flag
;                       | 0 | "N" | sf: smudge flag
;                       |---------| len: name's length
;                       | 0 | "A" |
;                       |---------|
;                       | 0 | "M" |
;                       |---------|
;                       | 1 | "E  |
;                       |=========|
;    Link Field Address |(pointer)| -> to the NFA
;                       |         |      of the before word
;                       |=========|
;     Compilation F. A. |  DOCOL  | or DOCON, DOVAL,
;                       |   (:)   |       DOUSE, DOVOC
;                       |=========|
;      Paramatere F. A. |(word 1) |
;                       |         |
;                       |---------|
;                       |(word 2) |
;                       |         |
;                       |---------|
;                       |    .    |
;                       |    .    |
;                       |---------|
;                       |(word n) |
;                       |         |
;                       |---------|
;                       |  SEMIS  |
;                       |   (;S)  |
;                       |=========|

; ***** FORTH DICTIONARY *****

; <<< core words >>>

; LIT <n>		( --- n )

	DB	83H,"LI","T"+80H
	DW	0	; end of dictionary
LIT	DW	$+2	; the address here + 2
	LODSW		; AX=[SI]; SI+=2
	JMP	APUSH

; EXECUTE	( a --- )

	DB	87H,"EXECUT","E"+80H
	DW	LIT-6
EXEC	DW	$+2
	POP	BX	; BX=a
	JMP	NEXT1

; BRANCH <n>

	DB	86H,"BRANC","H"+80H
	DW	EXEC-10
BRAN	DW	$+2
B1:	ADD	SI,[SI]	; SI+=[SI]
	JMP	NEXT

; 0BRANCH <n>	( f --- )

	DB	87H,"0BRANC","H"+80H
	DW	BRAN-9
ZBRAN	DW	$+2
	POP	AX	; AX=f
	OR	AX,AX
	JZ	B1	; Goto B1 if zero flag is 1.
	INC	SI	; SI++
	INC	SI
	JMP	NEXT

; (LOOP)

	DB	86H,"(LOOP",")"+80H
	DW	ZBRAN-10
XLOOP	DW	$+2
	MOV	BX,1
L1:	ADD	[BP],BX
	MOV	AX,[BP]
	SUB	AX,2[BP]	; AX-[BP+2]
	XOR	AX,BX
	JS	B1	; Jump to B1 if (minus) sign flag is 1.
	ADD	BP,4
	INC	SI
	INC	SI
	JMP	NEXT

; (+LOOP)	( n  --- )

	DB	87H,"(+LOOP",")"+80H
	DW	XLOOP-9
XPLOO	DW	$+2
	POP	BX	; BX=n
	JMP	L1

; (DO)		( n1 n2 --- )

	DB	84H,"(DO",")"+80H
	DW	XPLOO-10
XDO	DW	$+2
	POP	DX
	POP	AX
	XCHG	BP,SP	; Exchange BP and SP.
	PUSH	AX
	PUSH	DX
	XCHG	BP,SP
	JMP	NEXT

; AND		( n1 n2 --- n1&n2 )

	DB	83H,"AN","D"+80H
	DW	XDO-7
ANDD	DW	$+2
	POP	AX
	POP	BX
	AND	AX,BX
	JMP	APUSH

; OR		( n1 n2 --- n1|n2 )

	DB	82H,"O","R"+80H
	DW	ANDD-6
ORR	DW	$+2
	POP	AX
	POP	BX
	OR	AX,BX
	JMP	APUSH

; XOR		( n1 n2 --- n1^n2 )

	DB	83H,"XO","R"+80H
	DW	ORR-5
XORR	DW	$+2
	POP	AX
	POP	BX
	XOR	AX,BX
	JMP	APUSH

; SP@		( --- SP )

	DB	83H,"SP","@"+80H
	DW	XORR-6
SPAT	DW	$+2
	MOV	AX,SP
	JMP	APUSH

; SP!
; initialize SP

	DB	83H,"SP","!"+80H
	DW	SPAT-6
SPSTO	DW	$+2
	MOV	BX,UP
	MOV	SP,6[BX]	; SP=[BX+6]
	JMP	NEXT

; RP@		( --- BP )

	DB	83H,"RP","@"+80H
	DW	SPSTO-6
RPAT	DW	$+2
	MOV	AX,BP
	JMP	APUSH

; RP!
; initialize RP

	DB	83H,"RP","!"+80H
	DW	RPAT-6
RPSTO	DW	$+2
	MOV	BX,UP
	MOV	BP,8[BX]	; BP=[BX+8]
	JMP	NEXT

; ;S

	DB	82H,";","S"+80H
	DW	RPSTO-6
SEMIS	DW	$+2
	MOV	SI,[BP]
	INC	BP
	INC	BP
	JMP	NEXT

; >R		( n --- )

	DB	82H,">","R"+80H
	DW	SEMIS-5
TOR	DW	$+2
	POP	BX
	DEC	BP
	DEC	BP
	MOV	[BP],BX
	JMP	NEXT

; R>		( --- n )

	DB	82H,"R",">"+80H
	DW	TOR-5
FROMR	DW	$+2
	MOV	AX,[BP]
	INC	BP
	INC	BP
	JMP	APUSH

; R@		( --- n )

	DB	82H,"R","@"+80H
	DW	FROMR-5
RAT	DW	$+2
	MOV	AX,[BP]
	JMP	APUSH

; 0=		( n --- f )

	DB	82H,"0","="+80H
	DW	RAT-5
ZEQU	DW	$+2
	POP	AX
	OR	AX,AX
	MOV	AX,1
	JZ	$+3
	DEC	AX
	JMP	APUSH

; 0<		( n --- f ; n < 0 ? )

	DB	82H,"0","<"+80H
	DW	ZEQU-5
ZLESS	DW	$+2
	POP	AX
	OR	AX,AX
	MOV	AX,1
	JS	$+3
	DEC	AX
	JMP	APUSH

; +		( n1 n2 --- n2+n1 )

	DB	81H,"+"+80H
	DW	ZLESS-5
PLUS	DW	$+2
	POP	AX
	POP	BX
	ADD	AX,BX
	JMP	APUSH

; -		( n1 n2 --- n1-n2 )

	DB	81H,"-"+80H
	DW	PLUS-4
SUBB	DW	$+2
	POP	DX
	POP	AX
	SUB	AX,DX
	JMP	APUSH

; D+		( d1 d2 --- d2+d1 )

	DB	82H,"D","+"+80H
	DW	SUBB-4
DPLUS	DW	$+2
	POP	AX
	POP	DX
	POP	BX
	POP	CX
	ADD	DX,CX
	ADC	AX,BX	; AX + BX + carry flag
	JMP	DPUSH

; D-		( d1 d2 --- d1-d2 )

	DB	82H,"D","-"+80H
	DW	DPLUS-5
DSUB	DW	$+2
	POP	BX
	POP	CX
	POP	AX
	POP	DX
	SUB	DX,CX
	SBB	AX,BX	; AX - BX - carry flag
	JMP	DPUSH

; OVER		( n1 n2 --- n1 n2 n1 )

	DB	84H,"OVE","R"+80H
	DW	DSUB-5
OVER	DW	$+2
	POP	DX
	POP	AX
	PUSH	AX
	JMP	DPUSH

; DROP		( n --- )

	DB	84H,"DRO","P"+80H
	DW	OVER-7
DROP	DW	$+2
	POP	AX
	JMP	NEXT

; SWAP		( n1 n2 --- n2 n1 )

	DB	84H,"SWA","P"+80H
	DW	DROP-7
SWAP	DW	$+2
	POP	DX
	POP	AX
	JMP	DPUSH

; DUP		( n --- n n )

	DB	83H,"DU","P"+80H
	DW	SWAP-7
DUPE	DW	$+2
	POP	AX
	PUSH	AX
	JMP	APUSH

; ROT		( n1 n2 n3 --- n2 n3 n1 )

	DB	83H,"RO","T"+80H
	DW	DUPE-6
ROT	DW	$+2
	POP	DX
	POP	BX
	POP	AX
	PUSH	BX
	JMP	DPUSH

; U*		( u1 u2 --- ud )

	DB	82H,"U","*"+80H
	DW	ROT-6
USTAR	DW	$+2
	POP	AX
	POP	BX
	MUL	BX	; DXAX=AX*BX
	XCHG	AX,DX	; Conversion to little endian.
	JMP	DPUSH

; U/		( ud u1 --- ud%u1 ud/u1 )

	DB	82H,"U","/"+80H
	DW	USTAR-5
USLAS	DW	$+2
	POP	BX
	POP	DX
	POP	AX
	CMP	DX,BX	; Carry flag is set (as DX-BX).
	JNB	U1	; Jump U1 if carry flag is 0.
	DIV	BX	; AX=DXAX/BX, DX=DXAX%BX
	JMP	DPUSH
U1:	MOV	AX,-1	; over flow
	MOV	DX,AX
	JMP	DPUSH

; 2/		( n --- n/2 )

	DB	82H,"2","/"+80H
	DW	USLAS-5
TDIV	DW	$+2
	POP	AX
	SAR	AX,1	; AX>>1 (arithmetic!!)
	JMP	APUSH

; TOGGLE	( a b --- )
; b: 8 bit pattern

	DB	86H,"TOGGL","E"+80H
	DW	TDIV-5
TOGGL	DW	$+2
	POP	AX
	POP	BX
	XOR	[BX],AL
	JMP	NEXT

; @		( a --- n )
; fetch

	DB	81H,"@"+80H
	DW	TOGGL-9
ATT	DW	$+2
	POP	BX
	MOV	AX,[BX]
	JMP	APUSH

; !		( n a --- )
; store

	DB	81H,"!"+80H
	DW	ATT-4
STORE	DW	$+2
	POP	BX
	POP	AX
	MOV	[BX],AX
	JMP	NEXT

; C!		( b a --- )

	DB	82H,"C","!"+80H
	DW	STORE-4
CSTOR	DW	$+2
	POP	BX
	POP	AX
	MOV	[BX],AL
	JMP	NEXT

; CMOVE		( a1 a2 n --- )
; [a2]=[a1], [a2+1]=[a1+1], ...., [a2+n-1]=[a1+n-1]

	DB	85H,"CMOV","E"+80h
	DW	CSTOR-5
CMOVEE 	DW	$+2
	MOV	BX,SI
	POP	CX
	POP	DI
	POP	SI
	MOV	AX,DS
	MOV	ES,AX
	CLD
	REP	MOVSB
	MOV	SI,BX
	JMP	NEXT

; <CMOVE	( a1 a2 n --- )
; [a2+n-1]=[a1+n-1], [a2+n-2]=[a1+n-2], ...., [a2]=[a1]

	DB	86H,"<CMOV","E"+80H
	DW	CMOVEE-8
LCMOVE	DW	$+2
	MOV	BX,SI
	POP	CX
	POP	DI
	POP	SI
	MOV	AX,CX
	DEC	AX
	ADD	DI,AX
	ADD	SI,AX
	MOV	AX,DS
	MOV	ES,AX
	STD
	REP	MOVSB
	CLD
	MOV	SI,BX
	JMP	NEXT

; FILL		( a n b --- )
; Fill from address a to address a+n-1 with byte b.

	DB	84H,"FIL","L"+80H
	DW	LCMOVE-9
FILL	DW	$+2
	POP	AX
	POP	CX
	POP	DI
	MOV	BX,DS
	MOV	ES,BX
	CLD		; direction flag = 0 (increase)
	REP	STOSB	; while (CX) ES:[DI]=AL;
	JMP	NEXT

; : <name>

	DB	0C1H,":"+80H
	DW	FILL-7
COLON	DW	DOCOL
	DW	QEXEC		; ?EXEC
	DW	SCSP		; !CSP
	DW	CURR		; CURRENT
	DW	ATT		; @
	DW	CONT		; CONTEXT
	DW	STORE		; !
	DW	PCREAT		; (CREATE)
	DW	RBRAC		; ]
	DW	PSCOD		; (;CODE)
DOCOL:	INC	DX
	DEC	BP
	DEC	BP
	MOV	[BP],SI
	MOV	SI,DX
	JMP	NEXT

; CONSTANT <name>	( n --- )

	DB	88H,"CONSTAN","T"+80H
	DW	COLON-4
CON	DW	DOCOL
	DW	PCREAT		; (CREATE)
	DW	SMUDG		; SMUDGE
	DW	COMMA		; ,
	DW	PSCOD		; (;CODE)
DOCON:	INC	DX
	MOV	BX,DX	; Pointer registers are only BX,BP,SI,DI!
	MOV	AX,[BX]
	JMP	APUSH

; VARIABLE <name>

	DB	88H,"VARIABL","E"+80H
	DW	CON-11
VAR	DW	DOCOL
	DW	ZERO		; 0
	DW	CON		; CONSTANT
	DW	PSCOD		; (;CODE)
DOVAR:	INC	DX
	PUSH	DX
	JMP	NEXT

; 2CONSTANT <name>	( d --- )

	DB	89H,"2CONSTAN","T"+80H
	DW	VAR-11
TCON	DW	DOCOL
	DW	CON		; CONSTANT
	DW	COMMA		; ,
	DW	PSCOD 		; (;CODE)
	INC	DX
	MOV	BX,DX
	MOV	AX,[BX]
	MOV	DX,2[BX]
	JMP	DPUSH

; 2VARIABLE <name>

	DB	89H,"2VARIABL","E"+80H
	DW	TCON-12
TVAR	DW	DOCOL
	DW	VAR		; VARIABLE
	DW	ZERO		; 0
	DW	COMMA		; ,
	INC	DX
	PUSH	DX
	JMP	NEXT

; USER <name>	( n --- )

	DB	84H,"USE","R"+80H
	DW	TVAR-12
USER	DW	DOCOL
	DW	CON		; CONSTANT
	DW	PSCOD		; (;CODE)
DOUSE:	INC	DX
	MOV	BX,DX
	MOV	BL,[BX]
	SUB	BH,BH		; BHBL => 00BL
	MOV	DI,UP		; UP is the top of user area.
	LEA	AX,[BX+DI]	; AX=BX+DI
	JMP	APUSH

; DOES>		( --- a )

	DB	0C5H,"DOES",">"+80H
	DW	USER-7
DOES	DW	DOCOL
	DW	COMP		; COMPILE
	DW	PSCOD		; (;CODE)
	DW	LIT,0E9H	; jump code ('JMP' = 0xE9)
	DW	CCOMM		; C,
	DW	LIT,XDOES-2	; XDOES-2
	DW	HERE		; HERE
	DW	SUBB		; - ("JMP a" = "E9 a-$-2")
	DW	COMMA		; ,
	DW	SEMIS
XDOES:	XCHG	BP,SP
	PUSH	SI	; SI => return stack
	XCHG	BP,SP
	MOV	SI,[BX]
	ADD	SI,3H	; "E9 xxxx" is 3 bytes.
	INC	DX	; DX is the next address in the caller.
	PUSH	DX
	JMP	NEXT

; CREATE <name>

	DB	86H,"CREAT","E"+80H
	DW	DOES-8
CREAT	DW	DOCOL
	DW	PCREAT		; (CREATE)
	DW	SMUDG		; SMUDGE
	DW	PSCOD		; (;CODE)
	INC	DX
	PUSH	DX
	JMP	NEXT

; COLD

	DB	84H,"COL","D"+80H
	DW	CREAT-9
COLD	DW	DOCOL
	DW	LIT,UVR		; Set user variables.
	DW	UPP		; UP ( constant )
	DW	LIT,52		; 52 ( 26 variables * 2 bytes )
	DW	CMOVEE		; CMOVE
	DW	EMPBUF		; EMPTY-BUFFERS
	DW	ABORT		; ABORT

; WARM

	DB	84H,"WAR","M"+80H
	DW	COLD-7
WARM	DW	DOCOL
	DW	EMPBUF		; EMPTY-BUFFERS
	DW	ABORT		; ABORT

; KEY		( --- c )

	DB	83H,"KE","Y"+80H
	DW	WARM-7
KEY	DW	DOCOL
	DW	CIN
	DW	SEMIS

; ?TERMINAL	( --- f )

	DB	89H,"?TERMINA","L"+80H
	DW	KEY-6
QTERM	DW	DOCOL
	DW	CTST
	DW	SEMIS

; EMIT		( c --- )

	DB	84H,"EMI","T"+80H
	DW	QTERM-12
EMIT	DW	DOCOL
	DW	DUPE		; DUP
	DW	COUT		; COUT
	DW	PFLAG		; print flag
	DW	ATT		; @
	DW	ZBRAN,EMIT1-$	; IF
	DW	POUT		;  POUT
	DW	BRAN,EMIT2-$	; ELSE
EMIT1	DW	DROP		;  DROP
				; THEN
EMIT2	DW	SEMIS

; READ-REC	( n1 a n2 --- ef; 1 block only)
; n1: drive number
; a : address of disk buffer
; n2: reading block (sector)
; ef: error flag (0 or -1)

	DB	88H,"READ-RE","C"+80H
	DW	EMIT-7
RREC	DW	DOCOL
	DW	READ
	DW	SEMIS

; WRITE-REC	( n1 a n2 --- ef; 1 block only )
; n1: drive number
; a : address of disk buffer
; n2: writing block (sector)
; ef: error flag (0 or 1)

	DB	89H,"WRITE-RE","C"+80H
	DW	RREC-11
WREC	DW	DOCOL
	DW	WRITE
	DW	SEMIS

; <<< constants >>> 

; ORIG 		( --- n )
; (ORIGin)

	DB	84H,"ORI","G"+80H
	DW	WREC-12
ORIGI	DW	DOCON
	DW	_ORIG

; UVR		( --- n )
; (User VaRiables)
	DB	83H,"UV","R"+80H
	DW	ORIGI-7
TUVR	DW	DOCON
	DW	UVR

; B/BUF		( --- n )
; (Bytes per BUFfer)

	DB	85H,"B/BU","F"+80H
	DW	TUVR-6
BBUF	DW	DOCON
	DW	_BBUF

; B/SCR		( --- n )
; (Bloks per SCReen)

	DB	85H,"B/SC","R"+80H
	DW	BBUF-8
BSCR	DW	DOCON
	DW	_BSCR

; BFLEN		( --- n )
; (BuFfer LENgth)

	DB	85H,"BFLE","N"+80H
	DW	BSCR-8
BFLEN	DW	DOCON
	DW	_BFLEN

; LIMIT		( --- n )

	DB	85H,"LIMI","T"+80H
	DW	BFLEN-8
LIMIT	DW	DOCON
	DW	_LIMIT

; FIRST		( --- n )

	DB	85H,"FIRS","T"+80H
	DW	LIMIT-8
FIRST	DW	DOCON
	DW	_FIRST

; UP		( --- n )

	DB	82H,"U","P"+80H
	DW	FIRST-8
UPP	DW	DOCON
	DW	UP

; BL		( --- n )
; (BLank)

	DB	82H,"B","L"+80H
	DW	UPP-5
BLS	DW	DOCON
	DW	20H		; code of ' '

; C/L		( --- n )
; (Caracters per Line)

	DB	83H,"C/","L"+80H
	DW	BLS-5
CSLL	DW	DOCON
	DW	40H

; 0		( --- 0 )

	DB	81H,"0"+80H
	DW	CSLL-6
ZERO	DW	DOCON
	DW	0H

; 1		( --- 1 )

	DB	81H,"1"+80H
	DW	ZERO-4
ONE	DW	DOCON
	DW	1H

; 2		( --- 2 )

	DB	81H,"2"+80H
	DW	ONE-4
TWO	DW	DOCON
	DW	2H

; 3		( --- 3 )

	DB	81H,"3"+80H
	DW	TWO-4
THREE	DW	DOCON
	DW	3H

; -1		( --- -1 )

	DB	82H,"-","1"+80H
	DW	THREE-4
MONE	DW	DOCON
	DW	-1H

; TIBLEN	( --- n )
; (Text Input Buffer LENgth)

	DB	86H,"TIBLE","N"+80H
	DW	MONE-5
TIBLEN	DW	DOCON
	DW	50H

; MSGSCR	( --- n )
; (MeSsaGe SCReen)

	DB	86H,"MSGSC","R"+80H
	DW	TIBLEN-9
MSGSCR	DW	DOCON
	DW	3H

; #BUFF		( --- n )
; (number of BUFFers)

	DB	85H,"#BUF","F"+80H
	DW	MSGSCR-9
NUMBUF	DW	DOCON
	DW	_NUMBUF

; <<< variables >>>

; USE		( --- a )

	DB	83H,"US","E"+80H
	DW	NUMBUF-8
USE	DW	DOVAR
	DW	_FIRST

; PREV		( --- a )
; (PREVious)

	DB	84H,"PRE","V"+80H
	DW	USE-6
PREV	DW	DOVAR
	DW	_FIRST

; DISK-ERROR	( --- a )

	DB	8AH,"DISK-ERRO","R"+80H
	DW	PREV-7
DSKERR	DW	DOVAR
	DW	0H

; <<< user variables >>>

; S0		( --- a )

	DB	82H,"S","0"+80H
	DW	DSKERR-13
SZERO	DW	DOUSE
	DW	06H

; R0		( --- a )

	DB	82H,"R","0"+80H
	DW	SZERO-5
RZERO	DW	DOUSE
	DW	08H

; TIB		( --- a )
; (Terminal Input Buffer)

	DB	83H,"TI","B"+80H
	DW	RZERO-5
TIB	DW	DOUSE
	DW	0AH

; WIDTH		( --- a )

	DB	85H,"WIDT","H"+80H
	DW	TIB-6
WYDTH	DW	DOUSE
	DW	0CH

; WARNING	( --- a )

	DB	87H,"WARNIN","G"+80H
	DW	WYDTH-8
WARN	DW	DOUSE
	DW	0EH

; FENCE		( --- a )
; (FENCE for FORGETting)

	DB	85H,"FENC","E"+80H
	DW	WARN-10
FENCE	DW	DOUSE
	DW	10H

; DP		( --- a )

	DB	82H,"D","P"+80H
	DW	FENCE-8
DP	DW	DOUSE
	DW	12H

; VOC-LINK	( --- a )
; (VOCabulary LINK)

	DB	88H,"VOC-LIN","K"+80H
	DW	DP-5
VOCL	DW	DOUSE
	DW	14H

; BLK		( --- a )
; (BLocK)

	DB	83H,"BL","K"+80H
	DW	VOCL-11
BLK	DW	DOUSE
	DW	16H

; >IN 		( --- a )
; (to IN)

	DB	83H,">I","N"+80H
	DW	BLK-6
INN	DW	DOUSE
	DW	18H

; OUT		( --- a )

	DB	83H,"OU","T"+80H
	DW	INN-6
OUTT	DW	DOUSE
	DW	1AH

; SCR		( --- a )
; (SCReen)

	DB	83H,"SC","R"+80H
	DW	OUTT-6
SCR	DW	DOUSE
	DW	1CH

; OFFSET	( --- a )

	DB	86H,"OFFSE","T"+80H
	DW	SCR-6
OFSET	DW	DOUSE
	DW	1EH

; CONTEXT	( --- a )
; (CONTEXT vocabulary)

	DB	87H,"CONTEX","T"+80H
	DW	OFSET-9
CONT	DW	DOUSE
	DW	20H

; CURRENT	( --- a )
; (CURRENT vocabulary)

	DB	87H,"CURREN","T"+80H
	DW	CONT-10
CURR	DW	DOUSE
	DW	22H

; STATE		( --- a )
; (compilation STATE)

	DB	85H,"STAT","E"+80H
	DW	CURR-10
STATE	DW	DOUSE
	DW	24H

; BASE		( --- a )
; (Base n)

	DB	84H,"BAS","E"+80H
	DW	STATE-8
BASE	DW	DOUSE
	DW	26H

; DPL		( --- a )
; (Decimal Point Location)

	DB	83H,"DP","L"+80H
	DW	BASE-7
DPL	DW	DOUSE
	DW	28H

; FLD		( --- a )
; (number output FieLD width)
; A user variable for control of number output field width.
; Presently unused in fig-FORTH.

	DB	83H,"FL","D"+80H
	DW	DPL-6
FLDD	DW	DOUSE
	DW	2AH

; CSP		( --- a )
; (Check Stack Position) 

	DB	83H,"CS","P"+80H
	DW	FLDD-6
CSP	DW	DOUSE
	DW	2CH

; R#		( --- a )
; (R number)
; A user variable which may contain the location of an
; editing cursor, or other file related function.

	DB	82H,"R","#"+80H
	DW	CSP-6
RNUM	DW	DOUSE
	DW	2EH

; HLD		( --- a )
; (HeLD)
; A user variable that holds the address of the latest character
; of text during numeric output conversion.

	DB	83H,"HL","D"+80H
	DW	RNUM-5
HLD	DW	DOUSE
	DW	30H

; PFLAG		( --- a )
; (Printer FLAG)

	DB	85H,"PFLA","G"+80H
	DW	HLD-6
PFLAG	DW	DOUSE
	DW	32H

; <<< normal words >>>

; ENCLOSE	( a c --- a n1 n2 n3 )
; a : start address in text data
; c : delimiter code
; n1: offset to the first non-delimiter character
; n2: offset to the first delimiter after text
; n3: offset to next to the first delimiter after text

	DB	87H,"ENCLOS","E"+80H
	DW	PFLAG-8
ENCL	DW	DOCOL
	DW	OVER		; OVER
	DW	DUPE		; DUP
	DW	TOR		; >R
				; BEGIN
ENCL1	DW	TDUP		;  2DUP
	DW	CAT		;  C@
	DW	EQUAL		;  =
	DW	OVER		;  OVER
	DW	CAT		;  C@
	DW	ZEQU		;  0=
	DW	ZBRAN,ENCL5-$	;  IF ( [n1] is null )
	DW	DROP		;   DROP
	DW	SWAP		;   SWAP
	DW	DROP		;   DROP
	DW	FROMR		;   R>
	DW	SUBB		;   -
	DW	DUPE		;   DUP
	DW	ONEP		;   1+
	DW	OVER		;   OVER ( a n1 n1+1 n1 )
	DW	SEMIS		;   EXIT
				;  THEN
ENCL5	DW	ZBRAN,ENCL2-$	; WHILE
	DW	ONEP		;  1+
	DW	BRAN,ENCL1-$	; REPEAT
ENCL2	DW	DUPE		; DUP
	DW	TOR		; >R
	DW	ONEP		; 1+
				; BEGIN
ENCL3	DW	TDUP		;  2DUP
	DW	CAT		;  C@
	DW	NEQ		;  <>
	DW	OVER		;  OVER
	DW	CAT		;  C@
	DW	ZEQU		;  0=
	DW	ZBRAN,ENCL6-$	;  IF ( [n2] is null )
	DW	DROP		;   DROP
	DW	SWAP		;   SWAP
	DW	DROP		;   DROP
	DW	OVER		;   OVER
	DW	SUBB		;   -
	DW	FROMR		;   R>
	DW	FROMR		;   R>
	DW	SUBB		;   -
	DW	SWAP		;   SWAP
	DW	DUPE		;   DUP ( a n1 n2 n2 )
	DW	SEMIS		;   EXIT
				;  THEN
ENCL6	DW	ZBRAN,ENCL4-$	; WHILE
	DW	ONEP		;  1+
	DW	BRAN,ENCL3-$	; REPEAT ( [n1],[n2] aren't null )
ENCL4	DW	SWAP		; SWAP
	DW	DROP		; DROP
	DW	OVER		; OVER
	DW	SUBB		; -
	DW	FROMR		; R>
	DW	FROMR		; R>
	DW	SUBB		; -
	DW	SWAP		; SWAP
	DW	DUPE		; DUP
	DW	ONEP		; 1+ ( a n1 n2 n2+1 )
	DW	SEMIS

; (FIND)	( a1 a2 --- a / ff )
; a1: top address of text string searched
; a2: NFA at which start searching
; a : CFA of the found word
; ff: false flag

;	DB	86H,"(FIND",")"+80H
;	DW	ENCL-10
;PFIND	DW	DOCOL
				; BEGIN
;PFIND1	DW	OVER		;  OVER
;	DW	TDUP		;  2DUP
;	DW	CAT		;  C@
;	DW	SWAP		;  SWAP
;	DW	CAT		;  C@
;	DW	LIT,3FH		;  3F
;	DW	ANDD		;  AND ( length and smudge bits )
;	DW	EQUAL		;  =
;	DW	ZBRAN,PFIND2-$	;  IF
				;   BEGIN
;PFIND4	DW	ONEP		;    1+
;	DW	SWAP		;    SWAP
;	DW	ONEP		;    1+
;	DW	SWAP		;    SWAP
;	DW	TDUP		;    2DUP
;	DW	CAT		;    C@
;	DW	SWAP		;    SWAP
;	DW	CAT		;    C@
;	DW	NEQ		;    <>
;	DW	ZBRAN,PFIND4-$	;   UNTIL
;	DW	CAT		;   C@
;	DW	OVER		;   OVER
;	DW	CAT		;   C@
;	DW	LIT,7FH		;   7F
;	DW	ANDD		;   AND
;	DW	EQUAL		;   =
;	DW	ZBRAN,PFIND5-$	;   IF ( found )
;	DW	SWAP		;    SWAP
;	DW	DROP		;    DROP
;	DW	THREE		;    3
;	DW	PLUS		;    +
;	DW	SEMIS		;    EXIT
				;   THEN
;PFIND5	DW	ONEM		;   1-
;	DW	BRAN,PFIND3-$	;  ELSE
;PFIND2	DW	DROP		;   DROP
				;  THEN ( next word )
				;  BEGIN
;PFIND3	DW	ONEP		;   1+
;	DW	DUPE		;   DUP
;	DW	CAT		;   C@
;	DW	LIT,80H		;   80
;	DW	ANDD		;   AND
;	DW	ZBRAN,PFIND3-$	;  UNTIL
;	DW	ONEP		;  1+
;	DW	ATT		;  @
;	DW	DUPE		;  DUP
;	DW	LIT,0H		;  0
;	DW	EQUAL		;  =
;	DW	ZBRAN,PFIND6-$	;  IF ( last word )
;	DW	TDROP		;   2DROP
;	DW	ZERO		;   0 ( unfound )
;	DW	SEMIS		;   EXIT
				;  THEN
;PFIND6	DW	BRAN,PFIND1-$	; AGAIN

; *** Assembly Version ***
		DB	86H,"(FIND",")"+80H
		DW	ENCL-10
	PFIND 	DW	$+2
		MOV	AX,DS
		MOV	ES,AX
		POP	BX	; a2
		POP	CX	; a1
	PFIND1:	MOV	DI,CX
		MOV	AL,[BX]
		MOV	DL,AL
		XOR	AL,[DI]
		AND	AL,3FH
		JNZ	PFIND3
	PFIND2:	INC	BX
		INC	DI
		MOV	AL,[BX]
		XOR	AL,[DI]
		ADD	AL,AL
		JNZ	PFIND3
		JNB	PFIND2	; when carry flag == 0
		ADD	BX,3	; Compute CFA
		PUSH	BX	; a
		JMP	NEXT
	PFIND3:	INC	BX
		JB	PFIND4	; when carry flag == 1
		MOV	AL,[BX]
		ADD	AL,AL
		JMP	PFIND3
	PFIND4:	MOV	BX,[BX]
		OR	BX,BX
		JNZ	PFIND1
		MOV	AX,0	; ff
		JMP	APUSH

; DIGIT		( c n1 --- n2 tf / ff )
; c : character code
; n2: number n2 whom c means in base n1
; tf: true flag
; ff: false flag

	DB	85H,"DIGI","T"+80H
	DW	PFIND-9
DIGIT	DW	DOCOL
	DW	SWAP		; SWAP
	DW	LIT,30H		; 30 ( code of '0' )
	DW	SUBB		; -
	DW	DUPE		; DUP
	DW	ZLESS		; 0<
	DW	ZBRAN,DIGIT1-$	; IF
	DW	TDROP		;  2DROP
	DW	ZERO		;  0
	DW	BRAN,DIGIT2-$	; ELSE
DIGIT1	DW	DUPE		;  DUP
	DW	LIT,9H		;  9
	DW	GREAT		;  >
	DW	ZBRAN,DIGIT3-$	;  IF
	DW	LIT,7H		;   7 ( ":;<=>?@" )
	DW	SUBB		;   -
	DW	DUPE		;   DUP
	DW	LIT,0AH		;   0A
	DW	LESS		;   <
	DW	ZBRAN,DIGIT4-$	;   IF
	DW	TDROP		;    2DROP
	DW	ZERO		;    0
	DW	BRAN,DIGIT5-$	;   ELSE
DIGIT4	DW	TDUP		;    2DUP
	DW	GREAT		;    >
	DW	ZBRAN,DIGIT6-$	;    IF
	DW	SWAP		;     SWAP
	DW	DROP		;     DROP
	DW	ONE		;     1
	DW	BRAN,DIGIT5-$	;    ELSE
DIGIT6	DW	TDROP		;     2DROP
	DW	ZERO		;     0
				;    THEN
				;   THEN
DIGIT5	DW	BRAN,DIGIT2-$	;  ELSE
DIGIT3	DW	TDUP		;   2DUP
	DW	GREAT		;   >
	DW	ZBRAN,DIGIT7-$	;   IF
	DW	SWAP		;    SWAP
	DW	DROP		;    DROP
	DW	ONE		;    1
	DW	BRAN,DIGIT2-$	;   ELSE
DIGIT7	DW	TDROP		;    2DROP
	DW	ZERO		;    0
				;   THEN
				;  THEN
				; THEN
DIGIT2	DW	SEMIS

; NEGATE	( n --- -n )

	DB	86H,"NEGAT","E"+80H
	DW	DIGIT-8
MINUS	DW	DOCOL
	DW	ZERO		; 0
	DW	SWAP		; SWAP
	DW	SUBB		; -
	DW	SEMIS

; DNEGATE	( d --- -d )

	DB	87H,"DNEGAT","E"+80H
	DW	MINUS-9
DMINUS	DW	DOCOL
	DW	TOR		; >R
	DW	TOR		; >R
	DW	ZERO,ZERO	; 0.0
	DW	FROMR		; R>
	DW	FROMR		; R>
	DW	DSUB		; D-
	DW	SEMIS

; +!		( n a --- )

	DB	82H,"+","!"+80H
	DW	DMINUS-10
PSTOR	DW	DOCOL
	DW	SWAP		; SWAP
	DW	OVER		; OVER
	DW	ATT		; @
	DW	PLUS		; +
	DW	SWAP		; SWAP
	DW	STORE		; !
	DW	SEMIS

; ERASE		( a n --- ; fill with nulls )

	DB	85H,"ERAS","E"+80H
	DW	PSTOR-5
ERASE	DW	DOCOL
	DW	ZERO		; 0
	DW	FILL		; FILL
	DW	SEMIS

; BLANKS	( a n --- ; fill with blanks )

	DB	86H,"BLANK","S"+80H
	DW	ERASE-8
BLANK	DW	DOCOL
	DW	BLS		; 20H
	DW	FILL		; FILL
	DW	SEMIS

; <ROT		( n1 n2 n3 --- n3 n1 n2 )

	DB	84H,"<RO","T"+80H
	DW	BLANK-9
LROT	DW	DOCOL
	DW	ROT		; ROT
	DW	ROT		; ROT
	DW	SEMIS

; C@		( a --- c )

	DB	82H,"C","@"+80H
	DW	LROT-7
CAT	DW	DOCOL
	DW	ATT		; @
	DW	LIT,0FFH	; 0FF
	DW	ANDD		; AND
	DW	SEMIS

; NOT		( f1 --- f2 )

	DB	83H,"NO","T"+80H
	DW	CAT-5
NOTT	DW	DOCOL
	DW	ZEQU		; 0=
	DW	SEMIS

; =		( n1 n2 --- f )

	DB	81H,"="+80H
	DW	NOTT-6
EQUAL	DW	DOCOL
	DW	SUBB		; -
	DW	ZEQU		; 0=
	DW	SEMIS

; <>		( n1 n2 --- f )

	DB	82H,"<",">"+80H
	DW	EQUAL-4
NEQ	DW	DOCOL
	DW	EQUAL		; =
	DW	NOTT		; NOT
	DW	SEMIS

; <		( n1 n2 --- f )

	DB	81H,"<"+80H
	DW	NEQ-5
LESS	DW	DOCOL
	DW	SUBB		; -
	DW	ZLESS		; 0<
	DW	SEMIS

; >		( n1 n2 --- f )

	DB	81H,">"+80H
	DW	LESS-4
GREAT	DW	DOCOL
	DW	SWAP		; SWAP
	DW	LESS		; <
	DW	SEMIS

; U<		( u1 u2 --- f )

	DB	82H,"U","<"+80H
	DW	GREAT-4
ULESS	DW	DOCOL
	DW	TDUP		; 2DUP
	DW	XORR		; XOR
	DW	ZLESS		; 0<
	DW	ZBRAN,ULESS1-$	; IF ( u1's MSB <> u2's MSB)
	DW	DROP		;  DROP
	DW	ZLESS		;  0< ( u1's MSB = 1 ? )
	DW	ZEQU		;  0= ( u1's MSB = 0 ? )
	DW	BRAN,ULESS2-$	; ELSE
ULESS1	DW	SUBB		;  -
	DW	ZLESS		;  0< (u1 < u2 ? )
				; THEN
ULESS2	DW	SEMIS

; MIN		( n1 n2 --- n3 )

	DB	83H,"MI","N"+80H
	DW	ULESS-5
MIN	DW	DOCOL
	DW	TDUP		; 2DUP
	DW	GREAT		; >
	DW	ZBRAN,MIN1-$	; IF
	DW	SWAP		;  SWAP
				; THEN
MIN1	DW	DROP		; DROP
	DW	SEMIS

; MAX		( n1 n2 --- n3 )

	DB	83H,"MA","X"+80H
	DW	MIN-6
MAX	DW	DOCOL
	DW	TDUP		; 2DUP
	DW	LESS		; <
	DW	ZBRAN,MAX1-$	; IF
	DW	SWAP		;  SWAP
				; THEN
MAX1	DW	DROP		; DROP
	DW	SEMIS

; +-		( n1 n2 --- n3 )
; n1 if n2 >= 0, -n1 if n2 < 0. 

	DB	82H,"+","-"+80H
	DW	MAX-6
PM	DW	DOCOL
	DW	ZLESS		; 0<
	DW	ZBRAN,PM1-$	; IF
	DW	MINUS		;  NEGATE
				; THEN
PM1	DW	SEMIS

; ABS		( n --- u )

	DB	83H,"AB","S"+80H
	DW	PM-5
ABSO	DW	DOCOL
	DW	DUPE		; DUP
	DW	PM		; +-
	DW	SEMIS

; D+-		( d1 n --- d2 )
; d1 if n >= 0, -d1 if n < 0. 

	DB	83H,"D+","-"+80H
	DW	ABSO-6
DPM	DW	DOCOL
	DW	ZLESS		; 0<
	DW	ZBRAN,DPM1-$	; IF
	DW	DMINUS		;  DNEGATE
				; THEN
DPM1	DW	SEMIS

; DABS		( d --- ud )

	DB	84H,"DAB","S"+80H
	DW	DPM-6
DABS	DW	DOCOL
	DW	DUPE		; DUP
	DW	DPM		; D+-
	DW	SEMIS

; ?DUP		( n --- n n / 0 )

	DB	84H,"?DU","P"+80H
	DW	DABS-7
QDUP	DW	DOCOL
	DW	DUPE		; DUP
	DW	ZBRAN,QDUP1-$	; IF
	DW	DUPE		;  DUP
				; THEN
QDUP1	DW	SEMIS

; S->D		( n --- d )

	DB	84H,"S->","D"+80H
	DW	QDUP-7
STOD	DW	DOCOL
	DW	DUPE		; DUP
	DW	ZLESS		; 0<
	DW	ZBRAN,STOD1-$	; IF
	DW	MONE		;  -1
	DW	BRAN,STOD2-$	; ELSE
STOD1	DW	ZERO		;  0
				; THEN
STOD2	DW	SEMIS

; M*		( n1 n2 --- d )

	DB	82H,"M","*"+80H
	DW	STOD-7
MSTAR	DW	DOCOL
	DW	TDUP		; 2DUP
	DW	XORR		; XOR
	DW	TOR		; >R
	DW	ABSO		; ABS
	DW	SWAP		; SWAP
	DW	ABSO		; ABS
	DW	USTAR		; U*
	DW	FROMR		; R> ( |n1|*|n2| n1^n2 )
	DW	DPM		; D+-
	DW	SEMIS

; *		( n1 n2 --- n3 )

	DB	81H,"*"+80H
	DW	MSTAR-5
STAR	DW	DOCOL
	DW	MSTAR		; M*
	DW	DROP		; DROP
	DW	SEMIS

; M/MOD		( ud1 u2 --- u3 ud4 )
; u3 : ud1 % u2
; ud4: ud1 / u2

	DB	85H,"M/MO","D"+80H
	DW	STAR-4
MSMOD	DW	DOCOL
	DW	TOR		; >R
	DW	ZERO		; 0
	DW	RAT		; R@ ( ud1L ud1H 0 u2 )
	DW	USLAS		; U/ ( ud1L ud1H%u2 ud1H/u2 )
	DW	FROMR		; R>
	DW	SWAP		; SWAP
	DW	TOR		; >R ( ud1L ud1H%u2 u2 )
	DW	USLAS		; U/ ( ud1%u2 ud1%(u2*1000h)/u2 )
	DW	FROMR		; R>
	DW	SEMIS

; M/		( d n1 --- n2 n3 )

	DB	82H,"M","/"+80H
	DW	MSMOD-8
MSLAS	DW	DOCOL
	DW	OVER		; OVER
	DW	TOR		; >R		
	DW	TOR		; >R
	DW	DABS		; DABS
	DW	RAT		; R@
	DW	ABSO		; ABS
	DW	USLAS		; U/
	DW	FROMR		; R>
	DW	RAT		; R@
	DW	XORR		; XOR ( |d|%|n1| |d|/|n1| 0 )
	DW	PM		; +- ( |d|%|n1| +|d|/|n1| )
	DW	SWAP		; SWAP
	DW	FROMR		; R>
	DW	PM		; +-
	DW	SWAP		; SWAP
	DW	SEMIS

; /MOD		( n1 n2 --- n3 n4 )

	DB	84H,"/MO","D"+80H
	DW	MSLAS-5
SLMOD	DW	DOCOL
	DW	TOR		; >R
	DW	STOD		; S->D
	DW	FROMR		; R>
	DW	MSLAS		; M/
	DW	SEMIS

; */MOD		( n1 n2 n3 --- n4 n5 )
; n4: (n1*n2) % n3
; n5: (n1*n2) / n3

	DB	85H,"*/MO","D"+80H
	DW	SLMOD-7
SSMOD	DW	DOCOL
	DW	TOR		; >R
	DW	MSTAR		; M*
	DW	FROMR		; R>
	DW	MSLAS		; M/
	DW	SEMIS

; MOD		( n1 n2 --- n1%n2 )

	DB	83H,"MO","D"+80H
	DW	SSMOD-8
MODD	DW	DOCOL
	DW	SLMOD		; /MOD
	DW	DROP		; DROP
	DW	SEMIS

; /		( n1 n2 --- n1/n2 )

	DB	81H,"/"+80H
	DW	MODD-6
SLASH	DW	DOCOL
	DW	SLMOD		; /MOD
	DW	SWAP		; SWAP
	DW	DROP		; DROP
	DW	SEMIS

; 2DUP		( n1 n2 --- n1 n2 n1 n2 )

	DB	84H,"2DU","P"+80H
	DW	SLASH-4
TDUP	DW	DOCOL
	DW	OVER		; OVER
	DW	OVER		; OVER
	DW	SEMIS

; 2DROP		( n1 n2 --- )

	DB	85H,"2DRO","P"+80H
	DW	TDUP-7
TDROP	DW	DOCOL
	DW	DROP		; DROP
	DW	DROP		; DROP
	DW	SEMIS

; 2@		( a --- d )

	DB	82H,"2","@"+80H
	DW	TDROP-8
TAT	DW	DOCOL
	DW	DUPE		; DUP
	DW	ATT		; @
	DW	SWAP		; SWAP
	DW	TWOP		; 2+
	DW	ATT		; @
	DW	SEMIS

; 1+		( n --- n+1 )

	DB	82H,"1","+"+80H
	DW	TAT-5
ONEP	DW	DOCOL
	DW	ONE		; 1
	DW	PLUS		; +
	DW	SEMIS

; 2+		( n --- n+2 )

	DB	82H,"2","+"+80H
	DW	ONEP-5
TWOP	DW	DOCOL
	DW	TWO		; 2
	DW	PLUS		; +
	DW	SEMIS

; 1-		( n --- n-1 )

	DB	82H,"1","-"+80H
	DW	TWOP-5
ONEM	DW	DOCOL
	DW	ONE		; 1
	DW	SUBB		; -
	DW	SEMIS

; 2-		( n --- n-2 )

	DB	82H,"2","-"+80H
	DW	ONEM-5
TWOM	DW	DOCOL
	DW	TWO		; 2
	DW	SUBB		; -
	DW	SEMIS

; 2*		( n --- n+n )

	DB	82H,"2","*"+80H
	DW	TWOM-5
TWOS	DW	DOCOL
	DW	DUPE		; DUP
	DW	PLUS		; +
	DW	SEMIS

; HOLD		( c --- )

	DB	84H,"HOL","D"+80H
	DW	TWOS-5
HOLD	DW	DOCOL
	DW	MONE		; -1
	DW	HLD		; HLD
	DW	PSTOR		; +! ( [HLD]=[HLD]-1 )
	DW	HLD		; HLD
	DW	ATT		; @
	DW	CSTOR		; C! ( [[HLD]]=c )
	DW	SEMIS

; #		( ud1 --- ud2 )

	DB	81H,"#"+80H
	DW	HOLD-7
DIG	DW	DOCOL
	DW	BASE		; BASE
	DW	ATT		; @
	DW	MSMOD		; M/MOD
	DW	ROT		; ROT
	DW	LIT,9H		; 9
	DW	OVER		; OVER
	DW	LESS		; <
	DW	ZBRAN,DIG1-$	; IF
	DW	LIT,7H		;  7 ( ":;<=>?@" )
	DW	PLUS		;  +
				; THEN
DIG1	DW	LIT,30H		; 30 ( '0' code )
	DW	PLUS		; +
	DW	HOLD		; HOLD
	DW	SEMIS

; #S		( ud --- 0 0 )

	DB	82H,"#","S"+80H
	DW	DIG-4
DIGS	DW	DOCOL
				; BEGIN
DIGS1	DW	DIG		;  #
	DW	TDUP		;  2DUP
	DW	ORR		;  OR
	DW	ZEQU		;  0= ( udL|udH == 0 )
	DW	ZBRAN,DIGS1-$	; UNTIL
	DW	SEMIS

; <#		( --- )

	DB	82H,"<","#"+80H
	DW	DIGS-5
BDIGS	DW	DOCOL
	DW	PAD		; PAD
	DW	HLD		; HLD
	DW	STORE		; !
	DW	SEMIS

; #>		( d --- a n )

	DB	82H,"#",">"+80H
	DW	BDIGS-5
EDIGS	DW	DOCOL
	DW	TDROP		; 2DROP
	DW	HLD		; HLD
	DW	ATT		; @
	DW	PAD		; PAD
	DW	OVER		; OVER
	DW	SUBB		; -
	DW	SEMIS

; SIGN		( n ud --- ud )

	DB	84H,"SIG","N"+80H
	DW	EDIGS-5
SIGN	DW	DOCOL
	DW	ROT		; ROT
	DW	ZLESS		; 0<
	DW	ZBRAN,SIGN1-$	; IF
	DW	LIT,2DH		;  2D ( - CODE )
	DW	HOLD		;  HOLD
				; THEN
SIGN1	DW	SEMIS

; COUNT		( a --- a+1 n )

	DB	85H,"COUN","T"+80H
	DW	SIGN-7
COUNT	DW	DOCOL
	DW	DUPE		; DUP
	DW	ONEP		; 1+
	DW	SWAP		; SWAP
	DW	CAT		; C@
	DW	SEMIS

; TYPE		( a n --- )

	DB	84H,"TYP","E"+80H
	DW	COUNT-8
TYPES	DW	DOCOL
	DW	QDUP		; ?DUP
	DW	ZBRAN,TYPES1-$	; IF
	DW	OVER		;  OVER
	DW	PLUS		;  +
	DW	SWAP		;  SWAP
	DW	XDO		;  DO
TYPES3	DW	IDO		;   I
	DW	CAT		;   C@
	DW	EMIT		;   EMIT
	DW	XLOOP,TYPES3-$	;  LOOP
	DW	BRAN,TYPES2-$	; ELSE
TYPES1	DW	DROP		;  DROP
				; THEN
TYPES2	DW	SEMIS

; CR

	DB	82H,"C","R"+80H
	DW	TYPES-7
CR	DW	DOCOL
	DW	LIT,0DH		; 0D ( CR code )
	DW	EMIT		; EMIT
	DW	LIT,0AH		; 0A ( LF code )
	DW	EMIT		; EMIT
	DW	SEMIS

; SPACE		( --- )

	DB	85H,"SPAC","E"+80H
	DW	CR-5
SPACE	DW	DOCOL
	DW	BLS		; 20
	DW	EMIT		; EMIT
	DW	SEMIS

; SPACES	( n --- )

	DB	86H,"SPACE","S"+80H
	DW	SPACE-8
SPACS	DW	DOCOL
	DW	ZERO		; 0
	DW	MAX		; MAX
	DW	QDUP		; ?DUP
	DW	ZBRAN,SPACS1-$	; IF
	DW	ZERO		;  0
	DW	XDO		;  DO
SPACS2	DW	SPACE		;   SPACE
	DW	XLOOP,SPACS2-$	;  LOOP
				; THEN
SPACS1	DW	SEMIS

; -TRAILING	( a n1 --- a n2 ; remove trailing blanks )

	DB	89H,"-TRAILIN","G"+80H
	DW	SPACS-9
DTRAI	DW	DOCOL
	DW	DUPE		; DUP
	DW	ZERO		; 0
	DW	XDO		; DO
DTRAI1	DW	TDUP		;  2DUP
	DW	PLUS		;  +
	DW	ONEM		;  1-
	DW	CAT		;  C@
	DW	BLS		;  BL
	DW	SUBB		;  -
	DW	ZBRAN,DTRAI2-$	;  IF
	DW	LLEAVE		;   LEAVE
	DW	BRAN,DTRAI3-$	;  ELSE
DTRAI2	DW	ONEM		;   1-
				;  THEN
DTRAI3	DW	XLOOP,DTRAI1-$	; LOOP
	DW	SEMIS

; (.")		( type in-line string )

	DB	84H,'(."',')'+80H
	DW	DTRAI-12
PDOTQ	DW	DOCOL
	DW	RAT		; R@
	DW	COUNT		; COUNT
	DW	DUPE		; DUP
	DW	ONEP		; 1+
	DW	FROMR		; R>
	DW	PLUS		; +
	DW	TOR		; >R ( next SI = a+1+n )
	DW	TYPES		; TYPE
	DW	SEMIS

; ."

	DB	0C2H,'.','"'+80H
	DW	PDOTQ-7
DOTQ	DW	DOCOL
	DW	LIT,22H		; 22 ( " CODE )
	DW	STATE		; STATE
	DW	ATT		; @
	DW	ZBRAN,DOTQ1-$	; IF ( write )
	DW	COMP		;  COMPILE
	DW	PDOTQ		;  (.")
	DW	WORDS		;  WORD ( the delimiter is '"' )
	DW	CAT		;  C@
	DW	ONEP		;  1+
	DW	ALLOT		;  ALLOT
	DW	BRAN,DOTQ2-$	; ELSE ( display )
DOTQ1	DW	WORDS		;  WORD
	DW	COUNT		;  COUNT
	DW	TYPES		;  TYPE
				; THEN
DOTQ2	DW	SEMIS

; D.R		( d n --- )

	DB	83H,"D.","R"+80H
	DW	DOTQ-5
DDOTR	DW	DOCOL
	DW	TOR		; >R
	DW	SWAP		; SWAP
	DW	OVER		; OVER
	DW	DABS		; DABS
	DW	BDIGS		; <#
	DW	DIGS		; #S
	DW	SIGN		; SIGN
	DW	EDIGS		; #>
	DW	FROMR		; R>
	DW	OVER		; OVER
	DW	SUBB		; -
	DW	SPACS		; SPACES
	DW	TYPES		; TYPE
	DW	SEMIS

; D.		( d --- )

	DB	82H,"D","."+80H
	DW	DDOTR-6
DDOT	DW	DOCOL
	DW	ZERO		; 0
	DW	DDOTR		; D.R
	DW	SPACE		; SPACE
	DW	SEMIS

; .R		( n1 n2 --- )

	DB	82H,".","R"+80H
	DW	DDOT-5
DOTR	DW	DOCOL
	DW	TOR		; >R
	DW	STOD		; S->D
	DW	FROMR		; R>
	DW	DDOTR		; D.R
	DW	SEMIS

; .		( n --- )

	DB	81H,"."+80H
	DW	DOTR-5
DOT	DW	DOCOL
	DW	STOD		; S->D
	DW	DDOT		; D.
	DW	SEMIS

; DECIMAL

	DB	87H,"DECIMA","L"+80H
	DW	DOT-4
DECA	DW	DOCOL
	DW	LIT,0AH		; 0A
	DW	BASE		; BASE
	DW	STORE		; !
	DW	SEMIS

; HEX

	DB	83H,"HE","X"+80H
	DW	DECA-10
HEX	DW	DOCOL
	DW	LIT,10H		; 10
	DW	BASE		; BASE
	DW	STORE		; !
	DW	SEMIS

; (LINE)	( line scr --- a C/L ; get a screen line )

	DB	86H,"(LINE",")"+80H
	DW	HEX-6
PLINE	DW	DOCOL
	DW	TOR		; >R
	DW	CSLL		; C/L
	DW	BBUF		; B/BUF
	DW	SSMOD		; */MOD
	DW	FROMR		; R>
	DW	BSCR		; B/SCR
	DW	STAR		; *
	DW	PLUS		; +
	DW	BLOCK		; BLOCK
	DW	PLUS		; +
	DW	CSLL		; C/L
	DW	SEMIS

; .LINE		( line scr --- ; type out a screen line )

	DB	85H,".LIN","E"+80H
	DW	PLINE-9
DLINE	DW	DOCOL
	DW	PLINE		; (LINE)
	DW	DTRAI		; -TRAILING
	DW	TYPES		; TYPE
	DW	SEMIS

; ?COMP

	DB	85H,"?COM","P"+80H
	DW	DLINE-8
QCOMP	DW	DOCOL
	DW	STATE		; STATE
	DW	ATT		; @
	DW	ZEQU		; 0=
	DW	LIT,11H		; 11
	DW	QERR		; ?ERROR
	DW	SEMIS

; ?EXEC

	DB	85H,"?EXE","C"+80H
	DW	QCOMP-8
QEXEC	DW	DOCOL
	DW	STATE		; STATE
	DW	ATT		; @
	DW	LIT,12H		; 12
	DW	QERR		; ?ERROR
	DW	SEMIS

; ?STACK

	DB	86H,"?STAC","K"+80H
	DW	QEXEC-8
QSTAC	DW	DOCOL
	DW	SPAT		; SP@
	DW	SZERO		; S0
	DW	ATT		; @
	DW	SWAP		; SWAP
	DW	ULESS		; U<
	DW	ONE		; 1
	DW	QERR		; ?ERROR
	DW	SPAT		; SP@
	DW	HERE		; HERE
	DW	LIT,80H		; 80
	DW	PLUS		; +
	DW	ULESS		; U<
	DW	LIT,7H		; 7
	DW	QERR		; ?ERROR
	DW	SEMIS

; ?PAIRS	( n1 n2 --- )

	DB	86H,"?PAIR","S"+80H
	DW	QSTAC-9
QPAIR	DW	DOCOL
	DW	EQUAL		; =
	DW	NOTT		; NOT
	DW	LIT,13H		; 13
	DW	QERR		; ?ERROR
	DW	SEMIS

; ?LOADING

	DB	88H,"?LOADIN","G"+80H
	DW	QPAIR-9
QLOAD	DW	DOCOL
	DW	BLK		; BLK
	DW	ATT		; @
	DW	ZEQU		; 0=
	DW	LIT,16H		; 16
	DW	QERR		; ?ERROR
	DW	SEMIS

; ?CSP

	DB	84H,"?CS","P"+80H
	DW	QLOAD-11
QCSP	DW	DOCOL
	DW	SPAT		; SP@
	DW	CSP		; CSP
	DW	ATT		; @
	DW	SUBB		; -
	DW	LIT,14H		; 14
	DW	QERR		; ?ERROE
	DW	SEMIS

; !CSP

	DB	84H,"!CS","P"+80H
	DW	QCSP-7
SCSP	DW	DOCOL
	DW	SPAT		; SP@
	DW	CSP		; CSP
	DW	STORE		; !
	DW	SEMIS

; COMPILE <name>

	DB	87H,"COMPIL","E"+80H
	DW	SCSP-7
COMP	DW	DOCOL
	DW	QCOMP		; ?COMP
	DW	FROMR		; R>
	DW	DUPE		; DUP
	DW	TWOP		; 2+
	DW	TOR		; >R
	DW	ATT		; @
	DW	COMMA		; ,
	DW	SEMIS

; [COMPILE]

	DB	0C9H,"[COMPILE","]"+80H
	DW	COMP-10
BCOMP	DW	DOCOL
	DW	FIND		; FIND
	DW	QDUP		; ?DUP
	DW	ZEQU		; 0=
	DW	ZERO		; 0
	DW	QERR		; ?ERROR
	DW	COMMA		; ,
	DW	SEMIS

; LITERAL	( n --- )

	DB	0C7H,"LITERA","L"+80H
	DW	BCOMP-12
LITER	DW	DOCOL
	DW	STATE		; STATE
	DW	ATT		; @
	DW	ZBRAN,LITER1-$	; IF
	DW	COMP		;  COMPILE
	DW	LIT		;  LIT
	DW	COMMA		;  ,
				; THEN
LITER1	DW	SEMIS

; DLITERAL	( d --- )

	DB	0C8H,"DLITERA","L"+80H
	DW	LITER-10
DLITE	DW	DOCOL
	DW	STATE		; STATE
	DW	ATT		; @
	DW	ZBRAN,DLITE1-$	; IF
	DW	SWAP		;  SWAP
	DW	LITER		;  [COMPILE] LITERAL
	DW	LITER		;  [COMPILE] LITERAL
				; THEN
DLITE1	DW	SEMIS

; DEFINITIONS

	DB	8BH,"DEFINITION","S"+80H
	DW	DLITE-11
DEFIN	DW	DOCOL
	DW	CONT		; CONTEXT
	DW	ATT		; @
	DW	CURR		; CURRENT
	DW	STORE		; !
	DW	SEMIS

; ALLOT		( n --- )

	DB	85H,"ALLO","T"+80H
	DW	DEFIN-14
ALLOT	DW	DOCOL
	DW	DP		; DP
	DW	PSTOR		; +!
	DW	SEMIS

; HERE		( --- a )

	DB	84H,"HER","E"+80H
	DW	ALLOT-8
HERE	DW	DOCOL
	DW	DP		; DP
	DW	ATT		; @
	DW	SEMIS

; PAD		( --- a )

	DB	83H,"PA","D"+80H
	DW	HERE-7
PAD	DW	DOCOL
	DW	HERE		; HERE
	DW	LIT,44H		; 44
	DW	PLUS		; +
	DW	SEMIS

; LATEST	( --- a )

	DB	86H,"LATES","T"+80H
	DW	PAD-6
LATES	DW	DOCOL
	DW	CURR		; CURRENT
	DW	ATT		; @
	DW	ATT		; @
	DW	SEMIS

; SMUDGE

	DB	86H,"SMUDG","E"+80H
	DW	LATES-9
SMUDG	DW	DOCOL
	DW	LATES		; LATEST
	DW	LIT,20H		; 20 ( 0b 10 0000 )
	DW	TOGGL		; TOGGLE
	DW	SEMIS

; +ORIGIN	( n --- a )

	DB	87H,"+ORIGI","N"+80H
	DW	SMUDG-9
PORIG	DW	DOCOL
	DW	ORIGI		; ORIGIN
	DW	PLUS		; +
	DW	SEMIS

; TRAVERSE	( a1 direction --- a2 )

	DB	88H,"TRAVERS","E"+80H
	DW	PORIG-10
TRAV	DW	DOCOL
	DW	SWAP		; SWAP
				; BEGIN
TRAV1	DW	OVER		;  OVER
	DW	PLUS		;  +
	DW	LIT,07FH	;  07F
	DW	OVER		;  OVER
	DW	CAT		;  C@
	DW	LESS		;  <
	DW	ZBRAN,TRAV1-$	; UNTIL
	DW	SWAP		; SWAP
	DW	DROP		; DROP
	DW	SEMIS

; NFA		( pfa --- nfa )

	DB	83H,"NF","A"+80H
	DW	TRAV-11
NFA	DW	DOCOL
	DW	LIT,5H		; 5
	DW	SUBB		; -
	DW	MONE		; -1
	DW	TRAV		; TRAVERSE
	DW	SEMIS

; LFA		( pfa --- lfa )

	DB	83H,"LF","A"+80H
	DW	NFA-6
LFA	DW	DOCOL
	DW	LIT,4H		; 4
	DW	SUBB		; -
	DW	SEMIS

; CFA		( pfa --- cfa )

	DB	83H,"CF","A"+80H
	DW	LFA-6
CFA	DW	DOCOL
	DW	TWOM		; 2-
	DW	SEMIS

; PFA		( nfa --- pfa )

	DB	83H,"PF","A"+80H
	DW	CFA-6
PFA	DW	DOCOL
	DW	ONE		; 1
	DW	TRAV		; TRAVERSE
	DW	LIT,5H		; 5
	DW	PLUS		; +
	DW	SEMIS

; [

	DB	0C1H,"["+80H
	DW	PFA-6
LBRAC	DW	DOCOL
	DW	ZERO		; 0
	DW	STATE		; STATE
	DW	STORE		; !
	DW	SEMIS

; ]

	DB	081H,"]"+80H
	DW	LBRAC-4
RBRAC	DW	DOCOL
	DW	LIT,0C0H	; 0C0 (0b 1100 0000)
	DW	STATE		; STATE
	DW	STORE		; !
	DW	SEMIS

; ;

	DB	0C1H,";"+80H
	DW	RBRAC-4
SEMI	DW	DOCOL
	DW	QCSP		; ?CSP
	DW	COMP		; COMPILE
	DW	SEMIS		; ;S
	DW	SMUDG		; SMUDGE ( on => off )
	DW	LBRAC		; [COMPILE] [
	DW	SEMIS

; ,		( n --- )

	DB	81H,","+80H
	DW	SEMI-4
COMMA	DW	DOCOL
	DW	HERE		; HERE
	DW	STORE		; !
	DW	TWO		; 2
	DW	ALLOT		; ALLOT
	DW	SEMIS

; C,		( c --- )

	DB	82H,"C",","+80H
	DW	COMMA-4
CCOMM	DW	DOCOL
	DW	HERE		; HERE
	DW	CSTOR		; C!
	DW	ONE		; 1
	DW	ALLOT		; ALLOT
	DW	SEMIS

; IMMEDIATE

	DB	89H,"IMMEDIAT","E"+80H
	DW	CCOMM-5
IMMED	DW	DOCOL
	DW	LATES		; LATEST
	DW	LIT,40H		; 40 (0b 100 0000)
	DW	TOGGL		; TOGGLE
	DW	SEMIS

; VOCABULARY <name>

	DB	8AH,"VOCABULAR","Y"+80H
	DW	IMMED-12
VOCAB	DW	DOCOL
	DW	CREAT		; CREATE
	DW	LIT,0A081H	; A081
	DW	COMMA		; , ( "blank" word )
	DW	CURR		; CURRENT
	DW	ATT		; @
	DW	CFA		; CFA
	DW	COMMA		; ,
	DW	HERE		; HERE
	DW	VOCL		; VOC-LINK
	DW	ATT		; @
	DW	COMMA		; ,
	DW	VOCL		; VOC-LINK
	DW	STORE		; !
	DW	PSCOD		; (;CODE)
DOVOC:	JMP	XDOES		; DOES>
	DW	TWOP		; 2+
	DW	CONT		; CONTEXT
	DW	STORE		; !
	DW	SEMIS

; FORTH

	DB	0C5H,"FORT"
	DB	"H"+80H
	DW	VOCAB-13
FORTH	DW	DOVOC
	DW	0A081H		; "blank" word (= DB 81H," "+80H)
	DW	STAN79-14	; latest word
	DW	0

; FORGET <name>	( forget following words in the current vocabulary )

	DB	86H,"FORGE","T"+80H
	DW	FORTH-8
FORG	DW	DOCOL
	DW	CURR		; CURRENT
	DW	ATT		; @
	DW	CONT		; CONTEXT
	DW	ATT		; @
	DW	SUBB		; -
	DW	LIT,18H		; 18
	DW	QERR		; ?ERROR
	DW	TICK		; [COMPILE] '
	DW	DUPE		; DUP
	DW	FENCE		; FENCE
	DW	ATT		; @
	DW	LESS		; <
	DW	LIT,15H		; 15
	DW	QERR		; ?ERROR
	DW	DUPE		; DUP
	DW	NFA		; NFA
	DW	DP		; DP
	DW	STORE		; !
	DW	LFA		; LFA
	DW	ATT		; @
	DW	CURR		; CURRENT
	DW	ATT		; @
	DW	STORE		; !
	DW	SEMIS

; <MARK		( --- DP )

	DB	85H,"<MAR","K"+80H
	DW	FORG-9
LMARK	DW	DOCOL
	DW	HERE		; HERE
	DW	SEMIS

; >MARK		( --- DP )

	DB	85H,">MAR","K"+80H
	DW	LMARK-8
GMARK	DW	DOCOL
	DW	HERE		; HERE
	DW	ZERO		; 0
	DW	COMMA		; ,
	DW	SEMIS

; <RESOLVE	( a --- )

	DB	88H,"<RESOLV","E"+80H
	DW	GMARK-8
LRESOL	DW	DOCOL
	DW	HERE		; HERE
	DW	SUBB		; -
	DW	COMMA		; ,
	DW	SEMIS

; >RESOLVE	( a --- )

	DB	88H,">RESOLV","E"+80H
	DW	LRESOL-11
GRESOL	DW	DOCOL
	DW	HERE		; HERE
	DW	OVER		; OVER
	DW	SUBB		; -
	DW	SWAP		; SWAP
	DW	STORE		; !
	DW	SEMIS

; IF		( --- a 1 )

	DB	0C2H,"I","F"+80H
	DW	GRESOL-11
IFF	DW	DOCOL
	DW	QCOMP		; ?COMP
	DW	COMP		; COMPILE
	DW	ZBRAN		; 0BRANCH
	DW	GMARK		; >MARK
	DW	ONE		; 1
	DW	SEMIS

; ELSE		( a1 1 --- a2 1 )

	DB	0C4H,"ELS","E"+80H
	DW	IFF-5
ELSEE	DW	DOCOL
	DW	ONE		; 1
	DW	QPAIR		; ?PAIRS
	DW	COMP		; COMPILE
	DW	BRAN		; BRANCH
	DW	GMARK		; >MARK
	DW	SWAP		; SWAP
	DW	GRESOL		; >RESOLVE
	DW	ONE		; 1
	DW	SEMIS

; THEN		( a 1 --- )

	DB	0C4H,"THE","N"+80H
	DW	ELSEE-7
THEN	DW	DOCOL
	DW	ONE		; 1
	DW	QPAIR		; ?PAIRS
	DW	GRESOL		; >RESOLVE
	DW	SEMIS

; BEGIN		( --- a 3 )

	DB	0C5H,"BEGI","N"+80H
	DW	THEN-7
BEGIN	DW	DOCOL
	DW	QCOMP		; ?COMP
	DW	LMARK		; <MARK
	DW	THREE		; 3 
	DW	SEMIS

; AGAIN		( a 3 --- )

	DB	0C5H,"AGAI","N"+80H
	DW	BEGIN-8
AGAIN	DW	DOCOL
	DW	THREE		; 3
	DW	QPAIR		; ?PAIRS
	DW	COMP		; COMPILE
	DW	BRAN		; BRANCH
	DW	LRESOL		; <RESOLVE
	DW	SEMIS

; UNTIL		( a 3 --- )

	DB	0C5H,"UNTI","L"+80H
	DW	AGAIN-8
UNTIL	DW	DOCOL
	DW	THREE		; 3
	DW	QPAIR		; ?PAIRS
	DW	COMP		; COMPILE
	DW	ZBRAN		; 0BRANCH;
	DW	LRESOL		; <RESOLVE
	DW	SEMIS

; WHILE		( a1 3 --- a2 4 )

	DB	0C5H,"WHIL","E"+80H
	DW	UNTIL-8
WHILEE	DW	DOCOL
	DW	THREE		; 3
	DW	QPAIR		; ?PAIRS
	DW	COMP		; COMPILE
	DW	ZBRAN		; 0BRANCH
	DW	GMARK		; >MARK
	DW	LIT,4H		; 4
	DW	SEMIS

; REPEAT	( a 4 --- )

	DB	0C6H,"REPEA","T"+80H
	DW	WHILEE-8
REPEA	DW	DOCOL
	DW	LIT,4H		; 4
	DW	QPAIR		; ?PAIRS
	DW	COMP		; COMPILE
	DW	BRAN		; BRANCH
	DW	SWAP		; SWAP
	DW	LRESOL		; <RESOLVE
	DW	GRESOL		; >RESOLVE
	DW	SEMIS

; DO		( --- a 2 : compiling ; n1 n2 --- ; execution )

	DB	0C2H,"D","O"+80H
	DW	REPEA-9
DO	DW	DOCOL
	DW	COMP		; COMPILE
	DW	XDO		; (DO)
	DW	LMARK		; <MARK
	DW	TWO		; 2
	DW	SEMIS

; LOOP		( a 2 --- : compiling ; --- : execution )

	DB	0C4H,"LOO","P"+80H
	DW	DO-5
LOOPC	DW	DOCOL
	DW	TWO		; 2
	DW	QPAIR		; ?PAIRS
	DW	COMP		; COMPILE
	DW	XLOOP		; (LOOP)
	DW	LRESOL		; <RESOLVE
	DW	SEMIS

; +LOOP		( a 2 --- : compiling ; --- : execution )

	DB	0C5H,"+LOO","P"+80H
	DW	LOOPC-7
PLOOP	DW	DOCOL
	DW	TWO		; 2
	DW	QPAIR		; ?PAIRS
	DW	COMP		; COMPILE
	DW	XPLOO		; (+LOOP)
	DW	LRESOL		; <RESOLVE
	DW	SEMIS

; LEAVE		( --- )

	DB	85H,"LEAV","E"+80H
	DW	PLOOP-8
LLEAVE	DW	DOCOL	; ( Return Stack: limit i return_address )
	DW	FROMR		; R>
	DW	FROMR		; R>
	DW	DUPE		; DUP
	DW	FROMR		; R>
	DW	DROP		; DROP
	DW	TOR		; >R
	DW	TOR		; >R
	DW	TOR		; >R
	DW	SEMIS

; I		( --- n )

	DB	81H,"I"+80H
	DW	LLEAVE-8
IDO	DW	DOCOL	; ( Return Stack: limit i return_address )
	DW	FROMR		; R>
	DW	RAT		; R@
	DW	SWAP		; SWAP
	DW	TOR		; >R
	DW	SEMIS

; J		( --- n )

	DB	81H,"J"+80H
	DW	IDO-4
JDO	DW	DOCOL	; ( RS: limit_j j limit_i i return_addr )
	DW	FROMR		; R>
	DW	FROMR		; R>
	DW	FROMR		; R>
	DW	RAT		; R@
	DW	LROT		; <ROT
	DW	TOR		; >R
	DW	TOR		; >R
	DW	SWAP		; SWAP
	DW	TOR		; >R
	DW	SEMIS

; EXIT

	DB	0C4H,"EXI","T"+80H
	DW	JDO-4
EXIT	DW	DOCOL
	DW	QCOMP		; ?COMP
	DW	COMP		; COMPILE
	DW	SEMIS		; ;S
	DW	SEMIS

; PICK		( n1 --- n2 )

	DB	84H,"PIC","K"+80H
	DW	EXIT-7
PICK	DW	DOCOL
	DW	TWOS		; 2*
	DW	SPAT		; SP@
	DW	PLUS		; +
	DW	ATT		; @
	DW	SEMIS

; RPICK		( n1 --- n2 )
; copy the n1-th to Return Satack

	DB	85H,"RPIC","K"+80H
	DW	PICK-7
RPICK	DW	DOCOL
	DW	TWOS		; 2*
	DW	RPAT		; RP@
	DW	PLUS		; +
	DW	ATT		; @
	DW	SEMIS

; DEPTH		( --- n )
; (Parameter) Stack's depth

	DB	85H,"DEPT","H"+80H
	DW	RPICK-8
DEPTH	DW	DOCOL
	DW	SZERO		; S0
	DW	ATT		; @
	DW	SPAT		; SP@
	DW	TWOP		; 2+
	DW	SUBB		; -
	DW	TDIV		; 2/
	DW	SEMIS

; ROLL		( n --- )
; n1 n2 ... n(m-n+1) ... n(m-1) nm  ==>
; n1 n2 ... nm n(m-n+1)  ... n(m-1)

	DB	84H,"ROL","L"+80H
	DW	DEPTH-8
ROLL	DW	DOCOL
	DW	TOR		; >R
	DW	RAT		; R@
	DW	PICK		; PICK
	DW	SPAT		; SP@
	DW	DUPE		; DUP
	DW	TWOP		; 2+
	DW	FROMR		; R>
	DW	TWOS		; 2*
	DW	LCMOVE		; <CMOVE
	DW	DROP		; DROP
	DW	SEMIS

; <ROLL		( n --- )
; reverse of ROLL

	DB	85H,"<ROL","L"+80H
	DW	ROLL-7
LROLL	DW	DOCOL
	DW	TOR		; >R
	DW	DUPE		; DUP
	DW	SPAT		; SP@
	DW	DUPE		; DUP
	DW	TWOP		; 2+
	DW	SWAP		; SWAP
	DW	RAT		; R@
	DW	TWOS		; 2*
	DW	CMOVEE		; CMOVE
	DW	SPAT		; SP@
	DW	FROMR		; R>
	DW	TWOS		; 2*
	DW	PLUS		; +
	DW	STORE		; !
	DW	SEMIS
 
; FIND <name>		( --- cfa / 0 )

	DB	84H,"FIN","D"+80H
	DW	LROLL-8
FIND	DW	DOCOL
	DW	BLS		; BL
	DW	WORDS		; WORD
	DW	CONT		; CONTEXT
	DW	ATT		; @
	DW	ATT		; @
	DW	PFIND		; (FIND)
	DW	DUPE		; DUP
	DW	ZEQU		; 0=
	DW	ZBRAN,FIND1-$	; IF ( not found )
	DW	DROP		;  DROP
	DW	HERE		;  HERE
	DW	LATES		;  LATEST
	DW	PFIND		;  (FIND)
				; THEN
FIND1	DW	SEMIS

; ' <name>	( --- pfa : execution ; --- : compiling )

	DB	0C1H
	DB	"'"+80H
	DW	FIND-7
TICK	DW	DOCOL
	DW	FIND		; FIND
	DW	TWOP		; 2+ ( cfa -> pfa )
	DW	QDUP		; ?DUP
	DW	ZEQU		; 0=
	DW	ZERO		; 0
	DW	QERR		; ?ERROR
	DW	LITER		; [COMPILE] LITERAL
	DW	SEMIS

; WORD		( c --- a )
; c: delimiter 

	DB	84H,"WOR","D"+80H
	DW	TICK-4
WORDS	DW	DOCOL
	DW	BLK		; BLK
	DW	ATT		; @
	DW	ZBRAN,WORDS1-$	; IF
	DW	BLK		;  BLK
	DW	ATT		;  @
	DW	BLOCK		;  BLOCK
	DW	BRAN,WORDS2-$	; ELSE
WORDS1	DW	TIB		;  TIB
	DW	ATT		;  @
				; THEN
WORDS2	DW	INN		; >IN
	DW	ATT		; @
	DW	PLUS		; +
	DW	SWAP		; SWAP
	DW	ENCL		; ENCLOSE
	DW	HERE		; HERE
	DW	LIT,22H		; 22
	DW	BLANK		; BLANKS
	DW	INN		; >IN
	DW	PSTOR		; +!
	DW	OVER		; OVER
	DW	SUBB		; -
	DW	TOR		; >R
	DW	RAT		; R@
	DW	HERE		; HERE
	DW	CSTOR		; C!
	DW	PLUS		; +
	DW	HERE		; HERE
	DW	ONEP		; 1+
	DW	FROMR		; R>
	DW	CMOVEE		; CMOVE
	DW	HERE		; HERE
	DW	SEMIS

; (		( skip input stream until right parenthesis )

	DB	0C1H,"("+80H
	DW	WORDS-7
PAREN	DW	DOCOL
	DW	LIT,29H		; 29 ( code of right parenthesis )
	DW	WORDS		; WORD
	DW	DROP		; DROP
	DW	SEMIS

; EXPECT	( a n --- )

	DB	86H,"EXPEC","T"+80H
	DW	PAREN-4
EXPEC	DW	DOCOL
	DW	OVER		; OVER
	DW	PLUS		; +
	DW	OVER		; OVER
	DW	XDO		; DO
EXPE1	DW	KEY		;  KEY
	DW	DUPE		;  DUP
	DW	LIT,8H		;  8 ( backspace code )
	DW	EQUAL		;  =
	DW	ZBRAN,EXPE2-$	;  IF
	DW	DROP		;   DROP
	DW	DUPE		;   DUP	
	DW	IDO		;   I
	DW	EQUAL		;   =
	DW	DUPE		;   DUP
	DW	FROMR		;   R>
	DW	TWOM		;   2-
	DW	PLUS		;   +
	DW	TOR		;   >R
	DW	ZBRAN,EXPE6-$	;   IF
	DW	LIT,7H		;    7 ( bell code )
	DW	BRAN,EXPE7-$	;   ELSE
EXPE6	DW	LIT,8H		;    8
	DW	EMIT		;    EMIT
	DW	BLS		;    BL
	DW	EMIT		;    EMIT
	DW	LIT,8H		;    8
				;   THEN
EXPE7	DW	BRAN,EXPE3-$	;  ELSE
EXPE2	DW	DUPE		;   DUP
	DW	LIT,0DH		;   0D ( carriage return code )
	DW	EQUAL		;   =
	DW	ZBRAN,EXPE4-$	;   IF
	DW	LLEAVE		;    LEAVE
	DW	DROP		;    DROP
	DW	BLS		;    BL
	DW	ZERO		;    0
	DW	BRAN,EXPE5-$	;   ELSE
EXPE4	DW	DUPE		;    DUP
				;   THEN
EXPE5	DW	IDO		;   I
	DW	CSTOR		;   C!
	DW	ZERO		;   0
	DW	IDO		;   I
	DW	ONEP		;   1+
	DW	STORE		;   !
				;  THEN
EXPE3	DW	EMIT		;  EMIT
	DW	XLOOP,EXPE1-$	; LOOP
	DW	DROP		; DROP
	DW	SEMIS

; QUERY

	DB	85H,"QUER","Y"+80H
	DW	EXPEC-9
QUERY	DW	DOCOL
	DW	TIB		; TIB
	DW	ATT		; @
	DW	TIBLEN		; TIBLEN
	DW	EXPEC		; EXPECT
	DW	ZERO		; 0
	DW	INN		; >IN
	DW	STORE		; !
	DW	SEMIS

; x ( x is replaced by null code )

	DB	0C1H
	DB	0H+80H
	DW	QUERY-8
NULL	DW	DOCOL
	DW	BLK		; BLK
	DW	ATT		; @
	DW	ZBRAN,NULL1-$	; IF ( disk, not terminal )
	DW	ONE		;  1
	DW	BLK		;  BLK
	DW	PSTOR		;  +!
	DW	ZERO		;  0
	DW	INN		;  >IN
	DW	STORE		;  !
	DW	BLK		;  BLK
	DW	ATT		;  @
	DW	BSCR		;  B/SCR
	DW	ONEM		;  1-
	DW	ANDD		;  AND
	DW	ZEQU		;  0=
	DW	ZBRAN,NULL3-$	;  IF
	DW	QEXEC		;   ?EXEC
	DW	FROMR		;   R>
	DW	DROP		;   DROP
				;  THEN
NULL3	DW	BRAN,NULL2-$	; ELSE ( terminal )
NULL1	DW	FROMR		;  R> (null from INTERPRET)
	DW	DROP		;  DROP
				; THEN
NULL2	DW	SEMIS

; CONVERT	( d a --- d' a' )

	DB	87H,"CONVER","T"+80H
	DW	NULL-4
CONV	DW	DOCOL
				; BEGIN
CONV1	DW	ONEP		;  1+
	DW	DUPE		;  DUP
	DW	TOR		;  >R
	DW	CAT		;  C@
	DW	BASE		;  BASE
	DW	ATT		;  @
	DW	DIGIT		;  DIGIT
	DW	ZBRAN,CONV2-$	; WHILE
	DW	SWAP		;  SWAP
	DW	BASE		;  BASE
	DW	ATT		;  @
	DW	USTAR		;  U*
	DW	DROP		;  DROP
	DW	ROT		;  ROT
	DW	BASE		;  BASE
	DW	ATT		;  @
	DW	USTAR		;  U*
	DW	DPLUS		;  D+
	DW	DPL		;  DPL
	DW	ATT		;  @
	DW	ONEP		;  1+
	DW	ZBRAN,CONV3-$	;  IF
	DW	ONE		;   1
	DW	DPL		;   DPL
	DW	PSTOR		;   +!
				;  THEN
CONV3	DW	FROMR		;  R>
	DW	BRAN,CONV1-$	; REPEAT
CONV2	DW	FROMR		; R>
	DW	SEMIS

; NUMBER	( a --- d )

	DB	86H,"NUMBE","R"+80H
	DW	CONV-10
NUMB	DW	DOCOL
	DW	ZERO,ZERO	; 0.0
	DW	ROT		; ROT
	DW	DUPE		; DUP
	DW	ONEP		; 1+
	DW	CAT		; C@
	DW	LIT,2DH		; 2D ( - code )
	DW	EQUAL		; =
	DW	DUPE		; DUP
	DW	TOR		; >R
	DW	PLUS		; +
	DW	MONE		; -1
				; BEGIN
NUMB1	DW	DPL		;  DPL
	DW	STORE		;  !
	DW	CONV		;  CONVERT
	DW	DUPE		;  DUP
	DW	CAT		;  C@
	DW	BLS		;  BL
	DW	SUBB		;  -
	DW	ZBRAN,NUMB2-$	; WHILE
	DW	DUPE		;  DUP
	DW	CAT		;  C@
	DW	LIT,2EH		;  2E ( . code )
	DW	SUBB		;  -
	DW	ZERO		;  0
	DW	QERR		;  ?ERROR
	DW	ZERO		;  0
	DW	BRAN,NUMB1-$	; REPEAT
NUMB2	DW	DROP		; DROP
	DW	FROMR		; R>
	DW	ZBRAN,NUMB3-$	; IF
	DW	DMINUS		;  DNEGATE
				; THEN
NUMB3	DW	SEMIS

; +BUF		( a1 --- a2 f ; advance to next buffer address )

	DB	84H,"+BU","F"+80H
	DW	NUMB-9
PBUF	DW	DOCOL
	DW	BFLEN		; BFLEN
	DW	PLUS		; +
	DW	DUPE		; DUP
	DW	LIMIT		; LIMIT
	DW	EQUAL		; =
	DW	ZBRAN,PBUF1-$	; IF
	DW	DROP		;  DROP
	DW	FIRST		;  FIRST
				; THEN
PBUF1	DW	DUPE		; DUP
	DW	PREV		; PREV
	DW	ATT		; @
	DW	SUBB		; -
	DW	SEMIS

; UPDATE	( mark the buffer pointed to by PREV as updated )

	DB	86H,"UPDAT","E"+80H
	DW	PBUF-7
UPDAT	DW	DOCOL
	DW	PREV		; PREV
	DW	ATT		; @
	DW	ATT		; @
	DW	LIT,8000H	; 8000 ( set most significant bit )
	DW	ORR		; OR
	DW	PREV		; PREV
	DW	ATT		; @
	DW	STORE		; !
	DW	SEMIS

; EMPTY-BUFFERS	( clear block buffers without writing to disk )

	DB	8DH,"EMPTY-BUFFER","S"+80H
	DW	UPDAT-9
EMPBUF	DW	DOCOL
	DW	FIRST		; FIRST
	DW	LIMIT		; LIMIT
	DW	OVER		; OVER
	DW	SUBB		; -
	DW	ERASE		; ERASE
	DW	SEMIS

; SAVE-BUFFERS	( write updated block buffers to disk )

	DB	8CH,"SAVE-BUFFER","S"+80H
	DW	EMPBUF-16
SAVBUF	DW	DOCOL
	DW	NUMBUF		; #BUF
	DW	ONEP		; 1+
	DW	ZERO		; ZERO
	DW	XDO		; DO
SAVBUF1	DW	ZERO		;  ZERO
	DW	BUFFE		;  BUFFER
	DW	DROP		;  DROP
	DW	XLOOP,SAVBUF1-$	; LOOP
	DW	SEMIS

; DR0		( select drive 0 )

	DB	83H,"DR","0"+80H
	DW	SAVBUF-15
DRZER	DW	DOCOL
	DW	ZERO		; 0
	DW	OFSET		; OFFSET
	DW	STORE		; !
	DW	SEMIS

; DR1		( select drive 1 )

	DB	83H,"DR","1"+80H
	DW	DRZER-6
DRONE	DW	DOCOL
	DW	LIT,_DRSIZ	; 2D0 ( 720KB floppy disk )
	DW	BSCR		; B/SCR
	DW	STAR		; *
	DW	OFSET		; OFFSET
	DW	STORE		; !
	DW	SEMIS

; R/W		( a n f --- ; read/write disk,
;			read if f=1, write if f=0 )
;		a: buffer address
;		n: block number
;		f: direction flag		

	DB	83H,"R/","W"+80H
	DW	DRONE-6
RSLW	DW	DOCOL
	DW	TOR		; >R
	DW	LIT,_DRSIZ	; 2D0 ( = 720 )
	DW	BSCR		; B/SCR
	DW	STAR		; *
	DW	SLMOD		; /MOD
	DW	LROT		; <ROT
	DW	FROMR		; R>
	DW	ZBRAN,RSLW1-$	; IF
	DW	RREC		;  READ-REC
	DW	LIT,8H		;  8 ( error #8 )
	DW	BRAN,RSLW2-$	; ELSE
RSLW1	DW	WREC		;  WRITE-REC
	DW	LIT,9H		;  9 ( error #9 )
				; THEN
RSLW2	DW	OVER		; OVER
	DW	SWAP		; SWAP
	DW	QERR		; ?ERROR
	DW	DUPE		; DUP
	DW	ZBRAN,RSLW3-$	; IF
	DW	ZERO		;  0
	DW	PREV		;  PREV
	DW	ATT		;  @
	DW	STORE		;  ! (This buffer is no good!)
				; THEN
RSLW3	DW	DSKERR		; DISK-ERROR
	DW	STORE		; !
	DW	SEMIS

; BUFFER	( n --- a ; aquire buffer for block n )

	DB	86H,"BUFFE","R"+80H
	DW	RSLW-6
BUFFE	DW	DOCOL
	DW	USE		; USE
	DW	ATT		; @
	DW	DUPE		; DUP
	DW	TOR		; >R
				; BEGIN
BUFFE1	DW	PBUF		;  +BUF
	DW	ZBRAN,BUFFE1-$	; UNTIL
	DW	USE		; USE
	DW	STORE		; !
	DW	RAT		; R@
	DW	ATT		; @
	DW	ZLESS		; 0<
	DW	ZBRAN,BUFFE2-$	; IF ( updated )
	DW	RAT		;  R@
	DW	TWOP		;  2+ ( data area )
	DW	RAT		;  R@
	DW	ATT		;  @
	DW	LIT,7FFFH	;  7FFF
	DW	ANDD		;  AND ( blk # )
	DW	ZERO		;  0
	DW	RSLW		;  R/W ( write )
				; THEN
BUFFE2	DW	RAT		; R@
	DW	STORE		; !
	DW	RAT		; R@
	DW	PREV		; PREV
	DW	STORE		; !
	DW	FROMR		; R>
	DW	TWOP		; 2+ ( data area )
	DW	SEMIS

; BLOCK		( n --- a ; get buffer address for block n )

	DB	85H,"BLOC","K"+80H
	DW	BUFFE-9
BLOCK	DW	DOCOL
	DW	OFSET		; OFFSET
	DW	ATT		; @
	DW	PLUS		; +
	DW	TOR		; >R
	DW	PREV		; PREV
	DW	ATT		; @
	DW	DUPE		; DUP
	DW	ATT		; @
	DW	RAT		; R@
	DW	SUBB		; -
	DW	TWOS		; 2* ( disregard UPDATE bit )
	DW	ZBRAN,BLOCK1-$	; IF ( not PREV )
				;  BEGIN
BLOCK2	DW	PBUF		;   +BUF
	DW	ZEQU		;   0= ( true upon reaching PREV )
	DW	ZBRAN,BLOCK3-$	;   IF
	DW	DROP		;    DROP
	DW	RAT		;    R@
	DW	BUFFE		;    BUFFER
	DW	DUPE		;    DUP
	DW	RAT		;    R@
	DW	ONE		;    1
	DW	RSLW		;    R\W ( read )
	DW	TWOM		;    2-
				;   THEN
BLOCK3	DW	DUPE		;   DUP
	DW	ATT		;   @
	DW	RAT		;   R@
	DW	SUBB		;   -
	DW	TWOS		;   2*
	DW	ZEQU		;   0=
	DW	ZBRAN,BLOCK2-$	;  UNTIL
	DW	DUPE		;  DUP
	DW	PREV		;  PREV
	DW	STORE		;  !
				; THEN
BLOCK1	DW	FROMR		; R>
	DW	DROP		; DROP
	DW	TWOP		; 2+ ( data area )
	DW	SEMIS

; INTERPRET	( interpret or compile words in input stream )

	DB	89H,"INTERPRE","T"+80H
	DW	BLOCK-8
INTER	DW	DOCOL
				; BEGIN
INTER1	DW	FIND		;  FIND
	DW	QDUP		;  ?DUP
	DW	ZBRAN,INTER2-$	;  IF ( found )
	DW	DUPE		;   DUP
	DW	TWOP		;   2+ ( cfa => pfa )
	DW	NFA		;   NFA
	DW	CAT		;   C@
	DW	STATE		;   STATE
	DW	ATT		;   @
	DW	LESS		;   <
	DW	ZBRAN,INTER4-$	;   IF
	DW	COMMA		;    ,
	DW	BRAN,INTER5-$	;   ELSE
INTER4	DW	EXEC		;    EXECUTE
				;   THEN
INTER5	DW	QSTAC		;   ?STACK
	DW	BRAN,INTER3-$	;  ELSE
INTER2	DW	HERE		;   HERE
	DW	NUMB		;   NUMBER
	DW	DPL		;   DPL
	DW	ATT		;   @
	DW	ONEP		;   1+
	DW	ZBRAN,INTER6-$	;   IF
	DW	DLITE		;    [COMPILE] DLITERAL
	DW	BRAN,INTER7-$	;   ELSE
INTER6	DW	DROP		;    DROP
	DW	LITER		;    [COMPILE] LITERAL
				;   THEN
INTER7	DW	QSTAC		;   ?STACK
				;  THEN
INTER3	DW	BRAN,INTER1-$	; AGAIN

; QUIT		( restart, interpret from terminal )

	DB	84H,"QUI","T"+80H
	DW	INTER-12
QUIT	DW	DOCOL
	DW	ZERO		; 0
	DW	BLK		; BLK
	DW	STORE		; !
	DW	LBRAC		; [COMPILE] [
				; BEGIN
QUIT1	DW	RPSTO		;  RP!
	DW	CR		;  CR
	DW	QUERY		;  QUERY
	DW	INTER		;  INTERPRET
	DW	STATE		;  STATE
	DW	ATT		;  @
	DW	ZEQU		;  0=
	DW	ZBRAN,QUIT2-$	;  IF
	DW	PDOTQ		;   ."
	DB	2,"ok"		;   ok"
				;  THEN
QUIT2	DW	BRAN,QUIT1-$	; AGAIN

; ABORT		( clear stacks, warm start )

	DB	85H,"ABOR","T"+80H
	DW	QUIT-7
ABORT	DW	DOCOL
;-------------------------------------------
	DW	CR
	DW	PDOTQ
	DB	20,"FORTH'79+ Ver. 0.4.2"
;-------------------------------------------
	DW	SPSTO		; SP!
	DW	DECA		; DECIMAL
	DW	DRZER		; DR0
	DW	FORTH		; [COMPILE] FORTH
	DW	DEFIN		; DEFINITIONS
	DW	QUIT		; QUIT

; MESSAGE	( n --- ; output n'th message )

	DB	87H,"MESSAG","E"+80H
	DW	ABORT-8
MESS	DW	DOCOL
	DW	WARN		; WARNING
	DW	ATT		; @
	DW	ZBRAN,MESS1-$	; IF
	DW	QDUP		;  ?DUP
	DW	ZBRAN,MESS3-$	;  IF
	DW	MSGSCR		;   MSGSCR
	DW	OFSET		;   OFFSET
	DW	ATT		;   @
	DW	BSCR		;   B/SCR
	DW	SLASH		;   /
	DW	SUBB		;   -
	DW	DLINE		;   .LINE
	DW	SPACE		;   SPACE
				;  THEN
MESS3	DW	BRAN,MESS2-$	; ELSE
MESS1	DW	PDOTQ		;  ."
	DB	6,"MSG # "	;  MSG # "
	DW	DOT		;  .
				; THEN
MESS2	DW	SEMIS

; ERROR		( n --- ; output n'th error message then quit       
;			depending on the value of WARNING )

	DB	85H,"ERRO","R"+80H
	DW	MESS-10
ERROR	DW	DOCOL
	DW	WARN		; WARNING
	DW	ATT		; @
	DW	ZLESS		; 0<
	DW	ZBRAN,ERROR1-$	; IF
	DW	ABORT		;  ABORT
				; THEN
ERROR1	DW	HERE		; HERE
	DW	COUNT		; COUNT
	DW	TYPES		; TYPE
	DW	PDOTQ		; ."
	DB	2,"? "		; ? "
	DW	MESS		; MESSAGE
	DW	SPSTO		; SP!
	DW	BLK		; BLK
	DW	ATT		; @
	DW	QDUP		; ?DUP
	DW	ZBRAN,ERROR2-$	; IF
	DW	INN		;  >IN
	DW	ATT		;  @
	DW	SWAP		;  SWAP
				; THEN
ERROR2	DW	QUIT		; QUIT

; ?ERROR	( f n --- ; execute ERROR on true flag )

	DB	86H,"?ERRO","R"+80H
	DW	ERROR-8
QERR	DW	DOCOL
	DW	SWAP		; SWAP
	DW	ZBRAN,QERR1-$	; IF
	DW	ERROR		;  ERROR
	DW	BRAN,QERR2-$	; ELSE
QERR1	DW	DROP		;  DROP
				; THEN
QERR2	DW	SEMIS

; LOAD		( n --- ; interpret screen )

	DB	84H,"LOA","D"+80H
	DW	QERR-9
LOAD	DW	DOCOL
	DW	BLK		; BLK
	DW	ATT		; @
	DW	TOR		; >R
	DW	INN		; >IN
	DW	ATT		; @
	DW	TOR		; >R
	DW	ZERO		; 0
	DW	INN		; >IN
	DW	STORE		; !
	DW	BSCR		; B/SCR
	DW	STAR		; *
	DW	BLK		; BLK
	DW	STORE		; !
	DW	INTER		; INTERPRET
	DW	FROMR		; R>
	DW	INN		; >IN
	DW	STORE		; !
	DW	FROMR		; R>
	DW	BLK		; BLK
	DW	STORE		; !
	DW	SEMIS

; -->		( continue interpreting next screen )

	DB	0C3H,"--",">"+80H
	DW	LOAD-7
ARROW	DW	DOCOL
	DW	QLOAD		; ?LOADING
	DW	ZERO		; 0
	DW	INN		; >IN
	DW	STORE		; !
	DW	BSCR		; B/SCR
	DW	BLK		; BLK
	DW	ATT		; @
	DW	OVER		; OVER
	DW	MODD		; MOD
	DW	SUBB		; -
	DW	BLK		; BLK
	DW	PSTOR		; +!
	DW	SEMIS

; ID.		( nfa --- ; print word's name )

	DB	83H,"ID","."+80H
	DW	ARROW-6
IDDOT	DW	DOCOL
	DW	PAD		; PAD
	DW	LIT,22H		; 22
	DW	BLANK		; BLANKS
	DW	DUPE		; DUP
	DW	PFA		; PFA
	DW	LFA		; LFA
	DW	OVER		; OVER
	DW	SUBB		; -
	DW	PAD		; PAD
	DW	SWAP		; SWAP
	DW	CMOVEE		; CMOVE
	DW	PAD		; PAD
	DW	COUNT		; COUNT
	DW	LIT,1FH		; 1F ( 31 )
	DW	ANDD		; AND
	; modified last character
	DW	TDUP		; 2DUP
	DW	PLUS		; +
	DW	ONEM		; 1-
	DW	LIT,-80H	; -80
	DW	SWAP		; SWAP
	DW	PSTOR		; +!
	; end of new lines
	DW	TYPES		; TYPE
	DW	SPACE		; SPACE
	DW	SEMIS

; (CREATE) <name>

	DB	88H,"(CREATE",")"+80H
	DW	IDDOT-6
PCREAT	DW	DOCOL
	DW	FIND		; FIND
	DW	QDUP		; ?DUP
	DW	ZBRAN,PCREAT1-$	; IF
	DW	CR		;  CR
	DW	THREE		;  3
	DW	SUBB		;  -
	DW	MONE		;  -1
	DW	TRAV		;  TRAVERSE
	DW	IDDOT		;  ID.
	DW	LIT,4H		;  4
	DW	MESS		;  MESSAGE ( redefinition )
	DW	SPACE		;  SPACE
				; THEN
PCREAT1	DW	HERE		; HERE
	DW	DUPE		; DUP
	DW	CAT		; C@
	DW	WYDTH		; WIDTH
	DW	ATT		; @
	DW	MIN		; MIN
	DW	ONEP		; 1+
	DW	ALLOT		; ALLOT ( get area for name )
	DW	DUPE		; DUP
	DW	LIT,0A0H	; 0A0
	DW	TOGGL		; TOGGLE ( smudge )
	DW	HERE		; HERE
	DW	ONEM		; 1-
	DW	LIT,80H		; 80
	DW	TOGGL		; TOGGLE ( end of name )
	DW	LATES		; LATEST
	DW	COMMA		; , ( link field )
	DW	CURR		; CURRENT
	DW	ATT		; @
	DW	STORE		; ! ( link )
	DW	HERE		; HERE
	DW	TWOP		; 2+
	DW	COMMA		; , ( compilation field )
	DW	SEMIS

; (;CODE)

	DB	87H,"(;CODE",")"+80H
	DW	PCREAT-11
PSCOD	DW	DOCOL
	DW	FROMR		; R>
	DW	LATES		; LATEST
	DW	ONE		; 1
	DW	TRAV		; TRAVERSE
	DW	THREE		; 3
	DW	PLUS		; + ( compilation address )
	DW	STORE		; !
	DW	SEMIS

; .S

	DB	82H,".","S"+80H
	DW	PSCOD-10
DOTES	DW	DOCOL
	DW	SPAT		; SP@
	DW	SZERO		; S0
	DW	ATT		; @
	DW	EQUAL		; =
	DW	ZEQU		; 0=
	DW	ZBRAN,DOTES1-$	; IF
	DW	SPAT		;  SP@
	DW	SZERO		;  S0
	DW	ATT		;  @
	DW	TWOM		;  2-
	DW	XDO		;  DO
DOTES2	DW	IDO		;   I
	DW	ATT		;   @
	DW	DOT		;   .
	DW	LIT,-2		;   -2
	DW	XPLOO,DOTES2-$	;  +LOOP
				; THEN
DOTES1	DW	SEMIS

; ASSEMBLER

	DB	0C9H,"ASSEMBLE","R"+80H
	DW	DOTES-5
ASSEM	DW	DOVOC
	DW	0A081H
	DW	STAN79-14
	DW	FORTH+6

; CODE <name>

	DB	84H,"COD","E"+80H
	DW	ASSEM-12
CODE	DW	DOCOL
	DW	PCREAT		; (CREAT)
	DW	SMUDG		; SMUDGE
	DW	ASSEM		; [COMPILE] ASSEMBLER
	DW	SEMIS

; END-CODE

	DB	088H
	DB	"END-COD"
	DB	'E'+80H
	DW	CODE-7
ENDCO	DW	DOCOL
	DW	CURR		; CURRENT
	DW	ATT		; @
	DW	CONT		; CONTEXT
	DW	STORE		; !
	DW	SEMIS

; ;CODE

	DB	0C5H,";COD","E"+80H
	DW	ENDCO-11
SCODE	DW	DOCOL
	DW	QCSP		; ?CSP
	DW	COMP		; COMPILE
	DW	PSCOD		; (;CODE)
	DW	LBRAC		; [COMPILE] [
	DW	SMUDG		; SMUDGE
	DW	ASSEM		; [COMPILE] ASSEMBLER
	DW	SEMIS

; BYE

	DB	83H,"BY","E"+80H
	DW	SCODE-8
BYE	DW	$+2
	INT	20H		; exit program

; 79-STANDARD

	DB	8BH,"79-STANDAR","D"+80H
	DW	BYE-6
STAN79	DW	DOCOL
	DW	SEMIS

; ***************************************

INITDP	EQU	$	 ; initial Dictionry Pointer
; ---------------------------------------
codeSeg ENDS
	END	ORIG
