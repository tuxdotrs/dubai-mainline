# Removed from devices/motorola-dubai/default.nix when switching to the prebuilt
# pmOS kernel. Put back (and point `kernel` at this directory) to build from source.

# --- in the `let` block ---
  # The kernel is cross-compiled when the host can't build aarch64 natively,
  # since building it under binfmt emulation takes hours.
  kernelPkgs =
    if cfg.kernelBuildSystem == null || cfg.kernelBuildSystem == pkgs.stdenv.buildPlatform.system
    then pkgs
    else import pkgs.path {
      localSystem = cfg.kernelBuildSystem;
      crossSystem = pkgs.stdenv.hostPlatform.system;
      inherit (pkgs) overlays;
    };
  toolchain = import ./kernel/toolchain.nix {
    localSystem = kernelPkgs.stdenv.buildPlatform.system;
    crossSystem = pkgs.stdenv.hostPlatform.system;
  };
  kernel = kernelPkgs.callPackage ./kernel { inherit toolchain; };

# --- in options.motorola-dubai ---
    kernelBuildSystem = lib.mkOption {
      type = with lib.types; nullOr str;
      default = "x86_64-linux";
      description = ''
        System the kernel is (cross-)compiled on. null builds it like
        everything else.
      '';
    };

# --- in config ---
    # The kernel is pmOS's, config included. Mobile NixOS' required options
    # (firewall, binder, HID sensors... as built-ins) would change it, so they
    # are dropped; strict mode fails the build if the config isn't used as-is.
    mobile.kernel.structuredConfig = lib.mkForce [ ];

# --- in mobile.boot.stage-1.kernel ---
        useStrictKernelConfig = true;
