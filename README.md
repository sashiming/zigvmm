# zigvmm: A toy KVM-based hypervisor written in Zig

This is an experimental project to learn about KVM and virtualization. It lacks many production-ready features and is not intended for practical use.

It interacts with the KVM API directly to construct a virtual machine and boot [xv6](https://github.com/mit-pdos/xv6-public) on it.

## Prerequisites

- **OS**: Linux with KVM support
- **CPU**: x86_64 machine with hardware virtualization support (Intel VT-x or AMD-V)
- **Toolchain**: Zig 0.15.2

## How to run

```sh
zig build run
```
