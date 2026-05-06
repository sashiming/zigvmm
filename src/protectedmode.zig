const main = @import("main.zig");
const kvm = @import("kvm.zig");

const MEMORY_SIZE: usize = main.MEMORY_SIZE;
const GDT_START: usize = 0x8000;
const IDT_START: usize = 0x9000;
const START_ADDR: usize = main.START_ADDR;

// control register flags
const CR0_PE: usize = 1 << 0; // Protection Enable
const CR4_PAE: usize = 1 << 5; // Physical Address Extension

fn gdt_struct_to_u64(seg: kvm.KvmSegment) u64 {
    return (@as(u64, seg.limit) & 0xffff) |             // limit low  [15:0]
           (@as(u64, seg.base) & 0xffffff) << 16 |      // base low   [39:16]
           (@as(u64, seg.type) & 0xf) << 40 |           // type       [43:40]
           (@as(u64, seg.s) & 0x1) << 44 |              // s          [44]
           (@as(u64, seg.dpl) & 0x3) << 45 |            // dpl        [46:45]
           (@as(u64, seg.present) & 0x1) << 47 |        // present    [47]
           (@as(u64, seg.limit) & 0xf0000) << 32 |      // limit high [51:48]
           (@as(u64, seg.avl) & 0x1) << 52 |            // avl        [52]
           (@as(u64, seg.l) & 0x1) << 53 |              // l          [53]
           (@as(u64, seg.db) & 0x1) << 54 |             // db         [54]
           (@as(u64, seg.g) & 0x1) << 55 |              // g          [55]
           (@as(u64, seg.base) & 0xff000000) << 32;     // base high  [63:56]
}

fn setup_segments(vm_memory: []u8, sregs: *kvm.KvmSregs) void {
    // GDT
    const gdt: *[3]u64 = @ptrCast(@alignCast(vm_memory[GDT_START..].ptr));
    // 0: null
    // const gdt0 = kvm.KvmSegment.new();
    // 1: code segment
    const gdt1: kvm.KvmSegment = .{
        .base = 0,
        .limit = 0xffffffff, // flat memory model
        .selector = 0x08, // offset 1 in GDT
        .type = 0b1010, // code segment, execute + read
        .present = 1,
        .dpl = 0, // ring 0
        .db = 1, // 32 bit
        .s = 1, // code/data segment
        .l = 0,
        .g = 1, // 4KiB granularity
        .avl = 0,
        .unusable = 0,
        .padding = 0,
    };
    // 2: data segment
    const gdt2: kvm.KvmSegment = .{
        .base = 0,
        .limit = 0xffffffff, // flat memory model
        .selector = 0x10, // offset 2 in GDT
        .type = 0b0010, // data segment, read + write
        .present = 1,
        .dpl = 0, // ring 0
        .db = 1, // 32 bit
        .s = 1, // code/data segment
        .l = 0,
        .g = 1, // 4KiB granularity
        .avl = 0,
        .unusable = 0,
        .padding = 0,
    };

    // initialize GDT on guest memory
    gdt[0] = 0;
    gdt[1] = gdt_struct_to_u64(gdt1);
    gdt[2] = gdt_struct_to_u64(gdt2);
    // sregs
    sregs.gdt.base = GDT_START;
    sregs.gdt.limit = @sizeOf(u64) * 3 - 1;
    sregs.cs = gdt1;
    sregs.ds = gdt2;
    sregs.ss = gdt2;
    sregs.es = gdt2;
    sregs.fs = gdt2;
    sregs.gs = gdt2;
}

/// Setup protected mode by initializing GDT and setting CR0_PE
pub fn setup_protectedmode(vm_memory: []u8, sregs: *kvm.KvmSregs) void {
    setup_segments(vm_memory, sregs);
    sregs.cr0 |= CR0_PE;
    // sregs.cr4 |= CR4_PAE;
}
