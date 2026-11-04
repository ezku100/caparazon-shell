# Dock: segunda pulsación minimiza o restaura — diseño

Fecha: 2026-11-04

## Qué se quiere

Hoy, al pulsar el icono de una app que ya tiene ventanas, el dock sólo la enfoca
(`KWinFocusApp.js`): pulsar mil veces el icono deja la ventana siempre visible y
enfocada. Se quiere el comportamiento habitual de un dock:

- **Primer clic** sobre el icono de una app abierta → se enfoca su ventana (o se
  restaura si estaba minimizada).
- **Segundo clic** sobre el mismo icono, con esa ventana ya enfocada → se
  **minimiza**.
- **Clic** sobre el icono de una app cuya ventana está **minimizada** → se
  **restaura** y vuelve a enfocarse.

En una app con varias ventanas manda la que está enfocada; si la app no está
enfocada, el clic la enfoca sin más.

## Por qué en KWin y no en la shell

KWin 6.7.4 no expone `ext-foreign-toplevel-management`, así que Quickshell no
ve el estado de las ventanas (minimizada, maximizada). El único sitio donde ese
estado existe es el compositor, y ahí se llega con un script de KWin.

Verificado en la máquina con una sonda de sólo lectura sobre KWin 6.7.4:

| propiedad del script        | lectura | escritura |
|-----------------------------|---------|-----------|
| `window.minimized`          | sí      | **sí** (`setMinimized`) |
| `window.active`             | sí      | no        |
| `workspace.activeWindow`    | sí      | **sí** (`workspace.activeWindow = w`) |
| `window.maximizable`        | sí      | no        |

Y verificado también el ciclo completo: `window.minimized = true` deja la
ventana minimizada y `window.minimized = false` la restaura, sin robar el foco
(la ventana activa siguió siendo la misma).

## Enfoques considerados

1. **Que KWin decida (elegido).** Un script de KWin recibe el appId y decide:
   si hay una ventana minimizada → la restaura; si la app está enfocada → la
   minimiza; si no → la enfoca. KWin tiene el estado real, así que no hay que
   duplicarlo ni mantenerlo sincronizado en la shell.
2. **Que la shell decida.** Habría que publicar el estado (minimizada por
   ventana) desde KWin hasta la shell y mantenerlo actualizado en cada cambio:
   más código, más superficie y una fuente de verdad duplicada. Se descarta.
3. **Usar `ToplevelManager` de Quickshell.** Es la vía limpia, pero KWin 6.7.4
   no implementa el protocolo que necesita. Se descarta.

## Decisiones

- **Un solo script nuevo**: `modules/bar/KWinWindowAction.js`, que sustituye a
  `modules/bar/KWinFocusApp.js` (mismo mecanismo de carga por `gdbus`, pero
  además decide entre minimizar, restaurar y enfocar).
- **Dos datos de entrada**: `__TARGET__` (el appId elegido) y `__ACTIVE__` (la
  app que la shell cree que está enfocada). El segundo es una red de seguridad:
  si el clic sobre el dock llegara a robar el foco, `workspace.activeWindow` ya
  no apuntaría a la app y sin esta pista no se podría distinguir "enfocar" de
  "minimizar".
- **La decisión vive en el script**, no en el QML: así se puede probar con node
  contra un `workspace` falso, sin compositor.
- **El dock sigue sin robar foco**: los paneles de Quickshell no son ventanas
  normales para KWin, así que pulsar un icono no cambia la ventana activa
  (comprobado: con kitty enfocada, la ventana activa seguía siendo kitty).
- **Clic rápido**: si hay una acción en curso, se cancela y se lanza la nueva
  con el appId nuevo; si no, se perdía el segundo clic.
- **Clic central** y **menú contextual**: sin cambios.

## Fuera de alcance

- Maximizar/desmaximizar de verdad (la ventana maximizada ya se restaura como
  estaba; `maximized` no es escribible en el script de KWin 6.7.4).
- Miniaturas o ventanas del grupo (lo que hace el dock de Plasma).
- Ciclar entre varias ventanas de la misma app con clics sucesivos.

## Archivos

- `modules/bar/KWinWindowAction.js`: script de KWin nuevo (decide y actúa).
- `modules/bar/KWinFocusApp.js`: se elimina (queda código muerto).
- `modules/dock/Dock.qml`: pasa `__TARGET__` y `__ACTIVE__`, y relanza la acción
  en curso si llega otro clic.
- `tests/support/kwin_window_action_harness.js`: escenarios con `workspace` falso.
- `tests/test_dock_window_action.py`: contrato de los escenarios y del cableado.
- `README.md`: describe el comportamiento de la segunda pulsación.

## Verificación

- `uv run pytest -q` y `uv run ruff check` limpios.
- En vivo: con una app enfocada, el icono la minimiza al segundo clic y la
  restaura al tercero; una app en segundo plano se enfoca al pulsarla.
