; Evaluate a polynomial at a given value of X.
NULL                EQU 0                       ; Constants, to be expanded by the preprocessor
STD_OUTPUT_HANDLE   EQU -11                     ;   (no memory locations for these, just substituted into code)
STD_INPUT_HANDLE    EQU -10
MAX_INPUT_LENGTH    EQU 11                      ; Ten digits and a sign (for 32 bits)
ASCII_ZERO          EQU 48
ASCII_MINUS         EQU 45
MAX_DEGREE          EQU 6

;; Global macros
;;; Straight-up single-line macro
;;;; Fifth parameter
%define FIFTH_PARAM  qword [rsp+32]    

;;; Single-line macros can take parameters, as follows:
; Address in stack frame (relative to RBP)
%define BASE(a)      [rbp+(a)]        

;; Copy parameters into shadow space
%macro ParamsToShadow   0
   mov   [rsp+8], rcx  ; Parameter 1
   mov   [rsp+16], rdx ; Parameter 2
   mov   [rsp+24], r8  ; Parameter 3
   mov   [rsp+32], r9  ; Parameter 4
%endmacro

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
   mov   r9, 1                                    ; Sign
   mov   r10, 10                                  ; Base 10; value in R10 to allow multiplying

   ;; Handle the sign character (if any)                         
   jrcxz .endLoop                          ; Make sure there are actual characters to read
   mov   r8b, [rsi]                               ; Look at the first char
      ;;; If cl == '-'
   cmp   r8b, ASCII_MINUS
      ;;;; jump if cl != '-'.  That is, *invert* the IF test you want.
   jne   .Loop                             ; If no sign, pretend we didn't even look
   ;;; cl == '-'. Store the fact that we saw a '-' character.
   neg   r9                                       ; Sign <- -1
   dec   rcx                                      ; Consumed a character
   inc   rsi

   ;; Main loop
   jrcxz  .endLoop                         ; if CX <= 0, jump to the end of the loop
   ;; while R8 > 0
   .Loop:
      imul  r10                                   ; RAX *= 10 (previous digits)
      mov   r8b, [rsi]                            ; Move one digit into R8B
      sub   r8b, ASCII_ZERO                       ; Char to numeric
      add   rax, r8                               ; Add in the current digit
      inc   rsi                                   ; Point RSI at the next digit
      loop  .Loop                          ; Jump back to the beginning of the while and do it again
   .endLoop:                               ; End the loop
   imul  r9                                       ; Result *will* fit in RAX

   ;; Exit code (epilogue)
   ;; Restore saved, non-volatile register(s)
   pop   rsi
   ;; I could retrieve the parameters from shadow space, but they all go into volatile registers
   ret

;;;; Function int2str
;;;; Takes an int and the address of a string
;;;; Returns the number of bytes in the converted string in RAX
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
   jge   .CountDigits
   neg   rax
   neg   r9                      ; Sign is now negative
   mov   byte [rdi], ASCII_MINUS 
   inc   rdi                     ; Point to the place for the first digit
                                 ; Count of characters will be incremented later

   ;; Find number of digits
   .CountDigits:
      inc   rcx
      imul  r10, 10  ; Signed multiplication so product can go in R10
      cmp   rax, r10
      jg    .CountDigits
   ;; RCX now holds the number of digits in the number
   add   rdi, rcx    ; RDI = RDI + RCX - 1 (next line)
   dec   rdi         ; RDI now points to the place for the *last* digit
   mov   r10, 10     ; Divisor
   mov   rdx, 0      ; Clear out rdx before the first division

   .MainLoop:
      idiv  r10
      add   dl, ASCII_ZERO    ; numeric to string
      mov   [rdi], dl         ; Stow it away
      mov   rdx, 0            ; Clear it out, so the next div works
      dec   rdi               ; Back up to the previous digit
      cmp   rax, 0
      jg    .MainLoop

   ;; RDI now points one place before the first digit
   add   rdi, rcx             ; add the number of digits
   mov   [rdi+1], byte 0Dh    ; Carriage return.  Note this should be RDI+1 if there is no minus sign, but RDI if there is.
   mov   [rdi+2], byte 0Ah    ; Line feed
   add   rcx, 2               ; Add those 2 bytes to the length

   ;; If the number was negative, increment ECX for the minus sign
   cmp   r9, 0
   jge   .NoMinus
   inc   rcx                  ; One more character for the minus sign
   .NoMinus:

   mov   rax, rcx             ; Put the return value (number of bytes) into RAX

   ;; Exit code (epilogue)
   ;; Restore other registers
   pop   rdi
   ;; No need to retrieve the parameters from the shadow space
   ret

;; Function ReadInt
;; Parameters: OutputHandle, InputHandle, address of prompt, and prompt length
;; Returns integer read in RAX
ReadInt:
   ;; Entry code (preamble)
   ParamsToShadow
   ;; Push non-volatile registers
   push  rbp
   mov   rbp, rsp      ; Establish base pointer 
   ;; Make space for local parameters on the stack
   sub   rsp, 8 * ((MAX_INPUT_LENGTH + 2) + 2 + 1)
   ;; Variable addresses
   %define BYTES_READ               BASE(-120)
   %define BYTES_WRITTEN            BASE(-112)
   %define STRING_SPACE             BASE(-104)
   ;; (old RBP): [rbp]
   ;; (return address): [rbp + 8]
   %define OUT_HANDLE               BASE(16)
   %define IN_HANDLE                BASE(24)
   %define PROMPT_ADDR              BASE(32)
   %define PROMPT_LENGTH            BASE(40)

   ;; Prompt
   sub   RSP, 32 + 8 + 8                     ; Shadow space + 5th parameter + align stack
   mov   rcx, OUT_HANDLE                     ; Parameter 1: output handle
   mov   rdx, PROMPT_ADDR                    ; Parameter 2: address of prompt
   mov   r8, PROMPT_LENGTH                   ; Parameter 3: length of prompt
   lea   r9, BYTES_WRITTEN                   ; Parameter 4: address for bytes written
   mov   FIFTH_PARAM, NULL                   
   call  WriteFile                           ; Output can be redirected to a file using >
   add   RSP, 48                             ; Remove the 48 bytes shadow space for WriteFile

   ;; Read
   sub   RSP, 32 + 8 + 8                     ; Shadow space + 5th parameter + align stack
                                             ; to a multiple of 16 bytes (MS x64 calling convention)
   ;; Note we have to reload parameters from scratch.  They're all in volatile registers.
   mov   rcx, IN_HANDLE                      ; Parameter 1: input handle
   lea   rdx, STRING_SPACE
   mov   r8, MAX_INPUT_LENGTH                ; Parameter 3: maximum input length
   lea   r9, BYTES_READ
   mov   FIFTH_PARAM, NULL                   
   call  ReadFile                            
   add   RSP, 48                             ; Remove the 48 bytes

   ;; Convert to int
   sub   rsp, 32                             ; Shadow space
   ;; Again, reload parameters from scratch.
   mov   rcx, BYTES_READ                     ; Length of string, including CRLF
   lea   rdx, STRING_SPACE
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
   ;; Undefine the function-local macros
   %undef   BYTES_READ
   %undef   BYTES_WRITTEN
   %undef   STRING_SPACE
   %undef   OUT_HANDLE
   %undef   IN_HANDLE
   %undef   PROMPT_ADDR
   %undef   PROMPT_LENGTH

;; Function WriteInt
;; Parameters: OutputHandle, address of label, label length, number to print
;; Returns number of characters printed when printing the number (i.e., digits+2)
WriteInt:
      ;; Entry code (preamble)
   ParamsToShadow
   ;; Push non-volatile registers
   push  rbp
   mov   rbp, rsp      ; Establish base pointer 
   ;; Make space for local parameters on the stack
   sub   rsp, 8 * ((MAX_INPUT_LENGTH + 2) + 1)
   ;; Variable addresses
   %define BYTE_COUNT   BASE(-112)
   %define STRING_SPACE BASE(-104)
   ;; (old RBP): [rbp]
   ;; (return address): [rbp + 8]
   %define OUT_HANDLE   BASE(16)
   %define LABEL_ADDR   BASE(24)
   %define LABEL_LENGTH BASE(32)
   %define INT_TO_PRINT BASE(40)

   ;; Print label
   sub   RSP, 32 + 8 + 8                     ; Shadow space + 5th parameter + align stack
   mov   rcx, OUT_HANDLE                     ; Parameter 1: output handle
   mov   rdx, LABEL_ADDR                     ; Parameter 2: address of label
   mov   r8, LABEL_LENGTH                      ; Parameter 3: length of label
   lea   r9, BYTE_COUNT                       ; Parameter 4: address for bytes written
   mov   qword FIFTH_PARAM, NULL
   call  WriteFile                           ; Output can be redirected to a file using >
   add   RSP, 48                             ; Remove the 48 bytes shadow space for WriteFile

   ;; Convert number to string
   sub   rsp, 32                             ; Shadow space
   mov   rcx, INT_TO_PRINT                   ; Parameter 1: number
   lea   rdx, STRING_SPACE                   ; Parameter 2: address of string space
   call  int2str
   mov   BYTE_COUNT, rax                     ; Store the length of the string
   add   rsp, 32                             ; Dump the shadow space
   
   ;; Print number

   sub   RSP, 32 + 8 + 8                     ; Shadow space + 5th parameter + align stack
                                             ; to a multiple of 16 bytes (MS x64 calling convention)
   mov   rcx, OUT_HANDLE                     ; Parameter 1: output handle
   lea   rdx, STRING_SPACE                   ; Parameter 2: address of the number string
   mov   r8, BYTE_COUNT                      ; Parameter 3: length of the string
   lea   r9, BYTE_COUNT                      ; Parameter 4: address for bytes written
   mov   FIFTH_PARAM, NULL
   call  WriteFile                           ; Output can be redirected to a file using >
   add   RSP, 48                             ; Remove the 48 bytes shadow space for WriteFile

   ;; Exit code
   ;; Get rid of local variable space
   add   rsp, 8 * ((MAX_INPUT_LENGTH + 2) + 1)
   ;; Pop non-volatile register
   pop   rbp
   ret
   ;; Undefine the function-local macros
   %undef   BYTE_COUNT
   %undef   STRING_SPACE
   %undef   OUT_HANDLE
   %undef   LABEL_ADDR
   %undef   LABEL_LENGTH
   %undef   INT_TO_PRINT

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
   jns   .ParametersOver4    ; if RAX >= 0, leave it alone
   mov   rax, 0                        ; else (RAX is negative), RAX <- 0

   .ParametersOver4:
   sal   rax, 3                        ; Parameters to bytes.
                                       ; RAX now has the bytes for the fifth+ parameters to .eval                            
   add   rax, 32                       ; Add on the basic 32 bytes
   test  rax, 15                       ; Gives zero iff RAX is a multiple of 16
   jz    .FoundShadowSize    ; If RAX % 16 == 0, don't bother to add an extra 8
   add   rax, 8

   .FoundShadowSize:
   ;; Exit code
   ret

;; Function eval_poly
;; Parameters are the X at which to evaluate, the degree of the polynomial,
;; and the coefficients in order from a0 to aN.
;; The result of the evaluation is returned in RAX.
eval_poly:
   ;; Entry code (preamble)
   ParamsToShadow

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
   jrcxz .AfterHorner
   .HornersLoop:
      imul  r10                  ; RAX = RAX * X
      sub   r11, 8               ; Move R11 back to the next coefficient
      add   rax, [r11]           ; Add the next coefficient
      loop  .HornersLoop         ; The LOOP instruction actually decrements and
                                 ;    tests ECX, not RCX.  For a number as
                                 ;    small as the degree, it doesn't matter.
   .AfterHorner:
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

.CoefficientLoop:
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
   jrcxz .CoefficientsRead
   jmp   .CoefficientLoop

.CoefficientsRead:

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
jle   .CoefficientsLoaded            ; if RCX <= 0, no coefficients to load

lea   r10, [REL Coefficients + 16]  ; Pointer to a2
lea   r11, [RSP + 4 * 8]            ; Pointer to the stack location for a2

.LoadCoefficients:
mov   r9, [r10]                     ; Load a coefficient into a register
mov   [r11], r9                     ; Load it onto the stack
add   r10, 8                        ; Push the pointers along
add   r11, 8
loop  .LoadCoefficients

.CoefficientsLoaded:
;; Load the first 4 parameters
mov   rcx, [REL X]
mov   rdx, [REL Degree]
mov   r8, [REL Coefficients]        ; a0
cmp   rdx, 0
je    .BlankA1                       ; if degree > 0, load a1
mov   r9, [REL Coefficients + 8]    ; a1
jmp   .ParametersLoaded
.BlankA1:                            ; else (degree == 0), let a1 == 0
mov   r9, 0                         ; a1
.ParametersLoaded:

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
