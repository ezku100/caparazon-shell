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
- Opcionales: `matugen` (tema dinámico), `wtype` o `ydotool` (pegar emojis),
  `python3` con `PyGObject` (puente de escritorios).

En PikaOS:

```bash
sudo apt install quickshell qdbus6 dbus-tools
```

## Instalar

```bash
git clone https://github.com/ezku100/caparazon-shell.git
cd caparazon-shell
./install.sh
```

El instalador copia la shell a `~/.config/quickshell/caparazon`, instala el
puente de escritorios (`~/.local/bin` y el script de KWin) y registra el
arranque automático en `~/.config/autostart`.

Para quitar todo lo que instaló:

```bash
./install.sh desinstalar
```

## Arrancar y parar

```bash
quickshell -p ~/.config/quickshell/caparazon     # en primer plano
quickshell -p ~/.config/quickshell/caparazon -d  # desmontado
quickshell -c caparazon                         # por nombre de configuracion
pkill -f 'quickshell -p'                        # pararlo
```

Control del menú central desde la terminal o un atajo de KDE:

```bash
quickshell -p ~/.config/quickshell/caparazon ipc call menu toggle
quickshell -p ~/.config/quickshell/caparazon ipc call menu open
quickshell -p ~/.config/quickshell/caparazon ipc call menu close
```

## Atajos dentro del menú central

| Tecla | Acción |
|---|---|
| `←` `→` `↑` `↓` | Mover la selección de la cuadrícula |
| `Enter` | Lanzar la app, pegar el emoji o copiar del portapapeles |
| `Esc` | Cerrar el menú o limpiar el buscador |

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
├── scripts/               # utilidades de mantenimiento
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

## Tema

`theme/MatugenPalette.qml` lee `~/.cache/caparazon/colors.json` y lo recarga
cuando cambia. El archivo lo genera matugen a partir del `AccentColor` de
`kdeglobals`; si no existe, la shell usa una paleta Material 3 de reserva.

## Desarrollo

Quickshell recarga solo al guardar, asi que basta con editar y guardar:

```bash
quickshell -p ~/Projects/caparazon-shell
journalctl --user -f _COMM=quickshell
```

La fuente de verdad de este repositorio esta en el repo de dotfiles
(`quickshell/caparazon`). `scripts/sync-from-dotfiles.sh` copia los cambios
de aqui hacia alla o viceversa segun se ejecute.

## Creditos

- Ideas adaptadas de [caelestia-dots/shell](https://github.com/caelestia-dots/shell)
  y [ladybug-me/caelestia-kde](https://github.com/ladybug-me/caelestia-kde).
- Dock y gestion de ventanas inspirados en
  [ekremx25/quickshell](https://github.com/ekremx25/quickshell) (MIT).
- Lecciones de KWin y Quickshell recogidas en `ToraShell.md` del repo de
  dotfiles.

## Licencia

GPL-3.0. Ver [LICENSE](LICENSE).
