{
  lib,
  linuxManualConfig,
  writeText,
  gravity-linux,
  gravity-packages,
  # Kconfig symbols, without the `CONFIG_` prefix, mapped to "y", "m" or "n".
  # They replace the matching entries of Gravity's configuration.
  extraConfig ? { },
  # The linuxManualConfig arguments NixOS overrides: kernelPatches, applied
  # after Gravity's patches, and others like features and randstructSeed.
  # kernelPatches is not a named argument, so callPackage leaves it unset.
  ...
}@args:

let
  version = "7.3.0";

  # The options that differ from Gravity's configuration.
  nixConfig = {
    # Debug info and BTF make the build several times slower and need pahole.
    DEBUG_INFO = "n";
    DEBUG_INFO_NONE = "y";
    DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT = "n";
    DEBUG_INFO_BTF = "n";
    DEBUG_INFO_BTF_MODULES = "n";

    # Fedora signs modules with a key generated at build time. Nix keeps no
    # such key, and the stripped modules would no longer match it.
    MODULE_SIG = "n";
    MODULE_SIG_ALL = "n";

    # Fedora's GCC has no plugin support, so Gravity's configuration never sets
    # this, and nixpkgs' GCC would default it to y. Gravity builds without GCC
    # plugins.
    GCC_PLUGINS = "n";

    # m1n1 and QEMU start the plain Image, and Nix builds only that target.
    # COMPRESSED_INSTALL makes the kernel's install target copy the compressed
    # image instead, and EFI_ZBOOT makes that image the EFI application
    # vmlinuz.efi. m1n1 has no use for an EFI application.
    COMPRESSED_INSTALL = "n";
    EFI_ZBOOT = "n";

    # UBSAN makes GCC record each checked source file's path as the compiler
    # received it, and no prefix-map option remaps that record. Nix builds out
    # of tree with the source in the dev output, so the Image would refer to
    # dev, and dev refers to the Image's output.
    UBSAN = "n";
  }
  // extraConfig;

  # The Kconfig symbol a line of a .config file sets, or null.
  symbolOf =
    line:
    let
      set = builtins.match "CONFIG_([A-Za-z0-9_]+)=.*" line;
      unset = builtins.match "# CONFIG_([A-Za-z0-9_]+) is not set" line;
    in
    if set != null then
      lib.head set
    else if unset != null then
      lib.head unset
    else
      null;

  renderOption =
    name: value: if value == "n" then "# CONFIG_${name} is not set" else "CONFIG_${name}=${value}";

  gravityLines = lib.splitString "\n" (builtins.readFile ./gravity.config);

  lines =
    lib.filter (line: !(nixConfig ? ${toString (symbolOf line)})) gravityLines
    ++ lib.mapAttrsToList renderOption nixConfig;

  # The y and m options of the final configuration, in the shape
  # linuxManualConfig parses from a .config file.
  parsedConfig = lib.listToAttrs (
    lib.concatMap (
      line:
      let
        match = builtins.match "(CONFIG_[^=]+)=([ym])" line;
      in
      lib.optional (match != null) (lib.nameValuePair (lib.elemAt match 0) (lib.elemAt match 1))
    ) lines
  );

  # Gravity's packaging patches, applied after its kernel tree as Gravity's
  # kernel.spec does.
  gravityPatches = lib.pipe (builtins.readDir "${gravity-packages}/kernel") [
    (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".patch" name))
    lib.attrNames
    (lib.sort lib.lessThan)
    (map (name: {
      inherit name;
      patch = "${gravity-packages}/kernel/${name}";
    }))
  ];
in
linuxManualConfig (
  removeAttrs args [
    "lib"
    "linuxManualConfig"
    "writeText"
    "gravity-linux"
    "gravity-packages"
    "extraConfig"
  ]
  // {
    pname = "linux-gravity";
    inherit version;
    modDirVersion = version;
    src = gravity-linux;
    configfile = writeText "linux-gravity-${version}.config" (lib.concatStringsSep "\n" lines + "\n");
    config = parsedConfig;
    kernelPatches = gravityPatches ++ args.kernelPatches or [ ];
    extraMeta = {
      branch = lib.versions.majorMinor version;
      description = "Gravity Linux's kernel for the Apple M4 Mac mini";
      platforms = [ "aarch64-linux" ];
    };
  }
)
