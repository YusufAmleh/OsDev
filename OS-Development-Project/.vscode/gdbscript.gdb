    symbol-file /home/yusuf_amleh/os-tutorial/OS-Development-Project/build/i686_debug/kernel/kernel.elf
    set disassembly-flavor intel
    target remote | qemu-system-i386 -S -gdb stdio -m 32 -hda /home/yusuf_amleh/os-tutorial/OS-Development-Project/build/i686_debug/kernel/kernel.elf
    