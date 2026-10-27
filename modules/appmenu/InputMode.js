// Estado del selector del menú central de aplicaciones.
//
// El teclado (flechas) y el ratón (hover) controlaban cada uno su propia
// posición y se pisaban: el ratón apagaba el resaltado del teclado con
// cualquier movimiento del puntero y las flechas seguían desde una posición
// distinta a la que señalaba el cursor. Aquí hay un único cursor y se
// recuerda qué dispositivo lo manda: el último que se usa toma el control y
// el otro espera.
//
// El estado es un objeto plano y cada evento devuelve uno nuevo; nunca se
// modifica en sitio.

var POINTER_THRESHOLD = 6;

function initial() {
    return {
        mode: "mouse",
        cursor: 0,
        hovered: -1,
        travel: 0,
        pointerX: 0,
        pointerY: 0,
        pointerSeen: false
    };
}

function transition(state, event) {
    var next = {
        mode: state.mode,
        cursor: state.cursor,
        hovered: state.hovered,
        travel: state.travel,
        pointerX: state.pointerX,
        pointerY: state.pointerY,
        pointerSeen: state.pointerSeen
    };
    if (!event || !event.type)
        return next;

    if (event.type === "pointer")
        return withPointer(next, event);
    if (event.type === "hover")
        return withHover(next, event.index);
    if (event.type === "hoverExit")
        return withoutHover(next, event.index);
    if (event.type === "key" || event.type === "text") {
        next.mode = "keyboard";
        next.travel = 0;
        return next;
    }
    if (event.type === "move") {
        next.mode = "keyboard";
        next.travel = 0;
        next.cursor = movedCursor(
            next.cursor, event.direction, event.columns, event.count);
        return next;
    }
    if (event.type === "open") {
        next.mode = "mouse";
        next.travel = 0;
        next.pointerX = 0;
        next.pointerY = 0;
        next.pointerSeen = false;
        next.cursor = next.hovered >= 0 ? next.hovered : 0;
        return next;
    }
    if (event.type === "reset") {
        next.cursor = 0;
        return next;
    }
    return next;
}

// El recorrido del puntero se acumula y sólo al superar el umbral el ratón
// vuelve a mandar: así el temblor del puntero no roba la selección del
// teclado. La primera posición tras abrir el menú sólo ancla la referencia.
function withPointer(state, event) {
    if (!state.pointerSeen) {
        state.pointerX = event.x;
        state.pointerY = event.y;
        state.pointerSeen = true;
        return state;
    }
    var dx = event.x - state.pointerX;
    var dy = event.y - state.pointerY;
    state.pointerX = event.x;
    state.pointerY = event.y;
    state.travel += Math.sqrt(dx * dx + dy * dy);
    if (state.travel < POINTER_THRESHOLD)
        return state;
    state.travel = 0;
    state.mode = "mouse";
    if (state.hovered >= 0)
        state.cursor = state.hovered;
    return state;
}

// Con el ratón mandando, el cursor sigue a la tarjeta señalada. Con el
// teclado mandando el hover sólo se anota: no mueve nada.
function withHover(state, index) {
    state.hovered = index;
    if (state.mode === "mouse" && index >= 0)
        state.cursor = index;
    return state;
}

function withoutHover(state, index) {
    if (state.hovered === index)
        state.hovered = -1;
    return state;
}

function movedCursor(cursor, direction, columns, count) {
    if (!count || count <= 0)
        return 0;
    var index = Math.max(0, Math.min(cursor, count - 1));
    var step = columns > 0 ? columns : 1;
    if (direction === "left") {
        index = Math.max(0, index - 1);
    } else if (direction === "right") {
        index = Math.min(count - 1, index + 1);
    } else if (direction === "up") {
        if (index - step >= 0)
            index -= step;
    } else if (direction === "down") {
        if (index + step <= count - 1)
            index += step;
        else if (Math.floor(index / step) < Math.floor((count - 1) / step))
            index = count - 1;
    }
    return index;
}
