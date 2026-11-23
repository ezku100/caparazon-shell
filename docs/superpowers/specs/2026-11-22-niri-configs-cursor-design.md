# Diseño: categoría "Niri configs" con selector de tema de cursor

Fecha: 2026-11-22 · Estado: aprobado por el usuario el 2026-11-22

## Intención y por qué

El submenú de niri ya tiene una categoría `iconos` que permite elegir el tema
de iconos de la shell. El usuario pidió dos cambios:

1. renombrar esa categoría a **Niri configs**;
2. agregar dentro de ella una opción para cambiar el **tema del cursor**,
   reconociendo los temas Xcursor ya descargados en el sistema y editando el
   config de niri para que el cursor se actualice.

La categoría sigue existiendo **sólo en niri**. En Plasma el cursor y los
iconos los controla KDE; la shell no debe escribir ahí nada nuevo.

## Hechos verificados

- `SecondMenu.qml` define `iconCategory` con `key: "iconos"`, `label: "Iconos"`,
  `icon: "preferences-desktop-theme"` y lo agrega a `categories` sólo cuando
  `CompositorService.niri` es verdadero.
- El `Loader` monta `IconThemePanel` cuando `root.category === "iconos"`.
- `IconThemePanel.qml` ya habla sólo con `caparazon-wm icon-theme` y
  `caparazon-wm icon-theme --set <tema>`; no escribe ficheros ni reinicia.
- El cursor de niri vive en `/home/ezku/.config/niri/config.d/10-input-and-cursor.kdl`:

  ```kdl
  cursor {
      xcursor-theme "breeze_cursors"
      xcursor-size 24
      hide-when-typing
  }
  ```

- `config.kdl` incluye `config.d/10-input-and-cursor.kdl` en la línea 31.
- `niri msg action --help` expone `load-config-file` → “Reload the config file”.
- Temas Xcursor detectados ahora en `/usr/share/icons/*/cursors`: Adwaita,
  breeze_cursors, Breeze_Light, KDE_Classic, Layan-white-cursors, Oxygen_Black,
  Oxygen_Blue, Oxygen_White, Oxygen_Yellow, Oxygen_Zion.
- `caparazon-wm icon-theme` ya tiene el patrón a seguir: estado JSON, validación
  contra temas instalados, escritura atómica en el fichero dueño del include y
  CLI como única puerta al sistema.
- No se va a tocar `~/.config/autostart/caparazon.desktop` ni variables de
  entorno de KDE: el cambio es sólo config de niri.

## Metas

- El rail del submenú muestra la categoría `Niri configs` en lugar de `Iconos`,
  únicamente bajo niri.
- Dentro de esa categoría hay dos pestañas: **Iconos** y **Cursor**.
  La pestaña Iconos conserva el panel actual sin cambios de comportamiento.
- La pestaña Cursor lista los temas Xcursor instalados, marca el activo y permite
  elegir otro con un clic.
- Al elegir un cursor, el CLI:
  - valida que el tema existe;
  - escribe `xcursor-theme "<tema>"` dentro del bloque `cursor {}` del fichero
    que aporta el valor efectivo (normalmente `config.d/10-input-and-cursor.kdl`);
  - conserva `xcursor-size`, `hide-when-typing` y cualquier otra línea del bloque;
  - recarga niri con `niri msg action load-config-file` para aplicar el cambio
    sin reiniciar la shell.
- El QML sólo invoca al CLI; nunca escribe ficheros de configuración.

## No metas

- No cambiar el tema de iconos al cambiar el cursor, ni viceversa.
- No cambiar `xcursor-size` ni `hide-when-typing`.
- No instalar paquetes ni descargar cursores: sólo detectar los ya instalados.
- No generar miniaturas reales de Xcursor (formato binario); la celda usa un
  glifo de puntero y el nombre del tema.
- No modificar Plasma, KWin, `kdeglobals`, autostart ni `40-environment.kdl`.
- No reiniciar Quickshell para aplicar el cursor: éste se aplica con recarga de
  niri. La única recarga de la shell prevista es al final, para cargar el QML
  nuevo, y no cambia las preferencias de KDE.

## Restricciones

- Español en respuestas, tests y textos de UI.
- TDD estricto: test rojo antes de cada cambio de comportamiento.
- CLI como única puerta al sistema.
- Sin commits sin petición explícita.
- No delegar a agentes premium; trabajo directo con el modelo actual.
- No afectar el funcionamiento de la shell con KDE.

## Enfoques considerados

1. **Pestañas dentro de "Niri configs" (elegido por el usuario).** Una sola
   categoría, dos vistas hermanas, mismo rail y mismo `Loader`. Mantiene el
   descubrimiento cerca de los iconos y evita llenar el rail. El 2026-11-22 el
   usuario precisó que el contenedor use el mismo patrón visual que las demás
   categorías: `Flickable` con cabecera y `SegmentedChoice`, no botones caseros.
2. **Dos secciones con scroll en una sola página.** Menos código de navegación,
   pero empuja la lista de cursores fuera de la vista y mezcla dos listas largas.
3. **Categoría `Cursor` separada.** Más visible, pero contradice el pedido de
   poner la opción “en esta categoría” y agita el rail de niri.

## Diseño de las partes

### CLI — `integration/bin/caparazon-wm.py`

Nuevo bloque `# --- tema de cursor ---`, espejo del de iconos.

- `caparazon-wm cursor-theme` → JSON por stdout:

  ```json
  {
    "current": "breeze_cursors",
    "themes": ["Adwaita", "breeze_cursors", "Oxygen_Black", "..."],
    "default": "breeze_cursors",
    "configured": true
  }
  ```

  - `current`: valor efectivo de `xcursor-theme` en el árbol de includes de niri;
    si no está configurado, `default`.
  - `configured`: distingue “elegido” de “por defecto”.
  - `themes`: nombres de directorios con subdirectorio `cursors/`, ordenados.

- `caparazon-wm cursor-theme --set <tema>`:
  - valida contra `themes`;
  - llama a `write_cursor_theme(name)`;
  - ejecuta `niri msg action load-config-file`;
  - tema desconocido → código 1 con mensaje en stderr;
  - recarga fallida → código 1 con mensaje en stderr (config ya quedó escrita).

- Detección de temas:
  - raíces: `<XDG_DATA_DIRS>/icons`, `<XDG_DATA_HOME>/icons`, `~/.icons`,
    `~/.cursors`;
  - un tema es `<raíz>/<nombre>/cursors` existente;
  - entorno aislado en tests mediante `HOME`, `XDG_DATA_DIRS`, `XDG_DATA_HOME`.

- Lectura/escritura:
  - `read_niri_cursor_theme(text)` extrae `xcursor-theme` del bloque `cursor {}`.
  - `read_cursor_theme_file(path)` usa `_kdl_lines_in_load_order`; gana el último
    valor, igual que con los iconos.
  - `set_niri_cursor_theme(text, name)` reemplaza o agrega la línea dentro del
    bloque `cursor {}` sin tocar el resto.
  - Si no hay bloque `cursor`, se agrega al final del fichero dueño.
  - `write_cursor_theme(name)` elige el fichero dueño con el mismo mecanismo de
    includes que `write_icon_theme`; escritura atómica vía `.tmp` + `os.replace`.

- `DEFAULT_CURSOR_THEME = "breeze_cursors"`, coherente con el estado actual de
  esta máquina. No depende de `XCURSOR_THEME` para que el JSON sea estable.

### QML — el nombre de la categoría

- `modules/secondmenu/SecondMenu.qml`:
  - `iconCategory` pasa a llamarse `niriConfigsCategory`;
  - clave interna: `key: "niri-configs"`;
  - etiqueta visible: `label: "Niri configs"`;
  - mismo icono `preferences-desktop-theme`;
  - `categories` lo concatena igual, sólo si `CompositorService.niri`;
  - el `Loader` monta `NiriConfigsPanel` cuando
    `root.category === "niri-configs"`.
- Se actualizan los tests que hoy esperan `"iconos"` / `IconThemePanel`.

### QML — el contenedor de "Niri configs"

- `modules/secondmenu/NiriConfigsPanel.qml` (nuevo):
  - raíz `Flickable` con `clip`, `contentWidth`, `contentHeight` calculado desde
    `body.implicitHeight`, `boundsBehavior: Flickable.StopAtBounds` y
    `interactive: contentHeight > height`, igual que `ShellConfigPanel`;
  - `Column` `body` con cabecera `Row` de altura 22 y texto `Niri configs`,
    `Theme.fontUI`, 15 px y `Font.DemiBold`, igual que `ShellConfigPanel` y
    `SystemMonitorPanel`;
  - `readonly property var sections` con objetos `{ key, label }`:
    `iconos`/`Iconos` y `cursor`/`Cursor`. Agregar una opción futura del
    compositor sólo requiere una entrada nueva y su rama en `componentFor`;
  - `SegmentedChoice` compartido con `options: root.sections`, `value: root.tab`
    y `onPicked: (key) => root.tab = key`. No se mantienen botones caseros;
  - `componentFor(key)` resuelve `"cursor"` a `cursorComponent` y cualquier otra
    clave a `iconComponent`; el `Loader` usa `root.componentFor(root.tab)`;
  - el cuerpo carga `IconThemePanel` o `CursorThemePanel` con
    `anchors.fill: parent`, dentro de un host con altura explícita;
  - sin `Process`, sin ficheros, sin lógica de compositor.

### QML — la pestaña Cursor

- `modules/secondmenu/CursorThemePanel.qml` (nuevo):
  - espejo de `IconThemePanel`, sin `previews`;
  - `Process` de carga: `["caparazon-wm", "cursor-theme"]`;
  - `Process` de aplicación:
    `["caparazon-wm", "cursor-theme", "--set", root.pendingTheme]`;
  - estado: `themes`, `current`, `defaultTheme`, `pendingTheme`, `errorMessage`,
    `noticeMessage`, `applying`;
  - `GridView` con celda de 104 px de alto, glifo `↖`, nombre del tema y
    resaltado del activo;
  - mensaje al aplicar: `Cursor aplicado.`;
  - mensaje de error: lo que diga stderr, o `No se pudo aplicar el cursor`;
  - no menciona reinicio de shell; no escribe ficheros.

### Tests

- `tests/test_caparazon_wm.py`:
  - estado lista temas desde `icons/<tema>/cursors` y `~/.cursors/<tema>/cursors`;
  - estado lee `xcursor-theme` desde include (`10-input-and-cursor.kdl`);
  - `--set` actualiza el include y conserva `xcursor-size` y `hide-when-typing`;
  - `--set` crea bloque `cursor` si falta;
  - `--set` rechaza tema desconocido;
  - `--set` invoca `niri msg action load-config-file` (fake `niri` que registra
    argumentos).
- `tests/test_icon_theme_niri.py` (o archivo nuevo hermano):
  - la categoría es `niri-configs` / `Niri configs` y sigue sólo en niri;
  - `SecondMenu` monta `NiriConfigsPanel`;
  - el wrapper es `Flickable`, usa `SegmentedChoice` con secciones
    `Iconos`/`Cursor`, resuelve componentes con `componentFor` y carga ambos
    paneles;
  - `CursorThemePanel` habla con `cursor-theme` y no escribe configuración;
  - el usage del CLI incluye `cursor-theme`.

## Orden de ejecución previsto

1. Aprobar este diseño.
2. Invocar `writing-plans` y escribir el plan de implementación.
3. TDD: tests rojos de CLI y QML.
4. Implementar CLI, luego paneles, luego rename del rail.
5. Sincronizar `~/.local/bin/caparazon-wm`, correr suite completa, relanzar
   Quickshell y verificar en vivo: pestañas visibles, lista de temas, cambio
   aplicado y `xcursor-theme` reescrito sin tocar `xcursor-size`.
6. No commitear.
