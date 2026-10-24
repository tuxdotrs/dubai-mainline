# The pmOS linux-postmarketos-qcom-sc7280 kernel, unmodified: same source tag,
# same config (config-pmos.aarch64, copied from pmaports), built with LLVM like
# pmOS (clang 23.1.3, from ./toolchain.nix). Missing build tools are added
# here instead of changing the config.
# Strict mode (see ../default.nix) fails the build if `make oldconfig` would
# change anything.
{ mobile-nixos
, fetchFromGitHub
, buildPackages
, toolchain
, ...
}:

(mobile-nixos.kernel-builder.override { stdenv = toolchain.llvmPackages_23.stdenv; }) {
  version = "7.2.9";
  configfile = ./config-pmos.aarch64;
  src = import ./source.nix { inherit fetchFromGitHub; };

  makeFlags = [
    "LLVM=1"
    # clang for host tools too, as LLVM=1 does on pmOS
    "HOSTCC=${toolchain.pkgsBuildBuild.llvmPackages_23.clang}/bin/clang"
  ];
  nativeBuildInputs = with buildPackages; [
    toolchain.buildPackages.llvmPackages_23.lld
    toolchain.buildPackages.llvmPackages_23.llvm
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
  '';
}
