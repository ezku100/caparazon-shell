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
  acciones del `.desktop`.
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
- **JetBrainsMono Nerd Font**: el menú de apagado dibuja sus iconos con glifos
  de esta fuente. No está en los repos de Debian (la versión empaquetada no
  trae los glifos parcheados): descarga el release de
  [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts/releases), copia los
  `.ttf` a `~/.local/share/fonts` y ejecuta `fc-cache -f`. Sin ella se ven
  cuadros, pero el resto de la shell funciona igual.
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

Para quitar todo lo que instaló:

```bash
./install.sh desinstalar
```

La desinstalación devuelve el tema al servicio heredado
`kitty-theme-watch.service` y deja intacta la configuración anterior.

## Arrancar y parar

```bash
quickshell -p ~/.config/quickshell/caparazon     # en primer plano
quickshell -p ~/.config/quickshell/caparazon -d  # desmontado
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
├── integration/           # puente de KWin, daemon y arranque automatico
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
- `KWinFocusApp.js` enfoca una ventana concreta.
- `integration/kwin/ezkudesktops` empuja el estado de los escritorios y sus
  ventanas ocupadas a `org.ezku.Desktops`, un pequeño demonio en Python.

Los datos viajan por el journal del compositor y se leen con `journalctl -f`,
lo que evita un proceso por monitor.

El tema de iconos es la excepción: el proceso lo lee una sola vez al arrancar,
así que al cambiarlo en KDE la shell seguiría con los iconos viejos.
Caparazón vigila `kdeglobals` y se reinicia sola en cuanto el tema cambia de
verdad; el reinicio tarda un segundo y vacía el historial del portapapeles.

## Tema

`theme/MatugenPalette.qml` lee `~/.cache/caparazon/colors.json` y lo recarga
cuando cambia. El archivo lo genera matugen a partir del `AccentColor` de
`kdeglobals`; si no existe, la shell usa una paleta Material 3 de reserva.

La paleta llega por el motor [`ezku100/accent-theme`](https://github.com/ezku100/accent-theme),
que lee el acento de KDE y regenera todas las plantillas registradas cuando
cambia. La shell publica su propia plantilla y su descriptor:

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
