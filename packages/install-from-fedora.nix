# TODO(fedora): transitional, for the first install only. Remove once NixOS
# boots from m1n1/boot.bin on the mini and Gravity's Fedora is deleted. The
# end state is Gravity's installer, run from macOS, writing a NixOS image
# directly, with no Fedora in between.
#
# Installs NixOS from Gravity's Fedora on the mini. It creates the "nixos"
# partition in the largest free block of the internal disk, formats it as LUKS2
# holding a btrfs filesystem with the subvolumes @root, @nix and @home, and
# installs SYSTEM there with Fedora's Bluetooth pairings and Wi-Fi
# connections. SYSTEM's bootloader hook adds a GRUB entry with ID "nixos" to
# Fedora's /boot, and `grub2-reboot nixos` then boots NixOS once. Nothing else
# on the disk is modified.
{
  lib,
  writeShellApplication,
  btrfs-progs,
  coreutils,
  cryptsetup,
  gawk,
  gnugrep,
  gptfdisk,
  nixos-install-tools,
  systemd,
  util-linux,
  system,
}:

writeShellApplication {
  name = "install-from-fedora";
  runtimeInputs = [
    btrfs-progs
    coreutils
    cryptsetup
    gawk
    gnugrep
    gptfdisk
    nixos-install-tools
    systemd
    util-linux
  ];
  text = ''
    esp_property=/proc/device-tree/chosen/gravity,efi-system-partition
    min_bytes=$((20 * 1024 * 1024 * 1024))
    mnt=/mnt/nixos

    die() {
      echo "install-from-fedora: $*" >&2
      exit 1
    }

    [ "$(id -u)" -eq 0 ] || die "run this as root"
    tr -d '\0' < /proc/device-tree/compatible | grep -q 'apple,j773g' \
      || die "this is not an M4 Mac mini (J773g)"
    [ -e /dev/disk/by-partlabel/nixos ] && die "a partition named nixos already exists"

    # NixOS mounts the EFI system partition the device tree names, so it must be
    # the one Fedora mounts at /boot/efi.
    [ -e "$esp_property" ] || die "the device tree has no $esp_property"
    esp_partuuid=$(tr -d '\0' < "$esp_property" | tr '[:upper:]' '[:lower:]')
    esp=$(readlink -e "/dev/disk/by-partuuid/$esp_partuuid") \
      || die "no partition has the PARTUUID $esp_partuuid of $esp_property"
    fedora_esp=$(findmnt -n -o SOURCE /boot/efi) || die "Fedora's EFI system partition is not mounted at /boot/efi"
    [ "$(readlink -e "$fedora_esp")" = "$esp" ] \
      || die "Fedora's /boot/efi ($fedora_esp) is not $esp, the EFI system partition $esp_property names"
    disk=/dev/$(lsblk -n -o PKNAME "$esp")
    fedora_boot=$(findmnt -n -o SOURCE /boot) || die "Fedora's /boot is not mounted"
    [ "$(lsblk -n -o LABEL "$fedora_boot")" = BOOT ] \
      || die "Fedora's /boot ($fedora_boot) is not labeled BOOT; set hardware.m4mini.fedoraGrub.device"

    # The keyboard paired in Fedora types the passphrase at NixOS's first boot.
    # Each pairing is a directory /var/lib/bluetooth/ADAPTER/DEVICE with an
    # info file.
    compgen -G '/var/lib/bluetooth/*/*/info' > /dev/null \
      || die "Fedora has no paired Bluetooth device; pair the keyboard in Fedora first"

    first=$(sgdisk -F "$disk")
    last=$(sgdisk -E "$disk")
    sector=$(blockdev --getss "$disk")
    bytes=$(( (last - first + 1) * sector ))
    [ "$bytes" -ge "$min_bytes" ] \
      || die "the largest free block of $disk is $((bytes / 1024 / 1024)) MiB; NixOS needs at least 20 GiB"

    echo "The current partitions of $disk:"
    sgdisk -p "$disk"
    echo
    echo "NixOS will go into sectors $first-$last of $disk ($((bytes / 1024 / 1024 / 1024)) GiB of free space)."
    echo "No existing partition is changed."
    read -r -p "Type nixos to continue: " answer
    [ "$answer" = nixos ] || die "cancelled"

    sgdisk -n "0:$first:$last" -t 0:8300 -c 0:nixos "$disk"
    partx -u "$disk"
    udevadm settle
    part=/dev/disk/by-partlabel/nixos
    [ -e "$part" ] || die "the new partition did not appear at $part"

    echo "Choose the LUKS passphrase you will type at every boot."
    cryptsetup luksFormat --type luks2 "$part"
    cryptsetup open "$part" cryptroot

    mkfs.btrfs -L nixos /dev/mapper/cryptroot
    mkdir -p "$mnt"
    mount /dev/mapper/cryptroot "$mnt"
    btrfs subvolume create "$mnt/@root" "$mnt/@nix" "$mnt/@home"
    umount "$mnt"

    options=compress=zstd,noatime
    mount -o "subvol=@root,$options" /dev/mapper/cryptroot "$mnt"
    mkdir -p "$mnt/nix" "$mnt/home" "$mnt/boot" "$mnt/fedora-boot"
    mount -o "subvol=@nix,$options" /dev/mapper/cryptroot "$mnt/nix"
    mount -o "subvol=@home,$options" /dev/mapper/cryptroot "$mnt/home"
    mount --bind /boot/efi "$mnt/boot"
    mount --bind /boot "$mnt/fedora-boot"

    # nixos-install installs the bootloader inside $mnt, so the initrd secrets
    # come from the new root's /var/lib/bluetooth.
    install -d -m 0755 "$mnt/var/lib"
    cp -r --preserve=mode,timestamps /var/lib/bluetooth "$mnt/var/lib/bluetooth"

    # NixOS's NetworkManager joins Fedora's Wi-Fi networks from the first boot.
    install -d -m 0755 "$mnt/etc/NetworkManager"
    cp -r --preserve=mode,timestamps /etc/NetworkManager/system-connections \
      "$mnt/etc/NetworkManager/system-connections"

    nixos-install --root "$mnt" --system ${system} --no-root-passwd --no-channel-copy

    umount -R "$mnt"
    cryptsetup close cryptroot

    cat <<EOF

    NixOS is installed. Fedora stays GRUB's default. To boot NixOS once:

      sudo grub2-reboot nixos && sudo reboot

    If NixOS hangs, power-cycle the mini to get back to Fedora.
    EOF
  '';

  meta.platforms = lib.platforms.linux;
}
