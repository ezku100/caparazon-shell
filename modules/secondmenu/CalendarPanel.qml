import Quickshell
import Quickshell.Widgets
import QtQuick
import "../../theme"
import "../icons"
import "CalendarMath.js" as Cal

// Categoría Calendario del menú secundario: perfil y sesión activa, historial
// de notificaciones a la izquierda, calendario del mes y pronóstico semanal.
Item {
    id: root

    property var notificationHistory: null

    property string view: "notifications"
    property var selectedDay: root.today()

    signal overlayChanged(bool open)

    readonly property string selectedKey: Cal.dayKey(
        root.selectedDay.year, root.selectedDay.month, root.selectedDay.day)

    signal notificationActivated(string entry)

    readonly property var clockLocale: Qt.locale("es_MX")

    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth() + 1

    readonly property var grid: Cal.monthGrid(root.viewYear, root.viewMonth)
    readonly property string monthLabel: Cal.monthLabel(root.viewYear, root.viewMonth)

    readonly property string activityLabel: session.label.length > 0
        ? (session.systemWide ? "Sistema " : "Activo ") + session.label
        : ""
    readonly property string profileSubtitle:
        root.clockLocale.toString(clock.date, "dddd d 'de' MMMM")
        + (root.activityLabel.length > 0 ? "  ·  " + root.activityLabel : "")

    onViewYearChanged: root.updateRange()
    onViewMonthChanged: root.updateRange()

    function today() {
        const now = new Date();
        return {
            year: now.getFullYear(),
            month: now.getMonth() + 1,
            day: now.getDate()
        };
    }

    function setView(value) {
        if (value !== "events" && value !== "notifications")
            return;
        if (root.view === value)
            return;

        root.view = value;
        settings.setView(value);
    }

    function selectDay(year, month, day) {
        root.selectedDay = { year: year, month: month, day: day };
    }

    function openLinkDialog() {
        linkDialog.opened = true;
        root.overlayChanged(true);
    }

    function updateRange() {
        const first = new Date(root.viewYear, root.viewMonth - 1, 1);
        const last = new Date(root.viewYear, root.viewMonth, 0);
        const from = new Date(first.getFullYear(), first.getMonth() - 1, 1);
        const to = new Date(last.getFullYear(), last.getMonth() + 1, 0);
        calendar.setRange(
            Cal.dayKey(from.getFullYear(), from.getMonth() + 1, from.getDate()),
            Cal.dayKey(to.getFullYear(), to.getMonth() + 1, to.getDate())
        );
    }

    function resetToToday() {
        const now = new Date();
        root.viewYear = now.getFullYear();
        root.viewMonth = now.getMonth() + 1;
        root.selectDay(now.getFullYear(), now.getMonth() + 1, now.getDate());
    }

    function shiftMonth(delta) {
        let month = root.viewMonth + delta;
        let year = root.viewYear;
        while (month < 1) {
            month += 12;
            year -= 1;
        }
        while (month > 12) {
            month -= 12;
            year += 1;
        }
        root.viewMonth = month;
        root.viewYear = year;
        root.selectDay(
            year, month, Math.min(root.selectedDay.day, Cal.monthDays(year, month)));
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    ProfileService {
        id: profile
    }

    SessionService {
        id: session
    }

    WeatherService {
        id: weather
    }

    PanelSettings {
        id: settings
        onLoadedChanged: {
            if (settings.loaded)
                root.view = settings.view;
        }
    }

    CalendarService {
        id: calendar
    }

    Column {
        id: layout
        anchors.fill: parent
        spacing: 12

        // ── Cabecera: perfil + actividad, reloj grande ────────────────
        Item {
            id: header
            width: layout.width
            height: 56

            ClippingRectangle {
                id: avatarBox
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 48
                height: 48
                radius: 24
                color: Theme.m3Primary

                Image {
                    id: avatarImage
                    anchors.fill: parent
                    source: profile.avatarSource
                    fillMode: Image.PreserveAspectCrop
                    visible: profile.avatarSource.length > 0 && status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    visible: profile.avatarSource.length === 0 || avatarImage.status !== Image.Ready
                    text: (profile.userName || "?").charAt(0).toUpperCase()
                    color: Theme.m3OnPrimary
                    font.family: Theme.fontUI
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
            }

            Column {
                anchors.left: avatarBox.right
                anchors.leftMargin: 11
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    text: profile.userName
                    color: Theme.text
                    font.family: Theme.fontUI
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                Text {
                    text: root.profileSubtitle
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 11
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.clockLocale.toString(clock.date, "hh:mm AP")
                    color: Theme.text
                    font.family: Theme.fontUI
                    font.pixelSize: 44
                    font.weight: Font.Light
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: weather.ready
                    text: isNaN(weather.temperature)
                        ? "" : Math.round(weather.temperature) + "°C"
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 20
                    font.weight: Font.Light
                }
            }
        }

        // ── Cuerpo: notificaciones | calendario ───────────────────────
        Row {
            id: body
            width: layout.width
            height: layout.height - header.height - weekly.height - 2 * layout.spacing
            spacing: 12

            Column {
                id: sideColumn
                width: 208
                height: parent.height
                spacing: 6

                Item {
                    id: switchRow
                    width: parent.width
                    height: 24

                    Row {
                        anchors.fill: parent
                        spacing: 4

                        Repeater {
                            model: [
                                { key: "notifications", label: "Notificaciones" },
                                { key: "events", label: "Eventos" }
                            ]

                            delegate: Item {
                                id: viewButton
                                required property var modelData
                                readonly property bool active: root.view === modelData.key
                                width: (switchRow.width - 4) / 2
                                height: switchRow.height

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: viewButton.active
                                        ? Theme.m3Primary
                                        : (viewHover.hovered ? Theme.chipHover : "transparent")
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: viewButton.modelData.label
                                    color: viewButton.active ? Theme.m3OnPrimary : Theme.textDim
                                    font.family: Theme.fontUI
                                    font.pixelSize: 10
                                    font.weight: viewButton.active ? Font.DemiBold : Font.Normal
                                }

                                HoverHandler {
                                    id: viewHover
                                    cursorShape: Qt.PointingHandCursor
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton
                                    onClicked: root.setView(viewButton.modelData.key)
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: root.view === "events" && !calendar.linked
                    text: "Vincula un calendario con el botón G"
                    color: Theme.textDim
                    font.family: Theme.fontUI
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }

                NotificationHistory {
                    width: parent.width
                    height: root.view === "notifications"
                        ? parent.height - switchRow.height - sideColumn.spacing
                        : 0
                    visible: root.view === "notifications"
                    model: root.notificationHistory
                    showTitle: false
                    onNotificationActivated: root.notificationActivated(entry)
                }

                DayEvents {
                    width: parent.width
                    height: root.view === "events"
                        ? parent.height - switchRow.height - sideColumn.spacing
                        : 0
                    visible: root.view === "events"
                    events: calendar.eventsForDay(root.selectedKey)
                }
            }

            Rectangle {
                id: calendarCard
                width: body.width - 220
                height: parent.height
                radius: 16
                color: Theme.chip

                Column {
                    id: inner
                    width: calendarCard.width - 28
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Item {
                        id: monthHeader
                        width: parent.width
                        height: 26

                        Rectangle {
                            id: googleBadge
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            height: 22
                            radius: 11
                            color: "transparent"
                            border.width: 1
                            border.color: calendar.linked ? "#4285F4" : Theme.m3OutlineVariant

                            Text {
                                anchors.centerIn: parent
                                text: "G"
                                color: calendar.linked ? "#4285F4" : Theme.textDim
                                font.family: Theme.fontUI
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.openLinkDialog()
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: root.monthLabel
                            color: Theme.text
                            font.family: Theme.fontUI
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Item {
                            id: prevButton
                            anchors.right: nextButton.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            height: 26

                            Rectangle {
                                anchors.fill: parent
                                radius: 13
                                color: prevHover.hovered ? Theme.chipHover : "transparent"
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                color: Theme.textDim
                                font.family: Theme.fontUI
                                font.pixelSize: 18
                            }

                            HoverHandler {
                                id: prevHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onClicked: root.shiftMonth(-1)
                            }
                        }

                        Item {
                            id: nextButton
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            height: 26

                            Rectangle {
                                anchors.fill: parent
                                radius: 13
                                color: nextHover.hovered ? Theme.chipHover : "transparent"
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "›"
                                color: Theme.textDim
                                font.family: Theme.fontUI
                                font.pixelSize: 18
                            }

                            HoverHandler {
                                id: nextHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onClicked: root.shiftMonth(1)
                            }
                        }
                    }

                    Item {
                        id: weekdayRow
                        width: parent.width
                        height: 16

                        Row {
                            anchors.fill: parent

                            Repeater {
                                model: Cal.WEEKDAY_LABELS

                                delegate: Text {
                                    width: weekdayRow.width / 7
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData
                                    color: Theme.textDim
                                    font.family: Theme.fontUI
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }

                    Column {
                        id: weeksColumn
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: root.grid

                            delegate: Row {
                                width: weeksColumn.width

                                Repeater {
                                    model: modelData

                                    delegate: Item {
                                        id: cellItem
                                        property var cell: modelData
                                        property bool today: cell.current
                                            && Cal.isToday(cell.year, cell.month, cell.day)
                                        property bool selected: Cal.isSameDay(
                                            root.selectedDay,
                                            {
                                                year: cell.year,
                                                month: cell.month,
                                                day: cell.day
                                            })
                                        property var colors: Cal.colorsForDay(
                                            calendar.byDay, cell.year, cell.month,
                                            cell.day, calendar.calendarIds())

                                        width: weeksColumn.width / 7
                                        height: 32

                                        Rectangle {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            anchors.topMargin: 1
                                            width: 22
                                            height: 22
                                            radius: 11
                                            color: cellItem.today ? Theme.m3Primary : "transparent"
                                            border.width: cellItem.selected && !cellItem.today ? 1 : 0
                                            border.color: Theme.m3Primary
                                        }

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            anchors.topMargin: 1
                                            width: 22
                                            height: 22
                                            verticalAlignment: Text.AlignVCenter
                                            horizontalAlignment: Text.AlignHCenter
                                            text: cellItem.cell.day
                                            color: cellItem.today
                                                ? Theme.m3OnPrimary
                                                : (cellItem.cell.current ? Theme.text : Theme.textDim)
                                            opacity: cellItem.cell.current ? 1.0 : 0.45
                                            font.family: Theme.fontUI
                                            font.pixelSize: 12
                                            font.weight: cellItem.today
                                                ? Font.DemiBold : Font.Normal
                                        }

                                        Row {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: 1
                                            spacing: 2
                                            visible: cellItem.colors.length > 0

                                            Repeater {
                                                model: cellItem.colors.length > 3
                                                    ? [Theme.textDim]
                                                    : cellItem.colors

                                                delegate: Rectangle {
                                                    width: 4
                                                    height: 4
                                                    radius: 2
                                                    color: modelData
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: root.selectDay(
                                                cellItem.cell.year,
                                                cellItem.cell.month,
                                                cellItem.cell.day)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Pronóstico de la semana ───────────────────────────────────
        Rectangle {
            id: weekly
            width: layout.width
            height: 78
            radius: 16
            color: Theme.chip

            Row {
                id: weekRow
                anchors.fill: parent
                anchors.margins: 10
                visible: weather.days.length > 0

                Repeater {
                    model: weather.days

                    delegate: Item {
                        width: weekRow.width / 7
                        height: weekRow.height

                        Column {
                            anchors.centerIn: parent
                            spacing: 2

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.weekday
                                color: modelData.today ? Theme.m3Primary : Theme.textDim
                                font.family: Theme.fontUI
                                font.pixelSize: 10
                                font.weight: modelData.today
                                    ? Font.DemiBold : Font.Normal
                            }

                            IconImage {
                                anchors.horizontalCenter: parent.horizontalCenter
                                implicitSize: 22
                                source: IconResolver.firstOf(
                                    [weather.iconFor(modelData.code), "weather-few-clouds"])
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.max + "°C / " + modelData.min + "°C"
                                color: Theme.textDim
                                font.family: Theme.fontUI
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: weather.days.length === 0
                text: "Sin datos del clima"
                color: Theme.textDim
                font.family: Theme.fontUI
                font.pixelSize: 11
            }
        }
    }

    CalendarLinkDialog {
        id: linkDialog
        anchors.fill: parent
        calendars: calendar.calendars
        onChanged: calendar.refresh()
        onClosed: root.overlayChanged(false)
    }

    Component.onCompleted: root.updateRange()
}
