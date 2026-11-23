# DESIGN.md — Caparazón Shell

Estado: extraído del código existente el 2026-11-22. Este documento describe el sistema visual ya en uso; no propone un rediseño.

## Principios

- La fuente visual es `theme/Theme.qml`. Los componentes no inventan colores, tamaños ni animaciones nuevas.
- El submenú usa un solo `Flickable`; los paneles hijo crecen por `implicitHeight`. No se anidan scrolls.
- La interacción se construye con `QtQuick` básico: `Rectangle`, `Text`, `MouseArea`, `Grid`, `Column`, `Repeater` y el compartido `SegmentedChoice`. No se usa `QtQuick.Controls`.
- QML nunca escribe ficheros ni llama a `niri`: todo paso al sistema pasa por `caparazon-wm`.

## Color

Tokens de `Theme.qml`, todos opacos:

- Superficies: `m3Surface`, `m3SurfaceContainer`, `m3SurfaceContainerLow/High/Highest`.
- Texto: `m3OnSurface` (`Theme.text`), `m3OnSurfaceVariant` (`Theme.textDim`).
- Acento: `m3Primary`, `m3OnPrimary`, `m3Tertiary`.
- Bordes: `m3Outline`, `m3OutlineVariant` (`Theme.hairline`).
- Estado: `m3Error`, `m3ErrorContainer`, `m3OnErrorContainer`.
- Atajos usados por widgets: `chip = m3SurfaceContainerHigh`, `chipHover = m3SurfaceContainerHighest`.

Reglas:

- Fondo de panel: superficie del tema; selección fuerte: `m3SurfaceContainerHighest`.
- Elemento activo: borde de 2 px de `m3Primary` o relleno `m3Primary` con texto `m3OnPrimary`.
- Error: `m3Error`. Aviso o ayuda: `Theme.textDim`.
- Sin transparencias nuevas; la sombra y el glow viven en `Theme.qml`.

## Tipografía

- Familia: `Theme.fontUI` (`Noto Sans Display`); CJK: `Theme.fontJP`.
- Tamaños en uso: 11 px para ayuda/etiquetas, 13 px para controles y texto de lista, 15 px para cabeceras de categoría, 16 px para títulos de panel.
- Pesos: `Font.DemiBold` para cabeceras, títulos y selección; `Font.Normal` para el resto.
- El texto secundario usa `Theme.textDim` y `wrapMode: Text.WordWrap` cuando puede crecer.

## Forma y espacio

- Radio general: `Theme.radius` (16). Segmentos: radio 12.
- Espaciado típico: 4 px entre listas, 6 px entre chips, 8 px dentro de controles, 10 px entre bloques del `Column` raíz.
- Alturas recurrentes: 22 px cabecera de categoría, 28 px fila de lista/chip/botón pequeño, 34 px botón principal, 44 px `SegmentedChoice`.
- Padding lateral: 8 px dentro de chips; 14 px global (`Theme.padH`) cuando aplique.
- Un separador de 1 px usa `Theme.m3OutlineVariant`.

## Componentes

### `SegmentedChoice`

Archivo: `modules/secondmenu/SegmentedChoice.qml`.

- Fila de segmentos con `options: [{ key, label }]`, `value` y señal `picked(key)`.
- Activo: fondo `m3Primary`, texto `m3OnPrimary`. Inactivo: `Theme.chip`, texto `Theme.text`.
- Transición de color con `Theme.durFast`.
- No recorta etiquetas: usar textos cortos. Para catálogos más grandes, usar `Grid` + `Repeater` de chips.

### Chips de lista

- `Rectangle` con `radius: Theme.radius`, `height: 28`, fondo `Theme.chip`.
- Activo: `m3SurfaceContainerHighest`, borde `m3Primary` de 2 px, texto `Font.DemiBold`.
- Interacción: `MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor }`.

### Botón de acción

- `Rectangle` de 34 px, radio `Theme.radius`, fondo `m3Primary`, texto `m3OnPrimary` 12 px `DemiBold`.
- Deshabilitado o en curso: `Theme.chip` con `Theme.text`.
-Texto: verbos cortos en español (`Aplicar`, `Aplicando…`).

### Hosts de panel

- `Item` con `width: parent.width` y `height: loader.item ? loader.item.implicitHeight : 0`.
- `Loader { anchors.fill: parent; sourceComponent: ... }`.
- Nunca alturas fijas como `360` ni `Math.max(280, ...)` para contenido.

## Layout del submenú

- Raíz: `Flickable` con `clip: true`, `contentWidth: width`, `contentHeight: body.implicitHeight`, `boundsBehavior: Flickable.StopAtBounds` e `interactive: contentHeight > height`.
- `Column id: body` con `width: root.width`, `spacing: 10`.
- Cabecera: `Row id: header`, altura 22, texto 15 px `DemiBold`.
- Orden actual acordado para **Niri configs**: Monitores, separador, Teclado, separador, selector Iconos/Cursor, panel de temas.
- Las listas largas usan `Grid` + `Repeater` sin `GridView` interactivo.

## Interacción y feedback

- Un clic cambia selección pendiente; un botón **Aplicar** confirma los cambios persistentes.
- Los mensajes de estado van al final del panel, con error en `m3Error` y aviso en `Theme.textDim`.
- No se anuncian reinicios de shell cuando la acción sólo recarga niri.
- No se agrega sonido, vibración ni animación nueva; si hace falta, usar `Theme.durFast`/`Theme.dur`.

## Límites

- QML puede leer/escribir estado del sistema únicamente mediante `Process { command: ["caparazon-wm", ...] }`.
- Prohibido en QML de paneles: `FileView`, `.config/niri`, `~/.config`, `niri msg`, `localectl`, `kwriteconfig6`.
- La config de niri, KDE y autostart se modifica sólo desde la CLI, con escritura atómica y validación.
- No se toca `40-environment.kdl` ni `~/.config/autostart/caparazon.desktop`.

## Verificación visual

El QA visual lo hace el usuario de forma manual cuando lo pida. No se mueve el mouse ni se capturan pantallas sin permiso explícito.
