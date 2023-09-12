; Console Message, 64 bit. V1.03
NULL              EQU 0                         ; Constants, to be expanded by the preprocessor
STD_OUTPUT_HANDLE EQU -11                       ;   (no memory locations for these, just substituted into code)

extern GetStdHandle                             ; Import external symbols
extern WriteFile                                ; Windows API functions, not decorated
extern ExitProcess

global Start                                    ; Export symbols. The entry point

section .data                                   ; Initialized data segment, mostly used for constants
 Message        db "Hello, world!", 0Dh, 0Ah    ;    These have memory locations.
 MessageLength  EQU $-Message                   ; Address of this line ($) - address of Message

section .bss                                    ; Uninitialized data segment
alignb 8
 StandardHandle resq 1
 Written        resq 1

section .text                                   ; Code segment
Start:
 sub   RSP, 8                                   ; Align the stack to a multiple of 16 bytes

 sub   RSP, 32                                  ; 32 bytes of shadow space (MS x64 calling convention)
 mov   ECX, STD_OUTPUT_HANDLE
 call  GetStdHandle
 mov   qword [REL StandardHandle], RAX
 add   RSP, 32                                  ; Remove the 32 bytes

 sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
                                                ; to a multiple of 16 bytes (MS x64 calling convention)
 mov   RCX, qword [REL StandardHandle]          ; 1st parameter
 lea   RDX, [REL Message]                       ; 2nd parameter
 mov   R8, MessageLength                        ; 3rd parameter
 lea   R9, [REL Written]                        ; 4th parameter
 mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
 call  WriteFile                                ; Output can be redirected to a file using >
 add   RSP, 48                                  ; Remove the 48 bytes

 xor   ECX, ECX                                 ; Produces 0 for the return code
 call  ExitProcess
