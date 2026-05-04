const std = @import("std");
const linux = std.os.linux;
const kvm = @import("kvm.zig");
const allocator = std.heap.page_allocator;

const MEMORY_SIZE: usize = 0x100000; // 1 MiB

// const guest_code = [_]u8{
//     // simple addition and halt
//     0xb8, 0x01, 0x00, 0x00, 0x00, // mov eax, 1
//     0xbb, 0x02, 0x00, 0x00, 0x00, // mov ebx, 2
//     0x01, 0xd8, // add eax, ebx
//     0xf4, // hlt
// };

const guest_code = [_]u8{ 0xb0, 0x48, 0xe6, 0x01, 0xb0, 0x65, 0xe6, 0x01, 0xb0, 0x6c, 0xe6, 0x01, 0xb0, 0x6c, 0xe6, 0x01, 0xb0, 0x6f, 0xe6, 0x01, 0xb0, 0x20, 0xe6, 0x01, 0xb0, 0x4b, 0xe6, 0x01, 0xb0, 0x56, 0xe6, 0x01, 0xb0, 0x4d, 0xe6, 0x01, 0xb0, 0x21, 0xe6, 0x01, 0xf4 };

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

    // copy guest code to VM memory
    @memcpy(vm_memory[0..guest_code.len], &guest_code);

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
    sregs.cs.base = 0;
    sregs.cs.selector = 0;
    try kvm.control.set_sregs(vcpu_fd, &sregs);

    // initialize regs
    var regs = kvm.KvmRegs.new();
    regs.rip = 0x0; // entry point
    regs.rflags = 0x2; // reserved bit must be 1
    try kvm.control.set_regs(vcpu_fd, &regs);

    // run the VM
    var is_running: u8 = 1;
    while (is_running > 0) {
        try kvm.control.kvm_run(vcpu_fd);
        switch (vcpu_run.exit_reason) {
            kvm.KVM_EXIT_HLT => {
                std.debug.print("\nGuest halted\n", .{});
                is_running = 0;
                break;
            },
            kvm.KVM_EXIT_IO => {
                if (vcpu_run.exit.io.port == 0x01 and vcpu_run.exit.io.direction == kvm.KVM_EXIT_IO_OUT) {
                    // data_offset は kvm_run 先頭からのバイトオフセット
                    const base: [*]const u8 = @ptrCast(vcpu_run);
                    const offset: usize = @intCast(vcpu_run.exit.io.data_offset);
                    std.debug.print("{c}", .{base[offset]});
                }
            },
            else => {
                std.debug.print("Unexpected exit reason: {d}\n", .{vcpu_run.exit_reason});
                std.debug.print("Hardware exit reason: {d}\n", .{vcpu_run.exit.hw.hardware_exit_reason});
                is_running = 0;
                break;
            },
        }
    }
}
