import Quickshell
import Quickshell.Io
import QtQuick

// Clima actual con Open-Meteo (sin API key). weather.sh resuelve coordenadas,
// consulta /forecast y cachea la respuesta 15 min.
Item {
    id: root

    property real temperature: NaN
    property int code: -1
    property bool ready: false
    property var days: []

    readonly property string scriptPath: String(Qt.resolvedUrl("weather.sh"))
        .replace(/^file:\/\//, "")

    readonly property string conditionLabel: root.describe(root.code)
    readonly property string label: (root.ready && !isNaN(root.temperature))
        ? Math.round(root.temperature) + "° " + root.conditionLabel
        : ""
    readonly property string iconName: root.iconFor(root.code)

    // Códigos WMO de Open-Meteo.
    function describe(code) {
        if (code === 0) return "Despejado";
        if (code === 1) return "Mayormente despejado";
        if (code === 2) return "Parcialmente nublado";
        if (code === 3) return "Nublado";
        if (code === 45 || code === 48) return "Niebla";
        if (code >= 51 && code <= 57) return "Llovizna";
        if (code >= 61 && code <= 67) return "Lluvia";
        if (code >= 71 && code <= 77) return "Nieve";
        if (code >= 80 && code <= 82) return "Chubascos";
        if (code === 85 || code === 86) return "Chubascos de nieve";
        if (code >= 95) return "Tormenta";
        return "";
    }

    function iconFor(code) {
        if (code === 0 || code === 1) return "weather-clear";
        if (code === 2) return "weather-few-clouds";
        if (code === 3) return "weather-clouds";
        if (code === 45 || code === 48) return "weather-fog";
        if (code >= 51 && code <= 67) return "weather-showers";
        if (code >= 71 && code <= 86) return "weather-snow";
        if (code >= 95) return "weather-storm";
        return "weather-few-clouds";
    }

    function refresh() {
        proc.running = true;
    }

    function parseDays(data) {
        const daily = data && data.daily ? data.daily : null;
        if (!daily || !daily.time || daily.time.length === 0)
            return [];
        const locale = Qt.locale("es_MX");
        const out = [];
        for (let i = 0; i < daily.time.length; ++i) {
            const date = new Date(daily.time[i] + "T12:00:00");
            out.push({
                date: daily.time[i],
                weekday: locale.toString(date, "ddd"),
                code: Number(daily.weather_code[i]),
                max: Math.round(Number(daily.temperature_2m_max[i])),
                min: Math.round(Number(daily.temperature_2m_min[i])),
                today: i === 0
            });
        }
        return out;
    }

    Process {
        id: proc
        command: ["bash", root.scriptPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = String(text || "").trim();
                if (!raw) {
                    root.ready = false;
                    return;
                }
                try {
                    const data = JSON.parse(raw);
                    const current = data && data.current ? data.current : null;
                    if (!current) {
                        root.ready = false;
                        return;
                    }
                    root.temperature = Number(current.temperature_2m);
                    root.code = Number(current.weather_code);
                    root.ready = !isNaN(root.temperature);
                    root.days = root.parseDays(data);
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

    Component.onCompleted: root.refresh()
}
