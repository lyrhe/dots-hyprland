import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    // ── State ─────────────────────────────────────────────────────────────
    property var searchResults: []
    property bool searchRunning: false
    property bool isSearchActive: searchField.text.trim().length > 0

    // ── Playlist folder scanner ───────────────────────────────────────────
    FolderListModel {
        id: playlistModel
        folder: "file:///mnt/NewVolume/Music/playlists"
        nameFilters: ["*.m3u", "*.m3u8", "*.pls"]
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
        caseSensitive: false
    }

    // ── Playlist player ───────────────────────────────────────────────────
    Process {
        id: playlistProcess
        running: false
        onExited: (exitCode) => {
            if (exitCode !== 0)
                console.warn("MpdPlaylists: playlist play failed with code", exitCode)
        }
    }

    function playPlaylist(fileName) {
        const name = fileName.replace(/\.[^.]+$/, "")
        playlistProcess.command = [
            "bash", "-c",
            `mpc clear && mpc load "${name}" && mpc random on && mpc play`
        ]
        playlistProcess.running = true
    }

    // ── Song search ───────────────────────────────────────────────────────
    // Debounce: waits for the user to stop typing before firing the search
    Timer {
        id: searchDebounce
        interval: 350
        repeat: false
        onTriggered: root.doSearch(searchField.text.trim())
    }

    // StdioCollector gathers the full stdout of the process, then fires
    // onStreamFinished when the process exits and closes its pipe.
    Process {
        id: searchProcess
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.searchResults = text.trim().length > 0
                    ? text.trim().split("\n").filter(line => line.trim().length > 0)
                    : []
                root.searchRunning = false
            }
        }

        onExited: (exitCode) => {
            // Guard: if mpc returns non-zero (e.g. no results), clear running flag
            if (exitCode !== 0) {
                root.searchResults = []
                root.searchRunning = false
            }
        }
    }

    function doSearch(query) {
        if (query.length === 0) {
            root.searchResults = []
            root.searchRunning = false
            return
        }
        root.searchRunning = true
        // mpc search any <query> returns file paths relative to the music dir,
        // one per line.  head -100 caps the results to avoid flooding the list.
        const escaped = query.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
        searchProcess.command = [
            "bash", "-c",
            `mpc search any "${escaped}" | head -100`
        ]
        searchProcess.running = true
    }

    // ── Song player ───────────────────────────────────────────────────────
    Process {
        id: songProcess
        running: false
        onExited: (exitCode) => {
            if (exitCode !== 0)
                console.warn("MpdPlaylists: song play failed with code", exitCode)
        }
    }

    function playSong(filePath) {
        const escaped = filePath.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
        songProcess.command = [
            "bash", "-c",
            `mpc clear && mpc add "${escaped}" && mpc play`
        ]
        songProcess.running = true
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
                text: "queue_music"
                iconSize: 20
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                text: Translation.tr("Playlists")
                font.pixelSize: 15
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
                Layout.fillWidth: true
            }

            RippleButton {
                implicitWidth: 28
                implicitHeight: 28
                onClicked: playlistModel.folder = playlistModel.folder

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: 16
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        // ── Search bar ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 36
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                spacing: 6

                MaterialSymbol {
                    text: "search"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: searchField.implicitHeight

                    // Manual placeholder — StyledTextInput wraps TextInput
                    // (not TextField) so it has no placeholderText property
                    StyledText {
                        anchors.fill: parent
                        anchors.leftMargin: 2
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("Search songs…")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: 13
                        visible: searchField.text.length === 0 && !searchField.activeFocus
                    }

                    StyledTextInput {
                        id: searchField
                        anchors.fill: parent
                        color: Appearance.colors.colOnLayer1

                        onTextChanged: {
                            if (text.trim().length === 0) {
                                searchDebounce.stop()
                                root.searchResults = []
                                root.searchRunning = false
                            } else {
                                searchDebounce.restart()
                            }
                        }

                        Keys.onEscapePressed: clear()
                    }
                }

                // Clear button — only visible while there is text
                RippleButton {
                    visible: searchField.text.length > 0
                    implicitWidth: 24
                    implicitHeight: 24
                    onClicked: searchField.clear()

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 14
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        // ── Divider ──────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Appearance.colors.colLayer2
            opacity: 0.5
        }

        // ── Content: switches between playlists and song results ──────────
        // StackLayout only renders the active child, so both lists can
        // declare Layout.fillHeight: true without conflicting.
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.isSearchActive ? 1 : 0

            // ── Page 0: Playlist list ─────────────────────────────────
            Item {
                StyledText {
                    anchors.centerIn: parent
                    visible: playlistModel.count === 0
                             && playlistModel.status === FolderListModel.Ready
                    text: Translation.tr("No playlists found")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: 13
                }

                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: playlistModel.status !== FolderListModel.Ready
                }

                StyledListView {
                    id: playlistView
                    anchors.fill: parent
                    spacing: 4
                    clip: true
                    model: playlistModel

                    delegate: RippleButton {
                        id: playlistDelegate
                        required property string fileName

                        width: playlistView.width
                        implicitHeight: 44

                        onClicked: root.playPlaylist(playlistDelegate.fileName)

                        RowLayout {
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 12; rightMargin: 12
                            }
                            spacing: 10

                            MaterialSymbol {
                                text: "playlist_play"
                                iconSize: 18
                                color: Appearance.colors.colOnLayer1
                                opacity: 0.7
                            }

                            StyledText {
                                text: playlistDelegate.fileName
                                      .replace(/\.[^.]+$/, "")
                                      .replace(/[_-]/g, " ")
                                font.pixelSize: 13
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            MaterialSymbol {
                                text: "play_arrow"
                                iconSize: 16
                                color: Appearance.colors.colPrimary
                                opacity: playlistDelegate.hovered ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }
                        }
                    }
                }
            }

            // ── Page 1: Song search results ───────────────────────────
            Item {
                // Spinner while mpc search is running
                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: root.searchRunning
                }

                // Empty state (search done, nothing found)
                StyledText {
                    anchors.centerIn: parent
                    visible: !root.searchRunning && root.searchResults.length === 0
                    text: Translation.tr("No results")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: 13
                }

                StyledListView {
                    id: songView
                    anchors.fill: parent
                    visible: !root.searchRunning && root.searchResults.length > 0
                    spacing: 4
                    clip: true
                    // model is a plain JS array; delegates receive `modelData`
                    // (the file path string) and `index`
                    model: root.searchResults

                    delegate: RippleButton {
                        id: songDelegate
                        required property string modelData  // full relative file path
                        required property int index

                        // Split "Artist/Album/Song Title.flac" into parts
                        readonly property var pathParts: modelData.split("/")
                        readonly property string songTitle: {
                            const raw = pathParts[pathParts.length - 1]
                            // Strip extension and replace separators with spaces
                            return raw.replace(/\.[^.]+$/, "").replace(/[_-]/g, " ")
                        }
                        // Everything before the filename becomes the subtitle
                        readonly property string songSubtitle: pathParts.length > 1
                            ? pathParts.slice(0, pathParts.length - 1).join(" · ")
                            : ""

                        width: songView.width
                        // Taller rows when a subtitle is present
                        implicitHeight: songSubtitle.length > 0 ? 58 : 44

                        onClicked: root.playSong(modelData)

                        RowLayout {
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 12; rightMargin: 12
                            }
                            spacing: 10

                            MaterialSymbol {
                                text: "music_note"
                                iconSize: 18
                                color: Appearance.colors.colOnLayer1
                                opacity: 0.7
                                Layout.alignment: Qt.AlignVCenter
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                StyledText {
                                    text: songDelegate.songTitle
                                    font.pixelSize: 13
                                    color: Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                StyledText {
                                    visible: songDelegate.songSubtitle.length > 0
                                    text: songDelegate.songSubtitle
                                    font.pixelSize: 11
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            MaterialSymbol {
                                text: "play_arrow"
                                iconSize: 16
                                color: Appearance.colors.colPrimary
                                opacity: songDelegate.hovered ? 1.0 : 0.0
                                Layout.alignment: Qt.AlignVCenter
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }
                        }
                    }
                }
            }
        }
    }
}
