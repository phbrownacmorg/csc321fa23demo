; Read two numbers from the keyboard, add them, and display the result
NULL                EQU 0                       ; Constants, to be expanded by the preprocessor
STD_OUTPUT_HANDLE   EQU -11                     ;   (no memory locations for these, just substituted into code)
STD_INPUT_HANDLE    EQU -10
MAX_INPUT_LENGTH    EQU 10                      ; Nine digits and a sign
ASCII_ZERO          EQU 48

extern GetStdHandle                             ; Import external symbols
extern ReadFile
extern WriteFile                                ; Windows API functions, not decorated
extern ExitProcess

global Start                                    ; Export symbols. The entry point

section .data                                   ; Initialized data segment, mostly used for constants
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

 Term1          resq 1                          ; First term of addition
 Term2          resq 1                          ; Second term of addition
 Sum            resq 1                          ; Storage for the sum
 InputSpace     resb MAX_INPUT_LENGTH + 2       ; Use for all input commands
 BytesRead      resq 1
 SumStart       resq 1                          ; Address of the start of the sum

section .text                                   ; Code segment
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
 mov   EAX, 0                                   ; Clear EAX (where result will go)
 mov   R8, 0                                    ; Clear R8 (where each digit will go)
 lea   RSI, [REL InputSpace]                    ; Beginning of the string
 mov   ECX, [RSI + MAX_INPUT_LENGTH + 2]         ; BytesRead -> ECX
 sub   ECX, 2                                    ; Subtract 2 to exclude the CR/LF at the end
 mov   R10, 10                                 ; Base 10; value in R10 to allow multiplying
 ;; while ECX > 0
while_ECX_gt_0_1:
 cmp   ECX, 0                                    ; compare ECX to 0
 je    endwhile_ECX_gt_0_1                       ; if ECX == 0, jump to the end of the loop

 mov   R8B, [RSI]                               ; Move one digit into the low byte of R8
 sub   R8D, ASCII_ZERO                          ; Char to numeric
 mul   R10D                                     ; EAX *= 10 (previous digits)
 add   EAX, R8D                                 ; Add in the current digit
 dec   ECX                                      ; One less digit to handle
 inc   RSI                                      ; Point RSI at the next digit

 jmp   while_ECX_gt_0_1                         ; Jump back to the beginning of the while and do it again
endwhile_ECX_gt_0_1:                            ; End the loop
 mov   [REL Term1], EAX                         ; Store the first term to free up EAX

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
 mov   R8, 0                                    ; Clear R8 (where each digit will go)
 lea   RSI, [REL InputSpace]                    ; Beginning of the string
 mov   ECX, [RSI + MAX_INPUT_LENGTH + 2]         ; BytesRead -> ECX
 sub   ECX, 2                                    ; Subtract 2 to exclude the CR/LF at the end
 mov   R10, 10                                 ; Base 10; value in R10 to allow multiplying
 ;; while ECX > 0
while_ECX_gt_0_2:
 cmp   ECX, 0                                    ; compare ECX to 0
 je    endwhile_ECX_gt_0_2                       ; if ECX == 0, jump to the end of the loop

 mul   R10D                                     ; EAX *= 10 (previous digits)
 mov   R8B, [RSI]                               ; Move one digit into the low byte of R8
 sub   R8D, ASCII_ZERO                          ; Char to numeric
 add   EAX, R8D                                 ; Add in the current digit
 dec   ECX                                      ; One less digit to handle
 inc   RSI                                      ; Point RSI at the next digit

 jmp   while_ECX_gt_0_2                         ; Jump back to the beginning of the while and do it again
endwhile_ECX_gt_0_2:                            ; End the loop
 mov   [REL Term2], EAX                         ; Store the first term to free up EAX

;; Find the sum
add     eax, [REL Term1]
mov     [REL Sum], eax                          ; Squirrel it away so nothing bad happens to it

;; Convert the sum to a string and put it in InputSpace, with its length in BytesRead
mov     ecx, 2                                  ; ECX := number of bytes.  Initially two for the CR/LF.
lea     rdi, [REL InputSpace + MAX_INPUT_LENGTH - 1] ; Address of the last digit in InputSpace
mov     [RDI+1], byte 0Dh
mov     [RDI+2], byte 0Ah

    mov     r10d, 10                            ; 10 -> R10D to allow division
while_EAX_gt_0:
    div     r10d                                ; quotient in EAX, remainder in EDX
    add     edx, ASCII_ZERO                     ; number -> ASCII digit
    mov     [rdi], dl                           ; digit -> memory
    mov     edx, 0                              ; Clear EDX in preparation for the next div
    inc     ecx                                 ; one more digit
    dec     rdi                                 ; RDI points to previous byte
    cmp     eax, 0
    jne     while_EAX_gt_0
mov     [REL BytesRead], CL                     ; Number of digits to BytesRead
inc     RDI                                     ; Point back to the last byte written
mov     [REL SumStart], RDI                     ; Address of the beginning of the number

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

;; Print the sum itself
lea   RSI, [REL SumStart]
sub   RSP, 32 + 8 + 8                          ; Shadow space + 5th parameter + align stack
                                                ; to a multiple of 16 bytes (MS x64 calling convention)
mov   RCX, qword [REL StdOutHandle]            ; 1st parameter
mov   RDX, [RSI]                               ; 2nd parameter
mov   R8, [REL BytesRead]                      ; 3rd parameter
lea   R9, [REL BytesWritten]                   ; 4th parameter
mov   qword [RSP + 4 * 8], NULL                ; 5th parameter
call  WriteFile                                ; Output can be redirected to a file using >
add   RSP, 48                                  ; Remove the 48 bytes

;; Return code 0 for normal completion
 mov   ECX, dword 0                             ; Produces 0 for the return code
 call  ExitProcess
