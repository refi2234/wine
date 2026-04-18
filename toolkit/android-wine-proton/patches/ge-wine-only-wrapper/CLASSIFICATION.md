# GE Patch Classification

First-pass classification for the extracted GE wrapper Wine patch bundle.

Scope:
- Target runtime: GameNative / Winlator on Android ARM64
- Goal: identify GE Wine-layer changes worth attempting after the Android/ARM64 patch chain
- This is a triage document, not a final compatibility guarantee

## Summary

### Candidate

These are plausible for GameNative because they affect Wine game behavior directly and do not obviously depend on desktop Steam runtime assumptions.

- `patches/proton/0001-fshack-Implement-AMD-FSR-upscaler-for-fullscreen-hac.patch`
  - Reason: fullscreen hack / Vulkan upscaling in `win32u`, game-facing behavior, no obvious Steam dependency.
  - Risk: medium. Large patch, likely drift-prone, may interact with Android X11/window assumptions.

- `patches/proton/83-nv_low_latency_wine.patch`
  - Reason: `winevulkan` low-latency support, game-facing runtime behavior.
  - Risk: medium. Vendor-specific and useful only where host/translation stack exposes the feature.

- `patches/proton/0001-win32u-add-env-switch-to-disable-wm-decorations.patch`
  - Reason: small `win32u` env-gated behavior tweak. Could help borderless/window issues.
  - Risk: low.

- `patches/proton/fix-a-crash-in-ID2D1DeviceContext-if-no-target-is-set.patch`
  - Reason: likely pure stability fix in D2D path.
  - Risk: low.

- `patches/proton/0001-ntdll-Downgrade-using-kernel-write-watches-from-MESS.patch`
  - Reason: logging/noise reduction only. Safe if desired.
  - Risk: low, low value.

- `patches/game-patches/dai_xinput.patch`
  - Reason: targeted game fix in `win32u/input.c`, directly relevant to controller behavior.
  - Risk: medium. Very game-specific and hacky, but potentially useful.

- `patches/game-patches/pso2_hack.patch`
  - Reason: targeted workaround in Wine file behavior for one game.
  - Risk: medium. Specific, but self-contained.

- `patches/game-patches/vgsoh.patch`
  - Reason: targeted current-directory workaround for one game.
  - Risk: low to medium.

- `patches/game-patches/assettocorsa-hud.patch`
  - Reason: targeted UI/gameplay fix.
  - Risk: medium.

- `patches/game-patches/lemansultimate-gameinput.patch`
  - Reason: targeted input/game fix.
  - Risk: medium.

- `patches/wine-hotfixes/pending/unity_crash_hotfix.patch`
  - Reason: pure crash fix category, likely valuable if still relevant.
  - Risk: medium pending drift review.

- `patches/wine-hotfixes/pending/registry_RRF_RT_REG_SZ-RRF_RT_REG_EXPAND_SZ.patch`
  - Reason: compatibility fix for registry behavior, likely self-contained.
  - Risk: low to medium.

- `patches/wine-hotfixes/pending/ntdll_add_wine_disable_sfn.patch`
  - Reason: env-gated behavior, compatibility-focused.
  - Risk: medium.

- `patches/wine-hotfixes/pending/NCryptDecrypt_implementation.patch`
  - Reason: game login / crypto compatibility fix.
  - Risk: medium to high because implementation patches can be broad.

- `patches/wine-hotfixes/pending/webview2.patch`
  - Reason: modern launcher/game compatibility is increasingly WebView-dependent.
  - Risk: medium to high. Big surface area and may need follow-up pieces.

- `patches/wine-hotfixes/staging/cryptext-CryptExtOpenCER/0001.patch`
  - Reason: targeted staging-derived compatibility fix.
  - Risk: low to medium.

- `patches/wine-hotfixes/staging/wineboot-ProxySettings/0001.patch`
  - Reason: small staging-derived behavior fix. Could matter for launchers.
  - Risk: low.

### Needs Review

These patches may help, but they are likely to collide with Android/GameNative assumptions or rely on desktop Linux graphics/session behavior.

- `patches/wine-hotfixes/wine-wayland/*`
  - Reason: massive set aimed at Wine Wayland driver behavior.
  - For GameNative this is not an automatic reject, but it is high risk because your current Android stack patches `winex11.drv` and other non-Wayland assumptions.
  - Treat as a separate porting stream, not part of the initial GE import.

- `patches/proton/add-envvar-to-gate-media-converter.patch`
  - Reason: probably useful only if the corresponding Proton media-converter flow exists in your Android packaging.
  - Risk: medium. Wrapper/runtime coupling likely.

- `patches/proton/build_failure_prevention-add-nls.patch`
  - Reason: build-system-oriented, not runtime. Keep only if your toolchain still needs it.
  - Risk: low but low value.

### Reject For Initial GameNative Port

These should not be in the first GameNative GE patch stack because they are either too desktop-specific or belong to a different subsystem migration.

- Entire `wine-wayland` series for the first pass
  - Reason: too large and too coupled to Wayland-specific desktop driver behavior.
  - Revisit only after the baseline Android/X11-derived stack is stable.

- Any GE wrapper/runtime patch not copied into this Wine-only bundle
  - Reason: outside Wine tree, likely Steam/desktop runtime integration.

## Recommended Initial Apply Order

Start with the smallest, highest-signal subset:

1. `fix-a-crash-in-ID2D1DeviceContext-if-no-target-is-set.patch`
2. `0001-win32u-add-env-switch-to-disable-wm-decorations.patch`
3. `83-nv_low_latency_wine.patch`
4. selected pending hotfixes:
   - `unity_crash_hotfix.patch`
   - `registry_RRF_RT_REG_SZ-RRF_RT_REG_EXPAND_SZ.patch`
   - `NCryptDecrypt_implementation.patch`
   - `webview2.patch`
5. selected game patches only when targeting those titles
6. `0001-fshack-Implement-AMD-FSR-upscaler-for-fullscreen-hac.patch` last

## Immediate Recommendation

Do not try to import all 197 files into GameNative.

Build a first filtered stack around:
- the four small general-purpose Proton/Wine patches
- the pending hotfixes with broad compatibility value
- no wine-wayland series yet
- no per-game hacks unless you are chasing that specific title

## Wayland Decision

Wayland-specific work is out of scope for this GameNative port.

Decision:
- treat the entire `patches/wine-hotfixes/wine-wayland/` tree as excluded
- do not port `winewayland-*`, Wayland-specific `kernelbase` hacks, Wayland monitor/output handling, or mixed patches bundled only through that series
- if a generic non-Wayland patch exists only inside that folder, re-evaluate it later as an explicit one-off import, not as part of a Wayland batch

## Updated Recommended First Filter

Keep the first filter limited to non-Wayland GE patches:

1. `fix-a-crash-in-ID2D1DeviceContext-if-no-target-is-set.patch`
2. `0001-win32u-add-env-switch-to-disable-wm-decorations.patch`
3. `83-nv_low_latency_wine.patch`
4. selected pending hotfixes:
   - `unity_crash_hotfix.patch`
   - `registry_RRF_RT_REG_SZ-RRF_RT_REG_EXPAND_SZ.patch`
   - `NCryptDecrypt_implementation.patch`
   - `webview2.patch`
5. optionally `0001-fshack-Implement-AMD-FSR-upscaler-for-fullscreen-hac.patch` later, after the smaller set builds cleanly

## Excluded For Now

- entire `patches/wine-hotfixes/wine-wayland/` directory
- `patches/proton/add-envvar-to-gate-media-converter.patch`
- `patches/proton/build_failure_prevention-add-nls.patch`
- all per-game hacks unless you are targeting that exact title
