# Menú secundario: categoría Calendario

Fecha: 2026-10-28
Estado: propuesta (esperando aprobación)

## Objetivo

Un segundo menú, aparte del menú central de aplicaciones, con un rail de
categorías. La primera categoría es **Calendario** y muestra cinco cosas: la
hora en grande, el calendario mensual, la foto de perfil del usuario, el
tiempo de sesión activa y el clima.

El menú se abre haciendo clic en la hora o la fecha de la barra, y toma del
menú de apps el tamaño y el diseño como **referencia visual**: son dos menús
independientes, sin código compartido.

## Cómo se abre

- Clic en el reloj de la barra (`modules/bar/Clock.qml`): alterna abrir/cerrar.
- Mutuamente excluyente con el menú de apps: al abrir uno se cierra el otro.
- Se abre en la pantalla de la barra donde se hizo clic, igual que el menú de apps.
- `IpcHandler` nuevo con target `menu2` (`toggle`, `open`, `close`) para
  atajos de KDE; el clic en el reloj es la vía principal.

## Arquitectura

### 1. `modules/secondmenu/`: menú independiente

`modules/appmenu/AppMenu.qml` **no se toca**. El menú nuevo lleva su propio
chrome, con los mismos números que el de apps para que se vean iguales:

- `PanelWindow` a pantalla completa, scrim, región de blur y foco exclusivo.
- Tarjeta centrada con `MultiEffect` (sombra amplia, `shadowBlur 0.85`,
  `shadowVerticalOffset 16`), superficie de radio 24 con `Theme.surface` y
  borde `Theme.m3OutlineVariant`.
- Rail de radio 18 con `Theme.m3SurfaceContainerLow` y `contentArea` con sus
  márgenes (20 + `railInset` a la izquierda, 18 arriba y abajo).
- Medidas: `min(860, max(640, 60% del ancho))` × `min(620, max(460, 62% del
  alto))`, rail de 60 px.

El botón del rail es el mismo `RailButton` que ya existe en el repo (es un
componente de apoyo, no del menú de apps), así que el rail se ve igual.

Coste de la independencia: si algún día cambia el aspecto del menú de apps,
este menú hay que ajustarlo a mano.

### 2. `modules/secondmenu/` (nuevo)

| Archivo | Responsabilidad |
|---|---|
| `SecondMenu.qml` | Tarjeta del menú nuevo, rail de categorías y contenido por categoría |
| `CalendarPanel.qml` | La categoría Calendario: reloj grande, avatar, actividad, clima y calendario |
| `MonthGrid.qml` | Rejilla del mes (cálculo en JS, sin dependencias) |
| `ProfileService.qml` | Avatar y nombre del usuario |
| `SessionService.qml` | Tiempo de sesión activa |
| `WeatherService.qml` | Clima con caché y degradación sin red |
| `WeatherGlyph.qml` | Iconos de clima dibujados en QML (sol, nube, lluvia, nieve, tormenta, niebla) |

El rail nace con una sola categoría (`Calendario`, icono `x-office-calendar`)
y queda listo para las siguientes: la estructura ya es una lista.

### 3. Cableado

- `shell.qml`: `secondMenuState` (`QtObject` con `opened`, `closing`,
  `activeScreen`, `lastScreen`, `category`) e `IpcHandler` con target `menu2`.
- `modules/bar/Bar.qml`: `Loader` con `SecondMenu`, igual que el de
  `AppMenu`, y `openSecondMenu()` que cierra el menú de apps.
- `modules/bar/Clock.qml`: `MouseArea` con cursor de mano y señal `activated`;
  el padre decide si abre o cierra.

## Distribución de la categoría Calendario

Propuesta (recomendada): cabecera con reloj y avatar, calendario como bloque
principal y fila inferior con los chips de actividad y clima.

```
┌──── rail ────┬──────────────────────────────────────────────────────┐
│ ▣ calendario │  (avatar) Ezku      10:42                    ‹ ›     │
│              │            miércoles 28 de octubre    Octubre 2026   │
│              │  ┌────────────────────────────────────────────────┐  │
│              │  │  L   M   X   J   V   S   D                   │  │
│              │  │ 29  30   1   2   3   4   5                   │  │
│              │  │  6   7   8   9  10  11  12                   │  │
│              │  │ …                                           │  │
│              │  └────────────────────────────────────────────────┘  │
│              │  [⏱ Activo 2 h 28 min]   [☁ 24° Cielo nublado]        │
└──────────────┴──────────────────────────────────────────────────────┘
```

- La hora usa `Theme.fontUI` en ~64 px; los segundos no se muestran.
- El calendario empieza en lunes, marca hoy con círculo relleno en
  `Theme.m3Primary`, atenúa fines de semana y días de otros meses.
- Los chips de abajo usan `Theme.chip` con radio de media altura.

Alternativa B (dos columnas): reloj, avatar, actividad y clima en una columna
izquierda de ~300 px, calendario a la derecha. Menos altura vacía, pero la
hora queda menos protagonista.

## Datos

| Dato | Fuente | Respaldo |
|---|---|---|
| Hora y fecha | `SystemClock` + `Qt.locale("es_MX")` | — |
| Calendario | `Date` de JS: mes actual, semana desde lunes, navegación con ‹ › | — |
| Avatar | `~/.local/share/faces/$USER`, `~/.face`, `/usr/share/faces/$USER` | Monograma con la inicial sobre `Theme.m3Primary` |
| Nombre | `$USER` (o `getent passwd`) | Inicial sola |
| Actividad | `loginctl show-session $XDG_SESSION_ID -p ActiveEnterTimestamp` | `uptime -s` (uptime del sistema) con etiqueta distinta: "Sistema" |
| Clima | Open-Meteo, sin API key: geocodificación por ciudad + pronóstico | Ciudad en `~/.config/caparazon/weather.json`; si falta, geolocalización por IP (`ipapi.co`) cacheada 24 h. Caché de respuesta en `~/.cache/caparazon/weather.json`, TTL 15 min |

El clima se refresca cada 15 minutos con `Timer` y al abrir el menú. Sin red
el bloque muestra "—" y no rompe nada.

## Verificación

- Tests nuevos al estilo del repo (pytest sobre el QML y sobre lógica JS):
  - `Clock.qml` emite `activated` y `Bar.qml` abre `secondMenuState`.
  - La rejilla del mes calcula bien los días (inicio en lunes, meses de 28,
    29, 30 y 31 días, cambio de mes).
  - El menú nuevo no falla si faltan avatar, sesión o red.
- Suite completa del repo + ruff + basedpyright.
- Captura con `spectacle` del menú nuevo abierto, comparada con la del menú de
  apps, para confirmar mismo tamaño y diseño.
- Prueba en vivo: abrir desde el reloj, navegar meses, cambiar el acento y
  recargar la shell.

## Fuera de alcance

- Eventos y agenda: KDE Calendar no está integrado.
- Pronóstico por hora o por día.
- La segunda categoría del menú nuevo: el rail queda preparado, el contenido
  llega después.
- Atajo global de KDE: Quickshell 0.3 no expone atajos globales, así que el
  clic en el reloj es la vía principal.
- Notificaciones dentro del menú nuevo.

## Riesgos

- El chrome queda duplicado a propósito (los menús son independientes): si el
  menú de apps cambia de aspecto, el nuevo hay que ajustarlo a mano.
- El menú nuevo cubre la pantalla con su scrim, igual que el de apps. Por eso
  son excluyentes: abrir uno cierra al otro, y así el scrim y el foco nunca
  se encima.
