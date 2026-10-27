# Vigilante del tema de iconos y limpieza de `networkIcon`

Fecha: 2026-10-27
Estado: propuesto, pendiente de aprobación

## Intención y por qué

Al cambiar el tema de iconos en los Ajustes del Sistema, Caparazón seguía
mostrando los iconos del tema anterior: había que reiniciar la shell a mano.
Este trabajo añade un vigilante que detecta el cambio y reinicia la shell
sola, para que el escritorio quede coherente sin intervención del usuario.

El segundo punto es limpieza. La propiedad `networkIcon` viaja desde el script
de muestreo hasta el monitor de recursos, donde se declara y nunca se usa.
Se elimina la cadena entera, incluido el cálculo que hace el script.

## Objetivos

- Detectar el cambio del tema de iconos de KDE y reiniciar la shell sin que
  el usuario tenga que hacerlo.
- Reiniciar **sólo** cuando el valor del tema cambia de verdad: las demás
  escrituras de `kdeglobals` no deben mover la shell.
- Dejar el código sin propiedades muertas.
- No añadir dependencias nuevas: todo con lo que ya tiene el sistema.

## No objetivos

- No se adaptan en caliente los iconos dentro del proceso: se ha medido
  que el tema se lee una sola vez al arrancar (ver restricciones).
- No se vigilan otros ajustes de KDE (colores, temas de cursor, tipografías).
  Los colores dinámicos ya los cubre `MatugenPalette` con su `FileView`.
- No se cambia la manera de resolver iconos: sigue siendo por nombre de
  tema, sin rutas absolutas.

## Anti-objetivos

- Reiniciar la shell en bucle o al arrancar.
- Perder el estado de la sesión sin avisar: el reinicio es automático y
  aceptado, pero no debe dispararse por cambios ajenos al tema de iconos.
- Dejar el shell sin icono cuando el archivo de configuración no existe.

## Restricciones (medidas, no supuestas)

Medido con una sonda de Quickshell y un `HOME` falso, sin tocar la
configuración real:

- El tema de iconos se lee **una vez por proceso**. Cambiar `kdeglobals`
  con la shell en marcha no cambia lo que se dibuja: los 21 fotogramas
  capturados antes y después del cambio son idénticos. Control: arrancando
  con `Tela-dark` y con `breeze` desde el principio, los renders **sí** son
  distintos. Por tanto hace falta reiniciar el proceso;
  `Quickshell.reload(true)` recargaría el QML con el tema viejo y no serviría.
- `Quickshell.iconPath(nombre, true)` devuelve `image://icon/<nombre>`, no
  una ruta: la resolución ocurre al pintar, contra el tema activo del
  proceso. No hay ninguna ruta que "recargar".
- El tema sale de `~/.config/kdeglobals`, sección `[Icons]`, clave `Theme`.
  Lo lee KF6 al arrancar. `QT_ICON_THEME` no tiene efecto en esta pila:
  ponerlo a un valor inexistente no cambia nada.
- La shell corre bajo `app-caparazon@autostart.service`, una unidad
  **generada** por `systemd-xdg-autostart-generator` a partir del `.desktop`
  de autostart. El nombre se deduce del cgroup, no se escribe a mano.

## Enfoques considerados

**A. Vigilante dentro de la shell + reinicio del proceso. Elegido.**
Un servicio global de QML mira `kdeglobals`, extrae `[Icons] Theme` y, si
cambió, reinicia la shell. Una sola pieza, sin dependencias, sin archivos
instalados, y funciona igual en producción y en el arranque manual.

**B. Recarga en proceso con `Quickshell.reload(true)`. Descartado.**
La medición lo descarta: el nombre del tema ya está fijado en el proceso,
así que la recarga volvería a dibujar los mismos iconos.

**C. Script externo con `inotifywait` + unidad systemd aparte. Descartado.**
Funciona, pero añade un script, una unidad, su registro en el instalador y
su desinstalación; además tendría que adivinar el nombre de la unidad
*generada* de la shell. Más piezas para el mismo resultado.

## Decisiones

### D1. Detección

`FileView` de Quickshell con `watchChanges: true` sobre
`$XDG_CONFIG_HOME/kdeglobals`, más un `FileSystemWatcher` de QtQuick sobre el
directorio de configuración por si KConfig sustituye el archivo de forma
atómica. Es el mismo patrón que ya usa `MatugenPalette` con `colors.json`,
que el motor accent-theme escribe de forma atómica.

Ante cualquier aviso se rearranca un temporizador de 500 ms; al cumplirse se
vuelve a leer el archivo y se compara el valor. El valor se lee **en el
momento de decidir**, nunca del aviso: KConfig escribe `kdeglobals` en
varias pasadas y una lectura a medio escribir daría un valor vacío o
truncado.

### D2. Cuándo reiniciar

Sólo cuando `[Icons] Theme` pasa de un valor a otro valor no vacío. El
primer valor observado tras arrancar es la línea base y no dispara nada.

Toda la decisión vive en JavaScript (`IconTheme.themeDecision`), no en el
QML, para poder probarla con node como ya se hace con `IconNames.js`: la
función recibe el tema anterior, el nuevo y si ya se conoce una línea base,
y devuelve el tema que queda como referencia y si hay que reiniciar.

### D3. Cómo reiniciar

El reinicio se decide en dos casos, según dónde corra la shell:

- **Bajo systemd** (lo normal): se lee `/proc/self/cgroup` y se toma el
  último componente, que es el nombre de la unidad. El reinicio se lanza con
  `systemd-run --user --on-active=0.3 systemctl --user restart <unidad>`.
  `systemd-run` crea una unidad transitoria en `user.slice`, **fuera** del
  cgroup de la shell: así el reinicio no se mata a sí mismo a media faena.
  Si `systemd-run` no existe, se cae a `systemctl --user restart <unidad>`.
- **Sin systemd** (arranque manual en modo desarrollo): se lee el `argv` del
  proceso desde `/proc/$PPID/cmdline` y, cuando el PID actual muere, se
  vuelve a ejecutar ese mismo `argv`. Así la shell reaparece igual que se
  lanzó.

Un flag `restarting` impide encolar dos reinicios.

La construcción de los dos comandos también vive en JavaScript
(`IconTheme.restartCommand` e `IconTheme.relaunchCommand`), porque son
exactamente los datos que hay que acertar: qué unidad reiniciar, con qué
orden de argumentos y a qué PID esperar. La elección entre `systemd-run` y
`systemctl` la hace el propio script en tiempo de ejecución, con
`command -v systemd-run`, para que funcione también en sistemas donde no
existe.

### D4. Limpieza de `networkIcon`

La cadena muerta es completa y se quita entera:

- `modules/bar/resource-monitor.sh`: el cálculo de `net_icon` (wired frente
  a wireless) y el séptimo campo de la línea que imprime. El script pasa a
  emitir seis campos.
- `modules/bar/ResourceMonitorService.qml`: la propiedad `networkIcon`, su
  asignación y el mínimo de campos del parser (de siete a seis).
- `shell.qml`: `networkIcon: resourceService.networkIcon`.
- `modules/bar/Bar.qml`: la propiedad y su paso al monitor.
- `modules/bar/ResourceMonitor.qml`: la propiedad, que no se usaba; el
  componente sigue con `networkSource`, que va por `IconResolver`.

El estado de la interfaz de red no se pierde: `modules/bar/Network.qml` ya
calcula su propio icono con `IconResolver.firstOf`.

## Piezas

| Archivo | Acción | Qué hace |
| --- | --- | --- |
| `modules/icons/IconTheme.js` | nuevo | Lee `[Icons] Theme` de un texto INI, decide si el tema cambió y construye el comando de reinicio |
| `modules/icons/IconThemeWatcher.qml` | nuevo | Vigila `kdeglobals` y reinicia la shell cuando el tema cambia |
| `modules/icons/qmldir` | editar | Declarar el tipo nuevo |
| `shell.qml` | editar | Instanciar el vigilante una sola vez |
| `modules/bar/resource-monitor.sh` | editar | Quitar `net_icon` |
| `modules/bar/ResourceMonitorService.qml` | editar | Quitar la propiedad y el campo |
| `modules/bar/Bar.qml` | editar | Quitar la propiedad y su paso |
| `modules/bar/ResourceMonitor.qml` | editar | Quitar la propiedad muerta |
| `tests/support/icon_theme_harness.js` | nuevo | Escenarios del módulo, en node |
| `tests/test_icon_theme.py` | nuevo | Contrato del módulo del tema |
| `tests/test_icon_theme_watcher.py` | nuevo | Contrato del cableado del vigilante |
| `README.md` | editar | Documentar el reinicio automático |

## Pruebas

- Unitarias, con node: `IconTheme.iconTheme` devuelve el valor de
  `[Icons] Theme`; devuelve vacío si falta la sección, la clave o el
  archivo; ignora comentarios y secciones ajenas; `themeDecision` sólo pide
  reinicio con un valor nuevo y no vacío, y el primer valor observado sólo
  fija la línea base; los dos comandos se construyen con la unidad y el PID
  como argumentos, no pegados al script.
- Contrato: `shell.qml` instancia el vigilante una sola vez y el vigilante
  compara el tema antes de reiniciar.
- Calidad: `uv run pytest -q`, `uv run ruff check .`, `uv run basedpyright`.
- En vivo: cambiar el tema de iconos y comprobar que la unidad se reinicia
  (`ActiveEnterTimestamp` cambia) y que los iconos de la barra son los del
  tema nuevo. Se restaura el tema original al terminar.

## Riesgos

- El reinicio pierde el historial del portapapeles, que vive en memoria, y
  cierra los menús abiertos. Es el precio de que los iconos cambien, y se
  acepta: el reinicio manual hacía lo mismo.
- Si el reinicio falla, la shell sigue con el tema viejo y el aviso queda en
  el log; el siguiente cambio del tema reintenta.
- En el arranque manual, si no se puede leer el `argv`, la shell no
  reaparece sola y hay que arrancarla a mano. Se avisa en el log.

## Cómo se entrega

Rama `feature/vigilante-tema-iconos`, commits en español sin tildes, merge
`--no-ff` a `main` y push a `origin/main`, igual que las ramas anteriores.
