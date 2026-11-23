# Diseño: tema de iconos en niri y categoría dinámica "Iconos"

Fecha: 2026-11-21 · Estado: aprobado por el usuario

## Intención y por qué

En una sesión niri la shell arranca **sin iconos**: ni los de la barra y los
paneles (los de la propia shell) ni los del menú de aplicaciones (los que
traen las apps en su `.desktop`).

La causa está verificada y no es del QML: `IconResolver.qml` pide los iconos
**por nombre** a `Quickshell.iconPath()`, o sea al tema de iconos que Qt tenga
cargado. En Plasma, KDE pone ese tema en `~/.config/kdeglobals` y Qt lo
hereda. En niri no hay nada que lo configure: no existe `~/.icons/default`, así
que Qt arranca con `hicolor` y los nombres que usa la shell
(`preferences-desktop-emoticons`, `application-x-executable`, …) no existen
allí. `IconResolver` cae entonces en su icono genérico, que tampoco está, y
no se pinta nada.

`IconThemeWatcher.qml` no ayuda bajo niri: vigila `kdeglobals`, un fichero
que en niri no existe y que nadie escribe.

El objetivo es que en niri la shell use un tema de iconos real —**Papirus-Dark**
por defecto, como pidió el usuario— y que haya una **categoría dinámica en el
submenú** para ver y cambiar ese tema, que sólo aparezca en niri.

## Hechos verificados

- `papirus-icon-theme` (apt, 20260801-1) está instalado en esta máquina y trae
  `Papirus`, `Papirus-Dark`, `Papirus-Light` y `Papirus-Colors*`. El requisito
  es real: sin ese paquete no hay tema que usar.
- Temas instalados en `/usr/share/icons`: Adwaita, breeze, breeze-dark,
  Papirus*, hicolor, Oxygen*, KDE_Classic, desktop-base, locolor, …
- **No existe `~/.icons/default`** → en niri no hay tema configurado.
- `~/.config/kdeglobals` sí tiene `[Icons] Theme=Tela-dark` (lo usa Plasma).
- Qt lee el tema de iconos **al arrancar el proceso**: cambiarlo en caliente
  no repinta nada; hace falta reiniciar la shell.
- `~/.icons/default` es el mecanismo estándar que leen Qt y GTK, y no
  necesita permisos de root.
- `caparazon-wm detect` ya devuelve `niri` o `kwin` en texto plano.
- El `SecondMenu.qml` tiene un rail con cuatro categorías fijas
  (calendario, música, sistema, configs) y un `Loader` que monta el panel de
  la categoría activa.
- `IconTheme.js` ya tiene `relaunchCommand()` (mata el proceso y relanza con
  el mismo argv) y `restartCommand()` (vía `systemd-run`): el reinicio al
  cambiar un tema ya está resuelto.

## Metas

- En niri, la shell tiene tema de iconos desde el primer arranque: Papirus-Dark
  si el usuario no ha elegido otro.
- Los iconos del sistema (barra, rail, paneles) y los del menú de apps se
  resuelven con ese tema: es el mismo camino (`Quickshell.iconPath`), así que
  arreglar el tema arregla los dos grupos.
- Una categoría **"Iconos"** en el rail del submenú que sólo existe en niri:
  lista los temas instalados, marca el activo y permite elegir otro.
- Al elegir un tema, la shell **se reinicia sola** y los iconos cambian.
- Si el usuario ya tenía un tema configurado, no se toca.
- `papirus-icon-theme` queda documentado como **requisito** de la shell en niri.

## No metas

- No se toca la paleta de la shell: esto es sólo el tema de **iconos**.
- No se escribe en `/usr/share/icons` ni se instalan temas: sólo se elige entre
  los ya instalados y se apunta en `~/.icons/default`.
- No se cambia el comportamiento de Plasma: allí manda KDE y su watcher actual
  sigue igual.
- No se resuelve el caso de los `.desktop` que apuntan a una ruta absoluta
  fuera de cualquier tema: `IconResolver` ya lo indexa.
- No se instalan paquetes desde la shell.

## Restricciones

- El CLI es la única puerta al sistema (regla del repo): el QML no escribe
  ficheros de configuración del sistema por su cuenta.
- TDD: test rojo antes de cada cambio de comportamiento.
- Sin commits hasta que el usuario lo pida explícitamente.

## Enfoques considerados

1. **Categoría "Iconos" en el `SecondMenu`, sólo en niri (elegido).** El rail
   del submenú ya es el sitio de las secciones de ajustes; una categoría que
   aparece y desaparece según el compositor encaja con lo pedido y no
   ensucia el menú de apps, donde las categorías filtran aplicaciones.
2. **Sección dentro de "Configs de Caparazón".** Más escondida y no es una
   categoría aparte. Descartado.
3. **Categoría en el `AppMenu`.** El rail de ahí filtra apps por categoría
   freedesktop; un selector de iconos no filtra nada. Descartado.
4. **Resolver los iconos por ruta dentro de `IconResolver`** (buscar el PNG/SVG
   del tema a mano, sin depender de Qt). Evita el reinicio, pero hay que
   replicar el desempate de Qt entre variantes, tamaños y escalado: frágil y
   mucho más código. Descartado.
5. **Que el instalador escriba el tema y el panel sólo lo muestre.** El
   instalador no es el sitio donde se cambia una preferencia en caliente.
   Descartado.

## Diseño de las partes

### CLI — `integration/bin/caparazon-wm.py`

- `caparazon-wm icon-theme` → JSON por stdout:
  `{"current": "Papirus-Dark", "themes": ["Adwaita", "Papirus", …], "default": "Papirus-Dark", "configured": true}`.
  - `current`: lo que dice `~/.icons/default`; si no hay fichero, el default.
  - `configured`: si el fichero existe (para distinguir "elegido" de "puesto
    por defecto").
  - `themes`: los directorios con `index.theme` de `/usr/share/icons`,
    `~/.local/share/icons` y `~/.icons`, ordenados.
- `caparazon-wm icon-theme --set <tema>` → valida que el tema esté en la lista
  y escribe `~/.icons/default` de forma atómica (`[Icon Theme]\nName=<tema>\n`).
  Código 0. Tema desconocido → código 1 con mensaje en stderr.
- Tema por defecto: `Papirus-Dark` (constante del CLI).
- No necesita sudo: escribe en `~/.icons`.

### QML — detecting el compositor

- `modules/icons/CompositorService.qml` (singleton, como `IconResolver`):
  ejecuta `caparazon-wm detect` una vez por proceso y expone
  `readonly property string compositor` y `readonly property bool niri`.
- El singleton evita una consulta por ventana: el rail y el panel comparten la
  misma respuesta.

### QML — la categoría

- `modules/secondmenu/SecondMenu.qml`:
  - `categories` pasa a ser una lista base (las cuatro de hoy) más la de
    iconos **sólo si `CompositorService.niri`**.
  - La categoría nueva: `{ key: "iconos", icon: "preferences-desktop-theme", label: "Iconos" }`.
  - El `Loader` monta `IconThemePanel` cuando `category === "iconos"`.
- `modules/secondmenu/IconThemePanel.qml` (nuevo):
  - Al cargar: `caparazon-wm icon-theme` → guarda `current`, `themes` y
    `default`.
  - Lista los temas con su miniatura (el icono del propio tema, resuelto con
    `IconResolver`) y marca el activo.
  - Al elegir uno: `caparazon-wm icon-theme --set <tema>`; si el comando
    falla, muestra el error y no cambia nada.
  - Avisa de que la shell se va a reiniciar.

### QML — aplicar el cambio

- `IconThemeWatcher.qml` gana una segunda fuente vigilada: `~/.icons/default`.
  Si el fichero aparece o cambia, el reinicio es el mismo que ya se usa para
  KDE (`restartCommand` con `systemd-run` o `relaunchCommand` sin él).
- El panel **no** reinicia: escribe el fichero y el watcher reinicia. Un solo
  camino de reinicio, sea el cambio desde la UI o desde fuera.
- En KDE el watcher sigue vigilando `kdeglobals` y el comportamiento no cambia.

### Instalador — `install.sh`

- Rama niri: si no existe `~/.icons/default`, se pone `Papirus-Dark` (llamando
  al CLI, para que la escritura tenga un solo sitio). Si ya existe, no se
  toca: es una elección del usuario.
- Rama niri: aviso si falta el paquete `papirus-icon-theme`, con el comando
  apt exacto, como ya se hace con `power-profiles-daemon`.

### JS — `modules/icons/IconTheme.js`

- Función nueva `defaultIconTheme(text)`: lee el `Name=` de la sección
  `[Icon Theme]` de `~/.icons/default`; `""` si no está. Va con el resto de la
  lógica en JS plano, que ya se prueba con node sin levantar la shell.

### Tests

- `tests/test_caparazon_wm.py`:
  - `icon-theme` devuelve la lista de temas y `current`.
  - Sin `~/.icons/default`: `current` = el default y `configured` = `false`.
  - `--set` escribe el fichero con `[Icon Theme]` y `Name=`.
  - `--set` con un tema inexistente → código 1 y no escribe nada.
- Test del JS: `defaultIconTheme()` con el formato real del fichero.
- `tests/test_shell_qml_cli.py`: el panel llama a `caparazon-wm icon-theme` y
  `SecondMenu.qml` filtra la categoría según el compositor.
- `tests/test_install_compositor_agnostic.py`: aviso de `papirus-icon-theme`.

### Documentación

- README: `papirus-icon-theme` en la tabla de requisitos de niri y en su
  comando `apt install`; sección corta con cómo cambiar el tema desde la
  categoría "Iconos".

## Riesgos y límites

- **El reinicio es real**: al cambiar el tema, la shell se reinicia y el menú
  se cierra. Es lo que hace falta, porque Qt sólo lee el tema al arrancar.
- **Sin guardian en niri**: el reinicio usa `relaunchCommand`, que relanza el
  proceso con su mismo argv; si la corre bajo systemd, `restartCommand` la
  relanza como unidad. Los dos caminos ya existen.
- **La lista de temas es del sistema**: si el usuario instala un tema después,
  aparece al reabrir el panel (se consulta al montar).
- En niri, `~/.icons/default` también afecta a las demás apps de la sesión
  que lean el tema al arrancar (GTK y Qt): es el comportamiento estándar y lo
  que se espera de un "tema de iconos del sistema".

## Qué queda para quien lo implemente

Nada: el diseño está cerrado (contrato del CLI, formato del fichero, rutas de
la categoría y del panel, casos de test y documentación). Si al implementar
aparece un dato que contradice este documento, se para y se pregunta.

## Enmienda 2026-11-22 — tema unificado, include del config y `?fallback=`

Complemento aprobado en la sesión de corrección de iconos (ver también el
plan `2026-11-21-iconos-niri.md`, sección "Ampliación 2026-11-22"):

- **Fuente única del tema**: `CAPARAZON_ICON_THEME` y `QS_ICON_THEME` viven
  sólo en `config.d/40-environment.kdl`, con valor **`Tela-dark`** (el que
  ya usan kdeglobals y GTK en esta máquina; Papirus-Dark queda como default
  del CLI cuando no hay configuración). Fuera el bloque duplicado de
  `config.kdl`.
- **El CLI sigue los `include` de niri**: `read_icon_theme_file` y
  `write_icon_theme` expanden `include "…"` en orden de carga (gana el
  último valor) y `--set` escribe en el archivo dueño, no en `config.kdl`.
- **`QS_ICON_THEME` en el autostart**: quickshell no hereda el
  `environment` de niri (arranca vía `~/.config/autostart/caparazon.desktop`,
  padre `systemd --user`); el `Exec` lleva
  `QS_ICON_THEME=Tela-dark CAPARAZON_ICON_THEME=Tela-dark`.
- **Sin `?fallback=`**: `IconNames.js` recorta la query; `MusicButton` y
  `DockApp` usan `IconResolver.source` en vez de
  `Quickshell.iconPath(name, fallback)`.
- `QT_QPA_PLATFORMTHEME` sigue en `"kde"` (plasma-integration instalado);
  `qt6ct` no está en la máquina y no se cambia sin instalarlo.
