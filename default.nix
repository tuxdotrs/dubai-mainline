# nix-build -A outputs.default                 (images, see README.md)
# nixos-rebuild switch --file default.nix ...   (updates)
# Builds natively for aarch64 (binfmt on x86_64); the kernel is cross-compiled.
{ device ? ./devices/motorola-dubai, system ? "aarch64-linux", ... }@args:

import ./mobile-nixos/lib/eval-with-configuration.nix (args // {
  inherit device system;
  configuration = [ ./configuration.nix ];
})
