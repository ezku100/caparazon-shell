import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Volumen del sink por defecto (Pipewire).
VolumeChip {
    audioNode: Pipewire.defaultAudioSink
}
