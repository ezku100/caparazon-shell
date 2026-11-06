// Estados del dock inteligente.
//
// El dock está oculto por defecto y sube al acercar el puntero al borde
// inferior; se puede usar encima de cualquier ventana y se retira al dejarlo.
// El modo anclado se elige en Configs de la shell: visible y reservando su
// franja, como el dock de siempre.
//
// Aquí sólo vive el cálculo: qué estado corresponde a cada situación, dónde
// queda la zona clicable y cuánto espacio reserva el dock. Sin QML, para que
// se pueda comprobar con node.

function stateFor(dockPinned, pointerOnDock) {
    if (dockPinned) {
        return "anchored";
    }
    return pointerOnDock ? "revealed" : "hidden";
}

// La franja que queda al apartar el dock cae dentro del rectángulo del dock
// (58..64 está dentro de 12..64), así que al revelarse no se pierde el ratón.
function maskRect(state, metrics) {
    var x = Math.round((metrics.surfaceWidth - metrics.dockWidth) / 2);
    if (state === "hidden") {
        return {
            x: x,
            y: metrics.surfaceHeight - metrics.hotEdge,
            width: metrics.dockWidth,
            height: metrics.hotEdge,
        };
    }
    return {
        x: x,
        y: metrics.shadowPad,
        width: metrics.dockWidth,
        height: metrics.dockHeight,
    };
}

// Distancia que baja el dock para salirse de la pantalla.
function dockOffset(state, metrics) {
    return state === "hidden" ? metrics.dockHeight + metrics.shadowPad : 0;
}

// Franja que el compositor le reserva: sólo cuando el dock está anclado.
function exclusiveZone(dockPinned, metrics) {
    return dockPinned ? metrics.dockHeight + metrics.bottomGap : 0;
}
