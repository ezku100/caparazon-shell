"""Categoría "Monitor del sistema" del menú secundario.

El submenú tenía calendario y música. La nueva categoría muestra un gráfico
grande con selector de métrica (CPU, RAM, GPU, Swap, red y temperatura) y se
abre al pulsar los anillos del monitor en la barra. Cada anillo de la barra
puede apagarse desde un botón propio.
"""

from __future__ import annotations

from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SECOND_MENU = REPOSITORY_ROOT / "modules" / "secondmenu" / "SecondMenu.qml"
SYSTEM_PANEL = REPOSITORY_ROOT / "modules" / "secondmenu" / "SystemMonitorPanel.qml"
RESOURCE_MONITOR = REPOSITORY_ROOT / "modules" / "bar" / "ResourceMonitor.qml"
RESOURCE_RING = REPOSITORY_ROOT / "modules" / "bar" / "ResourceRing.qml"
RESOURCE_SERVICE = REPOSITORY_ROOT / "modules" / "bar" / "ResourceMonitorService.qml"
BAR = REPOSITORY_ROOT / "modules" / "bar" / "Bar.qml"
SHELL = REPOSITORY_ROOT / "shell.qml"


def test_the_second_menu_has_the_system_category() -> None:
    """El raíl del submenú ofrece la categoría del monitor."""
    contents = SECOND_MENU.read_text(encoding="utf-8")

    assert 'key: "sistema"' in contents
    assert 'icon: "utilities-system-monitor"' in contents


def test_the_system_category_loads_its_panel() -> None:
    """Elegir la categoría carga el panel del monitor."""
    contents = SECOND_MENU.read_text(encoding="utf-8")

    assert 'root.category === "sistema"' in contents
    assert "systemComponent" in contents
    assert "SystemMonitorPanel {" in contents


def test_the_panel_shows_the_six_metrics() -> None:
    """El panel muestra CPU, RAM, GPU, Swap, red y temperatura."""
    contents = SYSTEM_PANEL.read_text(encoding="utf-8")

    for label in ("CPU", "RAM", "GPU", "Swap", "Red", "Temp"):
        assert f'label: "{label}"' in contents


def test_the_panel_uses_the_same_card_style_as_the_other_panels() -> None:
    """Tarjetas Theme.chip con radio 16, como calendario y música."""
    contents = SYSTEM_PANEL.read_text(encoding="utf-8")

    assert "radius: 16" in contents
    assert "color: Theme.chip" in contents
    assert "font.family: Theme.fontUI" in contents


def test_the_panel_has_a_metric_selector() -> None:
    """El panel deja elegir qué métrica muestra el gráfico."""
    contents = SYSTEM_PANEL.read_text(encoding="utf-8")

    assert "property int selectedIndex: 0" in contents
    assert "model: root.metrics" in contents
    assert "onClicked: root.selectedIndex = tab.index" in contents


def test_the_panel_draws_a_big_chart() -> None:
    """El gráfico grande se dibuja con el motor de trazado de los anillos."""
    contents = SYSTEM_PANEL.read_text(encoding="utf-8")

    assert "import QtQuick.Shapes" in contents
    assert "PathSvg {" in contents
    assert "areaPath" in contents
    assert "linePath" in contents


def test_the_panel_shows_the_statistics_of_the_window() -> None:
    """Bajo el gráfico van actual, máximo, mínimo y media."""
    contents = SYSTEM_PANEL.read_text(encoding="utf-8")

    for label in ("Actual", "Máx", "Mín", "Media"):
        assert f'label: "{label}"' in contents


def test_the_panel_reads_the_temperature() -> None:
    """La temperatura llega al panel y se muestra en grados."""
    contents = SYSTEM_PANEL.read_text(encoding="utf-8")

    assert "property int temperature: 0" in contents
    assert 'unit: "°C"' in contents
    assert "root.temperature" in contents


def test_the_second_menu_forwards_temperature_and_samples() -> None:
    """El submenú pasa la temperatura y el historial al panel."""
    contents = SECOND_MENU.read_text(encoding="utf-8")

    assert "property int temperature: 0" in contents
    assert "property var metricSamples: []" in contents
    assert "temperature: root.temperature" in contents
    assert "samples: root.metricSamples" in contents


def test_the_service_keeps_the_history_and_the_hidden_meters() -> None:
    """El servicio guarda el historial y qué medidores están apagados."""
    contents = RESOURCE_SERVICE.read_text(encoding="utf-8")

    assert "property int temperature: 0" in contents
    assert "property var samples: []" in contents
    assert "property var hiddenMeters:" in contents
    assert "function pushSample(sample)" in contents
    assert "function toggleMeter(key)" in contents
    assert "function isHidden(key)" in contents
    assert "function restoreMeters()" in contents


def test_the_hidden_meters_survive_a_restart() -> None:
    """Los medidores apagados se guardan en disco y se releen al arrancar."""
    contents = RESOURCE_SERVICE.read_text(encoding="utf-8")

    assert "meters.json" in contents
    assert "FileView {" in contents
    assert "JsonAdapter {" in contents
    assert "property var hidden: []" in contents
    assert "writeAdapter()" in contents
    assert "metersFile.reload()" in contents


def test_the_service_reads_the_temperature_from_the_sampler() -> None:
    """El séptimo campo del script es la temperatura."""
    contents = RESOURCE_SERVICE.read_text(encoding="utf-8")

    assert "fields[6]" in contents
    assert "root.temperature =" in contents


def test_the_bar_hides_the_meters_that_were_switched_off() -> None:
    """Los anillos de la barra se ocultan cuando el panel los apaga."""
    contents = RESOURCE_MONITOR.read_text(encoding="utf-8")

    assert "visible: !root.isHidden(" in contents
    assert "function isHidden(key)" in contents


def test_the_panel_switches_the_bar_meters_on_and_off() -> None:
    """El interruptor de cada medidor vive en la categoría del monitor."""
    contents = SYSTEM_PANEL.read_text(encoding="utf-8")

    assert "property var resources: null" in contents
    assert "function isHidden(key)" in contents
    assert "function toggleMeter(key)" in contents
    assert "resources.toggleMeter(key)" in contents
    assert "model: root.barMeters" in contents
    assert "En la barra" in contents


def test_the_temperature_has_its_own_switch() -> None:
    """La temperatura también se puede apagar desde el panel."""
    contents = SYSTEM_PANEL.read_text(encoding="utf-8")

    assert '{ key: "temp", label: "Temp" }' in contents


def test_the_bar_shows_a_temperature_ring() -> None:
    """La barra tiene un anillo de temperatura en grados."""
    contents = RESOURCE_MONITOR.read_text(encoding="utf-8")

    assert "property int temperature: 0" in contents
    assert 'label: "Temp"' in contents
    assert "value: root.temperature" in contents
    assert 'unit: "°C"' in contents
    assert 'visible: !root.isHidden("temp")' in contents


def test_the_bar_forwards_the_temperature_to_the_ring() -> None:
    """La barra pasa la temperatura del servicio al monitor de anillos."""
    contents = BAR.read_text(encoding="utf-8")

    assert "temperature: bar.resources ? bar.resources.temperature : 0" in contents


def test_the_panel_header_keeps_its_height() -> None:
    """La cabecera lleva altura explícita o colapsa a cero y no se dibuja."""
    contents = SYSTEM_PANEL.read_text(encoding="utf-8")
    header = contents[contents.index("id: header"):contents.index("id: selector")]

    assert "height: 22" in header
    assert "Monitor del sistema" in header


def test_the_metric_tabs_leave_room_inside_the_capsule() -> None:
    """Las pestañas del selector dejan aire arriba y abajo."""
    contents = SYSTEM_PANEL.read_text(encoding="utf-8")
    delegate = contents[
        contents.index("delegate: Rectangle {"):contents.index("MouseArea {")
    ]

    assert "height: 52" in delegate
    assert "height: 46" not in delegate
    assert "spacing: 3" in delegate


def test_the_second_menu_forwards_the_service_to_the_panel() -> None:
    """El submenú pasa el servicio global al panel para los interruptores."""
    contents = SECOND_MENU.read_text(encoding="utf-8")

    assert "property var resources: null" in contents
    assert "resources: root.resources" in contents


def test_the_ring_has_no_button_on_the_bar() -> None:
    """Los anillos de la barra no llevan botón: se controlan desde el panel."""
    contents = RESOURCE_RING.read_text(encoding="utf-8")

    assert "meterKey" not in contents
    assert "hideBadge" not in contents
    assert "toggled" not in contents


def test_the_monitor_in_the_bar_is_clickable() -> None:
    """Los anillos de la barra emiten activated al pulsarlos."""
    contents = RESOURCE_MONITOR.read_text(encoding="utf-8")

    assert "signal activated()" in contents
    assert "onClicked: root.activated()" in contents


def test_clicking_the_monitor_opens_the_system_category() -> None:
    """El monitor de la barra abre el submenú en la categoría del sistema."""
    contents = BAR.read_text(encoding="utf-8")

    assert 'onActivated: bar.openSecondMenu("sistema")' in contents
    assert "function openSecondMenu(category)" in contents
    assert 'secondMenuState.open(bar.screen, category || "calendario")' in contents


def test_the_bar_forwards_the_metrics_to_the_second_menu() -> None:
    """Las métricas llegan de la barra al panel del monitor."""
    contents = BAR.read_text(encoding="utf-8")

    for metric in (
        "cpuUsage",
        "ramUsage",
        "gpuUsage",
        "swapUsage",
        "networkUsage",
    ):
        assert f"{metric}: bar.{metric}" in contents

    assert "temperature: bar.resources ? bar.resources.temperature : 0" in contents
    assert "metricSamples: bar.resources ? bar.resources.samples : []" in contents
    assert "resources: bar.resources" in contents


def test_the_shell_gives_the_service_to_the_bar() -> None:
    """La barra recibe el servicio global para compartir los medidores."""
    contents = SHELL.read_text(encoding="utf-8")

    assert "resources: resourceService" in contents
