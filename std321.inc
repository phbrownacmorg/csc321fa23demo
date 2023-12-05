;; Protect against this file being included multiple times
%ifndef STD321_INC
%define STD321_INC

NULL                EQU 0       ; Constants, to be expanded by the preprocessor
ASCII_CR            EQU 13      ;   (no memory locations for these, just
ASCII_LF            EQU 10      ;    substituted straight into the code)
ASCII_ZERO          EQU 48
ASCII_MINUS         EQU 45

MAX_INT_LENGTH      EQU 11      ; Ten digits and a sign (for 32 bits)
MAX_STRING_LENGTH   EQU 90      ; 96 bytes less 4 for the length and 2 for the CR/LF
                                ; IS THE CR/LF ALLOWANCE CORRECT?

%ifndef STD321_NO_EXTERNS
    ;; External functions (from std321.obj)
    extern  std321_int_to_str_fn
    extern  std321_str_to_int_fn
    extern  std321_write_str_fn
    extern  std321_read_str_fn
    extern  std321_read_int_fn
    extern  std321_write_int_fn
%endif

;; Global macros
;;;; Fifth parameter
%define FIFTH_PARAM qword [rsp+32]    

%define BASE(a)     [(rbp)+(a)]
%define STACK(a)    [(rsp)+(a)]

;; Copy parameters into shadow space
%macro  ParamsToShadow   0
   mov   [rsp+8], rcx  ; Parameter 1
   mov   [rsp+16], rdx ; Parameter 2
   mov   [rsp+24], r8  ; Parameter 3
   mov   [rsp+32], r9  ; Parameter 4
%endmacro

;; Convert an integer into a string
;; args are int, string address
;; string length is returned in RAX
;; No CR-LF is added at the end of the string
%macro  int_to_str  2
    sub     rsp, 32
    mov     rcx, %1
    lea     rdx, %2
    call    std321_int_to_str_fn
    add     rsp, 32
%endmacro

;; Convert a string to an integer
;; args are string address, string length
;; int is returned in RAX
%macro  str_to_int  2
    sub     rsp, 32
    lea     rcx, %1
    mov     rdx, %2
    call    std321_str_to_int_fn
    add     rsp, 32
%endmacro

;; Write a string to standard input.
;; Arguments are the address of the string and the length of the string.
;; The number of bytes written is returned in RAX.
%macro  write_str   2
    sub     rsp, 32
    lea     rcx, %1
    mov     rdx, %2
    call    std321_write_str_fn
    add     rsp, 32
%endmacro

;; Write a string to standard input, without using lea to load the address of
;; the string.  This macro is intended for use inside another function, where
;; the address of the string has already been loaded once with lea and then 
;; stored.
;; Arguments are the address of the string and the length of the string.
;; The number of bytes written is returned in RAX.
%macro  write_str_no_lea   2
    sub     rsp, 32
    mov     rcx, %1
    mov     rdx, %2
    call    std321_write_str_fn
    add     rsp, 32
%endmacro

;; Read a string from standard input.
;; Arguments are the address of the prompt, length of the prompt, address
;; of string space, and the maximum number of bytes to read.  The number of
;; bytes read is returned in RAX.
%macro  read_str    3-4     MAX_STRING_LENGTH
    sub     rsp, 32
    lea     rcx, %1
    mov     rdx, %2
    lea     r8, %3
    mov     r9, %4
    call    std321_read_str_fn
    add     rsp, 32
%endmacro

;; Read a string from standard input, without using lea to load the address
;; of the prompt.  This macro is intended for use inside another function,
;; where the address of the prompt has already been loaded once with lea and
;; then stored.
;; Arguments are the address of the prompt, length of the prompt, address
;; of string space, and the maximum number of bytes to read.  The number of
;; bytes read is returned in RAX.
%macro  read_str_one_lea    4
    sub     rsp, 32
    mov     rcx, %1
    mov     rdx, %2
    lea     r8, %3
    mov     r9, %4
    call    std321_read_str_fn
    add     rsp, 32
%endmacro

;; Read an integer from standard input.
;; Arguments are the address of a prompt string, and the length of the prompt
;; string.  The 64-bit integer is returned in RAX.

%macro  read_int    2
    sub     rsp, 32
    lea     rcx, %1
    mov     rdx, %2
    call    std321_read_int_fn
    add     rsp, 32
%endmacro

;; Write an integer, with a label, to standard output.
;; Arguments are the integer to print, the address of the label string, and
;; the length of the label string.  The number of bytes written when printing
;; the integer is returned in RAX.

%macro  write_int   3
    sub     rsp, 32
    mov     rcx, %1
    lea     rdx, %2
    mov     r8, %3
    call    std321_read_int_fn
    add     rsp, 32
%endmacro

%endif