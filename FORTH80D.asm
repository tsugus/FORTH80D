; ************************************************************
; *                                                          *
; *                                                          *
; *                  F  O  R  T  H  8  0  D                  *
; *                                                          *
; *                                                          *
; *                A FORTH language processor                *
; *               conforming FORTH-79 Standard               *
; *                                                          *
; *                           for                            *
; *                                                          *
; *                      i8086 & MS-DOS                      *
; *                                                          *
; *                      Version 0.7.0                       *
; *                                                          *
; *                                     (C) 2023-2024 Tsugu  *
; *                                                          *
; *                                                          *
; *           This software is released under the            *
; *                                                          *
; *                       MIT License.                       *
; *    (https://opensource.org/licenses/mit-license.php)     *
; *                                                          *
; ************************************************************
;
; ***** Comment Notations *****
;
; X <- Y	: assign Y to X
;
; {X}		: the 8-bit memory of address X
; 		  Not a value itself !
; 		  The {X} to which you assign is a variable.
; 		  The {X} which you assign is a value.
;
; [X]		: the 16-bit memory of address X
; 		  [X] = {X+1} * 256 + {x}
;
; [X] <- [Y]	: {X+1} <- {Y+1} and {Y} <- {X}
;
; ***** Registers Set ******
;
; 				FORTH	8086
; Instruction Pointer		IP	SI
; (parameter) Stack Pointer	SP	SP
; Return stack Pointer		RP	BP
; Working register		W	DX
;
; stack		:	|[INITS0-2] ... [IP+4] [IP+2] [IP]
; return stack	:	|[INITR0-2] ... [RP+4] [RP+2] [RP]
;
; ***** Memory Map *****
;
;               |=======|
;        ORIG ->| 0100H |     program start
;               |   .   |
;               |   .   |
;               |=======|
;       LIT-6 ->| 01B6H |     start of dictionary
;               |   .   |
;               |   .   |
;      INITDP ->| ????H |     initial position of DP
;               |   .   |
;               |   .   |
;               | ----- |----
;          DP  v|   x   |  |  dictionary pointer (go under)
;               |   .   |  |  word buffer (70 bytes)
;               |   .   |  |
;               | ----- | temporary buffer area (151 bytes)
;         PAD  v| x+46H |  |
;               |   :   |  |  text buffer (81 bytes)
;               | x+96H |  |
;               | ----- |----
;               |   .   |
;               |   .   |
;               | ----- |
;          SP  ^|   .   |     stack pointer (go upper)
;               |   .   |
;               | 7716H |     bottom of stack
;               |=======|
; INITS0, TIB ->| 7718H |     terminal input buffer
;               |   .   |
;               |   .   |
;               | ----- |
;          RP  ^|   .   |     return stack pointer (go upper)
;               |   .   |
;               | 77B6H |     bottom of return stack
;               |=======|
;  INITR0, UP ->| 77B8H |     top of user variables area
;               |   :   |
;               |=======|
;       FIRST ->| 77F8H |     top of disk buffers
;               |   :   |
;               | 7FFEH |     bottom of disk buffers
;               |=======|
;       LIMIT ->| 8000H |     out of area
;
; ***** Disk Buffer's Structure *****
;
;               |===========| f: update flag
;       FIRST ->| f |   n   | n: block number (15 bit)
;               |-----------| -----
;               |           |   |
;               |           |   |
;               |           |   |
;       buffer1 |    DATA   |  1024 bytes
;               ~           ~   |
;               ~           ~   |
;               |           |   |
;               |-----------| -----
;               | 00H | 00H | double null characters
;               |===========|
;               | f |   n   |
;               |-----------| -----
;               |           |   |
;               |           |   |
;               |           |   |
;       buffer2 |    DATA   |  1024 bytes
;               ~           ~   |
;               ~           ~   |
;               |           |   |
;               |-----------| -----
;               | 00H | 00H |
;               |===========|
;       LIMIT ->
;
; ========== ENVIRONMENT DEPENDENT ==========
;
DRSIZ	EQU	720		; drive size (KB)
BPS	EQU	512		; bytes per sector
;
; ***** System Memory Configuration *****
;
ORIG0	EQU	100H
BBUF0	EQU	1024		; bytes per buffer
BFLEN0	EQU	BBUF0+4		; buffer tags length = 4
LIMIT0	EQU	8000H
NUMBU0	EQU	2		; number of disk block buffers
FIRST0	EQU	LIMIT0-BFLEN0*NUMBU0
UP	EQU	FIRST0-40H	; user variables area size
				;                        = 40H
INITR0	EQU	UP
INITS0	EQU	INITR0-0A0H	; return stack size = A0H
;
MXTOKN	EQU	34		; max bytes of tokens
				;  (On 2-base,
				;  'length' + '-'
				;    + "16-digits"
				;    + '.' + "16-digits")
WRDBSZ	EQU	64+6		; word buffer size ( > C/L)
PADSZ	EQU	80+1		; PAD size
TMPBSZ	EQU	WRDBSZ+PADSZ	; temporary buffer area size
;
; ***************************************
;
codeSeg	SEGMENT
	ASSUME	CS:codeSeg, DS:codeSeg
; ---------------------------------------
	ORG	100H
;
ORIG:	NOP
	JMP	CLD_
	NOP
	JMP	WRM
;
; ***** COLD & WARM *****
;
; COLD START
;
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
;
; WARM START
;
WRM:	MOV	SI,OFFSET WRM1
	JMP	NEXT
WRM1	DW	WARM
;
; ***** USER VARIABLES *****
;
UVR	DW	0		; (release No.)
	DW	7		; (revision No.)
	DW	0000H		; (user version xx[Alphabet])
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
UVREND	DW	0		; PFLAG
;
; ***** INTERFACE (for MS-DOS) *****
;
; ( --- f ; Take a type-state of keyboard. )
CTST	DW	$+2
	MOV	AH,0BH	; Is Type Ahead Buffer empty? Or not?
	INT	21H	; AL=00H or FFH
	AND	AX,1
	JMP	APUSH
;
; ( --- c ; Input one character from keyboard. )
CIN	DW	$+2
	MOV	AH,7
	INT	21H
	XOR	AH,AH
	JMP	APUSH
;
; ( c --- ; Output one character to console. )
COUT	DW	$+2
	POP	DX
	MOV	AH,2
	INT	21H
	JMP	NEXT
;
; ( c --- ; Output one character to printer. )
POUT	DW	$+2
	POP	DX
	MOV	AH,5
	INT	21H
	JMP	NEXT
;
; ( drvNo bufAddr secNo --- errFlg ; Read a sector on disks. )
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
;
; ( drvNo bufAddr secNo --- errFLg ; Write a sector on disks. )
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
;
; ***** FORTH INNER INTERPRETER *****
;
; DPUSH		( --- DX AX )
; APUSH		( --- AX )
; NEXT		( --- )
; NEXT1		( --- )
;
DPUSH:	PUSH	DX		; Push DX to the (parameter) stack.
APUSH:	PUSH	AX
NEXT:	LODSW			; AX=[SI]; SI+=2
	MOV	BX,AX		; BX=AX
NEXT1:	MOV	DX,BX		; DX=BX
	INC	DX		; DX++
	JMP	WORD PTR [BX]	; goto [BX]
;
; ***** Word's Structure *****
;
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
;       Parameter F. A. | (word 1)| -> PFA 1
;                       |         |
;                       |---------|
;                       | (word 2)| -> PFA 2
;                       |         |
;                       |---------|
;                       |    .    |
;                       |    .    |
;                       |---------|
;                       | (word n)| -> PFA n
;                       |         |
;                       |---------|
;                       |  SEMIS  | -> PFA of ";S"
;                       |   (;S)  |
;                       |=========|
;
; ***** FORTH DICTIONARY *****
;
; 	===== core words =====
;
; ( --- n ; n = [IP] )
	DB	83H,'LI','T'+80H
	DW	0	; end of dictionary
LIT	DW	$+2	; the address here + 2
	LODSW		; AX=[SI]; SI+=2
	JMP	APUSH
;
; ( cfa --- ; PC <- [cfa] )
	DB	87H,'EXECUT','E'+80H
	DW	LIT-6
EXEC	DW	$+2
	POP	BX	; BX=a
	JMP	NEXT1
;
; ( --- ; Jump to [IP+2]. )
	DB	86H,'BRANC','H'+80H
	DW	EXEC-10
BRAN	DW	$+2
BRAN1:	ADD	SI,[SI]	; SI+=[SI]
	JMP	NEXT
;
; ( f --- ; Jump to [IP+2] if f == 0. )
	DB	87H,'0BRANC','H'+80H
	DW	BRAN-9
ZBRAN	DW	$+2
	POP	AX	; AX=f
	OR	AX,AX
	JZ	BRAN1	; Goto BRAN1 if zero flag is 1.
	INC	SI	; SI++
	INC	SI
	JMP	NEXT
;
; ( --- ; [RP]++, jump to [IP] if [RP] < [RP+2]. )
	DB	86H,'(LOOP',')'+80H
	DW	ZBRAN-10
XLOOP	DW	$+2
	MOV	BX,1
XLOOP1:	ADD	[BP],BX
	MOV	AX,[BP]
	SUB	AX,2[BP]	; AX-[BP+2]
	XOR	AX,BX
	JS	BRAN1	; Jump to BRAN1 if (minus) sign flag is 1.
	ADD	BP,4
	INC	SI
	INC	SI
	JMP	NEXT
;
; ( n  --- ; [RP]+=n, jump to [IP] if [RP] < [RP+2]. )
	DB	87H,'(+LOOP',')'+80H
	DW	XLOOP-9
XPLOO	DW	$+2
	POP	BX	; BX=n
	JMP	XLOOP1
;
; ( n1 n2 --- ; Push n1, n2 to Return Stack. )
	DB	84H,'(DO',')'+80H
	DW	XPLOO-10
XDO	DW	$+2
	POP	DX
	POP	AX
	XCHG	BP,SP	; Exchange BP and SP.
	PUSH	AX
	PUSH	DX
	XCHG	BP,SP
	JMP	NEXT
;
; ( n1 n2 --- n3 ; n3 = n1 & n2 )
	DB	83H,'AN','D'+80H
	DW	XDO-7
ANDD	DW	$+2
	POP	AX
	POP	BX
	AND	AX,BX
	JMP	APUSH
;
; ( n1 n2 --- n3 ; n3 = n1 | n2 )
	DB	82H,'O','R'+80H
	DW	ANDD-6
ORR	DW	$+2
	POP	AX
	POP	BX
	OR	AX,BX
	JMP	APUSH
;
; ( n1 n2 --- n3 ; n3 = n1 ^ n2 )
	DB	83H,'XO','R'+80H
	DW	ORR-5
XORR	DW	$+2
	POP	AX
	POP	BX
	XOR	AX,BX
	JMP	APUSH
;
; ( --- n ; n = [SP] )
	DB	83H,'SP','@'+80H
	DW	XORR-6
SPAT	DW	$+2
	MOV	AX,SP
	JMP	APUSH
;
; ( --- ; Initialize SP. )
	DB	83H,'SP','!'+80H
	DW	SPAT-6
SPSTO	DW	$+2
	MOV	BX,UP
	MOV	SP,6[BX]	; SP=[BX+6]
	JMP	NEXT
;
; ( --- n ; n = [RP] )
	DB	83H,'RP','@'+80H
	DW	SPSTO-6
RPAT	DW	$+2
	MOV	AX,BP
	JMP	APUSH
;
; ( --- ; Initialize RP. )
	DB	83H,'RP','!'+80H
	DW	RPAT-6
RPSTO	DW	$+2
	MOV	BX,UP
	MOV	BP,8[BX]	; BP=[BX+8]
	JMP	NEXT
;
; ( --- ; IP <- pop from Return Stack. )
	DB	82H,';','S'+80H
	DW	RPSTO-6
SEMIS	DW	$+2
	MOV	SI,[BP]
	INC	BP
	INC	BP
	JMP	NEXT
;
; ( n --- ; Push n to Return Stack. )
	DB	82H,'>','R'+80H
	DW	SEMIS-5
TOR	DW	$+2
	POP	BX
	DEC	BP
	DEC	BP
	MOV	[BP],BX
	JMP	NEXT
;
; ( --- n ; Pop n from Return Stack. )
	DB	82H,'R','>'+80H
	DW	TOR-5
FROMR	DW	$+2
	MOV	AX,[BP]
	INC	BP
	INC	BP
	JMP	APUSH
;
; ( --- n ; Copy n from Return Stack. )
	DB	82H,'R','@'+80H
	DW	FROMR-5
RAT	DW	$+2
	MOV	AX,[BP]
	JMP	APUSH
;
; ( n --- f ; n = 0 ? )
	DB	82H,'0','='+80H
	DW	RAT-5
ZEQU	DW	$+2
	POP	AX
	OR	AX,AX
	MOV	AX,1
	JZ	$+3
	DEC	AX
	JMP	APUSH
;
; ( n --- f ; n < 0 ? )
	DB	82H,'0','<'+80H
	DW	ZEQU-5
ZLESS	DW	$+2
	POP	AX
	OR	AX,AX
	MOV	AX,1
	JS	$+3
	DEC	AX
	JMP	APUSH
;
; ( n1 n2 --- n3 ; n3 = n1 + n2 )
	DB	81H,'+'+80H
	DW	ZLESS-5
PLUS	DW	$+2
	POP	AX
	POP	BX
	ADD	AX,BX
	JMP	APUSH
;
; ( n1 n2 --- n3 ; n3 = n1 - n2 )
	DB	81H,'-'+80H
	DW	PLUS-4
SUBB	DW	$+2
	POP	DX
	POP	AX
	SUB	AX,DX
	JMP	APUSH
;
; ( d1 d2 --- d3 ; d3 = d1 + d2 )
	DB	82H,'D','+'+80H
	DW	SUBB-4
DPLUS	DW	$+2
	POP	AX
	POP	DX
	POP	BX
	POP	CX
	ADD	DX,CX
	ADC	AX,BX	; AX + BX + carry flag
	JMP	DPUSH
;
; ( d1 d2 --- d3 ; d3 = d1 - d2 )
	DB	82H,'D','-'+80H
	DW	DPLUS-5
DSUB	DW	$+2
	POP	BX
	POP	CX
	POP	AX
	POP	DX
	SUB	DX,CX
	SBB	AX,BX	; AX - BX - carry flag
	JMP	DPUSH
;
; ( n1 n2 --- n1 n2 n1 )
	DB	84H,'OVE','R'+80H
	DW	DSUB-5
OVER	DW	$+2
	POP	DX
	POP	AX
	PUSH	AX
	JMP	DPUSH
;
; ( n --- )
	DB	84H,'DRO','P'+80H
	DW	OVER-7
DROP	DW	$+2
	POP	AX
	JMP	NEXT
;
; ( n1 n2 --- n2 n1 )
	DB	84H,'SWA','P'+80H
	DW	DROP-7
SWAP	DW	$+2
	POP	DX
	POP	AX
	JMP	DPUSH
;
; ( n --- n n )
	DB	83H,'DU','P'+80H
	DW	SWAP-7
DUPE	DW	$+2
	POP	AX
	PUSH	AX
	JMP	APUSH
;
; ( n1 n2 n3 --- n2 n3 n1 )
	DB	83H,'RO','T'+80H
	DW	DUPE-6
ROT	DW	$+2
	POP	DX
	POP	BX
	POP	AX
	PUSH	BX
	JMP	DPUSH
;
; ( u1 u2 --- ud ; ud = u1 * u2 )
	DB	82H,'U','*'+80H
	DW	ROT-6
USTAR	DW	$+2
	POP	AX
	POP	BX
	MUL	BX	; DXAX=AX*BX
	XCHG	AX,DX	; Conversion to little endian.
	JMP	DPUSH
;
; ( ud1 u2 --- u3 u4 ; u3 = ud1 % u2, u4 = ud1 / u2 )
	DB	82H,'U','/'+80H
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
;
; ( n1 --- n2 ; n2 = n1 >> 1, arithmetical shift )
	DB	82H,'2','/'+80H
	DW	USLAS-5
TDIV	DW	$+2
	POP	AX
	SAR	AX,1	; AX>>1 (arithmetic!!)
	JMP	APUSH
;
; ( a b --- ; {a} <- {a} & b )
	DB	86H,'TOGGL','E'+80H
	DW	TDIV-5
TOGGL	DW	$+2
	POP	AX
	POP	BX
	XOR	[BX],AL
	JMP	NEXT
;
; ( a --- n ; n = [a] )
	DB	81H,'@'+80H
	DW	TOGGL-9
ATT	DW	$+2
	POP	BX
	MOV	AX,[BX]
	JMP	APUSH
;
; ( n a --- ; [a] <- n )
	DB	81H,'!'+80H
	DW	ATT-4
STORE	DW	$+2
	POP	BX
	POP	AX
	MOV	[BX],AX
	JMP	NEXT
;
; ( c a --- ; {a} <- c )
	DB	82H,'C','!'+80H
	DW	STORE-4
CSTOR	DW	$+2
	POP	BX
	POP	AX
	MOV	[BX],AL
	JMP	NEXT
;
; ( a1 a2 n --- ; n bytes copy )
; {a2}={a1}, {a2+1}={a1+1}, ...., {a2+n-1}={a1+n-1}
	DB	85H,'CMOV','E'+80H
	DW	CSTOR-5
CMOVEE	DW	$+2
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
;
; ( a1 a2 n --- ; reverse n bytes copy )
; {a2+n-1}={a1+n-1}, {a2+n-2}={a1+n-2}, ...., {a2}={a1}
	DB	86H,'<CMOV','E'+80H
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
;
; ( a n b --- ; Fill the n bytes on or after a with b. )
	DB	84H,'FIL','L'+80H
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
;
; ( --- ) <name>
	DB	0C1H,':'+80H
	DW	FILL-7
COLON	DW	DOCOL
	DW	QEXEC
	DW	SCSP
	DW	CURR
	DW	ATT
	DW	CONT
	DW	STORE
	DW	PCREAT
	DW	RBRAC
	DW	PSCOD
DOCOL:	INC	DX
	DEC	BP
	DEC	BP
	MOV	[BP],SI
	MOV	SI,DX
	JMP	NEXT
;
; ( n --- ) <name>
	DB	88H,'CONSTAN','T'+80H
	DW	COLON-4
CON	DW	DOCOL
	DW	PCREAT
	DW	SMUDG
	DW	COMMA
	DW	PSCOD
DOCON:	INC	DX
	MOV	BX,DX	; Pointer registers are only BX,BP,SI,DI!
	MOV	AX,[BX]
	JMP	APUSH
;
; ( --- ) <name>
	DB	88H,'VARIABL','E'+80H
	DW	CON-11
VAR	DW	DOCOL
	DW	ZERO
	DW	CON
	DW	PSCOD
DOVAR:	INC	DX
	PUSH	DX
	JMP	NEXT
;
; ( d --- ) <name>
	DB	89H,'2CONSTAN','T'+80H
	DW	VAR-11
TCON	DW	DOCOL
	DW	CON
	DW	COMMA
	DW	PSCOD
	INC	DX
	MOV	BX,DX
	MOV	AX,[BX]
	MOV	DX,2[BX]
	JMP	DPUSH
;
; ( --- ) <name>
	DB	89H,'2VARIABL','E'+80H
	DW	TCON-12
TVAR	DW	DOCOL
	DW	VAR
	DW	ZERO
	DW	COMMA
	DW	PSCOD
	INC	DX
	PUSH	DX
	JMP	NEXT
;
; ( n --- ) <name>
	DB	84H,'USE','R'+80H
	DW	TVAR-12
USER	DW	DOCOL
	DW	CON
	DW	PSCOD
DOUSE:	INC	DX
	MOV	BX,DX
	MOV	BL,[BX]
	SUB	BH,BH		; BHBL => 00BL
	MOV	DI,UP		; UP is the top of user area.
	LEA	AX,[BX+DI]	; AX=BX+DI
	JMP	APUSH
;
; ( --- a )
	DB	0C5H,'DOES','>'+80H
	DW	USER-7
DOES	DW	DOCOL
	DW	COMP
	DW	PSCOD
	DW	LIT,0E9H	; jump code ('JMP' = 0xE9)
	DW	CCOMM
	DW	LIT,XDOES-2
	DW	HERE
	DW	SUBB		; - ("JMP a" = "E9 a-$-2")
	DW	COMMA
	DW	SEMIS
XDOES:	XCHG	BP,SP
	PUSH	SI	; SI => return stack
	XCHG	BP,SP
	MOV	SI,[BX]
	ADD	SI,3H	; "E9 xxxx" is 3 bytes.
	INC	DX	; DX is the next address in the caller.
	PUSH	DX
	JMP	NEXT
;
; ( --- ) <name>
	DB	86H,'CREAT','E'+80H
	DW	DOES-8
CREAT	DW	DOCOL
	DW	PCREAT
	DW	SMUDG
	DW	PSCOD
	INC	DX
	PUSH	DX
	JMP	NEXT
;
; ( --- )
	DB	84H,'COL','D'+80H
	DW	CREAT-9
COLD	DW	DOCOL
	DW	LIT,UVR		; Set user variables.
	DW	UPP		; UP ( constant )
	DW	LIT,UVREND-UVR+2
	DW	CMOVEE
	DW	EMPBUF
	DW	ABORT
;
; ( --- )
	DB	84H,'WAR','M'+80H
	DW	COLD-7
WARM	DW	DOCOL
	DW	EMPBUF
	DW	ABORT
;
; ( --- c )
	DB	83H,'KE','Y'+80H
	DW	WARM-7
KEY	DW	DOCOL
	DW	CIN
	DW	SEMIS
;
; ( --- f )
	DB	89H,'?TERMINA','L'+80H
	DW	KEY-6
QTERM	DW	DOCOL
	DW	CTST
	DW	SEMIS
;
; ( c --- )
	DB	84H,'EMI','T'+80H
	DW	QTERM-12
EMIT	DW	DOCOL
	DW	DUPE
	DW	COUT
	DW	PFLAG		; print flag
	DW	ATT
	DW	ZBRAN,EMIT1-$	; IF
	DW	POUT
	DW	BRAN,EMIT2-$	; ELSE
EMIT1	DW	DROP
				; THEN
EMIT2	DW	SEMIS
;
; ( n1 a n2 --- ef ; 1 block only )
; n1: drive number
; a : address of disk buffer
; n2: reading block
; ef: error flag (0 or -1)
	DB	88H,'READ-RE','C'+80H
	DW	EMIT-7
RREC	DW	DOCOL
	DW	LIT,BBUF0/BPS
	DW	STAR
	DW	LIT,BBUF0/BPS
	DW	ZERO
	DW	XDO		; DO
RREC1	DW	THREE
	DW	PICK
	DW	THREE
	DW	PICK
	DW	THREE
	DW	PICK		;  copy 3 values
	DW	READ		;  ( n1 a n2' ef )
	DW	DUPE
	DW	ZBRAN,RREC2-$	;  IF ( n1 a n2' ef )
	DW	LLEAVE
	DW	BRAN,RREC3-$	;  ELSE ( n1 a n2' ef )
RREC2	DW	IDO
	DW	ONEP
	DW	LIT,BBUF0/BPS
	DW	LESS
	DW	ZBRAN,RREC3-$	;   IF ( n1 a n2' ef )
	DW	DROP		;    ( n1 a n2' )
	DW	SWAP
	DW	LIT,BPS
	DW	PLUS
	DW	SWAP
	DW	ONEP		;    ( n1 a+128 n2'+1 )
				;   THEN
				;  THEN
RREC3	DW	XLOOP,RREC1-$	; LOOP
	DW	TOR
	DW	TDROP
	DW	DROP
	DW	FROMR
	DW	SEMIS
;
; ( n1 a n2 --- ef ; 1 block only )
; n1: drive number
; a : address of disk buffer
; n2: writing block
; ef: error flag (0 or 1)
	DB	89H,'WRITE-RE','C'+80H
	DW	RREC-11
WREC	DW	DOCOL
	DW	LIT,BBUF0/BPS
	DW	STAR
	DW	LIT,BBUF0/BPS
	DW	ZERO
	DW	XDO		; DO
WREC1	DW	THREE
	DW	PICK
	DW	THREE
	DW	PICK
	DW	THREE
	DW	PICK		;  copy 3 values
	DW	WRITE		;  ( n1 a n2' ef )
	DW	DUPE
	DW	ZBRAN,WREC2-$	;  IF ( n1 a n2' ef )
	DW	LLEAVE
	DW	BRAN,WREC3-$	;  ELSE ( n1 a n2' ef )
WREC2	DW	IDO
	DW	ONEP
	DW	LIT,BBUF0/BPS
	DW	LESS
	DW	ZBRAN,WREC3-$	;   IF ( n1 a n2' ef )
	DW	DROP		;    ( n1 a n2' )
	DW	SWAP
	DW	LIT,BPS
	DW	PLUS
	DW	SWAP
	DW	ONEP		;    ( n1 a+128 n2'+1 )
				;   THEN
				;  THEN
WREC3	DW	XLOOP,WREC1-$	; LOOP
	DW	TOR
	DW	TDROP
	DW	DROP
	DW	FROMR
	DW	SEMIS
;
; 	===== constants =====
;
; ( --- n )
; (origin)
	DB	84H,'ORI','G'+80H
	DW	WREC-12
ORIGI	DW	DOCON
	DW	ORIG0
;
; ( --- n )
; (bytes per buffer)
	DB	85H,'B/BU','F'+80H
	DW	ORIGI-7
BBUF	DW	DOCON
	DW	BBUF0
;
; ( --- n )
; (buffer length)
	DB	85H,'BFLE','N'+80H
	DW	BBUF-8
BFLEN	DW	DOCON
	DW	BFLEN0
;
; ( --- n )
	DB	85H,'LIMI','T'+80H
	DW	BFLEN-8
LIMIT	DW	DOCON
	DW	LIMIT0
;
; ( --- n )
	DB	85H,'FIRS','T'+80H
	DW	LIMIT-8
FIRST	DW	DOCON
	DW	FIRST0
;
; ( --- n )
	DB	82H,'U','P'+80H
	DW	FIRST-8
UPP	DW	DOCON
	DW	UP
;
; ( --- n )
; (blank)
	DB	82H,'B','L'+80H
	DW	UPP-5
BLS	DW	DOCON
	DW	20H		; ' ' code
;
; ( --- n )
; (characters per line)
	DB	83H,'C/','L'+80H
	DW	BLS-5
CSLL	DW	DOCON
	DW	40H
;
; ( --- 0 )
	DB	81H,'0'+80H
	DW	CSLL-6
ZERO	DW	DOCON
	DW	0H
;
; ( --- 1 )
	DB	81H,'1'+80H
	DW	ZERO-4
ONE	DW	DOCON
	DW	1H
;
; ( --- 2 )
	DB	81H,'2'+80H
	DW	ONE-4
TWO	DW	DOCON
	DW	2H
;
; ( --- 3 )
	DB	81H,'3'+80H
	DW	TWO-4
THREE	DW	DOCON
	DW	3H
;
; ( --- -1 )
	DB	82H,'-','1'+80H
	DW	THREE-4
MONE	DW	DOCON
	DW	-1H
;
; ( --- n )
; (text input buffer length)
	DB	86H,'TIBLE','N'+80H
	DW	MONE-5
TIBLEN	DW	DOCON
	DW	50H
;
; ( --- n )
; (message screen)
	DB	86H,'MSGSC','R'+80H
	DW	TIBLEN-9
MSGSCR	DW	DOCON
	DW	4H
;
; ( --- n )
; (number of buffers)
	DB	85H,'#BUF','F'+80H
	DW	MSGSCR-9
NUMBUF	DW	DOCON
	DW	NUMBU0
;
; 	===== "unofficial" constants =====
;
; ( --- n )
; (screens per drive)
	DB	89H,'SCR/DRIV','E'+80H
	DW	NUMBUF-8
SCRDR	DW	DOCON
	DW	DRSIZ
;
; ( --- n )
; (the initial value table of user variables)
	DB	83H,'UV','R'+80H
	DW	SCRDR-12
TUVR	DW	DOCON
	DW	UVR
;
; 	===== variables =====
;
; ( --- a )
	DB	83H,'US','E'+80H
	DW	TUVR-6
USE	DW	DOVAR
	DW	FIRST0
;
; ( --- a )
; (previous)
	DB	84H,'PRE','V'+80H
	DW	USE-6
PREV	DW	DOVAR
	DW	FIRST0
;
; ( --- a )
	DB	8AH,'DISK-ERRO','R'+80H
	DW	PREV-7
DSKERR	DW	DOVAR
	DW	0H
;
; 	===== user variables =====
;
; ( --- a )
	DB	82H,'S','0'+80H
	DW	DSKERR-13
SZERO	DW	DOUSE
	DW	06H
;
; ( --- a )
	DB	82H,'R','0'+80H
	DW	SZERO-5
RZERO	DW	DOUSE
	DW	08H
;
; ( --- a )
; (terminal input buffer)
	DB	83H,'TI','B'+80H
	DW	RZERO-5
TIB	DW	DOUSE
	DW	0AH
;
; ( --- a )
	DB	85H,'WIDT','H'+80H
	DW	TIB-6
WYDTH	DW	DOUSE
	DW	0CH
;
; ( --- a )
	DB	87H,'WARNIN','G'+80H
	DW	WYDTH-8
WARN	DW	DOUSE
	DW	0EH
;
; ( --- a )
; (fence for FORGETting)
	DB	85H,'FENC','E'+80H
	DW	WARN-10
FENCE	DW	DOUSE
	DW	10H
;
; ( --- a )
	DB	82H,'D','P'+80H
	DW	FENCE-8
DP	DW	DOUSE
	DW	12H
;
; ( --- a )
; (vocabulary link)
	DB	88H,'VOC-LIN','K'+80H
	DW	DP-5
VOCL	DW	DOUSE
	DW	14H
;
; ( --- a )
; (blocK)
	DB	83H,'BL','K'+80H
	DW	VOCL-11
BLK	DW	DOUSE
	DW	16H
;
; ( --- a )
; (to in)
	DB	83H,'>I','N'+80H
	DW	BLK-6
INN	DW	DOUSE
	DW	18H
;
; ( --- a )
	DB	83H,'OU','T'+80H
	DW	INN-6
OUTT	DW	DOUSE
	DW	1AH
;
; ( --- a )
; (screen)
	DB	83H,'SC','R'+80H
	DW	OUTT-6
SCR	DW	DOUSE
	DW	1CH
;
; ( --- a )
	DB	86H,'OFFSE','T'+80H
	DW	SCR-6
OFSET	DW	DOUSE
	DW	1EH
;
; ( --- a )
; (context vocabulary)
	DB	87H,'CONTEX','T'+80H
	DW	OFSET-9
CONT	DW	DOUSE
	DW	20H
;
; ( --- a )
; (current vocabulary)
	DB	87H,'CURREN','T'+80H
	DW	CONT-10
CURR	DW	DOUSE
	DW	22H
;
; ( --- a )
; (compilation state)
	DB	85H,'STAT','E'+80H
	DW	CURR-10
STATE	DW	DOUSE
	DW	24H
;
; ( --- a )
; (base n)
	DB	84H,'BAS','E'+80H
	DW	STATE-8
BASE	DW	DOUSE
	DW	26H
;
; ( --- a )
; (decimal point location)
	DB	83H,'DP','L'+80H
	DW	BASE-7
DPL	DW	DOUSE
	DW	28H
;
; ( --- a )
; (number output field width)
; A user variable for control of number output field width.
; Presently unused in this FORTH.
	DB	83H,'FL','D'+80H
	DW	DPL-6
FLDD	DW	DOUSE
	DW	2AH
;
; ( --- a )
; (check stack position)
	DB	83H,'CS','P'+80H
	DW	FLDD-6
CSP	DW	DOUSE
	DW	2CH
;
; ( --- a )
; (R number)
; A user variable which may contain the location of
; an editing cursor, or other file related function.
	DB	82H,'R','#'+80H
	DW	CSP-6
RNUM	DW	DOUSE
	DW	2EH
;
; ( --- a )
; (held)
; A user variable that holds the address of the latest
; character of text during numeric output conversion.
	DB	83H,'HL','D'+80H
	DW	RNUM-5
HLD	DW	DOUSE
	DW	30H
;
; ( --- a )
; (printer flag)
	DB	85H,'PFLA','G'+80H
	DW	HLD-6
PFLAG	DW	DOUSE
	DW	32H
;
; 	===== normal words =====
;
; ( a c --- a n1 n2 n3 )
; a : start address in text data
; c : delimiter code
; n1: offset to the first non-delimiter character
; n2: offset to the first delimiter after text
; n3: offset to the first character not included
	DB	87H,'ENCLOS','E'+80H
	DW	PFLAG-8
ENCL	DW	DOCOL
	DW	OVER
	DW	DUPE
	DW	TOR
				; BEGIN
ENCL1	DW	TDUP
	DW	CAT
	DW	EQUAL
	DW	OVER
	DW	CAT
	DW	ZEQU
	DW	ZBRAN,ENCL5-$	;  IF ( [n1] is null )
	DW	DROP
	DW	SWAP
	DW	DROP
	DW	FROMR
	DW	SUBB
	DW	DUPE
	DW	ONEP
	DW	OVER		;   ( a n1 n1+1 n1 )
	DW	SEMIS		;   EXIT
				;  THEN
ENCL5	DW	ZBRAN,ENCL2-$	; WHILE
	DW	ONEP
	DW	BRAN,ENCL1-$	; REPEAT
ENCL2	DW	DUPE
	DW	TOR
	DW	ONEP
				; BEGIN
ENCL3	DW	TDUP
	DW	CAT
	DW	NEQ
	DW	OVER
	DW	CAT
	DW	ZEQU
	DW	ZBRAN,ENCL6-$	;  IF ( [n2] is null )
	DW	DROP
	DW	SWAP
	DW	DROP
	DW	OVER
	DW	SUBB
	DW	FROMR
	DW	FROMR
	DW	SUBB
	DW	SWAP
	DW	DUPE		;   ( a n1 n2 n2 )
	DW	SEMIS		;   EXIT
				;  THEN
ENCL6	DW	ZBRAN,ENCL4-$	; WHILE
	DW	ONEP
	DW	BRAN,ENCL3-$	; REPEAT ( [n1],[n2] <> null )
ENCL4	DW	SWAP
	DW	DROP
	DW	OVER
	DW	SUBB
	DW	FROMR
	DW	FROMR
	DW	SUBB
	DW	SWAP
	DW	DUPE
	DW	ONEP		; ( a n1 n2 n2+1 )
	DW	SEMIS
;
; ( a1 a2 --- a / ff ;
;             Search a FORCE WORD in the FORTH DICTIONARY. )
; a1: top address of text string searched
; a2: NFA at which start searching
; a : CFA of the found word
; ff: false flag
; ***** ASSEMBLY VERSION *****
	DB	86H,'(FIND',')'+80H
	DW	ENCL-10
PFIND	DW	$+2
	MOV	AX,DS
	MOV	ES,AX
	POP	BX	; a2
	POP	CX	; a1
PFIN1:	MOV	DI,CX
	MOV	AL,[BX]
	MOV	DL,AL
	XOR	AL,[DI]
	AND	AL,3FH
	JNZ	PFIN3
PFIN2:	INC	BX
	INC	DI
	MOV	AL,[BX]
	XOR	AL,[DI]
	ADD	AL,AL
	JNZ	PFIN3
	JNB	PFIN2	; when carry flag == 0
	ADD	BX,3	; Compute CFA
	PUSH	BX	; a
	JMP	NEXT
PFIN3:	INC	BX
	JB	PFIN4	; when carry flag == 1
	MOV	AL,[BX]
	ADD	AL,AL
	JMP	PFIN3
PFIN4:	MOV	BX,[BX]
	OR	BX,BX
	JNZ	PFIN1
	MOV	AX,0	; ff
	JMP	APUSH
; ****************************
;	DB	86H,'(FIND',')'+80H
;	DW	ENCL-10
;PFIND	DW	DOCOL
				; BEGIN
;PFIND1	DW	OVER
;	DW	TDUP
;	DW	CAT
;	DW	SWAP
;	DW	CAT
;	DW	LIT,3FH
;	DW	ANDD		;  ( length and smudge bits )
;	DW	EQUAL
;	DW	ZBRAN,PFIND2-$	;  IF
				;   BEGIN
;PFIND4	DW	ONEP
;	DW	SWAP
;	DW	ONEP
;	DW	SWAP
;	DW	TDUP
;	DW	CAT
;	DW	SWAP
;	DW	CAT
;	DW	NEQ
;	DW	ZBRAN,PFIND4-$	;   UNTIL
;	DW	CAT
;	DW	OVER
;	DW	CAT
;	DW	LIT,7FH
;	DW	ANDD
;	DW	EQUAL
;	DW	ZBRAN,PFIND5-$	;   IF ( found )
;	DW	SWAP
;	DW	DROP
;	DW	THREE
;	DW	PLUS
;	DW	SEMIS		;    EXIT
				;   THEN
;PFIND5	DW	ONEM
;	DW	BRAN,PFIND3-$	;  ELSE
;PFIND2	DW	DROP
				;  THEN ( next word )
				;  BEGIN
;PFIND3	DW	ONEP
;	DW	DUPE
;	DW	CAT
;	DW	LIT,80H
;	DW	ANDD
;	DW	ZBRAN,PFIND3-$	;  UNTIL
;	DW	ONEP
;	DW	ATT
;	DW	DUPE
;	DW	LIT,0H
;	DW	EQUAL
;	DW	ZBRAN,PFIND6-$	;  IF ( last word )
;	DW	TDROP
;	DW	ZERO		;   ( unfound )
;	DW	SEMIS		;   EXIT
				;  THEN
;PFIND6	DW	BRAN,PFIND1-$	; AGAIN
;
; ( c n1 --- n2 tf / ff )
; c : character code
; n1: base value
; n2: number n2 whom c means in base n1
; tf: true flag
; ff: false flag
	DB	85H,'DIGI','T'+80H
	DW	PFIND-9
DIGIT	DW	DOCOL
	DW	SWAP
	DW	LIT,30H		; 30 ( '0' code )
	DW	SUBB
	DW	DUPE
	DW	ZLESS
	DW	ZBRAN,DIGI1-$	; IF
	DW	TDROP
	DW	ZERO
	DW	BRAN,DIGI2-$	; ELSE
DIGI1	DW	DUPE
	DW	LIT,9H
	DW	GREAT
	DW	ZBRAN,DIGI3-$	;  IF
	DW	LIT,7H		;   7 ( ":;<=>?@" )
	DW	SUBB
	DW	DUPE
	DW	LIT,0AH
	DW	LESS
	DW	ZBRAN,DIGI4-$	;   IF
	DW	TDROP
	DW	ZERO
	DW	BRAN,DIGI5-$	;   ELSE
DIGI4	DW	TDUP
	DW	GREAT
	DW	ZBRAN,DIGI6-$	;    IF
	DW	SWAP
	DW	DROP
	DW	ONE
	DW	BRAN,DIGI5-$	;    ELSE
DIGI6	DW	TDROP
	DW	ZERO
				;    THEN
				;   THEN
DIGI5	DW	BRAN,DIGI2-$	;  ELSE
DIGI3	DW	TDUP
	DW	GREAT
	DW	ZBRAN,DIGI7-$	;   IF
	DW	SWAP
	DW	DROP
	DW	ONE
	DW	BRAN,DIGI2-$	;   ELSE
DIGI7	DW	TDROP
	DW	ZERO
				;   THEN
				;  THEN
				; THEN
DIGI2	DW	SEMIS
;
; ( n --- -n )
	DB	86H,'NEGAT','E'+80H
	DW	DIGIT-8
MINUS	DW	DOCOL
	DW	ZERO
	DW	SWAP
	DW	SUBB
	DW	SEMIS
;
; ( d --- -d )
	DB	87H,'DNEGAT','E'+80H
	DW	MINUS-9
DMINUS	DW	DOCOL
	DW	TOR
	DW	TOR
	DW	ZERO,ZERO
	DW	FROMR
	DW	FROMR
	DW	DSUB
	DW	SEMIS
;
; ( n a --- ; [a] <- [a]+n )
	DB	82H,'+','!'+80H
	DW	DMINUS-10
PSTOR	DW	DOCOL
	DW	SWAP
	DW	OVER
	DW	ATT
	DW	PLUS
	DW	SWAP
	DW	STORE
	DW	SEMIS
;
; ( a n --- ; Fill with nulls. )
	DB	85H,'ERAS','E'+80H
	DW	PSTOR-5
ERASE	DW	DOCOL
	DW	ZERO
	DW	FILL
	DW	SEMIS
;
; ( a n --- ; Fill with blanks. )
	DB	86H,'BLANK','S'+80H
	DW	ERASE-8
BLANK	DW	DOCOL
	DW	BLS
	DW	FILL
	DW	SEMIS
;
; ( n1 n2 n3 --- n3 n1 n2 )
	DB	84H,'<RO','T'+80H
	DW	BLANK-9
LROT	DW	DOCOL
	DW	ROT
	DW	ROT
	DW	SEMIS
;
; ( a --- c ; c = [a] )
	DB	82H,'C','@'+80H
	DW	LROT-7
CAT	DW	DOCOL
	DW	ATT
	DW	LIT,0FFH
	DW	ANDD
	DW	SEMIS
;
; ( f1 --- f2 )
	DB	83H,'NO','T'+80H
	DW	CAT-5
NOTT	DW	DOCOL
	DW	ZEQU
	DW	SEMIS
;
; ( n1 n2 --- f )
	DB	81H,'='+80H
	DW	NOTT-6
EQUAL	DW	DOCOL
	DW	SUBB
	DW	ZEQU
	DW	SEMIS
;
; ( n1 n2 --- f )
	DB	82H,'<','>'+80H
	DW	EQUAL-4
NEQ	DW	DOCOL
	DW	EQUAL
	DW	NOTT
	DW	SEMIS
;
; ( n1 n2 --- f )
	DB	81H,'<'+80H
	DW	NEQ-5
LESS	DW	DOCOL
	DW	SUBB
	DW	ZLESS
	DW	SEMIS
;
; ( n1 n2 --- f )
	DB	81H,'>'+80H
	DW	LESS-4
GREAT	DW	DOCOL
	DW	SWAP
	DW	LESS
	DW	SEMIS
;
	DB	82H,'0','>'+80H
	DW	GREAT-4
ZGREAT	DW	DOCOL
	DW	ZERO
	DW	GREAT
	DW	SEMIS
;
; ( u1 u2 --- f )
	DB	82H,'U','<'+80H
	DW	ZGREAT-5
ULESS	DW	DOCOL
	DW	TDUP
	DW	XORR
	DW	ZLESS
	DW	ZBRAN,ULESS1-$	; IF ( u1's MSB <> u2's MSB)
	DW	DROP
	DW	ZLESS		;  ( u1's MSB = 1 ? )
	DW	ZEQU		;  ( u1's MSB = 0 ? )
	DW	BRAN,ULESS2-$	; ELSE
ULESS1	DW	SUBB
	DW	ZLESS		;  (u1 < u2 ? )
				; THEN
ULESS2	DW	SEMIS
;
; ( d1 d2 --- f )
	DB	82H,'D','<'+80H
	DW	ULESS-5
DLESS	DW	DOCOL
	DW	DSUB
	DW	SWAP
	DW	DROP
	DW	ZLESS
	DW	SEMIS
;
; ( n1 n2 --- n3 )
	DB	83H,'MI','N'+80H
	DW	DLESS-5
MIN	DW	DOCOL
	DW	TDUP
	DW	GREAT
	DW	ZBRAN,MIN1-$	; IF
	DW	SWAP
				; THEN
MIN1	DW	DROP
	DW	SEMIS
;
; ( n1 n2 --- n3 )
	DB	83H,'MA','X'+80H
	DW	MIN-6
MAX	DW	DOCOL
	DW	TDUP
	DW	LESS
	DW	ZBRAN,MAX1-$	; IF
	DW	SWAP
				; THEN
MAX1	DW	DROP
	DW	SEMIS
;
; ( n1 n2 --- n3 ; n1 if n2 >= 0, -n1 if n2 < 0. )
	DB	82H,'+','-'+80H
	DW	MAX-6
PM	DW	DOCOL
	DW	ZLESS
	DW	ZBRAN,PM1-$	; IF
	DW	MINUS		;  NEGATE
				; THEN
PM1	DW	SEMIS
;
; ( n --- u )
	DB	83H,'AB','S'+80H
	DW	PM-5
ABSO	DW	DOCOL
	DW	DUPE
	DW	PM
	DW	SEMIS
;
; ( d1 n --- d2 ;d1 if n >= 0, -d1 if n < 0. )
	DB	83H,'D+','-'+80H
	DW	ABSO-6
DPM	DW	DOCOL
	DW	ZLESS
	DW	ZBRAN,DPM1-$	; IF
	DW	DMINUS		;  DNEGATE
				; THEN
DPM1	DW	SEMIS
;
; ( d --- ud )
	DB	84H,'DAB','S'+80H
	DW	DPM-6
DABS	DW	DOCOL
	DW	DUPE
	DW	DPM
	DW	SEMIS
;
; ( n --- n n / 0 )
	DB	84H,'?DU','P'+80H
	DW	DABS-7
QDUP	DW	DOCOL
	DW	DUPE
	DW	ZBRAN,QDUP1-$	; IF
	DW	DUPE
				; THEN
QDUP1	DW	SEMIS
;
; ( n --- d )
	DB	84H,'S->','D'+80H
	DW	QDUP-7
STOD	DW	DOCOL
	DW	DUPE
	DW	ZLESS
	DW	ZBRAN,STOD1-$	; IF
	DW	MONE
	DW	BRAN,STOD2-$	; ELSE
STOD1	DW	ZERO
				; THEN
STOD2	DW	SEMIS
;
; ( n1 n2 --- d ; d = n1 * n2 )
	DB	82H,'M','*'+80H
	DW	STOD-7
MSTAR	DW	DOCOL
	DW	TDUP
	DW	XORR
	DW	TOR
	DW	ABSO
	DW	SWAP
	DW	ABSO
	DW	USTAR
	DW	FROMR
	DW	DPM
	DW	SEMIS
;
; ( n1 n2 --- n3 ; n3 = n1 * n2 )
	DB	81H,'*'+80H
	DW	MSTAR-5
STAR	DW	DOCOL
	DW	MSTAR
	DW	DROP
	DW	SEMIS
;
; ( ud1 u2 --- u3 ud4 ; u3 = ud1 % u2, ud4 = ud1 / u2 )
	DB	85H,'M/MO','D'+80H
	DW	STAR-4
MSMOD	DW	DOCOL
	DW	TOR
	DW	ZERO
	DW	RAT
	DW	USLAS
	DW	FROMR
	DW	SWAP
	DW	TOR
	DW	USLAS
	DW	FROMR
	DW	SEMIS
;
; ( d n1 --- n2 n3 ; n2 = d % n1, n3 = d / n1 )
	DB	82H,'M','/'+80H
	DW	MSMOD-8
MSLAS	DW	DOCOL
	DW	OVER
	DW	TOR
	DW	TOR
	DW	DABS
	DW	RAT
	DW	ABSO
	DW	USLAS
	DW	FROMR
	DW	RAT
	DW	XORR
	DW	PM
	DW	SWAP
	DW	FROMR
	DW	PM
	DW	SWAP
	DW	SEMIS
;
; ( n1 n2 --- n3 n4 ; n3 = n1 % n2, n4 = n1 / n2 )
	DB	84H,'/MO','D'+80H
	DW	MSLAS-5
SLMOD	DW	DOCOL
	DW	TOR
	DW	STOD
	DW	FROMR
	DW	MSLAS
	DW	SEMIS
;
; ( n1 n2 n3 --- n4 n5 ; n4 = n1 * n2 % n3, n5 = n1 * n2 / n3 )
	DB	85H,'*/MO','D'+80H
	DW	SLMOD-7
SSMOD	DW	DOCOL
	DW	TOR
	DW	MSTAR
	DW	FROMR
	DW	MSLAS
	DW	SEMIS
;
; ( n1 n2 --- n3 ; n3 = n1 % n2 )
	DB	83H,'MO','D'+80H
	DW	SSMOD-8
MODD	DW	DOCOL
	DW	SLMOD
	DW	DROP
	DW	SEMIS
;
; ( n1 n2 --- n3 ; n3 = n1 / n2 )
	DB	81H,'/'+80H
	DW	MODD-6
SLASH	DW	DOCOL
	DW	SLMOD
	DW	SWAP
	DW	DROP
	DW	SEMIS
;
; ( n1 n2 --- n1 n2 n1 n2 )
	DB	84H,'2DU','P'+80H
	DW	SLASH-4
TDUP	DW	DOCOL
	DW	OVER
	DW	OVER
	DW	SEMIS
;
; ( n1 n2 --- )
	DB	85H,'2DRO','P'+80H
	DW	TDUP-7
TDROP	DW	DOCOL
	DW	DROP
	DW	DROP
	DW	SEMIS
;
; ( a --- d )
	DB	82H,'2','@'+80H
	DW	TDROP-8
TAT	DW	DOCOL
	DW	DUPE
	DW	ATT
	DW	SWAP
	DW	TWOP
	DW	ATT
	DW	SEMIS
;
; ( n --- n+1 )
	DB	82H,'1','+'+80H
	DW	TAT-5
ONEP	DW	DOCOL
	DW	ONE
	DW	PLUS
	DW	SEMIS
;
; ( n --- n+2 )
	DB	82H,'2','+'+80H
	DW	ONEP-5
TWOP	DW	DOCOL
	DW	TWO
	DW	PLUS
	DW	SEMIS
;
; ( n --- n-1 )
	DB	82H,'1','-'+80H
	DW	TWOP-5
ONEM	DW	DOCOL
	DW	ONE
	DW	SUBB
	DW	SEMIS
;
; ( n --- n-2 )
	DB	82H,'2','-'+80H
	DW	ONEM-5
TWOM	DW	DOCOL
	DW	TWO
	DW	SUBB
	DW	SEMIS
;
; ( n --- n+n )
	DB	82H,'2','*'+80H
	DW	TWOM-5
TWOS	DW	DOCOL
	DW	DUPE
	DW	PLUS
	DW	SEMIS
;
; ( c --- )
	DB	84H,'HOL','D'+80H
	DW	TWOS-5
HOLD	DW	DOCOL
	DW	MONE
	DW	HLD
	DW	PSTOR
	DW	HLD
	DW	ATT
	DW	CSTOR
	DW	SEMIS
;
; ( ud1 --- ud2 )
	DB	81H,'#'+80H
	DW	HOLD-7
DIG	DW	DOCOL
	DW	BASE
	DW	ATT
	DW	MSMOD
	DW	ROT
	DW	LIT,9H
	DW	OVER
	DW	LESS
	DW	ZBRAN,DIG1-$	; IF
	DW	LIT,7H		;  7 ( ":;<=>?@" )
	DW	PLUS
				; THEN
DIG1	DW	LIT,30H		; 30 ( '0' code )
	DW	PLUS
	DW	HOLD
	DW	SEMIS
;
; ( ud1 --- ud2 ; ud2 = 0.0 )
	DB	82H,'#','S'+80H
	DW	DIG-4
DIGS	DW	DOCOL
				; BEGIN
DIGS1	DW	DIG
	DW	TDUP
	DW	ORR
	DW	ZEQU
	DW	ZBRAN,DIGS1-$	; UNTIL
	DW	SEMIS
;
; ( --- )
	DB	82H,'<','#'+80H
	DW	DIGS-5
BDIGS	DW	DOCOL
	DW	PAD
	DW	HLD
	DW	STORE
	DW	SEMIS
;
; ( d --- a n )
	DB	82H,'#','>'+80H
	DW	BDIGS-5
EDIGS	DW	DOCOL
	DW	TDROP
	DW	HLD
	DW	ATT
	DW	PAD
	DW	OVER
	DW	SUBB
	DW	SEMIS
;
; ( n ud --- ud )
	DB	84H,'SIG','N'+80H
	DW	EDIGS-5
SIGN	DW	DOCOL
	DW	ROT
	DW	ZLESS
	DW	ZBRAN,SIGN1-$	; IF
	DW	LIT,2DH		;  ( '-' code )
	DW	HOLD
				; THEN
SIGN1	DW	SEMIS
;
; ( a --- a+1 n )
	DB	85H,'COUN','T'+80H
	DW	SIGN-7
COUNT	DW	DOCOL
	DW	DUPE
	DW	ONEP
	DW	SWAP
	DW	CAT
	DW	SEMIS
;
; ( a n --- )
	DB	84H,'TYP','E'+80H
	DW	COUNT-8
TYPES	DW	DOCOL
	DW	QDUP
	DW	ZBRAN,TYPES1-$	; IF
	DW	OVER
	DW	PLUS
	DW	SWAP
	DW	XDO		;  DO
TYPES3	DW	IDO
	DW	CAT
	DW	EMIT
	DW	XLOOP,TYPES3-$	;  LOOP
	DW	BRAN,TYPES2-$	; ELSE
TYPES1	DW	DROP
				; THEN
TYPES2	DW	SEMIS
;
; ( --- )
	DB	82H,'C','R'+80H
	DW	TYPES-7
CR	DW	DOCOL
	DW	LIT,0DH		; ( CR code )
	DW	EMIT
	DW	LIT,0AH		; ( LF code )
	DW	EMIT
	DW	SEMIS
;
; ( --- )
	DB	85H,'SPAC','E'+80H
	DW	CR-5
SPACE	DW	DOCOL
	DW	BLS
	DW	EMIT
	DW	SEMIS
;
; ( n --- )
	DB	86H,'SPACE','S'+80H
	DW	SPACE-8
SPACS	DW	DOCOL
	DW	ZERO
	DW	MAX
	DW	QDUP
	DW	ZBRAN,SPACS1-$	; IF
	DW	ZERO
	DW	XDO		;  DO
SPACS2	DW	SPACE
	DW	XLOOP,SPACS2-$	;  LOOP
				; THEN
SPACS1	DW	SEMIS
;
; ( a n1 --- a n2 )
	DB	89H,'-TRAILIN','G'+80H
	DW	SPACS-9
DTRAI	DW	DOCOL
	DW	DUPE
	DW	ZERO
	DW	XDO		; DO
DTRAI1	DW	TDUP
	DW	PLUS
	DW	ONEM
	DW	CAT
	DW	BLS
	DW	SUBB
	DW	ZBRAN,DTRAI2-$	;  IF
	DW	LLEAVE
	DW	BRAN,DTRAI3-$	;  ELSE
DTRAI2	DW	ONEM
				;  THEN
DTRAI3	DW	XLOOP,DTRAI1-$	; LOOP
	DW	SEMIS
;
; ( --- )
	DB	84H,'(."',')'+80H
	DW	DTRAI-12
PDOTQ	DW	DOCOL
	DW	RAT
	DW	COUNT
	DW	DUPE
	DW	ONEP
	DW	FROMR
	DW	PLUS
	DW	TOR
	DW	TYPES
	DW	SEMIS
;
; ( --- )
	DB	0C2H,'.','"'+80H
	DW	PDOTQ-7
DOTQ	DW	DOCOL
	DW	LIT,22H		; ( '"' code )
	DW	STATE
	DW	ATT
	DW	ZBRAN,DOTQ1-$	; IF
	DW	COMP
	DW	PDOTQ
	DW	WORDS
	DW	CAT
	DW	ONEP
	DW	ALLOT
	DW	BRAN,DOTQ2-$	; ELSE
DOTQ1	DW	WORDS
	DW	COUNT
	DW	TYPES
				; THEN
DOTQ2	DW	SEMIS
;
; ( d n --- )
	DB	83H,'D.','R'+80H
	DW	DOTQ-5
DDOTR	DW	DOCOL
	DW	TOR
	DW	SWAP
	DW	OVER
	DW	DABS
	DW	BDIGS
	DW	DIGS
	DW	SIGN
	DW	EDIGS
	DW	FROMR
	DW	OVER
	DW	SUBB
	DW	SPACS
	DW	TYPES
	DW	SEMIS
;
; ( d --- )
	DB	82H,'D','.'+80H
	DW	DDOTR-6
DDOT	DW	DOCOL
	DW	ZERO
	DW	DDOTR
	DW	SPACE
	DW	SEMIS
;
; ( n --- )
	DB	82H,'U','.'+80H
	DW	DDOT-5
UDOT	DW	DOCOL
	DW	ZERO
	DW	DDOT
	DW	SEMIS
;
; ( n1 n2 --- )
	DB	82H,'.','R'+80H
	DW	UDOT-5
DOTR	DW	DOCOL
	DW	TOR
	DW	STOD
	DW	FROMR
	DW	DDOTR
	DW	SEMIS
;
; ( n --- )
	DB	81H,'.'+80H
	DW	DOTR-5
DOT	DW	DOCOL
	DW	STOD
	DW	DDOT
	DW	SEMIS
;
; ( --- )
	DB	87H,'DECIMA','L'+80H
	DW	DOT-4
DECA	DW	DOCOL
	DW	LIT,0AH
	DW	BASE
	DW	STORE
	DW	SEMIS
;
; ( --- )
	DB	83H,'HE','X'+80H
	DW	DECA-10
HEX	DW	DOCOL
	DW	LIT,10H
	DW	BASE
	DW	STORE
	DW	SEMIS
;
; ( line scr --- a C/L )
	DB	86H,'(LINE',')'+80H
	DW	HEX-6
PLINE	DW	DOCOL
	DW	TOR
	DW	CSLL
	DW	BBUF
	DW	SSMOD
	DW	FROMR
	DW	PLUS
	DW	BLOCK
	DW	PLUS
	DW	CSLL
	DW	SEMIS
;
; ( line scr --- )
	DB	85H,'.LIN','E'+80H
	DW	PLINE-9
DLINE	DW	DOCOL
	DW	PLINE
	DW	DTRAI
	DW	TYPES
	DW	SEMIS
;
; ( --- )
	DB	85H,'?COM','P'+80H
	DW	DLINE-8
QCOMP	DW	DOCOL
	DW	STATE
	DW	ATT
	DW	ZEQU
	DW	LIT,11H
	DW	QERR
	DW	SEMIS
;
; ( --- )
	DB	85H,'?EXE','C'+80H
	DW	QCOMP-8
QEXEC	DW	DOCOL
	DW	STATE
	DW	ATT
	DW	LIT,12H
	DW	QERR
	DW	SEMIS
;
; ( --- )
	DB	86H,'?STAC','K'+80H
	DW	QEXEC-8
QSTAC	DW	DOCOL
	DW	SPAT
	DW	SZERO
	DW	ATT
	DW	SWAP
	DW	ULESS
	DW	ONE
	DW	QERR
	DW	SPAT
	DW	HERE
	DW	LIT,TMPBSZ
	DW	PLUS
	DW	ULESS
	DW	LIT,7H
	DW	QERR
	DW	SEMIS
;
; ( n1 n2 --- )
	DB	86H,'?PAIR','S'+80H
	DW	QSTAC-9
QPAIR	DW	DOCOL
	DW	EQUAL
	DW	NOTT
	DW	LIT,13H
	DW	QERR
	DW	SEMIS
;
; ( --- )
	DB	88H,'?LOADIN','G'+80H
	DW	QPAIR-9
QLOAD	DW	DOCOL
	DW	BLK
	DW	ATT
	DW	ZEQU
	DW	LIT,16H
	DW	QERR
	DW	SEMIS
;
; ( --- )
	DB	84H,'?CS','P'+80H
	DW	QLOAD-11
QCSP	DW	DOCOL
	DW	SPAT
	DW	CSP
	DW	ATT
	DW	SUBB
	DW	LIT,14H
	DW	QERR
	DW	SEMIS
;
; ( --- )
	DB	84H,'!CS','P'+80H
	DW	QCSP-7
SCSP	DW	DOCOL
	DW	SPAT
	DW	CSP
	DW	STORE
	DW	SEMIS
;
; ( --- ) <word>
	DB	87H,'COMPIL','E'+80H
	DW	SCSP-7
COMP	DW	DOCOL
	DW	QCOMP
	DW	FROMR
	DW	DUPE
	DW	TWOP
	DW	TOR
	DW	ATT
	DW	COMMA
	DW	SEMIS
;
; ( --- ) <word>
	DB	0C9H,'[COMPILE',']'+80H
	DW	COMP-10
BCOMP	DW	DOCOL
	DW	FIND
	DW	QDUP
	DW	ZEQU
	DW	ZERO
	DW	QERR
	DW	COMMA
	DW	SEMIS
;
; ( n --- )
	DB	0C7H,'LITERA','L'+80H
	DW	BCOMP-12
LITER	DW	DOCOL
	DW	STATE
	DW	ATT
	DW	ZBRAN,LITER1-$	; IF
	DW	COMP
	DW	LIT
	DW	COMMA
				; THEN
LITER1	DW	SEMIS
;
; ( d --- )
	DB	0C8H,'DLITERA','L'+80H
	DW	LITER-10
DLITE	DW	DOCOL
	DW	STATE
	DW	ATT
	DW	ZBRAN,DLITE1-$	; IF
	DW	SWAP
	DW	LITER		;  [COMPILE] LITERAL
	DW	LITER		;  [COMPILE] LITERAL
				; THEN
DLITE1	DW	SEMIS
;
; ( --- )
	DB	8BH,'DEFINITION','S'+80H
	DW	DLITE-11
DEFIN	DW	DOCOL
	DW	CONT
	DW	ATT
	DW	CURR
	DW	STORE
	DW	SEMIS
;
; ( n --- )
	DB	85H,'ALLO','T'+80H
	DW	DEFIN-14
ALLOT	DW	DOCOL
	DW	DP
	DW	PSTOR
	DW	SEMIS
;
; ( --- a )
	DB	84H,'HER','E'+80H
	DW	ALLOT-8
HERE	DW	DOCOL
	DW	DP
	DW	ATT
	DW	SEMIS
;
; ( --- a )
	DB	83H,'PA','D'+80H
	DW	HERE-7
PAD	DW	DOCOL
	DW	HERE
	DW	LIT,WRDBSZ
	DW	PLUS
	DW	SEMIS
;
; ( --- a )
	DB	86H,'LATES','T'+80H
	DW	PAD-6
LATES	DW	DOCOL
	DW	CURR
	DW	ATT
	DW	ATT
	DW	SEMIS
;
; ( --- )
	DB	86H,'SMUDG','E'+80H
	DW	LATES-9
SMUDG	DW	DOCOL
	DW	LATES
	DW	LIT,20H		; ( = 0b 10 0000 )
	DW	TOGGL
	DW	SEMIS
;
; ( n --- a )
	DB	87H,'+ORIGI','N'+80H
	DW	SMUDG-9
PORIG	DW	DOCOL
	DW	ORIGI
	DW	PLUS
	DW	SEMIS
;
; ( a1 n --- a2 ; n is a direction flag. )
	DB	88H,'TRAVERS','E'+80H
	DW	PORIG-10
TRAV	DW	DOCOL
	DW	SWAP
				; BEGIN
TRAV1	DW	OVER
	DW	PLUS
	DW	LIT,07FH
	DW	OVER
	DW	CAT
	DW	LESS
	DW	ZBRAN,TRAV1-$	; UNTIL
	DW	SWAP
	DW	DROP
	DW	SEMIS
;
; ( pfa --- nfa )
	DB	83H,'NF','A'+80H
	DW	TRAV-11
NFA	DW	DOCOL
	DW	LIT,5H
	DW	SUBB
	DW	MONE
	DW	TRAV
	DW	SEMIS
;
; ( pfa --- lfa )
	DB	83H,'LF','A'+80H
	DW	NFA-6
LFA	DW	DOCOL
	DW	LIT,4H
	DW	SUBB
	DW	SEMIS
;
; ( pfa --- cfa )
	DB	83H,'CF','A'+80H
	DW	LFA-6
CFA	DW	DOCOL
	DW	TWOM
	DW	SEMIS
;
; ( nfa --- pfa )
	DB	83H,'PF','A'+80H
	DW	CFA-6
PFA	DW	DOCOL
	DW	ONE
	DW	TRAV
	DW	LIT,5H
	DW	PLUS
	DW	SEMIS
;
; ( --- )
	DB	0C1H,'['+80H
	DW	PFA-6
LBRAC	DW	DOCOL
	DW	ZERO
	DW	STATE
	DW	STORE
	DW	SEMIS
;
; ( --- )
	DB	081H,']'+80H
	DW	LBRAC-4
RBRAC	DW	DOCOL
	DW	LIT,0C0H	; ( = 0b 1100 0000 )
	DW	STATE
	DW	STORE
	DW	SEMIS
;
; ( --- )
	DB	0C1H,';'+80H
	DW	RBRAC-4
SEMI	DW	DOCOL
	DW	QCSP
	DW	COMP
	DW	SEMIS
	DW	SMUDG
	DW	LBRAC		; [COMPILE] [
	DW	SEMIS
;
; ( n --- )
	DB	81H,','+80H
	DW	SEMI-4
COMMA	DW	DOCOL
	DW	HERE
	DW	STORE
	DW	TWO
	DW	ALLOT
	DW	SEMIS
;
; ( c --- )
	DB	82H,'C',','+80H
	DW	COMMA-4
CCOMM	DW	DOCOL
	DW	HERE
	DW	CSTOR
	DW	ONE
	DW	ALLOT
	DW	SEMIS
;
; ( --- )
	DB	89H,'IMMEDIAT','E'+80H
	DW	CCOMM-5
IMMED	DW	DOCOL
	DW	LATES
	DW	LIT,40H		; ( = 0b 100 0000 )
	DW	TOGGL
	DW	SEMIS
;
; ( --- ) <name>
	DB	8AH,'VOCABULAR','Y'+80H
	DW	IMMED-12
VOCAB	DW	DOCOL
	DW	CREAT
	DW	LIT,0A081H	; "blank" word (= 81H,' '+80H)
	DW	COMMA
	DW	CURR
	DW	ATT
	DW	CFA
	DW	COMMA
	DW	HERE
	DW	VOCL
	DW	ATT
	DW	COMMA
	DW	VOCL
	DW	STORE
	DW	PSCOD
DOVOC:	JMP	XDOES
	DW	TWOP
	DW	CONT
	DW	STORE
	DW	SEMIS
;
; ( --- )
	DB	0C5H,'FORT','H'+80H
	DW	VOCAB-13
FORTH	DW	DOVOC
	DW	0A081H		; "blank" word (= 81H,' '+80H)
	DW	STAN79-14	; latest word
	DW	0
;
; ( --- ) <word>
	DB	86H,'FORGE','T'+80H
	DW	FORTH-8
FORG	DW	DOCOL
	DW	CURR
	DW	ATT
	DW	CONT
	DW	ATT
	DW	SUBB
	DW	LIT,18H
	DW	QERR
	DW	TICK		; [COMPILE] '
	DW	DUPE
	DW	FENCE
	DW	ATT
	DW	LESS
	DW	LIT,15H
	DW	QERR
	DW	DUPE
	DW	NFA
	DW	DP
	DW	STORE
	DW	LFA
	DW	ATT
	DW	CURR
	DW	ATT
	DW	STORE
	DW	SEMIS
;
; ( --- DP )
	DB	85H,'<MAR','K'+80H
	DW	FORG-9
LMARK	DW	DOCOL
	DW	HERE
	DW	SEMIS
;
; ( --- DP )
	DB	85H,'>MAR','K'+80H
	DW	LMARK-8
GMARK	DW	DOCOL
	DW	HERE
	DW	ZERO
	DW	COMMA
	DW	SEMIS
;
; ( a --- )
	DB	88H,'<RESOLV','E'+80H
	DW	GMARK-8
LRESOL	DW	DOCOL
	DW	HERE
	DW	SUBB
	DW	COMMA
	DW	SEMIS
;
; ( a --- )
	DB	88H,'>RESOLV','E'+80H
	DW	LRESOL-11
GRESOL	DW	DOCOL
	DW	HERE
	DW	OVER
	DW	SUBB
	DW	SWAP
	DW	STORE
	DW	SEMIS
;
; ( --- a 1 )
	DB	0C2H,'I','F'+80H
	DW	GRESOL-11
IFF	DW	DOCOL
	DW	QCOMP
	DW	COMP
	DW	ZBRAN
	DW	GMARK
	DW	ONE
	DW	SEMIS
;
; ( a1 1 --- a2 1 )
	DB	0C4H,'ELS','E'+80H
	DW	IFF-5
ELSEE	DW	DOCOL
	DW	ONE
	DW	QPAIR
	DW	COMP
	DW	BRAN
	DW	GMARK
	DW	SWAP
	DW	GRESOL
	DW	ONE
	DW	SEMIS
;
; ( a 1 --- )
	DB	0C4H,'THE','N'+80H
	DW	ELSEE-7
THEN	DW	DOCOL
	DW	ONE
	DW	QPAIR
	DW	GRESOL
	DW	SEMIS
;
; ( --- a 3 )
	DB	0C5H,'BEGI','N'+80H
	DW	THEN-7
BEGIN	DW	DOCOL
	DW	QCOMP
	DW	LMARK
	DW	THREE
	DW	SEMIS
;
; ( a 3 --- )
	DB	0C5H,'AGAI','N'+80H
	DW	BEGIN-8
AGAIN	DW	DOCOL
	DW	THREE
	DW	QPAIR
	DW	COMP
	DW	BRAN
	DW	LRESOL
	DW	SEMIS
;
; ( a 3 --- )
	DB	0C5H,'UNTI','L'+80H
	DW	AGAIN-8
UNTIL	DW	DOCOL
	DW	THREE
	DW	QPAIR
	DW	COMP
	DW	ZBRAN
	DW	LRESOL
	DW	SEMIS
;
; ( a1 3 --- a2 4 )
	DB	0C5H,'WHIL','E'+80H
	DW	UNTIL-8
WHILEE	DW	DOCOL
	DW	THREE
	DW	QPAIR
	DW	COMP
	DW	ZBRAN
	DW	GMARK
	DW	LIT,4H
	DW	SEMIS
;
; ( a 4 --- )
	DB	0C6H,'REPEA','T'+80H
	DW	WHILEE-8
REPEA	DW	DOCOL
	DW	LIT,4H
	DW	QPAIR
	DW	COMP
	DW	BRAN
	DW	SWAP
	DW	LRESOL
	DW	GRESOL
	DW	SEMIS
;
; ( --- a 2 : compiling ; n1 n2 --- ; execution )
	DB	0C2H,'D','O'+80H
	DW	REPEA-9
DO	DW	DOCOL
	DW	COMP
	DW	XDO
	DW	LMARK
	DW	TWO
	DW	SEMIS
;
; ( a 2 --- : compiling ; --- : execution )
	DB	0C4H,'LOO','P'+80H
	DW	DO-5
LOOPC	DW	DOCOL
	DW	TWO
	DW	QPAIR
	DW	COMP
	DW	XLOOP
	DW	LRESOL
	DW	SEMIS
;
; ( a 2 --- : compiling ; --- : execution )
	DB	0C5H,'+LOO','P'+80H
	DW	LOOPC-7
PLOOP	DW	DOCOL
	DW	TWO
	DW	QPAIR
	DW	COMP
	DW	XPLOO
	DW	LRESOL
	DW	SEMIS
;
; ( --- ; Exit a loop. )
	DB	85H,'LEAV','E'+80H
	DW	PLOOP-8
LLEAVE	DW	DOCOL
	DW	FROMR
	DW	FROMR
	DW	DUPE
	DW	FROMR
	DW	DROP
	DW	TOR
	DW	TOR
	DW	TOR
	DW	SEMIS
;
; ( --- n ; n = loop counter )
	DB	81H,'I'+80H
	DW	LLEAVE-8
IDO	DW	DOCOL
	DW	FROMR
	DW	RAT
	DW	SWAP
	DW	TOR
	DW	SEMIS
;
; ( --- n ; n = outer loop counter )
	DB	81H,'J'+80H
	DW	IDO-4
JDO	DW	DOCOL
	DW	FROMR
	DW	FROMR
	DW	FROMR
	DW	RAT
	DW	LROT
	DW	TOR
	DW	TOR
	DW	SWAP
	DW	TOR
	DW	SEMIS
;
; ( --- )
	DB	0C4H,'EXI','T'+80H
	DW	JDO-4
EXIT	DW	DOCOL
	DW	QCOMP
	DW	COMP
	DW	SEMIS
	DW	SEMIS
;
; ( n1 --- n2 )
	DB	84H,'PIC','K'+80H
	DW	EXIT-7
PICK	DW	DOCOL
	DW	TWOS
	DW	SPAT
	DW	PLUS
	DW	ATT
	DW	SEMIS
;
; ( n1 --- n2 )
	DB	85H,'RPIC','K'+80H
	DW	PICK-7
RPICK	DW	DOCOL
	DW	TWOS
	DW	RPAT
	DW	PLUS
	DW	ATT
	DW	SEMIS
;
; ( --- n )
	DB	85H,'DEPT','H'+80H
	DW	RPICK-8
DEPTH	DW	DOCOL
	DW	SZERO
	DW	ATT
	DW	SPAT
	DW	TWOP
	DW	SUBB
	DW	TDIV
	DW	SEMIS
;
; ( n --- )
; n1 n2 ... n(m-n+1) ... n(m-1) nm  ==>
; n1 n2 ... nm n(m-n+1)  ... n(m-1)
	DB	84H,'ROL','L'+80H
	DW	DEPTH-8
ROLL	DW	DOCOL
	DW	TOR
	DW	RAT
	DW	PICK
	DW	SPAT
	DW	DUPE
	DW	TWOP
	DW	FROMR
	DW	TWOS
	DW	LCMOVE
	DW	DROP
	DW	SEMIS
;
; ( n --- ; reverse of ROLL )
	DB	85H,'<ROL','L'+80H
	DW	ROLL-7
LROLL	DW	DOCOL
	DW	TOR
	DW	DUPE
	DW	SPAT
	DW	DUPE
	DW	TWOP
	DW	SWAP
	DW	RAT
	DW	TWOS
	DW	CMOVEE
	DW	SPAT
	DW	FROMR
	DW	TWOS
	DW	PLUS
	DW	STORE
	DW	SEMIS
;
; ( --- cfa / 0 ) <name>
	DB	84H,'FIN','D'+80H
	DW	LROLL-8
FIND	DW	DOCOL
	DW	BLS
	DW	WORDS
	DW	CONT
	DW	ATT
	DW	ATT
	DW	PFIND
	DW	DUPE
	DW	ZEQU
	DW	ZBRAN,FIND1-$	; IF
	DW	DROP
	DW	HERE
	DW	LATES
	DW	PFIND
				; THEN
FIND1	DW	SEMIS
;
; ( --- pfa : execution ; --- : compiling ) <name>
	DB	0C1H,"'"+80H
	DW	FIND-7
TICK	DW	DOCOL
	DW	FIND
	DW	TWOP
	DW	QDUP
	DW	ZEQU
	DW	ZERO
	DW	QERR
	DW	LITER		; [COMPILE] LITERAL
	DW	SEMIS
;
; ( c --- a ; c is a delimiter. )
	DB	84H,'WOR','D'+80H
	DW	TICK-4
WORDS	DW	DOCOL
	DW	BLK
	DW	ATT
	DW	ZBRAN,WORDS1-$	; IF
	DW	BLK
	DW	ATT
	DW	BLOCK
	DW	BRAN,WORDS2-$	; ELSE
WORDS1	DW	TIB
	DW	ATT
				; THEN
WORDS2	DW	INN
	DW	ATT
	DW	PLUS
	DW	SWAP
	DW	ENCL
	DW	HERE
	DW	LIT,MXTOKN+2
	DW	BLANK
	DW	INN
	DW	PSTOR
	DW	OVER
	DW	SUBB
	DW	TOR
	DW	RAT
	DW	HERE
	DW	CSTOR
	DW	PLUS
	DW	HERE
	DW	ONEP
	DW	FROMR
	DW	CMOVEE
	DW	HERE
	DW	SEMIS
;
; ( --- )
	DB	0C1H,'('+80H
	DW	WORDS-7
PAREN	DW	DOCOL
	DW	LIT,29H		; ( ')' code )
	DW	WORDS
	DW	DROP
	DW	SEMIS
;
; ( a n --- )
	DB	86H,'EXPEC','T'+80H
	DW	PAREN-4
EXPEC	DW	DOCOL
	DW	OVER
	DW	PLUS
	DW	OVER
	DW	XDO		; DO
EXPEC1	DW	KEY
	DW	DUPE
	DW	LIT,8H		;  ( BS code )
	DW	EQUAL
	DW	ZBRAN,EXPEC2-$	;  IF
	DW	DROP
	DW	DUPE
	DW	IDO
	DW	EQUAL
	DW	DUPE
	DW	FROMR
	DW	TWOM
	DW	PLUS
	DW	TOR
	DW	ZBRAN,EXPEC6-$	;   IF
	DW	LIT,7H		;    ( bell code )
	DW	BRAN,EXPEC7-$	;   ELSE
EXPEC6	DW	LIT,8H		;    ( BS code )
	DW	EMIT
	DW	BLS
	DW	EMIT
	DW	LIT,8H		;    ( BS code )
				;   THEN
EXPEC7	DW	BRAN,EXPEC3-$	;  ELSE
EXPEC2	DW	DUPE
	DW	LIT,0DH		;   ( CR code )
	DW	EQUAL
	DW	ZBRAN,EXPEC4-$	;   IF
	DW	LLEAVE
	DW	DROP
	DW	BLS
	DW	ZERO
	DW	BRAN,EXPEC5-$	;   ELSE
EXPEC4	DW	DUPE
				;   THEN
EXPEC5	DW	IDO
	DW	CSTOR
	DW	ZERO
	DW	IDO
	DW	ONEP
	DW	STORE
				;  THEN
EXPEC3	DW	EMIT
	DW	XLOOP,EXPEC1-$	; LOOP
	DW	DROP
	DW	SEMIS
;
; ( --- )
	DB	85H,'QUER','Y'+80H
	DW	EXPEC-9
QUERY	DW	DOCOL
	DW	TIB
	DW	ATT
	DW	TIBLEN
	DW	EXPEC
	DW	ZERO
	DW	INN
	DW	STORE
	DW	SEMIS
;
; ( --- ; The name of this word is null itself. )
	DB	0C1H,0H+80H
	DW	QUERY-8
NULL	DW	DOCOL
	DW	BLK
	DW	ATT
	DW	ZBRAN,NULL1-$	; IF
	DW	ONE
	DW	BLK
	DW	PSTOR
	DW	ZERO
	DW	INN
	DW	STORE
	DW	QEXEC
	DW	FROMR
	DW	DROP
NULL3	DW	BRAN,NULL2-$	; ELSE
NULL1	DW	FROMR
	DW	DROP
				; THEN
NULL2	DW	SEMIS
;
; ( d a --- d' a' )
	DB	87H,'CONVER','T'+80H
	DW	NULL-4
CONV	DW	DOCOL
				; BEGIN
CONV1	DW	ONEP
	DW	DUPE
	DW	TOR
	DW	CAT
	DW	BASE
	DW	ATT
	DW	DIGIT
	DW	ZBRAN,CONV2-$	; WHILE
	DW	SWAP
	DW	BASE
	DW	ATT
	DW	USTAR
	DW	DROP
	DW	ROT
	DW	BASE
	DW	ATT
	DW	USTAR
	DW	DPLUS
	DW	DPL
	DW	ATT
	DW	ONEP
	DW	ZBRAN,CONV3-$	;  IF
	DW	ONE
	DW	DPL
	DW	PSTOR
				;  THEN
CONV3	DW	FROMR
	DW	BRAN,CONV1-$	; REPEAT
CONV2	DW	FROMR
	DW	SEMIS
;
; ( a --- d )
	DB	86H,'NUMBE','R'+80H
	DW	CONV-10
NUMB	DW	DOCOL
	DW	ZERO,ZERO	; 0.0
	DW	ROT
	DW	DUPE
	DW	ONEP
	DW	CAT
	DW	LIT,2DH		; ( '-' code )
	DW	EQUAL
	DW	DUPE
	DW	TOR
	DW	PLUS
	DW	MONE
				; BEGIN
NUMB1	DW	DPL
	DW	STORE
	DW	CONV
	DW	DUPE
	DW	CAT
	DW	BLS
	DW	SUBB
	DW	ZBRAN,NUMB2-$	; WHILE
	DW	DUPE
	DW	CAT
	DW	LIT,2EH		;  ( '.' code )
	DW	SUBB
	DW	ZERO
	DW	QERR
	DW	ZERO
	DW	BRAN,NUMB1-$	; REPEAT
NUMB2	DW	DROP
	DW	FROMR
	DW	ZBRAN,NUMB3-$	; IF
	DW	DMINUS		;  DNEGATE
				; THEN
NUMB3	DW	SEMIS
;
; ( a1 --- a2 f )
	DB	84H,'+BU','F'+80H
	DW	NUMB-9
PBUF	DW	DOCOL
	DW	BFLEN
	DW	PLUS
	DW	DUPE
	DW	LIMIT
	DW	EQUAL
	DW	ZBRAN,PBUF1-$	; IF
	DW	DROP
	DW	FIRST
				; THEN
PBUF1	DW	DUPE
	DW	PREV
	DW	ATT
	DW	SUBB
	DW	SEMIS
;
; ( --- )
	DB	86H,'UPDAT','E'+80H
	DW	PBUF-7
UPDAT	DW	DOCOL
	DW	PREV
	DW	ATT
	DW	ATT
	DW	LIT,8000H	; ( Set the MSB. )
	DW	ORR
	DW	PREV
	DW	ATT
	DW	STORE
	DW	SEMIS
;
; ( --- )
	DB	8DH,'EMPTY-BUFFER','S'+80H
	DW	UPDAT-9
EMPBUF	DW	DOCOL
	DW	FIRST
	DW	LIMIT
	DW	OVER
	DW	SUBB
	DW	ERASE
	DW	SEMIS
;
; ( --- )
	DB	8CH,'SAVE-BUFFER','S'+80H
	DW	EMPBUF-16
SAVBUF	DW	DOCOL
	DW	NUMBUF
	DW	ONEP
	DW	ZERO
	DW	XDO		; DO
SAVBU1	DW	ZERO
	DW	BUFFE
	DW	DROP
	DW	XLOOP,SAVBU1-$	; LOOP
	DW	SEMIS
;
; ( --- )
	DB	83H,'DR','0'+80H
	DW	SAVBUF-15
DRZER	DW	DOCOL
	DW	ZERO
	DW	OFSET
	DW	STORE
	DW	SEMIS
;
; ( --- )
	DB	83H,'DR','1'+80H
	DW	DRZER-6
DRONE	DW	DOCOL
	DW	LIT,DRSIZ
	DW	OFSET
	DW	STORE
	DW	SEMIS
;
; ( a n f --- ; Read/write disks. )
; Read if f=1, write if f=0.
; a: buffer address
; n: block number
; f: direction flag
	DB	83H,'R/','W'+80H
	DW	DRONE-6
RSLW	DW	DOCOL
	DW	TOR
	DW	LIT,DRSIZ
	DW	SLMOD
	DW	LROT
	DW	FROMR
	DW	ZBRAN,RSLW1-$	; IF
	DW	RREC
	DW	LIT,8H		;  8 ( error #8 )
	DW	BRAN,RSLW2-$	; ELSE
RSLW1	DW	WREC
	DW	LIT,9H		;  9 ( error #9 )
				; THEN
RSLW2	DW	OVER
	DW	SWAP
	DW	QERR
	DW	DUPE
	DW	ZBRAN,RSLW3-$	; IF
	DW	ZERO
	DW	PREV
	DW	ATT
	DW	STORE		;  ( This buffer is no good. )
				; THEN
RSLW3	DW	DSKERR
	DW	STORE
	DW	SEMIS
;
; ( n --- a )
	DB	86H,'BUFFE','R'+80H
	DW	RSLW-6
BUFFE	DW	DOCOL
	DW	USE
	DW	ATT
	DW	DUPE
	DW	TOR
				; BEGIN
BUFFE1	DW	PBUF
	DW	ZBRAN,BUFFE1-$	; UNTIL
	DW	USE
	DW	STORE
	DW	RAT
	DW	ATT
	DW	ZLESS
	DW	ZBRAN,BUFFE2-$	; IF
	DW	RAT
	DW	TWOP
	DW	RAT
	DW	ATT
	DW	LIT,7FFFH
	DW	ANDD
	DW	ZERO
	DW	RSLW
				; THEN
BUFFE2	DW	RAT
	DW	STORE
	DW	RAT
	DW	PREV
	DW	STORE
	DW	FROMR
	DW	TWOP
	DW	SEMIS
;
; ( n --- a )
	DB	85H,'BLOC','K'+80H
	DW	BUFFE-9
BLOCK	DW	DOCOL
	DW	OFSET
	DW	ATT
	DW	PLUS
	DW	TOR
	DW	PREV
	DW	ATT
	DW	DUPE
	DW	ATT
	DW	RAT
	DW	SUBB
	DW	TWOS
	DW	ZBRAN,BLOCK1-$	; IF
				;  BEGIN
BLOCK2	DW	PBUF
	DW	ZEQU
	DW	ZBRAN,BLOCK3-$	;   IF
	DW	DROP
	DW	RAT
	DW	BUFFE
	DW	DUPE
	DW	RAT
	DW	ONE
	DW	RSLW
	DW	TWOM
				;   THEN
BLOCK3	DW	DUPE
	DW	ATT
	DW	RAT
	DW	SUBB
	DW	TWOS
	DW	ZEQU
	DW	ZBRAN,BLOCK2-$	;  UNTIL
	DW	DUPE
	DW	PREV
	DW	STORE
				; THEN
BLOCK1	DW	FROMR
	DW	DROP
	DW	TWOP
	DW	SEMIS
;
; ( --- )
	DB	89H,'INTERPRE','T'+80H
	DW	BLOCK-8
INTER	DW	DOCOL
				; BEGIN
INTER1	DW	FIND
	DW	QDUP
	DW	ZBRAN,INTER2-$	;  IF
	DW	DUPE
	DW	TWOP
	DW	NFA
	DW	CAT
	DW	STATE
	DW	ATT
	DW	LESS
	DW	ZBRAN,INTER4-$	;   IF
	DW	COMMA
	DW	BRAN,INTER5-$	;   ELSE
INTER4	DW	EXEC
				;   THEN
INTER5	DW	QSTAC
	DW	BRAN,INTER3-$	;  ELSE
INTER2	DW	HERE
	DW	NUMB
	DW	DPL
	DW	ATT
	DW	ONEP
	DW	ZBRAN,INTER6-$	;   IF
	DW	DLITE		;    [COMPILE] DLITERAL
	DW	BRAN,INTER7-$	;   ELSE
INTER6	DW	DROP
	DW	LITER		;    [COMPILE] LITERAL
				;   THEN
INTER7	DW	QSTAC
				;  THEN
INTER3	DW	BRAN,INTER1-$	; AGAIN
;
; ( --- )
	DB	84H,'QUI','T'+80H
	DW	INTER-12
QUIT	DW	DOCOL
	DW	ZERO
	DW	BLK
	DW	STORE
	DW	LBRAC		; [COMPILE] [
				; BEGIN
QUIT1	DW	RPSTO
	DW	CR
	DW	QUERY
	DW	INTER
	DW	STATE
	DW	ATT
	DW	ZEQU
	DW	ZBRAN,QUIT2-$	;  IF
	DW	PDOTQ
	DB	2,'ok'
				;  THEN
QUIT2	DW	BRAN,QUIT1-$	; AGAIN
;
; ( --- )
	DB	85H,'ABOR','T'+80H
	DW	QUIT-7
ABORT	DW	DOCOL
;-------------------------------------------
	DW	CR
	DW	PDOTQ
	DB	17,'FORTH80D Version '
	DW	TUVR
	DW	ATT		; release No.
	DW	ZERO,ZERO,DDOTR	; U. without spaces
	DW	LIT,2EH		; '.' code
	DW	EMIT
	DW	TUVR
	DW	LIT,2
	DW	PLUS
	DW	ATT		; revision No.
	DW	ZERO,ZERO,DDOTR
	; ----- OPTIONAL -----
	DW	LIT,2EH		; '.' code
	DW	EMIT
	DW	TUVR
	DW	LIT,5
	DW	PLUS
	DW	CAT		; major user version (0-255)
	DW	ZERO,ZERO,DDOTR
	; --------------------
	DW	TUVR
	DW	LIT,4
	DW	PLUS
	DW	CAT		; user version (0-25)
	DW	LIT,41H		; 'A' code
	DW	PLUS
	DW	EMIT
;-------------------------------------------
	DW	SPSTO
	DW	DECA
	DW	DRZER
	DW	FORTH		; [COMPILE] FORTH
	DW	DEFIN
	DW	QUIT
;
; ( n --- )
	DB	87H,'MESSAG','E'+80H
	DW	ABORT-8
MESS	DW	DOCOL
	DW	WARN
	DW	ATT
	DW	ZBRAN,MESS1-$	; IF
	DW	QDUP
	DW	ZBRAN,MESS3-$	;  IF
	DW	MSGSCR
	DW	OFSET
	DW	ATT
	DW	SUBB
	DW	DLINE
	DW	SPACE
				;  THEN
MESS3	DW	BRAN,MESS2-$	; ELSE
MESS1	DW	PDOTQ
	DB	5,'MSG #'
	DW	DOT
				; THEN
MESS2	DW	SEMIS
;
; ( n --- )
	DB	85H,'ERRO','R'+80H
	DW	MESS-10
ERROR	DW	DOCOL
	DW	WARN
	DW	ATT
	DW	ZLESS
	DW	ZBRAN,ERROR1-$	; IF
	DW	ABORT
				; THEN
ERROR1	DW	HERE
	DW	COUNT
	DW	TYPES
	DW	PDOTQ
	DB	3,' ? '
	DW	MESS
	DW	SPSTO
	DW	BLK
	DW	ATT
	DW	QDUP
	DW	ZBRAN,ERROR2-$	; IF
	DW	INN
	DW	ATT
	DW	SWAP
				; THEN
ERROR2	DW	QUIT
;
; ( f n --- )
	DB	86H,'?ERRO','R'+80H
	DW	ERROR-8
QERR	DW	DOCOL
	DW	SWAP
	DW	ZBRAN,QERR1-$	; IF
	DW	ERROR
	DW	BRAN,QERR2-$	; ELSE
QERR1	DW	DROP
				; THEN
QERR2	DW	SEMIS
;
; ( n --- )
	DB	84H,'LOA','D'+80H
	DW	QERR-9
LOAD	DW	DOCOL
	DW	BLK
	DW	ATT
	DW	TOR
	DW	INN
	DW	ATT
	DW	TOR
	DW	ZERO
	DW	INN
	DW	STORE
	DW	BLK
	DW	STORE
	DW	INTER
	DW	FROMR
	DW	INN
	DW	STORE
	DW	FROMR
	DW	BLK
	DW	STORE
	DW	SEMIS
;
; ( --- )
	DB	0C3H,'--','>'+80H
	DW	LOAD-7
ARROW	DW	DOCOL
	DW	QLOAD
	DW	ZERO
	DW	INN
	DW	STORE
	DW	ONE
	DW	BLK
	DW	PSTOR
	DW	SEMIS
;
; ( nfa --- )
	DB	83H,'ID','.'+80H
	DW	ARROW-6
IDDOT	DW	DOCOL
	DW	DUPE
	DW	PFA
	DW	LFA
	DW	OVER
	DW	SUBB
	DW	PAD
	DW	SWAP
	DW	CMOVEE
	DW	PAD
	DW	COUNT
	DW	LIT,1FH		; 1F ( 31 )
	DW	ANDD
	DW	TDUP
	DW	PLUS
	DW	ONEM
	DW	LIT,-80H
	DW	SWAP
	DW	PSTOR
	DW	TYPES
	DW	SPACE
	DW	SEMIS
;
; ( --- ) <name>
	DB	88H,'(CREATE',')'+80H
	DW	IDDOT-6
PCREAT	DW	DOCOL
	DW	FIND
	DW	QDUP
	DW	ZBRAN,PCREA1-$	; IF
	DW	CR
	DW	THREE
	DW	SUBB
	DW	MONE
	DW	TRAV
	DW	IDDOT
	DW	LIT,4H
	DW	MESS
				; THEN
PCREA1	DW	HERE
	DW	DUPE
	DW	CAT
	DW	WYDTH
	DW	ATT
	DW	MIN
	DW	ONEP
	DW	ALLOT
	DW	DUPE
	DW	LIT,0A0H
	DW	TOGGL
	DW	HERE
	DW	ONEM
	DW	LIT,80H
	DW	TOGGL
	DW	LATES
	DW	COMMA
	DW	CURR
	DW	ATT
	DW	STORE
	DW	HERE
	DW	TWOP
	DW	COMMA
	DW	SEMIS
;
; ( --- )
	DB	87H,'(;CODE',')'+80H
	DW	PCREAT-11
PSCOD	DW	DOCOL
	DW	FROMR
	DW	LATES
	DW	ONE
	DW	TRAV
	DW	THREE
	DW	PLUS
	DW	STORE
	DW	SEMIS
;
; ( --- )
	DB	82H,'.','S'+80H
	DW	PSCOD-10
DOTES	DW	DOCOL
	DW	SPAT
	DW	SZERO
	DW	ATT
	DW	EQUAL
	DW	ZEQU
	DW	ZBRAN,DOTES1-$	; IF
	DW	SPAT
	DW	SZERO
	DW	ATT
	DW	TWOM
	DW	XDO		;  DO
DOTES2	DW	IDO
	DW	ATT
	DW	DOT
	DW	LIT,-2
	DW	XPLOO,DOTES2-$	;  +LOOP
				; THEN
DOTES1	DW	SEMIS
;
; ( --- )
	DB	0C9H,'ASSEMBLE','R'+80H
	DW	DOTES-5
ASSEM	DW	DOVOC
	DW	0A081H		; "blank" word (= 81H,' '+80H)
	DW	STAN79-14
	DW	FORTH+6
;
; ( --- ) <name>
	DB	84H,'COD','E'+80H
	DW	ASSEM-12
CODE	DW	DOCOL
	DW	PCREAT
	DW	SMUDG
	DW	ASSEM		; [COMPILE] ASSEMBLER
	DW	SEMIS
;
; ( --- )
	DB	88H,'END-COD','E'+80H
	DW	CODE-7
ENDCO	DW	DOCOL
	DW	CURR
	DW	ATT
	DW	CONT
	DW	STORE
	DW	SEMIS
;
; ( --- )
	DB	0C5H,';COD','E'+80H
	DW	ENDCO-11
SCODE	DW	DOCOL
	DW	QCSP
	DW	COMP
	DW	PSCOD
	DW	LBRAC		; [COMPILE] [
	DW	SMUDG
	DW	ASSEM		; [COMPILE] ASSEMBLER
	DW	SEMIS
;
; ( n --- )
	DB	84H,'LIS','T'+80H
	DW	SCODE-8
LIST	DW	DOCOL
	DW	BASE
	DW	ATT
	DW	DECA
	DW	SWAP
	DW	CR
	DW	DUPE
	DW	DUPE
	DW	SCR
	DW	STORE
	DW	PDOTQ
	DB	6,'SCR # '
	DW	DOT
	DW	OFSET
	DW	ATT
	DW	PLUS
	DW	LIT,DRSIZ
	DW	SLMOD
	DW	PDOTQ
	DB	9,' ( Drive '
	DW	DOT
	DW	PDOTQ
	DB	2,'# '
	DW	DOT
	DW	PDOTQ
	DB	1,')'
	DW	LIT,10H
	DW	ZERO
	DW	XDO		; DO
LIST1	DW	CR
	DW	IDO
	DW	THREE
	DW	DOTR
	DW	SPACE
	DW	IDO
	DW	SCR
	DW	ATT
	DW	PLINE
	DW	TYPES
	DW	LIT,3CH		; ( '<' code )
	DW	EMIT
	DW	XLOOP,LIST1-$	; LOOP
	DW	CR
	DW	BASE
	DW	STORE
	DW	SEMIS
;
; ( --- ; Exit FORTH. )
	DB	83H,'BY','E'+80H
	DW	LIST-7
BYE	DW	$+2
	INT	20H
;
; ( --- )
	DB	8BH,'79-STANDAR','D'+80H
	DW	BYE-6
STAN79	DW	DOCOL
	DW	SEMIS
;
; ***************************************
;
INITDP	EQU	$	 ; initial DP
; ---------------------------------------
codeSeg	ENDS
	END	ORIG
