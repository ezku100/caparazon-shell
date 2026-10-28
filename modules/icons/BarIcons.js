// Nombres de icono de tema para los indicadores de la barra.
//
// Cuatro sitios de la barra dibujaban glifos de Nerd Font: el menu de sesion,
// el chip de audio, el selector de perfil de energia y el boton de encendido.
// Aqui viven las cadenas de nombres de tema que los sustituyen, y los umbrales
// del chip de audio, para poder probarlos con node igual que IconNames.js.
//
// Cada cadena va del nombre mas especifico al mas general y esta ordenada para
// que al menos uno resuelva en cada tema instalado (Tela-dark, Colloid-Dark,
// Reversal-dark, breeze, breeze-dark, Adwaita y Papirus). IconResolver prueba
// por su cuenta las variantes -symbolic, asi que basta el nombre base.
//
// Las funciones devuelven copias: el QML nunca recibe la tabla compartida.

var SESSION = {
    "lock": ["system-lock-screen"],
    "logout": ["system-log-out", "application-exit"],
    "shutdown": ["system-shutdown"],
    "reboot": ["system-reboot"]
};

var POWER_BUTTON = ["system-shutdown", "preferences-system-power"];

var SPEAKER = {
    "muted": ["audio-volume-muted"],
    "low": ["audio-volume-low"],
    "medium": ["audio-volume-medium"],
    "high": ["audio-volume-high"]
};

var MICROPHONE = {
    "on": ["audio-input-microphone", "microphone-sensitivity-medium", "microphone"],
    "muted": ["microphone-sensitivity-muted", "mic-off", "audio-input-microphone"]
};

var POWER_PROFILE = {
    "power-saver": ["power-profile-power-saver-symbolic",
                    "battery-profile-powersave", "battery-low"],
    "balanced": ["power-profile-balanced-symbolic",
                 "battery-profile-balanced", "battery-low"],
    "performance": ["power-profile-performance-symbolic",
                    "battery-profile-performance", "battery-low"]
};

// Umbrales del chip de audio: los mismos que tenia la version con glifos.
var SILENCE_LEVEL = 0.001;
var LOW_LEVEL = 0.40;
var HIGH_LEVEL = 0.75;

// Copia de la lista, para que nadie modifique la tabla por accidente.
function copy(names) {
    return names ? names.slice() : [];
}

// Nombres para una accion del menu de sesion; vacio si la accion no existe.
function sessionNames(action) {
    return copy(SESSION[String(action || "")]);
}

// Nombres del boton de la barra que abre el menu de sesion.
function powerButtonNames() {
    return copy(POWER_BUTTON);
}

// Nombres del perfil de energia; un perfil desconocido se dibuja como
// equilibrado, que es lo que hacia el glifo vacio de antes.
function powerProfileNames(profile) {
    return copy(POWER_PROFILE[String(profile || "")] || POWER_PROFILE["balanced"]);
}

// Nombres del chip de audio. Silenciado manda sobre el nivel; en el altavoz el
// nivel reparte bajo, medio y alto; el microfono solo tiene dos estados.
function volumeNames(muted, level, microphone) {
    var value = typeof level === "number" && isFinite(level) ? level : 0;
    var silenced = muted === true || value <= SILENCE_LEVEL;

    if (microphone === true)
        return copy(silenced ? MICROPHONE["muted"] : MICROPHONE["on"]);

    if (silenced)
        return copy(SPEAKER["muted"]);
    if (value < LOW_LEVEL)
        return copy(SPEAKER["low"]);
    if (value < HIGH_LEVEL)
        return copy(SPEAKER["medium"]);
    return copy(SPEAKER["high"]);
}
