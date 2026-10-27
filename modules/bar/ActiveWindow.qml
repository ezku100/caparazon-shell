import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"
import "../icons"

// Ventana activa, alimentada por ActiveWindowService.
// Icono de la app (tintado como los de la bandeja) + nombre de la app +
// título de la ventana. Sin separador: el aire entre módulos ya los separa.
Item {
    id: root

    property string appId: ""
    property string title: ""
    property bool compact: false

    readonly property bool isDesktop: root.appId === "plasmashell"

    readonly property var entry: {
        if (!root.appId || root.isDesktop)
            return null;

        const id = root.appId.endsWith(".desktop")
            ? root.appId
            : root.appId + ".desktop";

        return DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(root.appId);
    }

    readonly property string appName: {
        if (root.isDesktop)
            return "Desktop";

        if (root.entry && root.entry.name)
            return displayName(root.entry.name);

        return prettyAppId(root.appId);
    }

    function displayName(name) {
        if (!name)
            return "";

        // Muchos .desktop de Linux ponen el Name en minúsculas
        // ("limusic", "kitty"). Respetamos nombres ya capitalizados.
        if (name === name.toLowerCase())
            return name.charAt(0).toUpperCase() + name.slice(1);

        return name;
    }

    readonly property string iconName: root.isDesktop
        ? "emblem-pika"
        : (root.entry && root.entry.icon ? root.entry.icon : root.appId)

    readonly property string iconSource: root.appId !== ""
        ? IconResolver.source(root.iconName, "application-x-executable")
        : ""

    function prettyAppId(id) {
        if (!id)
            return "";
        let name = id.replace(/\.desktop$/, "").split(".").pop();
        name = name.replace(/[-_]/g, " ");
        return name.replace(/\b\w/g, function(c) { return c.toUpperCase(); });
    }

    implicitWidth: visible ? row.implicitWidth : 0
    implicitHeight: Theme.barHeight
    visible: appId !== "" || title !== ""

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7

        Item {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.appId !== ""
            width: 26
            height: 26

            // Mismo fondo circular que el indicador de perfil de energía.
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.lighter(Theme.chipHover, 1.3)
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: 16
                source: root.iconSource
                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: Theme.m3OnSurfaceVariant
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.compact && root.appName !== ""
            width: Math.min(120, implicitWidth)
            text: root.appName
            color: Theme.text
            font.family: Theme.fontUI
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.isDesktop && root.title !== ""
            width: Math.min(root.compact ? 160 : 260, implicitWidth)
            text: root.title
            color: Theme.textDim
            font.family: Theme.fontUI
            font.pixelSize: 12
            font.weight: Font.Medium
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
