# Android Wine and Proton Nightlies

GitHub Actions pipeline for two Android build flows in one repo:

- `proton`: Proton-based Android/ARM64EC build using Valve Proton plus the GameNative Android layer and optional GE-style extras.
- `wine`: plain Wine Android `x86_64` build with the March 4, 2026 `REF4IK/wine-bionic` source patch set.

## Workflows

- `.github/workflows/android-proton-nightlies.yml`
- `.github/workflows/android-wine-nightlies.yml`

All supporting files for both workflows live under `toolkit/android-wine-proton/`.

Manual dispatch for Proton supports:

- `proton_ref`, `gamenative_ref`
- `target_app_id`
- `force_build`
- optional Proton patch toggles like `enable_ntsync`, `extra_winebus_patches`, `ge_perf_second_pass`, `ge_compat_patch_bundle`

Manual dispatch for plain Wine supports:

- `wine_repo`, `wine_ref`
- `wine_version_label`, `wine_version_code`
- `target_app_id`
- `force_build`

## Local Script Layout

- `toolkit/android-wine-proton/scripts/build-proton-arm64.sh`: Proton Android package builder
- `toolkit/android-wine-proton/scripts/build-wine-bionic.sh`: plain Wine Android x86_64 builder
- `toolkit/android-wine-proton/scripts/apply-ref4ik-bionic-patches.sh`: applies the exact March 4 `wine-bionic` source patches from the local repo patchset
- `toolkit/android-wine-proton/scripts/create-proton-wcp.sh`: packages Winlator-compatible `.wcp` archives

## Plain Wine Patch Set

Stored in `toolkit/android-wine-proton/patches/ref4ik-wine-bionic-2026-03-04/`:

- `0001` pulse Android mutex patch
- `0002` winex11 GLX env patch
- `0003` Pipetto-crypto esync patch
- `0004` ntdll locale workaround
- `0005` winevulkan `-Os` link fix

## Notes

- `toolkit/android-wine-proton/latest.json` now tracks both artifact families separately.
- The Proton flow is based on the working structure from `Pepelespooder/proton-arm64-nightlies`.
- The plain Wine flow keeps the `wine-bionic` source fixes while moving the CI logic into this shared workflow.
