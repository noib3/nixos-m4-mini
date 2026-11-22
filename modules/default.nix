{ overlay }:

{ lib, ... }:

{
  imports = [
    ./kernel.nix
    ./firmware.nix
    ./boot.nix
    ./esp.nix
    ./initrd-bluetooth.nix
    ./initrd-ssh.nix
    # TODO(fedora): remove with the module once Gravity's Fedora is deleted.
    ./fedora-grub.nix
  ];

  options.hardware.m4mini.enable = lib.mkEnableOption "support for the Apple M4 Mac mini (J773g)";

  config = {
    nixpkgs.overlays = [ overlay ];
  };
}
