# Development notes

(Internal technical documentation. The public READMEs —
[`README.md`](README.md) / [`README.es.md`](README.es.md) — are meant for
people who just want to install and use the mod.)

## Structure

```
install.ps1              — installer/uninstaller (script, for development, always ES)
installer/
  installer.py            — .exe installer (Spanish) — bundles lua/actual_metar
  installer_en.py          — .exe installer (English) — bundles lua_en/actual_metar
  dist/actual-metar.exe       — compiled ES binary (PyInstaller, onefile)
  dist/actual-metar-en.exe    — compiled EN binary
luasec_payload/             — precompiled LuaSec/OpenSSL, bundled into both .exe (see below)
  ATTRIBUTION.txt            — provenance and licenses
  lib/                       — ssl.lua, ssl/https.lua, cacert.pem, ssl.dll -> modules\actual_metar\lib\ (and Saved Games, compat)
  bin/                       — libcrypto-4-x64.dll, libssl-4-x64.dll, lua5.1.dll -> <DCS>\bin\ and \bin-mt\
ovgme/                       — no-.exe install alternative (see below)
  build_ovgme_packages.ps1   — builds the two OvGME zips (ES/EN)
  OVGME_LEEME.txt / OVGME_README.txt — instructions for the one manual step
lua/actual_metar/            — mod, SPANISH UI (original)
lua_en/actual_metar/          — mod, ENGLISH UI (translation — see below)
  init.lua                 — bootstrap (loaded from MissionEditor.lua)
  menu.lua                 — "ACTUAL METAR" menu entry
  window.lua                — panel (UI)
  ticker.lua                — pumps the async fetch on every UpdateManager tick
  https_transport.lua       — non-blocking HTTPS GET (LuaSocket+LuaSec)
  lib_path.lua              — locates the LuaSec payload
  metar_fetch.lua           — orchestrates download + calculation (coroutine)
  json.lua                  — minimal JSON decoder
  weather_calc.lua          — METAR -> DCS field translation
  cloud_presets.lua         — DCS cloud preset table
  mission_datetime.lua      — date/time calculation (no final UTC conversion, see below)
  mission_apply.lua         — writes into the in-memory mission table
  dcs_maps.lua               — ICAO + timezone per map (built-in)
  custom_maps.lua            — user-added/removed ICAOs (persisted)
  paths.lua                  — resolves <Saved Games>\DCS\ (shared by lib_path and custom_maps)
```

The distribution packages (`Instalacion-ES.zip`, `Installation-EN.zip`,
`ActualMetar-ES-OvGME.zip`, `ActualMetar-EN-OvGME.zip`) are no longer kept
in the repo or built by hand — `.github/workflows/build.yml` builds them
on every tag and publishes them as a Release.

## `lua/` vs `lua_en/`: two translated copies, not one with i18n

These are two **parallel, functionally identical** file trees — same code,
only the comments and the strings the user sees change (labels, buttons,
status messages, the installer's console). There's no internationalization
system (string tables, `gettext`, etc.) — that was a deliberate choice to
keep each tree simple and self-contained, at the cost of having to apply
any logic change **twice** (once in `lua/`, once in `lua_en/`). If a bug is
fixed or a feature is added, it has to be mirrored in the other language
before the task is considered done — this actually happened with the
`mission_apply.lua` fix (clouds with no preset field on new missions),
fixed first in `lua/` and mirrored into `lua_en/` in the same session.

The modules' internal namespace (`actual_metar.*`) and the install folder
name (`MissionEditor\modules\actual_metar\`) are the same in both languages —
a user installs one or the other, never both at once, and the
`MissionEditor.lua` marker (see below) is intentionally the same text so
switching languages is just "run the other installer," with no leftovers
from the previous one.

## Building the `.exe`s

```powershell
cd installer
python -m pip install pyinstaller

# Spanish (bundles lua/actual_metar + luasec_payload):
python -m PyInstaller --onefile --console --name actual-metar --add-data "..\lua\actual_metar;actual_metar" --add-data "..\luasec_payload;luasec" --distpath .\dist --workpath .\build --specpath . installer.py

# English (bundles lua_en/actual_metar + luasec_payload):
python -m PyInstaller --onefile --console --name actual-metar-en --add-data "..\lua_en\actual_metar;actual_metar" --add-data "..\luasec_payload;luasec" --distpath .\dist --workpath .\build_en --specpath . installer_en.py
```

The `.lua` files and the LuaSec payload get bundled inside the `.exe`
itself (extracted to `sys._MEIPASS` at runtime, under subfolders
`actual_metar` and `luasec` — same names for both languages). Nothing else
needs to be distributed alongside the executable: running it leaves DCS
ready for HTTPS, no manual steps.

**IMPORTANT**: `install.ps1`, `installer/installer.py`, and
`installer/installer_en.py` all use the exact same marker text in
`MissionEditor.lua`
(`-- ACTUAL-METAR-BEGIN (no editar a mano; gestionado por install.ps1)`,
**left untranslated** on purpose — see the previous section) so each can
detect whether another one already patched the file. If that text changes
in one place, it has to change in the other three too — otherwise one
installer won't recognize the other's patch and will duplicate the
`require`. This actually happened during development (with `installer.py`
and `install.ps1` before the text was synced).

## Test status

This project was built and tested at two very different layers:

- **All the calculation logic** (`json.lua`, `cloud_presets.lua`,
  `weather_calc.lua`, `mission_datetime.lua`, `mission_apply.lua`,
  `dcs_maps.lua`) is **genuinely tested**, with a real Lua 5.1 interpreter
  (the same version DCS uses) outside the game, with its results checked
  field by field against `metar-dcs-app` (the earlier Python version,
  already validated in real use) — including DST transition edge cases
  (EU/US) and rain-preset matching. All files also pass a Lua syntax check.
- **The Mission Editor integration** (`window.lua`, `menu.lua`,
  `https_transport.lua`, `ticker.lua`) closely follows techniques already
  proven in production by the `dcs-sms` project (`nielsvaes/dcs-sms`, open
  source) — menu registration via `me_menubar`, `Window`/`Static`/
  `EditBox`/`Button`/`CheckBox`/`ComboList` widgets, non-blocking HTTPS via
  LuaSocket+LuaSec — and **has already been confirmed working end-to-end**
  on a real machine (fetch, apply, map dropdown, date/time checkboxes)
  after a joint debugging session.

## Real bug fixed: cloud presets on new/blank missions

Reported during a real test: a freshly-created mission (not a previously
saved one) may not have the `["preset"]` key in `mission.weather.clouds`
yet (the editor's native Weather dialog was never opened for it).
`mission_apply.lua` originally only WROTE the computed preset if that key
already existed, falling back to the dynamic model otherwise — with a
warning note. Fixed by always writing `clouds.preset`, whether the key
existed or not: adding a key to a Lua table is safe, and DCS only reads the
keys it knows about, so the fallback (and its note) are no longer needed.
Applied in `lua/actual_metar/mission_apply.lua` and mirrored into `lua_en/`.

## Date/time: deliberate decision not to convert to UTC

DCS stores `mission.start_time` in seconds since midnight **UTC/Zulu**
(confirmed by inspecting the `pydcs/dcs` project). However, per an explicit
request, the mod does **not** convert the chosen time to UTC before writing
it: it writes the chosen local time (Local/Map/Custom) as-is, literally,
into `start_time`. If the astronomically-correct conversion is ever wanted
back (so the editor shows the map's real solar time instead of a literal
value), it's in `mission_datetime.lua`'s history.

We still need to resolve "what time is it right now" at the chosen map for
the "Map" mode, and that does require handling real timezones with their
DST rules — implemented by hand in `mission_datetime.lua` (EU and US rules)
because Lua has no zoneinfo/tzdata. The "Local" mode (formerly "Península")
no longer uses any timezone table at all: it reads `os.date("*t")` directly
without the `"!"` prefix, i.e. whatever time Windows has configured on that
PC. It requires no administrator permissions (reading the system clock
never does).

## Custom ICAOs (`custom_maps.lua`)

The "Map" dropdown has `+`/`-` buttons to add or remove entries without
touching code. They're saved to
`<Saved Games>\DCS\actual-metar\custom_icaos.lua`, a plain Lua file
(`return { {name=, icao=, std_offset_h=, rule=}, ... }`) read/written with
`loadfile`/`io.open` — same style `dcs-sms` uses for its own settings
(`me_hotkeys.lua`, `me_scripts.lua`). ICAOs added this way have no known
real timezone (there's no way to guess which airport a hand-typed ICAO
belongs to) — they're saved with `std_offset_h=0, rule="none"` (UTC) by
default; if the user knows the real zone, they can hand-edit the file while
DCS is closed. Built-in maps (`dcs_maps.lua`) can't be removed from the
panel — the `-` button only acts on entries flagged `is_builtin = false`.

The "Name" field next to the ICAO is optional: if left blank,
`custom_maps.add(icao, name)` defaults to `"Custom (ICAO)"`.

Since a custom entry has no known real timezone, `window.lua` disables the
"Map" checkbox and label in the Time section as soon as one is selected in
the dropdown (`entry.is_builtin == false`), and if "Map" was active at that
moment it automatically jumps to "Local" (`select_time_mode`, returned by
`wire_radio_group` so the selection can be forced from code and not just
from a checkbox click).

## Maps and timezones

`dcs_maps.lua` defines, per map, `{standard_offset_hours, rule}` where
`rule` is `"none"` (no DST), `"eu"` (last Sunday of March/October), or
`"us"` (2nd Sunday of March / 1st Sunday of November). Auto-detecting the
open map uses `mission.theatre` — the real `theatre` → `dcs_maps.lua` entry
mapping lives in `M.THEATRE_TO_ID`; if a map isn't recognized, the window
shows the real `theatre` string so it can be added.

Known limitation: the Falklands do observe southern-hemisphere DST
(Sep-Apr) that isn't modeled — its standard offset is used year-round.

## Project rename: "REAL METAR" -> "ACTUAL METAR"

Explicit user decision, no technical reason behind it. The rename touched
**everything**: the Lua namespace (`real_metar` -> `actual_metar`, folders
`lua/real_metar/` -> `lua/actual_metar/` and same for `lua_en/`), the
`MissionEditor.lua` marker (`REAL-METAR-BEGIN/END` ->
`ACTUAL-METAR-BEGIN/END`), the data folder under
`Saved Games\DCS\real-metar\` -> `\actual-metar\`, the installer's own
config folder (`%AppData%\real-metar\` -> `\actual-metar\`), the visible
menu/panel text in the Mission Editor, and the GitHub repository
(<https://github.com/UveDCS/ActualMetar-DCS>).

**Migrating existing installs** (important: the user already had this
genuinely installed on their `F:\DCS World` before the rename): all three
installers (`installer.py`, `installer_en.py`, `install.ps1`) keep
`OLD_BEGIN_MARKER`/`OLD_END_MARKER` constants (the old `REAL-METAR-...`
text) purely to detect and clean up previous installs, never to generate
them. `install()`/`Install-LuaSec` gained, in this order:

1. If `MissionEditor\modules\real_metar\` (old folder) exists, delete it
   before creating the new `modules\actual_metar\`.
2. If `MissionEditor.lua` has the old `REAL-METAR-BEGIN/END` block, remove
   it **before** checking/adding the new block (otherwise both `require`
   calls would end up present at once: `real_metar.init` AND
   `actual_metar.init`).
3. If `Saved Games\DCS\real-metar\` exists and `\actual-metar\` does
   **not** exist yet, **move** the whole folder (not copy-then-delete) —
   this preserves `custom_icaos.lua` (user data) untouched, and `lib\` gets
   overwritten right after with the bundled payload anyway. If both folders
   already exist (repeated reinstall), neither is touched — the new one is
   assumed authoritative and the old one is left alone just in case.

Tested end-to-end in an isolated sandbox that reproduces the exact prior
real state (old marker + `modules\real_metar\` with a file + a
`Saved Games\...\real-metar\` with `custom_icaos.lua` and an old `ssl.lua`):
after `install()`, the old modules folder is gone, the new marker appears
exactly once (the old one, zero times), `custom_icaos.lua` survives with its
content intact, and `lib\` ends up with the real payload (not the dummy
`ssl.lua`). See the safe-testing discipline below.

`VERSION` bumped to `0.2.0` (a rename is a naming-compatibility-breaking
change, even though migration makes it transparent to the user).

## Reproducible CI builds (`.github/workflows/build.yml`)

Pushing a `v*` tag runs GitHub Actions (`windows-latest` runner) through the
exact same PyInstaller commands from the section above, packages both
distribution `.zip`s, computes `SHA256SUMS.txt`, and publishes everything as
a Release via `gh release create --generate-notes`. This is deliberate, not
just convenience: it means anyone can verify the `.exe` they download is
exactly what got built from this repo's public source (see the Actions tab
for the build history), instead of having to trust a binary hand-compiled
on a machine nobody else can inspect — see the "Is this safe?" section in
the public READMEs. Don't build and upload releases by hand unless the
workflow is broken; fix the workflow first instead of working around it.

## Bundled LuaSec: why and where it's from

Explicit user decision: "I don't want anyone doing a second manual step to
install this — running the exe should be enough." Before this, the README
asked people without `dcs-sms` to manually download `payload/` from its
repo — it worked, but was real friction for anyone who didn't already have
that mod.

The 7 files in `luasec_payload/` were copied **straight from the user's own
working `dcs-sms` install** (`Saved Games\DCS\dcs-sms\lib\` and
`F:\DCS World\bin\`) — i.e. a build already confirmed working in
production, not something compiled from scratch. `libcrypto-1_1-x64.dll`
was deliberately excluded: that one ships with DCS itself, it isn't part of
the LuaSec payload `dcs-sms` adds.

Licenses that allow this redistribution: LuaSec (MIT), OpenSSL
(Apache-2.0), Lua 5.1 (MIT), cacert.pem (MPL-2.0) — the same reasoning
`dcs-sms` itself uses to justify shipping this precompiled build in its own
public repo. Credit and detail live in `luasec_payload/ATTRIBUTION.txt`.

`install_luasec()` (same name in `installer.py`/`installer_en.py`,
`Install-LuaSec` in `install.ps1`) does two copies:
- `luasec_payload/lib/*` → `Saved Games\DCS\actual-metar\lib\` (recursive,
  because of `ssl/https.lua`). `lib_path.lua` already looked here first
  before falling back to `dcs-sms\lib\`, so no `.lua` needed changing.
- `luasec_payload/bin/*` → `<DCS>\bin\` and `<DCS>\bin-mt\`, whichever
  exist. This part is new: we never used to write outside `Saved Games`
  before. The Saved Games path is resolved by reusing `dcs-sms`'s cached
  `saved_games` value from `config.toml` when present (note: it comes
  escaped as `\\` in the TOML, needs un-escaping), otherwise guessing
  `Saved Games\DCS` or `DCS.openbeta` based on whether the DCS path
  contains "openbeta".

Risk explicitly accepted by the user: some MP servers' Integrity Check
could in theory flag these new DLLs in `bin\`. Full reasoning (why this
hasn't caused real problems in practice) is in the public READMEs'
"Requirements" section.

Uninstalling still doesn't touch `Saved Games\DCS\actual-metar\lib\` or the
`bin\`/`bin-mt\` DLLs — same convention `dcs-sms` already follows of not
deleting anything that looks like user data on uninstall. Nobody has asked
for the opposite.

## OvGME package: a no-`.exe` alternative (`ovgme/`)

Motivation: a real user (Max) reported their antivirus (Avast) flagged the
`.exe` as suspicious during install — same underlying problem as the
Defender ML detections documented below. Rather than wait solely on
SignPath signing, an install path was added that depends on no compiled
executable at all: a package for
[OvGME](https://wiki.hoggitworld.com/view/OVGME)/JSGME, which only copies
plain files inside the DCS folder (nothing an antivirus could mistake for
a dropper).

**Architecture change needed to make this work**: OvGME can only manage
one target folder (the DCS install), it can't touch `Saved Games`. Before
this, the LuaSec payload lived in `Saved Games\DCS\actual-metar\lib\`,
outside the reach of a single OvGME package. `lib_path.lua` (both
languages) was changed to look **inside its own module folder** first
(`MissionEditor\modules\actual_metar\lib\`), computed via
`debug.getinfo(1, "S").source` instead of assuming a fixed path — so it
works the same whether the mod arrived via the `.exe` or was copied by
hand via OvGME. The full search order is now: (1) own module folder, (2)
`Saved Games\...\actual-metar\lib\` (compatibility with `.exe` installs
from before this change), (3) `Saved Games\...\dcs-sms\lib\` (reuse
dcs-sms's payload). `install_luasec()` in all three installers now copies
the payload to **both of the first two locations at once**, so installing
via the `.exe` leaves things ready for either resolution path. Tested with
the local Lua 5.1 interpreter simulating OvGME's folder layout (with a
fake `lfs`) before touching the installers.

**The one thing OvGME can't automate**: the `MissionEditor.lua` patch.
Shipping a full replacement of that file was ruled out (it goes stale on
DCS updates, and clobbers `dcs-sms`'s own patch if the user has that too)
— instead, the package ships an `OVGME_LEEME.txt`/`OVGME_README.txt` with
the exact 3 lines to paste by hand, once (same `ACTUAL-METAR-BEGIN/END`
marker the other installers use, so it's indistinguishable from an
automatic patch).

`ovgme/build_ovgme_packages.ps1` builds the two zips
(`ActualMetar-ES-OvGME.zip` / `ActualMetar-EN-OvGME.zip`): each mirrors
`MissionEditor\modules\actual_metar\` (including `lib\`) + `bin\` +
`bin-mt\` + `version.txt` + the instructions file, with the zip's top-level
folder named exactly like the zip itself (OvGME's mandatory naming rule).
Called both by hand during development and by
`.github/workflows/build.yml` on every tag — same reproducible process as
the `.exe`s. Known quirk: if the user's DCS install isn't the MT build,
the package still creates a `bin-mt\` folder with 3 unused DLLs (harmless,
DCS never reads it if it doesn't need it) — a limitation of OvGME's
"folder mirror" model, which can't conditionally skip copying based on
whether `bin-mt\` already exists.

## Caution when testing the installers on this machine

DCS path auto-detection (sweeping `<drive>:\DCS World` across every drive)
doesn't distinguish "test mode" — it finds the machine's real install just
as readily as a real one. During development this actually caused a test
to accidentally touch the real install (it deleted the modules folder and
came close to duplicating the patch). When testing either installer
against a fake folder, always seed `%AppData%\actual-metar\config.json` with
a clearly fake path *before* running it, and verify with a debug call to
`resolve_dcs_path()` that it returns that fake path before letting the
installer touch anything.

**Since `install_luasec()` was added, the risk is bigger**: on top of
writing into the fake DCS path, it now also writes into `bin\`/`bin-mt\`
under that same fake path, and into a separately-resolved Saved Games
folder (`resolve_saved_games_dir()`/`Find-SavedGamesPath`). Before testing
`install()`/`install_luasec()`, also verify that `resolve_saved_games_dir()`
returns a test path (not the real `Saved Games\DCS`) — e.g. by passing it
an explicit fake path or testing that function in isolation, not just
`resolve_dcs_path()`.
