; A util for 25LC512 EEPROM devices, attached in parallel-SPI interface
;
; Commands:
;	r <adr> <len>		Read NVRAM
;	w <adr> <val>...	Write NVRAM

	maclib	z80

spi	equ	40h	; base port of SPI interface

spi$dat	equ	spi+0
spi$ctl	equ	spi+1

NVSCS	equ	10b	; chip select for NVRAM

READ	equ	00000011b
WRITE	equ	00000010b
RDSR	equ	00000101b
WREN	equ	00000110b
CE	equ	11000111b
SE	equ	11011000b
PE	equ	01000010b

; SR bits
WIP	equ	00000001b

CR	equ	13
LF	equ	10

cpm	equ	0
bdos	equ	5
cmd	equ	0080h

conin	equ	1
print	equ	9
getver	equ	12

	org	00100h

	jmp	start

usage:	db	'Usage: NVRAM R adr len',CR,LF
	db	'       NVRAM W adr val...',CR,LF
	db	'       NVRAM CE',CR,LF
	db	'       NVRAM SE adr',CR,LF
	db	'       NVRAM PE adr',CR,LF,'$'

cemsg:	db	'Erase Entire Chip$'
semsg:	db	'Erase Sector $'
pemsg:	db	'Erase Page $'
ynmsg:	db	' (y/n)? $'
cancel:	db	'Erase Canceled',CR,LF,'$'
erasing: db	'Erasing...$'
done:	db	'Done.',CR,LF,'$'

start:
	sspd	usrstk
	lxi	sp,stack
	lda	cmd
	ora	a
	jz	help

	lxi	h,cmd
	mov	b,m
	inx	h
pars0:
	mov	a,m
	cpi	' '
	jnz	pars1
	inx	h
	djnz	pars0
	jmp	help

pars1:
	cpi 	'R'
	jz	pars2
	cpi 	'W'
	jz	pars2
	cpi	'C'
	jz	pars3
	cpi	'S'
	jz	pars3
	cpi	'P'
	jnz	help
pars3:	inx	h
	dcr	b
	jz	help
	mov	c,a
	mov	a,m
	cpi	'E'
	jnz	help
	mov	a,c
pars2:	sta	com
	cpi	'C'	; entire chip, no params
	jz	cecmd
	call	skipb
	jc	help
	call	parshx
	jc	help
	xchg
	shld	adr
	xchg
	lda	com
	cpi	'P'
	jz	pecmd
	cpi	'S'
	jz	secmd
	call	skipb
	jc	help
	lda	com
	cpi	'R'
	jz	nvrd
	mvi	c,0
	lxix	buf
nvwr:
	call	parshx
	jc	help
	mov	a,d
	ora	a
	jnz	help
	stx	e,+0
	inxix
	inr	c
	mov	a,b
	ora	a
	jz	write1
	call	skipb
	jnc	nvwr
write1:
	mov	l,c
	mvi	h,0
	shld	num
	call	nvset
	jmp	exit

nvrd:
	call	parsnm
	jc	help
	; TODO: limit to space in 'buf'
	xchg
	shld	num
	call	nvget
	lxi	h,buf
	push	h
read0:
	lhld	adr
	call	wrdout
	mvi	a,':'
	call	chrout
	mvi	b,16
read1:
	mvi	a,' '
	call	chrout
	pop	h
	mov	a,m
	inx	h
	push	h
	call	hexout
	lhld	adr
	inx	h
	shld	adr
	lhld	num
	dcx	h
	shld	num
	mov	a,h
	ora	l
	jz	read2
	djnz	read1
	call	crlf
	jmp	read0
read2:
	pop	h
	call	crlf
exit:
	jmp	cpm

cecmd:	lxi	d,cemsg
	mvi	c,print
	call	bdos
	mvi	b,0	; adr flag
	mvi	c,CE	; command
ecmds:	push	b
	call	getyn
	lxi	d,erasing
	mvi	c,print
	call	bdos
	pop	b
	mov	a,c
	call	nvcmd
	call	nvwait
	lxi	d,done
	mvi	c,print
	call	bdos
	jmp	exit

secmd:	lxi	d,semsg
	mvi	c,print
	call	bdos
	lhld	adr
	mvi	l,0
	mov	a,h
	ani	11000000b
	mov	h,a
	call	wrdout
	mvi	b,1	; adr flag
	mvi	c,SE	; command
	jmp	ecmds

pecmd:	lxi	d,pemsg
	mvi	c,print
	call	bdos
	lhld	adr
	mov	a,l
	ani	10000000b
	mov	l,a
	call	wrdout
	mvi	b,1	; adr flag
	mvi	c,PE	; command
	jmp	ecmds

; Does not return unless 'Y' is the reposnse.
getyn:
	lxi	d,ynmsg
	mvi	c,print
	call	bdos
	mvi	c,conin
	call	bdos
	push	psw
	call	crlf
	pop	psw
	ani	5fh
	cpi	'Y'
	rz
	lxi	d,cancel
	mvi	c,print
	call	bdos
	jmp	exit

help:
	lxi	d,usage
	mvi	c,print
	call	bdos
	jmp	exit

; Waits for WIP == 0
nvwait:
	mvi	a,NVSCS
	out	spi$ctl
	mvi	a,RDSR
	out	spi$dat
	in	spi$dat	; prime pump
	in	spi$dat
	push	psw
	xra	a
	out	spi$ctl	; SCS off
	pop	psw
	ani	WIP
	jnz	nvwait
	ret

; Send NVRAM command, prefixed by WREN.
; A = command, B==0 if no address in 'adr'
nvcmd:
	push	psw
	mvi	a,NVSCS
	out	spi$ctl
	mvi	a,WREN
	out	spi$dat
	xra	a	; not SCS
	out	spi$ctl
	mvi	a,NVSCS
	out	spi$ctl
	pop	psw	; command
	out	spi$dat
	mov	a,b
	ora	a
	jz	nvcmd0
	lhld	adr
	mov	a,h
	out	spi$dat
	mov	a,l
	out	spi$dat
nvcmd0:	xra	a
	out	spi$ctl	; SCS off
	ret

nvget:
	mvi	a,NVSCS
	out	spi$ctl
	mvi	a,READ
	out	spi$dat
	lhld	adr
	mov	a,h
	out	spi$dat
	mov	a,l
	out	spi$dat
	in	spi$dat	; prime pump
	mvi	c,spi$dat
	lhld	num
	xchg
	mov	a,e
	ora	a
	jz	nvget1
	inr	d	; TODO: handle 64K... and overflow of 'buf'...
nvget1:	lxi	h,buf
	mov	b,e
nvget0:	inir	; B = 0 after
	dcr	d
	jnz	nvget0
	xra	a	; not SCS
	out	spi$ctl
	ret

nvset:
	; TODO: wait for WIP=0...
	mvi	a,NVSCS
	out	spi$ctl
	mvi	a,WREN
	out	spi$dat
	xra	a	; not SCS
	out	spi$ctl
	mvi	a,NVSCS
	out	spi$ctl
	mvi	a,WRITE
	out	spi$dat
	lhld	adr
	mov	a,h
	out	spi$dat
	mov	a,l
	out	spi$dat
	lhld	num	; can't exceed 128?
	mov	b,l
	lxi	h,buf
	mvi	c,spi$dat
	outir
	xra	a	; not SCS
	out	spi$ctl
	ret

chrout:
	push	h
	push	d
	push	b
	mov	e,a
	mvi	c,002h
	call	bdos
	pop	b
	pop	d
	pop	h
	ret

crlf:
	mvi	a,CR
	call	chrout
	mvi	a,LF
	call	chrout
	ret

wrdout:
	push	h
	mov	a,h
	call	hexout
	pop	h
	mov	a,l
hexout:
	push	psw
	rrc
	rrc
	rrc
	rrc
	call	hexdig
	pop	psw
	;jmp	hexdig
hexdig:
	ani	0fh
	adi	90h
	daa
	aci	40h
	daa
	jmp	chrout

skipb:
	inx	h	; skip option letter
	dcr	b
	stc
	rz
skip0:	mov	a,m
	ora	a
	cpi	' '
	rnz	; no carry?
	inx	h
	djnz	skip0
	stc
	ret

; Parse (up to) 16-bit hex value.
; input: HL is cmd buf, B remaining chars
; returns number in DE, CY if error, NZ end of text
parshx:
	lxi	d,0
pm0:	mov	a,m
	cpi	' '
	rz
	sui	'0'
	rc
	cpi	'9'-'0'+1
	jc	pm3
	sui	'A'-'0'
	rc
	cpi	'F'-'A'+1
	cmc
	rc
	adi	10
pm3:
	ani	0fh
	xchg
	dad	h
	jc	pme
	dad	h
	jc	pme
	dad	h
	jc	pme
	dad	h
	jc	pme
	xchg
	add	e	; carry not possible
	mov	e,a
	inx	h
	djnz	pm0
nzret:
	xra	a
	inr	a	; NZ
	ret
pme:	xchg
	stc
	ret

; Parse a 16-bit (max) decimal number
parsnm:
	lxi	d,0
pd0:	mov	a,m
	cpi	' '
	rz
	cpi	'0'
	rc
	cpi	'9'+1
	cmc
	rc
	ani	0fh
	push	h
	mov	h,d
	mov	l,e
	dad	h	; *2
	jc	pd1
	dad	h	; *4
	jc	pd1
	dad	d	; *5
	jc	pd1
	dad	h	; *10
	jc	pd1
	mov	e,a
	mvi	d,0
	dad	d
	xchg
	pop	h
	rc
	inx	h
	djnz	pd0
	ora	a	; NC
	ret

pd1:	pop	h
	ret	; CY still set

	ds	40
stack:	ds	0
usrstk:	dw	0

com:	db	0
adr:	dw	0
num:	dw	0

buf:	ds	0

	end
