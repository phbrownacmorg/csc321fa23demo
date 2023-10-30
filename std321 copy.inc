;; Protect against this file being included multiple times
%ifndef STD321_INC
%define STD321_INC

NULL                EQU 0       ; Constants, to be expanded by the preprocessor
ASCII_CR            EQU 13     ;   (no memory locations for these, just
ASCII_LF            EQU 10     ;    substituted straight into the code)
ASCII_ZERO          EQU 48
ASCII_MINUS         EQU 45

;; External functions (from std321.obj)
extern  std321_int_to_str_fn
extern  std321_str_to_int_fn

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
    std321_int_to_str_fn
    add     rsp, 32
%endmacro

;; Convert a string to an integer
;; args are string address, string length
;; int is returned in RAX
%macro  str_to_int  2
    sub     rsp, 32
    lea     ecx, %1
    mov     edx, %2
    std321_str_to_int_fn
    add     rsp, 32
%endmacro

;; Read an integer from standard input.
;; Arguments are the address of a prompt string, and the length of the prompt
;; string.  The 64-bit integer is returned in RAX.

%macro  read_int    2
    sub     rsp, 32
    lea     ecx, %1
    mov     edx, %2
    std321_read_int_fn
    add     rsp, 32
%endmacro

;; Write an integer, with a label, to standard output.
;; Arguments are the integer to print, the address of the label string, and
;; the length of the label string.  The number of bytes written when printing
;; the integer is returned in RAX.

%macro  write_int   3
    sub     rsp, 32
    mov     ecx, %1
    lea     edx, %2
    mov     r8, %3
    std321_read_int_fn
    add     rsp, 32
%endmacro

%endif