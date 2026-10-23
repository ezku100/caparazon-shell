//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import "modules/bar"
import "modules/dock"

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
            trayMenuState: shellRoot.trayMenuState
            notificationServer: notifServer
            activeWindowAppId: activeWindowService.appId
            activeWindowTitle: activeWindowService.title
            cpuUsage: resourceService.cpu
            ramUsage: resourceService.ram
            gpuUsage: resourceService.gpu
            swapUsage: resourceService.swap
            networkUsage: resourceService.network
            networkIcon: resourceService.networkIcon
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
