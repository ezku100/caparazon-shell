// Estados del dock inteligente.
//
// El dock está oculto por defecto y sale al acercar el puntero al borde donde
// vive (inferior, superior, izquierda o derecha); se puede usar encima de
// cualquier ventana y se retira al dejarlo. El modo anclado se elige en
// Configs de Caparazón Shell: visible y reservando su franja, como el dock de
// siempre. Los lados izquierdo y derecho lo convierten en una columna.
//
// Aquí sólo vive el cálculo: qué estado corresponde a cada situación, dónde
// queda la zona clicable y cuánto espacio reserva el dock. Sin QML, para que
// se pueda comprobar con node.
//
// Las coordenadas son las de la ventana del dock: a lo ancho ocupa toda la
// pantalla cuando está arriba/abajo, y a lo alto cuando está en un lado.

function stateFor(dockPinned, pointerOnDock) {
    if (dockPinned) {
        return "anchored";
    }
    return pointerOnDock ? "revealed" : "hidden";
}

// Qué borde ocupa y sobre qué eje se extiende.
function edges(metrics) {
    var position = metrics.position || "bottom";
    var vertical = position === "left" || position === "right";
    return {
        position: position,
        vertical: vertical,
        left: position === "left",
        right: position === "right",
        top: position === "top",
        bottom: position === "bottom",
    };
}

// Posición del dock a lo largo de su eje: centrado en la pantalla.
function alongOffset(metrics) {
    var axis = edges(metrics).vertical ? metrics.surfaceHeight : metrics.surfaceWidth;
    return Math.round((axis - metrics.dockLength) / 2);
}

// Rectángulo de la parte visible del dock (cuerpo o franja sensible),
// relativo a la ventana. El cuerpo se pega al filo y el aire de la sombra
// queda del lado de dentro.
function maskRect(state, metrics) {
    var e = edges(metrics);
    var along = alongOffset(metrics);
    var length = metrics.dockLength;
    var thickness = metrics.dockThickness;
    var hot = metrics.hotEdge;

    if (state === "hidden") {
        if (e.vertical) {
            return {
                x: e.left ? 0 : metrics.surfaceWidth - hot,
                y: along,
                width: hot,
                height: length,
            };
        }
        return {
            x: along,
            y: e.top ? 0 : metrics.surfaceHeight - hot,
            width: length,
            height: hot,
        };
    }

    if (e.vertical) {
        return {
            x: e.left ? 0 : metrics.surfaceWidth - thickness,
            y: along,
            width: thickness,
            height: length,
        };
    }
    return {
        x: along,
        y: e.top ? 0 : metrics.shadowPad,
        width: length,
        height: thickness,
    };
}

// Distancia que recorre el dock para salirse de la pantalla (la misma en los
// cuatro bordes: atraviesa su grosor más el aire de la sombra).
function dockOffset(state, metrics) {
    return state === "hidden"
        ? metrics.dockThickness + metrics.shadowPad
        : 0;
}

// Franja que el compositor le reserva: sólo cuando el dock está anclado.
function exclusiveZone(dockPinned, metrics) {
    return dockPinned ? metrics.dockThickness + metrics.bottomGap : 0;
}
