import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

// Place at: modules/ii/sidebarLeft/QuickCapture.qml

Item {
    id: root

    // ── State ─────────────────────────────────────────────────────────────
    property string saveStatus: ""   // "" | "saving" | "saved" | "error"

    readonly property string clippingsDir:
        "/mnt/NewVolume/Obsidian/Multiverse of 郷愁/14. Clippings/"

    // ── Save process ──────────────────────────────────────────────────────
    // Content is passed as sys.argv[1] so no shell escaping is ever needed,
    // regardless of what the user typed (quotes, backslashes, Unicode, etc.).
    Process {
        id: saveProcess
        running: false

        onExited: (exitCode) => {
            if (exitCode === 0) {
                root.saveStatus = "saved"
                textArea.clear()
            } else {
                root.saveStatus = "error"
            }
            statusResetTimer.restart()
        }
    }

    // Reset the status badge after 3 s
    Timer {
        id: statusResetTimer
        interval: 3000
        repeat: false
        onTriggered: root.saveStatus = ""
    }

    function saveCapture() {
        const content = textArea.text.trim()
        if (content.length === 0) return

        const now     = new Date()
        const year    = now.getFullYear()
        const month   = String(now.getMonth() + 1).padStart(2, "0")
        const day     = String(now.getDate()).padStart(2, "0")
        const dateStr = `${year}-${month}-${day}`
        const timeStr = now.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })

        const filePath = root.clippingsDir + dateStr + ".md"

        root.saveStatus = "saving"

        // Python receives:
        //   argv[1] = raw text content
        //   argv[2] = full file path (handles Japanese characters fine)
        //   argv[3] = human-readable timestamp for the header
        saveProcess.command = [
            "python3", "-c",
            `
import sys, os

content   = sys.argv[1]
filepath  = sys.argv[2]
timestamp = sys.argv[3]

os.makedirs(os.path.dirname(filepath), exist_ok=True)

file_exists = os.path.isfile(filepath) and os.path.getsize(filepath) > 0

with open(filepath, "a", encoding="utf-8") as f:
    if file_exists:
        f.write("\\n\\n---\\n\\n")
    f.write(f"*{timestamp}*\\n\\n")
    f.write(content)
    if not content.endswith("\\n"):
        f.write("\\n")
`,
            content,
            filePath,
            timeStr
        ]
        saveProcess.running = true
    }

    // ── UI ────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // ── Header ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: "edit_note"
                iconSize: 20
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                text: Translation.tr("Quick Capture")
                font.pixelSize: 15
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
                Layout.fillWidth: true
            }
        }

        // ── Divider ──────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Appearance.colors.colLayer2
            opacity: 0.5
        }

        // ── Text area ─────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2

            // TextArea is itself a Flickable — no ScrollView wrapper needed.
            // Anchoring directly to the parent Rectangle guarantees the width
            // is always constrained to the layout, with no intermediate
            // unconstrained contentItem to cause overflow.
            TextArea {
                id: textArea
                anchors.fill: parent
                anchors.margins: 8

                background: null
                color: Appearance.colors.colOnLayer1
                placeholderText: Translation.tr("Type or paste something to capture…")
                placeholderTextColor: Appearance.colors.colSubtext

                wrapMode: TextArea.Wrap
                selectByMouse: true
                font.pixelSize: 13
                font.family: Appearance.font.family

                // Attach a scrollbar to the TextArea's internal Flickable
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                // Ctrl+Enter → save
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Return
                            && (event.modifiers & Qt.ControlModifier)) {
                        root.saveCapture()
                        event.accepted = true
                    }
                }
            }
        }

        // ── Footer ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Character count
            StyledText {
                text: textArea.length > 0
                    ? textArea.length + Translation.tr(" chars")
                    : Translation.tr("Ctrl+Enter to save")
                color: Appearance.colors.colSubtext
                font.pixelSize: 11
            }

            Item { Layout.fillWidth: true }

            // Status badge
            Rectangle {
                visible: root.saveStatus !== ""
                radius: Appearance.rounding.full
                implicitWidth: statusRow.implicitWidth + 16
                implicitHeight: 22
                color: root.saveStatus === "saved"  ? Appearance.colors.colPrimary
                     : root.saveStatus === "error"  ? Appearance.colors.colError
                     : Appearance.colors.colLayer2

                Behavior on color { ColorAnimation { duration: 150 } }

                RowLayout {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        text: root.saveStatus === "saved"  ? "check"
                            : root.saveStatus === "error"  ? "error"
                            : "hourglass_top"
                        iconSize: 12
                        color: root.saveStatus === ""
                            ? Appearance.colors.colSubtext
                            : Appearance.colors.colOnPrimary
                    }

                    StyledText {
                        text: root.saveStatus === "saved"  ? Translation.tr("Saved")
                            : root.saveStatus === "error"  ? Translation.tr("Error")
                            : Translation.tr("Saving…")
                        font.pixelSize: 11
                        color: root.saveStatus === ""
                            ? Appearance.colors.colSubtext
                            : Appearance.colors.colOnPrimary
                    }
                }
            }

            // Save button
            RippleButton {
                implicitWidth: 72
                implicitHeight: 32
                enabled: textArea.length > 0 && root.saveStatus !== "saving"
                opacity: enabled ? 1.0 : 0.4
                Behavior on opacity { NumberAnimation { duration: 120 } }

                onClicked: root.saveCapture()

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary
                    opacity: 0.15
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        text: "save"
                        iconSize: 14
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        text: Translation.tr("Save")
                        font.pixelSize: 13
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }
}
