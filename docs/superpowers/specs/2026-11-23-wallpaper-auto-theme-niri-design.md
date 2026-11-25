# Diseño: tema automático multi-repo desde el wallpaper en Niri

Fecha: 2026-11-23  
Estado: corregido, pendiente de aprobación  
Tamaño: proyecto mediano (motor compartido, fuentes, plantillas, watcher, tests, docs)

## Corrección al enfoque anterior

El diseño anterior tenía dos errores de fondo:

1. `accent-theme` y `caparazon-shell` son **dos repositorios del usuario**. No
   deben tratarse como “un motor externo que se reutiliza”. El cambio correcto
   es extender `accent-theme` como motor y dejar que `caparazon-shell` sea
   consumidor de las paletas.

2. No es cierto que Qt no pueda tematizarse fuera de KDE. Qt 6.10.2 está
   instalado, y los shells reales usan mecanismos estándar: `QT_QPA_PLATFORMTHEME`,
   `QT_STYLE_OVERRIDE`, `qt6ct`, Kvantum, KColorScheme o motores como
   `hyprqt6engine`. Lo que sí hay que matizar: `QStyleHints::colorScheme` y
   `setColorScheme` son API de aplicación; no bastan por sí solos para forzar
   el tema de terceros desde fuera. La vía externa real es platform theme +
   paleta/KColorScheme + estilo.

La implementación manual de `app-theme` sigue descartada como destino final.
Era un selector de tokens y no resolvía la fuente del color.

## Intención y por qué

El usuario quiere que en Niri el tema se comporte como en KDE: el color sale
del wallpaper, Matugen genera toda la paleta, y al cambiar de wallpaper cambian
la shell, GTK, Qt y las apps sin intervención manual.

La fuente elegida sigue siendo el preview de Waywallen + `matugen image`.
KDE debe seguir funcionando como hasta ahora; Niri debe tener su propia fuente
sin depender de que Plasma actualice `kdeglobals`.

## Hallazgos locales

- Qt instalado: `6.10.2`.
- Niri ya exporta `XDG_CURRENT_DESKTOP "niri"`, `XDG_MENU_PREFIX "plasma-"` y
  `QT_QPA_PLATFORMTHEME "kde"` en
  `~/.config/niri/config.d/40-environment.kdl`.
- Sólo existe el plugin `KDEPlasmaPlatformTheme6.so`; no están instalados
  `qt6ct`, `qt5ct` ni Kvantum, aunque sus archivos de config quedaron de
  intentos anteriores.
- `qt6ct` (`0.11-2+b1`) está disponible en el repo PikaOS y está compilado
  contra Qt `6.10.2`. `qt6-style-kvantum` es un paquete transitivo vacío; el
  paquete real es `qt-style-kvantum` (`1.1.8-1`) más
  `qt-style-kvantum-themes`. **No se instalará nada sin permiso explícito**.
- `hyprqt6engine` no está en apt. Es el motor Qt6 directo que menciona el
  usuario: usa `QT_QPA_PLATFORMTHEME=hyprqt6engine` y lee
  `~/.config/hypr/hyprqt6engine.conf`, con `theme.color_scheme` apuntando a un
  qt6ct theme o a un KColorScheme. Requiere compilarlo; también necesita permiso.
- `~/.config/kdeglobals` ya contiene un esquema oscuro completo y
  `AccentColor=213,32,56`; el problema no es que Qt no pueda leer color, sino
  que en Niri nadie actualiza ese acento desde el wallpaper.
- `accent-theme` ya sabe generar paletas y aplicar 14 integraciones, pero sólo
  toma el acento de `kdeglobals` y ejecuta `matugen color hex`.
- `caparazon-shell` lee paletas desde `~/.cache/caparazon/colors*.json` con
  `FileView watchChanges: true`; no necesita duplicar Matugen.

## Referencias externas

- Dux DMS, Application Theming: https://duxlabs.dev/docs/dms/application-themes
  - Un shell real genera con Matugen `~/.config/gtk-3.0/dank-colors.css`,
    `~/.config/gtk-4.0/dank-colors.css`,
    `~/.config/qt6ct/colors/matugen.conf` y, si se usa qtengine,
    `~/.config/qtengine/config.json`.
  - En Niri fija `environment { QT_QPA_PLATFORMTHEME "qt6ct" ... }`; el botón
    “Apply GTK colors” apunta GTK a los CSS y “Apply Qt colors” enlaza la paleta
    Matugen con qt5ct/qt6ct. Es la prueba de que un mismo evento de wallpaper
    alimenta GTK y Qt.
  - Advertencia propia: no poner `QT_QPA_PLATFORMTHEME` en `environment.d` en
    sesiones Plasma porque rompe KDE; usar configuración del compositor o
    unidad de servicio. Aquí se toca sólo el bloque `environment` de Niri.
  - Dolphin requiere `qt6ct-kde` o `qtengine`; con `qt6ct` estándar los colores
    se ven mal. Ninguno de los dos está en apt.
- Qt, `QStyleHints::colorScheme`: https://doc.qt.io/qt-6/qstylehints.html#colorScheme-prop
  - Introducido en Qt 6.5; sigue el esquema del sistema y reacciona a cambios.
  - `setColorScheme()` existe desde 6.8, pero los platform plugins pueden no
    atenderlo; no es una varilla mágica para apps de terceros.
- Qt, opciones de `QGuiApplication` y variables de entorno:
  https://doc.qt.io/qt-6/qguiapplication.html#supported-command-line-options
  - `-platformtheme` sobreescribe `QT_QPA_PLATFORMTHEME`.
  - El documento recomienda variables de entorno para procesos hijos.
- Niri, bloque `environment`:
  https://niri-wm.github.io/niri/Configuration%3A-Miscellaneous.html
  - Permite fijar variables para procesos lanzados por Niri; es exactamente
    donde debe vivir `QT_QPA_PLATFORMTHEME` en este diseño.
- Noctalia, plantillas GTK/Qt:
  https://docs.noctalia.dev/noctalia/templates/official/gtk-qt/
  - Para Niri: `environment { QT_QPA_PLATFORMTHEME "qt6ct" }`.
  - KDE apps como Dolphin requieren KColorScheme; el tema Qt normal puede
    dejarlos ilegibles.
  - Alternativas listadas: `qt6ct-kde`, `qtengine`, `hyprqt6engine`.
- Matugen Themes, sección GTK:
  https://github.com/InioX/matugen-themes#gtk
  - Genera `~/.config/gtk-3.0/colors.css` y `~/.config/gtk-4.0/colors.css`.
  - Requiere `@import 'colors.css';` en los `gtk.css` correspondientes.
- Matugen Themes, sección Kvantum:
  https://github.com/InioX/matugen-themes#kvantum
  - Genera `~/.config/Kvantum/matugen/matugen.kvconfig` y `matugen.svg`.
  - `~/.config/Kvantum/kvantum.kvconfig` selecciona `theme=matugen`.
- Matugen Themes, sección Qt:
  https://github.com/InioX/matugen-themes#qt
  - Genera `~/.config/qt6ct/colors/matugen.conf`.
  - Requiere `QT_QPA_PLATFORMTHEME=qt6ct` para que el platform theme aplique
    la paleta.
  - También documenta `~/.local/share/color-schemes/Matugen.colors` como
    KColorScheme.
- ArchWiki, apariencia uniforme Qt/GTK:
  https://wiki.archlinux.org/title/Uniform_look_for_Qt_and_GTK_applications
  - Kvantum es un estilo Qt6; se activa desde qt6ct o con
    `QT_STYLE_OVERRIDE=kvantum`.
- Manjaro Sway, perfil:
  https://github.com/manjaro-sway/manjaro-sway/blob/main/packages/manjaro-sway-settings/payload/etc/skel/.profile
  - Usa `QT_QPA_PLATFORMTHEME=xdgdesktopportal` y
    `QT_STYLE_OVERRIDE=kvantum`.
  - Comentario clave: `QT_STYLE_OVERRIDE` lo leen Qt5 y Qt6, independiente
    del platform theme.
- hyprqt6engine: https://github.com/hyprwm/hyprqt6engine
  - “QT6 Theme Provider for Hyprland. Compatible with KDE, replaces qt6ct.”
  - Confirma que existen motores que entregan tema Qt6 a apps en shells
    no-KDE. No está instalado aquí y no se compilará sin permiso.

## Goals

- Extender `accent-theme` con una fuente Niri/Waywallen sin romper la fuente
  KDE existente.
- Usar `matugen image` sobre el preview de Waywallen para obtener la paleta.
- Regenerar automáticamente cuando cambie el wallpaper.
- Publicar la paleta en los archivos que `caparazon-shell` ya consume.
- Generar también GTK 3/4, Qt6, KColorScheme, Kvantum y apps integradas.
- Mantener la CLI como única puerta al sistema.
- No romper ni interrumpir KDE ni la shell existente.
- No instalar paquetes, ejecutar git ni hacer comprobaciones visuales sin
  permiso.

## Non-goals

- No volver a introducir un selector manual de tokens.
- No usar `niri pick-color`: mueve el ratón e interrumpe al usuario.
- No capturar frames del escritorio ni abrir visores de imagen.
- No deshabilitar `accent-theme.service` ni el watcher de KDE sin aprobación.
- No ejecutar `install.sh` de ningún repo contra el HOME real sin permiso.
- No modificar la sesión Plasma ni sus esquemas activos como efecto colateral.
- No delegar a subagentes ni categorías premium.

## Anti-goals

- Que el tema quede congelado en el acento rojo viejo de `kdeglobals`.
- Que un evento de Waywallen dispare regeneraciones en bucle.
- Que un fallo de extracción reemplace la paleta buena por una inválida.
- Que el watcher de Niri y el de KDE escriban el mismo output al mismo tiempo.
- Que Dolphin u otras apps KDE queden con paleta ilegible por usar un tema Qt
  normal en vez de KColorScheme.

## Constraints (verbatim de la sesión)

- `"CLI como única puerta al sistema"`.
- `"TDD estricto"`.
- `"sin commits sin petición explícita"`.
- `"No ejecutar comandos de git de lectura/escritura (git status, git diff, git log...)"`.
- `"No instalar nada de nada (ni siquiera paquetes pequeños como curl o jq). Si hace falta algo así, pedir permiso primero."`.
- `"No delegar a subagentes/categorías con modelos premium... Solo se vale delegar si el usuario lo pide explícito en ese mensaje."`.
- `"no debemos afectar el funcionamiento de la shell con kde"`.
- `"DALE VAMOS CON EL QUE RECOMIENDAS SOLO RECUERDA ESTO NO DEBE DAÑAR NI INTERRUMPIR LO QUE YA SE TIENE EN KDE CON LA SHELL"`.
- `"bro estoy usando mi computadora si quieres comprobaciones visuales pidemelas porque interrumpes el trabajo al quitarme el mause y eso"`.
- `"No ejecutar install.sh contra HOME real"`.

## Arquitectura corregida

### Dueño del motor

`accent-theme` es el dueño de:

- detección de fuente;
- resolución del wallpaper;
- invocación de Matugen;
- render de plantillas;
- publicación atómica;
- integraciones en vivo;
- watcher y estado.

`caparazon-shell` es consumidor:

- mantiene `MatugenPalette.qml` y `FileView watchChanges: true`;
- elimina el panel manual `AppThemePanel.qml` y la pestaña `Tema`;
- expone estado mínimo desde su CLI leyendo el JSON de estado de
  `accent-theme`, sin duplicar lógica.

### Selección de fuente

La CLI de `accent-theme` gana `--source`:

- `kde`: comportamiento actual, lee `AccentColor` de `kdeglobals`;
- `waywallen`: lee `last_wallpaper`, resuelve `preview_path` en la DB y usa
  `matugen image ... --prefer saturation`;
- `auto`: usa `waywallen` cuando `XDG_CURRENT_DESKTOP=niri`, y `kde` en Plasma.

 Esto evita dos servicios peleando por los mismos archivos. El watcher se
 ampliará para vigilar la fuente correspondiente.

### Salidas de tema

`accent-theme` publicará, con `staging -> os.replace`:

- `~/.cache/caparazon/colors.json`
- `~/.cache/caparazon/colors-oled.json`
- `~/.cache/caparazon/colors-perla.json`
- `~/.config/gtk-3.0/colors.css`
- `~/.config/gtk-4.0/colors.css`
- `~/.config/qt6ct/colors/matugen.conf`
- `~/.local/share/color-schemes/Matugen.colors`
- `~/.config/Kvantum/matugen/matugen.kvconfig`
- `~/.config/Kvantum/matugen/matugen.svg`
- las salidas ya registradas de las 14 apps.

Los `gtk.css` actuales ya importan `colors.css`; no hace falta reescribirlos
salvo validación.

### Estrategia GTK/Qt recomendada (referencia Dux DMS)

Ruta recomendada, pendiente de permiso para instalar:

1. Instalar `qt6ct` desde PikaOS (`0.11-2+b1`, compilado contra Qt 6.10.2).
   Es la opción documentada por Dux para “dedicated Qt control”. Opcional, sólo
   si se quiere cambiar el estilo: `qt-style-kvantum` y
   `qt-style-kvantum-themes`. No instalar `qt6-style-kvantum`: es un dummy
   transitional.
2. En Niri, y sólo en `~/.config/niri/config.d/40-environment.kdl`, reemplazar
   `QT_QPA_PLATFORMTHEME "kde"` por:
   `QT_QPA_PLATFORMTHEME "qt6ct"` y `QT_QPA_PLATFORMTHEME_QT6 "qt6ct"`.
   No tocar `~/.config/environment.d/` ni servicios de usuario: Dux advierte
   que eso rompe Plasma.
3. `accent-theme`, en el mismo ciclo de `matugen image`, escribe:
   `~/.config/gtk-3.0/colors.css`, `~/.config/gtk-4.0/colors.css`,
   `~/.config/qt6ct/colors/matugen.conf` y
   `~/.local/share/color-schemes/Matugen.colors`. Los `gtk.css` actuales ya
   importan `colors.css`; no hace falta un botón manual “Apply”.
4. Activar `QT_STYLE_OVERRIDE=kvantum` en Niri sólo si se instala Kvantum y se
   confirma que da mejor resultado que Breeze/Oxygen, que ya están instalados.

Esto es lo que documenta Dux: un solo cambio de wallpaper regenera CSS de GTK y
paleta de qt6ct; Niri apunta Qt al platform theme qt6ct. KDE/Plasma queda
intacto porque la variable se fija en el bloque `environment` de Niri.

**Límite conocido:** Dux documenta que Dolphin necesita `qt6ct-kde` o
`qtengine` (no `qt6ct` estándar) para colorearse bien; ninguno está en apt. Si
el usuario quiere cubrir también apps KDE lanzadas desde Niri, hay tres opciones
(todas requieren permiso):

- compilar `qtengine` (un solo plugin para Qt5/Qt6, con `config.json`);
- compilar `hyprqt6engine` (compatible con KColorScheme);
- usar el fallback de `~/.config/dolphinrc` con `ColorScheme=Matugen`.

Sin permiso no se instala ni compila nada. Sin instalar, el diseño no asume que
qt6ct o Kvantum existen; no se propone seguir con `kde` porque eso obliga a
tocar `kdeglobals`, que es justo lo que debe evitarse.

## Flujo propuesto

1. `accent-theme watch --source auto` detecta Niri y elige `waywallen`.
2. Lee `last_wallpaper` de Waywallen y resuelve el preview en la DB en modo
   read-only.
3. Ejecuta `matugen image <preview> -c <config propio> --prefer saturation -j hex`.
4. Valida `source_color` y todos los roles requeridos.
5. Renderiza las plantillas de shell, GTK, Qt, KColorScheme, Kvantum y apps.
6. Publica los staging con `os.replace`; si algo falla, conserva la paleta
   anterior.
7. Escribe `~/.cache/accent-theme/niri-state.json` con wallpaper, color,
   timestamp y resultado.
8. `caparazon-wm theme status` lee ese JSON y lo muestra.
9. El watcher usa `flock`, debounce y caché del último ID; si el wallpaper no
   cambió, no regenera.

## Cambios por repo

### `accent-theme`

- `src/accent_theme/sources/`: fuentes `kde`, `waywallen` y resolver `auto`.
- `src/accent_theme/matugen.py`: modo `image` además de `color hex`.
- `src/accent_theme/cli.py`: `--source`, `--once`, `--watch`, estado JSON.
- `src/accent_theme/registry.py`: descriptores nuevos de GTK/Qt/KColorScheme.
- `templates/`: plantillas GTK, qt6ct, Kvantum y KColorScheme.
- `install.sh`: registrar plantillas y service; no ejecutar contra HOME real.
- `README.md`: documentar fuentes y comportamiento en Niri.
- Tests nuevos para fuentes, Matugen image, publicación y watcher.

### `caparazon-shell`

- `modules/secondmenu/AppThemePanel.qml`: eliminar.
- `modules/secondmenu/NiriConfigsPanel.qml`: quitar pestaña manual `Tema`.
- `integration/bin/caparazon-wm.py`: subcomando `theme status` como wrapper de
  lectura del estado.
- `tests/test_app_theme_panel.py`: migrar a ausencia de panel manual.
- `tests/test_niri_configs_panel.py`: ajustar a nueva pestaña.

## Tests (TDD, rojo → verde)

- `auto` elige `waywallen` con `XDG_CURRENT_DESKTOP=niri`.
- `auto` elige `kde` con `XDG_CURRENT_DESKTOP=plasma`.
- `last_wallpaper` se lee desde TOML, con fallback a entradas por display.
- La DB se abre read-only y `preview_path` se resuelve dentro de la librería.
- Matugen se invoca con `image`, `--prefer saturation` y config propio.
- Se parsean `source_color` y los roles requeridos.
- Sólo se publican las rutas permitidas; staging se renombra y se limpia.
- `kdeglobals` y el watcher KDE quedan intactos en modo `waywallen`.
- El watcher no regenera si el ID de wallpaper no cambió.
- El watcher regenera cuando cambia `last_wallpaper`.
- La caché de estado no se actualiza si falla la generación.
- GTK, qt6ct, KColorScheme y Kvantum reciben salidas válidas.
- QML ya no ofrece selección manual de tema.

## Lo que queda al builder

Nombres internos, dataclasses, longitud de funciones y mapeo exacto de roles a
variables quedan al builder. Regla: copiar la semántica de los archivos
generados actuales en lugar de inventar colores o rutas nuevas.

## Revisión de diseño

- **¿Se mira el frame animado?** No. Se usa el preview; cambiar a captura de
  frame sería otro enfoque y necesitaría permiso para comprobaciones visuales.
- **¿Se toca KDE?** No en modo `waywallen`: ni `kdeglobals`, ni esquemas, ni
  watchers de Plasma.
- **¿Dolphin queda fuera?** Queda cubierto por KColorScheme como salida, pero
  Dux advierte que `qt6ct` estándar no lo colorea bien; para apps KDE dentro de
  Niri haría falta `qtengine`, `qt6ct-kde` o el fallback de `dolphinrc`, todos
  pendientes de permiso.
- **¿Se instala algo?** No sin permiso explícito. La recomendación Dux requiere
  `qt6ct`; el estilo Kvantum es opcional (`qt-style-kvantum` +
  `qt-style-kvantum-themes`).
- **¿Se habilita systemd automáticamente?** No sin aprobación explícita.
