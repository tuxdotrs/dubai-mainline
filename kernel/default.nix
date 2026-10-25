# sc7280-mainline/linux (the submodule in ./linux), built with LLVM like pmOS
# builds linux-postmarketos-qcom-sc7280. ./config is pmOS's config for that
# package; `make oldconfig` fills in options it doesn't have yet (no strict
# check, see ../devices/motorola-dubai/default.nix).
# Bumping: check out another tag in ./linux and update `version`.
{ lib
, mobile-nixos
, llvmPackages
, buildPackages
, ...
}:

assert lib.assertMsg (builtins.pathExists ./linux/Makefile)
  "kernel/linux is empty: run `git submodule update --init --depth 1 kernel/linux`";

let
  inherit (llvmPackages) stdenv;
  clang = stdenv.cc.cc;
  clangInclude = "${lib.getLib clang}/lib/clang/${lib.versions.major clang.version}/include";
in
(mobile-nixos.kernel-builder.override { inherit stdenv; }) {
  version = "7.3.0";
  configfile = ./config;
  src = builtins.path {
    name = "linux-src";
    path = ./linux;
    filter = path: _: baseNameOf path != ".git";
  };

  makeFlags = [
    "LLVM=1"
    # Unwrapped clang and ld.lld, as nixpkgs' kernel/common-flags.nix does: the
    # cc-wrapper adds -nostdlibinc, which the kernel's
    # -Werror=unused-command-line-argument rejects, and doesn't like --target.
    # These override the builder's wrapped CC (the last one on the command line wins).
    "CC=${lib.getExe clang}"
    "LD=${lib.getExe' buildPackages.llvmPackages.lld "ld.lld"}"
    "CFLAGS_MODULE=-I${clangInclude}"
    "CFLAGS_KERNEL=-I${clangInclude}"
    # LLVM=1 links host tools with -fuse-ld=lld unless HOSTLDFLAGS picks a
    # linker; that bypasses the ld wrapper, so extract-cert, resolve_btfids...
    # get no rpath ("libcrypto.so.3: cannot open shared object file").
    "HOSTLDFLAGS=-fuse-ld=bfd"
    # The builder points the Makefile's `DEPMOD = depmod` at kmod, but 7.3 moved
    # that default into scripts/depmod.sh; without depmod in PATH,
    # modules_install skips it and stage-1 finds no modules.
    "DEPMOD=${buildPackages.kmod}/bin/depmod"
  ];
  nativeBuildInputs = with buildPackages; [
    llvmPackages.lld
    llvmPackages.llvm
    python3 # drivers/gpu/drm/msm header generation
    zstd # CONFIG_MODULE_COMPRESS_ZSTD
    pahole # CONFIG_DEBUG_INFO_BTF
  ];

  isModular = true;
  isCompressed = "gz";

  # CONFIG_EFI_ZBOOT: zinstall installs vmlinuz.efi, which `make Image.gz` doesn't build
  preInstall = ''
    make $makeFlags "''${makeFlagsArray[@]}" -j$NIX_BUILD_CORES vmlinuz.efi
  '';
  # boot.img uses the gzip'd Image, like pmOS (its /boot/vmlinuz)
  postInstall = ''
    cp -v $buildRoot/arch/arm64/boot/Image.gz $out/
    test -s $out/lib/modules/*/modules.dep || { echo "modules.dep is missing"; exit 1; }
  '';
}
