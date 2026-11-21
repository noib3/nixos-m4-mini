# Gravity Linux's m1n1 fork, built as Gravity builds its stage 2: a release
# build without chainloading. The M4 sources set NO_DISPLAY themselves.
{
  lib,
  m1n1,
  rustPlatform,
  src,
}:

(m1n1.override { customLogo = null; }).overrideAttrs (
  finalAttrs: previousAttrs: {
    pname = "m1n1-gravity";
    version = "1.6.1";
    inherit src;

    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit (finalAttrs) pname version;
      src = "${finalAttrs.src}/rust";
      sourceRoot = "rust";
      hash = "sha256-/2JQ31pMHbNjZsIu2RLCWzNul/qzL1O2+XB3qdOEb2U=";
    };

    makeFlags = lib.remove "CHAINLOADING=1" previousAttrs.makeFlags;

    # Gravity's fork has LICENSE.GPL2 and LICENSE.MIT in place of LICENSE.
    installPhase = ''
      runHook preInstall

      install -Dm644 build/m1n1.bin -t $out/lib/m1n1/
      install -Dm644 LICENSE.* 3rdparty_licenses/LICENSE.* -t $out/share/doc/m1n1/licenses/

      runHook postInstall
    '';

    meta = previousAttrs.meta // {
      homepage = "https://github.com/GravityLinux/bootloader";
    };
  }
)
