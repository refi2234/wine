# GE-Only Wine Wrapper Patchset

This directory is the extracted GE wrapper-side Wine patch stack from `GloriousEggroll/proton-ge-custom`.

Source checkout:
- `C:\Users\Makin\Desktop\Proton build\_tmp_ge_custom`

Source commits:
- GE wrapper commit: `245d4b08958a1fa27d684de7d2a8120df8f9c299`
- GE wine submodule commit: `b8fdff8e1f855b5276ec4ddca0f31b2792554322`
- Valve upstream branch containing that wine commit: `origin/proton_10.0`

Important finding:
- The GE `wine` submodule itself is not ahead of Valve's `proton_10.0` branch.
- GE-specific Wine changes are applied by the wrapper patch script, not by extra commits inside the `wine` git history.

Patch groups copied here:
- `patches/game-patches/`
- `patches/wine-hotfixes/pending/`
- `patches/wine-hotfixes/staging/cryptext-CryptExtOpenCER/`
- `patches/wine-hotfixes/staging/wineboot-ProxySettings/`
- `patches/wine-hotfixes/wine-wayland/`
- selected `patches/proton/*.patch` files applied in the WINE section of `patches/protonprep-valve-staging.sh`

Excluded on purpose:
- automatic wine-staging patchinstall payloads from `wine-staging/`
- non-Wine components like DXVK, VKD3D, gstreamer, protonfixes, winetricks
- Proton wrapper/runtime files not applied to the Wine tree

Selection source:
- `C:\Users\Makin\Desktop\Proton build\_tmp_ge_custom\patches\protonprep-valve-staging.sh`

Next step:
- classify these patches into Android-safe, desktop-only, and GameNative candidates before layering them onto the ARM64 Android patch chain.
