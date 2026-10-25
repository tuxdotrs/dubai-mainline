# Kernel

## Source and config

- Source: https://github.com/sc7280-mainline/linux, submodule `kernel/linux`,
  tag **`v7.3.0-sc7280`** (commit 7a0dfc4ec; the tag object is 5c9d0dbc). This
  is the tree pmOS packages as `linux-postmarketos-qcom-sc7280`. The default
  branch is `sc7280-7.2.y`; releases are tags `vX.Y.Z-sc7280`.
- Config: `kernel/config` = pmOS'
  `config-postmarketos-qcom-sc7280.aarch64` (written for 7.2.9) plus
  `CONFIG_HW_RANDOM_QCOM=y`, `CONFIG_DRM_SIMPLEDRM=y` (boot log on screen) and the netfilter modules the NixOS firewall uses
  (`XT_MATCH_PKTTYPE`, `IP_NF_MATCH_RPFILTER`, `IP6_NF_MATCH_RPFILTER`,
  `XT_MATCH_LIMIT`, `XT_TARGET_LOG`, `NF_LOG_*`). New options in 7.3 take their defaults from
  `make oldconfig` (69 of them for 7.2.9 → 7.3.0; relevant ones: `QCOM_PAS=y`,
  `QCOM_SOC=y`).
- DTBs: `arch/arm64/boot/dts/qcom/sm7325-motorola-dubai{,-csot,-tianma}.dtb`.

### Config changes between 7.2.9 and 7.3.0 worth knowing

| Option | What happened |
|---|---|
| `CRYPTO_DEV_QCOM_RNG` | Qualcomm TRNG moved to `HW_RANDOM_QCOM` (defaults to n) → set `=y` |
| `PROC_SYSCTL` | No longer an option; sysctl always builds with `CONFIG_SYSCTL` |
| `CRYPTO_DEV_QCE` | Marked `BROKEN` upstream, disappears |
| `CC_MS_EXTENSIONS`, `WARN_CONTEXT_ANALYSIS` | Compiler-dependent (clang 21 vs pmOS' clang 23) |

## How it's built

`kernel/default.nix` uses **nixpkgs `linuxManualConfig`**
(`pkgs/os-specific/linux/kernel/build.nix` in the pinned nixpkgs), called with
`kernelPkgs.callPackage` from the device module so it cross-compiles from
x86_64 (`motorola-dubai.kernelBuildSystem`, default `"x86_64-linux"`; building
under binfmt emulation takes hours).

Key points of the expression:

- `stdenv = llvmPackages.stdenv` — clang 21.1.8 from the Mobile NixOS
  nixpkgs pin. `common-flags.nix` passes the **unwrapped** clang as `CC`.
- `extraMakeFlags` sets `LD/AR/NM/OBJCOPY/OBJDUMP/READELF/STRIP` to
  `${buildPackages.llvmPackages.bintools-unwrapped}/bin/${targetPrefix}ld.lld`
  etc. Reason: a *cross* `llvmPackages.stdenv` still has **GNU binutils**; with
  GNU ld, Kconfig silently drops `LTO_CLANG_THIN`, `RELR`, `COMPAT_VDSO`
  (pmOS has all three). extraMakeFlags come after common-flags, so they win.
  In cross builds the tools carry the target prefix
  (`aarch64-unknown-linux-gnu-ld.lld`) — plain `ld.lld` doesn't exist there.
- **No `LLVM=1`**: with it, the kernel links *host* tools with
  `-fuse-ld=lld` (unwrapped, outside Nix's ld wrapper) → `extract-cert`,
  `resolve_btfids` get no rpath → "libcrypto.so.3 / libelf.so.1: cannot open
  shared object file".
- `target = "Image.gz"` (boot.img uses the gzip'd Image, like pmOS'
  `/boot/vmlinuz`). Because `CONFIG_EFI_ZBOOT=y`, `zinstall` installs
  `vmlinuz.efi`, so `vmlinuz.efi` is added to `buildFlags` and `Image.gz` is
  copied to `$out` in `postInstall`.
- passthru `file = "Image.gz"; isQcdt = false; isExynosDT = false;` — read by
  Mobile NixOS' android system type.
- Outputs: `out` (Image.gz, vmlinuz.efi, dtbs/, System.map), `modules`
  (`lib/modules/7.3.0`, with `modules.dep`, modules stripped and zstd'd), `dev`
  (build tree incl. the final `.config`). Mobile NixOS' initrd uses
  `kernel.modules` when it exists.

The prebuilt pmOS binary kernel remains available as a fallback:
`motorola-dubai.kernel = "prebuilt";` (`kernel/prebuilt/`,
unpacks `linux-postmarketos-qcom-sc7280-7.2.9-r2.apk` from
mirror.postmarketos.org and runs `depmod`, since the apk ships empty
`modules.dep/alias` placeholders that Alpine fills at install time).

## Patches (`kernel/patches/`, applied via `kernelPatches`)

- `qrtr-ns-wait-for-hello.patch` — **modem stalls at boot**. af_qrtr refuses
  every packet to a remote node with `-EAGAIN` until our own HELLO to it has
  been sent (from a work item, `af_qrtr.c` `hello_sent`). When the remote's
  HELLO reaches the QRTR name service first, `announce_servers()` got
  `-EAGAIN` on the first service and returned, so the remote never learned of
  *any* local service. For the modem that means no rmtfs/tqftpserv → its
  watchdog fires 65 s later (`DOG detects stalled initialization`), repeat.
  The race is timing-dependent: it hit 3/3 boots once the NixOS firewall
  started successfully (which shifts early boot by ~0.2 s), 0/5 before. Found
  with kprobes on `service_announce_new`/`qrtr_node_enqueue` (retval -11).
  The patch retries `-EAGAIN` (20 ms × 50) and continues past other errors.
  Verified 3/3 clean boots with the firewall on. Candidate for upstream
  (net/qrtr; mainline only skips `-ENODEV` there).

## Build history: every failure and its cause

Kept so nobody re-walks this path.

| # | Error | Cause | Fix |
|---|---|---|---|
| 1 | `clang: error: argument unused during compilation: '-nostdlibinc'` | cc-wrapper adds `-nostdlibinc`; kernel builds with `-Werror=unused-command-line-argument` | use unwrapped clang (linuxManualConfig does) |
| 2 | `certs/extract-cert: libcrypto.so.3: cannot open shared object file` | `LLVM=1` → host link with unwrapped lld, no rpath | drop `LLVM=1` (or `HOSTLDFLAGS=-fuse-ld=bfd`) |
| 3 | `resolve_btfids: libelf.so.1: cannot open shared object file` | same as 2 | same |
| 4 | **Boot loop**; stage-1 exits 99 creating `functions/rndis.usb0` | Mobile NixOS' kernel-builder seds `= depmod` in the top Makefile; 7.3 moved `DEPMOD` into `scripts/depmod.sh`; no depmod in PATH → `modules_install` only warns → no `modules.dep` → `makeModulesClosure` (allowMissing) finds no modules → initrd has 0 `.ko` | linuxManualConfig has kmod in PATH; with the old builder, pass `DEPMOD=${kmod}/bin/depmod` |
| 5 | `*** Missing file: arch/arm64/boot/vmlinuz.efi` (zinstall) | `CONFIG_EFI_ZBOOT` | add `vmlinuz.efi` to `buildFlags` |
| 6 | Builds, but `LD_IS_BFD`, `LTO_NONE` | cross llvm stdenv uses GNU binutils | LLVM tools via `extraMakeFlags` |
| 7 | `linker '…/llvm-binutils/bin/ld.lld' not found` | cross tools are target-prefixed | `${targetPrefix}ld.lld` |

Bug 4 lives in Mobile NixOS' kernel-builder and affects every kernel ≥ 7.3;
worth reporting upstream.

## Verifying a kernel build

"It built" is not enough (see #4 and #6). On the build host:

```sh
K=$(readlink -f build/kernel)
outs=$(nix-store -q --outputs $(nix-store -q --deriver $K))
M=$(echo "$outs" | grep -- -modules$); D=$(echo "$outs" | grep -- -dev$)
ls $K/Image.gz $K/dtbs/qcom/sm7325-motorola-dubai-*.dtb
test -s $M/lib/modules/*/modules.dep && echo modules.dep ok
for m in panel-novatek-nt37701 spi-geni-qcom goodix_berlin_core goodix_berlin_spi \
         libcomposite usb_f_rndis qcom_q6v5_pas ath11k_ahb; do
  find $M -name "$m.ko*" | grep -q . || echo "MISSING $m"; done
zcat $K/Image.gz | strings | grep -m1 "Linux version"   # expect clang + LLD
grep -E '^CONFIG_(LD_IS_LLD|LTO_CLANG_THIN|RELR|COMPAT_VDSO|HW_RANDOM_QCOM)=' \
  $D/lib/modules/*/build/.config
# initrd must contain ~10 modules
zstd -dc $(readlink -f build/system/initrd) | cpio -t --quiet | grep -c '\.ko'
```

And diff the final `.config` against the previous known-good one, ignoring
compiler-version lines. Then check the boot.img ramdisk end (boot-chain.md).

## Bumping the kernel

```sh
git -C kernel/linux fetch --depth 1 origin tag v7.3.1-sc7280
git -C kernel/linux checkout v7.3.1-sc7280
# update `version` in kernel/default.nix
./build.sh kernel     # read the "(NEW)" lines in build/logs/kernel.log
git add kernel/linux kernel/default.nix
```

Check pmaports' `device/community/linux-postmarketos-qcom-sc7280` for a
newer config and APKBUILD (pmOS lags the sc7280-mainline tags a bit; the
mirror at https://mirror.postmarketos.org/postmarketos/master/aarch64/ shows
which version pmOS ships). Review new Qualcomm/remoteproc options by hand.

## Parked: pmOS' exact toolchain

pmOS builds with Alpine clang/lld **23.1.3** and LLVM built with zstd.
`kernel/toolchain/toolchain.nix` imports a nixpkgs with clang 23.1.3.
A strict "config must not change" build failed only on
`DEBUG_INFO_COMPRESSED_ZSTD` (nixpkgs LLVM lacks zstd; the overlay builds
libllvm with zstd but clang/lld then fail at CMake `find_package(zstd)`). Not
needed for a working kernel.
