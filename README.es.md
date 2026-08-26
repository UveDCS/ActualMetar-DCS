# REAL METAR

*[Read in English](README.md)*

Un **mod para el Mission Editor de DCS World** que añade una pestaña **REAL
METAR** en la barra de menú superior. Elige un mapa (o escribe cualquier
ICAO), obtén el METAR real de ese aeropuerto y aplícalo directamente a la
misión que tengas abierta —clima y, opcionalmente, fecha y hora— con un
clic. Sin app externa, sin navegador, sin servidor que arrancar: todo vive
dentro de DCS.

Proyecto independiente — **no** requiere [`dcs-sms`](https://github.com/nielsvaes/dcs-sms),
aunque convive perfectamente con él si también lo tienes instalado (entrada
de menú separada, ficheros separados).

## ¿Es esto seguro?

- **Código 100% abierto y auditable.** Todo el mod (Lua) y el instalador
  (Python) están en este repositorio, sin nada oculto. Si prefieres no
  fiarte de un `.exe` descargado, compílalo tú mismo en un par de minutos —
  instrucciones en [`DEVELOPMENT.md`](DEVELOPMENT.md).
- **Los `.exe` de cada [Release](../../releases) se compilan aquí mismo, en
  GitHub Actions**, directamente desde este código fuente público (ver el
  workflow en [`.github/workflows/build.yml`](.github/workflows/build.yml) y
  el historial de compilaciones en [Actions](../../actions)) — no son
  binarios subidos a mano desde un ordenador que no puedes revisar. Cada
  release incluye un `SHA256SUMS.txt` para comprobar que el fichero que
  descargaste es exactamente el que se compiló ahí.
- **Sin telemetría ni servidores propios.** La única petición de red que
  hace el mod es un GET de solo lectura a
  [aviationweather.gov](https://aviationweather.gov) (METAR público) para el
  ICAO que elijas — no se envía nada a ningún otro sitio.
- **Qué toca exactamente en tu sistema** al instalar (nada más, en ningún
  otro sitio):
  - `<DCS>\MissionEditor\modules\real_metar\` — los ficheros del mod.
  - `<DCS>\MissionEditor\MissionEditor.lua` — una línea añadida entre
    marcadores propios, con backup automático (`.real-metar.bak`) antes de
    tocarlo.
  - `Saved Games\DCS\real-metar\` — LuaSec y tus ICAOs personalizados.
  - `<DCS>\bin\` y `\bin-mt\` — 3 DLLs de LuaSec/OpenSSL para que funcione
    el HTTPS (ver la nota sobre Integrity Check en
    [Requisitos](#requisitos)).
- **¿Por qué avisa Windows al abrir el `.exe`?** SmartScreen marca cualquier
  ejecutable sin firma digital (firmar cuesta dinero todos los años) la
  primera vez que se ejecuta en una máquina — es el aviso estándar para
  software gratuito sin firmar, no un indicio de nada malicioso. Si te
  preocupa, la alternativa es compilarlo tú mismo desde el código fuente.

## Qué hace

- **METAR real a un clic.** Descarga el METAR actual de cualquier ICAO
  directamente desde [aviationweather.gov](https://aviationweather.gov),
  desde dentro del propio Mission Editor, sin congelarlo.
- **Consciente del mapa.** Un desplegable lista todos los mapas de DCS con
  un aeropuerto de referencia ya puesto; también detecta automáticamente la
  zona horaria real del mapa que tengas abierto. Puedes escribir cualquier
  otro ICAO si prefieres otro aeropuerto.
- **Presets de nubes reales, no solo un slider de densidad.** Encaja la
  capa de nubes del METAR contra los presets volumétricos reales de DCS
  (`Preset1`...`Preset27`, más las variantes con lluvia) usando los mismos
  datos de referencia que el proyecto open source
  [DCS-real-weather](https://github.com/evogelsa/DCS-real-weather) — solo
  cae al modelo clásico de densidad/base/grosor si ningún preset cubre la
  base de nubes del METAR.
- **Viento, QNH, temperatura, visibilidad, niebla** — todo convertido a lo
  que espera DCS, incluyendo el detalle (fácil de pasar por alto) de que DCS
  guarda la dirección del viento invertida respecto al METAR.
- **Fecha y hora opcionales**, con tres formas de elegir la hora: el reloj
  de tu propio PC ("Local"), la hora real actual en la ubicación real del
  mapa ("Mapa"), o una a mano. **Lo que elijas se escribe tal cual** — sin
  conversión de zona horaria, sin sorpresas: eliges las 12:20, en el editor
  salen las 12:20.
- **Añade o elimina aeropuertos del desplegable de Mapa** (`+`/`-` al lado)
  — tus entradas personalizadas se guardan en disco y siguen ahí la próxima
  vez que abras DCS.
- **Escribe directamente en los datos de la misión abierta, en memoria** —
  nada de cirugía sobre el fichero `.miz`. Solo hay que darle a Guardar en
  el editor después.

## Requisitos

- DCS World (cualquier build reciente; probado tanto en la versión estándar
  como en la MT).
- **LuaSec**, para el fetch por HTTPS — DCS trae LuaSocket pero no LuaSec.
  **Incluido automáticamente**: el instalador ya copia todo lo necesario, no
  hay que descargar ni colocar nada a mano. Como parte de esto, instalar
  REAL METAR copia unos pocos ficheros de soporte (LuaSec/OpenSSL) en tu
  propia instalación de DCS (`bin\` y `bin-mt\`), no solo en `Saved Games`.
  - Este build de LuaSec/OpenSSL viene originalmente del proyecto
    [`dcs-sms`](https://github.com/nielsvaes/dcs-sms) (LuaSec es MIT,
    OpenSSL es Apache-2.0 — ambas licencias permiten redistribuir). Crédito
    completo en `luasec_payload/ATTRIBUTION.txt` dentro del repositorio.
  - **Nota de transparencia:** meter DLLs en `bin\`/`bin-mt\` podría, en
    teoría, hacer que el Integrity Check de algún servidor multijugador
    estricto marque la instalación. No afecta al Mission Editor ni a
    misiones locales/sin conexión — solo importaría al entrar a un servidor
    MP que aplique ese check.

## Instalación

Descarga el último `real-metar.exe` desde la página de
[Releases](../../releases) (o compílalo tú mismo, ver
[`DEVELOPMENT.md`](DEVELOPMENT.md)) y ejecútalo. Verás un menú numerado,
mismo estilo que `dcs-sms.exe`:

```
1. Instalar o actualizar REAL METAR
2. Desinstalar REAL METAR
3. Fijar la ruta de instalación de DCS World a mano
q. Salir
```

Elige **1**. Autodetecta tu instalación de DCS (reaprovechando la ruta
cacheada de `dcs-sms` si la tienes); si no la encuentra, usa antes la opción
**3** y escribe la carpeta que contiene `MissionEditor\` y `bin\`.

> El `.exe` no está firmado (firmar cuesta dinero), así que es probable que
> Windows SmartScreen lo marque la primera vez. Dale a **Más información →
> Ejecutar de todas formas**. Si tu DCS está bajo `Program Files`, tendrás
> que ejecutar el instalador como Administrador (escribir ahí lo requiere).

Después **reinicia DCS World por completo** —no solo el Mission Editor, todo
el juego— porque `MissionEditor.lua` solo se carga una vez por arranque.
Abre el Mission Editor: **REAL METAR** debería aparecer en la barra de menú
superior, junto a Archivo/Edición/Ver/...

**Una actualización de DCS me sobrescribió la instalación / desapareció el
menú:** vuelve a ejecutar el instalador (opción 1). Es seguro relanzarlo
las veces que haga falta — no duplica nada, solo refresca los ficheros del
mod y vuelve a parchear si hace falta.

**Desinstalar:** ejecuta el `.exe` de nuevo y elige la opción **2**.

## Uso

1. Abre una misión en el Mission Editor.
2. **REAL METAR → Panel METAR** en el menú superior.
3. Elige tu mapa en el desplegable (o escribe un ICAO directamente), luego
   **Obtener METAR**. Verás el texto crudo del METAR y un resumen de lo que
   se va a escribir (viento, QNH, temperatura, nubes, visibilidad, niebla).
   - ¿No está el aeropuerto que quieres? Escribe su ICAO (y opcionalmente un
     nombre) y dale a `+` junto al desplegable para añadirlo de forma
     permanente. Elige una entrada que hayas añadido tú y dale a `-` para
     eliminarla (los mapas predefinidos no se pueden eliminar). Las entradas
     personalizadas no tienen zona horaria real conocida, así que la opción
     de hora **Mapa** se deshabilita automáticamente mientras esté elegida
     una de ellas.
4. Marca **También aplicar fecha y hora** si también quieres fijar la
   fecha/hora de la misión, y elige:
   - **Fecha**: *Actual* (hoy) o *Personalizada* (una fecha a mano).
   - **Hora**: *Local* (el reloj de tu propio PC, con el huso horario que
     tenga configurado), *Mapa* (la hora real que es ahora mismo en la
     ubicación real de ese mapa), o *Personalizada* (escribe cualquier
     HH:MM). Lo que elijas se escribe tal cual en la misión — sin
     conversión.
5. **Aplicar a la misión abierta.**
6. Guarda la misión (Ctrl+S) como siempre.

## Mapas soportados

| Mapa | ICAO de referencia |
|---|---|
| Caucasus | UGKO (Kutaisi) |
| Nevada (NTTR) | KLAS (Las Vegas) |
| Normandy | LFRK (Caen) |
| Persian Gulf | OMDB (Dubai) |
| The Channel | LFAC (Calais) |
| Syria | OSDI (Damasco) |
| Marianas | PGUM (Guam) |
| South Atlantic (Falklands) | EGYP (Mount Pleasant) |
| Sinai | HESH (Sharm El Sheikh) |
| Kola Peninsula | ULMM (Murmansk) |
| Afghanistan | OAKB (Kabul) |
| Iraq | ORBI (Bagdad) |
| Germany Cold War | ETAR (Ramstein) |

Se puede escribir cualquier ICAO a mano sin importar el mapa. Los
aeropuertos de referencia y sus zonas horarias están en
`lua/real_metar/dcs_maps.lua` — fácil de ampliar.

## Solución de problemas

- **No aparece el menú "REAL METAR" tras instalar** — reiniciaste el
  Mission Editor pero no todo DCS. Cierra DCS World del todo y vuelve a
  abrirlo.
- **El mapa/huso horario sale como "no reconocido"** — el string interno
  `theatre` de esa misión no está aún en nuestra tabla. Sigue funcionando
  igual, solo escribe el ICAO a mano; si nos dices el valor exacto que
  muestra, lo añadimos.
- **"Obtener METAR" da un error de paquete que falta** — necesitas el
  paquete LuaSec, mira [Requisitos](#requisitos) arriba.
- **No pasa nada, sin ningún error** — revisa
  `<Saved Games>\DCS\Logs\dcs.log` buscando líneas etiquetadas `real_metar`.

## Créditos

- Datos de referencia de presets de nubes adaptados de
  [evogelsa/DCS-real-weather](https://github.com/evogelsa/DCS-real-weather).
- Técnicas de integración con el Mission Editor (registro de menú, HTTPS no
  bloqueante, uso de widgets) aprendidas del proyecto open source
  [nielsvaes/dcs-sms](https://github.com/nielsvaes/dcs-sms).
- Datos METAR de [aviationweather.gov](https://aviationweather.gov).

## Contribuir / próximos pasos

Esto es una primera versión — issues y pull requests bienvenidos. Ver
[`DEVELOPMENT.md`](DEVELOPMENT.md) para la estructura del proyecto y cómo
compilar el instalador desde el código fuente.
