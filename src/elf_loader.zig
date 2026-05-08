const std = @import("std");
const elf = std.elf;

pub fn load_elf_file(path: []const u8, dest: []u8) !u64 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(&read_buf);

    const header = try elf.Header.read(&file_reader.interface);

    var phdrs: [16]elf.Elf64_Phdr = undefined;
    var phdr_count: usize = 0;

    var itr = header.iterateProgramHeaders(&file_reader);
    while (try itr.next()) |phdr| {
        if (phdr.p_type != elf.PT_LOAD) continue;
        if (phdr_count >= phdrs.len) return error.TooManyLoadSegments;
        phdrs[phdr_count] = phdr;
        phdr_count += 1;
    }

    // セグメントごとにロード
    for (phdrs[0..phdr_count]) |phdr| {
        const offset: u64 = phdr.p_offset;
        const filesz: usize = @intCast(phdr.p_filesz);
        const memsz: usize = @intCast(phdr.p_memsz);
        const dest_offset: usize = @intCast(phdr.p_paddr);

        if (dest_offset + memsz > dest.len) return error.DestTooSmall;

        try file.seekTo(offset);
        _ = try file.readAll(dest[dest_offset .. dest_offset + filesz]);

        if (memsz > filesz) {
            @memset(dest[dest_offset + filesz .. dest_offset + memsz], 0);
        }
    }

    const entry_pa = header.entry;  // xv6: 0x10000c
    return entry_pa;
}
