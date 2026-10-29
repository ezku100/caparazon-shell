//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import "modules/bar"
import "modules/appmenu"
import "modules/dock"
import "modules/icons"

// Caparazón — punto de entrada.
// Una barra por pantalla (Quickshell.screens).
ShellRoot {
    id: shellRoot

    // Watcher de la ventana activa: un solo journalctl para todas las barras.
    ActiveWindowService {
        id: activeWindowService
    }

    // Arranca (si hace falta) el puente KWin que publica escritorios ocupados.
    Process {
        id: desktopBridge
        running: true
        command: ["bash", Quickshell.env("HOME") + "/.local/bin/ezku-desktops-bootstrap.sh"]
    }

    // Muestreo de CPU/RAM: una sola instancia para todas las barras.
    ResourceMonitorService {
        id: resourceService
    }

    // Gestor de escritorios virtuales: un solo dbus-monitor para todas las barras.
    WorkspacesService {
        id: workspacesSvc
    }

    // Historial de portapapeles: un solo watcher para toda la shell.
    ClipboardHistoryService {
        id: clipboardHistoryService
    }

    // Vigilante del tema de iconos: reinicia la shell cuando KDE cambia de
    // tema, porque el proceso lee el tema una sola vez al arrancar.
    IconThemeWatcher {
        id: iconThemeWatcher
    }

    // Servidor de notificaciones: una sola instancia para toda la shell.
    // Las barras sólo consumen el modelo; así no se pelea el bus D-Bus.
    NotificationServer {
        id: notifServer
        keepOnReload: true
        bodySupported: true
        imageSupported: true

        onNotification: function(notification) {
            // El chip muestra una sola notificación: al llegar una nueva,
            // cerramos las anteriores para que no reaparezcan al expirar.
            const old = notifServer.trackedNotifications.values.slice();
            for (const item of old)
                item.dismiss();

            // Mantenerla en trackedNotifications mientras esté viva.
            notification.tracked = true;
        }
    }

    // Historial de notificaciones para el menú secundario: el servidor sólo
    // conserva la última (el chip cierra las anteriores), así que aquí se
    // guardan las más recientes, de la más nueva a la más vieja.
    ListModel {
        id: notificationHistoryModel
    }

    Connections {
        target: notifServer
        function onNotification(notification) {
            notificationHistoryModel.insert(0, {
                appName: String(notification.appName || ""),
                summary: String(notification.summary || ""),
                body: String(notification.body || ""),
                appIcon: String(notification.appIcon || ""),
                stamp: Date.now()
            });
            while (notificationHistoryModel.count > 30)
                notificationHistoryModel.remove(notificationHistoryModel.count - 1);
        }
    }

    // Estado global del menú de energía: una sola capa para todas las
    // pantallas, pero los botones sólo se dibujan en la pantalla activa.
    property QtObject powerMenuState: QtObject {
        property bool opened: false
        property bool closing: false
        property var activeScreen: null

        function open(screen) {
            activeScreen = screen;
            closing = false;
            opened = true;
        }

        function close() {
            if (!opened) return;
            opened = false;
            closing = true;
        }

        function finishClose() {
            closing = false;
            activeScreen = null;
        }
    }

    // Estado global del menú de aplicaciones. Sólo hay una tarjeta, en la
    // pantalla cuya barra lo abrió.
    property QtObject appMenuState: QtObject {
        property bool opened: false
        property bool closing: false
        property var activeScreen: null
        // Última pantalla donde se abrió; el atajo de teclado la reutiliza.
        property var lastScreen: null
        property string mode: "apps"
        property string category: "all"

        function open(screen) {
            if (secondMenuState.opened)
                secondMenuState.close();
            activeScreen = screen;
            lastScreen = screen;
            closing = false;
            mode = "apps";
            category = "all";
            opened = true;
        }

        function close() {
            if (!opened)
                return;
            opened = false;
            closing = true;
        }

        function finishClose() {
            closing = false;
            activeScreen = null;
        }
    }

    // Estado global del menú secundario (calendario). Es independiente del
    // de apps: abrir uno cierra al otro.
    property QtObject secondMenuState: QtObject {
        property bool opened: false
        property bool closing: false
        property var activeScreen: null
        property var lastScreen: null
        property string category: "calendario"

        function open(screen) {
            if (appMenuState.opened)
                appMenuState.close();
            activeScreen = screen;
            lastScreen = screen;
            closing = false;
            opened = true;
        }

        function close() {
            if (!opened)
                return;
            opened = false;
            closing = true;
        }

        function finishClose() {
            closing = false;
            activeScreen = null;
        }
    }

    // Pantalla donde abre el menú cuando se invoca por teclado: la última en
    // la que se abrió (si sigue conectada) o, si no, la primera.
    function appMenuScreen() {
        const last = shellRoot.appMenuState.lastScreen;
        for (let i = 0; i < Quickshell.screens.length; ++i) {
            if (Quickshell.screens[i] === last)
                return last;
        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    // Pantalla donde abre el menú secundario por teclado.
    function secondMenuScreen() {
        const last = shellRoot.secondMenuState.lastScreen;
        for (let i = 0; i < Quickshell.screens.length; ++i) {
            if (Quickshell.screens[i] === last)
                return last;
        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    // Pantalla cuyo nombre de salida coincide (p. ej. "DP-1"); null si no hay.
    function screenByName(name) {
        for (let i = 0; i < Quickshell.screens.length; ++i) {
            if (Quickshell.screens[i].name === name)
                return Quickshell.screens[i];
        }
        return null;
    }

    // Pregunta a KWin cuál es la pantalla activa (la de la ventana enfocada,
    // o la del cursor si está activada "La pantalla activa sigue al ratón") y
    // abre ahí el menú. busctl responde algo como: s "DP-1"
    Process {
        id: activeOutputQuery
        command: ["busctl", "--user", "call", "org.kde.KWin", "/KWin",
                  "org.kde.KWin", "activeOutputName"]
        stdout: StdioCollector {
            onStreamFinished: {
                const match = /"([^"]*)"/.exec(text);
                const screen = (match && shellRoot.screenByName(match[1]))
                    || shellRoot.appMenuScreen();
                shellRoot.appMenuState.open(screen);
            }
        }
    }

    // Igual que activeOutputQuery, pero para el menú secundario (calendario).
    Process {
        id: secondOutputQuery
        command: ["busctl", "--user", "call", "org.kde.KWin", "/KWin",
                  "org.kde.KWin", "activeOutputName"]
        stdout: StdioCollector {
            onStreamFinished: {
                const match = /"([^"]*)"/.exec(text);
                const screen = (match && shellRoot.screenByName(match[1]))
                    || shellRoot.secondMenuScreen();
                shellRoot.secondMenuState.open(screen);
            }
        }
    }

    // Control por línea de comandos / atajos de KDE:
    //   quickshell -p <ruta> ipc call menu toggle   (también: open, close)
    IpcHandler {
        target: "menu"

        function toggle(): void {
            if (shellRoot.appMenuState.opened)
                shellRoot.appMenuState.close();
            else
                activeOutputQuery.running = true;
        }

        function open(): void {
            if (!shellRoot.appMenuState.opened)
                activeOutputQuery.running = true;
        }

        function close(): void {
            shellRoot.appMenuState.close();
        }
    }

    // Control del menú secundario (calendario).
    IpcHandler {
        target: "menu2"

        function toggle(): void {
            if (shellRoot.secondMenuState.opened)
                shellRoot.secondMenuState.close();
            else
                secondOutputQuery.running = true;
        }

        function open(): void {
            if (!shellRoot.secondMenuState.opened)
                secondOutputQuery.running = true;
        }

        function close(): void {
            shellRoot.secondMenuState.close();
        }
    }

    // Estado global de menús de bandeja: sólo puede haber uno abierto.
    property QtObject trayMenuState: QtObject {
        property var active: null

        function activate(menu) {
            if (active && active !== menu) {
                // Si el activo es un submenú, cerrar su menú raíz; cerrar
                // solo el submenú dejaría el menú del icono anterior abierto.
                const top = typeof active.topMenu === "function"
                    ? active.topMenu()
                    : active;
                if (top !== menu)
                    top.close();
            }
            active = menu;
        }

        function deactivate(menu) {
            if (active === menu)
                active = null;
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: Bar {
            workspacesService: workspacesSvc
            powerMenuState: shellRoot.powerMenuState
            appMenuState: shellRoot.appMenuState
            secondMenuState: shellRoot.secondMenuState
            clipboardHistory: clipboardHistoryService
            notificationHistory: notificationHistoryModel
            trayMenuState: shellRoot.trayMenuState
            notificationServer: notifServer
            activeWindowAppId: activeWindowService.appId
            activeWindowTitle: activeWindowService.title
            cpuUsage: resourceService.cpu
            ramUsage: resourceService.ram
            gpuUsage: resourceService.gpu
            swapUsage: resourceService.swap
            networkUsage: resourceService.network
            powerProfile: resourceService.powerProfile
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: Dock {
            screen: modelData
            activeAppId: activeWindowService.appId
            windowAppIds: activeWindowService.windowAppIds
            trayMenuState: shellRoot.trayMenuState
        }
    }
}
