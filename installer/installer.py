"""REAL METAR - instalador interactivo para el mod del Mission Editor de DCS World.

Replica el estilo del menu de dcs-sms.exe: un .exe independiente (compilado
con PyInstaller) que no necesita nada al lado salvo el propio ejecutable -
los ficheros Lua del mod van empaquetados dentro.

Uso normal: doble clic. Abre un menu numerado en la consola.
"""

import json
import os
import shutil
import sys

VERSION = "0.1.0"

# IMPORTANTE: este texto tiene que ser IDENTICO al de install.ps1 (mismo
# marcador), o el detector de "ya esta parcheado" de un instalador no
# reconoce el parche puesto por el otro y se duplica el require. (Pasó de
# verdad durante las pruebas: casi se lía con la instalacion real por esto.)
BEGIN_MARKER = "-- REAL-METAR-BEGIN (no editar a mano; gestionado por install.ps1)"
END_MARKER = "-- REAL-METAR-END"

CONFIG_DIR = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "real-metar")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.json")

DCS_SMS_CONFIG = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "dcs-sms", "config.toml")


def bundled_lua_dir():
    """Carpeta con los .lua del mod: dentro del .exe empaquetado (PyInstaller
    onefile la descomprime en sys._MEIPASS), o los .lua reales del repo (sin
    copia propia) cuando se ejecuta como script normal en desarrollo."""
    base = getattr(sys, "_MEIPASS", None)
    if base:
        return os.path.join(base, "real_metar")
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(here, "..", "lua", "real_metar")


def bundled_luasec_dir():
    """Carpeta con el paquete LuaSec/OpenSSL incluido en el instalador (ver
    luasec_payload/ATTRIBUTION.txt): mismo patron que bundled_lua_dir()."""
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
    """<Saved Games>\\DCS(.openbeta)\\ - reaprovecha el valor cacheado de
    dcs-sms si existe; si no, adivina segun si la instalacion es OpenBeta."""
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
    raw = input("Ruta de instalacion de DCS World (la que contiene MissionEditor\\): ").strip()
    raw = raw.strip('"')
    if not raw:
        print("Vacio, no se ha cambiado nada.")
        return None
    if not is_dcs_path(raw):
        print(f"AVISO: no se encontro MissionEditor\\MissionEditor.lua en: {raw}")
        confirm = input("¿Guardar igualmente? [s/N]: ").strip().lower()
        if confirm != "s":
            return None
    cfg = load_config()
    cfg["dcs_install"] = raw
    save_config(cfg)
    print(f"Ruta guardada: {raw}")
    return raw


def install_luasec(dcs_path):
    """Copia el paquete LuaSec/OpenSSL incluido en el instalador para que el
    fetch HTTPS funcione sin pasos manuales (ver luasec_payload/ATTRIBUTION.txt
    para procedencia y licencias). lib/ -> Saved Games\\DCS\\real-metar\\lib\\;
    bin/ -> <DCS>\\bin\\ y \\bin-mt\\ (las que existan)."""
    payload = bundled_luasec_dir()
    lib_src = os.path.join(payload, "lib")
    bin_src = os.path.join(payload, "bin")
    if not os.path.isdir(lib_src) or not os.path.isdir(bin_src):
        print("AVISO: no se encontro el paquete LuaSec incluido en el instalador;")
        print("el fetch por HTTPS puede no funcionar.")
        return

    saved_games = resolve_saved_games_dir(dcs_path)
    lib_dst = os.path.join(saved_games, "real-metar", "lib")
    for root, _dirs, files in os.walk(lib_src):
        rel = os.path.relpath(root, lib_src)
        dst_root = lib_dst if rel == "." else os.path.join(lib_dst, rel)
        os.makedirs(dst_root, exist_ok=True)
        for name in files:
            shutil.copy2(os.path.join(root, name), os.path.join(dst_root, name))
    print(f"LuaSec (HTTPS) instalado en: {lib_dst}")

    bin_dirs = [os.path.join(dcs_path, "bin"), os.path.join(dcs_path, "bin-mt")]
    installed_bin = [bd for bd in bin_dirs if os.path.isdir(bd)]
    for bd in installed_bin:
        for name in os.listdir(bin_src):
            shutil.copy2(os.path.join(bin_src, name), os.path.join(bd, name))
    if installed_bin:
        print("Dependencias de OpenSSL copiadas en: " + ", ".join(installed_bin))
    else:
        print("AVISO: no se encontraron las carpetas bin\\/bin-mt\\ de DCS; el fetch")
        print("por HTTPS puede no funcionar.")


def install(dcs_path):
    if not dcs_path:
        print("No hay una ruta de DCS World valida. Usa la opcion 3 primero.")
        return

    me_lua = os.path.join(dcs_path, "MissionEditor", "MissionEditor.lua")
    modules_dir = os.path.join(dcs_path, "MissionEditor", "modules", "real_metar")
    source_dir = bundled_lua_dir()

    if not os.path.isdir(source_dir):
        print(f"ERROR: no se encuentran los ficheros Lua del mod ({source_dir}).")
        return
    if not os.path.isfile(me_lua):
        print(f"ERROR: no se encuentra MissionEditor.lua en: {me_lua}")
        return

    os.makedirs(modules_dir, exist_ok=True)
    copied = 0
    for name in os.listdir(source_dir):
        if name.endswith(".lua"):
            shutil.copy2(os.path.join(source_dir, name), os.path.join(modules_dir, name))
            copied += 1
    print(f"Ficheros Lua copiados a: {modules_dir} ({copied} ficheros)")

    with open(me_lua, "r", encoding="utf-8", errors="surrogateescape") as f:
        content = f.read()

    if BEGIN_MARKER not in content:
        backup = me_lua + ".real-metar.bak"
        if not os.path.isfile(backup):
            shutil.copy2(me_lua, backup)
            print(f"Backup creado: {backup}")
        block = f"\n{BEGIN_MARKER}\nrequire('real_metar.init')\n{END_MARKER}\n"
        with open(me_lua, "a", encoding="utf-8", errors="surrogateescape") as f:
            f.write(block)
        print("MissionEditor.lua parcheado (require agregado).")
    else:
        print("MissionEditor.lua ya tenia el require de REAL METAR (no se toca).")

    print()
    install_luasec(dcs_path)

    print()
    print("Instalacion completa.")
    print("Reinicia DCS World POR COMPLETO (no solo el Mission Editor) y abre el editor:")
    print("deberia aparecer REAL METAR en la barra de menu superior.")
    print()
    print("Nota: se han copiado unos ficheros de soporte (LuaSec/OpenSSL) en tu instalacion")
    print("de DCS ('bin\\' y 'bin-mt\\') para que el fetch por HTTPS funcione sin pasos extra.")
    print("Vienen de un build de terceros (proyecto dcs-sms, licencias MIT/Apache-2.0), ver")
    print("luasec_payload/ATTRIBUTION.txt. Algunos servidores multijugador con Integrity Check")
    print("estricto podrian, en teoria, marcarlos; no afecta al Mission Editor ni a misiones")
    print("locales/sin conexion.")


def uninstall(dcs_path):
    if not dcs_path:
        print("No hay una ruta de DCS World valida. Usa la opcion 3 primero.")
        return

    me_lua = os.path.join(dcs_path, "MissionEditor", "MissionEditor.lua")
    modules_dir = os.path.join(dcs_path, "MissionEditor", "modules", "real_metar")

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
            print("Bloque REAL-METAR quitado de MissionEditor.lua.")
        else:
            print("MissionEditor.lua no tenia el bloque REAL-METAR (nada que quitar).")

    if os.path.isdir(modules_dir):
        shutil.rmtree(modules_dir)
        print(f"Carpeta de modulos borrada: {modules_dir}")

    print("Desinstalado. Reinicia DCS World por completo.")


def main():
    dcs_path = resolve_dcs_path()

    while True:
        print()
        print(f"REAL METAR  v{VERSION}")
        print()
        print(f"  DCS install: {dcs_path or 'no detectado'}")
        print()
        print("  1. Instalar o actualizar REAL METAR (mod + require en MissionEditor.lua)")
        print("     - No sabes cual elegir? Elige esta. Deja instalada la ultima version.")
        print("  2. Desinstalar REAL METAR")
        print("  3. Fijar la ruta de instalacion de DCS World a mano")
        print("  q. Salir")
        print()
        choice = input("Elige [1/2/3/q]: ").strip().lower()

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
            print("Opcion no reconocida.")
            continue

        input("\nPulsa Enter para continuar...")


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        pass
    except Exception as e:
        print(f"\nError inesperado: {e}")
        try:
            input("Pulsa Enter para salir...")
        except EOFError:
            pass
