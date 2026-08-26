# Notas de desarrollo

(Documentación técnica interna. Los README públicos —
[`README.md`](README.md) / [`README.es.md`](README.es.md)— están pensados
para quien solo quiere instalar y usar el mod.)

## Estructura

```
install.ps1              — instalador/desinstalador (script, para desarrollo, siempre ES)
installer/
  installer.py            — instalador .exe (español) — empaqueta lua/actual_metar
  installer_en.py          — instalador .exe (inglés) — empaqueta lua_en/actual_metar
  dist/actual-metar.exe       — binario compilado ES (PyInstaller, onefile)
  dist/actual-metar-en.exe    — binario compilado EN
luasec_payload/             — LuaSec/OpenSSL precompilado, empaquetado en ambos .exe (ver mas abajo)
  ATTRIBUTION.txt            — origen y licencias
  lib/                       — ssl.lua, ssl/https.lua, cacert.pem, ssl.dll -> Saved Games\DCS\actual-metar\lib\
  bin/                       — libcrypto-4-x64.dll, libssl-4-x64.dll, lua5.1.dll -> <DCS>\bin\ y \bin-mt\
lua/actual_metar/            — mod, interfaz en ESPAÑOL (original)
lua_en/actual_metar/          — mod, interfaz en INGLÉS (traducción — ver mas abajo)
  init.lua                 — arranque (cargado desde MissionEditor.lua)
  menu.lua                 — entrada de menú "ACTUAL METAR"
  window.lua                — panel (UI)
  ticker.lua                — bombea el fetch async por tick de UpdateManager
  https_transport.lua       — GET HTTPS no bloqueante (LuaSocket+LuaSec)
  lib_path.lua              — localiza el payload de LuaSec
  metar_fetch.lua           — orquesta descarga + calculo (corutina)
  json.lua                  — decodificador JSON minimo
  weather_calc.lua          — traduccion METAR -> campos DCS
  cloud_presets.lua         — tabla de presets de nubes de DCS
  mission_datetime.lua      — calculo de fecha/hora (sin conversion final a UTC, ver mas abajo)
  mission_apply.lua         — escribe en la tabla mission en memoria
  dcs_maps.lua               — ICAO + zona horaria por mapa (predefinidos)
  custom_maps.lua            — ICAOs añadidos/eliminados a mano por el usuario (persistidos)
  paths.lua                  — resuelve <Saved Games>\DCS\ (compartido por lib_path y custom_maps)
Instalacion-ES/             — paquete listo para distribuir: actual-metar.exe + README.md + DEVELOPMENT.md (es)
Installation-EN/            — idem en inglés: actual-metar.exe + README.md + DEVELOPMENT.md (en)
```

## `lua/` vs `lua_en/`: dos copias traducidas, no una con i18n

Son dos árboles de ficheros **paralelos y funcionalmente idénticos** — mismo
código, solo cambian los comentarios y las cadenas de texto que ve el
usuario (labels, botones, mensajes de estado, la consola del instalador).
No hay ningún sistema de internacionalización (tablas de strings, `gettext`,
etc.) — se decidió así a propósito para mantener cada árbol simple y
autocontenido, a costa de tener que aplicar cualquier cambio de lógica
**dos veces** (una vez en `lua/`, otra en `lua_en/`). Si se corrige un bug o
se añade una función, hay que replicarlo en el otro idioma antes de dar la
tarea por terminada — pasó de verdad con el fix de `mission_apply.lua`
(nubes sin preset en misiones nuevas), corregido primero en `lua/` y
replicado en `lua_en/` en la misma sesión.

El espacio de nombres interno de los módulos (`actual_metar.*`) y el nombre
de la carpeta de instalación (`MissionEditor\modules\actual_metar\`) son
iguales en ambos idiomas — un usuario instala uno u otro, nunca los dos a
la vez, y el marcador de `MissionEditor.lua` (ver mas abajo) es
intencionadamente el mismo texto para que cambiar de idioma sea solo
"ejecutar el otro instalador", sin dejar restos del anterior.

## Compilar los `.exe`

```powershell
cd installer
python -m pip install pyinstaller

# Español (empaqueta lua/actual_metar + luasec_payload):
python -m PyInstaller --onefile --console --name actual-metar --add-data "..\lua\actual_metar;actual_metar" --add-data "..\luasec_payload;luasec" --distpath .\dist --workpath .\build --specpath . installer.py

# Ingles (empaqueta lua_en/actual_metar + luasec_payload):
python -m PyInstaller --onefile --console --name actual-metar-en --add-data "..\lua_en\actual_metar;actual_metar" --add-data "..\luasec_payload;luasec" --distpath .\dist --workpath .\build_en --specpath . installer_en.py
```

Los `.lua` y el payload de LuaSec quedan empaquetados dentro del propio
`.exe` (extraidos a `sys._MEIPASS` en tiempo de ejecucion, en subcarpetas
`actual_metar` y `luasec` — mismos nombres para los dos idiomas). No hace
falta distribuir nada más junto al ejecutable: ejecutarlo ya deja DCS listo
para usar HTTPS, sin pasos manuales.

**IMPORTANTE**: `install.ps1`, `installer/installer.py` e
`installer/installer_en.py` usan el mismo marcador de texto exacto en
`MissionEditor.lua`
(`-- ACTUAL-METAR-BEGIN (no editar a mano; gestionado por install.ps1)`,
**sin traducir**, a propósito — ver seccion anterior) para poder detectar
si otro ya parcheó el fichero. Si se cambia ese texto en un sitio, hay que
cambiarlo en los otros tres también — si no, un instalador no reconoce el
parche del otro y duplica el `require`. Pasó de verdad durante el
desarrollo (con `installer.py` e `install.ps1` antes de sincronizar el
texto).

## Estado de las pruebas

Este proyecto se ha construido y probado en dos capas muy distintas:

- **Toda la lógica de cálculo** (`json.lua`, `cloud_presets.lua`,
  `weather_calc.lua`, `mission_datetime.lua`, `mission_apply.lua`,
  `dcs_maps.lua`) está **probada de verdad**, con un intérprete Lua 5.1 real
  (la misma versión que usa DCS) fuera del juego, y sus resultados
  contrastados campo a campo contra `metar-dcs-app` (la versión previa en
  Python, ya validada en uso real) — incluyendo casos límite de horario de
  verano (transición UE/EEUU) y el matching de presets de nubes con lluvia.
  Todos los ficheros además pasan una verificación de sintaxis Lua.
- **La integración con el Mission Editor** (`window.lua`, `menu.lua`,
  `https_transport.lua`, `ticker.lua`) sigue al pie de la letra las
  técnicas ya probadas en producción por el proyecto `dcs-sms`
  (`nielsvaes/dcs-sms`, código abierto) — registro de menú vía
  `me_menubar`, widgets `Window`/`Static`/`EditBox`/`Button`/`CheckBox`/
  `ComboList`, HTTPS no bloqueante vía LuaSocket+LuaSec — y **ya se ha
  confirmado funcionando end-to-end** en una máquina real (fetch, aplicar,
  desplegable de mapas, checkboxes de fecha/hora) tras una sesión de
  depuración conjunta.

## Bug real corregido: presets de nubes en misiones nuevas/en blanco

Reportado en una prueba real: una misión recién creada (no una guardada
previamente) puede no tener la clave `["preset"]` en `mission.weather.clouds`
todavía (no se ha tocado nunca el diálogo nativo de Weather del editor).
`mission_apply.lua` originalmente solo ESCRIBÍA el preset calculado si esa
clave ya existía, cayendo al modelo dinámico si no — con una nota de aviso.
Se corrigió escribiendo `clouds.preset` siempre, exista la clave o no:
añadir una clave a una tabla Lua es seguro, y DCS solo lee las claves que
conoce, así que el fallback (y su nota) ya no hacen falta. Aplicado en
`lua/actual_metar/mission_apply.lua` y replicado en `lua_en/`.

## Fecha/hora: decisión deliberada de no convertir a UTC

DCS guarda `mission.start_time` en segundos desde medianoche **UTC/Zulu**
(confirmado inspeccionando el proyecto `pydcs/dcs`). Sin embargo, por
petición explícita, el mod **no convierte** la hora elegida a UTC antes de
escribirla: escribe la hora local elegida (Península/Mapa/Personalizada)
tal cual, literalmente, en `start_time`. Si se quisiera la conversión
astronómicamente correcta de vuelta (para que el editor muestre la hora
solar real del mapa en vez de un valor literal), está en el historial de
`mission_datetime.lua`.

Sigue haciendo falta resolver "qué hora es ahora mismo" en el mapa elegido
para el modo "Mapa", y eso sí requiere manejar zonas horarias reales con su
horario de verano — implementado a mano en `mission_datetime.lua` (reglas UE
y EEUU) porque Lua no tiene zoneinfo/tzdata. El modo "Local" (antes
"Península") ya no usa ninguna tabla de husos horarios: lee directamente
`os.date("*t")` sin el prefijo `"!"`, es decir la hora que tenga configurada
Windows en ese PC, sea cual sea. No requiere permisos de administrador (leer
el reloj del sistema nunca los requiere).

## ICAOs personalizados (`custom_maps.lua`)

El desplegable "Mapa" tiene botones `+`/`-` para añadir o quitar entradas
sin tocar código. Se guardan en
`<Saved Games>\DCS\actual-metar\custom_icaos.lua`, un fichero Lua normal
(`return { {name=, icao=, std_offset_h=, rule=}, ... }`) que se lee/escribe
con `loadfile`/`io.open` — mismo estilo que usa `dcs-sms` para sus propios
ajustes (`me_hotkeys.lua`, `me_scripts.lua`). Los ICAOs añadidos así no
tienen zona horaria real conocida (no hay forma de adivinar de qué
aeropuerto es un ICAO escrito a mano) — se guardan con
`std_offset_h=0, rule="none"` (UTC) por defecto; si el usuario conoce la
zona real, puede editar el fichero a mano estando DCS cerrado. Los mapas
predefinidos (`dcs_maps.lua`) no se pueden eliminar desde el panel — el
botón `-` solo actúa sobre entradas marcadas `is_builtin = false`.

El campo "Nombre" junto al ICAO es opcional: si se deja en blanco,
`custom_maps.add(icao, nombre)` usa por defecto `"Personalizado (ICAO)"`.

Como una entrada personalizada no tiene zona horaria real conocida,
`window.lua` deshabilita el checkbox y la etiqueta "Mapa" del apartado Hora
en cuanto se selecciona una en el desplegable (`entry.is_builtin == false`),
y si "Mapa" estaba activo en ese momento, salta automáticamente a "Local"
(`select_time_mode`, devuelto por `wire_radio_group` para poder forzar la
seleccion desde código y no solo desde el click del checkbox).

## Mapas y zonas horarias

`dcs_maps.lua` define, por mapa, `{offset_horas_estandar, regla}` donde
`regla` es `"none"` (sin horario de verano), `"eu"` (último domingo de
marzo/octubre) o `"us"` (2º domingo de marzo / 1er domingo de noviembre).
La detección automática del mapa abierto usa `mission.theatre` — el mapeo
`theatre` real → entrada de `dcs_maps.lua` está en
`M.THEATRE_TO_ID`; si un mapa no se reconoce, la ventana muestra el string
real de `theatre` para poder añadirlo.

Limitación conocida: Falklands sí observa horario de verano austral
(sep-abr) que no está modelado — usa su offset estándar todo el año.

## Rename del proyecto: "REAL METAR" -> "ACTUAL METAR"

Decisión explícita del usuario, sin motivo técnico. El rename tocó **todo**:
namespace Lua (`real_metar` -> `actual_metar`, carpetas `lua/real_metar/` ->
`lua/actual_metar/` y `lua_en/` igual), el marcador de `MissionEditor.lua`
(`REAL-METAR-BEGIN/END` -> `ACTUAL-METAR-BEGIN/END`), la carpeta de datos en
`Saved Games\DCS\real-metar\` -> `\actual-metar\`, la carpeta de config del
instalador (`%AppData%\real-metar\` -> `\actual-metar\`), el texto visible
del menú/panel en el Mission Editor, y el repositorio de GitHub
(<https://github.com/UveDCS/ActualMetar-DCS>).

**Migración de instalaciones ya existentes** (importante: el usuario ya
tenía esto instalado de verdad en su `F:\DCS World` antes del rename): los
tres instaladores (`installer.py`, `installer_en.py`, `install.ps1`)
guardan constantes `OLD_BEGIN_MARKER`/`OLD_END_MARKER` (el texto antiguo
`REAL-METAR-...`) solo para detectar y limpiar instalaciones previas, nunca
para generarlas. En `install()`/`Install-LuaSec` se añadió, en este orden:

1. Si existe `MissionEditor\modules\real_metar\` (carpeta antigua), se borra
   antes de crear la nueva `modules\actual_metar\`.
2. Si `MissionEditor.lua` tiene el bloque antiguo `REAL-METAR-BEGIN/END`, se
   quita **antes** de comprobar/añadir el bloque nuevo (si no, quedarían los
   dos `require` a la vez: `real_metar.init` Y `actual_metar.init`).
3. Si existe `Saved Games\DCS\real-metar\` y **no** existe ya
   `\actual-metar\`, se **mueve** la carpeta entera (no se copia y se borra
   el original por separado) — así se preserva `custom_icaos.lua` (datos del
   usuario) sin tocarlo, y `lib\` se sobrescribe después con el payload
   empaquetado de todas formas. Si ambas carpetas ya existen (reinstalación
   repetida), no se toca ninguna — se asume la nueva como buena y no se
   borra la antigua por si acaso.

Probado de punta a punta en un sandbox aislado que reproduce exactamente el
estado real previo (marcador antiguo + `modules\real_metar\` con un fichero
+ `Saved Games\...\real-metar\` con `custom_icaos.lua` y un `ssl.lua`
antiguo): tras `install()`, la carpeta antigua de módulos desaparece, el
marcador nuevo aparece una sola vez (el viejo, cero veces), `custom_icaos.lua`
sobrevive con su contenido intacto, y `lib\` queda con el payload real
(no el `ssl.lua` de prueba). Ver la disciplina de pruebas seguras más abajo.

`VERSION` subió a `0.2.0` (rename es un cambio que rompe compatibilidad de
nombres, aunque la migración lo haga transparente para el usuario).

## Build reproducible en CI (`.github/workflows/build.yml`)

Al hacer push de un tag `v*`, GitHub Actions (runner `windows-latest`)
ejecuta exactamente los mismos comandos de PyInstaller de la sección
anterior, empaqueta los dos `.zip` de distribución, calcula
`SHA256SUMS.txt` y publica todo como Release con `gh release create
--generate-notes`. Esto es intencional, no solo comodidad: significa que
cualquiera puede verificar que el `.exe` que se descarga es exactamente el
que se compiló desde el código público de este repo (ver el historial en la
pestaña Actions), en vez de tener que fiarse de un binario compilado a mano
en un ordenador que nadie más puede inspeccionar — ver la sección "¿Es esto
seguro?" de los README públicos. No compilar ni subir releases a mano salvo
que el workflow falle; en ese caso, arreglar el workflow antes que
saltárselo.

## LuaSec empaquetado: por qué y de dónde sale

Decisión explícita del usuario: "no quiero que nadie ande haciendo segundos
pasos para instalarlo, quiero que ejecuten el exe y listo". Antes de esto,
el README pedía descargar `payload/` del repo de `dcs-sms` a mano si no se
tenía ese mod ya instalado — funcionaba, pero era fricción real para
cualquiera sin `dcs-sms`.

Los 7 ficheros de `luasec_payload/` se copiaron **directamente de la propia
instalación de `dcs-sms` del usuario** (`Saved Games\DCS\dcs-sms\lib\` y
`F:\DCS World\bin\`), es decir, de un build ya verificado funcionando en
producción — no se compiló nada desde cero. Se excluyó deliberadamente
`libcrypto-1_1-x64.dll`: esa la trae el propio DCS de fábrica, no es parte
del payload de LuaSec que añade `dcs-sms`.

Licencias que permiten esta redistribución: LuaSec (MIT), OpenSSL
(Apache-2.0), Lua 5.1 (MIT), cacert.pem (MPL-2.0) — mismo razonamiento que
usa `dcs-sms` para justificar que él mismo distribuye este build
precompilado en su propio repo público. Crédito y detalle en
`luasec_payload/ATTRIBUTION.txt`.

`install_luasec()` (mismo nombre en `installer.py`/`installer_en.py`,
`Install-LuaSec` en `install.ps1`) hace dos copias:
- `luasec_payload/lib/*` → `Saved Games\DCS\actual-metar\lib\` (recursivo, por
  `ssl/https.lua`). `lib_path.lua` ya buscaba aquí primero antes de caer a
  `dcs-sms\lib\`, así que no hizo falta tocar ningún `.lua`.
- `luasec_payload/bin/*` → `<DCS>\bin\` y `<DCS>\bin-mt\`, solo en las que
  existan. Esta parte es nueva: nunca antes escribíamos fuera de
  `Saved Games`. La ruta de `Saved Games` se resuelve reaprovechando el
  `saved_games` cacheado de `dcs-sms\config.toml` si existe (ojo: en el TOML
  viene con backslash escapado, `\\`, hay que des-escaparlo), si no
  adivinando `Saved Games\DCS` o `DCS.openbeta` según si la ruta de DCS
  contiene "openbeta".

Riesgo aceptado explícitamente por el usuario: el Integrity Check de
algunos servidores MP podría en teoría marcar estas DLLs nuevas en `bin\`.
Ver el razonamiento completo (por qué en la práctica no ha dado problemas)
en los README públicos, sección "Requisitos"/"Requirements".

Desinstalar (`uninstall`) sigue sin tocar `Saved Games\DCS\actual-metar\lib\`
ni las DLLs de `bin\`/`bin-mt\` — mismo criterio que ya usa `dcs-sms` de no
borrar nada con pinta de dato de usuario en el desinstalador. No se ha
pedido lo contrario.

## Precaución al probar los instaladores en esta máquina

La autodetección de ruta de DCS (barrido de `<unidad>:\DCS World` en todas
las unidades) no distingue "modo de prueba" — encuentra la instalación real
de la máquina igual que la real. Durante el desarrollo esto llegó a hacer
que una prueba tocara por accidente la instalación real (borró la carpeta
de módulos y estuvo a punto de duplicar el parche). Al probar cualquiera de
los dos instaladores contra una carpeta falsa, sembrar siempre
`%AppData%\actual-metar\config.json` con una ruta claramente falsa *antes* de
ejecutar, y verificar con una llamada de depuración a `resolve_dcs_path()`
que devuelve esa ruta falsa antes de dejar que el instalador toque nada.

**Desde que se añadió `install_luasec()`, el riesgo es mayor**: además de
escribir en la ruta de DCS falsa, ahora también escribe en `bin\`/`bin-mt\`
dentro de esa misma ruta falsa, y en una carpeta de Saved Games resuelta por
separado (`resolve_saved_games_dir()`/`Find-SavedGamesPath`). Antes de
probar `install()`/`install_luasec()`, verificar TAMBIÉN que
`resolve_saved_games_dir()` devuelve una ruta de prueba (no la real
`Saved Games\DCS`) — por ejemplo pasándole explícitamente una ruta falsa o
probando la función de forma aislada, no solo `resolve_dcs_path()`.
