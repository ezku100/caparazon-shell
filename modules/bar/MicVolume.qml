import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Volumen del micrófono por defecto. Sólo aparece cuando hay una captura
// activa desde ese micrófono (algún enlace lo está usando).
VolumeChip {
    id: root

    readonly property var source: Pipewire.defaultAudioSource
    readonly property string sourceName: root.source ? root.source.name : ""
    readonly property var links: Pipewire.links ? Pipewire.links.values : []
    readonly property bool micActive: root.sourceName !== ""
        && root.links.some(function(link) {
            // Comparar por nombre evita depender de la identidad del wrapper
            // cuando Pipewire recrea el nodo al cambiar el dispositivo.
            return link.source && link.source.name === root.sourceName;
        })

    // Mantiene los nodos vivos desde el arranque, antes de que el micrófono
    // aparezca como fuente por defecto. Sin esto, la primera evaluación puede
    // quedar en falso hasta una recarga de la configuración.
    PwObjectTracker { objects: Pipewire.nodes.values }

    audioNode: root.source
    microphone: true
    visible: root.micActive
}
