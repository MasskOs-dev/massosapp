import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Dialogs
import QtWebEngine

ApplicationWindow {
    id: win
    width: 1280; height: 800; visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: view ? view.wv.title : "Quantum Browser"
    Material.theme: Theme.dark ? Material.Dark : Material.Light
    Material.accent: Theme.accent
    Material.background: Theme.bg2
    Material.foreground: Theme.text

    property int cur: 0
    property var view: viewsRepeater.count > cur ? viewsRepeater.itemAt(cur) : null
    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property real tabW: Math.max(120, Math.min(210, (width - 200) / Math.max(1, tabsModel.count + 0.3)))
    property string toastText: ""
    property bool chromeVisible: true
    property bool restoringSession: false
    property var privateBrowserProfile: null
    property var pendingCertificateError: null
    property var pendingPermissionRequest: null
    readonly property var searchEngines: ["Google", "DuckDuckGo", "Bing", "Brave Search"]
    property var browserProfile: null

    WebEngineProfilePrototype {
        id: persistentProfilePrototype
        storageName: "QuantumBrowser"
        httpCacheType: WebEngineProfile.MemoryHttpCache
        httpCacheMaximumSize: 48 * 1024 * 1024
        persistentCookiesPolicy: WebEngineProfile.AllowPersistentCookies
        persistentPermissionsPolicy: WebEngineProfile.StoreInMemory
    }
    WebEngineProfilePrototype {
        id: privateProfilePrototype
        httpCacheType: WebEngineProfile.MemoryHttpCache
        httpCacheMaximumSize: 16 * 1024 * 1024
        persistentCookiesPolicy: WebEngineProfile.NoPersistentCookies
        persistentPermissionsPolicy: WebEngineProfile.StoreInMemory
    }

    ListModel { id: tabsModel }
    ListModel { id: bookmarks }
    function newTab(u, privateTab) {
        if (privateTab && !win.ensurePrivateProfile()) {
            win.toast("Private profile unavailable")
            return
        }
        var privateProfileId = privateTab ? 0 : -1
        tabsModel.append({ title: privateTab ? "Private tab" : "New Tab", url: u || "", icon: "", loading: false,
                           privateTab: !!privateTab, privateProfileId: privateProfileId })
        cur = tabsModel.count - 1
                win.scheduleSessionSave()
    }
    function ensurePrivateProfile() {
        if (!privateBrowserProfile) {
            privateBrowserProfile = privateProfilePrototype.instance()
            if (privateBrowserProfile) backend.registerPrivateProfile(privateBrowserProfile)
        }
        return !!privateBrowserProfile
    }
    function closeTab(i) {
        if (tabsModel.count === 1) newTab("", false)
        var privateProfileId = tabsModel.get(i).privateProfileId
        tabsModel.remove(i)
        if (privateProfileId >= 0) {
            var privateTabsRemain = false
            for (var tabIndex = 0; tabIndex < tabsModel.count; tabIndex++) {
                if (tabsModel.get(tabIndex).privateTab) { privateTabsRemain = true; break }
            }
            if (!privateTabsRemain) Qt.callLater(function() { backend.releasePrivateProfile(privateProfileId) })
        }
        if (cur >= tabsModel.count) cur = tabsModel.count - 1
        else if (cur > i) cur--
        win.scheduleSessionSave()
    }
    function go(t) { var u = backend.normalize(t); if (u !== "" && view) view.wv.url = u }
        function restoreSession() {
            var saved
            try { saved = JSON.parse(backend.sessionState) } catch (error) { saved = null }
            if (!saved || !Array.isArray(saved.tabs) || saved.tabs.length === 0) {
                newTab("", false)
                return
            }
            restoringSession = true
            tabsModel.clear()
            for (var i = 0; i < saved.tabs.length; i++) {
                var tab = saved.tabs[i]
                tabsModel.append({ title: tab.title || "Restored tab", url: tab.url || "", icon: "", loading: false,
                                   privateTab: false, privateProfileId: -1 })
            }
            cur = Math.max(0, Math.min(Number(saved.current) || 0, tabsModel.count - 1))
            restoringSession = false
        }
        function scheduleSessionSave() {
            if (!restoringSession && tabsModel.count > 0) sessionSaveTimer.restart()
        }
        function saveSessionNow() {
            sessionSaveTimer.stop()
            var savedTabs = []
            var selected = -1
            for (var i = 0; i < tabsModel.count; i++) {
                var tab = tabsModel.get(i)
                if (tab.privateTab) continue
                if (i === cur) selected = savedTabs.length
                savedTabs.push({ url: tab.url || "", title: tab.title || "New Tab" })
            }
            if (savedTabs.length === 0) savedTabs.push({ url: "", title: "New Tab" })
            if (selected < 0) selected = savedTabs.length - 1
            backend.saveSession(JSON.stringify({ tabs: savedTabs, current: selected }), selected)
        }
        function handleCertificateError(error) {
            if (!error.overridable) {
                error.rejectCertificate()
                toast("Blocked an invalid site certificate")
                return
            }
            error.defer()
            pendingCertificateError = error
            certificatePrompt.open()
        }
        function decideCertificate(accept) {
            var error = pendingCertificateError
            pendingCertificateError = null
            if (error) {
                if (accept && error.overridable) error.acceptCertificate()
                else error.rejectCertificate()
            }
            certificatePrompt.close()
        }
        function handlePermissionRequest(permission) {
            if (!permission.isValid) return
            pendingPermissionRequest = permission
            permissionPrompt.open()
        }
        function permissionName(permission) {
            if (!permission) return "this feature"
            switch (permission.permissionType) {
            case WebEnginePermission.MediaAudioCapture: return "your microphone"
            case WebEnginePermission.MediaVideoCapture: return "your camera"
            case WebEnginePermission.MediaAudioVideoCapture: return "your camera and microphone"
            case WebEnginePermission.Geolocation: return "your location"
            case WebEnginePermission.Notifications: return "notifications"
            case WebEnginePermission.DesktopVideoCapture: return "your screen"
            case WebEnginePermission.DesktopAudioVideoCapture: return "your screen and audio"
            case WebEnginePermission.ClipboardReadWrite: return "clipboard access"
            default: return "this feature"
            }
        }
        function decidePermission(grant) {
            var permission = pendingPermissionRequest
            pendingPermissionRequest = null
            if (permission && permission.isValid) {
                if (grant) permission.grant()
                else permission.deny()
            }
            permissionPrompt.close()
        }
    function bmIndex() { var u = view ? view.wv.url.toString() : ""; for (var i = 0; i < bookmarks.count; i++) if (bookmarks.get(i).url === u) return i; return -1 }
    property int bmTick: 0
    readonly property bool isBookmarked: { bmTick; return bmIndex() >= 0 }
    function toggleBookmark() {
        if (!view || view.wv.url.toString() === "") return
        var i = bmIndex()
        if (i >= 0) { bookmarks.remove(i); toast("Bookmark removed") }
        else { bookmarks.append({ title: view.wv.title, url: view.wv.url.toString() }); toast("Bookmarked") }
        bmTick++
    }
    function toast(t) { toastText = t; toastBox.opacity = 1; toastTimer.restart() }
    onCurChanged: scheduleSessionSave()
    onClosing: saveSessionNow()
    onVisibilityChanged: {
        if (view && view.wv.isFullScreen && visibility !== Window.FullScreen)
            view.wv.fullScreenCancelled()
    }
    Component.onCompleted: {
        browserProfile = persistentProfilePrototype.instance()
        if (!browserProfile) { console.error("Unable to create the browser profile"); return }
        backend.registerDefaultProfile(browserProfile)
        Theme.dark = backend.darkMode
        restoreSession()
    }

    TextEdit { id: clip; visible: false }
    Timer { id: sessionSaveTimer; interval: 700; repeat: false; onTriggered: win.saveSessionNow() }
    Shortcut { sequence: "Ctrl+T"; onActivated: { win.newTab("", false); addr.forceActiveFocus() } }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: win.newTab("", true) }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.closeTab(win.cur) }
    Shortcut { sequence: "Ctrl+L"; onActivated: { addr.forceActiveFocus(); addr.selectAll() } }
    Shortcut { sequence: "Ctrl+D"; onActivated: win.toggleBookmark() }
    Shortcut { sequence: "Ctrl+R"; onActivated: win.view.wv.reload() }
    Shortcut { sequence: "Alt+Left"; onActivated: win.view.wv.goBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: win.view.wv.goForward() }
    Shortcut { sequence: "Ctrl+Tab"; onActivated: win.cur = (win.cur + 1) % tabsModel.count }
    Shortcut { sequence: "F11"; onActivated: win.visibility = win.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen }

    component GBtn: Item {
        id: gb
        property string d
        property bool active: true
        property bool raised: false
        property color tint: Theme.text
        property color hoverTint: "transparent"
        signal clicked
        width: 38; height: 38
        opacity: active ? 1 : 0.35
        Rectangle {
            anchors.fill: parent; radius: 12
            color: gm.pressed ? Theme.hover : gm.containsMouse && gb.active ? (gb.hoverTint.a > 0 ? gb.hoverTint : Theme.hover) : gb.raised ? Theme.glassStrong : "transparent"
            scale: gm.pressed ? 0.88 : 1
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        }
        Icon { anchors.centerIn: parent; d: gb.d; color: gb.tint; size: 20
            scale: gm.containsMouse && gb.active ? 1.1 : 1; Behavior on scale { NumberAnimation { duration: 160 } } }
        MouseArea { id: gm; anchors.fill: parent; hoverEnabled: true; enabled: gb.active; onClicked: gb.clicked() }
    }

    component Glass: Rectangle { color: Theme.glass }

    Item {
        id: root
        anchors.fill: parent
        anchors.margins: win.maxed ? 0 : 16

        Rectangle { id: shadowSrc; anchors.fill: parent; radius: frame.radius; visible: false }
        MultiEffect { anchors.fill: shadowSrc; source: shadowSrc; shadowEnabled: !win.maxed; shadowBlur: 1.0; shadowOpacity: 0.4
            shadowVerticalOffset: 10; shadowColor: "#000000"; autoPaddingEnabled: true }

        Rectangle {
            id: frame
            anchors.fill: parent; radius: win.maxed ? 0 : 18
            gradient: Gradient { GradientStop { position: 0; color: Theme.bg1 } GradientStop { position: 1; color: Theme.bg2 } }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 10; anchors.topMargin: 6; spacing: 0

                // ── title bar ──
                Item {
                    Layout.fillWidth: true; Layout.preferredHeight: chromeVisible ? 38 : 0
                    opacity: chromeVisible ? 1 : 0; visible: chromeVisible || opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 180 } }
                    HoverHandler { id: titleHover }
                    DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                    TapHandler { onDoubleTapped: win.visibility = win.visibility === Window.Maximized ? Window.Windowed : Window.Maximized }
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 8; spacing: 10
                        Image { source: "../assets/logo.png"; sourceSize.height: 64; Layout.preferredWidth: 22; Layout.preferredHeight: 22; fillMode: Image.PreserveAspectFit }
                        Text { text: "Quantum Browser"; color: Theme.sub; font.pixelSize: 14 }
                        Item { Layout.fillWidth: true }
                        GBtn { d: Icons.minimize; onClicked: win.showMinimized() }
                        GBtn { d: Icons.maximize; raised: true; onClicked: win.visibility = win.visibility === Window.Maximized ? Window.Windowed : Window.Maximized }
                        GBtn { d: Icons.close; hoverTint: "#e5484d"; onClicked: win.close() }
                    }
                }

                // ── tabs ──
                Item {
                    Layout.fillWidth: true; Layout.preferredHeight: 40; z: 2
                    Row {
                        anchors.fill: parent; anchors.leftMargin: 8; spacing: 0
                        ListView {
                            id: tabStrip
                            orientation: ListView.Horizontal; interactive: false; model: tabsModel
                            width: tabsModel.count * win.tabW; height: parent.height
                            Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                            add: Transition { ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220 }
                                NumberAnimation { property: "scale"; from: 0.75; to: 1; duration: 280; easing.type: Easing.OutBack } } }
                            remove: Transition { ParallelAnimation {
                                NumberAnimation { property: "opacity"; to: 0; duration: 160 }
                                NumberAnimation { property: "scale"; to: 0.75; duration: 160 } } }
                            displaced: Transition { NumberAnimation { property: "x"; duration: 240; easing.type: Easing.OutCubic } }
                            delegate: Item {
                                id: tab
                                width: win.tabW; height: ListView.view.height
                                readonly property bool sel: index === win.cur
                                clip: true
                                Rectangle { // taller than tab so bottom corners are hidden by clip
                                    x: 3; width: parent.width - 6; height: parent.height + 16; radius: 14
                                    color: tab.sel ? Theme.glassStrong : tma.containsMouse ? Theme.hover : Theme.glass
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                }
                                Rectangle { anchors.bottom: parent.bottom; x: 14; height: 2.5; radius: 1.25; color: Theme.accent
                                    width: tab.sel ? parent.width - 28 : 0
                                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } } }
                                MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                    onPressed: m => { rip.rx = m.x; rip.ry = m.y; rAnim.restart() }
                                    onClicked: m => m.button === Qt.MiddleButton ? win.closeTab(index) : win.cur = index }
                                Item { // ripple rings
                                    id: rip; anchors.fill: parent; property real t: 0; property real rx: 0; property real ry: 0
                                    NumberAnimation { id: rAnim; target: rip; property: "t"; from: 0; to: 1; duration: 750; easing.type: Easing.OutCubic }
                                    Repeater { model: 2
                                        Rectangle { property real p: Math.max(0, Math.min(1, rip.t * 1.3 - index * 0.25))
                                            visible: p > 0 && p < 1; width: 10 + p * 70; height: width; radius: width / 2
                                            x: rip.rx - width / 2; y: rip.ry - height / 2; color: "transparent"
                                            border.color: Theme.accent; border.width: 1.5; opacity: (1 - p) * 0.6 } }
                                }
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 10; anchors.bottomMargin: 2; spacing: 8
                                    Item { Layout.preferredWidth: 18; Layout.preferredHeight: 18
                                        Image { anchors.fill: parent; source: model.icon; visible: !model.privateTab && !model.loading && model.icon !== ""; asynchronous: true }
                                        Icon { anchors.centerIn: parent; d: model.privateTab ? Icons.eyeOff : Icons.folder; size: 18; color: model.privateTab ? Theme.accent : Theme.sub; sw: 1.5; visible: !model.loading && (model.privateTab || model.icon === "") }
                                        Rectangle { anchors.fill: parent; radius: 9; color: "transparent"; border.width: 2; border.color: Theme.accent; visible: model.loading
                                            RotationAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: model.loading } } }
                                    Text { Layout.fillWidth: true; text: model.title; elide: Text.ElideRight; color: Theme.text; font.pixelSize: 14 }
                                    Item { Layout.preferredWidth: 22; Layout.preferredHeight: 22
                                        Rectangle { anchors.fill: parent; radius: 11; color: cma.containsMouse ? Theme.hover : "transparent" }
                                        Icon { anchors.centerIn: parent; d: Icons.close; size: 14; color: Theme.sub }
                                        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; onClicked: win.closeTab(index) } }
                                }
                            }
                        }
                        Item { // + tab
                            width: 44; height: parent.height; clip: true
                            Rectangle { x: 3; width: 38; height: parent.height + 16; radius: 14; color: pma.containsMouse ? Theme.hover : Theme.glass
                                Behavior on color { ColorAnimation { duration: 150 } } }
                            Icon { anchors.centerIn: parent; anchors.verticalCenterOffset: -2; d: Icons.plus; size: 18; rotation: pma.containsMouse ? 90 : 0
                                Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutBack } } }
                            MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; onClicked: { win.newTab("", false); addr.forceActiveFocus() } }
                        }
                        Item {
                            width: 42; height: parent.height
                            GBtn { anchors.centerIn: parent; d: Icons.eyeOff; tint: Theme.accent; onClicked: win.newTab("", true) }
                        }
                    }
                }

                // ── toolbar ──
                Glass {
                    Layout.fillWidth: true; Layout.preferredHeight: chromeVisible ? 56 : 0; radius: 16
                    opacity: chromeVisible ? 1 : 0; visible: chromeVisible || opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 180 } }
                    HoverHandler { id: toolbarHover }
                    color: Theme.glassStrong
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 4
                        GBtn { d: Icons.back; active: win.view ? win.view.wv.canGoBack : false; onClicked: win.view.wv.goBack() }
                        GBtn { d: Icons.forward; active: win.view ? win.view.wv.canGoForward : false; onClicked: win.view.wv.goForward() }
                        GBtn { d: Icons.share; onClicked: { clip.text = win.view.wv.url.toString(); clip.selectAll(); clip.copy(); win.toast("Link copied") } }

                        Rectangle {
                            Layout.fillWidth: true; Layout.leftMargin: 8; Layout.rightMargin: 8; Layout.preferredHeight: 40; radius: 20
                            color: Theme.pill
                            Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; size: 19; color: Theme.sub
                                d: win.view && win.view.wv.url.toString().startsWith("https") ? Icons.lock : Icons.search }
                            TextField {
                                id: addr
                                anchors.fill: parent; anchors.leftMargin: 42; anchors.rightMargin: 84
                                background: null; color: Theme.text; font.pixelSize: 14
                                placeholderText: "Search or enter address"; placeholderTextColor: Theme.sub
                                selectByMouse: true; verticalAlignment: TextInput.AlignVCenter
                                onActiveFocusChanged: if (activeFocus) selectAll()
                                onAccepted: { win.go(text); win.view.wv.forceActiveFocus() }
                                Binding on text { when: !addr.activeFocus; value: win.view ? win.view.wv.url.toString() : "" }
                            }
                            Row { anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; spacing: 0
                                Item { width: 34; height: 34
                                    GBtn { anchors.fill: parent; d: Icons.shield; tint: backend.blockTrackers ? Theme.accent : Theme.sub; onClicked: settings.open() }
                                    Rectangle { visible: backend.blocked > 0; x: 22; y: 0; height: 14; width: Math.max(14, bc.width + 6); radius: 7; color: Theme.accent
                                        Text { id: bc; anchors.centerIn: parent; text: backend.blocked; font.pixelSize: 9; font.bold: true; color: Theme.dark ? "#0d1417" : "white" } } }
                                GBtn { width: 34; height: 34; d: win.view && win.view.wv.loading ? Icons.close : Icons.reload
                                    onClicked: win.view.wv.loading ? win.view.wv.stop() : win.view.wv.reload() }
                            }
                        }
                        GBtn { d: Icons.star; tint: win.isBookmarked ? Theme.accent : Theme.text; onClicked: win.toggleBookmark() }
                        GBtn { d: Icons.history; onClicked: historyPop.open() }
                        GBtn { d: Icons.download; onClicked: downloadsPop.open() }
                        GBtn { d: Icons.list; onClicked: bmPop.open() }
                        GBtn { d: Icons.gear; onClicked: settings.open() }
                    }
                    Rectangle { // load progress
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 2; x: 24; height: 3; radius: 1.5
                        width: win.view ? (parent.width - 48) * win.view.wv.loadProgress / 100 : 0
                        opacity: win.view && win.view.wv.loading ? 1 : 0
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#00b4ff" } GradientStop { position: 1; color: "#a020f0" } }
                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 350 } }
                    }
                }

                Item { Layout.preferredHeight: 8 }

                // ── pages ──
                StackLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.leftMargin: 2; Layout.rightMargin: 2; Layout.bottomMargin: 2
                    currentIndex: win.cur
                    Repeater {
                        id: viewsRepeater
                        model: tabsModel
                        delegate: Item {
                            property alias wv: web
                            opacity: StackLayout.isCurrentItem ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 220 } }
                            WebEngineView {
                                id: web
                                anchors.fill: parent
                                profile: model.privateTab ? win.privateBrowserProfile : win.browserProfile
                                backgroundColor: Theme.page
                                settings.javascriptCanOpenWindows: true
                                settings.pluginsEnabled: false
                                settings.fullScreenSupportEnabled: true
                                settings.playbackRequiresUserGesture: false
                                settings.webRTCPublicInterfacesOnly: backend.webRtcProtection
                                settings.autoLoadIconsForPage: false
                                settings.scrollAnimatorEnabled: true
                                lifecycleState: StackLayout.isCurrentItem ? WebEngineView.LifecycleState.Active : WebEngineView.LifecycleState.Discarded
                                Component.onCompleted: if (model.url !== "") web.url = model.url
                                onUrlChanged: {
                                    tabsModel.setProperty(index, "url", url.toString())
                                    if (!model.privateTab) backend.recordVisit(url.toString(), title)
                                    win.scheduleSessionSave()
                                }
                                onTitleChanged: {
                                    var pageTitle = title !== "" ? title : (model.privateTab ? "Private tab" : "New Tab")
                                    tabsModel.setProperty(index, "title", pageTitle)
                                    if (!model.privateTab) backend.recordVisit(url.toString(), pageTitle)
                                }
                                onIconChanged: tabsModel.setProperty(index, "icon", icon.toString())
                                onLoadingChanged: {
                                    tabsModel.setProperty(index, "loading", web.loading)
                                }
                                onCertificateError: error => win.handleCertificateError(error)
                                onNewWindowRequested: r => win.newTab(r.requestedUrl.toString(), model.privateTab)
                                onFullScreenRequested: r => { r.accept(); win.visibility = r.toggleOn ? Window.FullScreen : Window.Windowed }
                                onPermissionRequested: permission => win.handlePermissionRequest(permission)
                            }
                            Rectangle { // start page
                                anchors.fill: parent; radius: 14; color: Theme.page; visible: web.url.toString() === ""
                                ColumnLayout {
                                    anchors.centerIn: parent; spacing: 22
                                    Image { source: "../assets/logo.png"; sourceSize.height: 256; fillMode: Image.PreserveAspectFit
                                        Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 92; Layout.preferredHeight: 92
                                        SequentialAnimation on y { loops: Animation.Infinite
                                            NumberAnimation { to: -8; duration: 1800; easing.type: Easing.InOutSine } NumberAnimation { to: 0; duration: 1800; easing.type: Easing.InOutSine } } }
                                    Text { Layout.alignment: Qt.AlignHCenter; text: "Quantum"; color: Theme.text; font.pixelSize: 34; font.weight: Font.Light; font.letterSpacing: 5 }
                                    Glass { Layout.alignment: Qt.AlignHCenter; Layout.preferredHeight: 52; radius: 26
                                        Layout.preferredWidth: sf.activeFocus ? 580 : 520; color: Theme.pill
                                        Behavior on Layout.preferredWidth { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                                        Icon { x: 20; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; color: Theme.sub }
                                        TextField { id: sf; anchors.fill: parent; anchors.leftMargin: 54; anchors.rightMargin: 20; background: null
                                            placeholderText: "Search privately or type a URL"; placeholderTextColor: Theme.sub
                                            color: Theme.text; font.pixelSize: 16; onAccepted: win.go(text) } }
                                    Row { Layout.alignment: Qt.AlignHCenter; spacing: 14
                                        Repeater {
                                            model: [ { n: "DuckDuckGo", u: "https://duckduckgo.com" }, { n: "Wikipedia", u: "https://wikipedia.org" },
                                                     { n: "GitHub", u: "https://github.com" }, { n: "YouTube", u: "https://youtube.com" } ]
                                            delegate: Glass { width: 118; height: 46; radius: 16; color: qma.containsMouse ? Theme.hover : Theme.glass
                                                scale: qma.containsMouse ? 1.07 : 1
                                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                                                Text { anchors.centerIn: parent; text: modelData.n; color: Theme.text; font.pixelSize: 13 }
                                                MouseArea { id: qma; anchors.fill: parent; hoverEnabled: true; onClicked: win.go(modelData.u) } }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            HoverHandler { onPointChanged: { win.chromeVisible = true; chromeIdleTimer.restart() } }
            Timer {
                id: chromeIdleTimer
                interval: 30000
                running: true
                onTriggered: {
                    if (titleHover.hovered || toolbarHover.hovered) restart()
                    else win.chromeVisible = false
                }
            }

            MouseArea { width: 20; height: 20; anchors.right: parent.right; anchors.bottom: parent.bottom; cursorShape: Qt.SizeFDiagCursor
                onPressed: win.startSystemResize(Qt.RightEdge | Qt.BottomEdge) }

            Glass { id: toastBox; anchors.horizontalCenter: parent.horizontalCenter; radius: 20; height: 40; width: tt.width + 44
                y: opacity > 0 ? 112 : 96; opacity: 0; color: Theme.glassStrong
                Behavior on opacity { NumberAnimation { duration: 250 } }
                Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutBack } }
                Text { id: tt; anchors.centerIn: parent; text: win.toastText; color: Theme.text; font.pixelSize: 13 }
                Timer { id: toastTimer; interval: 1500; onTriggered: toastBox.opacity = 0 } }
        }
    }

    component PopupBg: Rectangle { radius: 18; color: Theme.dark ? "#f21b2428" : "#f7ffffff" }
    component Toggle: RowLayout {
        property alias text: lbl.text
        property alias checked: sw.checked
        signal toggled(bool v)
        Layout.fillWidth: true
        Text { id: lbl; Layout.fillWidth: true; color: Theme.text; font.pixelSize: 13 }
        Switch { id: sw; onToggled: parent.toggled(checked) }
    }

    Popup {
        id: certificatePrompt
        parent: Overlay.overlay; x: (win.width - width) / 2; y: (win.height - height) / 2
        width: Math.min(480, win.width - 32); padding: 22; modal: true; focus: true
        closePolicy: Popup.NoAutoClose
        background: PopupBg {}
        contentItem: ColumnLayout {
            spacing: 14
            Text { text: "Certificate warning"; color: Theme.text; font.pixelSize: 20; font.bold: true }
            Text {
                Layout.fillWidth: true; color: Theme.sub; wrapMode: Text.Wrap
                text: win.pendingCertificateError
                    ? win.pendingCertificateError.description + "\n\n" + win.pendingCertificateError.url.toString()
                    : "The site presented an invalid certificate."
            }
            Text {
                Layout.fillWidth: true; color: Theme.accent; wrapMode: Text.Wrap
                text: "Continuing bypasses certificate validation for this connection only."
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Go back"; onClicked: win.decideCertificate(false) }
                Button {
                    text: "Continue once"
                    visible: win.pendingCertificateError && win.pendingCertificateError.overridable
                    onClicked: win.decideCertificate(true)
                }
            }
        }
    }

    Popup {
        id: permissionPrompt
        parent: Overlay.overlay; x: (win.width - width) / 2; y: (win.height - height) / 2
        width: Math.min(440, win.width - 32); padding: 22; modal: true; focus: true
        closePolicy: Popup.NoAutoClose
        background: PopupBg {}
        contentItem: ColumnLayout {
            spacing: 14
            Text { text: "Site permission"; color: Theme.text; font.pixelSize: 20; font.bold: true }
            Text {
                Layout.fillWidth: true; color: Theme.sub; wrapMode: Text.Wrap
                text: (win.pendingPermissionRequest ? win.pendingPermissionRequest.origin.toString() : "This site")
                    + " wants to use " + win.permissionName(win.pendingPermissionRequest) + "."
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button { text: "Block"; onClicked: win.decidePermission(false) }
                Button { text: "Allow"; onClicked: win.decidePermission(true) }
            }
        }
    }

    Popup {
        id: settings
        parent: Overlay.overlay; x: (win.width - width) / 2; y: (win.height - height) / 2
        width: Math.min(760, win.width - 32); height: Math.min(680, win.height - 32); padding: 0; modal: true; focus: true
        enter: Transition { ParallelAnimation { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180 }
            NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: 240; easing.type: Easing.OutBack } } }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 120 } }
        background: PopupBg {}
        contentItem: ColumnLayout {
            spacing: 0
            RowLayout {
                Layout.fillWidth: true; Layout.leftMargin: 22; Layout.rightMargin: 18; Layout.topMargin: 14
                Layout.preferredHeight: 48
                ColumnLayout {
                    spacing: 2
                    Text { text: "Settings"; color: Theme.text; font.pixelSize: 19; font.bold: true }
                    Text { text: "Browser preferences"; color: Theme.sub; font.pixelSize: 11 }
                }
                Item { Layout.fillWidth: true }
                GBtn { d: Icons.close; onClicked: settings.close() }
            }
            TabBar {
                id: settingsTabs
                Layout.fillWidth: true; Layout.leftMargin: 16; Layout.rightMargin: 16; Layout.topMargin: 10
                background: Rectangle { radius: 12; color: Theme.glass }
                TabButton { text: "General" }
                TabButton { text: "Privacy" }
                TabButton { text: "Security" }
                TabButton { text: "Extensions" }
            }
            StackLayout {
                currentIndex: settingsTabs.currentIndex
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.leftMargin: 22; Layout.rightMargin: 22; Layout.topMargin: 12; Layout.bottomMargin: 20
                ScrollView {
                    id: generalSettingsScroll
                    clip: true; padding: 16
                    ColumnLayout {
                        width: generalSettingsScroll.availableWidth; spacing: 18
                        Text { text: "General"; color: Theme.text; font.pixelSize: 20; font.bold: true }
                        Text { text: "Search engine"; color: Theme.sub; font.pixelSize: 13 }
                        ComboBox {
                            Layout.fillWidth: true; model: win.searchEngines
                            currentIndex: Math.max(0, win.searchEngines.indexOf(backend.searchEngine))
                            onActivated: backend.searchEngine = currentText
                        }
                        Toggle { text: "Dark appearance"; checked: backend.darkMode
                            onToggled: v => { backend.darkMode = v; Theme.dark = v } }
                        Text {
                            Layout.fillWidth: true; color: Theme.sub; font.pixelSize: 12; wrapMode: Text.Wrap
                            text: "Regular open tabs resume next time. Private tabs and their URLs are never saved."
                        }
                        RowLayout { Layout.fillWidth: true
                            Text { text: "Page zoom"; color: Theme.text; Layout.fillWidth: true }
                            Button { text: "−"; onClicked: if (win.view) win.view.wv.zoomFactor = Math.max(0.3, win.view.wv.zoomFactor - 0.1) }
                            Button { text: "100%"; onClicked: if (win.view) win.view.wv.zoomFactor = 1 }
                            Button { text: "+"; onClicked: if (win.view) win.view.wv.zoomFactor = Math.min(3, win.view.wv.zoomFactor + 0.1) }
                        }
                    }
                }
                ScrollView {
                    id: privacySettingsScroll
                    clip: true; padding: 16
                    ColumnLayout {
                        width: privacySettingsScroll.availableWidth; spacing: 16
                        Text { text: "Privacy"; color: Theme.text; font.pixelSize: 20; font.bold: true }
                        Toggle { text: "Block ads and trackers by default"; checked: backend.blockTrackers
                            onToggled: v => backend.blockTrackers = v }
                        Toggle { text: "Upgrade HTTP navigations to HTTPS"; checked: backend.httpsOnly
                            onToggled: v => backend.httpsOnly = v }
                        Text { text: backend.blocked + " ad and tracker requests blocked this session"; color: Theme.sub; font.pixelSize: 12 }
                        Text { text: "History is kept in memory for this session. Private tabs do not add to it."; color: Theme.sub; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        Button { text: "Clear cache, cookies, and session history"; onClicked: { backend.clearData(); win.toast("Browsing data cleared") } }
                    }
                }
                ScrollView {
                    id: securitySettingsScroll
                    clip: true; padding: 16
                    ColumnLayout {
                        width: securitySettingsScroll.availableWidth; spacing: 16
                        Text { text: "Security"; color: Theme.text; font.pixelSize: 20; font.bold: true }
                        Toggle { text: "Limit WebRTC to public interfaces"; checked: backend.webRtcProtection
                            onToggled: v => backend.webRtcProtection = v }
                        Text { text: "Pop-up windows, plugins, and site permissions are denied by default."; color: Theme.sub; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        Text { text: "Chromium extensions run with the permissions granted by their manifests."; color: Theme.sub; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    }
                }
                ScrollView {
                    id: extensionsSettingsScroll
                    clip: true; padding: 16
                    ColumnLayout {
                        width: extensionsSettingsScroll.availableWidth; spacing: 12
                        Text { text: "Extensions"; color: Theme.text; font.pixelSize: 20; font.bold: true }
                        RowLayout {
                            Layout.fillWidth: true
                            Button { text: "Install AdGuard or another .crx"; onClicked: extensionFileDialog.open() }
                            Button { text: "Load unpacked"; onClicked: extensionFolderDialog.open() }
                        }
                        Text { text: backend.extensionStatus; color: Theme.sub; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        ListView {
                            Layout.fillWidth: true; Layout.preferredHeight: 260; clip: true; model: backend.extensions
                            delegate: RowLayout {
                                width: ListView.view.width; height: 48
                                Text { Layout.fillWidth: true; text: modelData.name; color: Theme.text; elide: Text.ElideRight }
                                Switch { checked: modelData.enabled; onToggled: backend.setExtensionEnabled(modelData.id, checked) }
                                GBtn { d: Icons.trash; onClicked: backend.uninstallExtension(modelData.id) }
                            }
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: extensionFileDialog
        title: "Install Chromium extension"
        nameFilters: ["Chromium extensions (*.crx)"]
        onAccepted: backend.installExtension(selectedFile.toString())
    }
    FolderDialog {
        id: extensionFolderDialog
        title: "Load unpacked Chromium extension"
        onAccepted: backend.installExtension(selectedFolder.toString())
    }

    Popup {
        id: historyPop
        parent: Overlay.overlay; x: (win.width - width) / 2; y: (win.height - height) / 2
        width: Math.min(560, win.width - 32); height: Math.min(620, win.height - 32); padding: 18
        background: PopupBg {}
        contentItem: ColumnLayout {
            RowLayout {
                Text { text: "History"; color: Theme.text; font.pixelSize: 18; font.bold: true; Layout.fillWidth: true }
                GBtn { d: Icons.trash; onClicked: backend.clearHistory() }
                GBtn { d: Icons.close; onClicked: historyPop.close() }
            }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 4; model: backend.history
                delegate: Rectangle {
                    width: ListView.view.width; height: 58; radius: 8
                    color: historyMouse.containsMouse ? Theme.hover : "transparent"
                    Column {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 3
                        Text { width: parent.width; text: modelData.title; color: Theme.text; elide: Text.ElideRight }
                        Text { width: parent.width; text: modelData.url; color: Theme.sub; font.pixelSize: 11; elide: Text.ElideRight }
                    }
                    MouseArea { id: historyMouse; anchors.fill: parent; hoverEnabled: true
                        onClicked: { win.go(modelData.url); historyPop.close() } }
                }
            }
        }
    }

    Popup {
        id: downloadsPop
        parent: Overlay.overlay; x: (win.width - width) / 2; y: (win.height - height) / 2
        width: Math.min(560, win.width - 32); height: Math.min(620, win.height - 32); padding: 18
        background: PopupBg {}
        contentItem: ColumnLayout {
            RowLayout {
                Text { text: "Downloads"; color: Theme.text; font.pixelSize: 18; font.bold: true; Layout.fillWidth: true }
                Button { text: "Open folder"; onClicked: backend.openDownloadsFolder() }
                GBtn { d: Icons.close; onClicked: downloadsPop.close() }
            }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 4; model: backend.downloads
                delegate: RowLayout {
                    width: ListView.view.width; height: 56
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 3
                        Text { Layout.fillWidth: true; text: modelData.name; color: Theme.text; elide: Text.ElideMiddle }
                        Text {
                            Layout.fillWidth: true; color: Theme.sub; font.pixelSize: 11
                            text: modelData.state + (modelData.total > 0 ? " · " + Math.floor(modelData.received * 100 / modelData.total) + "%" : "")
                        }
                    }
                    GBtn { d: Icons.close; active: modelData.state === "Starting" || modelData.state === "Downloading"
                        onClicked: backend.cancelDownload(modelData.id) }
                }
            }
            Text { visible: backend.downloads.length === 0; text: "No downloads this session"; color: Theme.sub; Layout.alignment: Qt.AlignHCenter }
        }
    }

    Popup {
        id: bmPop
        parent: Overlay.overlay; x: win.width - width - 80; y: 118; width: 320; padding: 16
        enter: Transition { ParallelAnimation { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180 }
            NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: 240; easing.type: Easing.OutBack } } }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 120 } }
        background: PopupBg {}
        contentItem: ColumnLayout {
            spacing: 8
            Text { text: "Bookmarks"; color: Theme.text; font.pixelSize: 16; font.bold: true }
            Text { visible: bookmarks.count === 0; text: "Nothing saved yet. Press ☆ or Ctrl+D."; color: Theme.sub; font.pixelSize: 12 }
            ListView { Layout.fillWidth: true; Layout.preferredHeight: Math.min(contentHeight, 260); model: bookmarks; clip: true; spacing: 4
                delegate: Rectangle { width: ListView.view.width; height: 40; radius: 10; color: bma.containsMouse ? Theme.hover : "transparent"
                    Text { anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; verticalAlignment: Text.AlignVCenter
                        text: model.title; elide: Text.ElideRight; color: Theme.text; font.pixelSize: 13 }
                    MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; onClicked: { win.go(model.url); bmPop.close() } } } }
        }
    }
}
