// Escenarios del contrato del selector del menú central de aplicaciones.
//
// El selector vive en modules/appmenu/InputMode.js, que QML carga como
// JavaScript. Aquí se ejecuta ese mismo archivo con node para comprobar la
// máquina de estados sin depender del compositor: mismo código, mismos casos.
//
// Salida por stdout: JSON con el resultado de cada escenario.

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repositoryRoot = path.resolve(__dirname, "..", "..");
const modulePath = path.join(repositoryRoot, "modules", "appmenu", "InputMode.js");

let context;
try {
    context = vm.createContext({});
    vm.runInContext(fs.readFileSync(modulePath, "utf8"), context, {
        filename: "InputMode.js",
    });
} catch (error) {
    process.stderr.write(`no se pudo cargar ${modulePath}: ${error.message}\n`);
    process.exit(1);
}

const threshold = context.POINTER_THRESHOLD;
const initial = context.initial;
const transition = context.transition;

function pointer(state, x, y) {
    return transition(state, { type: "pointer", x: x, y: y });
}

function hover(state, index) {
    return transition(state, { type: "hover", index: index });
}

function hoverExit(state, index) {
    return transition(state, { type: "hoverExit", index: index });
}

function keyboard(state) {
    return transition(state, { type: "key" });
}

function typing(state) {
    return transition(state, { type: "text" });
}

function move(state, direction, columns, count) {
    return transition(state, {
        type: "move",
        direction: direction,
        columns: columns,
        count: count,
    });
}

function reset(state) {
    return transition(state, { type: "reset" });
}

function open(state) {
    return transition(state, { type: "open" });
}

// Primer recorrido real del puntero: se toma como referencia la posición
// donde estaba, así que no cuenta como movimiento.
function pointerSample(state, x, y) {
    return pointer(state, x, y);
}

function check(ok, detail) {
    return { ok: ok, detail: detail };
}

function describe(state) {
    return `modo=${state.mode} cursor=${state.cursor} hover=${state.hovered} viaje=${state.travel}`;
}

const cases = [
    {
        id: "initial_state",
        name: "El selector arranca en modo ratón con el cursor en la primera app",
        run: () => initial(),
        expect: (state) =>
            check(
                state.mode === "mouse" &&
                    state.cursor === 0 &&
                    state.hovered === -1,
                describe(state),
            ),
    },
    {
        id: "arrow_keys_activate_keyboard_mode",
        name: "Las flechas activan el modo teclado y mueven el cursor",
        run: () => move(initial(), "down", 3, 9),
        expect: (state) =>
            check(
                state.mode === "keyboard" && state.cursor === 3,
                describe(state),
            ),
    },
    {
        id: "tiny_pointer_jitter_keeps_keyboard_mode",
        name: "El temblor del puntero no roba la selección del teclado",
        run: () => {
            let state = move(initial(), "down", 3, 9);
            state = hover(state, 7);
            state = pointerSample(state, 100, 100);
            state = pointer(state, 101, 100);
            return state;
        },
        expect: (state) =>
            check(
                state.mode === "keyboard" &&
                    state.cursor === 3 &&
                    state.hovered === 7,
                describe(state),
            ),
    },
    {
        id: "real_pointer_movement_returns_control_to_mouse",
        name: "Un recorrido real del puntero devuelve el control al ratón",
        run: () => {
            let state = move(initial(), "down", 3, 9);
            state = hover(state, 7);
            state = pointerSample(state, 0, 0);
            state = pointer(state, threshold + 10, 0);
            return state;
        },
        expect: (state) =>
            check(
                state.mode === "mouse" &&
                    state.cursor === 7 &&
                    state.hovered === 7,
                describe(state),
            ),
    },
    {
        id: "pointer_movement_accumulates_between_events",
        name: "El recorrido del puntero se acumula entre eventos sueltos",
        run: () => {
            const half = threshold / 2;
            let state = keyboard(initial());
            state = pointerSample(state, 0, 0);
            state = pointer(state, half, 0);
            state = pointer(state, half * 2, 0);
            return state;
        },
        expect: (state) => check(state.mode === "mouse", describe(state)),
    },
    {
        id: "first_pointer_sample_only_records_the_position",
        name: "La primera posición del puntero sólo se registra, no cambia el modo",
        run: () => {
            const state = keyboard(initial());
            return pointerSample(state, 500, 500);
        },
        expect: (state) =>
            check(
                state.mode === "keyboard" && state.travel === 0,
                describe(state),
            ),
    },
    {
        id: "hover_moves_cursor_while_mouse_is_active",
        name: "Con el ratón activo el cursor sigue a la tarjeta señalada",
        run: () => {
            let state = hover(initial(), 4);
            state = hover(state, 6);
            return state;
        },
        expect: (state) =>
            check(
                state.mode === "mouse" &&
                    state.cursor === 6 &&
                    state.hovered === 6,
                describe(state),
            ),
    },
    {
        id: "hover_does_not_move_cursor_in_keyboard_mode",
        name: "Con el teclado activo el hover no mueve el cursor",
        run: () => {
            const state = hover(move(initial(), "down", 3, 9), 7);
            return state;
        },
        expect: (state) =>
            check(
                state.mode === "keyboard" &&
                    state.cursor === 3 &&
                    state.hovered === 7,
                describe(state),
            ),
    },
    {
        id: "typing_returns_control_to_keyboard",
        name: "Escribir en el buscador devuelve el control al teclado",
        run: () => typing(hover(initial(), 4)),
        expect: (state) =>
            check(
                state.mode === "keyboard" && state.cursor === 4,
                describe(state),
            ),
    },
    {
        id: "arrows_continue_from_the_hovered_app",
        name: "Las flechas siguen desde la app que señalaba el ratón",
        run: () => move(hover(initial(), 5), "right", 3, 9),
        expect: (state) =>
            check(
                state.mode === "keyboard" && state.cursor === 6,
                describe(state),
            ),
    },
    {
        id: "vertical_moves_jump_one_row",
        name: "Las flechas verticales saltan una fila",
        run: () => {
            let state = move(initial(), "down", 3, 9);
            state = move(state, "up", 3, 9);
            state = move(state, "down", 3, 9);
            return state;
        },
        expect: (state) => check(state.cursor === 3, describe(state)),
    },
    {
        id: "down_from_the_last_row_stays",
        name: "Abajo desde la última fila no mueve el cursor",
        run: () => {
            let state = move(initial(), "down", 3, 9);
            state = move(state, "down", 3, 9);
            state = move(state, "down", 3, 9);
            return state;
        },
        expect: (state) => check(state.cursor === 6, describe(state)),
    },
    {
        id: "down_clamps_to_the_last_item",
        name: "Abajo se queda en la última app cuando la fila está a medias",
        run: () => {
            // Se llega a la app 5 de 8 (segunda fila) y se baja: no cabe
            // una fila entera, así que el cursor cae en la última app.
            let state = initial();
            for (let index = 0; index < 5; index += 1) {
                state = move(state, "right", 3, 8);
            }
            state = move(state, "down", 3, 8);
            return state;
        },
        expect: (state) => check(state.cursor === 7, describe(state)),
    },
    {
        id: "horizontal_moves_stay_inside_the_grid",
        name: "Izquierda y derecha no salen de la lista",
        run: () => {
            let state = move(initial(), "left", 3, 9);
            state = move(state, "left", 3, 9);
            state = move(state, "right", 3, 9);
            return state;
        },
        expect: (state) => check(state.cursor === 1, describe(state)),
    },
    {
        id: "hover_exit_clears_the_hovered_index",
        name: "Salir de una tarjeta quita el índice señalado sin mover el cursor",
        run: () => hoverExit(hover(initial(), 4), 4),
        expect: (state) =>
            check(
                state.hovered === -1 && state.cursor === 4,
                describe(state),
            ),
    },
    {
        id: "reset_returns_cursor_to_first_app",
        name: "Reiniciar devuelve el cursor a la primera app sin cambiar de modo",
        run: () => reset(hover(initial(), 6)),
        expect: (state) =>
            check(
                state.cursor === 0 && state.mode === "mouse",
                describe(state),
            ),
    },
    {
        id: "open_keeps_the_hovered_card",
        name: "Al abrir el menú se conserva la tarjeta que ya está señalada",
        run: () => open(hover(initial(), 7)),
        expect: (state) =>
            check(
                state.mode === "mouse" &&
                    state.cursor === 7 &&
                    state.hovered === 7 &&
                    state.travel === 0,
                describe(state),
            ),
    },
    {
        id: "open_without_hover_starts_at_the_first_app",
        name: "Al abrir el menú sin puntero encima arranca en la primera app",
        run: () => open(initial()),
        expect: (state) =>
            check(
                state.mode === "mouse" &&
                    state.cursor === 0 &&
                    state.hovered === -1,
                describe(state),
            ),
    },
    {
        id: "mouse_mode_keeps_cursor_on_hovered_app",
        name: "Mover el puntero con el ratón activo deja el cursor en la tarjeta señalada",
        run: () => {
            let state = hover(initial(), 3);
            state = pointerSample(state, 0, 0);
            state = pointer(state, threshold + 5, 0);
            return state;
        },
        expect: (state) =>
            check(
                state.mode === "mouse" && state.cursor === 3,
                describe(state),
            ),
    },
];

const results = cases.map((item) => {
    try {
        const outcome = item.expect(item.run());
        return {
            id: item.id,
            name: item.name,
            ok: outcome.ok,
            detail: outcome.detail,
        };
    } catch (error) {
        return {
            id: item.id,
            name: item.name,
            ok: false,
            detail: `error: ${error.message}`,
        };
    }
});

process.stdout.write(`${JSON.stringify({ cases: results }, null, 2)}\n`);
