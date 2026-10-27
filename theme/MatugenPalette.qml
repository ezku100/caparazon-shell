pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    readonly property string cacheDir: {
        const xdg = Quickshell.env("XDG_CACHE_HOME")
        return (xdg && xdg.length > 0) ? xdg : Quickshell.env("HOME") + "/.cache"
    }

    readonly property color surface: adapter.surface
    readonly property color surfaceContainerLowest: adapter.surfaceContainerLowest
    readonly property color surfaceContainerLow: adapter.surfaceContainerLow
    readonly property color surfaceContainer: adapter.surfaceContainer
    readonly property color surfaceContainerHigh: adapter.surfaceContainerHigh
    readonly property color surfaceContainerHighest: adapter.surfaceContainerHighest
    readonly property color fgSurface: adapter.fgSurface
    readonly property color fgSurfaceVariant: adapter.fgSurfaceVariant
    readonly property color outline: adapter.outline
    readonly property color outlineVariant: adapter.outlineVariant
    readonly property color primary: adapter.primary
    readonly property color fgPrimary: adapter.fgPrimary
    readonly property color secondary: adapter.secondary
    readonly property color tertiary: adapter.tertiary
    readonly property color error: adapter.error
    readonly property color errorContainer: adapter.errorContainer
    readonly property color fgErrorContainer: adapter.fgErrorContainer

    FileView {
        path: root.cacheDir + "/caparazon/colors.json"
        watchChanges: true
        printErrors: true
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property string surface: "#141218"
            property string surfaceContainerLowest: "#0f0d13"
            property string surfaceContainerLow: "#1d1b20"
            property string surfaceContainer: "#211f26"
            property string surfaceContainerHigh: "#2b2930"
            property string surfaceContainerHighest: "#36343b"
            property string fgSurface: "#e6e0e9"
            property string fgSurfaceVariant: "#cac4d0"
            property string outline: "#938f99"
            property string outlineVariant: "#49454f"
            property string primary: "#d0bcff"
            property string fgPrimary: "#381e72"
            property string secondary: "#ccc2dc"
            property string tertiary: "#efb8c8"
            property string error: "#f2b8b5"
            property string errorContainer: "#8c1d18"
            property string fgErrorContainer: "#f9dedc"
        }
    }
}
