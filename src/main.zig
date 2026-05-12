const std = @import("std");
const linux = std.os.linux;
const kvm = @import("kvm.zig");
const longmode = @import("longmode.zig");
const protectedmode = @import("protectedmode.zig");
const guestcodes = @import("guestcodes.zig");
const elf_loader = @import("elf_loader.zig");
const bda = @import("bda.zig");
const allocator = std.heap.page_allocator;

pub const MEMORY_SIZE: usize = 0x10000000; // 256 MiB
pub const START_ADDR: usize = 0x10000; // guest code will be loaded at this GPA

pub const guest_code = guestcodes.protectedmode;

pub fn main() !void {
    // open("/dev/kvm", O_RDWR)
    const kvm_fd = try kvm.control.open_kvm();
    defer _ = linux.close(kvm_fd);

    // ioctl(kvm_fd, KVM_GET_API_VERSION, 0)
    const api_version = try kvm.control.get_api_version(kvm_fd);
    std.debug.print("KVM API Version: {d}\n", .{api_version});

    // ioctl(kvm_fd, KVM_CREATE_VM, 0)
    const vm_fd = try kvm.control.create_vm(kvm_fd);

    // allocate memory for VM
    const vm_memory = try allocator.alloc(u8, MEMORY_SIZE);
    defer allocator.free(vm_memory);
    @memset(vm_memory, 0);

    // load kernel code to VM memory
    const entrypoint = try elf_loader.load_elf_file("xv6_kernel", vm_memory);

    // initialize BDA and MP tables
    bda.init_bda(vm_memory);

    // copy guest code to VM memory
    // @memcpy(vm_memory[START_ADDR .. START_ADDR + guest_code.len], &guest_code);

    // set the terminal to raw mode to handle UART input properly
    const stdin_fd = linux.STDIN_FILENO;
    const old_termios = try std.posix.tcgetattr(stdin_fd);
    var new_termios = old_termios;
    new_termios.lflag.ICANON = false;
    new_termios.lflag.ECHO = false;
    try std.posix.tcsetattr(stdin_fd, std.posix.TCSA.NOW, new_termios);
    defer std.posix.tcsetattr(stdin_fd, std.posix.TCSA.NOW, old_termios) catch {};

    _ = try std.Thread.spawn(.{}, kvm.io.stdin_reader, .{vm_fd});

    // ioctl(kvm_fd, KVM_SET_USER_MEMORY_REGION, &region)
    const region = kvm.KvmUserspaceMemoryRegion{
        .slot = 0,
        .flags = 0,
        .guest_phys_addr = 0x0,
        .memory_size = MEMORY_SIZE,
        .userspace_addr = @intFromPtr(vm_memory.ptr),
    };
    try kvm.control.set_user_memory_region(vm_fd, &region);

    try kvm.control.create_irqchip(vm_fd);
    const pit_config: kvm.KvmPitConfig = .{ .flags = 0, .padding = [_]u32{0} ** 15 };
    try kvm.control.create_pit2(vm_fd, &pit_config);

    // create VCPU
    const vcpu_fd = try kvm.control.create_vcpu(vm_fd);
    const vcpu_mmap_size = try kvm.control.get_vcpu_mmap_size(kvm_fd);

    // mmap the kvm_run shared memory from vcpu_fd
    const vcpu_run_mem = try std.posix.mmap(
        null,
        vcpu_mmap_size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        vcpu_fd,
        0,
    );
    defer std.posix.munmap(vcpu_run_mem);
    const vcpu_run: *kvm.KvmRun = @ptrCast(@alignCast(vcpu_run_mem.ptr));

    // initialize sregs
    var sregs = kvm.KvmSregs.new();
    try kvm.control.get_sregs(vcpu_fd, &sregs);
    // setup page tables, segments and control registers for long mode
    // longmode.setup_longmode(vm_memory, &sregs);
    protectedmode.setup_protectedmode(vm_memory, &sregs);
    try kvm.control.set_sregs(vcpu_fd, &sregs);

    // initialize regs
    var regs = kvm.KvmRegs.new();
    // regs.rip = 0x0; // entry point
    regs.rip = entrypoint; // entry point
    regs.rflags = 0x2; // reserved bit must be 1
    try kvm.control.set_regs(vcpu_fd, &regs);

    try kvm.io.fs_init("xv6_fs.img");
    defer kvm.io.fs_close();

    // run the VM
    while (true) {
        try kvm.control.kvm_run(vcpu_fd);
        switch (vcpu_run.exit_reason) {
            kvm.KVM_EXIT_HLT => {
                std.debug.print("\nGuest halted\n", .{});
                break;
            },
            kvm.KVM_EXIT_IO => {
                kvm.io.handle_pio(vm_fd, &vcpu_run.exit.io, @ptrCast(vcpu_run)) catch |err| {
                    std.debug.print("Error handling I/O exit: {}\n", .{err});
                    std.debug.print("Unexpected I/O port: 0x{x}\n", .{vcpu_run.exit.io.port});
                    try kvm.control.get_regs(vcpu_fd, &regs);
                    std.debug.print("EIP: 0x{x}\n", .{regs.rip});
                    break;
                };
            },
            else => {
                std.debug.print("Unexpected exit reason: {d}\n", .{vcpu_run.exit_reason});
                std.debug.print("Hardware exit reason: 0x{x}\n", .{vcpu_run.exit.hw.hardware_exit_reason});
                try kvm.control.get_regs(vcpu_fd, &regs);
                std.debug.print("EIP: 0x{x}\n", .{regs.rip});
                break;
            },
        }
    }
}
