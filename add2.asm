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

;;; Function str2int
;;; Takes the address and length of a string
;;; Returns the string converted to int (in EAX)
;;; Handles negative inputs
str2int: ;; Beginning of function is just a label
   ;; Parameters are address of string and length of string
   ;; Preamble: Copy parameters into shadow space
   mov [rbp+8], rcx  ; Parameter 1
   mov [rbp+16], rdx ; Parameter 2
   mov [rbp+24], r8  ; Parameter 3 not actually used
   mov [rbp+32], r9  ; parameter 4 not actually used



   ;; At the end
   ;; Retrieve the parameters from the shadow space
   mov r9, [rbp+32]
   mov r8, [rbp+24]
   mov rdx, [rbp+16]
   mov rcx, [rbp+8]
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

 sub   RSP, 32                                  ; Shadow space
 lea   RCX, [REL InputSpace]                    ; Addess of string
 mov   EDX, [REL BytesRead]                     ; Length of string, including CRLF
 call  str2int
 add   RSP, 32                                  ; Dump shadow space

;; Convert the first integer string -> int
 mov   EAX, 0                                   ; Clear EAX (where result will go)
 lea   RSI, [REL InputSpace]                    ; Beginning of the string
 mov   ECX, [REL BytesRead]                     ; BytesRead -> CX
 sub   ECX, 2                                   ; Subtract 2 to exclude the CR/LF at the end
 mov   R8, 0                                    ; clear R8
 mov   R9D, 1                                   ; Sign
 mov   R10, 10                                  ; Base 10; value in R10 to allow multiplying

 ;; Handle the sign character (if any)
                                   
 jecxz   endwhile_CX_gt_0_1                      ; Make sure there are actual characters to read
 mov    r8b, [RSI]                               ; Look at the first char
    ;;; If cl == '-'
 cmp    r8b, ASCII_MINUS
    ;;;; jump if cl != '-'.  That is, *invert* the IF test you want.
 jne    while_CX_gt_0_1                         ; If no sign, pretend we didn't even look

 ;;; cl == '-'. Store the fact that we saw a '-' character.
 neg    R9D                                     ; Sign <- -1
 dec    ECX                                      ; Consumed a character
 inc    RSI

 jecxz  endwhile_CX_gt_0_1                       ; if CX <= 0, jump to the end of the loop
 ;; while R8 > 0
while_CX_gt_0_1:
 mul   R10D                                     ; EAX *= 10 (previous digits)
 mov   r8b, [RSI]                               ; Move one digit into CL
 sub   r8b, ASCII_ZERO                          ; Char to numeric
 add   eax, r8d                                 ; Add in the current digit
 inc   RSI                                      ; Point RSI at the next digit

 loop  while_CX_gt_0_1                          ; Jump back to the beginning of the while and do it again
endwhile_CX_gt_0_1:                             ; End the loop
 imul  R9D                                      ; Result *will* fit in EAX
 mov   [REL Term1], eax                         ; Store the term

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
 mov   EAX, 0                                   ; Clear EAX (where result will go)
 lea   RSI, [REL InputSpace]                    ; Beginning of the string
 mov   R8, [REL BytesRead]                      ; BytesRead -> R8
 sub   R8, 2                                    ; Subtract 2 to exclude the CR/LF at the end
 mov   R9D, 1                                   ; Sign
 mov   R10, 10                                  ; Base 10; value in R10 to allow multiplying

 ;; Handle the sign character (if any)
 cmp    R8, 0                                   ; Make sure there are actual characters to read
 je     endwhile_R8_gt_0_2
 mov    cl, [RSI]                               ; Look at the first char
    ;;; If cl == '-'
 cmp    cl, ASCII_MINUS
    ;;;; jump if cl != '-'.  That is, *invert* the IF test you want.
 jne    while_R8_gt_0_2                         ; If no sign, pretend we didn't even look

 ;;; cl == '-'. Store the fact that we saw a '-' character.
 neg    R9D                                     ; Sign <- -1
 dec    R8                                      ; Consumed a character
 inc    RSI

 ;; while R8 > 0
while_R8_gt_0_2:
 cmp   R8, 0                                    ; compare R8 to 0
 je    endwhile_R8_gt_0_2                       ; if R8 <= 0, jump to the end of the loop

 mov   cl, [RSI]                                ; Move one digit into CL
 sub   ECX, ASCII_ZERO                          ; Char to numeric
 mul   R10D                                     ; EAX *= 10 (previous digits)
 add   eax, ecx                                 ; Add in the current digit
 dec   R8                                       ; One less digit to handle
 inc   RSI                                      ; Point RSI at the next digit

 jmp   while_R8_gt_0_2                          ; Jump back to the beginning of the while and do it again
endwhile_R8_gt_0_2:                             ; End the loop
 imul  r9d                                      ; Multiply by the sign
 mov   [REL Term2], eax                         ; Store the term

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
 mov    r8, 0                                   ; Clear byte count
 lea    rdi, [REL InputSpace + MAX_INPUT_LENGTH - 1] ; Point to last digit
 mov    [rdi+1], byte 0Dh                       ; Carriage return
 mov    [rdi+2], byte 0Ah                       ; Line feed
 add    r8, 2                                   ; Two bytes already there
 mov    eax, [REL Total]                        ; EAX <- sum
 mov    r9d, 1                                  ; Sign
 mov    r10d, 0Ah                               ; R10D <- 10, for division

    ;; Handle the sign
 ;; if EAX < 0
 cmp    eax, 0
 jge    Start_loop_int_to_string                ; Jump if the condition is *false*
 neg    r9d
 neg    eax

Start_loop_int_to_string:
 div    r10d                                    ; EAX <- EAX // 10, EDX <- EAX % 10
 add    dl, ASCII_ZERO                          ; quantity to digit
 mov    [rdi], dl                               ; Store the digit
 mov    edx, 0                                  ; Clear EDX, so the div works
 inc    r8                                      ; Another byte
 dec    rdi                                     ; Move RDI back to the next space
 cmp    eax, 0
 jg     Start_loop_int_to_string                ; Back to the beginning of the loop

    ;;; Add '-' if the original total was negative
 cmp    R9D, -1
 jne    Store_result                            ; Jump if sign was *not* negative (R9D == 1)
 mov    [rdi], byte ASCII_MINUS
 inc    r8
 dec    rdi

Store_result:
 inc    rdi                                     ; Last decrement was bogus
 mov    [REL StartTotal], rdi                   ; Store the starting address of the string
 mov    [REL BytesRead], r8                     ; Store the length of the total string

;; Print the sum itself
 sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
                                                ; to a multiple of 16 bytes (MS x64 calling convention)
 mov   RCX, qword [REL StdOutHandle]            ; 1st parameter
 mov   RDX, [REL StartTotal]                    ; 2nd parameter; mov not lea!
 mov   R8, [REL BytesRead]                      ; 3rd parameter
 lea   R9, [REL BytesWritten]                   ; 4th parameter
 mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
 call  WriteFile                                ; Output can be redirected to a file using >
 add   RSP, 48                                  ; Remove the 48 bytes

;; Return code 0 for normal completion
 mov   ECX, dword 0                             ; Produces 0 for the return code
 call  ExitProcess
