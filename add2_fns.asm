; Read two numbers from the keyboard, add them, and display the result
NULL                EQU 0                       ; Constants, to be expanded by the preprocessor
STD_OUTPUT_HANDLE   EQU -11                     ;   (no memory locations for these, just substituted into code)
STD_INPUT_HANDLE    EQU -10
MAX_INPUT_LENGTH    EQU 11                      ; Ten digits and a sign (for 32 bits)
ASCII_ZERO          EQU 48
ASCII_MINUS         EQU 45

extern GetStdHandle                             ; Import external symbols
extern ReadFile
extern WriteFile                                ; Windows API functions, not decorated
extern ExitProcess

global Start                                    ; Export symbols. The entry point

section .data                                   ; Initialized data segment, mostly used for constants
 ;Ten            dd 0000 000Ah
 Prompt1        db "Please enter an integer: "
 Prompt1Length  EQU $-Prompt1
 Prompt2        db "Please enter a second integer: "
 Prompt2Length  EQU $-Prompt2
 Message        db "The sum is: "               ;    These have memory locations.
 MessageLength  EQU $-Message                   ; Address of this line ($) - address of Message

section .bss                                    ; Uninitialized data segment
alignb 8
 StdOutHandle   resq 1
 StdInHandle    resq 1
 BytesWritten   resq 1                          ; Use for all output commands
 BytesRead      resq 1

 Term1          resq 1                          ; First term of addition
 Term2          resq 1                          ; Second term of addition
 Total          resq 1                          ; sum of the two terms
 StartTotal     resq 1                          ; Starting address of the output string
 InputSpace     resb MAX_INPUT_LENGTH + 2       ; Use for all input commands

section .text                                   ; Code segment

;;; Function str2int_OCD
;;; Takes the length and address of a string
;;; Returns the string converted to int (in EAX)
;;; Handles negative inputs
;;; This is the paranoid version
str2int_OCD: ;; Beginning of function is just a label
   ;; Parameters are length of the string and address of the string
   ;; Entry code (preamble)
   ;; Copy parameters into shadow space
   mov [rsp+8], rcx  ; Parameter 1 (length)
   mov [rsp+16], rdx ; Parameter 2 (address)
   mov [rsp+24], r8  ; Parameter 3 not actually used
   mov [rsp+32], r9  ; parameter 4 not actually used
   ;; Save other registers used
   push  rsi
   push  r10   ; actually a volatile register.  This is paranoid programming right here.

   ;; Body code goes here
   mov   eax, 0                                   ; Clear EAX (where result will go)
   ;; Length of the string is already in ECX
   mov   rsi, rdx                                 ; Beginning of the string
   sub   ecx, 2                                   ; Subtract 2 to exclude the CR/LF at the end
   mov   r8, 0                                    ; clear R8
   mov   r9d, 1                                   ; Sign
   mov   r10, 10                                  ; Base 10; value in R10 to allow multiplying

   ;; Handle the sign character (if any)                         
   jecxz str2int_OCD_endLoop                          ; Make sure there are actual characters to read
   mov   r8b, [rsi]                               ; Look at the first char
      ;;; If cl == '-'
   cmp   r8b, ASCII_MINUS
      ;;;; jump if cl != '-'.  That is, *invert* the IF test you want.
   jne   str2int_OCD_Loop                             ; If no sign, pretend we didn't even look
   ;;; cl == '-'. Store the fact that we saw a '-' character.
   neg   r9d                                      ; Sign <- -1
   dec   ecx                                      ; Consumed a character
   inc   rsi

   ;; Main loop
   jecxz  str2int_OCD_endLoop                         ; if CX <= 0, jump to the end of the loop
   ;; while R8 > 0
   str2int_OCD_Loop:
      mul   r10d                                  ; EAX *= 10 (previous digits)
      mov   r8b, [rsi]                            ; Move one digit into R8B
      sub   r8b, ASCII_ZERO                       ; Char to numeric
      add   eax, r8d                              ; Add in the current digit
      inc   rsi                                   ; Point RSI at the next digit
      loop  str2int_OCD_Loop                          ; Jump back to the beginning of the while and do it again
   str2int_OCD_endLoop:                               ; End the loop
   imul  r9d                                      ; Result *will* fit in EAX

   ;; Exit code (epilogue)
   ;; Restore other registers
   pop   r10
   pop   rsi
   ;; Retrieve the parameters from the shadow space
   mov   r9, [rsp+32]
   mov   r8, [rsp+24]
   mov   rdx, [rsp+16]
   mov   rcx, [rsp+8]
   ret

;;;; Function int2str_OCD
;;;; Takes an int and the address of a string
;;;; Returns the number of bytes in the converted string in EAX
;;;; Handles negative outputs
;;;; This is the paranoid version
int2str_OCD:
   ;; Entry code (preamble)
   ;; Copy parameters into shadow space
   mov   [rsp+8], rcx  ; Parameter 1 (value)
   mov   [rsp+16], rdx ; Parameter 2 (address)
   mov   [rsp+24], r8  ; Parameter 3 not actually used
   mov   [rsp+32], r9  ; parameter 4 not actually used
   ;; Save other registers used
   push  rdi
   push  r10

   ;; Body code goes here
   mov   eax, ecx    ; EAX <- value
   mov   rdi, rdx    ; Address
   mov   rcx, 0      ; Clear rcx (will store byte count)
   mov   r9, 1       ; Sign
   mov   r10, 1      ; 10 ** 0, for counting digits

   ;; Handle negative sign, if any
   cmp   eax, 0
   jge   int2str_OCD_CountDigits
   neg   eax
   neg   r9                      ; Sign is now negative
   mov   byte [rdi], ASCII_MINUS 
   inc   rdi                     ; Point to the place for the first digit
                                 ; Count of characters will be incremented later

   ;; Find number of digits
   int2str_OCD_CountDigits:
      inc   rcx
      imul  r10d, 10  ; Signed multiplication so product can go in R10D
      cmp   eax, r10d
      jg    int2str_OCD_CountDigits
   ;; RCX now holds the number of digits in the number
   add   rdi, rcx    ; RDI = RDI + RCX - 1 (next line)
   dec   rdi         ; RDI now points to the place for the *last* digit
   mov   r10d, 10    ; Divisor
   mov   rdx, 0      ; Clear out rdx before the first division

   int2str_OCD_MainLoop:
      div   r10d
      add   dl, ASCII_ZERO    ; numeric to string
      mov   [rdi], dl         ; Stow it away
      mov   rdx, 0            ; Clear it out, so the next div works
      dec   rdi               ; Back up to the previous digit
      cmp   eax, 0
      jg    int2str_OCD_MainLoop

   ;; RDI now points one place before the first digit
   add   rdi, rcx             ; add the number of digits
   mov   [rdi+1], byte 0Dh    ; Carriage return.  Note this should be RDI+1 if there is no minus sign, but RDI if there is.
   mov   [rdi+2], byte 0Ah    ; Line feed
   add   rcx, 2               ; Add those 2 bytes to the length

   ;; If the number was negative, increment ECX for the minus sign
   cmp   r9, 0
   jge   int2str_OCD_NoMinus
   inc   ecx                  ; One more character for the minus sign
   int2str_OCD_NoMinus:

   mov   eax, ecx             ; Put the return value (number of bytes) into EAX

   ;; Exit code (epilogue)
   ;; Restore other registers
   pop   r10
   pop   rdi
   ;; Retrieve the parameters from the shadow space
   mov   r9, [rsp+32]
   mov   r8, [rsp+24]
   mov   rdx, [rsp+16]
   mov   rcx, [rsp+8]
   ret

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

 ;; Prompt for the first integer
 sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
                                                ; to a multiple of 16 bytes (MS x64 calling convention)
 mov   RCX, qword [REL StdOutHandle]            ; 1st parameter
 lea   RDX, [REL Prompt1]                       ; 2nd parameter
 mov   R8, Prompt1Length                        ; 3rd parameter
 lea   R9, [REL BytesWritten]                   ; 4th parameter
 mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
 call  WriteFile                                ; Output can be redirected to a file using >
 add   RSP, 48                                  ; Remove the 48 bytes

;; Read the first integer
 sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
                                                ; to a multiple of 16 bytes (MS x64 calling convention)
 mov   RCX, qword [REL StdInHandle]             ; 1st parameter
 lea   RDX, [REL InputSpace]                    ; 2nd parameter
 mov   R8, MAX_INPUT_LENGTH                     ; 3rd parameter
 lea   R9, [REL BytesRead]                      ; 4th parameter
 mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
 call  ReadFile                                 ; Output can be redirected to a file using >
 add   RSP, 48                                  ; Remove the 48 bytes

;; Convert the first integer string -> int
 sub   RSP, 32                                  ; Shadow space
 mov   ECX, [REL BytesRead]                     ; Length of string, including CRLF
 lea   RDX, [REL InputSpace]                    ; Address of string
 call  str2int
 mov   [REL Term1], eax                         ; Store the term
 add   RSP, 32                                  ; Dump shadow space

;; Prompt for the second integer
 sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
                                                ; to a multiple of 16 bytes (MS x64 calling convention)
 mov   RCX, qword [REL StdOutHandle]            ; 1st parameter
 lea   RDX, [REL Prompt2]                       ; 2nd parameter
 mov   R8, Prompt2Length                        ; 3rd parameter
 lea   R9, [REL BytesWritten]                   ; 4th parameter
 mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
 call  WriteFile                                ; Output can be redirected to a file using >
 add   RSP, 48                                  ; Remove the 48 bytes

;; Read the second integer

 sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
                                                ; to a multiple of 16 bytes (MS x64 calling convention)
 mov   RCX, qword [REL StdInHandle]             ; 1st parameter
 lea   RDX, [REL InputSpace]                    ; 2nd parameter
 mov   R8, MAX_INPUT_LENGTH                     ; 3rd parameter
 lea   R9, [REL BytesRead]                      ; 4th parameter
 mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
 call  ReadFile                                 ; Output can be redirected to a file using >
 add   RSP, 48                                  ; Remove the 48 bytes

;; Convert the second integer string -> int
 sub   rsp, 32                                  ; Shadow space
 mov   ecx, [REL BytesRead]                     ; Parameter 1: bytes read
 lea   rdx, [REL InputSpace]                    ; Parameter 2: address of the string
 call  str2int
 mov   [REL Term2], eax                         ; Store the term
 add   rsp, 32                                  ; Dump the shadow space

;; Find the sum
 add    eax, [REL Term1]                        ; Do the actual addition
 mov    [REL Total], eax                        ; Store the sum

;; Print the label for the sum
 sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
                                                ; to a multiple of 16 bytes (MS x64 calling convention)
 mov   RCX, qword [REL StdOutHandle]            ; 1st parameter
 lea   RDX, [REL Message]                       ; 2nd parameter
 mov   R8, MessageLength                        ; 3rd parameter
 lea   R9, [REL BytesWritten]                   ; 4th parameter
 mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
 call  WriteFile                                ; Output can be redirected to a file using >
 add   RSP, 48                                  ; Remove the 48 bytes

;; Convert the sum to a string
 sub  rsp, 32                                   ; Shadow space
 mov  ecx, [REL Total]                          ; Parameter 1: number
 lea  rdx, [REL InputSpace]                     ; Parameter 2: address of string space
 call int2str
 mov  [REL BytesRead], eax                      ; Store the length of the string written
 add  rsp, 32                                   ; Dump the shadow space

;; Print the sum itself
 sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
                                                ; to a multiple of 16 bytes (MS x64 calling convention)
 mov   RCX, qword [REL StdOutHandle]            ; 1st parameter
 lea   rdx, [REL InputSpace]
 mov   R8, [REL BytesRead]                      ; 3rd parameter
 lea   R9, [REL BytesWritten]                   ; 4th parameter
 mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
 call  WriteFile                                ; Output can be redirected to a file using >
 add   RSP, 48                                  ; Remove the 48 bytes

;; Return code 0 for normal completion
 mov   ECX, dword 0                             ; Produces 0 for the return code
 call  ExitProcess
