# nixpkgs used only for the kernel's compiler: it has LLVM 23.1.3, the version
# pmOS builds linux-postmarketos-qcom-sc7280 with (the Mobile NixOS pin has 22,
# which changes compiler-dependent config lines). Everything else stays on the pin.
{ localSystem, crossSystem }:

import (builtins.fetchTarball {
  url = "https://github.com/NixOS/nixpkgs/archive/02c087f3fe673c9e317f206a627cb6b910336dbe.tar.gz";
  sha256 = "1l60ar0j7j7jrrg4r7j4kscrih0qn2n0lslffzflhv86lyq650r2";
}) {
  inherit localSystem crossSystem;
  overlays = [
    # Alpine's LLVM has zstd, nixpkgs' doesn't. Without it clang/lld reject
    # zstd debug compression, and Kconfig drops DEBUG_INFO_COMPRESSED_ZSTD.
    (final: prev: {
      llvmPackages_23 = prev.llvmPackages_23.overrideScope (_: p: {
        libllvm = p.libllvm.overrideAttrs (o: {
          buildInputs = o.buildInputs ++ [ final.zstd ];
          cmakeFlags = o.cmakeFlags ++ [ "-DLLVM_ENABLE_ZSTD=FORCE_ON" ];
          doCheck = false;
        });
      });
    })
  ];
}
