// Emojis agrupados para el menú de aplicaciones. Las etiquetas son sólo para
// la búsqueda; la cuadrícula muestra el emoji a tamaño grande.
var groups = [
    {
        name: "Caritas",
        emojis: [
            { char: "😀", name: "sonrisa" },
            { char: "😃", name: "sonrisa ojos abiertos" },
            { char: "😄", name: "sonrisa ojos felices" },
            { char: "😁", name: "sonrisa radiante" },
            { char: "😆", name: "risa" },
            { char: "😅", name: "risa nerviosa" },
            { char: "😂", name: "llorar de risa" },
            { char: "🤣", name: "carcajada" },
            { char: "😊", name: "feliz" },
            { char: "😇", name: "angel" },
            { char: "🙂", name: "tranquilo" },
            { char: "🙃", name: "al revés" },
            { char: "😉", name: "guiño" },
            { char: "😌", name: "aliviado" },
            { char: "😍", name: "enamorado" },
            { char: "🥰", name: "corazones" },
            { char: "😘", name: "beso" },
            { char: "😋", name: "delicioso" },
            { char: "😜", name: "lengua" },
            { char: "🤪", name: "loco" }
        ]
    },
    {
        name: "Gestos",
        emojis: [
            { char: "👋", name: "saludo" },
            { char: "🤚", name: "mano levantada" },
            { char: "🖐️", name: "mano abierta" },
            { char: "✋", name: "alto" },
            { char: "🖖", name: "vulcano" },
            { char: "👌", name: "perfecto" },
            { char: "🤌", name: "pizza" },
            { char: "🤏", name: "poco" },
            { char: "✌️", name: "victoria" },
            { char: "🤞", name: "dedos cruzados" },
            { char: "🤟", name: "te quiero" },
            { char: "🤘", name: "rock" },
            { char: "🤙", name: "llamada" },
            { char: "👈", name: "izquierda" },
            { char: "👉", name: "derecha" },
            { char: "👆", name: "arriba" },
            { char: "👇", name: "abajo" },
            { char: "☝️", name: "índice" },
            { char: "👍", name: "bien" },
            { char: "👎", name: "mal" }
        ]
    },
    {
        name: "Corazones",
        emojis: [
            { char: "❤️", name: "corazón rojo" },
            { char: "🧡", name: "corazón naranja" },
            { char: "💛", name: "corazón amarillo" },
            { char: "💚", name: "corazón verde" },
            { char: "💙", name: "corazón azul" },
            { char: "💜", name: "corazón morado" },
            { char: "🖤", name: "corazón negro" },
            { char: "🤍", name: "corazón blanco" },
            { char: "🤎", name: "corazón café" },
            { char: "💔", name: "corazón roto" },
            { char: "❣️", name: "exclamación corazón" },
            { char: "💕", name: "dos corazones" },
            { char: "💞", name: "corazones girando" },
            { char: "💓", name: "latido" },
            { char: "💗", name: "corazón creciendo" },
            { char: "💖", name: "brillo" },
            { char: "💘", name: "flecha" },
            { char: "💝", name: "regalo" },
            { char: "💟", name: "decoración" },
            { char: "♥️", name: "naipe" }
        ]
    },
    {
        name: "Animales",
        emojis: [
            { char: "🐶", name: "perro" },
            { char: "🐱", name: "gato" },
            { char: "🐭", name: "ratón" },
            { char: "🐹", name: "hámster" },
            { char: "🐰", name: "conejo" },
            { char: "🦊", name: "zorro" },
            { char: "🐻", name: "oso" },
            { char: "🐼", name: "panda" },
            { char: "🐨", name: "koala" },
            { char: "🐯", name: "tigre" },
            { char: "🦁", name: "león" },
            { char: "🐮", name: "vaca" },
            { char: "🐷", name: "cerdo" },
            { char: "🐸", name: "rana" },
            { char: "🐵", name: "mono" },
            { char: "🐔", name: "gallina" },
            { char: "🐧", name: "pingüino" },
            { char: "🐦", name: "pájaro" },
            { char: "🦄", name: "unicornio" },
            { char: "🐝", name: "abeja" }
        ]
    },
    {
        name: "Comida",
        emojis: [
            { char: "🍎", name: "manzana" },
            { char: "🍊", name: "naranja" },
            { char: "🍋", name: "limón" },
            { char: "🍌", name: "plátano" },
            { char: "🍉", name: "sandía" },
            { char: "🍇", name: "uvas" },
            { char: "🍓", name: "fresa" },
            { char: "🍒", name: "cereza" },
            { char: "🍑", name: "durazno" },
            { char: "🥭", name: "mango" },
            { char: "🍍", name: "piña" },
            { char: "🥥", name: "coco" },
            { char: "🥝", name: "kiwi" },
            { char: "🍅", name: "tomate" },
            { char: "🥑", name: "aguacate" },
            { char: "🥦", name: "brócoli" },
            { char: "🍞", name: "pan" },
            { char: "🧀", name: "queso" },
            { char: "🍕", name: "pizza" },
            { char: "🍔", name: "hamburguesa" }
        ]
    },
    {
        name: "Actividades",
        emojis: [
            { char: "⚽", name: "fútbol" },
            { char: "🏀", name: "baloncesto" },
            { char: "🏈", name: "fútbol americano" },
            { char: "⚾", name: "béisbol" },
            { char: "🎾", name: "tenis" },
            { char: "🏐", name: "voleibol" },
            { char: "🎱", name: "billar" },
            { char: "🏓", name: "ping pong" },
            { char: "🏸", name: "bádminton" },
            { char: "🥊", name: "boxeo" },
            { char: "🎯", name: "diana" },
            { char: "🎮", name: "videojuego" },
            { char: "🎲", name: "dado" },
            { char: "🎸", name: "guitarra" },
            { char: "🎹", name: "piano" },
            { char: "🎺", name: "trompeta" },
            { char: "🎨", name: "arte" },
            { char: "🎬", name: "cine" },
            { char: "📚", name: "libros" },
            { char: "🏆", name: "trofeo" }
        ]
    },
    {
        name: "Viajes",
        emojis: [
            { char: "🚗", name: "coche" },
            { char: "🚕", name: "taxi" },
            { char: "🚌", name: "autobús" },
            { char: "🚎", name: "trolebús" },
            { char: "🏎️", name: "carrera" },
            { char: "🚓", name: "policía" },
            { char: "🚑", name: "ambulancia" },
            { char: "🚒", name: "bomberos" },
            { char: "🚲", name: "bicicleta" },
            { char: "🛴", name: "patinete" },
            { char: "🚂", name: "tren" },
            { char: "✈️", name: "avión" },
            { char: "🚀", name: "cohete" },
            { char: "🚁", name: "helicóptero" },
            { char: "⛵", name: "velero" },
            { char: "🚢", name: "barco" },
            { char: "🏠", name: "casa" },
            { char: "🏢", name: "edificio" },
            { char: "🌍", name: "mundo" },
            { char: "🌙", name: "luna" }
        ]
    },
    {
        name: "Objetos",
        emojis: [
            { char: "⌚", name: "reloj" },
            { char: "📱", name: "teléfono" },
            { char: "💻", name: "portátil" },
            { char: "⌨️", name: "teclado" },
            { char: "🖥️", name: "monitor" },
            { char: "🖨️", name: "impresora" },
            { char: "🖱️", name: "ratón" },
            { char: "💡", name: "bombilla" },
            { char: "🔦", name: "linterna" },
            { char: "📷", name: "cámara" },
            { char: "🎥", name: "filmadora" },
            { char: "📞", name: "llamada" },
            { char: "📟", name: "buscapersonas" },
            { char: "📠", name: "fax" },
            { char: "📺", name: "televisión" },
            { char: "📻", name: "radio" },
            { char: "⏰", name: "alarma" },
            { char: "🔋", name: "batería" },
            { char: "🔌", name: "enchufe" },
            { char: "💾", name: "disquete" }
        ]
    },
    {
        name: "Símbolos",
        emojis: [
            { char: "✅", name: "hecho" },
            { char: "❌", name: "equis" },
            { char: "⚠️", name: "advertencia" },
            { char: "❓", name: "pregunta" },
            { char: "❗", name: "exclamación" },
            { char: "💯", name: "cien" },
            { char: "🔥", name: "fuego" },
            { char: "✨", name: "destellos" },
            { char: "⭐", name: "estrella" },
            { char: "🌟", name: "estrella brillante" },
            { char: "💫", name: "mareo" },
            { char: "⚡", name: "rayo" },
            { char: "☀️", name: "sol" },
            { char: "🌈", name: "arcoíris" },
            { char: "☁️", name: "nube" },
            { char: "❄️", name: "copo" },
            { char: "💧", name: "gota" },
            { char: "🎉", name: "fiesta" },
            { char: "🎊", name: "confeti" },
            { char: "🔔", name: "campana" }
        ]
    }
];

function all() {
    var result = [];
    for (var i = 0; i < groups.length; ++i) {
        var group = groups[i];
        for (var j = 0; j < group.emojis.length; ++j) {
            var emoji = group.emojis[j];
            result.push({
                char: emoji.char,
                name: emoji.name,
                group: group.name
            });
        }
    }
    return result;
}

function search(query) {
    var text = String(query || "").trim().toLowerCase();
    var items = all();
    if (!text)
        return items;

    var result = [];
    for (var i = 0; i < items.length; ++i) {
        var item = items[i];
        var haystack = (item.name + " " + item.group + " " + item.char).toLowerCase();
        if (haystack.indexOf(text) !== -1)
            result.push(item);
    }
    return result;
}
