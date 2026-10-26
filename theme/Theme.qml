pragma Singleton
import QtQuick

// Caparazón — tema central. Todo el look sale de aquí.
QtObject {
    id: theme

    // ── Paleta Material 3 desde matugen (fallback en MatugenPalette) ─────
    // Colores 100% opacos: nada de transparencias. Los tokens llevan prefijo
    // m3 porque QML reserva "onXxx" para manejadores de señales.
    readonly property color m3Surface:                 MatugenPalette.surface
    readonly property color m3SurfaceContainerLow:     MatugenPalette.surfaceContainerLow
    readonly property color m3SurfaceContainer:        MatugenPalette.surfaceContainer
    readonly property color m3SurfaceContainerHigh:    MatugenPalette.surfaceContainerHigh
    readonly property color m3SurfaceContainerHighest: MatugenPalette.surfaceContainerHighest
    readonly property color m3OnSurface:               MatugenPalette.fgSurface
    readonly property color m3Primary:                 MatugenPalette.primary
    readonly property color m3OnPrimary:               MatugenPalette.fgPrimary
    readonly property color m3Tertiary:                MatugenPalette.tertiary
    readonly property color m3OnSurfaceVariant:        MatugenPalette.fgSurfaceVariant
    readonly property color m3Outline:                 MatugenPalette.outline
    readonly property color m3OutlineVariant:          MatugenPalette.outlineVariant
    readonly property color m3Error:                   MatugenPalette.error
    readonly property color m3ErrorContainer:          MatugenPalette.errorContainer
    readonly property color m3OnErrorContainer:        MatugenPalette.fgErrorContainer

    // Alias que usan los widgets
    readonly property color surface:  m3SurfaceContainer   // relleno de la barra
    readonly property color text:     m3OnSurface
    readonly property color textDim:  m3OnSurfaceVariant
    readonly property color chip:     m3SurfaceContainerHigh
    readonly property color chipHover: m3SurfaceContainerHighest
    readonly property color hairline: m3OutlineVariant

    // ── Elevación ────────────────────────────────────────────────────────
    // Sombra M3: negra, difusa y proyectada hacia abajo. No es un color de
    // superficie: se aplica con MultiEffect detrás de la barra.
    readonly property color shadowColor:   "#000000"
    readonly property real  shadowOpacity: 0.30
    readonly property real  shadowBlur:    0.45   // 0..1 (MultiEffect)
    readonly property int   shadowOffsetY: 2
    // Aire extra de la ventana para que la sombra no se recorte. No se ve:
    // la ventana es transparente y el mask sólo deja clicable la barra.
    readonly property int   shadowPad:     12

    // ── Glow del escritorio activo ───────────────────────────────────────
    // Halo suave alrededor del kanji enfocado (MultiEffect, sin cápsula).
    readonly property color glowColor:   m3Primary
    readonly property real  glowOpacity: 1.0
    readonly property real  glowBlur:    0.65   // 0..1 (MultiEffect)
    readonly property int   glowMax:     32
    readonly property int   glowPad:     14      // aire para que no se recorte

    // ── Métricas ─────────────────────────────────────────────────────────
    readonly property int barHeight: 40     // alto de la barra visible
    readonly property int dockHeight: 52    // alto del dock visible
    readonly property int radius:    16     // radio inferior (convexo)
    readonly property int radiusTop: 18     // radio superior INVERTIDO (cóncavo): nace del borde
    readonly property int padH:      14     // padding lateral
    // Barra flotante: fracción del ancho del monitor que ocupa.
    // 1.0 = ancho completo; 0.88 = deja aire a los lados.
    readonly property real barWidthFrac: 0.88

    // ── Animación ────────────────────────────────────────────────────────
    readonly property int durFast: 130
    readonly property int dur:     220

    // ── Tipografía ───────────────────────────────────────────────────────
    readonly property string fontUI:   "Noto Sans Display"
    readonly property string fontIcon: "JetBrainsMono Nerd Font"
    readonly property string fontJP:   "Noto Sans CJK JP"
    readonly property int fontPx:      13
}
