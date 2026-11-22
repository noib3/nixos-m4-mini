{
  description = "NixOS on the M4 Mac mini (J773g), on Gravity Linux's kernel and boot chain";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The three Gravity pins move together. The `gravity-pins` check fails when
    # the kernel or bootloader pin differs from gravity-packages' sources.json.
    gravity-packages = {
      url = "github:GravityLinux/packages/2664badde5808d75644964d00d3b8ebc22abdba4";
      flake = false;
    };
    gravity-linux = {
      url = "github:GravityLinux/linux/c7e7b86aed0c4c052851e5c3b2c02088c0602f02";
      flake = false;
    };
    gravity-bootloader = {
      url = "github:GravityLinux/bootloader/f5f5d4520587b6b8e2d8eb4d866baae129f47765";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      inherit (nixpkgs) lib;

      linuxSystem = "aarch64-linux";
      darwinSystem = "aarch64-darwin";

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };

      linuxPkgs = pkgsFor linuxSystem;
      darwinPkgs = pkgsFor darwinSystem;

      mkSystem =
        modules:
        lib.nixosSystem {
          modules = [
            self.nixosModules.default
            { nixpkgs.hostPlatform = linuxSystem; }
          ]
          ++ modules;
        };
    in
    {
      overlays.default = final: _prev: {
        linux-gravity = final.callPackage ./packages/linux-gravity {
          inherit (inputs) gravity-linux gravity-packages;
        };
        linuxPackages-gravity = final.linuxPackagesFor final.linux-gravity;
        m1n1-gravity = final.callPackage ./packages/m1n1-gravity.nix {
          src = inputs.gravity-bootloader;
        };
        mk-m1n1-boot-bin = final.callPackage ./packages/mk-m1n1-boot-bin.nix { };
        fetch-gravity-kernel-config = final.callPackage ./packages/fetch-gravity-kernel-config.nix { };
      };

      nixosModules.default = import ./modules { overlay = self.overlays.default; };

      nixosConfigurations = {
        mini-minimal = mkSystem [ ./hosts/minimal.nix ];

        # TODO(fedora): remove once NixOS boots from m1n1/boot.bin on the mini.
        mini-minimal-fedora-grub = mkSystem [
          ./hosts/minimal.nix
          { hardware.m4mini.fedoraGrub.enable = true; }
        ];

        mini-vm = mkSystem [
          ./hosts/minimal.nix
          ./hosts/vm.nix
          { virtualisation.host.pkgs = darwinPkgs; }
        ];
      };

      packages.${linuxSystem} = {
        inherit (linuxPkgs) linux-gravity m1n1-gravity;
        boot-bin = self.nixosConfigurations.mini-minimal.config.system.build.m1n1BootBin;
        default = self.nixosConfigurations.mini-minimal.config.system.build.toplevel;

        # TODO(fedora): remove once NixOS boots from m1n1/boot.bin on the mini.
        install-from-fedora = linuxPkgs.callPackage ./packages/install-from-fedora.nix {
          system = self.nixosConfigurations.mini-minimal-fedora-grub.config.system.build.toplevel;
        };
      };

      packages.${darwinSystem} = {
        inherit (darwinPkgs) fetch-gravity-kernel-config;
        mini-vm = self.nixosConfigurations.mini-vm.config.system.build.vm;
      };

      apps.${darwinSystem} = {
        mini-vm = {
          type = "app";
          program = "${self.packages.${darwinSystem}.mini-vm}/bin/run-mini-vm";
        };
        fetch-gravity-kernel-config = {
          type = "app";
          program = lib.getExe darwinPkgs.fetch-gravity-kernel-config;
        };
      };

      checks.${linuxSystem} = {
        gravity-pins = linuxPkgs.callPackage ./checks/gravity-pins.nix { inherit inputs; };
        boot-bin-layout = linuxPkgs.callPackage ./checks/boot-bin-layout.nix {
          system = self.nixosConfigurations.mini-minimal.config.system.build.toplevel;
          bootBin = self.packages.${linuxSystem}.boot-bin;
          m1n1 = linuxPkgs.m1n1-gravity;
        };
        vm-boots = linuxPkgs.callPackage ./checks/vm-boots.nix { inherit self; };
        vm-luks = linuxPkgs.callPackage ./checks/vm-luks.nix { inherit self; };
      };

      formatter.${darwinSystem} = darwinPkgs.nixfmt;
    };
}
