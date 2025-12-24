# MyOS: A 32-bit Monolithic Kernel from Scratch

**MyOS** is a custom 32-bit operating system kernel and bootloader written from scratch in C++ and x86 Assembly. 

This project was built to explore the depths of system architecture, hardware abstraction, and low-level memory management. It features a custom 2-stage bootloader, a monolithic kernel with a Hardware Abstraction Layer (HAL), and a freestanding C++ runtime environment without reliance on standard libraries.

## 🚀 Key Features

### 🧠 The Kernel (C++ & Assembly)
* **Freestanding C++14:** Implemented a custom C++ runtime (CRT) with no dependencies on `libstdc++` or `libc`.
* **Hardware Abstraction Layer (HAL):** Modular design separating hardware logic from kernel policy.
* **Interrupt Handling:** Full **IDT** (Interrupt Descriptor Table) setup with ISR stubs in Assembly to handle CPU exceptions and hardware triggers.
* **Concurrency Prep:** Remapped the **8259 PIC** (Programmable Interrupt Controller) to manage IRQs (Keyboard, Timer) without conflicting with CPU exceptions.
* **Polymorphic Drivers:** Object-oriented device driver architecture allowing hot-swappable I/O interfaces (VGA vs. Serial).

### 💾 The Bootloader (16-bit Assembly)
* **Custom 2-Stage Design:**
    * **Stage 1 (MBR):** fits in 512 bytes, parses FAT12 headers, and loads Stage 2 via BIOS `int 13h`.
    * **Stage 2:** Enables the **A20 Line**, loads the GDT, and performs the transition from **Real Mode (16-bit)** to **Protected Mode (32-bit)**.
* **ELF Parsing:** Manually parses ELF program headers to load kernel segments into higher-half memory (`0x100000`).
* **"Thunking" Mechanism:** Implements a context-switching mechanism to temporarily drop back to Real Mode for disk I/O operations before native drivers are loaded.

### 📂 File System & I/O
* **Virtual File System (VFS):** Abstract layer for handling file operations (`fopen`, `fread`).
* **FAT12/16/32 Driver:** Read-only implementation of the FAT file system.
* **VGA Text Mode:** Direct memory mapped I/O driver (`0xB8000`).
* **Debug Logging:** Serial port driver targeting the QEMU `0xE9` debug port for host-side logging.

---

## 🛠️ Architecture & Memory Map

The OS follows a strict boot sequence to ensure system stability:

1.  **BIOS** loads Stage 1 to `0x7C00`.
2.  **Stage 1** finds and loads Stage 2 to `0x0500`.
3.  **Stage 2** enables A20, sets up GDT, enters Protected Mode, and loads the Kernel.
4.  **Kernel** is loaded to `0x100000` (1MB mark) to avoid overwriting BIOS/VGA memory.

| Memory Address | Component | Description |
| :--- | :--- | :--- |
| `0x00000000` | IVT / BIOS Data | Reserved by hardware |
| `0x00000500` | **Stage 2** | Extended Bootloader |
| `0x00007C00` | **Stage 1** | MBR Boot Sector |
| `0x000B8000` | **Video Memory** | VGA Text Buffer |
| `0x00100000` | **Kernel Code** | Entry point (`_start`) |
    // Compiles down to direct memory writes or OUT assembly instructions
    m_dev->Write(&c, 1); 
}
