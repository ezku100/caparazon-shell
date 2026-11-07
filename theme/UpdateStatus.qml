pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

/*
  Estado de actualización de la shell.

  Un proceso pregunta cada diez minutos (y veinte segundos después de
  arrancar) si el clon tiene commits nuevos en la rama de origen. La barra
  enseña el aviso y Configs el botón para actualizar. El archivo
  ~/.config/caparazon/update.conf lo escribe install.sh con la ruta del
  clon, la rama y la copia activa de la shell.
*/
Item {
    id: root
    visible: false

    readonly property string configPath:
        Quickshell.env("HOME") + "/.config/caparazon/update.conf"
    readonly property string binDir: Quickshell.env("HOME") + "/.local/bin"
    readonly property string checkScript: binDir + "/caparazon-update-check.sh"
    readonly property string updateScript: binDir + "/caparazon-update.sh"

    property string repo: ""
    property string branch: "main"
    property string shellDir: ""
    property bool loaded: false

    // idle | checking | uptodate | available | offline | norepo | error | updating
    property string state: "idle"
    property int behind: 0
    property bool dirty: false

    readonly property bool pending: root.behind > 0
    readonly property bool available: root.state === "available"
    readonly property bool busy: root.state === "checking" || root.state === "updating"

    function refresh() {
        if (!root.loaded || root.repo === "" || root.state === "updating"
                || checkProcess.running)
            return;
        root.state = "checking";
        checkProcess.running = true;
    }

    function applyCheck(text) {
        const parts = text.trim().split(/\s+/);
        const head = parts[0] || "";
        if (head === "available") {
            root.behind = parseInt(parts[1], 10) || 0;
            root.dirty = parts[2] === "dirty";
            root.state = "available";
        } else if (head === "uptodate") {
            root.behind = 0;
            root.dirty = false;
            root.state = "uptodate";
        } else if (head === "offline") {
            root.state = "offline";
        } else if (head === "norepo") {
            root.state = "norepo";
        } else {
            root.state = "error";
        }
    }

    function startUpdate() {
        if (root.state !== "available" || root.dirty)
            return;
        root.state = "updating";
        updateProcess.command = [
            "systemd-run", "--user", "--collect", "--unit=caparazon-update",
            "bash", root.updateScript, root.repo, root.shellDir, root.branch
        ];
        updateProcess.running = true;
    }

    function startFallback() {
        fallbackProcess.command = [
            "setsid", "--fork", "bash", root.updateScript,
            root.repo, root.shellDir, root.branch
        ];
        fallbackProcess.running = true;
    }

    Timer {
        id: periodic
        interval: 600000
        repeat: true
        running: root.loaded && root.state !== "updating"
        onTriggered: root.refresh()
    }

    Timer {
        id: startup
        interval: 20000
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: updatingTimeout
        interval: 45000
        repeat: false
        running: root.state === "updating"
        onTriggered: {
            if (root.state === "updating")
                root.state = "error";
        }
    }

    Process {
        id: checkProcess
        command: ["bash", root.checkScript, root.repo, root.branch]
        stdout: StdioCollector {
            onStreamFinished: root.applyCheck(text)
        }
        onExited: (exitCode) => {
            if (root.state === "checking")
                root.state = "error";
        }
    }

    Process {
        id: updateProcess
        onExited: (exitCode) => {
            if (exitCode !== 0 && root.state === "updating")
                root.startFallback();
        }
    }

    Process {
        id: fallbackProcess
        onExited: (exitCode) => {
            if (exitCode !== 0 && root.state === "updating")
                root.state = "error";
        }
    }

    FileView {
        id: confFile
        path: root.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoadFailed: root.state = "norepo"

        JsonAdapter {
            id: conf
            property string repo: ""
            property string branch: "main"
            property string shell: ""
        }
    }

    Connections {
        target: confFile
        function onLoaded() {
            if (root.loaded)
                return;

            root.repo = conf.repo;
            root.branch = conf.branch && conf.branch.length > 0
                ? conf.branch
                : "main";
            root.shellDir = conf.shell;
            root.loaded = true;
            startup.start();
        }
    }
}
