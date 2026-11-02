# Categoría Calendario: eventos de Google Calendar

Fecha: 2026-11-01
Estado: propuesta (esperando aprobación)

## Objetivo

Que la categoría **Calendario** del menú secondary deje de ser sólo un mes en
blanco y pase a mostrar los eventos de uno o varios calendarios de Google. Los
eventos llegan a una lista del día seleccionado, con un punto del color de su
calendario, y la rejilla del mes marca los días que tienen eventos.

El usuario no edita ningún archivo a mano: un icono "G" en la esquina
superior izquierda de la tarjeta del calendario abre un diálogo donde se pega
la URL secreta de iCal y la shell se encarga de validarla y guardarla.

Por qué ahora: el calendario mensual sin agenda es la mitad de útil, y la
shell ya tiene toda la maquinaria de datos externos que hace falta (el clima
usa el mismo patrón: script → JSON → `Process` → `StdioCollector`). La
integración de Google es, sobre todo, otra fuente de datos con esa forma.

## Cómo se ve

```
┌──── rail ────┬──────────────────────────────────────────────────────┐
│ ▣ calendario │  (avatar) Ezku      10:42                    ‹ ›     │
│              │            miércoles 28 de octubre    Octubre 2026   │
│              │  ┌────────────────────────────────────────────────┐  │
│              │  │ (G)              L   M   X   J   V   S   D      │  │
│              │  │          29  30   1   2   3   4   5             │  │
│              │  │           6   7   8   9  10  11  12             │  │
│              │  │          13  14  15 •• 16  17  18  19            │  │
│              │  │          20  21  22  23  24  25  26            │  │
│              │  │          27  28  29  30   1   2   3            │  │
│              │  └────────────────────────────────────────────────┘  │
│              │  ┌──────────────┐  ┌────────────────────────────────┐ │
│              │  │‹ Notificac. ›│  │  [⏱ Activo 2 h 28 min]  [☁ 24°]│ │
│              │  │ 10:30  Casa  │  └────────────────────────────────┘ │
│              │  │       Daily  │                                     │
│              │  │ 11:00 Trabajo│                                    │
│              │  │     1:1      │                                    │
│              │  └──────────────┘                                     │
└──────────────┴──────────────────────────────────────────────────────┘
```

La columna izquierda alterna entre el historial de notificaciones y los
eventos del día. La rejilla marca con puntitos de color los días con eventos
(hasta tres colores por día; a partir de cuatro, un punto neutro).

## Objetivos

- Mostrar los eventos de N calendarios de Google, sólo lectura, en la
  categoría Calendario.
- Lista del día **mixta y cronológica**, con un punto del color de cada
  calendario y su nombre en texto pequeño.
- Puntos de color en la rejilla del mes para los días con eventos.
- Conmutar la columna izquierda entre "Notificaciones" y "Eventos" con dos
  flechitas, y **recordar la última vista** entre reinicios de la shell.
- Poder vincular, quitar y activar calendarios desde dentro de la shell, sin
  editar configuración a mano.
- Degradar limpio: sin vínculos, sin red o con una URL inválida, la categoría
  sigue funcionando.

## No objetivos

- Crear, editar o borrar eventos.
- Mostrar la descripción ("notas") de los eventos.
- Escribir en Google o sincronizar con otro servicio de calendario.
- Avisos de escritorio para eventos próximos (queda para un paso aparte).
- El feed iCal no trae el color del calendario: los colores los asigna la
  shell.

## Anti-objetivos

- Nada de OAuth, ni de proyectos en Google Cloud, ni de consentimiento de
  Google: la vinculación es por URL secreta de iCal.
- Nada de `QtQuick.Controls`: el repo nunca lo ha usado y el diálogo se
  construye con `TextInput` de QtQuick y los tokens de `Theme`.
- Nada de librerías de calendario en QML: el parseo del ICS y la expansión de
  recurrencias ocurren en Python, fuera del hilo visual.
- Nada de secretos en logs, en el repo o en mensajes de error.

## Alternativas consideradas

### Vincular con Google

| Alternativa | Trade-off | Estado |
|---|---|---|
| **URL secreta de iCal** (Ajustes → Integrar calendarios → "Direcciones secretas en formato iCal") | Sólo lectura. La URL es una credencial que hay que regenerar si Google la invalida. Sin consentimiento ni proyecto en la nube | **Elegida** |
| API de Google Calendar con OAuth | Permite escribir eventos y leer metadatos finos. Cuesta 2-3 días más, pantalla de consentimiento y refresh tokens que caducan a los 7 días si la app queda en modo "Pruebas" | Descartada |
| vdirsyncer / gcalcli como fuente local | Una sola OAuth para varias apps (khal, Thunderbird). Añade dependencias del sistema y una capa de sincronización que la shell no necesita | Descartada |

### Cómo se muestran los eventos de varios calendarios

| Alternativa | Trade-off | Estado |
|---|---|---|
| **Lista mixta cronológica** con punto de color y nombre del calendario | Se lee como un día de verdad. El color identifica el origen; el nombre confirma | **Elegida** |
| Lista agrupada por calendario | Deja claro de dónde es cada evento, pero rompe el orden del día | Descartada |

### Cómo se conmutan las dos vistas

| Alternativa | Trade-off | Estado |
|---|---|---|
| **Dos flechitas `‹ ›` flanqueando la etiqueta** ("Notificaciones" / "Eventos") | Cabe en 208 px, repite el gesto que ya usa la rejilla para cambiar de mes y la etiqueta dice en qué vista estás | **Elegida** |
| Un botón que alterna (campana ↔ calendario) | Más compacto, pero el estado actual se lee peor | Descartada |
| Segmentado Material 3 (dos pestañas) | Lo más autoexplicativo, pero se ve apretado en una columna tan angosta | Descartada |

### Dónde vive la URL

| Alternativa | Trade-off | Estado |
|---|---|---|
| **Archivo de configuración en `~/.config/caparazon/`, escrito por el script** | El archivo tiene que existir de todos modos: la URL es una credencial. Lo que cambia es quién lo escribe: un script controla permisos (600) y escritura atómica, cosa que QML no puede hacer | **Elegida** |
| Pegar la URL en `~/.config/caparazon/calendar.json` a mano | Menos código, pero el usuario edita un JSON a mano: exactamente lo que esta feature evita | Descartada |
| Guardar la URL en `~/.cache/caparazon/` | Es caché, no configuración: se puede borrar sin querer y acabaría con permisos de lectura para todos | Descartada |

### Dónde vive el diálogo

| Alternativa | Trade-off | Estado |
|---|---|---|
| **Overlay dentro de la tarjeta del calendario** | El `SecondMenu` es un `PanelWindow` con foco exclusivo de teclado: un `TextInput` dentro recibe teclado sin pelear con otra superficie. No hay que sincronizar dos ventanas | **Elegida** |
| `PopupWindow` de Quickshell (como `DockMenu.qml`) | Se ve más desligado, pero es otra superficie Wayland y el foco hay que negociarlo con el `PanelWindow` que ya tiene foco exclusivo | Descartada (queda como plan B, ver Riesgos) |

## Arquitectura

### 1. Datos y scripts

Tres archivos, tres responsabilidades:

| Archivo | Responsabilidad |
|---|---|
| `~/.config/caparazon/calendar.json` | Configuración: la lista de calendarios vinculados. **`chmod 600`**: contiene credenciales |
| `~/.cache/caparazon/calendar/<id>.ics` + `<id>.meta.json` | Caché por calendario: el ICS crudo tal cual lo devuelve Google, más la marca de tiempo de la descarga. Se cachea el ICS crudo y no los eventos ya expandidos, para poder reexpandir otro rango de fechas sin volver a descargar |
| `modules/secondmenu/gcal.py` | Script único con subcomandos. Es el que sabe de ICS, OAuth no, recurrencias y permisos |

Subcomandos de `gcal.py`:

| Comando | Qué hace | Quién lo llama |
|---|---|---|
| `gcal.py calendars` | Imprime la configuración (lista de calendarios) como JSON | `CalendarService.qml` |
| `gcal.py events --from <YYYY-MM-DD> --to <YYYY-MM-DD>` | Recalca desde el ICS cacheado (descargando si hace falta), expande las recurrencias del rango dado e imprime el JSON normalizado | `CalendarService.qml` |
| `gcal.py set-url <url> [--name <nombre>]` | Valida la URL (descarga y comprueba que sea un `VCALENDAR` real), añade el calendario a la configuración con escritura atómica y `chmod 600`, e imprime el calendario creado | `CalendarLinkDialog.qml` |
| `gcal.py remove <id>` | Quita el calendario de la configuración | `CalendarLinkDialog.qml` |
| `gcal.py set-enabled <id> <true\|false>` | Activa o desactiva un calendario | `CalendarLinkDialog.qml` |
| `gcal.py set-name <id> <nombre>` / `set-color <id> <#rrggbb>` | Renombra o recolorea | `CalendarLinkDialog.qml` |

Reglas del script:

- Es importable (sin efectos al importar) para poder testearlo.
- Tipado estricto: `basedpyright` en modo `all`, sin `Any` implícito. Se
  amplía el `include` de `ruff` y `basedpyright` en `pyproject.toml` para que
  abran `modules/secondmenu/gcal.py`.
- Timeouts de red: 10 s por feed.
- Rango: `events` recibe el rango a expandir. El panel pide el mes visible más
  el mes anterior y el siguiente, para que los puntos no desaparezcan al
  cambiar de mes. Como la caché guarda el ICS crudo, cambiar de mes no obliga
  a volver a descargar.
- Zonas horarias: el evento conserva su hora de pared (la de su `TZID`) y la
  clave de día se calcula en esa misma zona. Un evento creado a las 9:00 en
  Ciudad de México aparece a las 9:00, aunque el sistema esté en otra zona.
- Todo el día: los eventos `VALUE=DATE` no se convierten; se usa la fecha
  literal del ICS.
- Eventos que cruzan medianoche: un evento aparece en todos los días que
  cubre, del día de inicio al de fin.
- Recurrencias: se expanden con `dateutil.rrule` (frecuencia, intervalo,
  `UNTIL`, `COUNT`, `BYDAY`). Los `EXDATE` eliminan ocurrencias. Los casos con
  `RECURRENCE-ID` (una instancia modificada suelta) no se resuelven en la v1:
  queda documentado como limitación.
- Nunca escribe la URL en stdout ni en mensajes de error: en un error de
  validación dice "la URL no responde con un calendario iCal", sin repetirla.

### 2. Formato de los datos

`~/.config/caparazon/calendar.json`:

```json
{
  "calendars": [
    {
      "id": "trabajo",
      "name": "Trabajo",
      "color": "#4285F4",
      "enabled": true,
      "ical_url": "https://calendar.google.com/calendar/ical/…/basic.ics"
    }
  ]
}
```

- `id`: identificador corto y estable, usado en la caché y en la UI. Lo
  genera el script a partir del nombre, con sufijo numérico si colisiona.
- `color`: lo asigna la shell. El primer calendario toma `Theme.m3Primary`;
  los siguientes van cayendo en una paleta fija. Editable en el diálogo.
- `ical_url`: la credencial. Sólo lectura, nunca se muestra entera en la UI
  (el diálogo muestra los últimos 4 caracteres).

Salida de `gcal.py events`:

```json
{
  "ok": true,
  "calendars": [
    { "id": "trabajo", "name": "Trabajo", "color": "#4285F4", "enabled": true }
  ],
  "by_day": {
    "2026-11-03": [
      {
        "id": "trabajo:abc123",
        "calendar_id": "trabajo",
        "color": "#4285F4",
        "name": "Daily sync",
        "all_day": false,
        "start": "2026-11-03T09:00:00-06:00",
        "end": "2026-11-03T09:30:00-06:00"
      }
    ]
  },
  "stale": false
}
```

- Las claves de `by_day` son fechas en la zona del propio evento
  (`YYYY-MM-DD`).
- `stale: true` cuando se sirve caché porque la red falló.
- Los eventos de calendarios deshabilitados no aparecen.

### 3. `CalendarService.qml`

Copia el molde de `WeatherService.qml`:

- `property var calendars: []`, `property var byDay: ({})`, `property bool ready`,
  `property bool linked` (hay al menos un calendario vinculado).
- `refresh()` lanza `gcal.py events` con `Process` y `StdioCollector`; el
  `JSON.parse` del stdout llena las propiedades.
- Un `Timer` de 15 minutos refresca, y el menú refresca al abrirse.
- El rango que se pide al script se recalcula cuando cambia el mes visible.
- La ruta del script se resuelve con `Qt.resolvedUrl("gcal.py")`, igual que
  hace `weather.sh`.
- Si el script falla o devuelve `ok: false`, el servicio conserva lo último
  que supo y marca `stale`.

### 4. `CalendarPanel.qml`

Cambios sobre el panel actual:

- La columna izquierda pasa a ser un conmutador de dos vistas:
  `‹ Notificaciones ›` y `‹ Eventos ›`. Las flechitas son `MouseArea` con el
  mismo lenguaje visual que las del mes (26 px, hover `Theme.chipHover`).
- El botón "Limpiar" sólo aparece en la vista de notificaciones.
- La vista de eventos es un componente nuevo, `DayEvents.qml`: lista mixta
  cronológica del día seleccionado. Cada fila: punto del color del
  calendario, hora a la izquierda ("09:00", o "Todo el día"), nombre del
  calendario a la derecha en 9 px `Theme.textDim`, y el título debajo.
  Estado vacío: "Sin eventos este día".
- La rejilla del mes añade MouseArea por celda: al hacer clic se selecciona
  ese día. Por defecto se selecciona hoy.
- El día seleccionado se marca con un anillo de `Theme.m3Primary`; el día
  actual conserva el círculo relleno. Son marcas distintas y no se pisan.
- Al cambiar de mes, la selección conserva el número de día si existe en el
  mes nuevo; si no, se queda en el último día de ese mes.
- Al abrir el menú, el mes visible y el día seleccionado vuelven a hoy (lo que
  ya hace `resetToToday()`); lo que se recuerda entre reinicios es la vista,
  no el día.
- Puntos de color: hasta tres por día, uno por calendario, en el orden de la
  configuración. Con cuatro o más, un punto neutro.
- Los colores salen de una paleta fija de ocho tonos. El primer calendario
  toma `Theme.m3Primary` y los siguientes van cayendo en esa paleta. El color
  lo asigna el QML y se lo pasa al script al crear el calendario
  (`set-url --color`), porque el script no conoce la paleta del tema.

### 5. `CalendarMath.js`

La lógica pura sigue en JS, sin dependencias, para poder testearla con el
harness de node que ya usa `tests/test_calendar_math.py`. Se añaden:

- `dayKey(year, month, day)` → `"YYYY-MM-DD"`.
- `colorsForDay(byDay, year, month, day)` → lista de colores de los
  calendarios con eventos ese día (en el orden de la configuración, máximo
  tres).
- `isSameDay(a, b)` → compara dos fechas `{year, month, day}`.

`monthGrid` no cambia: sigue siendo una rejilla de 42 celdas sin eventos. Los
eventos se cruzan en el panel, no en la rejilla.

### 6. `PanelSettings.qml` (memoria de la vista)

Copia el patrón de `modules/music/MusicSettings.qml`:

- `~/.cache/caparazon/secondmenu.json` → `{"view": "events"}`.
- `FileView` + `JsonAdapter` con escritura atómica y bandera `loaded` para no
  pisar la preferencia antes de haberla leído.
- `view` vale `"notifications"` o `"events"`. La vista por defecto es
  "notifications".

### 7. `CalendarLinkDialog.qml`

Overlay dentro de la tarjeta del calendario (`calendarCard`), no una ventana
aparte.

- **Icono "G"**: badge de 22 px en la esquina izquierda de la fila del mes
  (`monthHeader`), con una "G" tipográfica en `#4285F4` dibujada en QML. No
  se usa el logo real de Google (marca) y no depende del tema de iconos: en
  Papirus y Adwaita no hay icono de Google Calendar. Apagado cuando no hay
  ningún calendario vinculado, encendido cuando sí.
- **Cuerpo del diálogo**:
  - Título "Vincular calendarios".
  - Lista de calendarios vinculados: punto de color, nombre editable
    (`TextInput`), casilla de activar/desactivar, botón de quitar. El color se
    cambia con una paleta de ocho tonos que se despliega al pulsar el punto
    (no hay selector de color).
  - Formulario de alta: botón "Abrir ajustes de Google" (`xdg-open
    https://calendar.google.com/calendar/settings`), un `TextInput` para la
    URL, botón "Pegar" (`wl-paste --no-newline`) y botón "Guardar".
  - Una línea de estado: "Vinculado: Trabajo" / "La URL no responde con un
    calendario iCal" / "Sin conexión".
- `Escape` cierra el diálogo primero y el menú sólo si el diálogo ya está
  cerrado. Para eso `CalendarPanel` emite una señal `overlayChanged(bool)` y
  `SecondMenu` desactiva su `Shortcut` de `Escape` mientras el overlay está
  abierto.
- Al guardar, el diálogo llama a `gcal.py set-url`, y al terminar
  `CalendarService` refresca. No hace falta reiniciar la shell.

### 8. Dependencias del sistema

- `python3-dateutil` para expandir recurrencias (`RRULE`). Es python puro y
  son unos 40 KB. Sin él, los eventos recurrentes salen mal expandidos.
- `install.sh` lo exige: si falta, el instalador se detiene con un mensaje
  claro y el `apt install` que lo arregla, igual que hace con las
  dependencias del tema.
- Si en tiempo de ejecución la librería no está, `gcal.py` responde
  `ok: false` con un mensaje legible y la vista de eventos lo muestra, en vez
  de una lista vacía sin explicación.
- El resto son herramientas ya presentes: `wl-paste` (pegar), `xdg-open`
  (abrir ajustes), `python3` (script), `zoneinfo` de la stdlib (zonas
  horarias).

## Verificación

- **Tests nuevos** (pytest, contrato estático sobre QML como el resto del
  repo):
  - `tests/test_calendar_google.py`: existen `CalendarService.qml`,
    `DayEvents.qml`, `CalendarLinkDialog.qml` y `PanelSettings.qml`; el
    diálogo llama a `gcal.py set-url`; la configuración vive en
    `~/.config/caparazon`; la caché en `~/.cache/caparazon`; el servicio usa
    `StdioCollector`.
  - `tests/test_calendar_math.py` (extender): `dayKey`, `colorsForDay` y
    `isSameDay` con el harness de node, incluidos el límite de tres colores y
    el orden de la configuración.
  - `tests/test_gcal.py`: el script se importa por ruta y se prueban el
    parseo de un ICS de ejemplo (evento puntual, todo el día, recurrente,
    `EXDATE` y uno que cruza medianoche), el recorte por `--from`/`--to` y la
    normalización a `by_day`.
- **Suite completa** del repo + `ruff` + `basedpyright` sin errores nuevos.
- **Prueba en vivo**: vincular un calendario real desde el diálogo, ver los
  puntos en la rejilla, conmutar a la vista de eventos, comprobar que la
  lista muestra hora, color y calendario, cambiar de día, cambiar de mes,
  reiniciar la shell y confirmar que la vista se recuerda, quitar el
  calendario y confirmar que la categoría vuelve a su estado actual.
- **Degradación**: sin red (con caché), sin calendars vinculados, con una
  URL inválida y con un feed que devuelve 404.

## Fuera de alcance

- Escribir eventos.
- Descripciones y notas de los eventos.
- Avisos de escritorio para eventos próximos (idea siguiente, ~20 líneas
  sobre lo que ya existe).
- Integración con calendarios del sistema (KDE/Akademy), `khal` o
  `vdirsyncer`.
- Sincronización push: el feed se consulta cada 15 minutos, no hay
  Suscripciones push de Google.

## Riesgos

- **Foco del `TextInput` dentro del `PanelWindow`**: el menú tiene foco
  exclusivo de teclado, así que un `TextInput` dentro debería recibirlo. Si en
  la prueba en vivo no lo recibe, el plan B es convertir el diálogo en un
  `PopupWindow` de Quickshell con `focusable: true` (el repo ya usa ese
  patrón en `DockMenu.qml` y `TrayMenu.qml`).
- **Google puede invalidar o cambiar el feed**: caché de 15 minutos, datos
  viejos si la red falla y diálogo que vuelve a pedir la URL si deja de
  funcionar. No se puede evitar.
- **La URL es una credencial**: `chmod 600`, nunca en logs, nunca en el
  repo, nunca en mensajes de error. Cualquiera que tenga el archivo puede
  leer el calendario.
- **Coste de arranque**: una petición HTTP por calendario habilitado cada 15
  minutos, con la primera al abrir el menú. Con cuatro o cinco calendarios
  son unas peticiones por cuarto de hora: asumible, pero se lanza en
  paralelo y con timeout de 10 s para que un feed lento no bloquee al resto.
- **Dependencia nueva**: `python3-dateutil` es obligatoria para la feature.
  `install.sh` la exige y `gcal.py` avisa si en runtime falta.
