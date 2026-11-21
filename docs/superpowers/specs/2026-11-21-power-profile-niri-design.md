# Diseño: selector de perfil energético en niri (`caparazon-wm power-profile`)

Fecha: 2026-11-21 · Estado: pendiente de aprobación

## Intención y por qué

El chip de perfil energético de Caparazon (`modules/bar/PowerProfile.qml`) hoy
sólo funciona en Plasma: llama por `qdbus6` a
`org.kde.Solid.PowerManagement`. Bajo niri el clic no hace nada, porque niri
no tiene concepto de perfil energético (sus acciones son
`power-off-monitors`, `suspend`, etc.) y porque el widget habla con D-Bus de
KDE por su cuenta, saltándose la regla del repo de que todo pasa por
`caparazon-wm`.

El objetivo es que el selector funcione en ambos compositores y que el CLI sea
la única puerta al sistema.

## Hechos verificados

- KDE expone `currentProfile`, `profileChoices` y `setProfile` en
  `org.kde.Solid.PowerManagement`, objeto
  `/org/kde/Solid/PowerManagement/Actions/PowerProfile`. En vivo:
  `profileChoices` = `power-saver, balanced, performance`; perfil actual
  `performance`.
- `power-profiles-daemon` (apt, 0.30-2) es un servicio D-Bus del sistema,
  independiente del compositor, con los mismos tres nombres
  (`power-saver`, `balanced`, `performance`). En esta máquina no está
  instalado; `powerprofilesctl` tampoco.
- Los dos backends comparten vocabulario → no hace falta tabla de traducción.
- El widget no consulta nunca el perfil real: `profile` está fijado a
  `"balanced"` en el código, así que el icono miente hasta que se hace scroll.

## Metas

- `caparazon-wm power-profile` devuelve el perfil actual en JSON.
- `caparazon-wm power-profile --set <perfil>` aplica un perfil.
- Backend por compositor: Solid en Plasma, `power-profiles-daemon` en niri y
  en cualquier otro compositor; si el preferido no está disponible, se prueba
  el otro.
- El widget lee el perfil real al arrancar y refleja el resultado de aplicar
  uno (revierte si el comando falla).
- Sin backend disponible, el chip lo dice y no hace nada.
- Un solo vocabulario de tres perfiles en toda la shell.

## No metas

- No se instala ningún paquete automáticamente: `power-profiles-daemon` queda
  como paso manual documentado (en una máquina con Plasma y niri, tener PPD
  junto al powerdevil de KDE puede pelear por el governor de CPU).
- No se cambia el aspecto visual del chip.
- No se tocan los perfiles "hold"/"release" ni los estados *degraded* /
  *inhibited* de KDE.
- No se inventan perfiles ni se emula niri: niri no tiene ninguno.

## Restricciones

- El CLI es la única puerta al compositor y al sistema (regla del repo): el
  QML deja de hablar con `qdbus6`.
- TDD: test rojo antes de cada cambio de comportamiento.
- Sin commits hasta que el usuario lo pida explícitamente.

## Enfoques considerados

1. **Backend por compositor dentro de `caparazon-wm` (elegido).** Solid en
   Plasma, PPD en niri. El QML siempre llama al CLI, un solo vocabulario y sin
   traducciones. Mantiene el comportamiento actual de Plasma sin cambios.
2. **Sólo `power-profiles-daemon` en ambos.** Menos código, pero en Plasma
   duplicaría el control de powerdevil. Descartado.
3. **Brillo (`brightnessctl`) como "perfil" bajo niri.** No es un perfil
   energético: cambia el significado del chip y añade otro paquete.
   Descartado.
4. **Ocultar el chip bajo niri.** No es portarlo. Descartado.

## Diseño de las partes

### CLI — `integration/bin/caparazon-wm.py`

- `caparazon-wm power-profile` → JSON por stdout:
  `{"profile": "balanced", "choices": ["power-saver", "balanced", "performance"], "backend": "solid"|"ppd"|"none"}`.
- `caparazon-wm power-profile --set <perfil>` → aplica el perfil; código 0.
  Código 1 con mensaje en stderr si el perfil no está entre las `choices` o
  si no hay backend.
- Backend Solid: `qdbus6`/D-Bus de sesión sobre
  `org.kde.Solid.PowerManagement` (`.currentProfile`, `.profileChoices`,
  `.setProfile`).
- Backend PPD: `powerprofilesctl` (`list`, `get`, `set`).
- Selección: el compositor manda (`kwin` → Solid primero, resto → PPD
  primero); si el backend preferido no está disponible se prueba el otro.
  Sin ninguno: `backend: "none"`.

### QML — `modules/bar/PowerProfile.qml`

- Al cargar: ejecuta `caparazon-wm power-profile` y guarda `profile`,
  `choices` y `backend`.
- Al hacer scroll: `caparazon-wm power-profile --set <siguiente>`; actualiza
  el icono al instante y vuelve al valor anterior si el comando devuelve
  código distinto de 0.
- Con `backend == "none"`: el chip se atenúa, no acepta scroll y muestra
  "Sin soporte de perfil energético".
- Se conservan el círculo de fondo, el tono y los iconos actuales.

### Tests

- `tests/test_caparazon_wm.py` (ficheros falsos en `PATH`, mismo patrón que
  el resto del CLI):
  - PPD falso → `backend: "ppd"`, perfil leído y `--set` aplicado.
  - Solid falso → `backend: "solid"`, `.currentProfile` / `.profileChoices` /
    `.setProfile` leídos y aplicados.
  - Ninguno disponible → `backend: "none"`, consulta con código 0 y `--set`
    con código 1.
  - Perfil inválido → código 1 con mensaje en stderr.
- `tests/test_shell_qml_cli.py`: `PowerProfile.qml` llama a `caparazon-wm` y
  ya no menciona `qdbus6` ni `org.kde`.

### Documentación

- README: sección "Perfil energético" con la tabla de perfiles, cómo
  instalar `power-profiles-daemon` para las sesiones niri y el aviso de no
  instalarlo si se usa Plasma a diario.

## Qué queda para quien lo implemente

Nada: el diseño está cerrado (mapeo de nombres, backends, contrato JSON,
casos de test y documentación). Si al implementar aparece un dato que
contradice este documento, se para y se pregunta.
