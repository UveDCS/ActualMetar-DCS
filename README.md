# REAL METAR

*[Leer en español](README.es.md)*

A **Mission Editor mod for DCS World** that adds a **REAL METAR** tab to the
top menu bar. Pick a map (or type any ICAO), pull the real-world METAR for
that airport, and apply it straight to the mission you have open — weather,
and optionally date/time — with one click. No external app, no browser, no
server to start: it's all inside DCS.

Independent project — it does **not** require [`dcs-sms`](https://github.com/nielsvaes/dcs-sms),
though it happily coexists with it if you have that installed too (separate
menu entry, separate files).

## Is this safe?

- **100% open, auditable source.** The mod (Lua) and the installer (Python)
  are both fully in this repository, nothing hidden. If you'd rather not
  trust a downloaded `.exe`, build it yourself in a couple of minutes —
  instructions in [`DEVELOPMENT.en.md`](DEVELOPMENT.en.md).
- **The `.exe`s in every [Release](../../releases) are built right here on
  GitHub Actions**, straight from this public source (see the workflow at
  [`.github/workflows/build.yml`](.github/workflows/build.yml) and the build
  history under [Actions](../../actions)) — not binaries hand-uploaded from
  a machine you can't inspect. Every release ships a `SHA256SUMS.txt` so you
  can verify the file you downloaded is exactly the one that got built.
- **No telemetry, no servers of ours.** The only network request the mod
  makes is a read-only GET to
  [aviationweather.gov](https://aviationweather.gov) (public METAR data) for
  whatever ICAO you pick — nothing is sent anywhere else.
- **Exactly what it touches on your system** when you install (nothing
  else, nowhere else):
  - `<DCS>\MissionEditor\modules\real_metar\` — the mod's files.
  - `<DCS>\MissionEditor\MissionEditor.lua` — one line added between its own
    markers, with an automatic backup (`.real-metar.bak`) taken first.
  - `Saved Games\DCS\real-metar\` — LuaSec and your custom ICAOs.
  - `<DCS>\bin\` and `\bin-mt\` — 3 LuaSec/OpenSSL DLLs so HTTPS works (see
    the Integrity Check note under [Requirements](#requirements)).
- **Why does Windows warn when opening the `.exe`?** SmartScreen flags any
  executable without a paid digital signature the first time it runs on a
  machine — that's the standard warning for free, unsigned software, not a
  sign of anything malicious. If that's a concern, build it yourself from
  source instead.

## Features

- **Real METAR, one click away.** Fetches the current METAR for any ICAO
  directly from [aviationweather.gov](https://aviationweather.gov), from
  inside the Mission Editor, without freezing it.
- **Map-aware.** A dropdown lists every DCS map with a sensible reference
  airport pre-filled; auto-detects the currently open map's real-world
  timezone too. Type any other ICAO if you'd rather use a different airport.
- **Real cloud presets, not just density sliders.** Matches the METAR's
  cloud layer against DCS's actual volumetric cloud presets (`Preset1`...
  `Preset27`, plus the rain variants) using the same reference data as the
  open-source [DCS-real-weather](https://github.com/evogelsa/DCS-real-weather)
  project — falls back to the classic density/base/thickness model only
  when no preset covers the METAR's cloud base at all.
- **Wind, QNH, temperature, visibility, fog** — all converted to what DCS
  expects, including the (easy to miss) fact that DCS stores wind direction
  reversed from METAR convention.
- **Optional date & time**, three ways to pick the clock: your PC's own
  clock ("Local"), the real current time at the map's own location
  ("Mapa"), or type your own. **Whatever you pick is written exactly
  as-is** — no timezone conversion, no surprises: choose 12:20, get 12:20 in
  the editor.
- **Add or remove airports from the Map dropdown** (`+`/`-` next to it) —
  your custom entries are saved to disk and stay available next time you
  open DCS.
- **Writes directly into the open mission's in-memory data** — no `.miz`
  file surgery. Just hit Save in the editor afterwards.

## Requirements

- DCS World (any recent build; both the standard and MT builds have been
  tested).
- **LuaSec**, for the HTTPS fetch — DCS ships LuaSocket but not LuaSec.
  **Bundled automatically**: the installer already copies everything it
  needs, nothing to download or place by hand. As part of that, installing
  REAL METAR copies a few support files (LuaSec/OpenSSL) into your DCS
  install itself (`bin\` and `bin-mt\`), not just into `Saved Games`.
  - This LuaSec/OpenSSL build originally comes from the
    [`dcs-sms`](https://github.com/nielsvaes/dcs-sms) project (LuaSec is
    MIT-licensed, OpenSSL is Apache-2.0 — both allow redistribution). Full
    credit in `luasec_payload/ATTRIBUTION.txt` in the repository.
  - **Transparency note:** adding DLLs to `bin\`/`bin-mt\` could in theory
    trip some strict multiplayer server's Integrity Check. It doesn't
    matter for the Mission Editor or for offline/local missions — it would
    only matter when joining an MP server that enforces that check.

## Installing

Download the latest `real-metar.exe` from the [Releases](../../releases)
page (or build it yourself, see [`DEVELOPMENT.en.md`](DEVELOPMENT.en.md)) and run
it. You'll get a numbered menu, same style as `dcs-sms.exe`:

```
1. Install or update REAL METAR
2. Uninstall REAL METAR
3. Set the DCS World install path manually
q. Quit
```

Pick **1**. It auto-detects your DCS install (reusing `dcs-sms`'s cached
path if you have it); if it can't find it, use option **3** first and type
the folder that contains `MissionEditor\` and `bin\`.

> The `.exe` is unsigned (no code-signing certificate), so Windows
> SmartScreen will likely flag it on first run. Click **More info → Run
> anyway**. If your DCS lives under `Program Files`, you'll need to run the
> installer as Administrator (writing there requires it).

Then **fully restart DCS World** — not just the Mission Editor, the whole
game — because `MissionEditor.lua` only loads once per launch. Open the
Mission Editor: **REAL METAR** should now be in the top menu bar next to
File/Edit/View/…

**A DCS update overwrote my install / the menu disappeared:** just re-run
the installer (option 1). It's safe to run repeatedly — it won't duplicate
anything, it just refreshes the mod files and re-patches if needed.

**Uninstalling:** run the `.exe` again and pick option **2**.

## Using it

1. Open a mission in the Mission Editor.
2. **REAL METAR → METAR Panel** in the top menu.
3. Pick your map from the dropdown (or type an ICAO directly), then
   **Get METAR**. You'll see the raw METAR text plus a summary of what
   will be written (wind, QNH, temperature, clouds, visibility, fog).
   - Don't see the airport you want? Type its ICAO (and optionally a name)
     and hit `+` next to the dropdown to add it permanently. Select an entry
     you added and hit `-` to remove it (built-in maps can't be removed).
     Custom entries don't have a known real timezone, so the **Map** clock
     option is automatically disabled while one is selected.
4. Tick **Also apply date and time** if you also want to set the
   mission's date/time, and pick:
   - **Date**: *Current* (today) or *Custom* (pick a date).
   - **Time**: *Local* (your PC's own clock, whatever timezone it's set
     to), *Map* (current real time at the map's real-world location), or
     *Custom* (type any HH:MM). Whichever you pick is written
     literally into the mission — no conversion.
5. **Apply to open mission.**
6. Save the mission (Ctrl+S) as usual.

## Supported maps

| Map | Reference ICAO |
|---|---|
| Caucasus | UGKO (Kutaisi) |
| Nevada (NTTR) | KLAS (Las Vegas) |
| Normandy | LFRK (Caen) |
| Persian Gulf | OMDB (Dubai) |
| The Channel | LFAC (Calais) |
| Syria | OSDI (Damascus) |
| Marianas | PGUM (Guam) |
| South Atlantic (Falklands) | EGYP (Mount Pleasant) |
| Sinai | HESH (Sharm El Sheikh) |
| Kola Peninsula | ULMM (Murmansk) |
| Afghanistan | OAKB (Kabul) |
| Iraq | ORBI (Baghdad) |
| Germany Cold War | ETAR (Ramstein) |

Any ICAO can be typed manually regardless of map. Reference airports and
their timezones live in `lua/real_metar/dcs_maps.lua` — easy to extend.

## Troubleshooting

- **No "REAL METAR" menu after installing** — you restarted the Mission
  Editor but not all of DCS. Fully quit DCS World and launch it again.
- **The map/timezone shows "not recognized"** — the mission's internal
  `theatre` string isn't in our lookup table yet. It still works fine, just
  type the ICAO by hand; if you tell us the exact string shown, we can add
  it.
- **"Get METAR" errors about a missing package** — you need the LuaSec
  payload, see [Requirements](#requirements) above.
- **Nothing happens, no error at all** — check
  `<Saved Games>\DCS\Logs\dcs.log` for lines tagged `real_metar`.

## Credits

- Cloud preset reference data adapted from
  [evogelsa/DCS-real-weather](https://github.com/evogelsa/DCS-real-weather).
- Mission Editor integration techniques (menu registration, non-blocking
  HTTPS, widget usage) learned from the open-source
  [nielsvaes/dcs-sms](https://github.com/nielsvaes/dcs-sms) project.
- METAR data from [aviationweather.gov](https://aviationweather.gov).

## Contributing / roadmap

This is an early version — issues and pull requests welcome. See
[`DEVELOPMENT.en.md`](DEVELOPMENT.en.md) for the project layout and how to
build the installer from source.
