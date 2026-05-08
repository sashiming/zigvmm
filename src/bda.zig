const std = @import("std");

fn write_mp_floating_pointer(mem: []u8, mp_fp_addr: usize, mp_conf_addr: usize) void {
    var p = mem[mp_fp_addr .. mp_fp_addr + 16];
    @memset(p, 0);
    @memcpy(p[0..4], "_MP_");
    std.mem.writeInt(u32, p[4..8], @intCast(mp_conf_addr), .little);
    p[8] = 1;
    p[9] = 1; // MP spec ver 1.1
    p[11] = 0;
    var checksum: u8 = 0;
    for (p) |b| checksum +%= b;
    p[10] = 0 -% checksum;
}

fn write_mp_config_table(mem: []u8, mp_conf_addr: usize) void {
    const header_size = 44;
    const proc_entry_size = 20;
    const ioapic_entry_size = 8;
    const total_size = header_size + proc_entry_size + ioapic_entry_size;
    var p = mem[mp_conf_addr .. mp_conf_addr + total_size];
    @memset(p, 0);

    // header
    @memcpy(p[0..4], "PCMP");
    std.mem.writeInt(u16, p[4..6], total_size, .little); // base table length
    p[6] = 1; // MP spec ver 1.1
    @memcpy(p[8..16], "OEM ID  ");
    @memcpy(p[16..24], "PROD ID ");
    std.mem.writeInt(u16, p[34..36], 2, .little); // entry count
    std.mem.writeInt(u32, p[36..40], 0xfee00000, .little); // local APIC address

    // processor entry
    var pe = p[header_size .. header_size + proc_entry_size];
    pe[0] = 0; // entry type: processor
    pe[1] = 0; // local APIC ID
    pe[2] = 0x14; // local APIC version
    pe[3] = 0x03; // CPU flags: enabled + bootstrap processor

    // I/O APIC entry
    var ioe = p[header_size + proc_entry_size .. header_size + proc_entry_size + ioapic_entry_size];
    ioe[0] = 2; // entry type: I/O APIC
    ioe[1] = 0; // I/O APIC ID
    ioe[2] = 0x11; // I/O APIC version
    ioe[3] = 1; // I/O APIC flags: enabled
    std.mem.writeInt(u32, ioe[4..8], 0xfec00000, .little); // I/O APIC address

    // header: checksum
    var checksum: u8 = 0;
    for (p) |b| checksum +%= b;
    p[7] = 0 -% checksum;
}

pub fn init_bda(mem: []u8) void {
    // BDA[15:14]: EBDA base address >> 4 (0x9fc00)
    mem[0x40e] = 0xc0;
    mem[0x40f] = 0x9f;

    // MP floating pointer structure at 0xf0000
    const mp_fp_addr: usize = 0xf0000;
    const mp_conf_addr: usize = 0xf0010;
    write_mp_floating_pointer(mem, mp_fp_addr, mp_conf_addr);
    write_mp_config_table(mem, mp_conf_addr);
}