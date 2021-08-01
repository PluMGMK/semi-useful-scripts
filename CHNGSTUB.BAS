' CHNGSTUB.BAS
' Replace existing stub in a PE EXE with the new one (.\DOS64STB.BIN)
' Useful when hacking on "Dos64-Stub" in pure DOS

' Give a list of files to help out...
SHELL "dir"
LINE INPUT "Enter PE file to re-stub: ", pefile$
' Move it to a temporary file
NAME pefile$ AS "oldpe.tmp"
OPEN "oldpe.tmp" FOR BINARY AS #1

' Find the offset of the PE header
SEEK #1, 61
DIM elfanew AS LONG
GET #1, , elfanew

' Seek to the PE header
SEEK #1, (elfanew + 1)

' Open the stub too
OPEN "dos64stb.bin" FOR BINARY AS #2
' And recreate the PE file
OPEN pefile$ FOR BINARY AS #3

' Read in the MZ header up to the PE offset
mzhdr$ = SPACE$(60)
GET #2, , mzhdr$
' Write it to the new PE file
PUT #3, , mzhdr$

' Get and write the new PE header offset
DIM newstbsz AS LONG
newstbsz = LOF(2) + 7
' Need to qword-align it apparently...
newstbsz = newstbsz - (newstbsz MOD 8)
PUT #3, , newstbsz
' And seek past it so our file pointers continue to match up
SEEK #2, 65

' Buffered read/write of the MZ stub into the new PE file
DIM buflen AS LONG
buflen = 4096
buf$ = SPACE$(buflen)
WHILE LOC(2) <= (newstbsz - buflen)
	GET #2, , buf$
	PUT #3, , buf$
WEND
rembytes = newstbsz - LOC(2)
IF rembytes > 0 THEN
	rembuf$ = SPACE$(rembytes)
	GET #2, , rembuf$
	PUT #3, , rembuf$
END IF

' Need to fix up all raw fileptrs we encounter from here on
DIM deltaptr AS LONG
deltaptr = newstbsz - elfanew
DIM curptr AS LONG

' Copy the PE header up to the pointer to the number of sections
' 6 = 4 (magic) + 2 (Machine)
buf$ = SPACE$(6)
GET #1, , buf$
PUT #3, , buf$
' Number of sections is a 16-bit integer
GET #1, , numsecs%
PUT #3, , numsecs%
' Copy the timestamp (32 bits)
GET #1, , curptr
PUT #3, , curptr
' Copy *and fixup* the pointer to the symtable
GET #1, , curptr
curptr = curptr + deltaptr
PUT #3, , curptr
' Copy the symbol count (32 bits)
GET #1, , curptr
PUT #3, , curptr
' Size of optional header is a 16-bit integer
GET #1, , opthdrsz%
PUT #3, , opthdrsz%

' Now copy the 16-bit characteristics, plus the optional header
buf$ = SPACE$(opthdrsz% + 2)
GET #1, , buf$
PUT #3, , buf$

' Copy *and fix up* the section headers
FOR cursec% = 1 TO numsecs%
	' 20 = 8 (name) + 4 (virtsize) + 4 (virtaddx) + 4 (rawsize)
	buf$ = SPACE$(20)
	GET #1, , buf$
	PUT #3, , buf$
	' Three pointers to fixup
	FOR i% = 1 TO 3
		GET #1, , curptr
		curptr = curptr + deltaptr
		PUT #3, , curptr
	NEXT i%
	' 8 = 2 (numrelocs) + 2 (numlinenumbers) + 4 (characteristics)
	buf$ = SPACE$(8)
	GET #1, , buf$
	PUT #3, , buf$
NEXT cursec%

' Buffered R/W of the remainder (since we're done with fixups)
buf$ = SPACE$(buflen)
DIM oldpesz AS LONG
oldpesz = LOF(1)
WHILE LOC(1) <= (oldpesz - buflen)
	GET #1, , buf$
	PUT #3, , buf$
WEND
rembytes = oldpesz - LOC(1)
IF rembytes > 0 THEN
	rembuf$ = SPACE$(rembytes)
	GET #1, , rembuf$
	PUT #3, , rembuf$
END IF

' Tidy up
CLOSE (1)
CLOSE (2)
CLOSE (3)
KILL "oldpe.tmp"

SYSTEM

