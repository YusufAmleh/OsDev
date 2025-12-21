;the first code that runs when the OS boots up. 
;it must fit within 512 bytes which is the size of 1 disk sector
;the BIOS loads it at memory addres 0x7C00
bits 16 ;tells assembler to generate 16-bit code since it starts in 16 bit real mode


%define ENDL 0x0D, 0x0A ;creates a macro for newfile characters 0x0D and 0x0A (carriage return and line feed, CR and LF) make a newline on the widnows system, like pressing enter

%define fat12 1
%define fat16 2
%define fat32 3
%define ext2  4

; FAT12 header
; FAT filesystems require the first 3 bytes to be a jump instruction followed by an NOP
;jmp shorrt is a 2-byte instruction and NOP is 1 byte

section .fsjump

    jmp short start
    nop

;Defines the FAT filesystem's BIOS Parameter Block (BPB)
;FAT filesystem stores metadata about itself in the first sector which tells the filesystem (mkfs.fat) how the disk is organized
;this section acts like the table of contents for our bootloader
section .fsheaders

%if (FILESYSTEM == fat12) || (FILESYSTEM == fat16) || (FILESYSTEM == fat32)

    bdb_oem:                    db "abcdefgh"           ; 8 bytes
    bdb_bytes_per_sector:       dw 512 ;each sector is 512 bytes
    bdb_sectors_per_cluster:    db 1 ;a cluster is 1 sector
    bdb_reserved_sectors:       dw 1 ;this first sector is reserved as the boot sector
    bdb_fat_count:              db 2  ;there are 2 copies of the FAT 
    bdb_dir_entries_count:      dw 0E0h
    bdb_total_sectors:          dw 2880              ;total disk is 2880 sector   ; 2880 * 512 = 1.44MB
    bdb_media_descriptor_type:  db 0F0h                 ; F0 = 3.5" floppy disk
    bdb_sectors_per_fat:        dw 9                    ; 9 sectors/fat
    bdb_sectors_per_track:      dw 18
    bdb_heads:                  dw 2
    bdb_hidden_sectors:         dd 0
    bdb_large_sector_count:     dd 0

    %if (FILESYSTEM == fat32)
        fat32_sectors_per_fat:      dd 0
        fat32_flags:                dw 0
        fat32_fat_version_number:   dw 0
        fat32_rootdir_cluster:      dd 0
        fat32_fsinfo_sector:        dw 0
        fat32_backup_boot_sector:   dw 0
        fat32_reserved:             times 12 db 0
    %endif

    ; extended boot record
    ebr_drive_number:           db 0                    ; 0x00 floppy, 0x80 hdd, useless
                                db 0                    ; reserved
    ebr_signature:              db 29h
    ebr_volume_id:              db 12h, 34h, 56h, 78h   ; serial number, value doesn't matter
    ebr_volume_label:           db 'NANOBYTE OS'        ; 11 bytes, padded with spaces
    ebr_system_id:              db 'FAT12   '           ; 8 bytes

%endif

;
; Code goes here
; copies 16 bytes from where the CPU is pointing (DS:SI) to some safe location
; basically copying the info before erasing it so that it's not lost
section .entry
    global start

    start:
        ; move partition entry from MBR to a different location so we 
        ; don't overwrite it (which is passed through DS:SI)
        mov ax, PARTITION_ENTRY_SEGMENT
        mov es, ax
        mov di, PARTITION_ENTRY_OFFSET
        mov cx, 16
        rep movsb ;moves string byte (copes 1 byte from DS:SI to ES:DI) then repeats 16 times after each copy DI and SI are incremented
        
        ; setup data segments
        mov ax, 0           ; can't set ds/es directly
        mov ds, ax
        mov es, ax
        
        ; setup stack
        mov ss, ax
        mov sp, 0x7C00              ; stack grows downwards from where we are loaded in memory

        ; some BIOSes might start us at 07C0:0000 instead of 0000:7C00, this ensures that we actually use the latter
        push es
        push word .after ;by pushing ES and .after we ensure we load at the correct address
        retf

    .after:

        ; read something from floppy disk
        ; BIOS should set DL to drive number so we can read from the correct disk later
        mov [ebr_drive_number], dl ;saves BOOT drive number

        ; check if LBA extensions are present for disk access
        ;old BIOS used CHS addressing (Cyl-head-sector) but now the use LBA (logical Block addressing) which i just a sector number 
        mov ah, 0x41 ;checks extension
        mov bx, 0x55AA ;makes a unique signature
        stc
        int 13h ;calls BIOS disk services
        ; if extensions exist BX becomes 0xAA55, carry flag clears
        ; otherwise BX unchanged carry flag stays set


        ;records whether LBA extensions are available 
        ;this is used later to choose between LBA or CHS
        jc .no_disk_extensions
        cmp bx, 0xAA55
        jne .no_disk_extensions

        ; extensions are present
        mov byte [have_extensions], 1
        jmp .after_disk_extensions_check

    .no_disk_extensions:
        mov byte [have_extensions], 0

    .after_disk_extensions_check:



        ;sets up to load stage 2 into memory
        ;stage 2 is larger than 512 bytes so its stored as a regular file on disk so we need to load it into memory first
        ;stage 2 is stored starting at the sector right after the boot sector
        mov si, stage2_location ;contains location of stage 2

        mov ax, STAGE2_LOAD_SEGMENT         ; set segment registers
        mov es, ax

        mov bx, STAGE2_LOAD_OFFSET



    ; reads stage 2 from disk in a loop
    ;stage 2 is formated as 4 bytes - LBA sector #, 1 byte - number of sectors to read, repeat, ends with 0
    ;the reason for this format is since s2 might be split across non-contiguous sectors so this format describes the location of each of its fragments
    ;tells the BIOS where each fragment of s2 is stored so that it reads from there
    .loop:
        mov eax, [si]
        add si, 4
        mov cl, [si]
        inc si

        cmp eax, 0
        je .read_finish

        call disk_read

        xor ch, ch
        shl cx, 5
        mov di, es
        add di, cx
        mov es, di

        jmp .loop

    .read_finish:
        
        ; jump to our kernel
        mov dl, [ebr_drive_number]          ; boot device in dl
        mov si, PARTITION_ENTRY_OFFSET
        mov di, PARTITION_ENTRY_SEGMENT
    
        mov ax, STAGE2_LOAD_SEGMENT         ; set segment registers
        mov ds, ax
        mov es, ax

        jmp STAGE2_LOAD_SEGMENT:STAGE2_LOAD_OFFSET ;if everything works we jump to stage 2, far jump is used since we need to jump to a different code segment, near jump would only jump w/in our current code

        jmp wait_key_and_reboot             ; should never happen

        cli                                 ; disable interrupts, this way CPU can't get out of "halt" state
        hlt


section .text

    ;
    ; Error handlers
    ;

    floppy_error:
        mov si, msg_read_failed
        call puts
        jmp wait_key_and_reboot

    kernel_not_found_error:
        mov si, msg_stage2_not_found
        call puts
        jmp wait_key_and_reboot

    wait_key_and_reboot:
        mov ah, 0
        int 16h                     ; wait for keypress
        jmp 0FFFFh:0                ; jump to beginning of BIOS, should reboot

    .halt:
        cli                         ; disable interrupts, this way CPU can't get out of "halt" state
        hlt


    ;
    ; Prints a string to the screen
    ; Params:
    ;   - ds:si points to string
    ;
    puts:
        ; save registers we will modify
        push si
        push ax
        push bx

    .loop:
        lodsb               ; loads next character in al
        or al, al           ; verify if next character is null?
        jz .done

        mov ah, 0x0E        ; call bios interrupt
        mov bh, 0           ; set page number to 0
        int 0x10

        jmp .loop

    .done:
        pop bx
        pop ax
        pop si    
        ret

    ;
    ; Disk routines
    ;

    ;
    ; Converts an LBA address to a CHS address
    ; Parameters:
    ;   - ax: LBA address
    ; Returns:
    ;   - cx [bits 0-5]: sector number
    ;   - cx [bits 6-15]: cylinder
    ;   - dh: head
    ;

    lba_to_chs:

        push ax
        push dx

        xor dx, dx                          ; dx = 0
        div word [bdb_sectors_per_track]    ; ax = LBA / SectorsPerTrack
                                            ; dx = LBA % SectorsPerTrack

        inc dx                              ; dx = (LBA % SectorsPerTrack + 1) = sector, since sector number starts from 1
        mov cx, dx                          ; cx = sector

        xor dx, dx                          ; dx = 0
        div word [bdb_heads]                ; ax = (LBA / SectorsPerTrack) / Heads = cylinder
                                            ; dx = (LBA / SectorsPerTrack) % Heads = head
        mov dh, dl                          ; dh = head
        mov ch, al                          ; ch = cylinder (lower 8 bits)
        shl ah, 6
        or cl, ah                           ; put upper 2 bits of cylinder in CL

        pop ax
        mov dl, al                          ; restore DL
        pop ax
        ret


    ;
    ; Reads sectors from a disk using either LBA or CHS depending on availability
    ; Parameters:
    ;   - eax: LBA address
    ;   - cl: number of sectors to read (up to 128)
    ;   - dl: drive number
    ;   - es:bx: memory address where to store read data
    ; BIOS functions can unpredictably modify registers so we save them to perserve our state
    disk_read:

        push eax                            ; save registers we will modify
        push bx
        push cx
        push dx
        push si
        push di

        cmp byte [have_extensions], 1
        jne .no_disk_extensions

        ; with extensions
        ; fills in Disk Address Packet (DAP) structure and calls BIOS function 0x42
        mov [extensions_dap.lba], eax
        mov [extensions_dap.segment], es
        mov [extensions_dap.offset], bx
        mov [extensions_dap.count], cl

        mov ah, 0x42
        mov si, extensions_dap
        mov di, 3                           ; retry count
        jmp .retry

    ;CHS path, converts LBA to CHS then uses old BIOS function 0x02
    ;we convert to CHS since old BIOS doesn't undersntand LBA
    .no_disk_extensions:
        push cx                             ; temporarily save CL (number of sectors to read)
        call lba_to_chs                     ; compute CHS
        pop ax                              ; AL = number of sectors to read
        
        mov ah, 02h
        mov di, 3                           ; retry count

    ;retries disk read until success (maxes out at 3 retries)
    ;disk operations can fail without beinf wrong, so retrying usually fixes the issue
    ;saves all gates with pusha, sets carry glag, calls BIOS interrupt, if carry clear then success so jump to .done othweise retry
    ;if all retries (3) are exhausted we jump to error handler
    ;DI starts at 3 then defcrements each try that's how we keep count
    .retry:
        pusha                               ; save all registers, we don't know what bios modifies
        stc                                 ; set carry flag, some BIOS'es don't set it
        int 13h                             ; carry flag cleared = success
        jnc .done                           ; jump if carry not set

        ; read failed
        popa
        call disk_reset

        dec di
        test di, di
        jnz .retry

    .fail:
        ; all attempts are exhausted
        jmp floppy_error

    .done:
        popa

        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop eax                            ; restore registers modified
        ret


    ;
    ; Resets disk controller
    ; Parameters:
    ;   dl: drive number
    ;
    disk_reset:
        pusha
        mov ah, 0
        stc
        int 13h
        jc floppy_error
        popa
        ret

section .rodata

    msg_read_failed:        db 'Read failed!', ENDL, 0
    msg_stage2_not_found:   db 'STAGE2.BIN not found!', ENDL, 0
    file_stage2_bin:        db 'STAGE2  BIN'

section .data

    have_extensions:        db 0
    extensions_dap:
        .size:              db 10h
                            db 0
        .count:             dw 0
        .offset:            dw 0
        .segment:           dw 0
        .lba:               dq 0

    STAGE2_LOAD_SEGMENT     equ 0x0
    STAGE2_LOAD_OFFSET      equ 0x500

    PARTITION_ENTRY_SEGMENT equ 0x2000
    PARTITION_ENTRY_OFFSET  equ 0x0


section .data
    global stage2_location
    stage2_location:        times 30 db 0

section .bss
    buffer:                 resb 512

    ;Summmary of Stage 1 Process:
    ; Saves parition info (if from MBR)
    ; Set up segments and stack
    ; Detects disk capabilties (LBA vs CHS)
    ; Reads Stage 2 from disk into memory at 0x500
    ; Jumps to Stage 2
    ; Everything here fits into 512 bytes (technically 510 since 2 are reserved for boot signature 0xAA55)