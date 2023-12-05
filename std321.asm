%define STD321_NO_EXTERNS
%include "std321.inc"

STD_OUTPUT_HANDLE   EQU -11
STD_INPUT_HANDLE    EQU -10

extern GetStdHandle                             ; Import external symbols
extern ReadFile
extern WriteFile                                ; Windows API functions, not decorated

global std321_int_to_str_fn
global std321_str_to_int_fn
global std321_read_str_fn
global std321_write_str_fn
global std321_read_int_fn
global std321_write_int_fn

;; Get a standard handle.  Arguments are the constant for the handle and the
;; address where it should be stored.
%macro  std321_GetHandle   2
    sub     rsp, 32
    mov     rcx, %1
    call    GetStdHandle
    mov     %2, rax
    add     rsp, 32
%endmacro

;; Get the handle for standard output and leave it in RCX.  If the handle
;; has previously been gotten, this macro will not re-fetch, but rather
;; reuse the previous result.
%macro  std321_GetWriteHandle   0
    ;; Has the write handle been fetched yet?
    mov                 rcx, [REL StdOutHandle]
    cmp                 rcx, 0
    jnz                 %%WriteHandleFound
    std321_GetHandle    STD_OUTPUT_HANDLE, [REL StdOutHandle]
    mov                 rcx, [REL StdOutHandle]
    %%WriteHandleFound:
%endmacro

%macro  std321_GetReadHandle    0
    ;; Has the read handle been fetched yet?
    mov                 rcx, [REL StdInHandle]
    cmp                 rcx, 0
    jnz                 %%ReadHandleFound
    std321_GetHandle    STD_INPUT_HANDLE, [REL StdInHandle]
    mov                 rcx, [REL StdInHandle]
    %%ReadHandleFound:
%endmacro

section .data
    StdOutHandle    dq  0
    StdInHandle     dq  0

section .text

;; function std321_int_to_str_fn
;; Used by int_to_str macro
;; Arguments are integer to convert and address of string
;; Result (left in RAX) is the length (in bytes) of the string
;; Integer to convert is limited to 64 bits by size of RCX.  Therefore
;; string is limited to 20 characters (19 for 2^63, plus one for a sign)
std321_int_to_str_fn:
    ;; Entry code
    ParamsToShadow
    ;; No non-volatile registers are used

    ;; Body code
    mov     rax, rcx    ; RAX <- value
    mov     r11, rdx    ; r11 <- address
    mov     rcx, 0      ; Clear rcx (will store byte count)
    mov     r9, 1       ; Sign
    mov     r10, 1      ; 10 ** 0, for counting digits

    ;; Handle negative sign, if any
    cmp     rax, 0
    jge     .CountDigits
    neg     rax
    neg     r9                      ; Sign is now negative
    mov     byte [r11], ASCII_MINUS 
    inc     r11                     ; Point to the place for the first digit
                                    ; Count of characters will be incremented later

    ;; Find number of digits
    .CountDigits:
        inc     rcx
        imul    r10, 10  ; Signed multiplication so product can go in R10
        cmp     rax, r10
        jg      .CountDigits
    ;; RCX now holds the number of digits in the number
    add     r11, rcx    ; R11 = R11 + RCX - 1 (next line)
    dec     r11         ; R11 now points to the place for the *last* digit
    mov     r10, 10     ; Divisor
    mov     rdx, 0      ; Clear out rdx before the first division

    .MainLoop:
        div     r10
        add     dl, ASCII_ZERO    ; numeric to string
        mov     [r11], dl         ; Stow it away
        mov     rdx, 0            ; Clear it out, so the next div works
        dec     r11               ; Back up to the previous digit
        cmp     rax, 0
        jg      .MainLoop

    ;; If the number was negative, increment ECX for the minus sign
    cmp     r9, 0
    jge     .NoMinus
    inc     rcx                  ; One more character for the minus sign

.NoMinus:
    mov     rax, rcx             ; Put the return value (number of bytes) into EAX
    ret

;;; Function std321_str_to_int_fn
;;; Used by str_to_int macro
;;; Takes the length and address of a string
;;; Returns the string converted to int (in RAX)
;;; Handles negative inputs.  Ignores a CR/LF at the end of the string, if present.
std321_str_to_int_fn:
    ;; Parameters are length of the string and address of the string
    ;; Entry code (preamble)
    ParamsToShadow
   
    ;; Body code goes here
    mov     rax, 0      ; Clear RAX (where result will go)
    mov     r11, rcx    ; R11 <- string address
    mov     r8, rcx     ; r8 gets string address for CR/LF handling
    mov     rcx, rdx    ; RCX <- length of string
    
    ;; CR/LF handling
    add     r8, rcx                 ; Advance r8 to end of string
    sub     r8, 2                   ; Come back 2 bytes
    cmp     byte [r8], ASCII_CR     ; Looking at a CR?
    jne     .NoCrLf
    sub     rcx, 2                  ; If CR/LF are present, subtract 2 from RCX
    .NoCrLf:

    mov     r8, 0                   ; clear R8
    mov     r9, 1                   ; Sign
    mov     r10, 10                 ; Base 10; value in R10 to allow multiplying

    ;; Handle the sign character (if any)                         
    jrcxz   .endLoop                ; Make sure there are, in fact, characters to read
    mov     r8b, [r11]              ; Look at the first char
    cmp     r8b, ASCII_MINUS
    jne     .Loop                   ; If no minus sign, pretend we didn't even look
    ;; r8b == '-'. Store the fact that we saw a '-' character.
    neg     r9                      ; Sign <- -1
    dec     rcx                     ; Consumed a character
    inc     r11

    ;; Main loop
    jrcxz   .endLoop                ; if CX <= 0, jump to the end of the loop
    ;; while R8 > 0
    .Loop:
        mul     r10                 ; RAX *= 10 (previous digits)
        mov     r8b, [r11]          ; Move one digit into R8B
        sub     r8b, ASCII_ZERO     ; Char to numeric
        add     rax, r8             ; Add in the current digit
        inc     r11                 ; Point RSI at the next digit
        loop    .Loop               ; If RCX > 0, decrement RCX and do it again
    .endLoop:                       ; End the loop
    imul  r9                        ; Result *will* fit in RAX

    ;; Exit code (epilogue)
    ret

;;; Function std321_write_str_fn
;;; Arguments are address of string and length of string.  The number of bytes
;;; written is returned in RAX.
;;; If the standard write handle has not been gotten previously, this function
;;; will get it and store it for future use.
std321_write_str_fn:
    ParamsToShadow
    ;; Establish a stack frame
    push    rbp
    mov     rbp, rsp
    ;; Make space for a local variable on the stack
    sub     rsp, 8
    ;; Stack frame:
    ;; BYTE_COUNT           [rbp - 8]
    ;; (old RBP):           [rbp]
    ;; (return address):    [rbp + 8]
    ;; STRING_ADDR          [rbp + 16]
    ;; STRING_LENGTH        [rbp + 24]

    std321_GetWriteHandle
    ;; Print the prompt
    sub     rsp, (32 + 8 + 8)   ; Shadow space, leaving room the fifth parameter
                                ; and 8 more bytes for 16-byte alignment.
    ;; Handle is already in RCX
    mov     rdx, [rbp + 16]
    mov     r8,  [rbp + 24]
    lea     r9,  [rbp - 8]
    mov     FIFTH_PARAM, NULL
    call    WriteFile           ; Output can be redirected to a file using >
    add     rsp, 48

    ;; Put bytes written into RAX
    mov     rax, [rbp - 8]

    ;; Exit code
    ;; Get rid of local variable space
    add     rsp, 8
    ;; Pop non-volatile register
    pop     rbp
    ret

;;; Function std321_read_str_fn
;;; Arguments are address of prompt, length of prompt, address of string space,
;;; and maximum length of input.
;;; If the standard handles have not been gotten previously, this function
;;; will get them and store them for future use.
std321_read_str_fn:
    ParamsToShadow
    ;; Establish a stack frame
    push    rbp
    mov     rbp, rsp
    ;; Make space for a local variable on the stack
    sub     rsp, 8
    ;; Stack frame:
    ;; BYTES_READ        [rbp - 8]
    ;; (old RBP):        [rbp]
    ;; (return address): [rbp + 8]
    ;; PROMPT_ADDR       [rbp + 16]
    ;; PROMPT_LENGTH     [rbp + 24]
    ;; STRING_ADDR       [rbp + 32]
    ;; MAX_LENGTH        [rbp + 40]

    ;; Print the prompt
    write_str_no_lea    [rbp+16], [rbp+24]

    ;; Read the string
    std321_GetReadHandle
    sub     rsp, (32 + 8 + 8)   ; Shadow space, leaving room the fifth parameter
                                ; and 8 more bytes for 16-byte alignment.
    ;; Handle is already in RCX
    mov     rdx, [rbp + 32]
    mov     r8, [rbp + 40]
    lea     r9, [rbp - 8]
    mov     FIFTH_PARAM, NULL
    call    ReadFile
    add     rsp, 48

    ;; Put bytes read into RAX
    mov     rax, [rbp - 8]

    ;; Exit code
    ;; Get rid of local variable space
    add     rsp, 8
    ;; Pop non-volatile register
    pop     rbp
    ret

;;; Function std321_read_int_fn
;;; Used by read_int macro in std321.inc.
;;; Arguments are address of prompt string and length of prompt.
;;; If the standard handles have not been gotten previously, this function
;;; will get them and store them for future use.
std321_read_int_fn:
    ParamsToShadow
    ;; Establish a stack frame
    push    rbp
    mov     rbp, rsp
    ;; Make space for local variables on the stack
    sub     rsp, 8 * ((MAX_INT_LENGTH + 2) + 1)
    ;; Local variable addresses
    ;; BYTE_COUNT        [rbp - 112]
    ;; STRING_SPACE      [rbp - 104]
    ;; (old RBP):        [rbp]
    ;; (return address): [rbp + 8]
    ;; PROMPT_ADDR       [rbp + 16]
    ;; PROMPT_LENGTH     [rbp + 24]

    ;; Print the prompt and read the string
    read_str_one_lea    [rbp + 16], [rbp + 24], [rbp - 104], MAX_INT_LENGTH
    ;; Returns number of bytes read in RAX

    ;; Convert to int
    str_to_int [rbp - 104], rax
    ;; Leaves result in RAX

    ;; Exit code
    ;; Get rid of local variable space
    add   rsp, 8 * ((MAX_INT_LENGTH + 2) + 1)
    ;; Pop non-volatile register
    pop   rbp
    ret

;;; Function std321_write_int_fn
;;; Used by write_int macro in std321.inc.
;;; Arguments are the integer to be written, the address of a label string and
;;; the length of the label string.
;;; If the standard write handle has not been gotten previously, this function
;;; will get it and store it for future use.
std321_write_int_fn:
    ParamsToShadow
    ;; Establish a stack frame
    push    rbp
    mov     rbp, rsp
    ;; Make space for local variables on the stack
    sub     rsp, 8 * ((MAX_INT_LENGTH + 2) + 1)
    ;; Local variable addresses
    ;; BYTE_COUNT           [rbp - 112]
    ;; STRING_SPACE         [rbp - 104]
    ;; (old RBP):           [rbp]
    ;; (return address):    [rbp + 8]
    ;; INT_TO_PRINT         [rbp + 16]
    ;; LABEL_ADDR           [rbp + 24]
    ;; LABEL_LENGTH         [rbp + 32]

    ;; Print the label
    write_str_no_lea        [rbp + 24], [rbp + 32]

    ;; Convert number to string
    int_to_str  [rbp + 16], [rbp - 104]
    mov         [rbp - 112], rax

    ;; Print the number
    ;; First, add a CR/LF if needed
    lea         r11, [rbp - 104]        ; Start of the string
    add         r11, [rbp - 112]        ; End of the string
    sub         r11, 2                  ; Jump back 2 bytes
    cmp         byte [r11], ASCII_CR    ; Looking at a CR?
    jz          .CrLfAdded              ; If not...
    add         r11, 2                  ; Set r11 back to the end of the string
    mov         byte [r11], 0Ah         ; Put the CR/LF on the end
    inc         r11
    mov         byte [r11], 0Dh     
    add         [rbp - 112], dword 2    ; add to BYTE_COUNT for the CR/LF
    
.CrLfAdded:
    write_str   [rbp - 104], [rbp - 112]

    ;; Exit code
    ;; Get rid of local variable space
    add   rsp, 8 * ((MAX_INT_LENGTH + 2) + 1)
    ;; Pop non-volatile register
    pop   rbp
    ret
