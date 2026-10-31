# Música: modo compacto con espectro

Fecha: 2026-10-30
Estado: propuesta (esperando aprobación)

## Objetivo

Un **modo compacto** en la categoría Música del menú secundario. Se activa con
un botón tipo pantalla completa y deja el panel en una vista limpia: el álbum
con su vinilo girando, el título y el artista pegados al álbum, y un
**espectro de audio** al pie del panel. Se ocultan la barra de progreso, los
botones de reproducción y la letra de la canción.

El modo es una decisión persistente: se recuerda entre aperturas del menú y
entre reinicios de la shell.

```
┌─────────────────────────────────────────┐
│                                  ┌───┐  │
│                                  │ ⛶ │  │  ← botón compacto (esquina sup. der.)
│                                  └───┘  │
│                                         │
│            ╭───╮╭───╮                   │
│            │ ▓ ││ ▓ │   álbum + vinilo  │  ← clic = play/pausa
│            ╰───╯╰───╯                   │
│                                         │
│              Título de la pista         │
│              Artista · Álbum            │
│                                         │
│                                         │
│      ▂▄▆█▆▄▂▂▄▆█▆▄▂▂▄▆█▆▄▂             │  ← espectro al pie
└─────────────────────────────────────────┘
```

## Decisiones tomadas

- **El álbum no se sustituye**: se queda con el vinilo girando (ya gira hoy
  mientras suena).
- **Debajo del álbum sólo va el título y el artista**. El espectro no se
  mete entre el álbum y el texto: se queda **al pie del panel**, ocupando el
  sitio de la barra de progreso que se oculta. Así el bloque álbum+texto queda
  junto arriba y el espectro usa el aire que sobra abajo.
- **Clic en el álbum = play/pausa**, porque en modo compacto desaparecen los
  botones de transporte. Funciona también en modo normal (mismo gesto, misma
  respuesta en los dos modos).
- La **rueda** sobre el álbum sigue cambiando de reproductor, como ya está
  implementado.
- Todo vive **dentro del submenú**: ni la barra ni el dock cambian.

## Qué se oculta y qué se ve

| Elemento | Modo normal | Modo compacto |
|---|---|---|
| Álbum + vinilo | sí | sí (con espectro debajo) |
| Título / artista | sí | sí |
| Barra de progreso (seek) | sí | **no** |
| Botones (aleatorio·anterior·play·siguiente·repetir) | sí | **no** |
| Letra (`lyricsCard`) | si hay letra | **no** |
| Espectro | no | **sí** |
| Botón ⛶ | sí | sí |

En modo compacto el `stage` ocupa todo el ancho del panel (como ya hace
cuando no hay letra) y la `controlsCard` desaparece: en su sitio, al pie del
panel, aparece el **espectro**, con el ancho completo del `body` y una altura
fija de 64 px. El `body` se encoge lo justo para dejarle sitio.

## Arquitectura

### 1. `modules/music/spectrumfeed.py` (nuevo)

Adaptación del `wavefeed.py` que ya usaste en el plugin de Noctalia
(`~/noctbeats/plugins/mediacontrols/wavefeed.py`), con las mismas
características:

- `cava` con salida `raw` a un FIFO (32 barras, 8 bits, mono average,
  `autosens`, `sensitivity = 100`).
- El script lee el FIFO y publica `{"ts": …, "spec": [32 valores 0-255]}` en
  `~/.cache/caparazon/waves.json` a ~12 fps (escritura atómica con `.tmp` +
  `os.replace`).
- Doble `fork` + `setsid` para vivir desvinculado del panel; el repo ya tiene
  la convención de un helper python (`modules/appmenu/clipboard-watch.py`).

Se llama **`spectrumfeed.py`** y no `wavefeed.py` a propósito: así el `pkill`
que lo detiene no mata el sampler del plugin de Noctalia (que usa otro
datadir pero el mismo nombre de script).

Ficheros que usa, todos en `~/.cache/caparazon/`: `cava.conf`, `cava.fifo`,
`waves.json`.

**Ciclo de vida**: el sampler arranca cuando se activa el modo compacto y se
detiene (`pkill -f "spectrumfeed[.]py"`) al salir de él. En modo normal no
gasta CPU.

### 2. `modules/music/Spectrum.qml` (nuevo)

Componente que dibuja el espectro. Es autónomo (no sabe nada del panel) para
poder reusarlo.

- `FileView` sobre `~/.cache/caparazon/waves.json` con `watchChanges: true` +
  `JsonAdapter` (patrón ya usado en `WorkspacesService` y
  `ClipboardHistoryService`).
- Suavizado: `level += (target - level) * 0.45`, igual que el plugin; cuando
  no hay reproducción los niveles decaen a 0.
- Dibujo: `Repeater` de 32 `Rectangle` con esquinas redondeadas, altura según
  el nivel, y color interpolado a lo ancho entre `Theme.m3Primary` y
  `Theme.m3Tertiary` (degradado del tema, como pediste).
- Altura mínima de 2 px para que siempre se note la base.

### 3. `modules/music/SpectrumMath.js` (nuevo)

Lógica pura en JS, como `ArtUrls.js`: mapeo de byte a nivel (0-255 → 0..1),
paso de suavizado y decaimiento. Se prueba con un harness de node en
`tests/support/` y pytest parametrizado, siguiendo la convención del repo.

### 4. `modules/music/MusicSettings.qml` (nuevo)

Servicio pequeño que recuerda el modo:

- Lee `~/.cache/caparazon/music-panel.json` (`{"compact": true}`) con
  `FileView` + `JsonAdapter`.
- Escribe con un `Process` (`printf` a `.tmp` + `mv`), como el resto de
  escrituras del repo.
- Expone `property bool compact` y `function save()`.

### 5. `modules/secondmenu/MusicPanel.qml` (modificado)

- `property bool compact`, enlazado a `MusicSettings`.
- Botón ⛶ en la esquina superior derecha del panel: chip circular de 28 px,
  opacidad 0.55 que sube a 1 al pasar el ratón. Icono `view-fullscreen` para
  entrar y `window-restore` para salir (resueltos con `IconResolver.firstOf`,
  con `view-fullscreen-symbolic` como alternativa).
- `lyricsCard` y `controlsCard` se ocultan cuando `compact` es cierto; el
  alto de `body` se recalcula en consecuencia.
- `Spectrum` se inserta como **hermano de `body`** dentro de `layout`,
  anclado abajo, a todo el ancho: es el pie del panel. Sólo visible en modo
  compacto; en modo normal el sitio lo ocupa la `controlsCard`.
- `MouseArea` sobre `discs` → `root.player.togglePlaying()`, con cursor de
  mano cuando hay reproductor y `canTogglePlaying`.
- El `WheelHandler` que ya está en `discs` se mantiene; clic y rueda conviven.

## Objetivo visual

- El espectro usa los colores del tema (`Theme.m3Primary` → `Theme.m3Tertiary`),
  así que cambia solo con la paleta de matugen, igual que el resto del panel.
- El botón ⛶ es discreto pero visible: chip `Theme.chip` con borde
  `Theme.hairline`, opacidad baja en reposo.
- Sin parpadeo: el espectro aparece ya con los valores de la última lectura
  (`waves.json` conserva el último frame), no desde cero.

## Metas

- El modo compacto se nota de un vistazo y no deja controles estorbando.
- El espectro se ve fluido (12 fps) y con los colores del tema.
- La decisión se recuerda: se abre el menú y el panel ya está en el modo que
  dejaste.
- Clic en el álbum pausa y reanuda.

## No-objetivos

- No tocar la barra ni el dock.
- No tocar el tema, la letra ni su búsqueda.
- No cambiar el comportamiento de "pausar uno pausa los dos".
- No hacer capturas ni añadir previews.
- No añadir opciones por reproductor ni un spectrum en la barra.

## Anti-objetivos

- Nada de sliders de tamaño, colores configurables ni modos extra: el modo
  compacto es un interruptor, no un panel de ajustes.
- Nada de Processes duplicados: un solo sampler, y sólo existe mientras el
  modo compacto está activo.

## Pruebas

- `tests/test_music_compact.py`: cableado estático (como los tests de
  `test_music_art.py`) — propiedad `compact`, botón, ocultación de
  `lyricsCard` y `controlsCard`, `Spectrum` en el `stage`, clic →
  `togglePlaying`, rutas de los ficheros de estado.
- `tests/support/spectrum_math_harness.js` + tests parametrizados en pytest
  para `SpectrumMath.js` (mapeo, suavizado, decaimiento).

## Trabajo pendiente para quien lo implemente

Nada: la decisión es completa. Las piezas que se tocan son las cinco de
arriba; el resto del repo no se modifica.
