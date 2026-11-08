# Caparazón

Shell de escritorio para **KDE Plasma 6** en Wayland, escrita en QML con
[Quickshell](https://github.com/quickshell-mirror/quickshell). Sustituye la
barra superior y el dock de Plasma por una interfaz Material 3: barra
flotante, dock centrado, menú central de aplicaciones y un menú de sesión con
animación de despedida.

- **Barra flotante**: nace del borde superior, con curvas cóncavas, sombra
  difusa y 88 % del ancho del monitor. Se adapta a pantallas estrechas.
- **Dock real**: apps ancladas y ventanas abiertas, agrupadas por aplicación,
  con contador de instancias, foco al instante y menú contextual con las
  acciones del `.desktop`. Un clic sobre el icono **enfoca** la ventana; el
  siguiente clic la **minimiza**, y si estaba minimizada la **restaura**.
- **Dock inteligente**: el dock está **oculto** y sube al acercar el puntero al
  borde inferior (y se puede usar encima de la ventana); se oculta otra vez al
  dejarlo. Desde **Configs de la shell** (kanji 猫) puede pasar a **anclado**:
  siempre visible y reservando su franja. El estado se guarda en
  `~/.config/caparazon/dock.json` (`"dockPinned": true`).
- **Menú central**: buscador de aplicaciones con categorías, emojis y
  historial de portapapeles, navegable con flechas y `Enter`.
- **Escritorios virtuales**: pager en números kanji, con halo en el escritorio
  activo y marca de los que tienen ventanas, por pantalla.
- **Ventana activa**: icono, nombre y título de la ventana enfocada.
- **Recursos en vivo**: anillos de CPU, RAM, GPU, swap y red, con tooltip al
  pasar el ratón.
- **Bandeja del sistema**: iconos de StatusNotifier con menú propio dibujado
  en QML y un nivel de submenú.
- **Sonido y energía**: volumen y micrófono con medidor, perfil de energía con
  la rueda, estado de red y Bluetooth.
- **Avisos efímeros**: notificaciones y cambios de canción aparecen junto al
  reloj y se van solos.
- **Menú de sesión**: bloquear, cerrar sesión, apagar y reiniciar, con una
  despedida en japonés que se escribe letra a letra antes de ejecutar.
- **Tema dinámico**: la paleta Material 3 sale del color de acento de KDE
  mediante [matugen](https://github.com/WillPower3309/matugen) y se recarga en
  caliente.

## Requisitos

- KDE Plasma 6 sobre **Wayland** (KWin).
- `quickshell` 0.3.x o superior.
- Herramientas de KDE: `qdbus6`, `busctl`, `dbus-monitor`.
- `wl-paste` (historial de portapapeles) y `gdbus` (puente con KWin).
- Para el tema dinámico: `matugen`, `inotify-tools` (`inotifywait`),
  `util-linux` (`flock`), `libkf6config-bin` (`kreadconfig6`), `git` y
  `python3`.
- Opcionales: `wtype` o `ydotool` (pegar emojis),
  `python3` con `PyGObject` (puente de escritorios).

En PikaOS:

```bash
sudo apt install quickshell qdbus6 dbus-tools \
  matugen inotify-tools util-linux libkf6config-bin git python3
```

## Instalar

```bash
git clone https://github.com/ezku100/caparazon-shell.git
cd caparazon-shell
./install.sh
```

El instalador copia la shell a `~/.config/quickshell/caparazon`, instala el
puente de escritorios (`~/.local/bin` y el script de KWin), registra el
arranque automático en `~/.config/autostart` y deja el atajo global listo:
la tecla **Meta** abre el menú central.

Si el arranque automático ya apunta a otra copia —por ejemplo, tu clon de
trabajo—, el instalador la reutiliza: no copia la shell ni cambia el
arranque. Así el sistema tiene una sola shell, y es la que editas.

Además instala el motor de tema [`ezku100/accent-theme`](https://github.com/ezku100/accent-theme)
(clon o `git pull` en `~/.local/share/accent-theme/source`), registra la
plantilla de la shell y comprueba que la paleta generada contiene todos los
tokens que la shell necesita. Si falta cualquier dependencia, el instalador
se detiene indicando el comando `apt` exacto para instalarla.

## Actualizar

La shell se actualiza sola. Cada hora (y veinte segundos después de arrancar)
pregunta a GitHub si hay commits nuevos; cuando los hay, aparece junto al
reloj —a su izquierda— un icono con un punto rojo, y el reloj se corre como
cuando entra una notificación. Al pulsarlo se abre el panel de Configs, donde
**Actualizar ahora** trae los cambios, ejecuta `install.sh` y reinicia la
shell.

Si no quieres esperar a la revisión automática, en Configs está **Buscar
actualizaciones**: pregunta al momento y deja el resultado en la propia fila
("Estás al día", "N commits nuevos", "sin conexión"…).

El botón sólo actúa si el clon no tiene cambios locales sin commit: con
cambios, el aviso queda en gris y hay que actualizar a mano. Cada intento
queda registrado en `~/.cache/caparazon/update.log`.

La ruta del clon, la rama y la copia activa de la shell viven en
`~/.config/caparazon/update.conf`, que escribe `install.sh`. El reinicio se
lanza en una unidad transitoria de systemd (`caparazon-update`) para que el
propio reinicio de la shell no interrumpa la actualización.

Para saber si hay algo pendiente sin abrir Configs:

```bash
~/.local/bin/caparazon-update-check.sh ~/Projects/caparazon-shell main
```

A mano sigue funcionando igual:

```bash
cd caparazon-shell
git pull --ff-only
./install.sh
```

Para quitar todo lo que instaló:

```bash
./install.sh desinstalar
```

La desinstalación quita el registro del motor y deja intacta la configuración
anterior.

## Arrancar y parar

```bash
quickshell -p ~/.config/quickshell/caparazon     # en primer plano
quickshell -p ~/.config/quickshell/caparazon -d  # desmontado

El menú secundario se abre también por línea de comandos, con la categoría
que quieras (`quickshell -p <ruta> ipc call menu2 open configs`); el atajo
`menu2 toggle` lo abre y lo cierra.
quickshell -p ~/Projects/caparazon-shell -d       # desde tu clon
quickshell -c caparazon                         # por nombre de configuracion
pkill -f 'quickshell -p'                        # pararlo
```

Usa en cada comando la misma ruta con la que arrancaste la shell; el control
por IPC se dirige a la instancia que está corriendo.

Control del menú central desde la terminal o un atajo de KDE:

```bash
quickshell -p ~/.config/quickshell/caparazon ipc call menu toggle
quickshell -p ~/.config/quickshell/caparazon ipc call menu open
quickshell -p ~/.config/quickshell/caparazon ipc call menu close
```

## Atajos dentro del menú central

| Tecla | Acción |
|---|---|
| `Meta` | Abrir o cerrar el menú central (atajo global) |
| `←` `→` `↑` `↓` | Mover la selección de la cuadrícula |
| `Enter` | Lanzar la app, pegar el emoji o copiar del portapapeles |
| `Esc` | Cerrar el menú o limpiar el buscador |

El atajo global se registra como un lanzador de servicio de KDE
(`~/.local/share/applications/net.local.quickshell-2.desktop`) con la
combinación anotada en `~/.config/kglobalshortcutsrc`, así que
`./install.sh` lo deja funcionando sin tocar los ajustes del sistema.

KWin lee ese lanzador al arrancar: si instalaste la shell con la sesión
ya abierta, reinicia el compositor para que recoja el comando nuevo.

## Estructura

```text
caparazon-shell/
├── shell.qml              # punto de entrada: servicios globales y estado
├── modules/
│   ├── bar/               # barra superior, bandeja, pagers, medidores
│   ├── dock/              # dock, apps ancladas y widget de musica
│   └── appmenu/           # menu central, emojis y portapapeles
├── theme/                 # tokens Material 3 y paleta de matugen
├── components/            # piezas visuales compartidas
├── assets/                # tipografias
├── integration/           # puente de KWin, daemon, arranque y actualizador
└── install.sh
```

`shell.qml` crea **una sola instancia** de cada servicio (ventana activa,
escritorios, recursos, portapapeles y notificaciones) y reparte el estado a
las barras y docks de cada monitor, de modo que no se duplica ningún proceso
por pantalla.

## Integración con KDE

KWin no expone por D-Bus todo lo que una shell necesita, así que la shell
carga scripts propios en KWin:

- `KWinActiveTitle.js` publica la ventana activa y la lista de ventanas.
- `KWinWindowAction.js` enfoca, minimiza o restaura la ventana de una app.
- `integration/kwin/ezkudesktops` empuja el estado de los escritorios y sus
  ventanas ocupadas a `org.ezku.Desktops`, un pequeño demonio en Python.

Los datos viajan por el journal del compositor y se leen con `journalctl -f`,
lo que evita un proceso por monitor.

El tema de iconos es la excepción: el proceso lo lee una sola vez al arrancar,
así que al cambiarlo en KDE la shell seguiría con los iconos viejos.
Caparazón vigila `kdeglobals` y se reinicia sola en cuanto el tema cambia de
verdad; el reinicio tarda un segundo y vacía el historial del portapapeles.

## Música

La categoría **Música** del submenú muestra la carátula, el título, el artista
y los controles del reproductor MPRIS activo. La rueda del ratón cambia de
reproductor y un clic sobre el álbum pausa o reanuda.

El botón ⛶ activa el **modo compacto**: deja el álbum con el vinilo girando,
el título y el artista, y pone al pie un espectro que sigue al tema. Como la
tarjeta de controles se oculta, junto a ⛶ aparece un botón de siguiente pista.
La elección se recuerda en `~/.cache/caparazon/music-panel.json`, así que se
mantiene al cerrar el submenú o cambiar de categoría.

El espectro lo dibuja `modules/music/Spectrum.qml` a partir de
`~/.cache/caparazon/waves.json`, que publica `modules/music/spectrumfeed.py`
leyendo `cava`. El sampler sólo vive mientras el modo compacto está activo.

## Calendario

La categoría **Calendario** del submenú muestra, en solo lectura, los eventos de
uno o varios calendarios de Google. No hay OAuth ni cuenta de Google: cada
calendario se conecta con su **dirección secreta en formato iCal**.

### Conectar un calendario

1. Abre <https://calendar.google.com/calendar/settings> (o en Google Calendar,
   ⚙ → **Ajustes**) y elige el calendario en la columna izquierda. También
   puedes entrar desde el diálogo de la shell con **Abrir ajustes de Google**.
2. Entra en **Integrar calendario** y copia **Dirección secreta en formato
   iCal**: empieza por `https://calendar.google.com/calendar/ical/…` y termina
   en `basic.ics`. Trátala como una contraseña: quien la tenga puede leer ese
   calendario.
3. En la shell, abre el submenú (clic en el reloj) y entra en **Calendario**.
4. Pulsa el botón **G** de la esquina de la rejilla; se abre el diálogo.
5. Pega la dirección —**Pegar** la toma del portapapeles con `wl-paste`—,
   ponle nombre y elige color.
6. Pulsa **Guardar**. El calendario queda en la lista y sus días se marcan en
   la rejilla.

Repite con cada calendario que quieras ver; cada uno lleva su propio color.

### Gestionar los calendarios

En el mismo diálogo, por cada fila:

- el **punto de color** selecciona ese calendario para recolorearlo: la paleta
  marca el color actual con un anillo y el siguiente que pulses se guarda al
  instante;
- el **nombre** se edita en línea y se guarda al salir del campo;
- **activo / inactivo** lo oculta sin borrar la dirección;
- **Quitar** lo elimina del archivo de configuración.

**Abrir ajustes de Google** lleva a la página de ajustes desde el diálogo.

### Dónde se guarda

`~/.config/caparazon/calendar.json`, con permisos `600` (el directorio, `700`).
Sólo guarda id, nombre, color, estado y la dirección iCal. La credencial no sale
del sistema: `modules/secondmenu/gcal.py` es su único dueño; descarga el ICS,
lo cachea 15 minutos en `~/.cache/caparazon/calendar/<id>.ics` y publica un JSON
normalizado que consume `CalendarService.qml`.

Si la descarga falla se sirven los eventos ya cacheados (marcados como `stale`),
así que sin red el panel sigue mostrando lo último que vio.

### Uso del panel

La columna izquierda alterna **Notificaciones** y **Eventos** con dos botones; la
elección se recuerda en `~/.cache/caparazon/secondmenu.json`. Los chevrones del
encabezado cambian de mes (se conserva el día elegido) y el botón **G** abre el
diálogo.

En la vista de eventos, la rejilla marca con puntos de color los días con algo
(hasta tres; si hay más, un punto tenue) y, al elegir un día, la columna lista
sus eventos: color del calendario, hora —o «Todo el día»—, nombre del calendario
y título.

### Dependencia

`python3-dateutil` expande las recurrencias (reglas semanales, mensuales y
`EXDATE`):

```bash
sudo apt install python3-dateutil
```

`install.sh` la comprueba al instalar y avisa si falta.

### Límites conocidos

- Solo lectura: la shell no crea ni edita eventos.
- Las instancias modificadas de una serie (`RECURRENCE-ID`) no se interpretan:
  se muestran las ocurrencias de la regla.
- Los eventos de todo el día usan la fecha literal, con `DTEND` exclusivo, como
  manda el estándar.
- El panel se refresca cada 15 minutos y al cambiar algo en el diálogo.

### Probar el script a mano

```bash
python3 modules/secondmenu/gcal.py calendars
python3 modules/secondmenu/gcal.py events --from 2026-11-01 --to 2026-11-30
```

Las pruebas están en `tests/test_gcal.py` y `tests/test_calendar_google.py`.

## Tema

`theme/MatugenPalette.qml` lee `~/.cache/caparazon/colors.json` y lo recarga
cuando cambia (`watchChanges`). El archivo lo genera matugen a partir del
`AccentColor` de `kdeglobals`; si no existe, la shell usa una paleta Material 3
de reserva.

El motor [`ezku100/accent-theme`](https://github.com/ezku100/accent-theme) es
el único que regenera la paleta: lee el acento de KDE y regenera todas las
plantillas registradas cuando cambia. La shell no ejecuta su propio vigilante;
solo lee el resultado. El motor publica `colors.json` de forma atómica
(escribe `colors.staging.json` y lo renombra), así que la shell nunca ve un
archivo a medias y el `FileView` se entera al instante. La shell publica su
propia plantilla y su descriptor:

```text
integration/theme/quickshell-matugen.json   # tokens Material 3 que usa la shell
integration/theme/accent-theme.toml         # entrada y salida de la plantilla
integration/theme/required-tokens.txt       # tokens que la shell necesita
```

El motor copia la plantilla a `~/.config/accent-theme/templates/caparazon-shell/`
y escribe el resultado en `~/.cache/caparazon/colors.json`. El instalador
comprueba ese archivo al terminar: si falta algún token, falla con el nombre
del token que falta en lugar de dejar la shell con la paleta de reserva sin
avisar.

Para ver el estado del motor:

```bash
~/.local/bin/accent-theme doctor
```

### Estilos de color

La shell trae tres estilos y se cambian en vivo desde **Configs de la shell**
(kanji 猫) en el menú secundario: **Material** (roles oscuros tal cual),
**OLED** (negro puro con los mismos tokens) y **Perla** (roles claros para
fondos claros). El estilo activo se guarda en `~/.config/caparazon/style.json`
y `theme/ThemeStyle.qml` decide qué paleta lee `MatugenPalette.qml`:

```text
~/.cache/caparazon/colors.json         # Material
~/.cache/caparazon/colors-oled.json    # OLED
~/.cache/caparazon/colors-perla.json   # Perla
```

Cada paleta se genera con el acento de KDE, así que un cambio de acento repinta
los tres estilos. OLED parte de los mismos roles que Material y aplica un boost
de saturación (`saturation = 1.45` en su descriptor) para que los acentos se
distingan sobre negro puro; Perla usa los roles claros (`.light`) para los
acentos y los oscuros para el texto.

```text
integration/theme/quickshell-oled.json      # tokens del estilo OLED
integration/theme/quickshell-perla.json     # tokens del estilo Perla
integration/theme/accent-theme-oled.toml    # descriptor con saturation
integration/theme/accent-theme-perla.toml   # descriptor del estilo Perla
```

Si una paleta no está generada (por ejemplo, tras actualizar desde una versión
anterior), el panel marca su fila como no disponible y vuelve a Material para no
quedarse sin colores. Para generarlas, vuelve a ejecutar `./install.sh`.

### Tintado de los iconos

El tinte de los iconos (bandeja, dock, menú, submenú, recursos y nombre de la
ventana) depende de la superficie de la paleta, no del nombre del estilo. Sobre
superficie oscura se mantiene la tinta clara de siempre; sobre superficie clara
—como Perla— el tono profundo del acento y la tinta neutra dejaban los iconos
pesados y negros sobre el papel. Ahí los iconos llevan el acento lavado con la
propia superficie (`#006b58` + 30 % de papel = `#479182`).

Es un solo tinte para todos los iconos: no hay escala de intensidades del
acento, y el hover se marca con la tinta fuerte. El factor de lavado está en
`Theme.iconTintWash`.

Los tres tonos viven en `theme/Theme.qml`: `Theme.iconTint`,
`Theme.iconTintMuted` y `Theme.iconTintHover`.

## Desarrollo

Quickshell recarga solo al guardar, asi que basta con editar y guardar:

```bash
quickshell -p ~/Projects/caparazon-shell
journalctl --user -f _COMM=quickshell
```

Este repositorio es la fuente de verdad: se edita aqui, se commitea y se
sube. Para trabajar sobre el clon, deja el arranque automatico apuntando a
esa misma ruta —en `~/.config/autostart/caparazon.desktop`, la linea `Exec=`
debe usar `quickshell -p ~/Projects/caparazon-shell -d`— y arranca la shell
desde ahi. El instalador respeta lo que haya en el arranque: si ya apunta a
tu clon, no copia la shell ni crea una segunda.

## Creditos

- Ideas adaptadas de [caelestia-dots/shell](https://github.com/caelestia-dots/shell)
  y [ladybug-me/caelestia-kde](https://github.com/ladybug-me/caelestia-kde).
- Dock y gestion de ventanas inspirados en
  [ekremx25/quickshell](https://github.com/ekremx25/quickshell) (MIT).
- Lecciones de KWin y Quickshell recogidas en `ToraShell.md` del repo de
  dotfiles.

## Licencia

GPL-3.0. Ver [LICENSE](LICENSE).
