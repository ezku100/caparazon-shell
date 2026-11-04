# Dock inteligente: se aparta de las ventanas

Fecha: 2026-11-02
Estado: pendiente de aprobación

## Intención

El dock de Caparazón reserva hoy una franja de 52 px en el borde inferior
(`exclusiveZone`), así que las ventanas nunca lo tapan. El usuario quiere que el
dock ceda ese espacio: cuando una ventana se maximiza, el dock se esconde solo
para que la ventana ocupe también esa franja, y vuelve a salir bajo demanda
cuando el puntero se acerca al borde inferior.

El dock sigue siendo un dock **usable**: no sólo aparece, se puede usar; y en
cuanto el usuario deja de interactuar con él, se vuelve a esconder solo hasta
que se cumple la otra condición (la ventana se cierra o deja de estar
maximizada).

## Objetivos

- El dock se oculta automáticamente cuando hay una ventana maximizada o a
  pantalla completa en **esa** pantalla, liberando su franja reservada.
- Al mover el puntero por el borde inferior donde estaría el dock, el dock
  reaparece **por encima** de la ventana, sin redimensionarla ni empujarla.
- Mientras el dock está visible sobre la ventana, es interactivo (iconos,
  contador, menú contextual, widget de música).
- Al abandonar el dock, éste se vuelve a ocultar solo.
- Al cerrar la ventana o al quitarle el maximizado, el dock regresa a su
  sitio de siempre y vuelve a reservar su franja como hasta ahora.
- Todo es **por pantalla**: en multi-monitor, cada dock reacciona únicamente a
  las ventanas de su propia salida.

## Fuera de alcance (no-objetivos)

- Que el dock esquive ventanas **no** maximizadas: con la franja reservada,
  una ventana normal nunca llega al borde inferior, así que no hay conflicto.
  (Ver "Anti-objetivos".)
- Reveal por atajo de teclado. No se pide; se puede añadir después.
- Cambiar el comportamiento del dock en escritorios virtuales o por app.
- Reordenar o redimensionar ventanas: la shell no gestiona la disposición.
- Tiling de KWin: una ventana en modo tile no cuenta como maximizada.

## Anti-objetivos

- Que el dock siga visible **por debajo** de una ventana maximizada.
- Que la ventana maximizada se redimensione al revelar el dock (produce un
  parpadeo de 52 px que arruina la sensación de "overlay").
- Que el dock roba clics de la ventana en toda su franja: cuando está oculto,
  sólo se reserva una franja sensible delgada.

## Restricciones

- KWin 6.7.4 sobre Wayland; Quickshell 0.3.2; Qt 6.10.
- La franja del dock se reserva con `exclusiveZone` de un `PanelWindow`. Para
  que una ventana maximizada tome ese espacio hay que soltar la reserva
  (`exclusiveZone: 0`) y volver a tomarla al final.
- La shell hoy no sabe nada de geometría de ventanas: `ActiveWindowService.qml`
  sólo recibe `appId`/título y la lista de `appId`s.
- El puente con KWin ya existe y ya está instalado por `install.sh`:
  `integration/kwin/ezkudesktops` → D-Bus `org.ezku.Desktops.PushState` →
  `ezku-desktops-daemon.py` → `~/.cache/ezku-desktops.json`, que la shell ya
  lee con un `FileView` (`watchChanges: true`).

## Enfoques considerados

1. **Extender el puente `ezkudesktops` (elegido).** El script de KWin publica
   qué salidas tienen una ventana maximizada; el demonio lo guarda en el caché
   JSON; la shell lo lee con el `FileView` que ya existe.
   *A favor:* ruta `push` ya probada en producción, sin depender del journal,
   dato exacto por salida, no añade procesos ni ficheros nuevos.
   *En contra:* hay que recargar el script de KWin tras editarlo (detalle de
   desarrollo, no de despliegue: `install.sh` ya instala el fichero).
2. **Script propio de la shell publicado por el journal.** Un
   `KWinCoverage.js` nuevo, cargado por la shell como `KWinActiveTitle.js`.
   *A favor:* todo dentro del repo, cero despliegue.
   *En contra:* depende de que `journalctl --user` reciba los logs de
   `kwin_wayland`; el repo ya tiene un fallback por exactamente eso.
3. **Las dos rutas.** Más robusto, pero duplica el parseo y el mantenimiento
   para el mismo dato.

Se elige la **1**: es la ruta que el proyecto ya considera fiable.

## Detección en KWin

El API de scripts de KWin 6.7 da lo necesario sin adivinar alturas:

- `workspace.clientArea(workspace.MaximizeArea, client)` devuelve el
  rectángulo que ocupa una ventana maximizada **ya descontando** las franjas
  reservadas (el dock incluido).
- `client.frameGeometry` es la geometría real de la ventana.
- `client.fullScreen` marca las ventanas a pantalla completa.
- `client.output.name` identifica la salida.
- `client.maximizedChanged()` y `client.fullScreenChanged()` avisan del cambio
  en el instante; `client.frameGeometryChanged()` cubre los ajustes finos.

Regla: una ventana **cubre** su salida si está a pantalla completa, o si su
`frameGeometry` coincide (con una tolerancia de 2 px) con
`clientArea(MaximizeArea, client)`. La comparación se hace con la reserva del
dock ya descontada, así que funciona con cualquier combinación de paneles y no
depende de constantes como "52".

## Comportamiento del dock

Estados por pantalla:

| Estado | Qué hace el dock | `exclusiveZone` | Zona sensible (input) |
|---|---|---|---|
| `normal` | visible en su sitio | `dockHeight + bottomGap` | el dock (52 px, ancho del dock) |
| `oculto` | deslizado fuera de pantalla | `0` | franja de 6 px al borde inferior, ancho del dock |
| `revelado` | visible **sobre** la ventana | `0` | el dock (52 px, ancho del dock) |

Transiciones:

1. `normal` → `oculto`: aparece una ventana maximizada o a pantalla completa en
   esa salida. Se suelta la reserva (la ventana crece hasta el borde inferior)
   y el dock se desliza hacia abajo.
2. `oculto` → `revelado`: el puntero entra en la franja sensible de 6 px.
   El dock sube sobre la ventana; la reserva sigue en `0`, así que la ventana
   no se toca.
3. `revelado` → `oculto`: el puntero abandona la zona sensible. Se espera
   250 ms de gracia (evita parpadeos si el puntero roza el borde) y el dock
   vuelve a bajarse.
4. `oculto`/`revelado` → `normal`: la ventana se cierra o deja de estar
   maximizada. El dock vuelve a su sitio y recupera la reserva.

La franja sensible de 6 px se solapa con la parte inferior del propio dock,
de modo que al ampliar la zona sensible no se pierde el hover y no hay
parpadeo al revelarse.

Detalles de implementación (decisiones mías, no del usuario):

- El dock se oculta **deslizándose** hacia abajo (offset = `dockHeight +
  shadowPad`) con opacidad decreciente; 220 ms, `Easing.OutCubic`.
- 250 ms de gracia antes de esconder de nuevo.
- 6 px de franja sensible; ambos valores en `theme/Theme.qml`.
- La zona sensible se implementa con la `mask` (input region) del `PanelWindow`:
  se cambia de rectángulo según el estado. Al estar oculta, esa franja
  de 6 px es el único input que el dock roba a la ventana.
- `smartHide` en `~/.config/caparazon/dock.json` (por defecto `true`) permite
  desactivar el comportamiento sin tocar código.

## Ficheros tocados

| Fichero | Cambio |
|---|---|
| `integration/kwin/ezkudesktops/contents/code/main.js` | Detectar salidas cubiertas y publicarlas en el push; conectar `maximizedChanged`, `fullScreenChanged`, `frameGeometryChanged` y `outputChanged` para empujar el estado al instante. |
| `integration/bin/ezku-desktops-daemon.py` | Aceptar y persistir la nueva clave `covering` en `~/.cache/ezku-desktops.json`. |
| `modules/bar/ActiveWindowService.qml` | Exponer el mapa `covering` del caché (salida → appIds). |
| `shell.qml` | Pasar `covering` al delegate `Dock`. |
| `modules/dock/Dock.qml` | Máquina de estados, `exclusiveZone` dinámica, `mask` variable, animaciones, zona sensible. |
| `theme/Theme.qml` | Tokens de la franja sensible y de los tiempos de animación. |
| `tests/` | Tests de contrato: lógica de detección en JS y cableado en QML. |
| `README.md` | Documentar el comportamiento. |

## Lo que queda en manos del constructor

- Los valores exactos de la tolerancia (2 px) y de los tiempos: se ajustan
  probando en vivo.
- Si el `Mask` del `PanelWindow` necesita uniones de rectángulos o basta con
  un rectángulo que cambia de tamaño (la franja sensible está contenida en el
  rectángulo del dock, así que debería bastar con un único rectángulo).
- Verificar que `workspace.MaximizeArea` es accesible como propiedad del
  wrapper en el motor de scripts; si no, usar el valor numérico del enum y
  confirmarlo en ejecución.
