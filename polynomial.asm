; Read two numbers from the keyboard, add them, and display the result
NULL                EQU 0                       ; Constants, to be expanded by the preprocessor
STD_OUTPUT_HANDLE   EQU -11                     ;   (no memory locations for these, just substituted into code)
STD_INPUT_HANDLE    EQU -10
MAX_INPUT_LENGTH    EQU 11                      ; Ten digits and a sign (for 32 bits)
ASCII_ZERO          EQU 48
ASCII_MINUS         EQU 45
MAX_DEGREE          EQU 6

extern GetStdHandle                             ; Import external symbols
extern ReadFile
extern WriteFile                                ; Windows API functions, not decorated
extern ExitProcess

global Start                                    ; Export symbols. The entry point

section .data                                   ; Initialized data segment, mostly used for constants
 ;Ten            dd 0000 000Ah
 Prompt1        db "Please enter the value of X at which to evaluate: "
 Prompt1Length  EQU $-Prompt1
 Prompt2        db "Please enter the polynomial degree: "
 Prompt2Length  EQU $-Prompt2
 Prompt3        db "Please enter a coefficient (a0 to aN): "
 Prompt3Length  EQU $-Prompt3
 Message        db "f(x) = "               ;    These have memory locations.
 MessageLength  EQU $-Message                   ; Address of this line ($) - address of Message

section .bss                                    ; Uninitialized data segment
alignb 8
 StdOutHandle   resq 1
 StdInHandle    resq 1
 BytesWritten   resq 1                          ; Use for all output commands
 BytesRead      resq 1

 X              resq 1                          ; X at which to evaluate
 Degree         resq 1                          ; degree of the polynomial
 Coefficients   resq MAX_DEGREE + 1
 Fx             resq 1                          ; f(x)
 StringSpace    resb MAX_INPUT_LENGTH + 2       ; Use for all string conversions

section .text                                   ; Code segment

;;; Function str2int
;;; Takes the length and address of a string
;;; Returns the string converted to int (in EAX)
;;; Handles negative inputs
str2int: ;; Beginning of function is just a label
   ;; Parameters are length of the string and address of the string
   ;; Entry code (preamble)
   ;; Copy parameters into shadow space.  This is a little bit paranoid,
   ;;   but not very--if I ever call another procedure from within this
   ;;   one, I will need this.
   mov [rsp+8], rcx  ; Parameter 1 (length)
   mov [rsp+16], rdx ; Parameter 2 (address)
   ;; Save other non-volatile register(s) used
   push  rsi
   
   ;; Body code goes here
   mov   eax, 0                                   ; Clear EAX (where result will go)
   ;; Length of the string is already in ECX
   mov   rsi, rdx                                 ; Beginning of the string
   sub   ecx, 2                                   ; Subtract 2 to exclude the CR/LF at the end
   mov   r8, 0                                    ; clear R8
   mov   r9d, 1                                   ; Sign
   mov   r10, 10                                  ; Base 10; value in R10 to allow multiplying

   ;; Handle the sign character (if any)                         
   jecxz str2int_endLoop                          ; Make sure there are actual characters to read
   mov   r8b, [rsi]                               ; Look at the first char
      ;;; If cl == '-'
   cmp   r8b, ASCII_MINUS
      ;;;; jump if cl != '-'.  That is, *invert* the IF test you want.
   jne   str2int_Loop                             ; If no sign, pretend we didn't even look
   ;;; cl == '-'. Store the fact that we saw a '-' character.
   neg   r9d                                      ; Sign <- -1
   dec   ecx                                      ; Consumed a character
   inc   rsi

   ;; Main loop
   jecxz  str2int_endLoop                         ; if CX <= 0, jump to the end of the loop
   ;; while R8 > 0
   str2int_Loop:
      mul   r10d                                  ; EAX *= 10 (previous digits)
      mov   r8b, [rsi]                            ; Move one digit into R8B
      sub   r8b, ASCII_ZERO                       ; Char to numeric
      add   eax, r8d                              ; Add in the current digit
      inc   rsi                                   ; Point RSI at the next digit
      loop  str2int_Loop                          ; Jump back to the beginning of the while and do it again
   str2int_endLoop:                               ; End the loop
   imul  r9d                                      ; Result *will* fit in EAX

   ;; Exit code (epilogue)
   ;; Restore saved, non-volatile register(s)
   pop   rsi
   ;; I could retrieve the parameters from shadow space, but they all go into volatile registers
   ret

;;;; Function int2str
;;;; Takes an int and the address of a string
;;;; Returns the number of bytes in the converted string in EAX
;;;; Handles negative outputs
;;;; This is the non-paranoid version.
int2str:
   ;; Entry code (preamble)
   ;; Copy parameters into shadow space
   mov   [rsp+8], rcx  ; Parameter 1 (value)
   mov   [rsp+16], rdx ; Parameter 2 (address)
   ;;; Parameters 3 and 4 aren't used, so there's not much point in saving them

   ;; Save other non-volatile register(s) used
   push  rdi
   ;;; I also use R10, but it's volatile

   ;; Body code goes here
   mov   eax, ecx    ; EAX <- value
   mov   rdi, rdx    ; Address
   mov   rcx, 0      ; Clear rcx (will store byte count)
   mov   r9, 1       ; Sign
   mov   r10, 1      ; 10 ** 0, for counting digits

   ;; Handle negative sign, if any
   cmp   eax, 0
   jge   int2str_CountDigits
   neg   eax
   neg   r9                      ; Sign is now negative
   mov   byte [rdi], ASCII_MINUS 
   inc   rdi                     ; Point to the place for the first digit
                                 ; Count of characters will be incremented later

   ;; Find number of digits
   int2str_CountDigits:
      inc   rcx
      imul  r10d, 10  ; Signed multiplication so product can go in R10D
      cmp   eax, r10d
      jg    int2str_CountDigits
   ;; RCX now holds the number of digits in the number
   add   rdi, rcx    ; RDI = RDI + RCX - 1 (next line)
   dec   rdi         ; RDI now points to the place for the *last* digit
   mov   r10d, 10    ; Divisor
   mov   rdx, 0      ; Clear out rdx before the first division

   int2str_MainLoop:
      div   r10d
      add   dl, ASCII_ZERO    ; numeric to string
      mov   [rdi], dl         ; Stow it away
      mov   rdx, 0            ; Clear it out, so the next div works
      dec   rdi               ; Back up to the previous digit
      cmp   eax, 0
      jg    int2str_MainLoop

   ;; RDI now points one place before the first digit
   add   rdi, rcx             ; add the number of digits
   mov   [rdi+1], byte 0Dh    ; Carriage return.  Note this should be RDI+1 if there is no minus sign, but RDI if there is.
   mov   [rdi+2], byte 0Ah    ; Line feed
   add   rcx, 2               ; Add those 2 bytes to the length

   ;; If the number was negative, increment ECX for the minus sign
   cmp   r9, 0
   jge   int2str_NoMinus
   inc   ecx                  ; One more character for the minus sign
   int2str_NoMinus:

   mov   eax, ecx             ; Put the return value (number of bytes) into EAX

   ;; Exit code (epilogue)
   ;; Restore other registers
   pop   rdi
   ;; No need to retrieve the parameters from the shadow space
   ret

;; Function ReadInt
;; Parameters: OutputHandle, InputHandle, address of prompt, and prompt length
;; Returns integer read in EAX
ReadInt:
   ;; Entry code (preamble)
   ;; Copy parameters into shadow space
   mov   [rsp+8], rcx  ; Parameter 1 (output handle)
   mov   [rsp+16], rdx ; Parameter 2 (input handle)
   mov   [rsp+24], r8  ; Parameter 3 (address of prompt)
   mov   [rsp+32], r9 ; Parameter 4 (length of prompt)
   ;; Make space for local parameters on the stack
   sub   rsp, 8 * ((MAX_INPUT_LENGTH + 2) + 2 + 1)
   ;; Variable addresses
   ;; BytesRead: [rsp]
   ;; BytesWritten: [rsp + 8]
   ;; StringSpace: [rsp + 16]
   ;; (return address): [rsp + 120]
   ;; OutputHandle: [rsp + 128]
   ;; InputHandle: [rsp + 136]
   ;; Address of prompt: [rsp + 144]
   ;; Length of prompt: [rsp + 152]

   ;; Prompt
   mov   rcx, [rsp+128]                           ; Parameter 1: output handle
   mov   rdx, [rsp+144]                           ; Parameter 2: address of prompt
   mov   r8, [rsp+152]                            ; Parameter 3: length of prompt
   mov   r9, rsp                                  ; Parameter 4: address for bytes written
   add   r9, 8                                    ;      which is rsp+8
   sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
   mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
   call  WriteFile                                ; Output can be redirected to a file using >
   add   RSP, 48                                  ; Remove the 48 bytes shadow space for WriteFile


   ;; Exit code
   ;; Get rid of local variable space
   add   rsp, 8 * ((MAX_INPUT_LENGTH + 2) + 2 + 1)
   ;; Ensure that result is in EAX, then
   ret

Start:
 sub   RSP, 8                                   ; Align the stack to a multiple of 16 bytes

 ;; Get the handle for stdout
 sub   RSP, 32                                  ; 32 bytes of shadow space (MS x64 calling convention)
 mov   ECX, STD_OUTPUT_HANDLE
 call  GetStdHandle
 mov   qword [REL StdOutHandle], RAX
 add   RSP, 32                                  ; Remove the 32 bytes

 ;; Get the handle for stdin
 sub   RSP, 32                                  ; 32 bytes of shadow space (MS x64 calling convention)
 mov   ECX, STD_INPUT_HANDLE
 call  GetStdHandle
 mov   qword [REL StdInHandle], RAX
 add   RSP, 32                                  ; Remove the 32 bytes

 ;; Read X
 sub   rsp, 32                                  ; Shadow space
 mov   rcx, qword [REL StdOutHandle]            ; 1st parameter
 mov   rdx, qword [REL StdInHandle]             ; 2nd parameter
 lea   r8, [REL Prompt1]                        ; 3rd parameter
 mov   r9, Prompt1Length                        ; 4th parameter
 call  ReadInt
 add   rsp, 32                                  ; Dump shadow space

;  ;; Prompt for X
;  sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
;                                                 ; to a multiple of 16 bytes (MS x64 calling convention)
;  mov   RCX, qword [REL StdOutHandle]            ; 1st parameter
;  lea   RDX, [REL Prompt1]                       ; 2nd parameter
;  mov   R8, Prompt1Length                        ; 3rd parameter
;  lea   R9, [REL BytesWritten]                   ; 4th parameter
;  mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
;  call  WriteFile                                ; Output can be redirected to a file using >
;  add   RSP, 48                                  ; Remove the 48 bytes

;; Read X
 sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
                                                ; to a multiple of 16 bytes (MS x64 calling convention)
 mov   RCX, qword [REL StdInHandle]             ; 1st parameter
 lea   RDX, [REL StringSpace]                    ; 2nd parameter
 mov   R8, MAX_INPUT_LENGTH                     ; 3rd parameter
 lea   R9, [REL BytesRead]                      ; 4th parameter
 mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
 call  ReadFile                                 ; Output can be redirected to a file using >
 add   RSP, 48                                  ; Remove the 48 bytes

;; Convert X string -> int
 sub   RSP, 32                                  ; Shadow space
 mov   ECX, [REL BytesRead]                     ; Length of string, including CRLF
 lea   RDX, [REL StringSpace]                   ; Address of string
 call  str2int
 mov   [REL X], eax                             ; Store the term
 add   RSP, 32                                  ; Dump shadow space

;; Prompt for the degree
 sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
                                                ; to a multiple of 16 bytes (MS x64 calling convention)
 mov   RCX, qword [REL StdOutHandle]            ; 1st parameter
 lea   RDX, [REL Prompt2]                       ; 2nd parameter
 mov   R8, Prompt2Length                        ; 3rd parameter
 lea   R9, [REL BytesWritten]                   ; 4th parameter
 mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
 call  WriteFile                                ; Output can be redirected to a file using >
 add   RSP, 48                                  ; Remove the 48 bytes

;; Read the degree

 sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
                                                ; to a multiple of 16 bytes (MS x64 calling convention)
 mov   RCX, qword [REL StdInHandle]             ; 1st parameter
 lea   RDX, [REL StringSpace]                    ; 2nd parameter
 mov   R8, MAX_INPUT_LENGTH                     ; 3rd parameter
 lea   R9, [REL BytesRead]                      ; 4th parameter
 mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
 call  ReadFile                                 ; Output can be redirected to a file using >
 add   RSP, 48                                  ; Remove the 48 bytes

;; Convert the degree string -> int
 sub   rsp, 32                                  ; Shadow space
 mov   ecx, [REL BytesRead]                     ; Parameter 1: bytes read
 lea   rdx, [REL StringSpace]                   ; Parameter 2: address of the string
 call  str2int
 mov   [REL Degree], eax                        ; Store the degree
 add   rsp, 32                                  ; Dump the shadow space


;; Read the coefficients
mov    rcx, [REL Degree]                        ; RCX <- degree
inc    rcx                                      ; RCX <- number of coefficients
lea    r8, [REL Coefficients]

CoefficientLoop:
   push  rcx                                      ; Keep RCX safe
   push  r8                                       ; Keep the offset safe

   ;; Prompt for the coefficient
   sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
                                                ; to a multiple of 16 bytes (MS x64 calling convention)
   mov   RCX, qword [REL StdOutHandle]            ; 1st parameter
   lea   RDX, [REL Prompt3]                       ; 2nd parameter
   mov   R8, Prompt3Length                        ; 3rd parameter
   lea   R9, [REL BytesWritten]                   ; 4th parameter
   mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
   call  WriteFile                                ; Output can be redirected to a file using >
   add   RSP, 48                                  ; Remove the 48 bytes
   
   ;; Read the coefficient
   sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
                                                  ; to a multiple of 16 bytes (MS x64 calling convention)
   mov   RCX, qword [REL StdInHandle]             ; 1st parameter
   lea   RDX, [REL StringSpace]                   ; 2nd parameter
   mov   R8, MAX_INPUT_LENGTH                     ; 3rd parameter
   lea   R9, [REL BytesRead]                      ; 4th parameter
   mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
   call  ReadFile                                 ; Output can be redirected to a file using >
   add   RSP, 48                                  ; Remove the 48 bytes

   ;; Convert the coefficient string -> int
   sub   rsp, 32                                  ; Shadow space
   mov   ecx, [REL BytesRead]                     ; Parameter 1: bytes read
   lea   rdx, [REL StringSpace]                   ; Parameter 2: address of the string
   call  str2int
   add   rsp, 32                                  ; Dump the shadow space

   pop   r8                                       ; Pop the offset into Coefficients
   mov   [r8], eax                                ; Store off the coefficient
   add   r8, 8                                    ; Bump r8 along the Coefficients array
   pop   rcx                                      ; Get RCX back
   dec   rcx
   jrcxz CoefficientsRead
   jmp   CoefficientLoop

CoefficientsRead:

;; How much shadow space will we need for eval_poly?


; ;; Find the sum
;  add    eax, [REL Term1]                        ; Do the actual addition
;  mov    [REL Total], eax                        ; Store the sum

; ;; Print the label for the sum
;  sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
;                                                 ; to a multiple of 16 bytes (MS x64 calling convention)
;  mov   RCX, qword [REL StdOutHandle]            ; 1st parameter
;  lea   RDX, [REL Message]                       ; 2nd parameter
;  mov   R8, MessageLength                        ; 3rd parameter
;  lea   R9, [REL BytesWritten]                   ; 4th parameter
;  mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
;  call  WriteFile                                ; Output can be redirected to a file using >
;  add   RSP, 48                                  ; Remove the 48 bytes

; ;; Convert the sum to a string
;  sub  rsp, 32                                   ; Shadow space
;  mov  ecx, [REL Total]                          ; Parameter 1: number
;  lea  rdx, [REL StringSpace]                     ; Parameter 2: address of string space
;  call int2str
;  mov  [REL BytesRead], eax                      ; Store the length of the string written
;  add  rsp, 32                                   ; Dump the shadow space

; ;; Print the sum itself
;  sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
;                                                 ; to a multiple of 16 bytes (MS x64 calling convention)
;  mov   RCX, qword [REL StdOutHandle]            ; 1st parameter
;  lea   rdx, [REL StringSpace]
;  mov   R8, [REL BytesRead]                      ; 3rd parameter
;  lea   R9, [REL BytesWritten]                   ; 4th parameter
;  mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
;  call  WriteFile                                ; Output can be redirected to a file using >
;  add   RSP, 48                                  ; Remove the 48 bytes

;; Return code 0 for normal completion
 mov   ECX, dword 0                             ; Produces 0 for the return code
 call  ExitProcess
