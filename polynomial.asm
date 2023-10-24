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
 Message        db "f(x) = "                    ;    These have memory locations.
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
 ShadowSize     resq 1                          ; Size of shadow space for polynomial_eval

section .text                                   ; Code segment

;;; Function str2int
;;; Takes the length and address of a string
;;; Returns the string converted to int (in RAX)
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
   mov   rax, 0                                   ; Clear RAX (where result will go)
   ;; Length of the string is already in ECX
   mov   rsi, rdx                                 ; Beginning of the string
   sub   rcx, 2                                   ; Subtract 2 to exclude the CR/LF at the end
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
   dec   rcx                                      ; Consumed a character
   inc   rsi

   ;; Main loop
   jecxz  str2int_endLoop                         ; if CX <= 0, jump to the end of the loop
   ;; while R8 > 0
   str2int_Loop:
      mul   r10d                                  ; EAX *= 10 (previous digits)
      mov   r8b, [rsi]                            ; Move one digit into R8B
      sub   r8b, ASCII_ZERO                       ; Char to numeric
      add   rax, r8                               ; Add in the current digit
      inc   rsi                                   ; Point RSI at the next digit
      loop  str2int_Loop                          ; Jump back to the beginning of the while and do it again
   str2int_endLoop:                               ; End the loop
   imul  r9                                       ; Result *will* fit in RAX

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
   mov   rax, rcx    ; RAX <- value
   mov   rdi, rdx    ; Address
   mov   rcx, 0      ; Clear rcx (will store byte count)
   mov   r9, 1       ; Sign
   mov   r10, 1      ; 10 ** 0, for counting digits

   ;; Handle negative sign, if any
   cmp   rax, 0
   jge   int2str_CountDigits
   neg   rax
   neg   r9                      ; Sign is now negative
   mov   byte [rdi], ASCII_MINUS 
   inc   rdi                     ; Point to the place for the first digit
                                 ; Count of characters will be incremented later

   ;; Find number of digits
   int2str_CountDigits:
      inc   rcx
      imul  r10, 10  ; Signed multiplication so product can go in R10
      cmp   rax, r10
      jg    int2str_CountDigits
   ;; RCX now holds the number of digits in the number
   add   rdi, rcx    ; RDI = RDI + RCX - 1 (next line)
   dec   rdi         ; RDI now points to the place for the *last* digit
   mov   r10, 10     ; Divisor
   mov   rdx, 0      ; Clear out rdx before the first division

   int2str_MainLoop:
      div   r10
      add   dl, ASCII_ZERO    ; numeric to string
      mov   [rdi], dl         ; Stow it away
      mov   rdx, 0            ; Clear it out, so the next div works
      dec   rdi               ; Back up to the previous digit
      cmp   rax, 0
      jg    int2str_MainLoop

   ;; RDI now points one place before the first digit
   add   rdi, rcx             ; add the number of digits
   mov   [rdi+1], byte 0Dh    ; Carriage return.  Note this should be RDI+1 if there is no minus sign, but RDI if there is.
   mov   [rdi+2], byte 0Ah    ; Line feed
   add   rcx, 2               ; Add those 2 bytes to the length

   ;; If the number was negative, increment ECX for the minus sign
   cmp   r9, 0
   jge   int2str_NoMinus
   inc   rcx                  ; One more character for the minus sign
   int2str_NoMinus:

   mov   rax, rcx             ; Put the return value (number of bytes) into EAX

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
   mov   [rsp+32], r9  ; Parameter 4 (length of prompt)
   ;; Push non-volatile registers
   push  rbp
   mov   rbp, rsp      ; Establish base pointer 
   ;; Make space for local parameters on the stack
   sub   rsp, 8 * ((MAX_INPUT_LENGTH + 2) + 2 + 1)
   ;; Variable addresses
   ;; BytesRead: [rbp - 120]
   ;; BytesWritten: [rbp - 112]
   ;; StringSpace: [rbp - 104]
   ;; (old RBP): [rbp]
   ;; (return address): [rbp + 8]
   ;; OutputHandle: [rbp + 16]
   ;; InputHandle: [rbp + 24]
   ;; Address of prompt: [rbp + 32]
   ;; Length of prompt: [rbp + 40]

   ;; Prompt
   sub   RSP, 32 + 8 + 8                     ; Shadow space + 5th parameter + align stack
   mov   rcx, [rbp + 16]                     ; Parameter 1: output handle
   mov   rdx, [rbp + 32]                     ; Parameter 2: address of prompt
   mov   r8, [rbp + 40]                      ; Parameter 3: length of prompt
   mov   r9, rbp                             ; Parameter 4: address for bytes written
   sub   r9, 112                             ;      which is rbp - 112
   mov   qword [RSP + 4 * 8], NULL           ; 5th parameter
   call  WriteFile                           ; Output can be redirected to a file using >
   add   RSP, 48                             ; Remove the 48 bytes shadow space for WriteFile

   ;; Read
   sub   RSP, 32 + 8 + 8                     ; Shadow space + 5th parameter + align stack
                                             ; to a multiple of 16 bytes (MS x64 calling convention)
   ;; Note we have to reload parameters from scratch.  They're all in volatile registers.
   mov   rcx, [rbp + 24]                     ; Parameter 1: input handle
   mov   rdx, rbp                            ; Parameter 2: address of string space
   sub   rdx, 104                            ;     which is [rbp - 104]
   mov   r8, MAX_INPUT_LENGTH                ; Parameter 3: maximum input length
   mov   r9, rbp                             ; Parameter 4: address of bytes read
   sub   r9, 120                             ;     which is [rbp - 120]
   mov   qword [RSP + 4 * 8], NULL           ; 5th parameter
   call  ReadFile                            
   add   RSP, 48                             ; Remove the 48 bytes

   ;; Convert to int
   sub   rsp, 32                             ; Shadow space
   ;; Again, reload parameters from scratch.
   mov   rcx, [rbp-120]                      ; Length of string, including CRLF
   mov   rdx, rbp                            ; Address of string space
   sub   rdx, 104                            ;     which is [rbp - 104]
   call  str2int
   add   RSP, 32                             ; Dump shadow space
   ;; Leave result in RAX

   ;; Exit code
   ;; Get rid of local variable space
   add   rsp, 8 * ((MAX_INPUT_LENGTH + 2) + 2 + 1)
   ;; Pop non-volatile register
   pop   rbp
   ;; Ensure that result is in RAX, then
   ret

;; Function WriteInt
;; Parameters: OutputHandle, address of label, label length, number to print
;; Returns number of characters printed when printing the number (i.e., digits+2)
WriteInt:
      ;; Entry code (preamble)
   ;; Copy parameters into shadow space
   mov   [rsp+8], rcx  ; Parameter 1 (output handle)
   mov   [rsp+16], rdx ; Parameter 2 (address of label)
   mov   [rsp+24], r8  ; Parameter 3 (length of label)
   mov   [rsp+32], r9  ; Parameter 4 (number to print)
   ;; Push non-volatile registers
   push  rbp
   mov   rbp, rsp      ; Establish base pointer 
   ;; Make space for local parameters on the stack
   sub   rsp, 8 * ((MAX_INPUT_LENGTH + 2) + 1)
   ;; Variable addresses
   ;; ByteCount: [rbp - 112]
   ;; StringSpace: [rbp - 104]
   ;; (old RBP): [rbp]
   ;; (return address): [rbp + 8]
   ;; OutputHandle: [rbp + 16]
   ;; Label address: [rbp + 24]
   ;; Label length: [rbp + 32]
   ;; Number to print: [rbp + 40]

   ;; Print label
   sub   RSP, 32 + 8 + 8                     ; Shadow space + 5th parameter + align stack
   mov   rcx, [rbp + 16]                     ; Parameter 1: output handle
   mov   rdx, [rbp + 24]                     ; Parameter 2: address of label
   mov   r8, [rbp + 32]                      ; Parameter 3: length of label
   mov   r9, rbp                             ; Parameter 4: address for bytes written
   sub   r9, 112                             ;      which is rbp - 112
   mov   qword [RSP + 4 * 8], NULL           ; 5th parameter
   call  WriteFile                           ; Output can be redirected to a file using >
   add   RSP, 48                             ; Remove the 48 bytes shadow space for WriteFile

   ;; Convert number to string
   sub   rsp, 32                             ; Shadow space
   mov   rcx, [rbp + 40]                     ; Parameter 1: number
   mov   rdx, rbp                            ; Parameter 2: address of string space
   sub   rdx, 104                            ;       which is rbp - 104
   call  int2str
   mov   [rbp - 112], rax                    ; Store the length of the string
   add   rsp, 32                             ; Dump the shadow space
   
   ;; Print number

   sub   RSP, 32 + 8 + 8                     ; Shadow space + 5th parameter + align stack
                                             ; to a multiple of 16 bytes (MS x64 calling convention)
   mov   rcx, [rbp + 16]                     ; Parameter 1: output handle
   mov   rdx, rbp                            ; Parameter 2: address of the number string
   sub   rdx, 104                            ;        which is rbp - 104
   mov   r8, [rbp - 112]                     ; Parameter 3: length of the string
   mov   r9, rbp                             ; Parameter 4: address for bytes written
   sub   r9, 112                             ;        which is rbp - 112
   mov   qword [RSP + 4 * 8], NULL           ; 5th parameter
   call  WriteFile                           ; Output can be redirected to a file using >
   add   RSP, 48                             ; Remove the 48 bytes shadow space for WriteFile

   ;; Exit code
   ;; Get rid of local variable space
   add   rsp, 8 * ((MAX_INPUT_LENGTH + 2) + 1)
   ;; Pop non-volatile register
   pop   rbp
   ret

;; Function polynomial_shadow_size
;; One parameter: the degree of the polynomial
;; Return value (in RAX): the size of the shadow space for polynomial_eval
polynomial_ShadowSize:
   ;; Entry code (preamble)
   ;; Copy parameters into shadow space
   mov   [rsp+8], rcx  ; Parameter 1 (polynomial degree)
   ;; No need for a stack frame

   mov   rax, rcx                      ; Start with the degree of the polynomial
   inc   rax                           ; Degree + 1 = number of coefficients
   add   rax, 2                        ; Two more for X and the degree
   sub   rax, 4                        ; Four parameters in registers
                                       ; RAX now has the number of parameters that will 
                                       ;     need to be passed in the shadow space
   jns   polynomial_ParametersOver4    ; if RAX >= 0, leave it alone
   mov   rax, 0                        ; else (RAX is negative), RAX <- 0

   polynomial_ParametersOver4:
   mov   r9, 8                         ; Multiplier (quadwords to bytes)
   mul   r9                            ; RAX now has the bytes for the fifth+ parameters to polynomial_eval
   add   rax, 32                       ; Add on the basic 32 bytes
   test  rax, 15                       ; Gives zero iff EAX is a multiple of 16
   jz    polynomial_FoundShadowSize    ; If EAX % 16 == 0, don't bother to add an extra 8
   add   rax, 8

   polynomial_FoundShadowSize:
   ;; Exit code
   ret

;; Function eval_poly
;; Parameters are the X at which to evaluate, the degree of the polynomial,
;; and the coefficients in order from a0 to aN.
;; The result of the evaluation is returned in RAX.
eval_poly:
   ;; Entry code (preamble)
   ;; Copy parameters into shadow space
   mov   [rsp+8], rcx            ; Parameter 1 (X)
   mov   [rsp+16], rdx           ; Parameter 2 (degree)
   mov   [rsp+24], r8            ; Parameter 3 (a0)
   mov   [rsp+32], r9            ; Parameter 4 (a1)

   ;; Body code
   mov   r10, rcx                ; r10 <- X
   mov   rcx, rdx                ; rcx <- degree
   ;; Calculate address of last coefficient on stack
   mov   r11, rcx                ; R11 <- degree
   add   r11, 3                  ; Plus two more parameters and a return address
                                 ;     before a0 on the stack
   sal   r11, 3                  ; R11 <- R11 * 8 (convert to bytes)
   add   r11, rsp                ; Add RSP so R11 points to aN

   mov   rax, [r11]
   jrcxz AfterHorner
   HornersLoop:
      mul   r10
      sub   r11, 8               ; Move R11 back to the next coefficient
      add   rax, [r11]           ; Add the next coefficient
      loop  HornersLoop          ; The LOOP instruction actually decrements and
                                 ;    tests ECX, not RCX.  For a number as
                                 ;    small as the degree, it doesn't matter.
   AfterHorner:
   ;; Exit code: result is already in RAX. Used no non-volatile registers and
   ;; no local variables.
   ret

Start:
 sub   RSP, 8                                   ; Align the stack to a multiple of 16 bytes

 ;; Get the handle for stdout
 sub   RSP, 32                                  ; 32 bytes of shadow space (MS x64 calling convention)
 mov   RCX, STD_OUTPUT_HANDLE
 call  GetStdHandle
 mov   qword [REL StdOutHandle], RAX
 add   RSP, 32                                  ; Remove the 32 bytes

 ;; Get the handle for stdin
 sub   RSP, 32                                  ; 32 bytes of shadow space (MS x64 calling convention)
 mov   RCX, STD_INPUT_HANDLE
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
 mov   [REL X], rax                             ; Store the term
 add   rsp, 32                                  ; Dump shadow space

;; Read the degree
 sub   rsp, 32                                  ; Shadow space
 ;; Note we have to reload parameters from scratch.  They're all in volatile registers.
 mov   rcx, qword [REL StdOutHandle]            ; 1st parameter
 mov   rdx, qword [REL StdInHandle]             ; 2nd parameter
 lea   r8, [REL Prompt2]                        ; 3rd parameter
 mov   r9, Prompt2Length                        ; 4th parameter
 call  ReadInt
 mov   [REL Degree], rax                        ; Store the term
 add   rsp, 32                                  ; Dump shadow space

;; Read the coefficients
mov    rcx, [REL Degree]                        ; RCX <- degree
inc    rcx                                      ; RCX <- number of coefficients
lea    r8, [REL Coefficients]

CoefficientLoop:
   push  rcx                                    ; Keep RCX safe
   push  r8                                     ; Keep the offset safe

   sub   rsp, 32                                ; Shadow space
   mov   rcx, qword [REL StdOutHandle]          ; 1st parameter
   mov   rdx, qword [REL StdInHandle]           ; 2nd parameter
   lea   r8, [REL Prompt3]                      ; 3rd parameter
   mov   r9, Prompt3Length                      ; 4th parameter
   call  ReadInt
   add   rsp, 32                                ; Dump shadow space

   pop   r8                                     ; Pop the offset into Coefficients
   mov   [r8], rax                              ; Store off the coefficient
   add   r8, 8                                  ; Bump r8 along the Coefficients array
   pop   rcx                                    ; Get RCX back
   dec   rcx
   jrcxz CoefficientsRead
   jmp   CoefficientLoop

CoefficientsRead:

;; How much shadow space will we need for eval_poly?
sub   rsp, 32
mov   rcx, [REL Degree]
call  polynomial_ShadowSize
mov   [REL ShadowSize], rax
add   rsp, 32

;; Evaluate the polynomial
sub   rsp, [REL ShadowSize]         ; Make the shadow space

;; Put the 5th and following parameters on the stack (if they exist)
mov   rcx, [REL Degree]             ; Put degree in RCX
dec   RCX                           ; Degree - 1 = number of coefficients on stack
cmp   rcx, 0
jle   CoefficientsLoaded            ; if RCX <= 0, no coefficients to load

lea   r10, [REL Coefficients + 16]  ; Pointer to a2
lea   r11, [RSP + 4 * 8]            ; Pointer to the stack location for a2

LoadCoefficients:
mov   r9, [r10]                     ; Load a coefficient into a register
mov   [r11], r9                     ; Load it onto the stack
add   r10, 8                        ; Push the pointers along
add   r11, 8
loop  LoadCoefficients

CoefficientsLoaded:
;; Load the first 4 parameters
mov   rcx, [REL X]
mov   rdx, [REL Degree]
mov   r8, [REL Coefficients]        ; a0
cmp   rdx, 0
je    BlankA1                       ; if degree > 0, load a1
mov   r9, [REL Coefficients + 8]    ; a1
jmp   ParametersLoaded
BlankA1:                            ; else (degree == 0), let a1 == 0
mov   r9, 0                         ; a1
ParametersLoaded:

call  eval_poly
mov   [REL Fx], rax
add   rsp, [REL ShadowSize]         ; Dump the shadow space

; Print the result
sub   rsp, 32                                   ; Shadow space
mov   rcx, qword [REL StdOutHandle]
lea   rdx, [REL Message]
mov   r8, MessageLength
mov   r9, [REL Fx]                              ; result value
call  WriteInt
add   rsp, 32

;; Return code 0 for normal completion
mov   RCX, qword 0                             ; Produces 0 for the return code
call  ExitProcess
