# Downloads the kernel-16k-core package of a Gravity kernel release from
# Gravity's COPR repository and prints the kernel configuration it ships.
{
  writeShellApplication,
  coreutils,
  curl,
  gnugrep,
  gzip,
  libarchive,
}:

writeShellApplication {
  name = "fetch-gravity-kernel-config";
  runtimeInputs = [
    coreutils
    curl
    gnugrep
    gzip
    libarchive
  ];
  text = ''
    if [ "$#" -ne 1 ]; then
      echo "usage: fetch-gravity-kernel-config RELEASE  (e.g. 526, for 7.3.0-526.gravity)" >&2
      exit 2
    fi

    release=$1
    repo=https://download.copr.fedorainfracloud.org/results/adevwithanidea/gravity/fedora-44-aarch64

    primary=$(curl -fsSL "$repo/repodata/repomd.xml" | grep -o 'repodata/[^"]*-primary\.xml\.gz' | head -n 1)
    rpm=$(curl -fsSL "$repo/$primary" | gunzip -c \
      | grep -o "Packages/k/kernel-16k-core-[0-9.]*-$release\.gravity\.fc[0-9]*\.aarch64\.rpm" \
      | head -n 1)

    if [ -z "$rpm" ]; then
      echo "fetch-gravity-kernel-config: no kernel-16k-core package for release $release" >&2
      exit 1
    fi

    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    echo "fetch-gravity-kernel-config: downloading $rpm" >&2
    curl -fsSL -o "$tmp/kernel.rpm" "$repo/$rpm"
    bsdtar -xf "$tmp/kernel.rpm" -C "$tmp" --include '*/config'
    cat "$tmp"/lib/modules/*/config
  '';
}
