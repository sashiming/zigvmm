const main = @import("main.zig");
const kvm = @import("kvm.zig");

const MEMORY_SIZE: usize = main.MEMORY_SIZE;
const PML4_START: usize = 0x1000;
const PDPT_START: usize = 0x2000;
const PD_START: usize = 0x3000;
const PT_START: usize = 0x4000;
const GDT_START: usize = 0x8000;
const IDT_START: usize = 0x9000;
const START_ADDR: usize = main.START_ADDR;

const PT_SIZE: usize = MEMORY_SIZE / 0x1000;
// page table entry flags
const PTE_PRESENT: usize = 1 << 0;
const PTE_WRITABLE: usize = 1 << 1;
const PTE_USER: usize = 1 << 2;

// control register flags
const CR0_PE: usize = 1 << 0; // Protection Enable
const CR0_PG: usize = 1 << 31; // Paging Enable
const CR4_PAE: usize = 1 << 5; // Physical Address Extension
const EFER_LME: usize = 1 << 8; // Long Mode Enable
const EFER_LMA: usize = 1 << 10; // Long Mode Active

fn setup_pagetable(vm_memory: []u8) void {
    const pml4: *[512]usize = @ptrCast(@alignCast(vm_memory[PML4_START..].ptr));
    const pdpt: *[512]usize = @ptrCast(@alignCast(vm_memory[PDPT_START..].ptr));
    const pd: *[512]usize = @ptrCast(@alignCast(vm_memory[PD_START..].ptr));
    const pt: *[PT_SIZE]usize = @ptrCast(@alignCast(vm_memory[PT_START..].ptr));
    // PML4[0] -> PDPT
    pml4[0] = PDPT_START | PTE_PRESENT | PTE_WRITABLE;
    // PDPT[0] -> PD
    pdpt[0] = PD_START | PTE_PRESENT | PTE_WRITABLE;
    // PD[0] -> PT
    pd[0] = PT_START | PTE_PRESENT | PTE_WRITABLE;
    // PT[0] -> GPT 0x10000 - 0x11000 ...
    pt[0] = START_ADDR | PTE_PRESENT | PTE_WRITABLE;
    pt[1] = (START_ADDR + 0x1000) | PTE_PRESENT | PTE_WRITABLE;
    pt[2] = (START_ADDR + 0x2000) | PTE_PRESENT | PTE_WRITABLE;
    pt[3] = (START_ADDR + 0x3000) | PTE_PRESENT | PTE_WRITABLE;
}

fn setup_segments(sregs: *kvm.KvmSregs) void {
    // GDT
    // 実際のCPUではbit fieldで扱うが, KVMでは構造体で定義されているため, それに合わせる
    // const gdt: *[3]kvm.KvmSegment = @ptrCast(@alignCast(vm_memory[GDT_START..].ptr));
    // 0: null
    // const gdt0 = kvm.KvmSegment.new();
    // 1: code segment
    const gdt1: kvm.KvmSegment = .{
        .base = 0, // unused in 64-bit mode
        .limit = 0, // unused in 64-bit mode
        .selector = 0x08, // offset 1 in GDT
        .type = 0b1010, // code segment, execute + read
        .present = 1,
        .dpl = 0, // ring 0
        .db = 0, // in 64-bit mode, this bit must be 0
        .s = 1, // code/data segment
        .l = 1, // 64-bit code segment
        .g = 0, // limit is ignored in 64-bit mode
        .avl = 0,
        .unusable = 0,
        .padding = 0,
    };
    // 2: data segment
    const gdt2: kvm.KvmSegment = .{
        .base = 0, // unused in 64-bit mode
        .limit = 0, // unused in 64-bit mode
        .selector = 0x10, // offset 2 in GDT
        .type = 0b0010, // data segment, read + write
        .present = 1,
        .dpl = 0, // ring 0
        .db = 0, // in 64-bit mode, this bit must be 0
        .s = 1, // code/data segment
        .l = 1, // 64-bit code segment
        .g = 0, // limit is ignored in 64-bit mode
        .avl = 0,
        .unusable = 0,
        .padding = 0,
    };

    // sregs
    sregs.gdt.base = GDT_START;
    sregs.gdt.limit = @sizeOf(kvm.KvmSegment) * 3 - 1;
    sregs.cs = gdt1;
    sregs.ds = gdt2;
    sregs.ss = gdt2;
    sregs.es = gdt2;
    sregs.fs = gdt2;
    sregs.gs = gdt2;
}

pub fn setup_longmode(vm_memory: []u8, sregs: *kvm.KvmSregs) void {
    setup_pagetable(vm_memory);
    setup_segments(sregs);
    sregs.cr3 = PML4_START; // set CR3 to the base address of PML4
    sregs.cr0 = CR0_PE | CR0_PG;
    sregs.cr4 = CR4_PAE;
    sregs.efer = EFER_LME | EFER_LMA;
}
