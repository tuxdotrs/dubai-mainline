# The pmOS kernel, as pmOS ships it: its binary package
# linux-postmarketos-qcom-sc7280 unpacked, nothing rebuilt.
# The mirror only keeps the latest revision. When r2 is gone, bump url + hash,
# or put a saved copy back in the store with `nix-store --add-fixed sha256 <apk>`.
# The apk has no .config; config-postmarketos-qcom-sc7280.aarch64 is the one from
# pmaports at the same pkgrel (NixOS reads it, e.g. for ASLR sysctls).
# Building it from source instead: ../../../stuff-might-need-later/kernel-from-source
{ lib, stdenv, fetchurl, kmod, ... }:

stdenv.mkDerivation rec {
  pname = "linux";
  version = "7.2.9";

  src = fetchurl {
    url = "https://mirror.postmarketos.org/postmarketos/master/aarch64/linux-postmarketos-qcom-sc7280-${version}-r2.apk";
    sha256 = "a0bd82303ae2a5dc177c236c1f403d8bcbf5da4a302779975176f2fc9abc4dbb";
  };

  nativeBuildInputs = [ kmod ];

  unpackPhase = ''
    mkdir apk
    tar -xzf $src -C apk --warning=no-unknown-keyword boot usr
  '';

  installPhase = ''
    mkdir -p $out/lib
    cp apk/boot/vmlinuz $out/Image.gz
    cp -r apk/boot/dtbs $out/dtbs
    cp -r apk/usr/lib/modules $out/lib/modules
    rm -f $out/lib/modules/${version}/build
    # The apk's modules.dep has no dependencies (Alpine runs depmod on install);
    # Mobile NixOS reads it to pick the stage-1 modules.
    depmod -b $out ${version}
    cp ${configfile} $out/config
  '';

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  configfile = ./config-postmarketos-qcom-sc7280.aarch64;

  passthru = {
    inherit configfile;
    target = "Image.gz";
    file = "Image.gz";
    isQcdt = false;
    isExynosDT = false;
    modDirVersion = version;
    baseVersion = version;
    kernelOlder = lib.versionOlder version;
    kernelAtLeast = lib.versionAtLeast version;
  };
}
