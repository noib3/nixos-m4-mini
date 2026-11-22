# TODO(fedora): transitional, for the first install only, like
# install-from-fedora.
#
# Gives SSH access over Wi-Fi to Gravity's Fedora from its first boot, for a
# mini with no keyboard Fedora can use. Run from macOS on the mini after
# Gravity's installer, the script writes an RPM to gravity/extras on Gravity's
# EFI system partition, which gravity-extras-firstboot.service installs at
# Fedora's first boot. The RPM adds a NetworkManager connection to the Wi-Fi
# network SSID, and creates the user NAME in the wheel group, with the
# authorized keys in FILE and a password the script prompts for. With
# --hostname, the RPM also sets Fedora's hostname, which Avahi announces as
# HOSTNAME.local. The RPM then deletes its secrets and itself from the EFI
# system partition.
#
# The Wi-Fi password comes from the macOS keychain, or from a prompt when the
# keychain has none.
{
  lib,
  writeShellApplication,
  nfpm,
  openssl,
}:

writeShellApplication {
  name = "preseed-fedora-ssh";
  runtimeInputs = [
    nfpm
    openssl
  ];
  text = ''
    usage="usage: preseed-fedora-ssh --ssid SSID --user NAME --authorized-keys FILE [--hostname HOSTNAME] [--esp DISK]"

    die() {
      echo "preseed-fedora-ssh: $*" >&2
      exit 1
    }

    ssid=
    user=
    keys=
    esp=
    hostname=
    while [ $# -gt 0 ]; do
      case "$1" in
        --hostname) hostname=''${2:?$usage}; shift 2 ;;
        --ssid) ssid=''${2:?$usage}; shift 2 ;;
        --user) user=''${2:?$usage}; shift 2 ;;
        --authorized-keys) keys=''${2:?$usage}; shift 2 ;;
        --esp) esp=''${2:?$usage}; shift 2 ;;
        -h | --help) echo "$usage"; exit 0 ;;
        *) die "unknown argument $1; $usage" ;;
      esac
    done
    [ -n "$ssid" ] && [ -n "$user" ] && [ -n "$keys" ] || die "$usage"
    [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "$user is not a valid user name"
    grep -qE '^(ssh-|ecdsa-|sk-)' "$keys" || die "$keys has no SSH public key"
    if [ -n "$hostname" ]; then
      [[ "$hostname" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] \
        || die "$hostname is not a valid hostname"
    fi

    # Gravity's EFI system partition is the internal disk's only EFI partition,
    # unless --esp names one.
    if [ -z "$esp" ]; then
      mapfile -t esps < <(diskutil list internal physical | awk '$2 == "EFI" { print $NF }')
      [ "''${#esps[@]}" -eq 1 ] \
        || die "found ''${#esps[@]} EFI partitions on the internal disk (''${esps[*]}); pass --esp"
      esp=''${esps[0]}
    fi

    was_mounted=$(diskutil info "$esp" | awk -F': *' '/^ *Mounted:/ { print $2 }')
    diskutil mount "$esp" > /dev/null || die "could not mount $esp"
    esp_mnt=$(diskutil info "$esp" | sed -n 's/^ *Mount Point: *//p')
    [ -f "$esp_mnt/m1n1/boot.bin" ] || die "$esp ($esp_mnt) has no m1n1/boot.bin, so it isn't Gravity's"

    work=$(mktemp -d)
    chmod 700 "$work"
    cleanup() {
      rm -rf "$work"
      [ "$was_mounted" = Yes ] || diskutil unmount "$esp" > /dev/null || true
    }
    trap cleanup EXIT

    if ! psk=$(security find-generic-password -D "AirPort network password" -a "$ssid" -w 2> /dev/null); then
      read -r -s -p "Wi-Fi password of $ssid: " psk
      echo
    fi
    [ -n "$psk" ] || die "the Wi-Fi password of $ssid is empty"

    read -r -s -p "Password of $user in Fedora: " password
    echo
    read -r -s -p "Again: " password_again
    echo
    [ -n "$password" ] || die "the password is empty"
    [ "$password" = "$password_again" ] || die "the passwords differ"

    printf '%s' "$password" | openssl passwd -6 -stdin > "$work/password-hash"
    cp "$keys" "$work/authorized_keys"

    cat > "$work/wifi.nmconnection" <<EOF
    [connection]
    id=$ssid
    type=wifi
    autoconnect=true

    [wifi]
    mode=infrastructure
    ssid=$ssid

    [wifi-security]
    key-mgmt=wpa-psk
    psk=$psk

    [ipv4]
    method=auto

    [ipv6]
    method=auto
    EOF

    staged=/var/lib/preseed-fedora-ssh
    cat > "$work/postinstall.sh" <<EOF
    #!/bin/sh
    set -eu
    if ! id $user > /dev/null 2>&1; then
      useradd -m -G wheel -p "\$(cat $staged/password-hash)" $user
    fi
    install -d -m 0700 -o $user -g $user /home/$user/.ssh
    install -m 0600 -o $user -g $user $staged/authorized_keys /home/$user/.ssh/authorized_keys
    if command -v restorecon > /dev/null; then
      restorecon -R /home/$user/.ssh
    fi
    rm -rf $staged
    rm -f /boot/efi/gravity/extras/preseed-fedora-ssh-*.rpm
    nmcli connection reload || true
    EOF

    if [ -n "$hostname" ]; then
      cat >> "$work/postinstall.sh" <<EOF
    echo $hostname > /etc/hostname
    hostnamectl set-hostname $hostname || true
    systemctl try-restart avahi-daemon.service || true
    EOF
    fi

    cat > "$work/nfpm.yaml" <<EOF
    name: preseed-fedora-ssh
    arch: all
    platform: linux
    version: 1
    release: 1
    description: Wi-Fi and SSH access for the first boot of Gravity's Fedora
    contents:
      - src: $work/wifi.nmconnection
        dst: /etc/NetworkManager/system-connections/preseed-wifi.nmconnection
        file_info:
          mode: 0600
      - src: $work/authorized_keys
        dst: $staged/authorized_keys
        file_info:
          mode: 0600
      - src: $work/password-hash
        dst: $staged/password-hash
        file_info:
          mode: 0600
    scripts:
      postinstall: $work/postinstall.sh
    EOF

    mkdir -p "$esp_mnt/gravity/extras"
    rm -f "$esp_mnt"/gravity/extras/preseed-fedora-ssh-*.rpm
    nfpm package -f "$work/nfpm.yaml" -p rpm -t "$esp_mnt/gravity/extras/" > /dev/null

    echo "Wrote $(ls "$esp_mnt"/gravity/extras/preseed-fedora-ssh-*.rpm)."
    echo "At its first boot, Fedora joins $ssid and accepts SSH logins as $user."
    if [ -n "$hostname" ]; then
      echo "Log in with: ssh $user@$hostname.local"
    fi
  '';

  meta.platforms = lib.platforms.darwin;
}
