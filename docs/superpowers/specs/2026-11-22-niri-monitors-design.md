# Gestión de monitores en Niri configs

## Intención

Agregar un tercer elemento a la categoría **Niri configs** de Caparazón Shell para ver los monitores conectados y cambiar, desde la shell, lo que niri guarda en su configuración: monitor con foco al iniciar, resolución, tasa de refresco, rotación y posición.

Hoy la categoría sólo ofrece **Iconos** y **Cursor** mediante `SegmentedChoice` + `Flickable`. El config de niri no tiene bloques `output` activos; sólo ejemplos comentados en `10-input-and-cursor.kdl` y `90-user-extra.kdl`. El nuevo panel debe seguir el mismo contrato: QML pregunta y manda al CLI, y `caparazon-wm` es la única puerta al sistema.

## Objetivos

- Mostrar los outputs conectados por `niri msg --json outputs`: conector, fabricante/modelo/serial, modo actual y modos disponibles.
- Permitir elegir el monitor principal mediante `focus-at-startup`.
- Hacer que `primary-output` devuelva ese mismo monitor para que barra, dock y el resto de la shell lo traten como principal y a los demás como secundarios.
- Permitir cambiar modo `ANCHOxALTO@HHH.MMM`, transformación de rotación y posición `x/y`.
- Escribir los cambios en un archivo propio `config.d/15-outputs.kdl` y recargar niri con `niri msg action load-config-file`.
- Conservar el comportamiento actual de KDE/Plasma: el panel y el subcomando sólo operan cuando el compositor detectado es niri.

## No objetivos

- No tocar `40-environment.kdl`, `50-startup.kdl`, `~/.config/autostart` ni archivos de KDE.
- No exponer `scale`, VRR, apagado de outputs ni modos personalizados.
- No crear un concepto de “principal” distinto de `focus-at-startup`; la posición se edita aparte.
- No disponer monitores automáticamente: los valores `x/y` son explícitos.
- No cambiar el comportamiento de `primary-output` en KDE/Plasma; el cambio es sólo para niri.

## Anti-objetivos

- Que QML escriba archivos, ejecute `niri` directamente o conozca rutas de configuración.
- Que un cambio visual quede sólo en memoria: la fuente de verdad es el config de niri.
- Que un futuro bloque `output` activo en otro archivo sea sobrescrito o duplicado sin aviso.

## Restricciones

- Español en mensajes, errores y texto visible.
- Sin commits salvo petición explícita.
- TDD estricto: tests primero, implementación después.
- Sin delegación a agentes premium; trabajo directo con el modelo actual.
- Ejecución nativa: pytest, qmllint y QA con niri real.
- El CLI es la única puerta al sistema.
- No se debe afectar el funcionamiento de la shell con KDE.

## Approaches

### A. Config persistente, sin vista previa (elegida)

`caparazon-wm monitors` devuelve el estado detectado; `caparazon-wm monitors --apply <json>` valida, escribe `15-outputs.kdl`, añade su `include` a `config.kdl` si falta y recarga niri. La interfaz muestra el estado y aplica al pulsar **Aplicar**.

- A favor: encaja con Iconos/Cursor, es determinista y fácil de testear.
- En contra: no se ve el resultado hasta guardar.
- Es la opción elegida por el usuario.

### B. Vista previa en vivo con guardado posterior

Cada control llamaría antes a `niri msg output <nombre> mode|transform|position`, y **Guardar** escribiría el config.

- A favor: feedback inmediato.
- En contra: más estado, rollback y riesgo de sesión distinta del config; innecesario para el caso de uso.

### C. Editor crudo de KDL (descartado)

Mostrar el texto de los bloques `output` para editarlo.

- En contra: expone sintaxis, validación débil y rompe el patrón de CLI como única puerta.

## Decisiones de diseño

### Contrato del CLI

- `caparazon-wm monitors`: imprime un JSON con:
  - `outputs`: lista con `name`, `label`, `make`, `model`, `serial`, `primary`, `primary_configured`, `mode`, `modes`, `transform`, `x`, `y`.
  - `modes`: lista de objetos con `label`, `preferred` y `current`, para poder ordenar sin perder `is_preferred`.
  - `configured`: si existe `15-outputs.kdl` con bloques propios.
  - `error`: mensaje cuando niri no está disponible.
- `caparazon-wm monitors --apply <json>`: recibe un payload con `primary` y la lista `outputs`, cada una con `name`, `mode`, `transform`, `x`, `y`.
- Validación antes de escribir:
  - niri debe estar detectado como compositor.
  - todos los nombres deben existir entre los outputs conectados.
  - `primary` debe estar en la lista.
  - cada `mode` debe pertenecer a los modos reales de ese output.
  - `transform` debe estar en `normal`, `90`, `180`, `270`, `flipped`, `flipped-90`, `flipped-180`, `flipped-270`.
  - `x` e `y` deben ser enteros.
- Si hay bloques `output` activos fuera de `15-outputs.kdl`, el apply falla con un mensaje claro en vez de duplicarlos.
- `primary-output` en niri pasa a leer el monitor con `focus-at-startup` del config propio y devolverlo si está conectado y habilitado; si no hay uno válido, mantiene el fallback actual de salida superior izquierda.

### Formato de modo

`niri msg --json outputs` expone `refresh_rate` en milihz. El CLI genera el texto exacto que niri exige con tres decimales: `f"{refresh_rate / 1000:.3f}"`. Ejemplos reales: `1920x1080@60.000`, `1024x768@60.004`.

### Estado de “principal”

Como niri no tiene prioridad de monitor, el estado `primary` se resuelve así:

1. Nombre con `focus-at-startup` en `15-outputs.kdl`, si existe.
2. Si no hay ninguno configurado, la salida superior izquierda que ya devuelve `primary_output_niri()`.

`primary_configured` distingue ambos casos. La interfaz siempre envía un `primary` en el apply, de modo que después de guardar queda explícito. Ese mismo valor pasa a ser la respuesta de `caparazon-wm primary-output` en niri, que es la fuente que ya consulta `ShellLayout.qml` para decidir principal y secundarios.

### Escritura del config

- Archivo propio: `~/.config/niri/config.d/15-outputs.kdl`, respetando `NIRI_CONFIG` y `XDG_CONFIG_HOME` a través de `niri_config_path()`.
- `config.kdl` recibe `include "config.d/15-outputs.kdl"` justo después del include de `10-input-and-cursor.kdl`, de forma idempotente.
- Cada bloque lleva `mode`, `transform`, `position x=... y=...`, `scale` con el valor efectivo actual y `variable-refresh-rate` sólo si está activo.
- El bloque del monitor principal lleva además `focus-at-startup`.
- El apply conserva los bloques de outputs desconectados que ya vivan en `15-outputs.kdl` y reemplaza sólo los outputs conectados incluidos en el payload.
- Escritura atómica con archivo `.tmp`, `chmod 0o644` y `os.replace`, igual que los temas de iconos y cursor.
- Después de escribir se llama a `reload_niri_config()`. Si falla la recarga, el archivo queda guardado y el CLI devuelve error con mensaje explícito.
- Tras recargar correctamente se ejecuta `niri msg action focus-monitor <principal>` para que el cambio de foco se note en la sesión actual; `focus-at-startup` sigue siendo la persistencia para el próximo arranque.

### Panel QML

- Nuevo `modules/secondmenu/MonitorsPanel.qml`, montado por `NiriConfigsPanel.qml` como sección `{ key: "monitores", label: "Monitores" }`.
- Mantiene `Flickable`, `SegmentedChoice`, `Loader` y `componentFor` existentes; no crea pestañas propias.
- Carga estado con `Process { command: ["caparazon-wm", "monitors"] }`.
- Aplica con `Process { command: ["caparazon-wm", "monitors", "--apply", root.pendingJson] }`.
- Controles, sin depender de `QtQuick.Controls`:
  - fila de monitores conectados;
  - lista desplazable de modos disponibles;
  - rotación con `SegmentedChoice` de cuatro opciones visibles (`Normal`, `90°`, `180°`, `270°`);
  - campos numéricos `x` e `y`;
  - selector de principal;
  - botón **Aplicar** y texto de estado/error.
- El panel no contiene rutas `.config`, ni `FileView`, ni comandos `niri`.

## Lo que queda al implementador

- Nombres concretos de funciones y dataclasses en `caparazon-wm.py`.
- Estructura interna exacta del parser KDL y del constructor de bloques.
- Detalle de los controles QML y su maquetación dentro de 800×550.
- Mensajes de error concretos y textos de ayuda.
- División de tests en archivos y fixtures.
- Decidir, durante el plan, si los modos se ordenan por preferido/actual o por resolución y refresco; el estado debe conservar `is_preferred` para permitirlo.
