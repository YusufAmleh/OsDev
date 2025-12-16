[org 0x7c00]
bits 16

    mov ah, 0x0e
    mov al, 'H'
    int 0x10
    mov al, 'i'
    int 0x10

hang:
    jmp hang

times 510-($-$$) db 0
dw 0xaa55
