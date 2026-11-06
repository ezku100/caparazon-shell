# Estilos de color de la shell: Material, OLED y Perla

Fecha: 2026-11-06
Estado: propuesta (esperando aprobación)

## Objetivo

Una categoría nueva en el raíl del menú secundario, **Configs de la shell**,
que por ahora sólo ofrece el **estilo de color** de la shell. Tres estilos:

- **Material**: el actual, sin cambios.
- **OLED**: fondo negro y acentos mucho más vivos, para que los colores del
  acento se distingan sobre el fondo.
- **Perla**: tema blanco, con el fondo en un blanco perla y los colores de
  acento elegidos para que resalten sobre ese tono.

La categoría lleva el mismo kanji `猫` que el botón de menú.

Requisito de fondo: **los tres estilos tienen que conservar el mismo número
de plantillas que Material** (los mismos 17 tokens) y **tienen que seguir al
color de énfasis de KDE**: cuando cambias el acento, las tres paletas se
regeneran solas y la shell sigue con el estilo que tengas elegido.

Al terminar se commitea y sube a GitHub en los dos repos: `caparazon-shell`
y `accent-theme` (los dos son del usuario y van de la mano).

## Enfoques considerados

### 1. Transform de saturación por plantilla en el motor — **elegido**

El motor `accent-theme` acepta una clave opcional `saturation` en el
descriptor de una plantilla. Cuando está presente, el motor multiplica la
saturación HSV de los colores que matugen escribió en esa plantilla antes de
publicarla.

- A favor: las tres paletas quedan **en disco ya transformadas**, así que el
  `doctor` y la validación de `install.sh` ven exactamente lo que se ve; la
  decisión del "vivo" vive en un solo sitio; el motor sigue siendo el único
  que regenera las paletas cuando cambia el acento; la shell sólo elige qué
  archivo leer.
- En contra: hay que tocar el repo `accent-theme` (es el segundo repo) y
  relajar la validación del descriptor, que hoy rechaza cualquier clave que
  no sea `name`, `input_path` u `output_path`.

### 2. Boost de saturación dentro de la shell — descartado

Las mismas tres plantillas y los mismos registros, pero el motor no se toca: el
multiplicador se aplica al leer la paleta, en `MatugenPalette.qml`.

- A favor: un solo repo.
- En contra: el archivo en disco no coincide con lo que se ve; el color queda
  partido entre la plantilla y el ajuste; cualquier otra app que lea
  `colors-oled.json` vería la paleta sin boost.

### 3. Matugen con un esquema por estilo — descartado

Extender el motor para correr matugen con `-t scheme-vibrant` (OLED) y `-m
light` (Perla), una invocación por estilo.

- A favor: los colores los genera matugen entero, sin ajustes a posteriori.
- En contra: es el cambio más grande en el motor (varias invocaciones, caché y
  config de matugen), y "más saturado" quedaría a merced de que
  `scheme-vibrant` dé el punto. Además, el motor actual no lee los roles
  `.light`, y esa lectura hay que escribirla igual.

## Arquitectura

### 1. Motor `accent-theme`: `saturation` opcional por descriptor

Repo: `~/.local/share/accent-theme/source` (se sube a GitHub).

#### 1.1 Formato del descriptor

El parser de descriptores (`src/accent_theme/registry.py`) es propio y hoy
sólo acepta tres claves de texto. Se le añade **una clave opcional numérica**:

```toml
name = "caparazon-shell-oled"
input_path = "~/.config/accent-theme/templates/caparazon-shell-oled/quickshell-oled.json"
output_path = "~/.cache/caparazon/colors-oled.json"
saturation = 1.45
```

- `saturation` es un multiplicador de saturación HSV (`1.0` = sin cambio,
  `1.45` = 45 % más saturado). Si no aparece, la plantilla se publica tal
  cual: es el comportamiento actual.
- El valor se valida: debe ser un número `>= 1.0`. Un valor inválido es un
  error de registro, con el mismo estilo de mensaje que los demás errores de
  `registry.py` (`RegistryError`).
- `TemplateRegistration` gana un campo `saturation: float | None`.
- `render_matugen_config` **no** cambia: la clave `saturation` no forma parte
  del config de matugen, sólo del descriptor del motor.

#### 1.2 Propagación en `register`

`_handle_register` (en `cli.py`) reescribe el descriptor instalado con las
tres claves que matugen necesita. Tiene que **conservar `saturation`**, o el
boost se perdería justo después de registrar la plantilla. El descriptor
instalado en `~/.config/accent-theme/templates.d/caparazon-shell-oled.toml`
llevará por tanto las cuatro claves.

#### 1.3 Dónde se aplica

En `_handle_generate`, el bucle actual publica cada plantilla así:

```python
for registration in registrations:
    if registration.staging_path.exists():
        _ = registration.staging_path.replace(registration.output_path)
```

Ahí se inserta el transform: si la registration trae `saturation`, el JSON
que matugen dejó en `staging` se transforma y se vuelve a escribir **de forma
atómica** antes del renombrado. El resultado en disco es la paleta final.

Se respeta la atomicidad que ya garantiza el motor: el rename final sigue
siendo el paso que publica el archivo.

#### 1.4 Módulo nuevo: `src/accent_theme/transform.py`

- `boost_saturation(document: dict[str, str], factor: float) -> dict[str, str]`:
  recorre los valores del JSON y multiplica la saturación HSV de cada hex de
  seis dígitos. Los valores que no son hex (`"transparent"`, números, texto)
  se dejan como están.
- La conversión usa `colorsys`, que el motor ya usa en `accent.py`
  (`rgb_to_hsv` / `hsv_to_hex`): mismo lenguaje de color en todo el motor.
- La saturación se acota a `[0, 1]`: un acento ya saturado al 100 % no se
  deforma.
- Los colores **neutros** (saturación 0) no cambian: por eso la plantilla
  OLED tiene que usar grises **neutros puros** (`#000000`, `#080808`, …) y no
  grises con un pelo de tinte (un `#08080B` sí tiene saturación y se
  volvería azulado al aplicar el boost).

#### 1.5 `doctor`

El `doctor` lista las integraciones registradas. Con el transform, OLED
aparece como una integración más, pero con el boost visible: la línea de
cobertura pasa a distinguir `caparazon-shell-oled: ok (saturación 1.45)`. Es
informativo, no obligatorio para que el doctor pase.

### 2. Las tres plantillas (repo `caparazon-shell`)

`integration/theme/` pasa a tener tres plantillas con **los mismos 17
tokens**, las mismas claves y el mismo orden:

| Plantilla | Archivo | Tokens | Origen de cada color |
|---|---|---|---|
| Material | `quickshell-matugen.json` | 17 | `{{colors.<rol>.dark.hex}}` (sin cambios) |
| OLED | `quickshell-oled.json` | 17 | superficies fijas + acentos `{{colors.<rol>.dark.hex}}` + boost del motor |
| Perla | `quickshell-perla.json` | 17 | superficies fijas + acentos `{{colors.<rol>.light.hex}}` |

Los 17 tokens son los de `integration/theme/required-tokens.txt`: `surface`,
`surfaceContainerLowest`, `surfaceContainerLow`, `surfaceContainer`,
`surfaceContainerHigh`, `surfaceContainerHighest`, `fgSurface`,
`fgSurfaceVariant`, `outline`, `outlineVariant`, `primary`, `fgPrimary`,
`secondary`, `tertiary`, `error`, `errorContainer`, `fgErrorContainer`.

**El archivo `required-tokens.txt` no cambia**: es el mismo contrato para las
tres plantillas. Eso es exactamente la paridad que pide el requisito.

#### 2.1 OLED (`quickshell-oled.json`)

Superficies en negro y grises **neutros puros** (saturación 0, así que el
boost no las toca):

| Token | Valor |
|---|---|
| `surface` | `#000000` |
| `surfaceContainerLowest` | `#000000` |
| `surfaceContainerLow` | `#080808` |
| `surfaceContainer` | `#0F0F0F` |
| `surfaceContainerHigh` | `#161616` |
| `surfaceContainerHighest` | `#1E1E1E` |
| `fgSurface` | `#F2F2F2` |
| `fgSurfaceVariant` | `#B8B8B8` |
| `outline` | `#6E6E6E` |
| `outlineVariant` | `#2A2A2A` |

Los acentos salen de matugen en modo oscuro y los sube el motor:
`primary`, `fgPrimary`, `secondary`, `tertiary`, `error`, `errorContainer` y
`fgErrorContainer` usan `{{colors.<rol>.dark.hex}}`.

#### 2.2 Perla (`quickshell-perla.json`)

Superficies en blanco perla cálido (valores fijos):

| Token | Valor |
|---|---|
| `surface` | `#FAF9F6` |
| `surfaceContainerLowest` | `#FFFFFF` |
| `surfaceContainerLow` | `#F4F2ED` |
| `surfaceContainer` | `#EDEAE4` |
| `surfaceContainerHigh` | `#E5E1DA` |
| `surfaceContainerHighest` | `#DBD6CD` |
| `fgSurface` | `#1C1B19` |
| `fgSurfaceVariant` | `#56534D` |
| `outline` | `#9B968C` |
| `outlineVariant` | `#D6D1C7` |

Los acentos salen de matugen en modo **claro** (`{{colors.<rol>.light.hex}}`):
en esquema claro, `primary` es el tono 40 (oscuro, legible sobre perla) y
`on_primary` es el tono 80. Verificado: matugen entrega los 17 roles también
en `.light` dentro de la misma invocación `-m dark`, así que Perla usa el
**mismo acento** que Material, sólo que con los roles claros.

### 3. Registro e instalación (`install.sh`)

- Se registran tres integraciones con el motor:
  `caparazon-shell` (Material, `colors.json`), `caparazon-shell-oled`
  (`colors-oled.json`, con `saturation = 1.45`) y `caparazon-shell-perla`
  (`colors-perla.json`, sin boost).
- Cada descriptor vive en `integration/theme/`: `accent-theme.toml` (el
  actual), `accent-theme-oled.toml` y `accent-theme-perla.toml`.
- `validate_palette` pasa a comprobar los **tres** archivos contra el mismo
  `required-tokens.txt`: si a cualquiera de las tres paletas le falta un
  token, la instalación falla diciendo qué token y en qué archivo.
- El motor genera las tres en una sola pasada de matugen: cuando cambia el
  acento de KDE, `accent-theme generate` regenera las tres y la shell sigue
  con el estilo elegido.

### 4. La shell: elegir el estilo y repintar en vivo

#### 4.1 `theme/ThemeStyle.qml` (singleton nuevo)

Vive en `theme/` y se registra en `theme/qmldir` junto a `Theme` y
`MatugenPalette`.

- Lee `~/.config/caparazon/style.json` (`{"style": "oled"}`) con `FileView` +
  `JsonAdapter`, siguiendo el patrón de `PanelSettings.qml` y
  `MusicSettings.qml`: escritura atómica (a un `.tmp` y renombrando), bandera
  `loaded` para no pisar la preferencia con el valor por defecto, y
  `watchChanges` para reflejar cambios externos.
- Expone `style` (`"material"`, `"oled"` o `"perla"`) y `paletteFile`, que
  devuelve el nombre del archivo de paleta que corresponde:
  `colors.json`, `colors-oled.json` o `colors-perla.json`.
- `setStyle(value)` sólo acepta los tres valores conocidos.
- Si el archivo de paleta del estilo elegido **no existe** (instalación a
  medias, paleta borrada), el estilo cae a `material` y el panel lo dice. La
  shell nunca se queda sin paleta: `MatugenPalette` conserva sus valores de
  reserva.

#### 4.2 `theme/MatugenPalette.qml`

- El `FileView` de la paleta pasa a leer el archivo que manda `ThemeStyle`.
  Quickshell recarga el `FileView` cuando cambia su `path`, así que el cambio
  de estilo se ve al instante; además se fuerza un `reload()` al cambiar el
  estilo, por si acaso.
- Los 17 tokens y sus valores de reserva **no cambian**: siguen siendo los de
  Material, que es el plan B si falta un archivo.
- `theme/Theme.qml` **no cambia**: ya mapea los tokens a `m3*` y a los alias
  (`surface`, `text`, `chip`, …). Todo lo que usa `Theme.*` se repinta solo.

#### 4.3 Colores con hexadecimal fijo

Hay seis archivos con hex a mano: los scrims `#000000` (`AppMenu.qml`,
`PowerMenu.qml`, `SecondMenu.qml`), el texto del adiós `#FFFFFF`, el azul de
Google Calendar `#4285F4`, el vinilo `#141414`/`#2e2e2e` de `MusicPanel.qml` y
el scrim `#66000000` del diálogo de calendarios.

Decisión: **no se tocan en este trabajo**. Los scrims negros funcionan igual
en los tres estilos, el azul de Google es de marca y el vinilo negro se lee
bien también sobre perla. Se anotan aquí para que quede constancia de la
decisión y por si más adelante chican.

### 5. La categoría en el menú secundario

#### 5.1 El kanji en el raíl

El kanji `猫` del botón de menú (`modules/bar/LauncherButton.qml`) es un
`Text` con `Theme.fontJP`. El `RailButton` del raíl (`modules/appmenu/
RailButton.qml`) sólo sabe pintar un `IconImage` de tema, así que **no** puede
mostrar el kanji tal cual.

Se le añade a `RailButton` una propiedad opcional `glyph` (vacía por
defecto). Cuando `glyph` no está vacía, el botón pinta un `Text` con
`Theme.fontJP` en vez del `IconImage`, con **los mismos colores que usa hoy el
tinte del icono** (`Theme.textDim`, y `Theme.text` al pasar el ratón). Así el
raíl queda homogéneo y el test de contraste del raíl
(`tests/test_category_rail_contrast.py`) sigue valiendo: la selección no
re-tiñe el glifo.

El botón de menú de apps (`AppMenu.qml`) no usa `glyph`, así que no cambia.

#### 5.2 La categoría

- `modules/secondmenu/SecondMenu.qml`: la lista `categories` (líneas 47-51)
  crece con `{ key: "configs", glyph: "猫", label: "Configs de la shell" }`.
- El `Loader` de contenido (líneas 287-293) recibe su rama: `root.category ===
  "configs"` devuelve el componente nuevo.
- El `Component` nuevo monta `ShellConfigPanel.qml`.

`shell.qml` **no cambia**: `secondMenuState.category` es una cadena libre y el
IPC `menu2 open <categoría>` ya acepta la que sea
(`quickshell ipc call menu2 open configs`).

#### 5.3 El panel: `modules/secondmenu/ShellConfigPanel.qml`

Nuevo panel del submenú, con el mismo estilo del resto (tokens de `Theme`,
radios 11-16, `HoverChip`). Por ahora sólo una sección: **Estilo de color**.

```
┌ rail ────────┬──────────────────────────────────────────────┐
│ ▣ calendario │  Configs de la shell                         │
│ ♪ musica     │                                              │
│ 🖥 sistema   │  Estilo de color                             │
│ 猫 configs   │  ┌──────────────────────────────────────────┐  │
│              │  │ ● Material   ▪▪▪  el de ahora            │  │
│              │  │   OLED       ▪▪▪  negro, acentos vivos   │  │
│              │  │   Perla      ▪▪▪  blanco perla           │  │
│              │  └──────────────────────────────────────────┘  │
│              │                                              │
│              │  El estilo se aplica al instante.             │
└──────────────┴──────────────────────────────────────────────┘
```

- Tres filas, una por estilo. Cada fila: punto de selección, nombre, tres
  muestras de color (fondo, superficie, acento) y una descripción corta.
- La muestra de acento usa el valor real del estilo (el token `primary` de su
  paleta), así que se ve cómo queda con el acento actual de KDE.
- Al pulsar una fila: `ThemeStyle.setStyle(...)` → la shell se repinta.
- Si el archivo de paleta del estilo falta, la fila aparece desactivada con
  una nota ("falta instalar esta paleta").

## Verificación

### Tests del motor (`accent-theme`)

- `test_registry.py`: la clave `saturation` es opcional; `1.45` se acepta;
  `0.8`, un texto o un valor no numérico son error de registro; la clave
  sigue siendo opcional en los descriptores viejos.
- `test_transform.py` (nuevo): un gris neutro no cambia con boost; un color
  cromático sí; la saturación se acota a 1; los valores que no son hex se
  dejan intactos.
- `test_cli.py`: `generate` publica la paleta transformada; `register`
  conserva la clave `saturation` en el descriptor instalado.

### Tests de la shell (`caparazon-shell`)

- `tests/test_theme_install_contract.py`: existen las tres plantillas con los
  mismos 17 tokens; los tres descriptores son válidos; `install.sh` registra
  las tres y valida los tres archivos de paleta.
- `tests/test_shell_style.py` (nuevo): `ThemeStyle.qml` expone los tres
  estilos y sólo acepta esos valores; `MatugenPalette.qml` lee el archivo
  del estilo activo; el estilo se persiste en
  `~/.config/caparazon/style.json`.
- `tests/test_second_menu_wiring.py`: la categoría `configs` está en la lista
  del raíl, con su `glyph`, y su rama existe en el `Loader`.
- `tests/test_category_rail_contrast.py`: el glifo del raíl sigue el mismo
  tinte que el icono.
- Suite completa del repo + ruff + basedpyright, como en el resto del trabajo.

### Prueba en vivo

1. `./install.sh` con los dos repos actualizados.
2. `accent-theme doctor` → las tres integraciones correctas.
3. Abrir el submenú → **Configs de la shell** → cambiar a OLED → la shell se
   repinta en negro al instante.
4. Cambiar a Perla → la shell se repinta en blanco perla.
5. Cambiar el **color de énfasis de KDE** → en menos de un segundo las tres
   paletas se regeneran y la shell (con el estilo elegido) sigue al acento
   nuevo. `~/.cache/caparazon/colors-oled.json` debe tener el acento nuevo,
   más saturado.
6. Volver a Material → la shell vuelve al aspecto de siempre.

### Documentación

- `README.md` de la shell: sección nueva **Estilos de color** con los tres
  estilos, el archivo donde se guarda la elección y cómo se regeneran las
  paletas al cambiar el acento.
- `README.md` y `GUIA.md` del motor: la clave opcional `saturation` en los
  descriptores, con un ejemplo (el de OLED) y el aviso de que un motor viejo
  rechaza la clave.

### Publicación en GitHub

- `caparazon-shell`: los cambios se commitean en la rama en la que está el
  trabajo (`feature/dock-inteligente`) y se sube.
- `accent-theme`: el motor está en `main`. El cambio va en una rama propia
  (`feature/caparazon-styles`) y se sube; el merge a `main` lo decide el
  usuario.

## Fuera de alcance

- **Más opciones dentro de la categoría**: la categoría crecerá (tamaño de la
  barra, animaciones, etc.). Hoy sólo el estilo de color.
- **Que la categoría sea configurable por el usuario**: el raíl es fijo, como
  las demás categorías.
- **Un tema por app o por ventana**: el estilo es de la shell entera.
- **Mover los hex fijos a tokens**: se decide dejarlos como están (§4.3).
- **Que el motor genere esquemas de matugen distintos** (`scheme-vibrant`):
  descartado (§Enfoques 3).

## Riesgos

- **El boost satura también los tonos bajos**: los acentos de OLED salen de
  matugen en modo oscuro, así que `fgPrimary` y `errorContainer` (tonos 20-30)
  también se saturan. Sobre negro siguen siendo legibles, pero se revisan en
  la prueba en vivo.
- **La clave `saturation` cambia el formato del descriptor**: si hay
  descriptores a mano en `~/.config/accent-theme/templates.d/` con esa clave
  antes de que el motor la entienda, el `doctor` fallará con un error de
  clave desconocida. Se avisa en el README del motor.
- **El gris con tinte se vuelve de color**: si alguien cambia un `#08080B` de
  la plantilla OLED por un gris azulado, el boost lo tiñe. La plantilla usa
  grises neutros a propósito y el test del motor cubre que los neutros no
  cambian.
- **Perla invierte la legibilidad**: todo lo que use `Theme.text` sobre
  superficies claras queda correcto, pero un componente que pinte texto
  claro sobre `Theme.surface` sin pasar por tokens se vería mal. La revisión
  de hex fijos (§4.3) cubre los casos conocidos; la prueba en vivo es la que
  lo detecta.
