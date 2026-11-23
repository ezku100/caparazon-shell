# Diseño: reorden de Niri configs, resoluciones plegables y teclado

Fecha: 2026-11-22 · Estado: enfoque elegido por el usuario; pendiente de aprobación del documento.

## Intención

El usuario pidió tres cambios en la categoría **Niri configs**:

1. subir **Monitores** y dejar **Iconos** abajo;
2. hacer que las resoluciones sean desplegables para no ocupar espacio de más;
3. agregar un selector de idioma de teclado con las variantes más comunes —por ejemplo español y español latinoamericano— que modifique de verdad el config de niri para aplicarlo.

Se eligió el enfoque **Agrupado + CLI**: Monitores arriba, Teclado en medio, separador e Iconos/Cursor abajo; resolución en un `select` compacto; teclado agrupado por idioma/variante y persistido por `caparazon-wm`.

## Hechos verificados

- `NiriConfigsPanel.qml` hoy tiene este orden: cabecera → `Sección` + `SegmentedChoice` (`Iconos`, `Cursor`) → host de iconos/cursor → separador → `Monitores` → host de monitores.
- `tests/test_niri_configs_panel.py` afirma explícitamente que `panelHost` viene antes que `monitorsHost`; ese contrato debe invertirse.
- `MonitorsPanel.qml` muestra todas las resoluciones en un `Repeater` visible de forma permanente.
- El panel raíz mantiene un solo `Flickable` con `contentHeight: body.implicitHeight`; los paneles hijos usan `implicitHeight` y no deben crear otro scroll.
- Niri acepta `input.keyboard.xkb.layout` y `input.keyboard.xkb.variant` (docs: `Configuration:-Input`); ambos se pasan a libxkbcommon.
- `latam` es un **layout** propio de xkb, no una variante de `es`; “Español (Latinoamérica)” se representa como `layout "latam"` sin `variant`.
- La config real `/home/ezku/.config/niri/config.d/10-input-and-cursor.kdl` tiene `input { keyboard { xkb { layout "us" } } }` y además `options` en comentarios de ejemplo.
- `caparazon-wm` ya expone `icon-theme` y `cursor-theme` con JSON de estado, validación, escritura atómica del fichero dueño del include y `reload_niri_config()`.
- `~/.config/niri/config.d/40-environment.kdl`, `~/.config/autostart/caparazon.desktop` y la config de KDE quedan fuera de alcance.

## Metas

- Reordenar el cuerpo de `NiriConfigsPanel.qml`: Monitores primero, Teclado después, Iconos/Cursor al final.
- Convertir la lista de resoluciones en un control compacto que muestre la resolución activa y abra la lista sólo al pulsarlo.
- Agregar `KeyboardLayoutPanel.qml` con idiomas comunes agrupados y sus variaciones visibles.
- Agregar el subcomando `keyboard-layout` a `caparazon-wm` para leer y escribir `layout`/`variant` en el config de niri, con recarga en vivo.
- Mantener el único scroll del panel, el patrón visual existente y el contrato de que QML nunca escribe ficheros ni invoca `niri` directamente.
- Cubrir cada cambio con tests antes de implementarlo.

## No metas

- No tocar Plasma, KWin, `kdeglobals`, `40-environment.kdl`, `50-startup.kdl` ni autostart.
- No cambiar iconos, cursor, monitores ni atajos de teclado al elegir un idioma.
- No exponer `options`, `model`, `rules` ni `file` de xkb en la UI; se conservan intactos en el config.
- No ofrecer todos los layouts del sistema ni depender de `localectl` en caliente: el catálogo es curado y estable.
- No crear un segundo `Flickable`, `GridView` interactivo ni componentes de `QtQuick.Controls`.
- No automatizar comprobaciones visuales con mouse/capturas sin permiso explícito del usuario.

## Restricciones

- Responder y rotular en español.
- TDD estricto: test rojo antes de cada cambio de comportamiento.
- CLI como única puerta al sistema.
- Sin commits salvo petición explícita.
- Sin delegación a agentes premium; trabajo directo con el modelo actual.
- Ejecución nativa: `pytest`, `qmllint`, `ruff`, CLI real contra config real.
- No afectar el funcionamiento de la shell con KDE.

## Enfoques considerados

1. **Agrupado + CLI (elegido).** Monitores arriba, teclado en medio, iconos/cursor abajo; resolución compacta; catálogo curado por idioma/variante y CLI con `keyboard-layout`.
2. **Catálogo mínimo.** Misma estructura, pero sólo español e inglés; se descartó porque el usuario pidió “los más comunes”.
3. **Acordeón inline.** Misma estructura pero la lista de resoluciones empuja el contenido hacia abajo; se descartó porque el objetivo era no ocupar espacio.

## Decisiones de diseño

### Catálogo de teclado

| Idioma | Opción | `layout` | `variant` |
|---|---|---|---|
| Español | España | `es` | `""` |
| Español | Latinoamérica | `latam` | `""` |
| Inglés | EE. UU. | `us` | `""` |
| Inglés | EE. UU., internacional | `us` | `intl` |
| Inglés | Reino Unido | `gb` | `""` |
| Portugués | Brasil | `br` | `""` |
| Portugués | Portugal | `pt` | `""` |
| Francés | Francia | `fr` | `""` |
| Francés | Canadá | `fr` | `ca` |
| Alemán | Alemania | `de` | `""` |
| Italiano | Italia | `it` | `""` |
| Japonés | Japón | `jp` | `""` |

- `DEFAULT_KEYBOARD_LAYOUT = "us"`, coherente con la máquina actual.
- Una combinación configurada fuera del catálogo se muestra tal cual (`layout`/`variant`) y no se marca como activa en la UI; nunca se reemplaza silenciosamente.
- El catálogo vive en Python y se serializa al JSON; QML no duplica la lista de códigos xkb.

### CLI — `integration/bin/caparazon-wm.py`

Nuevo bloque `# --- idioma de teclado ---`, espejo del de cursor.

- `caparazon-wm keyboard-layout` imprime:

  ```json
  {
    "layout": "us",
    "variant": "",
    "label": "Inglés (EE. UU.)",
    "configured": true,
    "languages": [
      {
        "label": "Español",
        "options": [
          {"layout": "es", "variant": "", "label": "España"},
          {"layout": "latam", "variant": "", "label": "Latinoamérica"}
        ]
      }
    ]
  }
  ```

- `caparazon-wm keyboard-layout --set <layout> [variant]`:
  - `variant` es opcional; omitirlo equivale a `""`;
  - valida que la combinación exista en el catálogo;
  - unknown combination → código 1 y mensaje en stderr;
  - escribe y recarga con `reload_niri_config()`;
  - recarga fallida → código 1 con mensaje explícito; el config ya quedó guardado.
- Lectura:
  - usa `_kdl_lines_in_load_order()` para obtener el `layout` y `variant` efectivos;
  - gana el último valor dentro del bloque `xkb {}`;
  - `configured: false` si no hay `layout` en el árbol; en ese caso el valor effective es `us`.
- Escritura:
  - `set_niri_keyboard_layout(text, layout, variant)` reemplaza o agrega `layout "<layout>"` dentro del bloque `xkb {}`;
  - agrega `variant "<variant>"` sólo si no está vacío; si está vacío, elimina cualquier `variant` previo para no dejar residuos;
  - conserva `options`, `model`, `rules`, comentarios y el resto del fichero;
  - el fichero dueño se resuelve así: último archivo que aporta `layout`/`variant` efectivo, si no el que contiene `xkb {`, si no `config.d/10-input-and-cursor.kdl` cuando exista, si no el root;
  - si no hay bloque `xkb`, se crea dentro de `input { keyboard { ... } }`, o `input { keyboard { xkb { ... } } }` completo si no existe;
  - escritura atómica con `.tmp`, `chmod 0o644` y `os.replace`, igual que temas y monitores.
- El `usage` de `main()` incluye `keyboard-layout`.

### QML — `modules/secondmenu/KeyboardLayoutPanel.qml` (nuevo)

- `Item` con `implicitHeight: content.implicitHeight + 12`, igual que los paneles hermanos.
- `Process` de carga: `["caparazon-wm", "keyboard-layout"]`.
- `Process` de aplicación: `["caparazon-wm", "keyboard-layout", "--set", root.pendingLayout]` o con `root.pendingVariant` como cuarto argumento cuando no esté vacío.
- Estado: `layout`, `variant`, `label`, `languages`, `pendingLayout`, `pendingVariant`, `pendingLabel`, `applying`, `errorMessage`, `noticeMessage`.
- Controles sin `QtQuick.Controls`:
  - texto **Idioma** y `Grid` + `Repeater` de chips con los `languages` del JSON;
  - texto **Variación** y `SegmentedChoice` con las `options` del idioma pendiente;
  - texto **Aplicado** con `label` devuelto por la CLI;
  - botón **Aplicar**, deshabilitado si no hay cambio pendiente o mientras aplica;
  - texto de error/aviso con `Theme.m3Error` / `Theme.textDim`.
- Al elegir idioma se toma su primera variante como pendiente; al elegir variante se actualiza la combinación pendiente.
- No contiene `FileView`, rutas `.config/niri`, `niri` ni `caparazon-wm` fuera de los `Process`.

### QML — `modules/secondmenu/NiriConfigsPanel.qml`

Orden final del `Column body`:

1. cabecera `Niri configs`;
2. `Monitores` + `monitorsHost` (`monitorComponent`);
3. separador;
4. `Teclado` + `keyboardHost` (`keyboardComponent`);
5. separador;
6. `Sección` + `SegmentedChoice` de `Iconos`/`Cursor`;
7. `panelHost` con `componentFor(root.tab)`.

- Se mantiene `property string tab: "iconos"`; el control segmentado sigue gobernando sólo iconos/cursor.
- Se agregan `keyboardComponent` y `keyboardHost`, con altura从 `keyboardLoader.item.implicitHeight`.
- El wrapper sigue sin `Process`, sin `caparazon-wm` y sin rutas de config.
- Los tests de orden se invierten: `monitorsHost` antes que `keyboardHost`, y `keyboardHost` antes que `panelHost`.

### QML — `modules/secondmenu/MonitorsPanel.qml`

- Nuevo `property bool resolutionsOpen: false`, cerrado por defecto.
- Nueva función `selectedModeLabel()` que devuelve la resolución pendiente o `Sin monitores`.
- El bloque actual de `Text: "Resolución y tasa"` se sustituye por:
  - encabezado `Resolución y tasa`;
  - `Rectangle` disparador con el texto de `selectedModeLabel()` y un caret `▾`/`▴`;
  - `MouseArea` que alterna `root.resolutionsOpen`;
  - `Column` contenedor con `height: root.resolutionsOpen ? modesList.implicitHeight : 0`, `clip: true` y `visible: root.resolutionsOpen`;
  - `Column modesList` con el `Repeater` actual de modos, sin cambios en la lógica de selección ni en el resaltado activo.
- No se agrega scroll, popup ni animación nueva; sólo se oculta/muestra la lista existente.

### DESIGN.md

Como no existe `DESIGN.md`, se crea uno para codificar el sistema visual ya presente: tokens de `Theme.qml`, tipografía, radios, espaciado, `SegmentedChoice`, chips, botones, hosts con `implicitHeight`, un solo `Flickable` y límite CLI. Esto satisface el gate de frontend sin introducir un lenguaje visual nuevo.

### Tests

- `tests/test_keyboard_layout_cli.py` (nuevo):
  - catálogo y etiquetas;
  - lectura de `layout`/`variant` desde include y desde root;
  - fallback a `us` cuando no hay config;
  - `--set es` y `--set latam` escriben el layout correcto;
  - `--set us intl` agrega `variant "intl"`;
  - `--set us` elimina un `variant` previo;
  - conserva `options` y comentarios dentro de `xkb`;
  - combinación desconocida falla;
  - invoca `niri msg action load-config-file` con un `niri` falso.
- `tests/test_keyboard_layout_panel.py` (nuevo):
  - carga y aplica vía `caparazon-wm keyboard-layout`;
  - no contiene `FileView`, `.config/niri` ni `niri`;
  - usa `Grid` + `Repeater` para idiomas y `SegmentedChoice` para variaciones;
  - el command de apply incluye la variante sólo cuando no está vacía.
- `tests/test_niri_configs_panel.py`:
  - actualizar orden de hosts;
  - verificar `keyboardComponent`, `keyboardHost`, `keyboardLoader` y altura por `implicitHeight`;
  - reforzar que el wrapper no habla con el sistema.
- `tests/test_monitors_panel.py`:
  - verificar estado plegado, disparador, carete y lista oculta;
  - verificar que el `Repeater` y el resaltado activo siguen presentes.
- Verificación final: tests focalizados, suite completa, `qmllint` de los QML tocados, `ruff` focalizado, `py_compile`, `git diff --check` y `caparazon-wm keyboard-layout` real. Sin QA visual automatizado.

## Orden de ejecución previsto

1. Aprobar este diseño.
2. Invocar `writing-plans` y escribir el plan TDD.
3. Tests rojos de CLI, QML de teclado, orden del wrapper y resoluciones plegables.
4. Implementar CLI; luego `KeyboardLayoutPanel`; luego reorden del wrapper; luego resoluciones.
5. Sincronizar `~/.local/bin/caparazon-wm` si aplica y correr verificación nativa.
6. No commitear.
