import Quickshell
import Quickshell.Io
import QtQuick

// Eventos de los calendarios iCal vinculados. gcal.py descarga, cachea y
// publica un JSON normalizado; aquí sólo se habla con él.
Item {
    id: root

    property var calendars: []
    property var byDay: ({})
    property var errors: []
    property bool ready: false
    property bool linked: false
    property bool stale: false
    property string rangeFrom: ""
    property string rangeTo: ""

    readonly property string scriptPath: String(Qt.resolvedUrl("gcal.py"))
        .replace(/^file:\/\//, "")

    function refresh() {
        if (root.rangeFrom.length === 0 || root.rangeTo.length === 0)
            return;
        proc.running = true;
    }

    function setRange(from, to) {
        if (from === root.rangeFrom && to === root.rangeTo)
            return;
        root.rangeFrom = from;
        root.rangeTo = to;
        root.refresh();
    }

    function eventsForDay(key) {
        return root.byDay && root.byDay[key] ? root.byDay[key] : [];
    }

    function calendarIds() {
        const ids = [];
        for (let i = 0; i < root.calendars.length; ++i) {
            const item = root.calendars[i];
            if (item.enabled)
                ids.push(item.id);
        }
        return ids;
    }

    Process {
        id: proc
        command: [
            "python3", root.scriptPath, "events",
            "--from", root.rangeFrom,
            "--to", root.rangeTo
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = String(text || "").trim();
                if (!raw) {
                    root.ready = false;
                    return;
                }
                try {
                    const data = JSON.parse(raw);
                    root.calendars = data && data.calendars ? data.calendars : [];
                    root.byDay = data && data.by_day ? data.by_day : ({});
                    root.stale = !!(data && data.stale);
                    root.errors = data && data.errors ? data.errors : [];
                    if (data && data.error)
                        root.errors = [{ id: "", name: "", message: data.error }];
                    root.linked = root.calendarIds().length > 0;
                    root.ready = true;
                } catch (error) {
                    root.ready = false;
                }
            }
        }
    }

    Timer {
        interval: 900000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
