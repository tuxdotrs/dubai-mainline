# Building the pmOS kernel from source (parked)

The image currently uses pmOS's binary kernel package
(devices/motorola-dubai/kernel). This directory has the from-source build
for when it's needed again.

    kernel-from-source/
      default.nix          Mobile NixOS kernel-builder, LLVM=1, unmodified pmOS config
      source.nix           sc7280-mainline/linux tag v7.2.9-sc7280
      config-pmos.aarch64  pmOS config, as in pmaports
      toolchain.nix        nixpkgs 02c087f3 for clang/lld 23.1.3 (pmOS's version), zstd overlay
      device-glue.nix      what devices/motorola-dubai/default.nix had for it

## Where it stopped

With strict config mode (`make oldconfig` must not change the pmOS config):

- clang 22 (Mobile NixOS' pin): 4 compiler-dependent lines differ.
- clang 23.1.3 from toolchain.nix: only `# CONFIG_DEBUG_INFO_COMPRESSED_ZSTD is not set`
  goes away. That option needs `-gz=zstd` / `--compress-debug-sections=zstd`,
  and nixpkgs builds LLVM without zstd.
- The zstd overlay in toolchain.nix builds libllvm, but clang and lld then fail at
  CMake: LLVM's exported config wants `find_package(zstd)`, so they need `zstd`
  in their buildInputs too (override clang/lld in the same overrideScope).

Logs: arcturus:~/Projects/nixos-mobile/logs/kernel-clang23.log

## Re-enabling

1. Copy kernel-from-source/{default,source,toolchain}.nix and config-pmos.aarch64
   to devices/motorola-dubai/kernel/.
2. Put the pieces of device-glue.nix back into devices/motorola-dubai/default.nix.
