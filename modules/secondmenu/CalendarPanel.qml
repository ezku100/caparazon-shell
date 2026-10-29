import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import "../../theme"
import "../icons"
import "CalendarMath.js" as Cal

// Categoría Calendario del menú secundario: perfil y sesión activa, historial
// de notificaciones a la izquierda, calendario del mes y pronóstico semanal.
Item {
    id: root

    property var notificationHistory: null

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

    function resetToToday() {
        const now = new Date();
        root.viewYear = now.getFullYear();
        root.viewMonth = now.getMonth() + 1;
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

    Column {
        id: layout
        anchors.fill: parent
        spacing: 12

        // ── Cabecera: perfil + actividad, reloj grande ────────────────
        Item {
            id: header
            width: layout.width
            height: 56

            Rectangle {
                id: avatarBox
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 48
                height: 48
                radius: 24
                color: Theme.m3Primary
                clip: true

                Image {
                    id: avatarImage
                    anchors.fill: parent
                    source: profile.avatarSource
                    fillMode: Image.PreserveAspectCrop
                    visible: profile.avatarSource.length > 0 && status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    visible: avatarImage.status !== Image.Ready
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

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.clockLocale.toString(clock.date, "HH:mm")
                color: Theme.text
                font.family: Theme.fontUI
                font.pixelSize: 44
                font.weight: Font.Light
            }
        }

        // ── Cuerpo: notificaciones | calendario ───────────────────────
        Row {
            id: body
            width: layout.width
            height: layout.height - header.height - weekly.height - 2 * layout.spacing
            spacing: 12

            NotificationHistory {
                width: 208
                height: parent.height
                model: root.notificationHistory
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

                                        width: weeksColumn.width / 7
                                        height: 32

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 26
                                            height: 26
                                            radius: 13
                                            color: cellItem.today ? Theme.m3Primary : "transparent"
                                        }

                                        Text {
                                            anchors.centerIn: parent
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
                                text: modelData.max + "° / " + modelData.min + "°"
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
}
