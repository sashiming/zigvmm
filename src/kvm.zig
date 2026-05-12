const std = @import("std");
const linux = std.os.linux;

const kvm_fd_t = linux.fd_t;
const vm_fd_t = linux.fd_t;
const vcpu_fd_t = linux.fd_t;

pub const KvmUserspaceMemoryRegion = extern struct {
    slot: u32,
    flags: u32,
    guest_phys_addr: u64,
    memory_size: u64,
    userspace_addr: u64,
};

pub const KvmExitIO = extern struct {
    direction: u8,
    size: u8,
    port: u16,
    count: u32,
    data_offset: u64, // kvm_run 先頭からのオフセット
};

pub const KvmRun = extern struct {
    request_interrupt_window: u8,
    immediate_exit: u8,
    _pad1: [6]u8,
    exit_reason: u32, // KVM_EXIT_*
    ready_for_interrupt_injection: u8,
    if_flag: u8,
    flags: u16,
    cr8: u64,
    apic_base: u64,
    exit: extern union {
        hw: extern struct {
            hardware_exit_reason: u64,
        },
        /// KVM_EXIT_IO
        io: KvmExitIO,
        /// union サイズを 256 bytes に固定 (C の char padding[256] に対応)
        _padding: [256]u8,
    },
    kvm_valid_regs: u64,
    kvm_dirty_regs: u64,
    s: extern union {
        _padding: [2048]u8,
    },

    comptime {
        std.debug.assert(@offsetOf(KvmRun, "exit_reason") == 8);
        std.debug.assert(@offsetOf(KvmRun, "exit") == 32);
        std.debug.assert(@sizeOf(@TypeOf(@as(KvmRun, undefined).exit)) == 256);
        std.debug.assert(@offsetOf(KvmRun, "kvm_valid_regs") == 288);
    }
};

// exit reasons
pub const KVM_EXIT_UNKNOWN: u32 = 0;
pub const KVM_EXIT_EXCEPTION: u32 = 1;
pub const KVM_EXIT_IO: u32 = 2;
pub const KVM_EXIT_HLT: u32 = 5;
pub const KVM_EXIT_MMIO: u32 = 6;
// io directions
pub const KVM_EXIT_IO_IN: u8 = 0;
pub const KVM_EXIT_IO_OUT: u8 = 1;

pub const KvmPitConfig = extern struct {
    flags: u32,
    padding: [15]u32,
};

pub const KvmSegment = extern struct {
    base: u64,
    limit: u32,
    selector: u16,
    type: u8,
    present: u8,
    dpl: u8,
    db: u8,
    s: u8,
    l: u8,
    g: u8,
    avl: u8,
    unusable: u8,
    padding: u8,

    pub fn new() @This() {
        return .{
            .base = 0,
            .limit = 0,
            .selector = 0,
            .type = 0,
            .present = 0,
            .dpl = 0,
            .db = 0,
            .s = 0,
            .l = 0,
            .g = 0,
            .avl = 0,
            .unusable = 0,
            .padding = 0,
        };
    }
};

pub const KvmDtable = extern struct {
    base: u64,
    limit: u16,
    padding: [3]u16,

    pub fn new() @This() {
        return .{
            .base = 0,
            .limit = 0,
            .padding = [_]u16{0} ** 3,
        };
    }
};

pub const KvmSregs = extern struct {
    cs: KvmSegment,
    ds: KvmSegment,
    es: KvmSegment,
    fs: KvmSegment,
    gs: KvmSegment,
    ss: KvmSegment,
    tr: KvmSegment,
    ldt: KvmSegment,
    gdt: KvmDtable,
    idt: KvmDtable,
    cr0: u64,
    cr2: u64,
    cr3: u64,
    cr4: u64,
    cr8: u64,
    efer: u64,
    apic_base: u64,
    interrupt_bitmap: [4]u64, // ((256 + 63) / 64) = 4  (KVM_NR_INTERRUPTS = 256)

    pub fn new() @This() {
        return .{
            .cs = KvmSegment.new(),
            .ds = KvmSegment.new(),
            .es = KvmSegment.new(),
            .fs = KvmSegment.new(),
            .gs = KvmSegment.new(),
            .ss = KvmSegment.new(),
            .tr = KvmSegment.new(),
            .ldt = KvmSegment.new(),
            .gdt = KvmDtable.new(),
            .idt = KvmDtable.new(),
            .cr0 = 0,
            .cr2 = 0,
            .cr3 = 0,
            .cr4 = 0,
            .cr8 = 0,
            .efer = 0,
            .apic_base = 0,
            .interrupt_bitmap = [_]u64{0} ** 4,
        };
    }
};

pub const KvmRegs = extern struct {
    rax: u64,
    rbx: u64,
    rcx: u64,
    rdx: u64,
    rsi: u64,
    rdi: u64,
    rsp: u64,
    rbp: u64,
    r8: u64,
    r9: u64,
    r10: u64,
    r11: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
    rip: u64,
    rflags: u64,

    pub fn new() @This() {
        return .{
            .rax = 0,
            .rbx = 0,
            .rcx = 0,
            .rdx = 0,
            .rsi = 0,
            .rdi = 0,
            .rsp = 0,
            .rbp = 0,
            .r8 = 0,
            .r9 = 0,
            .r10 = 0,
            .r11 = 0,
            .r12 = 0,
            .r13 = 0,
            .r14 = 0,
            .r15 = 0,
            .rip = 0,
            .rflags = 0,
        };
    }
};

pub const KvmIRQLevel = extern struct {
    irq: extern union {
        irq: u32,
        status: i32,
    },
    level: u32,
};

const KVMIO: u8 = 0xae;
pub const KVM_GET_API_VERSION: u32 = linux.IOCTL.IO(KVMIO, 0x00);
pub const KVM_CREATE_VM: u32 = linux.IOCTL.IO(KVMIO, 0x01);
pub const KVM_GET_VCPU_MMAP_SIZE: u32 = linux.IOCTL.IO(KVMIO, 0x04);
pub const KVM_CREATE_VCPU: u32 = linux.IOCTL.IO(KVMIO, 0x41);
pub const KVM_SET_USER_MEMORY_REGION: u32 = linux.IOCTL.IOW(KVMIO, 0x46, KvmUserspaceMemoryRegion);
pub const KVM_CREATE_IRQCHIP: u32 = linux.IOCTL.IO(KVMIO, 0x60);
pub const KVM_IRQ_LINE: u32 = linux.IOCTL.IOW(KVMIO, 0x61, KvmIRQLevel);
pub const KVM_CREATE_PIT2: u32 = linux.IOCTL.IOW(KVMIO, 0x77, KvmPitConfig);
pub const KVM_RUN: u32 = linux.IOCTL.IO(KVMIO, 0x80);
pub const KVM_GET_REGS: u32 = linux.IOCTL.IOR(KVMIO, 0x81, KvmRegs);
pub const KVM_SET_REGS: u32 = linux.IOCTL.IOW(KVMIO, 0x82, KvmRegs);
pub const KVM_GET_SREGS: u32 = linux.IOCTL.IOR(KVMIO, 0x83, KvmSregs);
pub const KVM_SET_SREGS: u32 = linux.IOCTL.IOW(KVMIO, 0x84, KvmSregs);

const FileError = error{FileOpenFailed};
const IoctlError = error{ GetAPIVersion, CreateVM, SetUserMemoryRegion, CreateIRQChip, IRQLine, CreatePIT2, CreateVcpu, GetVcpuMmapSize, GetSregs, SetSregs, GetRegs, SetRegs, KvmRun };

fn open(path: [*:0]const u8, flags: linux.O, perm: linux.mode_t) isize {
    const fd = linux.open(path, flags, perm);
    return @bitCast(fd);
}

fn ioctl(fd: linux.fd_t, request: u32, arg: usize) isize {
    const ret = linux.ioctl(fd, request, arg);
    return @bitCast(ret);
}

pub const control = struct {
    /// open /dev/kvm and return fd
    pub fn open_kvm() !kvm_fd_t {
        const fd = open("/dev/kvm", .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0);
        if (fd < 0) {
            return FileError.FileOpenFailed;
        }
        return @intCast(fd);
    }

    pub fn get_api_version(fd: kvm_fd_t) !usize {
        const version = ioctl(fd, KVM_GET_API_VERSION, 0);
        if (version < 0) {
            return IoctlError.GetAPIVersion;
        }
        return @intCast(version);
    }

    pub fn create_vm(fd: kvm_fd_t) !vm_fd_t {
        const vm_fd = ioctl(fd, KVM_CREATE_VM, 0);
        if (vm_fd < 0) {
            return IoctlError.CreateVM;
        }
        return @intCast(vm_fd);
    }

    pub fn set_user_memory_region(fd: vm_fd_t, region: *const KvmUserspaceMemoryRegion) !void {
        const ret = ioctl(fd, KVM_SET_USER_MEMORY_REGION, @intFromPtr(region));
        if (ret < 0) {
            return IoctlError.SetUserMemoryRegion;
        }
    }

    pub fn create_irqchip(fd: vm_fd_t) !void {
        const ret = ioctl(fd, KVM_CREATE_IRQCHIP, 0);
        if (ret < 0) {
            return IoctlError.CreateIRQChip;
        }
    }

    pub fn irq_line(fd: vm_fd_t, irqnum: u32, level: u32) !void {
        const irq_level: KvmIRQLevel = .{
            .irq = .{ .irq = irqnum },
            .level = level,
        };
        const ret = ioctl(fd, KVM_IRQ_LINE, @intFromPtr(&irq_level));
        if (ret < 0) {
            return IoctlError.IRQLine;
        }
    }

    pub fn create_pit2(fd: vm_fd_t, config: *const KvmPitConfig) !void {
        const ret = ioctl(fd, KVM_CREATE_PIT2, @intFromPtr(config));
        if (ret < 0) {
            return IoctlError.CreatePIT2;
        }
    }

    pub fn create_vcpu(fd: vm_fd_t) !vcpu_fd_t {
        const vcpu_fd = ioctl(fd, KVM_CREATE_VCPU, 0);
        if (vcpu_fd < 0) {
            return IoctlError.CreateVcpu;
        }
        return @intCast(vcpu_fd);
    }

    pub fn get_vcpu_mmap_size(fd: kvm_fd_t) !usize {
        const size = ioctl(fd, KVM_GET_VCPU_MMAP_SIZE, 0);
        if (size < 0) {
            return IoctlError.GetVcpuMmapSize;
        }
        return @intCast(size);
    }

    pub fn get_sregs(fd: vcpu_fd_t, sregs: *KvmSregs) !void {
        const ret = ioctl(fd, KVM_GET_SREGS, @intFromPtr(sregs));
        if (ret < 0) {
            return IoctlError.GetSregs;
        }
    }

    pub fn set_sregs(fd: vcpu_fd_t, sregs: *const KvmSregs) !void {
        const ret = ioctl(fd, KVM_SET_SREGS, @intFromPtr(sregs));
        if (ret < 0) {
            return IoctlError.SetSregs;
        }
    }

    pub fn get_regs(fd: vcpu_fd_t, regs: *KvmRegs) !void {
        const ret = ioctl(fd, KVM_GET_REGS, @intFromPtr(regs));
        if (ret < 0) {
            return IoctlError.GetRegs;
        }
    }

    pub fn set_regs(fd: vcpu_fd_t, regs: *const KvmRegs) !void {
        const ret = ioctl(fd, KVM_SET_REGS, @intFromPtr(regs));
        if (ret < 0) {
            return IoctlError.SetRegs;
        }
    }

    pub fn kvm_run(fd: vcpu_fd_t) !void {
        const ret = ioctl(fd, KVM_RUN, 0);
        if (ret < 0) {
            return IoctlError.KvmRun;
        }
    }
};

const IDE_STATUS_BSY: u8 = 0x80;
const IDE_STATUS_DRDY: u8 = 0x40;
const IDE_STATUS_DF: u8 = 0x20;
const IDE_STATUS_DSC: u8 = 0x10;    // Seek Complete
const IDE_STATUS_DRQ: u8 = 0x08;    // Data Request
const IDE_STATUS_CORR: u8 = 0x04;
const IDE_STATUS_IDX: u8 = 0x02;
const IDE_STATUS_ERR: u8 = 0x01;

pub const io = struct {
    var fs_file: ?std.fs.File = null;
    var ide_sector_buffer: [512]u8 = undefined;
    var ide_sector_buffer_offset: usize = 0;
    var ide_sector_number: usize = 0;
    var ide_status: u8 = IDE_STATUS_DRDY;
    var ide_lba: u32 = 0;

    fn pulse_irq(fd: vm_fd_t, irqnum: u32) !void {
        try control.irq_line(fd, irqnum, 1);
        try control.irq_line(fd, irqnum, 0);
    }

    pub fn fs_init(path: []const u8) !void {
        fs_file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
    }

    pub fn fs_close() void {
        if (fs_file) |file| {
            file.close();
        }
    }

    fn fs_read_sector(vm_fd: vm_fd_t) !void {
        if (fs_file == null) return error.IDENoDisk;
        var read_buf: [4096]u8 = undefined;
        const offset = @as(u64, ide_lba) * 512;
        var fr = fs_file.?.reader(&read_buf);
        try fr.seekTo(offset);
        var reader = &fr.interface;
        try reader.readSliceAll(ide_sector_buffer[0..512]);
        ide_sector_buffer_offset = 0;
        ide_status = IDE_STATUS_DRDY | IDE_STATUS_DSC | IDE_STATUS_DRQ;
        // activate IRQ 14
        try pulse_irq(vm_fd, 14);
    }

    fn fs_write_sector(vm_fd: vm_fd_t) !void {
        if (fs_file == null) return error.IDENoDisk;
        var write_buf: [4096]u8 = undefined;
        const offset = @as(u64, ide_lba) * 512;
        var fw = fs_file.?.writer(&write_buf);
        try fw.seekTo(offset);
        var writer = &fw.interface;
        try writer.writeAll(ide_sector_buffer[0..512]);
        try writer.flush();
        ide_status = IDE_STATUS_DRDY | IDE_STATUS_DSC;
        // activate IRQ 14
        try pulse_irq(vm_fd, 14);
    }

    pub fn handle_pio_exit(vm_fd: vm_fd_t, exitio: *KvmExitIO, data_base: [*]u8) !void {
        const ioport = exitio.port;
        const iodir = exitio.direction;
        const iosize = exitio.size;
        const iocount = exitio.count;
        const data_offset = exitio.data_offset;
        if (ioport >= 0x3f8 and ioport <= 0x3ff) {
            // COM1 UART
            if (ioport == 0x3f8 and iodir == KVM_EXIT_IO_OUT) {
                // THR (Transmitter Holding Register)
                std.debug.print("{c}", .{data_base[data_offset]});
            } else if (ioport == 0x3fd and iodir == KVM_EXIT_IO_IN) {
                // LSR (Line Status Register)
                data_base[data_offset] = 0x20; // THR empty
            }
        } else if (ioport >= 0x3d4 and ioport <= 0x3d5) {
            // VGA
            if (iodir == KVM_EXIT_IO_IN) {
                data_base[data_offset] = 0; // dummy data
            }
        } else if ((ioport >= 0x1f0 and ioport <= 0x1f7) or ioport == 0x3f6) {
            // IDE
            switch (ioport) {
                0x1f0 => {
                    // Data Register (r/w)
                    const total: usize = @as(usize, iocount) * @as(usize, iosize);
                    if (iodir == KVM_EXIT_IO_IN) {
                        // read
                        for (0..total) |i| {
                            data_base[data_offset + i] = ide_sector_buffer[ide_sector_buffer_offset];
                            ide_sector_buffer_offset += 1;
                            if (ide_sector_buffer_offset >= 512) {
                                ide_sector_buffer_offset = 0;
                                ide_status &= ~IDE_STATUS_DRQ; // clear DRQ
                                break;
                            }
                        }
                    } else {
                        // write
                        for (0..total) |i| {
                            ide_sector_buffer[ide_sector_buffer_offset] = data_base[data_offset + i];
                            ide_sector_buffer_offset += 1;
                            if (ide_sector_buffer_offset >= 512) {
                                ide_sector_buffer_offset = 0;
                                ide_status &= ~IDE_STATUS_DRQ; // clear DRQ
                                try fs_write_sector(vm_fd);    // write sector to disk and activate IRQ 14
                                break;
                            }
                        }
                    }
                },
                0x1f1 => {
                    // Error Register (r) / Features Register (w)
                    if (iodir == KVM_EXIT_IO_IN) {
                        data_base[data_offset] = 0; // no error
                    } else {
                        // ignore features
                    }
                },
                0x1f2 => {
                    // Sector Count Register (r/w)
                    if (iodir == KVM_EXIT_IO_IN) {
                        data_base[data_offset] = @intCast(ide_sector_number);
                    } else {
                        ide_sector_number = @intCast(data_base[data_offset]);
                    }
                },
                0x1f3 => {
                    // LBA Low (r/w)
                    if (iodir == KVM_EXIT_IO_IN) {
                        data_base[data_offset] = @truncate(ide_lba);
                    } else {
                        ide_lba &= 0xffffff00;
                        ide_lba |= @as(u32, data_base[data_offset]);
                    }
                },
                0x1f4 => {
                    // LBA Mid (r/w)
                    if (iodir == KVM_EXIT_IO_IN) {
                        data_base[data_offset] = @truncate(ide_lba >> 8);
                    } else {
                        ide_lba &= 0xffff00ff;
                        ide_lba |= @as(u32, data_base[data_offset]) << 8;
                    }
                },
                0x1f5 => {
                    // LBA High (r/w)
                    if (iodir == KVM_EXIT_IO_IN) {
                        data_base[data_offset] = @truncate(ide_lba >> 16);
                    } else {
                        ide_lba &= 0xff00ffff;
                        ide_lba |= @as(u32, data_base[data_offset]) << 16;
                    }
                },
                0x1f6 => {
                    // Drive/Head Register (r/w)
                    if (iodir == KVM_EXIT_IO_IN) {
                        data_base[data_offset] = 0; // master drive, LBA mode
                    } else {
                        const val: u8 = data_base[data_offset];
                        if ((val >> 6) & 1 != 0) {  // LBA mode
                            ide_lba &= 0x00ffffff;
                            ide_lba |= @as(u32, val & 0xf) << 24;
                        } else {
                            // CHS mode
                            return error.IDEUnsupportedCHSMode;
                        }
                    }
                },
                0x1f7 => {
                    // Status Register (r) / Command Register (w)
                    if (iodir == KVM_EXIT_IO_IN) {
                        data_base[data_offset] = ide_status;
                    } else {
                        const cmd: u8 = data_base[data_offset];
                        if (cmd == 0x20) { // READ SECTORS
                            try fs_read_sector(vm_fd);
                        } else if (cmd == 0x30) { // WRITE SECTORS
                            ide_sector_buffer_offset = 0;
                            ide_status = IDE_STATUS_DRDY | IDE_STATUS_DSC | IDE_STATUS_DRQ;
                        } else {
                            return error.IDEUnsupportedCommand;
                        }
                    }
                },
                0x3f6 => {
                    // Alt Status Register (r) / Device Control Register (w)
                    if (iodir == KVM_EXIT_IO_IN) {
                        data_base[data_offset] = 0; // no write-protect
                    } else {
                        // ignore device control writes
                    }
                },
                else => {
                    return error.IDEUnexpectedIoPort;
                },
            }
        } else {
            return error.UnexpectedIoPort;
        }
    }
};
