# Diseño: `Super+D` maximiza la columna en niri

Fecha: 2026-11-23 · Estado: aprobado por el usuario; implementado y verificado.

## Intención

El usuario pidió que `Super+D` deje de abrir el menú y pase a maximizar la ventana. Tras revisar las acciones disponibles en niri 26.04, eligió **maximizar la columna** (`maximize-column`), no maximizar a bordes ni pantalla completa.

## Hechos verificados

- Antes del cambio, `~/.config/niri/config.d/70-binds.kdl` tenía `Mod+D { spawn "caparazon-shell-ipc" "menu" "toggle"; }`.
- Antes del cambio, `integration/niri/config.kdl` tenía el mismo bind.
- `Mod+Space` ya abre el menú principal en ambas configs; la config instalada además tiene `Mod+F { fullscreen-window; }` (la copia del repo no declara `Mod+F`).
- La documentación oficial de niri distingue `maximize-column` (ancho completo, conserva bordes/gaps/struts), `maximize-window-to-edges` (maximizado clásico sin bordes ni gaps) y `fullscreen-window` (cubre también la barra).
- `niri validate` existe en la versión instalada (`niri 26.04 (e40b7520-modified)`).

## Metas

- Reemplazar `Mod+D` por `Mod+D { maximize-column; }` en la config instalada y en la copia versionada del repo.
- Mantener `Mod+Space` como único atajo del menú principal.
- Mantener `Mod+F` como pantalla completa.
- Cubrir el contrato con un test rojo antes del cambio.
- Validar ambas configs y recargar niri en vivo sin comprobaciones visuales.

## No metas

- No cambiar `maximize-window-to-edges`, `fullscreen-window`, `Mod+F` ni `Mod+Space`.
- No tocar Plasma, KWin, autostart, iconos, cursor, monitores ni Waywallen.
- No crear un `~/dotfiles`; el repo ya versiona la config de instalación.

## Restricciones

- Responder en español.
- TDD estricto: test rojo antes del cambio de comportamiento.
- CLI como puerta de validación/recarga: `niri validate` y `niri msg ...`, sin QML escribiendo ficheros.
- Sin commits salvo petición explícita.
- Sin comprobaciones visuales ni interrumpir el mouse sin permiso explícito.
- No afectar el funcionamiento de la shell con KDE.

## Enfoques considerados

1. **Maximizar columna (elegido).** `Mod+D { maximize-column; }`. Es la opción que pidió el usuario; conserva bordes/gaps y sigue siendo una columna normal del layout scrollable.
2. **Maximizar a bordes.** `maximize-window-to-edges`; más parecido a otros escritorios, pero oculta bordes/gaps y el usuario no lo eligió.
3. **Pantalla completa.** `fullscreen-window`; cubre la barra y ya está asignado a `Mod+F`, por lo que duplicaría acción.

## Decisiones de diseño

- El test vivirá en `tests/test_niri_binds.py` y afirmará que la config del repo contiene `Mod+D { maximize-column; }` y ya no contiene el bind anterior de menú en `Mod+D`.
- La config instalada se editará con el mismo reemplazo exacto, sin tocar backups ni otros archivos de `config.d`.
- Después del cambio se ejecutará `niri validate` sobre la config instalada y se recargará la config de niri en vivo.

## Lo que queda al implementador

- Escribir el test, verlo fallar, aplicar los dos reemplazos, verlo pasar.
- Ejecutar la suite completa de pytest, `ruff`, `git diff --check` y validación/recarga de niri.
- Reportar el resultado sin hacer comprobaciones visuales.
