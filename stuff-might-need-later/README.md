# Parked

    toolchain.nix   nixpkgs 02c087f3 for clang/lld 23.1.3 (pmOS's version), zstd overlay

The kernel in ../kernel is built with nixpkgs linuxManualConfig, the pin's clang and a
non-strict config (pmOS's config + `make oldconfig`). toolchain.nix is for
building it with pmOS's exact compiler and an unmodified config again.

## Where it stopped

With strict config mode (`make oldconfig` must not change the pmOS config, on
the 7.2.9 source):

- clang 22 (Mobile NixOS' pin): 4 compiler-dependent lines differ.
- clang 23.1.3 from toolchain.nix: only `# CONFIG_DEBUG_INFO_COMPRESSED_ZSTD is not set`
  goes away. That option needs `-gz=zstd` / `--compress-debug-sections=zstd`,
  and nixpkgs builds LLVM without zstd.
- The zstd overlay in toolchain.nix builds libllvm, but clang and lld then fail at
  CMake: LLVM's exported config wants `find_package(zstd)`, so they need `zstd`
  in their buildInputs too (override clang/lld in the same overrideScope).

## Using it

In devices/motorola-dubai/default.nix, import it with the kernel's
localSystem/crossSystem and pass `toolchain.llvmPackages_23` to ../kernel in
place of the pin's `llvmPackages` (kernel/default.nix takes the stdenv and the
LLVM tools from it). linuxManualConfig has no strict config check; compare the
built .config (in the kernel's dev output) with ../kernel/config by hand.
