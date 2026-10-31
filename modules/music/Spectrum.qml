import Quickshell
import Quickshell.Io
import QtQuick
import "../../theme"
import "SpectrumMath.js" as SpectrumMath

/*
  Espectro de audio del modo compacto de Música.

  Dibuja las barras que publica el sampler (modules/music/spectrumfeed.py) en
  ~/.cache/caparazon/waves.json. El suavizado y el degradado del tema están
  en SpectrumMath.js, que se puede probar con node.

  El sampler sólo corre mientras `active` es true: en modo normal no gasta
  CPU. `playing` decide si las barras muestran el espectro o decaen a cero.
*/
Item {
    id: root

    // Visible y con sampler en marcha.
    property bool active: false

    // Hay reproducción: si no, las barras decaen en vez de congelarse.
    property bool playing: false

    property int barCount: SpectrumMath.BARS

    // Niveles suavizados del último frame, de 0 a 1.
    property var levels: []

    implicitHeight: 64

    onActiveChanged: {
        if (active) {
            // El propio sampler se guarda de duplicados: si ya hay uno con
            // este datadir, el nuevo se sale solo.
            feed.running = true;
        } else {
            stopSampler();
            root.levels = [];
        }
    }

    function stopSampler() {
        if (feedStop.running)
            return;

        feedStop.running = true;
    }

    // Arranca el sampler de cava.
    Process {
        id: feed
        command: [
            "python3",
            Quickshell.shellPath("modules/music/spectrumfeed.py"),
            Quickshell.env("HOME") + "/.cache/caparazon"
        ]
    }

    // Para el sampler. El patrón con corchetes no coincide con el propio
    // pkill, así que no se mata a sí mismo.
    Process {
        id: feedStop
        command: ["pkill", "-f", "spectrumfeed[.]py"]
    }

    // Los bytes que publica el sampler. La lista es `list<int>` y no
    // `property var` a propósito: con `var` el JsonAdapter entrega una
    // QVariantList y al convertirla a JavaScript Quickshell 0.3.2
    // reventaba (QJSEngine::create) cada vez que recargaba la shell.
    FileView {
        id: waves
        path: Quickshell.env("HOME") + "/.cache/caparazon/waves.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: wavesAdapter
            property list<int> spec: []
        }
    }

    // A ~12 fps, como publica el sampler.
    Timer {
        running: root.active
        interval: 83
        repeat: true
        onTriggered: root.levels = SpectrumMath.nextLevels(
            wavesAdapter.spec, root.levels, root.playing,
            root.barCount, SpectrumMath.FACTOR)
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 3

        Repeater {
            model: root.barCount

            delegate: Rectangle {
                id: bar

                readonly property real level: index < root.levels.length
                    ? root.levels[index]
                    : 0

                width: (parent.width - (root.barCount - 1) * parent.spacing)
                    / root.barCount
                height: Math.max(2, level * parent.height)
                anchors.bottom: parent.bottom
                radius: Math.min(2, width / 2)
                color: SpectrumMath.mixColor(
                    Theme.m3Primary, Theme.m3Tertiary, index, root.barCount)
            }
        }
    }
}
