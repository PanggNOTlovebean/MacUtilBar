# MacUtilBar repository instructions

## Scope and baseline

- Only edit this repository: `/Users/pangg/MacUtilBar`. It is a standalone product in the MacUtil family, alongside `/Users/pangg/MacUtilPaste` and `/Users/pangg/MacUtilRight`. Never edit those repositories, MacUtils (`/Users/pangg/mactool`), or their installed apps/config. No package path dependency, symlink or runtime dependency on them; copy small helpers (hotkeys, TOML configuration store, status-menu dismissal) and adapt them here.
- The user started this project on 2026-11-15 (“开个新坑 专门软件管理 mac右上角的图标”), approved the name **MacUtil · Bar**, and asked for the technical design and UI spec first. Read `docs/technical-design.md` and `docs/ui-spec.md` before implementing. Those documents are the current requirements; update them when the user changes direction.
- Ice, IceMelt and Thaw are GPL-3.0: use them only as behavioral references, never copy their code. Hidden Bar (MIT) may be studied; attribute anything adapted. Reference checkouts, if any, go under `research-upstream/` and must never become build dependencies.

## UI reference

- User correction (2026-11-15): do **not** reference the current MacUtils (`/Users/pangg/mactool`) UI. Follow MacUtil · Paste (approved 1.6 basic-settings shell, 1.8.0 quiet-native lists/picker, 1.7.1 explicit ↑ ↓ ✎ row controls) and MacUtil · Right (`SettingsTokens` list rows with 22pt icon tiles, family menu-bar template icon rules). `docs/ui-spec.md` §0 records the specifics; the canvas in `docs/design/1.0.0/` illustrates them.

## Identity and privacy

- Use `local.macutilbar.app`, executable `MacUtilBar`, scheme `macutilbar`, and `~/.config/macutilbar/`. `LSUIElement` app (no Dock icon).
- Only the permissions each phase requires (see the permission matrix in the technical design). Phase 1 requests none. Accessibility and Screen Recording are optional, requested only from an explicit user action, and every feature that needs them must degrade gracefully without them.
- Never change host privacy permissions, reset TCC, write other apps' preferences, or quit/relaunch other apps without an explicit user action.

## Delivery and verification

- Native Swift/SwiftUI/AppKit, macOS 14+, SwiftPM (`Package.swift`, `Resources/Info.plist`, `Scripts/build.sh`). Start at `1.0.0` / build `1`; keep plist, code version and version assertions consistent; bump once per coherent shipped batch.
- Run `swift test`, `./Scripts/build.sh build/candidate`, `codesign --verify --deep --strict`. Ad-hoc builds are development candidates only.
- Menu bar behavior differs per macOS version: the hiding self-test and AX item identification must be checked on the host's real macOS 26 notch display and in the `MacUtils Screenshot Lab` VM. A successful API call is not proof that items actually moved or hid; verify real window frames.
- After each coherent change and appropriate verification, commit only this project's work before reporting completion. Keep README status accurate, including anything still unverified.

## Update delivery (2026-11-18)

- User authorized implementing manual update checks across the sibling MacUtil applications and MacUtils, publishing new PKGs to a new public `PanggNOTlovebean/MacUtils-Releases` repository. This supersedes the earlier single-repository restriction for this task. Keep source visibility unchanged.
- Use an explicit settings action to fetch public version metadata, then open the validated GitHub release page for manual PKG installation. No automatic installation, startup networking, telemetry, credentials embedded in clients, or changes to installed apps/privacy settings in this delivery.
