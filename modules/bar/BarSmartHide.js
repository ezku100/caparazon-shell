//
// La barra puede ser dinámica como el dock: oculta hasta que el puntero toca
// el filo del borde donde vive y se aparta al dejarla. El modo anclado la
// deja siempre visible y reservando su franja, como hasta ahora. El modo se
// elige en Configs de Caparazón Shell.
//
// Aquí sólo vive el cálculo: qué estado corresponde a cada situación, dónde
// queda la zona clicable y cuánto espacio reserva la barra. Sin QML, para
// que se pueda comprobar con node.
//
// Las coordenadas son las de la ventana de la barra: a lo ancho ocupa toda
// la pantalla cuando está arriba/abajo, y a lo alto cuando está a un lado.

function stateFor(barAnchored, pointerOnBar) {
    if (barAnchored) {
        return "anchored";
    }
    return pointerOnBar ? "revealed" : "hidden";
}

// Qué borde ocupa y sobre qué eje se extiende.
function edges(metrics) {
    var position = metrics.position || "top";
    return {
        position: position,
        vertical: position === "left" || position === "right",
        left: position === "left",
        right: position === "right",
        top: position === "top",
        bottom: position === "bottom",
    };
}

// Rectángulo de la parte visible que acepta el puntero, relativo a la
// ventana. Oculta deja sólo una franja fina en el filo: es lo que permite
// volver a llamarla sin que la barra tape nada. El cuerpo va pegado al filo
// y el aire de la sombra queda del lado de dentro.
function maskRect(state, metrics) {
    var e = edges(metrics);
    var hot = metrics.hotEdge;
    var thickness = metrics.barThickness;
    var pad = metrics.shadowPad;

    if (state === "hidden") {
        if (e.vertical) {
            return {
                x: e.left ? 0 : metrics.surfaceWidth - hot,
                y: 0,
                width: hot,
                height: metrics.surfaceHeight,
            };
        }
        return {
            x: 0,
            y: e.top ? 0 : metrics.surfaceHeight - hot,
            width: metrics.surfaceWidth,
            height: hot,
        };
    }

    if (e.vertical) {
        return {
            x: e.left ? 0 : metrics.surfaceWidth - thickness,
            y: 0,
            width: thickness,
            height: metrics.surfaceHeight,
        };
    }
    return {
        x: pad,
        y: e.top ? 0 : metrics.surfaceHeight - thickness,
        width: metrics.surfaceWidth - 2 * pad,
        height: thickness,
    };
}

// Franja que el compositor le reserva: sólo en modo anclado. Revelada al
// pasar el ratón no debe empujar las ventanas.
function exclusiveZone(barAnchored, barThickness) {
    return barAnchored ? barThickness : 0;
}
