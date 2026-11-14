# Barra vertical (izquierda/derecha) — diseño

Fecha: 2026-11-12

## Intención y por qué

La barra hoy sólo vive en el borde superior o inferior. El usuario quiere poder
moverla también a los laterales, como el dock, sin perder su identidad: mismo
cristal, misma curva cóncava pegada al filo, mismo radio, misma sombra.

En vertical la barra **ocupa todo el alto de la pantalla** y mantiene **el
mismo grosor que la barra horizontal tiene de alto** (`Theme.barHeight`, 40 px).
No es un panel ancho: es una tira.

Los menús (menú de bandeja y submenú) **no se adaptan al giro**: el menú de
aplicaciones y su submenú se abren **en el centro** de la pantalla cuando la
barra está en un lateral, y en horizontal siguen donde están (sobre su icono).
El reloj se mantiene en **12 horas** en las dos orientaciones.

## Objetivos

- La barra se ancla en los cuatro bordes: arriba, abajo, izquierda, derecha.
- En vertical: tira de 40 px de ancho, alto completo de la pantalla, pegada al
  borde, con el estilo y diseño intactos.
- El contenido se apila en una sola columna conservando el orden de lectura
  del horizontal (izquierda → arriba, centro → centro, derecha → abajo).
- Los anillos se ocultan cuando la bandeja de apps en segundo plano está
  desplegada, en cualquier posición (regla que ya existía en modo compacto).
- La elección se guarda en `display.json` y se elige desde Configs.

## Fuera de alcance (anti-objetivos)

- No se rediseña la barra: ni ancho, ni colores, ni componentes nuevos.
- No se adapta el contenido a la barra vertical con variantes "bonitas": si no
  cabe en 40 px, se compacta.
- No se rediseña el dock (ya es vertical).
- No se toca la lógica de menús (dirección de apertura, contenido, barreras).

## Restricciones

- Quickshell 0.3.2 / Qt 6.10. `PanelWindow` con `anchors` parciales.
- `Theme.barHeight` = 40 px es el grosor de la tira vertical.
- La ventana de la barra es más grande que el cristal por `Theme.shadowPad`
  (aire para la sombra). Ese aire va siempre hacia el interior de la pantalla.
- `exclusiveZone` reserva la franja visible (40 px), no el aire de la sombra.
- El dock ya resolvió el giro de 90° del trazado (`px()`/`py()`/`inverse()` en
  `Dock.qml`): la barra reutiliza ese patrón.

## Enfoques considerados

1. **Tira vertical de 40 px, alto completo (elegido).** Rotación 1:1 de la
   barra horizontal. Coste: cada componente con contenido ancho necesita una
   versión vertical (reloj de dos líneas, ventana activa sólo con icono,
   anillos y bandeja en columna).
2. **Panel lateral ancho (~220 px).** Todo legible en filas apiladas, pero deja
   de ser una barra y se come mucha pantalla. Descartado por el usuario: el
   grosor se mantiene.
3. **Tira fina con textos girados 90°.** Cabe todo pero se lee de lado.
   Descartado.

## Cómo se monta

### La ventana (Bar.qml)

- `position` acepta `"top" | "bottom" | "left" | "right"`.
- `vertical` = `position === "left" || position === "right"`.
- Anclaje de la `PanelWindow`:
  - horizontal: `top`/`bottom` + `left`/`right` (como hoy), con `sideMargin`.
  - vertical: `top` + `bottom` + `left` (si es izquierda) o `right` (si es
    derecha), sin márgenes laterales: la ventana ocupa todo el alto pegada al
    borde.
- Medidas: en vertical `implicitWidth = Theme.barHeight + Theme.shadowPad`; en
  horizontal sigue mandando `implicitHeight`.
- `hitArea`: en vertical es una franja vertical de `Theme.barHeight` de ancho y
  todo el alto; el aire de la sombra queda hacia el interior (a la derecha si
  la barra está a la izquierda, al revés si está a la derecha).
- `frame` (el recorte del revelado): en horizontal crece en alto desde el filo;
  en vertical crece en ancho desde el filo (izquierda → crece hacia la
  derecha; derecha → crece hacia la izquierda).
- Sombra (`MultiEffect`): en vertical el desplazamiento pasa al eje
  horizontal (hacia dentro de la pantalla), igual que hace el dock.
- `exclusiveZone`: `Theme.barHeight` en los cuatro bordes.

### El cristal (ShapePath)

Se reescribe el trazado en el espacio canónico del dock — el "filo" abajo, con
sus dos esquinas cóncavas — y se mapea a cada borde con `px()`/`py()` e
`inverse()`, igual que `Dock.qml`:

- arriba: espejo vertical (es el comportamiento actual)
- abajo: identidad
- izquierda/derecha: giro de 90° que conserva el sentido de los arcos

Los radios no cambian: `Theme.radiusTop` para el labio cóncavo del filo y
`Theme.radius` para las esquinas convexas del lado interior.

### El contenido (Bar.qml)

En vertical los tres grupos se apilan en una columna:

- **Arriba** (lo que hoy está a la izquierda): lanzador, escritorios, ventana
  activa.
- **Centro** (lo que hoy está en el centro): chip de actualización, reloj,
  notificación, multimedia.
- **Abajo** (lo que hoy está a la derecha): anillos, bandeja, iconos de estado.

### Componentes con versión vertical

| Componente | Horizontal | Vertical |
|---|---|---|
| `Workspaces` | fila de indicadores | columna de indicadores |
| `ActiveWindow` | icono + nombre (limitado) | sólo el icono (26 px) |
| `Clock` | hora + separador + fecha | 12 h en dos líneas: "10 PM" arriba, "42" abajo (≤ 40 px) |
| `MediaChip` | carátula + título | sólo la carátula |
| `ResourceMonitor` | fila de anillos | columna de anillos |
| `Tray` | fila de iconos | columna de iconos; al desplegarse crece hacia arriba |
| Iconos de estado | fila | columna |

Cada componente recibe un `vertical` (o `compact`) y cambia su layout, no su
estilo. Los que ya tienen `compact` (`Clock`, `ActiveWindow`) reutilizan ese
camino.

### Los anillos y la bandeja

Regla nueva, general:

```
ringsShown = (vertical || !compactBar) && tray.collapsed
```

Es decir: los anillos se ocultan siempre que la bandeja de apps en segundo
plano esté desplegada (en cualquier posición), y además en modo compacto
horizontal. En vertical es obligatorio: la bandeja desplegada y los anillos
comparten la misma columna y se pisarían.

### La bandeja desplegada en vertical

La bandeja plegada sigue siendo un círculo (26 px). Desplegada, la columna de
iconos crece **hacia arriba** (hacia el centro de la tira), igual que en
horizontal crece hacia la izquierda. El orden de los iconos se invierte
(primero el más cercano al botón), como ya ocurre en horizontal.

### Los menús

Regla del usuario: el **menú de aplicaciones y su submenú están en el centro**,
sin importar dónde esté la barra.

- **Barra en un lateral (izquierda/derecha):** el menú de aplicaciones se abre
  **centrado horizontalmente en la pantalla**, abriendo hacia arriba desde la
  altura de su icono (que está al final de la tira). Al estar centrado no hay
  excepción de borde: el submenú sigue abriendo hacia la izquierda, como
  siempre, y ya no puede salirse de la pantalla.
- **Barra horizontal (arriba/abajo):** el menú se abre sobre su icono, en el
  borde derecho, y el submenú a la izquierda. No se toca nada de lo que ya
  funciona.

El cálculo del ancla del menú (`barBottomInItem`, `anchor.rect.y`) asume hoy
una barra horizontal. En vertical se sustituye por el borde superior real del
icono, para que el menú salga pegado al icono igual que hoy.

### Configuración

- `ShellLayout.setBarPosition()` acepta los cuatro valores.
- El adaptador de `display.json` deja de forzar `"top"`: acepta los cuatro y
  cae a `"top"` sólo si el valor no es válido.
- `ShellConfigPanel.barPositionRows` gana las filas "Izquierda" y "Derecha",
  con su nota (columna vertical de 40 px, alto completo).

## Qué queda para quien lo construya

- Reordenar `Bar.qml` sin romper la versión horizontal (que debe quedar
  idéntica: mismo aspecto, mismos tamaños, mismos menús).
- Comprobar en pantalla: barra a la izquierda y a la derecha, con la bandeja
  plegada y desplegada, con y sin anillos visibles.
- `qmllint` no sirve (imports de Quickshell): la verificación es el log de
  Quickshell sin errores ni warnings nuevos + la revisión visual del usuario.

## Verificación

- `quickshell log -i <instancia>`: sin errores ni warnings tras recargar.
- El usuario valida el aspecto en los cuatro bordes.
- Regresión: la barra horizontal (arriba y abajo) debe quedar como está.
