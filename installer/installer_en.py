"""ACTUAL METAR - interactive installer for the DCS World Mission Editor mod.

Mirrors dcs-sms.exe's menu style: a standalone .exe (built with PyInstaller)
that needs nothing else alongside it - the mod's Lua files are bundled
inside.

Normal use: double-click. Opens a numbered menu in the console.

This is the ENGLISH build: it bundles lua_en/actual_metar (the English UI
translation of the mod) instead of lua/actual_metar (Spanish, original).
"""

import json
import os
import shutil
import sys

VERSION = "0.2.0"

# IMPORTANT: this text must be IDENTICAL to install.ps1's marker (and to
# installer.py's, the Spanish build) - not translated. Both language
# installers target the same require('actual_metar.init') line, so keeping
# one shared marker means installing one language over the other just
# refreshes the module files instead of duplicating the require.
BEGIN_MARKER = "-- ACTUAL-METAR-BEGIN (no editar a mano; gestionado por install.ps1)"
END_MARKER = "-- ACTUAL-METAR-END"

# Old names (the project used to be called "REAL METAR"). Only used to
# migrate existing installs to the new names; never generated anymore.
OLD_BEGIN_MARKER = "-- REAL-METAR-BEGIN (no editar a mano; gestionado por install.ps1)"
OLD_END_MARKER = "-- REAL-METAR-END"

CONFIG_DIR = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "actual-metar")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.json")

DCS_SMS_CONFIG = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "dcs-sms", "config.toml")


def bundled_lua_dir():
    """Folder with the mod's .lua files: inside the packaged .exe
    (PyInstaller onefile unpacks it to sys._MEIPASS), or the repo's actual
    lua_en/actual_metar files (no copy of our own) when run as a plain script
    in development."""
    base = getattr(sys, "_MEIPASS", None)
    if base:
        return os.path.join(base, "actual_metar")
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(here, "..", "lua_en", "actual_metar")


def bundled_luasec_dir():
    """Folder with the LuaSec/OpenSSL payload bundled in the installer (see
    luasec_payload/ATTRIBUTION.txt): same pattern as bundled_lua_dir()."""
    base = getattr(sys, "_MEIPASS", None)
    if base:
        return os.path.join(base, "luasec")
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(here, "..", "luasec_payload")


def load_config():
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_config(cfg):
    try:
        os.makedirs(CONFIG_DIR, exist_ok=True)
        with open(CONFIG_PATH, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2)
    except OSError:
        pass


def is_dcs_path(path):
    return path and os.path.isfile(os.path.join(path, "MissionEditor", "MissionEditor.lua"))


def read_dcs_sms_path():
    try:
        with open(DCS_SMS_CONFIG, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("dcs_install"):
                    value = line.split("=", 1)[1].strip().strip('"')
                    return value.replace("/", "\\")
    except OSError:
        pass
    return None


def read_dcs_sms_saved_games():
    try:
        with open(DCS_SMS_CONFIG, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("saved_games"):
                    value = line.split("=", 1)[1].strip().strip('"')
                    return value.replace("\\\\", "\\").replace("/", "\\")
    except OSError:
        pass
    return None


def resolve_saved_games_dir(dcs_path):
    """<Saved Games>\\DCS(.openbeta)\\ - reuses dcs-sms's cached value if
    present, otherwise guesses based on whether the install is OpenBeta."""
    cached = read_dcs_sms_saved_games()
    if cached and os.path.isdir(cached):
        return cached

    home = os.environ.get("USERPROFILE", os.path.expanduser("~"))
    root = os.path.join(home, "Saved Games")
    is_beta = bool(dcs_path) and "openbeta" in dcs_path.lower()
    order = ["DCS.openbeta", "DCS"] if is_beta else ["DCS", "DCS.openbeta"]
    candidates = [os.path.join(root, name) for name in order]
    for c in candidates:
        if os.path.isdir(c):
            return c
    return candidates[0]


def autodetect_dcs_path():
    candidates = [
        os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "Eagle Dynamics", "DCS World"),
        os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "Eagle Dynamics", "DCS World OpenBeta"),
        os.path.join(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"), "Eagle Dynamics", "DCS World"),
        os.path.join(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"), "Eagle Dynamics", "DCS World OpenBeta"),
    ]
    for c in candidates:
        if is_dcs_path(c):
            return c

    dcs_sms_path = read_dcs_sms_path()
    if is_dcs_path(dcs_sms_path):
        return dcs_sms_path

    import string
    for letter in string.ascii_uppercase:
        drive = f"{letter}:\\"
        if os.path.isdir(drive):
            candidate = os.path.join(drive, "DCS World")
            if is_dcs_path(candidate):
                return candidate
    return None


def resolve_dcs_path():
    cfg = load_config()
    cached = cfg.get("dcs_install")
    if is_dcs_path(cached):
        return cached
    found = autodetect_dcs_path()
    if found:
        cfg["dcs_install"] = found
        save_config(cfg)
    return found


def prompt_manual_path():
    print()
    raw = input("DCS World install path (the one containing MissionEditor\\): ").strip()
    raw = raw.strip('"')
    if not raw:
        print("Empty, nothing changed.")
        return None
    if not is_dcs_path(raw):
        print(f"WARNING: MissionEditor\\MissionEditor.lua not found in: {raw}")
        confirm = input("Save anyway? [y/N]: ").strip().lower()
        if confirm != "y":
            return None
    cfg = load_config()
    cfg["dcs_install"] = raw
    save_config(cfg)
    print(f"Path saved: {raw}")
    return raw


def install_luasec(dcs_path):
    """Copies the bundled LuaSec/OpenSSL payload so HTTPS fetches work with no
    manual steps (see luasec_payload/ATTRIBUTION.txt for provenance and
    licenses). lib/ -> Saved Games\\DCS\\actual-metar\\lib\\; bin/ -> <DCS>\\bin\\
    and \\bin-mt\\ (whichever exist)."""
    payload = bundled_luasec_dir()
    lib_src = os.path.join(payload, "lib")
    bin_src = os.path.join(payload, "bin")
    if not os.path.isdir(lib_src) or not os.path.isdir(bin_src):
        print("WARNING: the LuaSec payload bundled with the installer wasn't found;")
        print("the HTTPS fetch may not work.")
        return

    saved_games = resolve_saved_games_dir(dcs_path)
    own_dir = os.path.join(saved_games, "actual-metar")
    old_own_dir = os.path.join(saved_games, "real-metar")
    if os.path.isdir(old_own_dir) and not os.path.isdir(own_dir):
        shutil.move(old_own_dir, own_dir)
        print(f"Old 'real-metar' folder migrated to 'actual-metar': {own_dir}")

    lib_dst = os.path.join(own_dir, "lib")
    for root, _dirs, files in os.walk(lib_src):
        rel = os.path.relpath(root, lib_src)
        dst_root = lib_dst if rel == "." else os.path.join(lib_dst, rel)
        os.makedirs(dst_root, exist_ok=True)
        for name in files:
            shutil.copy2(os.path.join(root, name), os.path.join(dst_root, name))
    print(f"LuaSec (HTTPS) installed to: {lib_dst}")

    bin_dirs = [os.path.join(dcs_path, "bin"), os.path.join(dcs_path, "bin-mt")]
    installed_bin = [bd for bd in bin_dirs if os.path.isdir(bd)]
    for bd in installed_bin:
        for name in os.listdir(bin_src):
            shutil.copy2(os.path.join(bin_src, name), os.path.join(bd, name))
    if installed_bin:
        print("OpenSSL dependencies copied to: " + ", ".join(installed_bin))
    else:
        print("WARNING: couldn't find DCS's bin\\/bin-mt\\ folders; the HTTPS fetch")
        print("may not work.")


def install(dcs_path):
    if not dcs_path:
        print("No valid DCS World path. Use option 3 first.")
        return

    me_lua = os.path.join(dcs_path, "MissionEditor", "MissionEditor.lua")
    modules_dir = os.path.join(dcs_path, "MissionEditor", "modules", "actual_metar")
    old_modules_dir = os.path.join(dcs_path, "MissionEditor", "modules", "real_metar")
    source_dir = bundled_lua_dir()

    if not os.path.isdir(source_dir):
        print(f"ERROR: the mod's Lua files can't be found ({source_dir}).")
        return
    if not os.path.isfile(me_lua):
        print(f"ERROR: MissionEditor.lua not found at: {me_lua}")
        return

    if os.path.isdir(old_modules_dir):
        shutil.rmtree(old_modules_dir)
        print(f"Old 'real_metar' folder removed (project renamed to 'actual_metar'): {old_modules_dir}")

    os.makedirs(modules_dir, exist_ok=True)
    copied = 0
    for name in os.listdir(source_dir):
        if name.endswith(".lua"):
            shutil.copy2(os.path.join(source_dir, name), os.path.join(modules_dir, name))
            copied += 1
    print(f"Lua files copied to: {modules_dir} ({copied} files)")

    with open(me_lua, "r", encoding="utf-8", errors="surrogateescape") as f:
        content = f.read()

    old_start = content.find(OLD_BEGIN_MARKER)
    old_end = content.find(OLD_END_MARKER)
    if old_start != -1 and old_end != -1:
        old_end += len(OLD_END_MARKER)
        content = content[:old_start] + content[old_end:]
        with open(me_lua, "w", encoding="utf-8", errors="surrogateescape") as f:
            f.write(content)
        print("Old REAL-METAR block removed from MissionEditor.lua (project renamed to ACTUAL-METAR).")

    if BEGIN_MARKER not in content:
        backup = me_lua + ".actual-metar.bak"
        if not os.path.isfile(backup):
            shutil.copy2(me_lua, backup)
            print(f"Backup created: {backup}")
        block = f"\n{BEGIN_MARKER}\nrequire('actual_metar.init')\n{END_MARKER}\n"
        with open(me_lua, "a", encoding="utf-8", errors="surrogateescape") as f:
            f.write(block)
        print("MissionEditor.lua patched (require added).")
    else:
        print("MissionEditor.lua already had the ACTUAL METAR require (left untouched).")

    print()
    install_luasec(dcs_path)

    print()
    print("Install complete.")
    print("FULLY restart DCS World (not just the Mission Editor) and open the editor:")
    print("ACTUAL METAR should now be in the top menu bar.")
    print()
    print("Note: a few support files (LuaSec/OpenSSL) were copied into your DCS install")
    print("('bin\\' and 'bin-mt\\') so the HTTPS fetch works with no extra steps. They come")
    print("from a third-party build (dcs-sms project, MIT/Apache-2.0 licenses), see")
    print("luasec_payload/ATTRIBUTION.txt. Some multiplayer servers with a strict Integrity")
    print("Check could in theory flag them; this doesn't affect the Mission Editor or")
    print("offline/local missions.")


def uninstall(dcs_path):
    if not dcs_path:
        print("No valid DCS World path. Use option 3 first.")
        return

    me_lua = os.path.join(dcs_path, "MissionEditor", "MissionEditor.lua")
    modules_dir = os.path.join(dcs_path, "MissionEditor", "modules", "actual_metar")

    if os.path.isfile(me_lua):
        with open(me_lua, "r", encoding="utf-8", errors="surrogateescape") as f:
            content = f.read()
        start = content.find(BEGIN_MARKER)
        end = content.find(END_MARKER)
        if start != -1 and end != -1:
            end += len(END_MARKER)
            new_content = content[:start] + content[end:]
            with open(me_lua, "w", encoding="utf-8", errors="surrogateescape") as f:
                f.write(new_content)
            print("ACTUAL METAR block removed from MissionEditor.lua.")
        else:
            print("MissionEditor.lua had no ACTUAL METAR block (nothing to remove).")

    if os.path.isdir(modules_dir):
        shutil.rmtree(modules_dir)
        print(f"Modules folder deleted: {modules_dir}")

    print("Uninstalled. Fully restart DCS World.")


def main():
    dcs_path = resolve_dcs_path()

    while True:
        print()
        print(f"ACTUAL METAR  v{VERSION}")
        print()
        print(f"  DCS install: {dcs_path or 'not detected'}")
        print()
        print("  1. Install or update ACTUAL METAR (mod + require in MissionEditor.lua)")
        print("     - Not sure which to pick? Pick this. It leaves the latest version installed.")
        print("  2. Uninstall ACTUAL METAR")
        print("  3. Set the DCS World install path manually")
        print("  q. Quit")
        print()
        choice = input("Choose [1/2/3/q]: ").strip().lower()

        if choice == "1":
            install(dcs_path)
        elif choice == "2":
            uninstall(dcs_path)
        elif choice == "3":
            new_path = prompt_manual_path()
            if new_path:
                dcs_path = new_path
        elif choice == "q":
            break
        else:
            print("Unrecognized option.")
            continue

        input("\nPress Enter to continue...")


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        pass
    except Exception as e:
        print(f"\nUnexpected error: {e}")
        try:
            input("Press Enter to exit...")
        except EOFError:
            pass
