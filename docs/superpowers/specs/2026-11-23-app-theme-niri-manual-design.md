# Diseño: tema manual de apps (GTK/Qt) en Niri

Fecha: 2026-11-23  
Estado: propuesto, pendiente de aprobación  
Tamaño: proyecto (CLI, plantillas, panel QML, tests, instalador y docs)

## Intención y por qué

En la sesión Niri no hay Plasma que repinte GTK, Qt ni las apps que hoy dependen
del motor `accent-theme`. El usuario quiere una opción manual dentro de
**Niri configs** para elegir uno de los 17 tokens ya definidos en la shell
(Material / OLED / Perla) y usar ese color como semilla para regenerar:

- los temas de GTK 3 y GTK 4;
- los esquemas de qt5ct y qt6ct;
- el tema de Kvantum (`.kvconfig` y `.svg`);
- las 8 plantillas de apps que ya registra `accent-theme`
  (cava, ghostty, heroic, kate, kitty, konsole, steam, zen);
- las integraciones directas de Brave, Equibop, Materialgram, OBS y Millennium;
- las recargas en vivo de Kitty, Ghostty, Zen, Cava y Millennium.

La semilla **siempre** sale de la paleta activa de la shell, sin reescribirla.
El futuro vigilante de wallpaper en Niri llamará a la misma acción de la CLI,
así que esto queda preparado para ese salto sin KDE.

## Goals

- Un panel nuevo en `Niri configs` con los 17 tokens del estilo activo.
- Un subcomando nuevo de `caparazon-wm` que expone estado y aplica el token.
- Generación determinista y atómica de los archivos de tema de GTK/Qt/apps.
- Cero escrituras en la paleta de la shell ni en la configuración de KDE.
- Misma acción reutilizable por un futuro watcher de wallpaper.

## Non-goals

- No cambiar `~/.config/caparazon/style.json`.
- No reescribir `~/.cache/caparazon/colors.json`, `colors-oled.json` ni
  `colors-perla.json`.
- No registrar plantillas nuevas en `accent-theme`.
- No escribir `~/.config/accent-theme/matugen.toml`.
- No leer ni escribir `~/.config/kdeglobals`.
- No iniciar ni reiniciar servicios de systemd.
- No instalar paquetes ni ejecutar comandos git.
- No hacer comprobaciones visuales ni reiniciar la shell sin permiso.

## Anti-goals

- Romper el tema de la shell en KDE.
- Inventar estilos de color nuevos: los únicos colores seleccionables son los
  17 tokens predefinidos del estilo activo.
- Sustituir el motor `accent-theme` por una implementación paralela.
- Escribir archivos de configuración directamente desde QML.

## Constraints (verbatim de la sesión)

- `"CLI como única puerta al sistema"`.
- `"TDD estricto"`.
- `"sin commits sin petición explícita"`.
- `"No ejecutar comandos de git de lectura/escritura (git status, git diff, git log...)"`.
- `"No instalar nada de nada (ni siquiera paquetes pequeños como curl o jq). Si hace falta algo así, pedir permiso primero."`.
- `"No delegar a subagentes/categorías con modelos premium... Solo se vale delegar si el usuario lo pide explícito en ese mensaje."`.
- `"recuerda que no debemos afectar el funcionamiento de la shell con kde"`.
- `"DALE VAMOS CON EL QUE RECOMIENDAS SOLO RECUERDA ESTO NO DEBE DAÑAR NI INTERRUMPIR LO QUE YA SE TIENE EN KDE CON LA SHELL"`.
- `"bro estoy usando mi computadora si quieres comprobaciones visuales pidemelas porque interrumpes el trabajo al quitarme el mause y eso"`.

## Approaches considerados

1. **Acción directa desde la CLI (elegido).**  
   El panel llama a `caparazon-wm app-theme --set <token>`. La CLI lee el estilo
   activo, toma el hex del token, genera un config de matugen propio sin las
   plantillas de la shell, publica los outputs y llama a las integraciones.
   Un futuro watcher llama exactamente al mismo comando. Es simple, auditable y
   no añade un servicio nuevo.

2. **Cola por archivo.**  
   El panel escribe `~/.config/caparazon/app-theme-request.json` y un servicio
   vigila ese archivo. Más desacoplado, pero añade un daemon, latencia y un
   punto de fallo más. Descartado.

3. **Sustitución directa de colores en los archivos generados.**  
   Tomar el hex elegido y hacer `sed` sobre los archivos de GTK/Qt/apps sin
   matugen. Descartado: rompe la coherencia de roles (primary/on-primary,
   surface/on-surface, etc.) y contradice el uso de matugen ya existente.

## Decisiones ya tomadas

- Subcomando: `caparazon-wm app-theme`.
  - Sin argumentos: imprime JSON de estado.
  - `--set <token>`: aplica el token del estilo activo.
  - `--help`/uso incorrecto: error con mensaje accionable.
- Estado de selección: `~/.config/caparazon/app-theme.json` con
  `{"token":"tertiary"}`. El estilo se lee de `style.json` en cada llamada;
  el token se guarda por nombre, no por hex, para que siga siendo válido al
  cambiar de estilo.
- El panel muestra los 17 tokens con su hex calculado desde la paleta activa.
- El estilo activo se obtiene leyendo `~/.config/caparazon/style.json`
  (solo lectura). Si no existe o es inválido, se usa `material`.
- La generación usa `matugen` con `-t scheme-fidelity -m dark -j hex` y la
  semilla del token elegido, igual que el motor existente.
- Config de matugen propio en `~/.cache/caparazon/app-theme/matugen.toml`.
  Nunca se escribe `~/.config/accent-theme/matugen.toml`.
- Plantillas y descriptores propios en
  `~/.config/caparazon/app-theme/templates/` y `.../templates.d/`, copiados
  desde el repo por el instalador. No se registran en `accent-theme`.
- Los outputs se publican con `staging -> replace` atómico, como hace el motor.
- Se reutilizan los módulos Python de `accent-theme` ya instalados para matugen,
  integraciones de apps y recargas en vivo, pero **sin** llamar a
  `accent-theme generate` ni a `read_kde_accent`.
- Si el motor `accent-theme` no está disponible, la CLI falla con un mensaje
  claro y no escribe nada. El panel refleja `engineAvailable: false`.

## Arquitectura de la generación

### Mapeo de tokens

La UI usa los nombres camelCase de `integration/theme/required-tokens.txt`.
La CLI los traduce a los roles de matugen:

| Token shell | Role matugen |
|---|---|
| `surface` | `surface` |
| `surfaceContainerLowest` | `surface_container_lowest` |
| `surfaceContainerLow` | `surface_container_low` |
| `surfaceContainer` | `surface_container` |
| `surfaceContainerHigh` | `surface_container_high` |
| `surfaceContainerHighest` | `surface_container_highest` |
| `fgSurface` | `on_surface` |
| `fgSurfaceVariant` | `on_surface_variant` |
| `outline` | `outline` |
| `outlineVariant` | `outline_variant` |
| `primary` | `primary` |
| `fgPrimary` | `on_primary` |
| `secondary` | `secondary` |
| `tertiary` | `tertiary` |
| `error` | `error` |
| `errorContainer` | `error_container` |
| `fgErrorContainer` | `on_error_container` |

### Plantillas

Las plantillas nuevas se derivan de los archivos que KDE genera hoy; no son un
rediseño visual. Se conservan nombres de variables, orden y estructura, y sólo
se sustituyen los literales de color por placeholders `{{colors.*.dark.hex}}`
según el role correspondiente.

Salidas previstas:

| Destino | Origen de la plantilla |
|---|---|
| `~/.config/gtk-3.0/colors.css` | archivo actual de GTK 3 |
| `~/.config/gtk-4.0/colors.css` | archivo actual de GTK 4 |
| `~/.config/qt5ct/colors/matugen.conf` | archivo actual de qt5ct |
| `~/.config/qt6ct/colors/matugen.conf` | archivo actual de qt6ct |
| `~/.config/Kvantum/matugen/matugen.kvconfig` | archivo actual de Kvantum |
| `~/.config/Kvantum/matugen/matugen.svg` | archivo actual de Kvantum |
| 8 plantillas de apps | descriptores existentes de `accent-theme` |

Las plantillas de apps no se copian: la CLI lee sus descriptores desde
`~/.config/accent-theme/templates.d/`, filtra los tres `caparazon-shell*`, y
reutiliza `input_path` tal cual. Eso evita duplicar contenido y sigue usando
los archivos que el motor ya mantiene.

### Flujo de `--set <token>`

1. Comprobar `detect_compositor() == "niri"`. En KWin, error y salida sin escribir.
2. Leer estilo activo y paleta correspondiente.
3. Validar token contra los 17 permitidos y su hex (`#[0-9a-f]{6}`).
4. Localizar el source de `accent-theme` y el binario de matugen.
5. Cargar descriptores de apps existentes, excluyendo `caparazon-shell*`.
6. Añadir los descriptores propios de GTK/Qt con outputs en las rutas reales.
7. Renderizar el config propio con `render_matugen_config()` del motor.
8. Ejecutar matugen con la semilla elegida y parsear tokens.
9. Publicar cada `*.staging*` a su ruta final con `os.replace`.
10. Llamar a `apply_app_integrations()` con `Accent(r,g,b)` derivado del hex y
    `tokens.app_environment()`.
11. Llamar a `apply_live_integrations()` con el mismo hex.
12. Escribir `~/.config/caparazon/app-theme.json` de forma atómica.
13. Imprimir JSON: `{style, token, hex, outputs, apps, live}`.

Si cualquier paso falla, no se escribe el archivo de selección y se dejan los
archivos anteriores intactos en la medida de lo posible. Los staging se limpian.

## Cambios por archivo

- `integration/bin/caparazon-wm.py`: nuevos `AppThemeState`, `app_theme_state()`,
  `app_theme_apply()`, mapeo de tokens, carga de descriptores, publicación y
  registro del subcomando en `main()`.
- `integration/theme/app-theme/*.tmpl` y `*.toml`: plantillas y descriptores.
- `modules/secondmenu/NiriConfigsPanel.qml`: tercera pestaña `Tema`.
- `modules/secondmenu/AppThemePanel.qml`: grid de 17 swatches, igual patrón que
  `IconThemePanel.qml` (sólo `Process` a la CLI).
- `install.sh`: copiar plantillas/descriptores a `~/.config/caparazon/app-theme`
  también en niri; no registrarlas en `accent-theme` ni llamar a `generate`.
- `README.md`: sección nueva explicando el flujo manual y el futuro watcher.
- Tests nuevos en `tests/test_app_theme.py`.

## Tests (TDD, rojo -> verde)

- Estado devuelve 17 tokens con hex del estilo activo; respeta `style.json`.
- `--set` rechaza token desconocido y hex inválido sin escribir nada.
- `--set` se niega en KWin y no toca ningún archivo.
- Config generado no contiene `caparazon-shell*`.
- Matugen se llama con la semilla del token elegido y el config propio.
- Sólo se publican las rutas permitidas; los staging se renombran y limpian.
- `style.json`, `colors*.json`, `kdeglobals` y `accent-theme` permanecen intactos.
- Integraciones de apps y live se llaman con el accent explícito, no con KDE.
- Contrato QML: `NiriConfigsPanel` incluye la pestaña y el panel llama a
  `caparazon-wm app-theme`.

## Lo que queda al builder

Los detalles de implementación (nombres internos de funciones, estructura exacta
de dataclasses, longitud de cada plantilla y mapping completo role -> variable)
se dejan al builder, con una regla: si algo del mapping no está claro, copiar la
semántica del archivo generado actual en lugar de inventar un color nuevo.

## Revisiones de diseño (builder check casero)

Por la regla de no subagentes, la revisión la hice yo mismo sobre este doc.
Puntos que podrían haberse preguntado y quedan resueltos aquí:

- **¿El panel cambia también la shell?** No. La shell ya contiene el token;
  seleccionarlo sólo alimenta GTK/Qt/apps. Es lo que el usuario pidió al decir
  que no se tocara la parte predefinida de la shell.
- **¿Se guarda el hex o el nombre del token?** El nombre. El hex se recalcula
  desde la paleta activa en cada aplicación.
- **¿Hace falta un daemon?** No. La acción directa es suficiente y es la que el
  usuario aprobó; el watcher futuro reutilizará el mismo comando.
- **¿Se duplica el motor accent-theme?** No. Se importan sus módulos con
  parámetros explícitos; nunca se ejecuta su CLI ni su watcher.
