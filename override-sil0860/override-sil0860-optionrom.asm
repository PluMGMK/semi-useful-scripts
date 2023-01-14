; Not a script, but a little Option ROM for QEMU.
; When I use VFIO to attach my SIL0860 IDE card to a VM,
; it redirects int 13h in a way that prevents SeaBIOS
; from reading the hard drives attached to the VM in the
; normal way. (I think it's because there are no HDDs
; attached to the SIL0860, only a CD-ROM drive.)
; This attempts to detect that and restore the original
; int 13h vector, so I can boot my VMs with the card attached.

; Assemble with `uasm -bin override-sii0860-optionrom.asm`
; Then use signrom from https://searchcode.com/codesearch/raw/26110632/
; `signrom override-sii0860-optionrom.BIN override-sii0860`

	.model	compact
	.code
	.386

?SECTS	equ	1h	; Each sector is 512 bytes

rom	segment	use16
	assume	ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
	org	0
sig	dw	0AA55h
rsize	db	?SECTS
start:
	jmp	initrom

intro	db	0Dh,0Ah,"Silicon Image override Option ROM loaded...",0Dh,0Ah,0
introm	db	"int 13h is in Option ROM...",0Dh,0Ah,0
siirom	db	"Option ROM identified as Silicon Image!",0Dh,0Ah,0
intrest	db	"int 13h restored to original vector!"
newline	db	0Dh,0Ah,0

align	4
simgsig	label	dword
	db	"SIMG"

initrom	proc far	uses ds es fs eax bx si
	lea	si,intro
	call	print

	xor	ax,ax
	mov	ds,ax
	les	bx,ds:[13h*4]	; get the int 13h vector
	mov	ax,es:[0]
	cmp	ax,[sig]
	jne	@@nosiirom

	lea	si,introm
	call	print

	mov	eax,es:[1Ch]
	cmp	eax,[simgsig]
	jne	@@nosiirom

	lea	si,siirom
	call	print

	; Get SIL's local EBDA
	movzx	ax,byte ptr es:[5Eh]	; size of SIL EBDA in kiB
	shl	ax,6
	add	ax,ds:[40Eh]	; pointer to EBDA in standard BDA
	mov	fs,ax

	mov	eax,fs:[1]	; saved int 13h vector in EBDA
	mov	ds:[13h*4],eax	; restore it

	lea	si,intrest
	call	print

@@nosiirom:
	lea	si,newline
	call	print

	ret
initrom	endp

; Take string in CS:SI
print	proc near	uses ax bx
	cld
	mov	ah,0Eh	; teletype output
	mov	bx,7	; white
@@:
	lods	byte ptr cs:[si]
	test	al,al
	jz	@F
	int	10h
	jmp	@B

@@:
	ret
print	endp
.erre	(($ - sig) LE (?SECTS SHL 9)), <"Option ROM is larger than size specified in '?SECTS'!">

	org (?SECTS SHL 9 - 1)
rom_end:
rom	ends

end
