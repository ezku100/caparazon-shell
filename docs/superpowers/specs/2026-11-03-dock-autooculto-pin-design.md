# Dock auto-oculto con pin — diseño

Fecha: 2026-11-03
Sustituye a: `2026-11-02-dock-inteligente-design.md` (detección de ventanas maximizadas).

## Qué se quiere

El dock del borde inferior está **oculto siempre** y sube al acercar el puntero al
borde inferior; se puede usar encima de cualquier ventana y se vuelve a ocultar al
dejar de interactuar. Un **botón de pin** dentro del dock lo deja **anclado**: visible
y reservando su franja, como el dock de siempre. El estado del pin se recuerda entre
sesiones.

Se abandona la detección de ventanas maximizadas: KWin 6.7.4 devuelve nombres de
salida que no coinciden con la geometría de la ventana (`c.output.name` decía
`HDMI-A-1` para una ventana en `DP-1`), así que el mapa `covering` podía apartar el
dock del monitor equivocado.

## Estados

Tres estados, calculados en `DockSmartHide.js`:

| `dockPinned` | puntero en el dock | estado     | ¿reserva franja? |
|--------------|--------------------|------------|------------------|
| `true`       | —                  | `anchored` | sí (52 px)       |
| `false`      | `true`             | `revealed` | no               |
| `false`      | `false`            | `hidden`   | no               |

- `hidden`: el dock baja `dockHeight + shadowPad` y sólo queda una franja sensible de
  `dockHotEdge` (6 px) pegada al borde inferior.
- `revealed`: el dock sube a su posición normal, flotando **encima** de la ventana.
- `anchored`: igual que el dock actual; la ventana maximizada respeta la franja.

## Configuración

`~/.config/caparazon/dock.json` gana `"dockPinned": false` (por defecto `false`, es
decir, nace oculto). Se escribe con `pinsFile.writeAdapter()`, el mismo mecanismo que
ya usa el anclaje de apps. Se elimina la clave `smartHide`.

## Botón de pin

- Icono `pin` al extremo derecho del dock, junto a los iconos de apps.
- Relleno cuando está anclado, contorno cuando no.
- Un clic alterna `dockPinned` y persiste el archivo.
- Vive dentro del dock, así que sólo se ve cuando el dock está revelado o anclado.

## Reglas de ocultado

- El puntero sobre el dock (o sobre su franja sensible) lo revela.
- Al salir hay una gracia de `Theme.dockHideGrace` (250 ms) antes de ocultarlo, para
  que cruzar hacia arriba no lo esconda por el camino.
- **No se oculta mientras haya un menú abierto** (menú de app, menú de música o menú
  de sesión abierto desde el dock): si el usuario está interactuando con él, debe
  seguir ahí aunque el puntero salga del rectángulo.
- Con el dock anclado no se oculta nunca.

## Qué se elimina

- `covering` en el script de KWin (`main.js`), en el demonio, en
  `ActiveWindowService.qml` y en `shell.qml`.
- Sus tests (`test_dock_covering.py`, `test_dock_covering_wiring.py`) y el harness
  `dock_covering_harness.js`.
- `smartHide` de `Dock.qml` y de la documentación.

El puente de escritorios (`ezku-desktops-daemon`) sigue existiendo para escritorios,
ventana activa y apps abiertas; sólo pierde el campo `covering`.

## Archivos

- `modules/dock/DockSmartHide.js`: estados y franjas con `anchored`.
- `modules/dock/Dock.qml`: pin, botón, guarda de menús, `exclusiveZone`, `maskRect`.
- `theme/Theme.qml`: sin cambios (`dockHotEdge`, `dockHideGrace` siguen sirviendo).
- `integration/kwin/ezkudesktops/contents/code/main.js`: quitar `covering`.
- `integration/bin/ezku-desktops-daemon.py`: quitar `covering`.
- `modules/bar/ActiveWindowService.qml`, `shell.qml`: quitar `covering`.
- `README.md`: describir el auto-ocultado y el pin.
- Tests: reescribir los del dock; borrar los de `covering`.

## Verificación

- Tests de contrato en verde (`pytest`, `ruff`).
- En vivo: dock oculto al arrancar, sube al borde inferior, responde a clics y menús
  sin desaparecer, se oculta al salir, el pin lo ancla y la ventana maximizada
  respeta la franja; reiniciar la shell conserva el pin.
