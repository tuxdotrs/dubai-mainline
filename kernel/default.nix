# sc7280-mainline/linux (the submodule in ./linux) with nixpkgs' linuxManualConfig,
# built with clang/lld like pmOS builds linux-postmarketos-qcom-sc7280.
# ./config is pmOS's config for that package; `make oldconfig` fills in options
# it doesn't have yet with their defaults.
# Bumping: check out another tag in ./linux and update `version`.
{ lib
, linuxManualConfig
, llvmPackages
, buildPackages
, ...
}:

assert lib.assertMsg (builtins.pathExists ./linux/Makefile)
  "kernel/linux is empty: run `git submodule update --init --depth 1 kernel/linux`";

let
  # e.g. .../bin/aarch64-unknown-linux-gnu-ld.lld when cross-compiling
  llvm = "${buildPackages.llvmPackages.bintools-unwrapped}/bin/${llvmPackages.stdenv.cc.targetPrefix}";
in
(linuxManualConfig {
  version = "7.3.0";
  src = builtins.path {
    name = "linux-src";
    path = ./linux;
    filter = path: _: baseNameOf path != ".git";
  };
  configfile = ./config;
  # boot.img uses the gzip'd Image, like pmOS (its /boot/vmlinuz)
  target = "Image.gz";
  # common-flags.nix passes this stdenv's clang unwrapped as CC
  inherit (llvmPackages) stdenv;
  # ...but its bintools (LD, AR, NM...) are GNU binutils when cross-compiling,
  # and with GNU ld Kconfig drops pmOS' LTO_CLANG_THIN, RELR and COMPAT_VDSO.
  # These come after common-flags.nix, so they win. (Not LLVM=1: it would also
  # link host tools with -fuse-ld=lld, bypassing the ld wrapper's rpath.)
  extraMakeFlags = [
    "LD=${llvm}ld.lld"
    "AR=${llvm}llvm-ar"
    "NM=${llvm}llvm-nm"
    "OBJCOPY=${llvm}llvm-objcopy"
    "OBJDUMP=${llvm}llvm-objdump"
    "READELF=${llvm}llvm-readelf"
    "STRIP=${llvm}llvm-strip"
  ];
}).overrideAttrs (old: {
  # With CONFIG_EFI_ZBOOT, zinstall installs vmlinuz.efi, which the Image.gz
  # target doesn't build; Image.gz itself is copied by hand.
  buildFlags = old.buildFlags ++ [ "vmlinuz.efi" ];
  postInstall = old.postInstall + ''
    cp -v $buildRoot/arch/arm64/boot/Image.gz $out/
  '';
  # Read by Mobile NixOS' android system type
  passthru = old.passthru // {
    file = "Image.gz";
    isQcdt = false;
    isExynosDT = false;
  };
})
