# Iconos de tema en la barra: fin de los glifos Nerd Font

Fecha: 2026-10-28
Estado: aprobado en conversación con el usuario

## Intención y por qué

Quedan trece iconos dibujados con glifos de JetBrainsMono Nerd Font: los cuatro
del menú de sesión, los seis del chip de audio (altavoz y micrófono), los dos
del selector de perfil de energía y el del botón de energía. Todo el resto de la
shell —CPU, RAM, GPU, swap, red, bluetooth, menú de aplicaciones, lupa, dock,
bandeja y lanzador— ya resuelve sus iconos por nombre contra el tema activo con
`IconResolver`.

Eso tiene dos costes. La fuente no está en los repositorios de Debian y hay que
instalarla a mano; y esos trece iconos no cambian cuando el usuario cambia de
tema, porque son glifos de una fuente, no iconos de un tema. Este trabajo los
convierte y quita la dependencia.

## Objetivos

- Que ningún icono de la shell se dibuje con glifos de Nerd Font.
- Conservar estados, tamaños y colores: el cambio debe notarse lo justo.
- Que esos iconos salgan del tema activo, como los del resto de la barra.
- Quitar el requisito de Nerd Font del README y el aviso del instalador.
- No añadir dependencias nuevas.

## No objetivos

- No se rediseña el menú de sesión ni el chip de audio: sólo cambia el dibujo
  del icono.
- No se toca la tipografía de texto (las frases de despedida ni los números de
  Workspaces).
- No se cambia la forma de resolver iconos: sigue siendo `IconResolver`.
- No se toca el vigilante del tema: un cambio de tema sigue reiniciando la
  shell, porque el tema se lee una vez por proceso (medido en el spec del
  2026-10-27).

## Anti-objetivos

- Un icono que desaparece cuando el tema no trae un nombre: no. Siempre hay
  alternativas y, en último caso, el genérico.
- Perder el cambio de color del icono al pasar el ratón.
- Introducir rutas absolutas de iconos.
- Dejar Nerd Font como requisito "por si acaso" cuando ya no se usa.

## Restricciones (medidas, no supuestas)

Tema de iconos activo: `Tela-dark` (`[Icons] Theme` en `~/.config/kdeglobals`).

Herencia de temas, leída de cada `index.theme`: `Tela-dark` → `hicolor`,
`Adwaita`, `breeze`; `Colloid-Dark` y `Reversal-dark` → `hicolor`, `breeze`;
`breeze` → `hicolor`; `breeze-dark` → `breeze`, `hicolor`; `Adwaita` →
`AdwaitaLegacy`, `hicolor`; `Papirus` → `breeze`, `hicolor`. `ePapirus` y
`ePapirus-Dark` están instalados vacíos, sin un solo icono: no cuentan.

`IconResolver.byName` prueba el nombre exacto, el mismo sin `-symbolic`, con
`-symbolic` y en minúsculas. Por eso basta con el nombre "bonito", y los temas
que sólo traen la variante simbólica (`Adwaita`) también resuelven.

El índice de iconos del usuario **no** sirve de respaldo aquí: su `find` llega a
profundidad 2 sobre `~/.local/share/icons` y los iconos de un tema están a
profundidad 3-4, así que no se indexan. La resolución depende del tema activo y
de su herencia; de ahí que cada cadena lleve alternativas comprobadas tema por
tema.

Comprobado en disco, nombre exacto o `-symbolic`, en `Tela-dark`,
`Colloid-Dark`, `Reversal-dark`, `breeze`, `breeze-dark`, `Adwaita` y `Papirus`:

| Nombre | Temas que lo traen |
| --- | --- |
| `system-lock-screen` | los siete |
| `system-log-out` | los siete |
| `application-exit` | los siete |
| `system-shutdown` | los siete |
| `system-reboot` | los siete |
| `preferences-system-power` | Tela-dark, Colloid-Dark, Reversal-dark, Papirus |
| `audio-input-microphone` | los siete |
| `microphone-sensitivity-medium` | los siete |
| `microphone-sensitivity-muted` | los siete |
| `mic-off` | Tela-dark, Colloid-Dark, breeze, breeze-dark, Papirus |
| `microphone` | Colloid-Dark, Reversal-dark, breeze, breeze-dark, Adwaita |
| `audio-volume-high` | los siete |
| `audio-volume-medium` | los siete |
| `audio-volume-low` | los siete |
| `audio-volume-muted` | los siete |
| `power-profile-power-saver-symbolic` | Tela-dark, Colloid-Dark, Reversal-dark, Adwaita, Papirus |
| `power-profile-balanced-symbolic` | Tela-dark, Colloid-Dark, Reversal-dark, Adwaita, Papirus |
| `power-profile-performance-symbolic` | Tela-dark, Colloid-Dark, Reversal-dark, Adwaita, Papirus |
| `battery-profile-powersave` | Tela-dark, Colloid-Dark, Reversal-dark, breeze, breeze-dark, Papirus |
| `battery-profile-balanced` | breeze, breeze-dark, Papirus |
| `battery-profile-performance` | Tela-dark, Colloid-Dark, Reversal-dark, breeze, breeze-dark, Papirus |
| `battery-low` | los siete |

Las cadenas de la sección D1 están ordenadas para que **la primera que resuelva
exista siempre**, en cualquiera de los siete temas.

## Enfoques considerados

**A. Convertir los cuatro ficheros y quitar el requisito. Elegido.**
Trece glifos pasan a iconos de tema y la fuente deja de ser necesaria: se borra
del README y del instalador. Cierra el tema de una vez y deja la shell sin
dependencias fuera de los repos.

**B. Convertir los cuatro ficheros y dejar el requisito. Descartado.**
Mismo trabajo, pero sigue pidiendo instalar una fuente que ya no se usa para
nada. Documentación que miente.

**C. Sólo el menú de sesión (cuatro glifos). Descartado.**
Era el alcance inicial. Deja nueve glifos y la dependencia entera, y obliga a
volver sobre lo mismo más adelante.

## Decisiones

### D1. Las cadenas de nombres viven en JavaScript

`modules/icons/BarIcons.js`, cargado por QML como los otros módulos de la
carpeta y ejecutado por node en los tests, igual que `IconNames.js` e
`IconTheme.js`. El QML no decide nada: pregunta
`IconResolver.firstOf(BarIcons.volumeNames(muted, level, microphone))`.

| Dónde | Estado | Nombres, en orden |
| --- | --- | --- |
| Menú de sesión | bloquear | `system-lock-screen` |
| Menú de sesión | cerrar sesión | `system-log-out`, `application-exit` |
| Menú de sesión | apagar | `system-shutdown` |
| Menú de sesión | reiniciar | `system-reboot` |
| Botón de energía | siempre | `system-shutdown`, `preferences-system-power` |
| Chip de audio | micrófono activo | `audio-input-microphone`, `microphone-sensitivity-medium`, `microphone` |
| Chip de audio | micrófono silenciado | `microphone-sensitivity-muted`, `mic-off`, `audio-input-microphone` |
| Chip de audio | altavoz silenciado | `audio-volume-muted` |
| Chip de audio | altavoz bajo (< 40 %) | `audio-volume-low` |
| Chip de audio | altavoz medio (< 75 %) | `audio-volume-medium` |
| Chip de audio | altavoz alto | `audio-volume-high` |
| Perfil de energía | ahorro | `power-profile-power-saver-symbolic`, `battery-profile-powersave`, `battery-low` |
| Perfil de energía | equilibrado | `power-profile-balanced-symbolic`, `battery-profile-balanced`, `battery-low` |
| Perfil de energía | rendimiento | `power-profile-performance-symbolic`, `battery-profile-performance`, `battery-low` |

Las funciones devuelven copias de las listas, no las listas: así ningún QML
puede modificar la tabla por accidente.

### D2. Cómo se dibuja

`IconImage` de `Quickshell.Widgets` con `MultiEffect` en `colorization: 1.0`,
igual que `ResourceRing` y `PowerProfile`. La colorización sustituye el color
del icono por el del texto, que es lo que hoy hace `color` en cada `Text`.

Tamaños: 52 px en el menú de sesión (dentro del círculo de 128), 15 px en el chip
de audio (dentro del medidor de 26), 16 px en el perfil de energía y 15 px en el
botón. Son los tamaños que tienen hoy los glifos: nada se mueve.

Colores, sin cambios: en el menú, `Theme.m3Primary` en reposo y
`Theme.m3Surface` al pasar el ratón, animado con `Behavior on color`; en el chip,
`Theme.text` y `Theme.textDim` cuando está silenciado; el perfil y el botón
siguen con lo que ya usan.

### D3. Estados del chip de audio

La lógica se traslada tal cual: silenciado si `muted` o nivel ≤ 0.001; altavoz
bajo por debajo de 0.40, medio por debajo de 0.75, alto el resto; el micrófono
sólo tiene dos estados. El mute se sigue leyendo además por el color atenuado,
así que en un tema sin icono de micrófono silenciado el estado se distingue
igual.

### D4. Perfil de energía

Ya estaba mezclado: "equilibrado" usaba un icono de tema
(`power-profile-balanced-symbolic`) y los otros dos, glifos. Pasa a tres cadenas
por `IconResolver`. Un perfil desconocido se dibuja como equilibrado, que es lo
que hacía antes (glifo vacío → icono de equilibrado).

### D5. Fuera la dependencia

- `theme/Theme.qml`: se quita `fontIcon`, que queda sin ningún uso.
- `README.md`: se quita el requisito de Nerd Font de la lista de requisitos.
- `install.sh`: se quita `require_nerd_font` y su llamada.

## Piezas

| Archivo | Acción | Qué hace |
| --- | --- | --- |
| `modules/icons/BarIcons.js` | nuevo | Cadenas de iconos de la barra y los umbrales del chip de audio |
| `modules/bar/PowerMenu.qml` | editar | Cuatro iconos de tema en lugar de glifos |
| `modules/bar/VolumeChip.qml` | editar | Icono de tema para altavoz y micrófono |
| `modules/bar/PowerProfile.qml` | editar | Los tres estados con icono de tema |
| `modules/bar/PowerButton.qml` | editar | Icono de tema en lugar del glifo |
| `theme/Theme.qml` | editar | Quitar `fontIcon` |
| `README.md` | editar | Quitar el requisito de Nerd Font |
| `install.sh` | editar | Quitar `require_nerd_font` y su llamada |
| `tests/support/bar_icons_harness.js` | nuevo | Escenarios del módulo, en node |
| `tests/test_bar_icons.py` | nuevo | Contrato de las cadenas y los umbrales |
| `tests/test_bar_icon_wiring.py` | nuevo | Contrato del cableado de los cuatro QML |
| `docs/superpowers/plans/2026-10-28-iconos-de-tema.md` | nuevo | Plan de ejecución |

## Pruebas

- Con node: cada acción del menú devuelve su cadena; el chip de audio devuelve
  la cadena de silenciado cuando `muted` o nivel ≤ 0.001, la de micrófono en sus
  dos estados, y las de altavoz en los umbrales 0.40 y 0.75; un perfil
  desconocido devuelve la cadena de equilibrado; ninguna cadena sale vacía y
  todas empiezan por un nombre que existe en los siete temas.
- Contrato: los cuatro QML no contienen escapes `\u{F…` ni `Theme.fontIcon`, y
  sí usan `IconResolver.firstOf` y `BarIcons`; `Theme.qml` ya no define
  `fontIcon`; el README no menciona Nerd Font; `install.sh` no define
  `require_nerd_font`.
- Calidad: `uv run pytest -q`, `uv run ruff check .`, `uv run basedpyright`.
- En vivo: recargar la shell, capturar la barra y el menú abierto, comprobar que
  los iconos aparecen, que el hover cambia el color y que el log QML no tiene
  errores. Se compara con una captura de antes del cambio.

## Riesgos

- Los iconos de tema son más planos que los glifos: el menú de sesión puede
  verse algo distinto. Mitigación: mismos tamaños y colores; si no convence, se
  revierte el fichero.
- Un tema sin ninguno de los nombres deja el genérico. Afecta al aspecto, no a
  la función, y hoy pasaría lo mismo con la fuente ausente (cuadros).
- `IconImage` necesita `Quickshell.Widgets` en tres ficheros que hoy no lo
  importan; un import mal puesto rompe la carga de la shell entera. Se verifica
  con la shell real, no sólo con los tests.

## Cómo se entrega

Rama `feature/iconos-de-tema`, commits en español sin tildes, merge `--no-ff` a
`main` y push a `origin/main`, igual que las ramas anteriores.
