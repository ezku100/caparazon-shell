import Quickshell
import Quickshell.Io
import QtQuick

// Watcher único para toda la shell: evita un journalctl por monitor.
Item {
    id: root
    visible: false

    property string appId: ""
    property string title: ""
    property var windowAppIds: []

    Process {
        id: kwinLoader
        running: false
        command: [
            "bash", "-c",
            // Recargar siempre: si Quickshell se reinicia, el script de KWin
            // sigue cargado pero no vuelve a publicar el estado actual. Al
            // recargarlo, el dock recibe ventanas y app activa de inmediato.
            "if gdbus call --session --dest org.kde.KWin --object-path /Scripting --method org.kde.kwin.Scripting.isScriptLoaded caparazon-active-title 2>/dev/null | grep -q true; then " +
            "gdbus call --session --dest org.kde.KWin --object-path /Scripting --method org.kde.kwin.Scripting.unloadScript caparazon-active-title >/dev/null 2>&1; " +
            "fi; " +
            "gdbus call --session --dest org.kde.KWin --object-path /Scripting --method org.kde.kwin.Scripting.loadScript \"$1\" caparazon-active-title >/dev/null; " +
            "gdbus call --session --dest org.kde.KWin --object-path /Scripting --method org.kde.kwin.Scripting.start >/dev/null",
            "bash",
            Quickshell.shellPath("modules/bar/KWinActiveTitle.js")
        ]
    }

    Process {
        id: journal
        running: true
        command: [
            "journalctl", "--user", "-b", "-f", "-n", "200", "-o", "cat",
            "_COMM=kwin_wayland"
        ]
        stdout: SplitParser {
            onRead: function(line) {
                const activePrefix = "js: CAPARAZON_ACTIVE:";
                const windowsPrefix = "js: CAPARAZON_WINDOWS:";

                if (line.startsWith(activePrefix)) {
                    try {
                        const info = JSON.parse(line.substring(activePrefix.length));
                        root.appId = info.appId || "";
                        root.title = info.title || "";
                    } catch (e) {
                        console.log("caparazon: título de ventana inválido:", line);
                    }
                    return;
                }

                if (!line.startsWith(windowsPrefix))
                    return;

                try {
                    const ids = JSON.parse(line.substring(windowsPrefix.length));
                    root.windowAppIds = Array.isArray(ids) ? ids : [];
                } catch (e) {
                    console.log("caparazon: lista de ventanas inválida:", line);
                }
            }
        }
    }

    // journalctl debe estar escuchando antes de recargar el script de KWin;
    // si no, las líneas que el script publica al cargar se pierden.
    Timer {
        interval: 600
        running: true
        onTriggered: kwinLoader.running = true
    }

    // Respaldo: si tras arrancar aún no llegó ninguna lista de ventanas,
    // se recarga el script una vez más.
    Timer {
        interval: 3000
        running: true
        onTriggered: {
            if (root.windowAppIds.length === 0 && !kwinLoader.running)
                kwinLoader.running = true;
        }
    }
}
