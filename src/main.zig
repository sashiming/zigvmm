const std = @import("std");
const linux = std.os.linux;
const kvm = @import("kvm.zig");
const longmode = @import("longmode.zig");
const guestcodes = @import("guestcodes.zig");
const allocator = std.heap.page_allocator;

pub const MEMORY_SIZE: usize = 0x400000; // 4 MiB
pub const START_ADDR: usize = 0x10000; // guest code will be loaded at this GPA

pub const guest_code = guestcodes.hello_kvm;

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

    // copy guest code to VM memory
    @memcpy(vm_memory[START_ADDR .. START_ADDR + guest_code.len], &guest_code);

    // ioctl(kvm_fd, KVM_SET_USER_MEMORY_REGION, &region)
    const region = kvm.KvmUserspaceMemoryRegion{
        .slot = 0,
        .flags = 0,
        .guest_phys_addr = 0x0,
        .memory_size = MEMORY_SIZE,
        .userspace_addr = @intFromPtr(vm_memory.ptr),
    };
    try kvm.control.set_user_memory_region(vm_fd, &region);

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
    longmode.setup_longmode(vm_memory, &sregs);
    try kvm.control.set_sregs(vcpu_fd, &sregs);

    // initialize regs
    var regs = kvm.KvmRegs.new();
    regs.rip = 0x0; // entry point (GVA)
    regs.rflags = 0x2; // reserved bit must be 1
    try kvm.control.set_regs(vcpu_fd, &regs);

    // run the VM
    while (true) {
        try kvm.control.kvm_run(vcpu_fd);
        switch (vcpu_run.exit_reason) {
            kvm.KVM_EXIT_HLT => {
                std.debug.print("\nGuest halted\n", .{});
                break;
            },
            kvm.KVM_EXIT_IO => {
                if (vcpu_run.exit.io.port == 0x01 and vcpu_run.exit.io.direction == kvm.KVM_EXIT_IO_OUT) {
                    // data_offset は kvm_run 先頭からのバイトオフセット
                    const base: [*]const u8 = @ptrCast(vcpu_run);
                    const offset: usize = @intCast(vcpu_run.exit.io.data_offset);
                    std.debug.print("{c}", .{base[offset]});
                } else if (vcpu_run.exit.io.port == 0x3f8 and vcpu_run.exit.io.direction == kvm.KVM_EXIT_IO_OUT) {
                    // UART COM1 THR (Transmitter Holding Register)
                    const base: [*]const u8 = @ptrCast(vcpu_run);
                    const offset: usize = @intCast(vcpu_run.exit.io.data_offset);
                    std.debug.print("{c}", .{base[offset]});
                } else if (vcpu_run.exit.io.port == 0x3fd and vcpu_run.exit.io.direction == kvm.KVM_EXIT_IO_IN) {
                    // UART COM1 LSR (Line Status Register)
                    const base: [*]u8 = @ptrCast(vcpu_run);
                    const offset: usize = @intCast(vcpu_run.exit.io.data_offset);
                    base[offset] = 0x20; // THR empty
                } else {
                    std.debug.print("Unexpected I/O port: {x}\n", .{vcpu_run.exit.io.port});
                }
            },
            else => {
                std.debug.print("Unexpected exit reason: {d}\n", .{vcpu_run.exit_reason});
                std.debug.print("Hardware exit reason: {d}\n", .{vcpu_run.exit.hw.hardware_exit_reason});
                break;
            },
        }
    }
}
