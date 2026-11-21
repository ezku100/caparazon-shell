# Puerto a niri (backends de compositor + dotfile) — diseño

Fecha: 2026-11-21

## Qué se quiere

Que caparazon-shell funcione igual de bien bajo **niri** (≥ 26.04) que bajo KWin,
sin bifurcar el QML por compositor, y un **dotfile `config.kdl`** de niri con
gaps, bordes, sombras, esquinas redondeadas, animaciones y blur para que la
sesión no se vea vacía.

## Por qué una capa única (`caparazon-wm`)

Hoy hay cinco puntos duros atados a KDE, repartidos por el QML:

| Sitio | Llamada actual |
|---|---|
| `shell.qml` (`activeOutputQuery`, `secondOutputQuery`) | `busctl … org.kde.KWin activeOutputName` |
| `modules/bar/WorkspacesService.qml` | `busctl … VirtualDesktopManager` + `dbus-monitor` |
| `modules/bar/ActiveWindowService.qml` | script KWin + `journalctl _COMM=kwin_wayland` |
| `theme/ShellLayout.qml` | `kscreen-doctor --json -o` |
| `modules/dock/Dock.qml` | `gdbus … org.kde.kwin.Scripting` + `KWinWindowAction.js` |
| `modules/bar/PowerMenu.qml` (logout) | `qdbus6 org.kde.Shutdown` |

En su lugar: un CLI único **`caparazon-wm`** (`integration/bin/caparazon-wm.py`)
con subcomandos estables. El QML sólo invoca ese CLI; el CLI despacha a backend
`kwin` o `niri` según detección. Mismo patrón que ya usan
`ezku-desktops-daemon.py` (D-Bus propio) y el bootstrap.

```
QML / bootstrap
      │
      ▼
caparazon-wm <subcmd>        ← detect → kwin | niri
      ├─ kwin  → busctl / gdbus / kscreen-doctor / qdbus6 / script KWin
      └─ niri  → niri msg -j / event-stream / loginctl
```

## Detección

Orden (barato, por invocación; los streams detectan una vez al arrancar):

1. `NIRI_SOCKET` definido → `niri`
2. `busctl --user call org.kde.KWin …` responde → `kwin`
3. `niri msg version` responde → `niri`
4. Fallback → `kwin` (comportamiento actual en Plasma)

## Contrato de subcomandos

| Subcomando | Salida |
|---|---|
| `detect` | `kwin` \| `niri` |
| `active-output` | nombre de pantalla, p. ej. `DP-1` |
| `primary-output` | principal (kscreen prioridad 1; en niri: primera activa) |
| `workspaces` | JSON: `{current, desktops:[{pos,id,name}], occupied, perOutput, focusedScreen, occupiedPerOutput}` (mismo shape que el caché de hoy) |
| `watch-workspaces` | una línea JSON por evento de cambio (reemplaza `dbus-monitor` / event-stream) |
| `windows` | JSON: `{appId, title, appIds:[]}` |
| `watch-windows` | una línea JSON por cambio de ventana enfocada/lista |
| `window-action <active> <candidatos…>` | enfoca / minimiza / restaura (ciclo del dock) |
| `logout` | cierra la sesión |

El JSON de `workspaces` es el que ya consume `WorkspacesService` vía
`queriedDesks` / `queriedCurrentId` y el caché `~/.cache/ezku-desktops.json`:
se reutiliza el shape, no se inventa otro.

## Acciones de ventana (dock)

- **kwin**: el camino actual se mueve *dentro* del CLI (bash + `KWinWindowAction.js`
  + `gdbus`); el test node existente sigue siendo el árbitro de la lógica.
- **niri**: `niri msg -j windows` + `niri msg action focus-window --id`. niri **no**
  expone `minimize-window` en su CLI; el mínimo viable es enfocar. Si durante la
  implementación `niri msg -j windows` trae estado minimizado accionable vía
  protocolo, se añade; si no, el segundo clic en niri mantiene el foco y queda
  documentado en el README (no se cierra la ventana por error).

## Efectos / blur

- Sombras, animaciones, colorización, scrim: **QML/Qt** — viajan sin cambios.
- Blur tras el `PowerMenu`: ya usa `BackgroundEffect.blurRegion`
  (`ext-background-effect-v1`); niri 26.04 lo soporta en layer surfaces.
- Blur global tras barra/dock: `layer-rule` en `config.kdl` (Parte B).

## Parte B — dotfile niri

`~/.config/niri/config.kdl` (fuente en el repo + `~/dotfiles/niri/`):

- `layout { gaps, border{width,radius,colores}, focus-ring, shadow }`
- `window-rule { geometry-corner-radius }` (esquinas redondeadas)
- `animations { window-open/close, workspace-switch }`
- `layer-rule { background-effect { blur } }` sobre las namespaces de Quickshell
  (verificar con `niri msg layers` en sesión niri)
- Validación: `niri validate -c <ruta>` (niri 26.04 ya está en PikaOS)

## Fuera de alcance

- Actividades, KRunner, atajos globales de Plasma, decoraciones KWin.
- Plugin Noctalia de escritorios bajo niri (el daemon sigue; el empuje KWin se
  omite en niri y la ocupación viene de `caparazon-wm workspaces`).
- Cambiar la sesión de inicio del usuario (sigue en Plasma hasta que él cambie).
