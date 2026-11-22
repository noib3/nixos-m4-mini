{ overlay }:

{ lib, ... }:

{
  imports = [
    ./kernel.nix
    ./firmware.nix
    ./boot.nix
    ./initrd-bluetooth.nix
  ];

  options.hardware.m4mini.enable = lib.mkEnableOption "support for the Apple M4 Mac mini (J773g)";

  config = {
    nixpkgs.overlays = [ overlay ];
  };
}
