import sys
import json
from pathlib import Path
from urllib.parse import quote_plus

from PySide6.QtCore import QObject, Property, QSettings, QStandardPaths, Signal, Slot, QUrl
from PySide6.QtGui import QDesktopServices, QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWebEngineQuick import QtWebEngineQuick
from PySide6.QtWebEngineCore import QWebEngineUrlRequestInterceptor, QWebEngineUrlRequestInfo
import FeatherIconsQML

TRACKERS = {
    "doubleclick.net", "googlesyndication.com", "google-analytics.com", "googletagmanager.com",
    "googleadservices.com", "adservice.google.com", "facebook.net", "scorecardresearch.com",
    "hotjar.com", "taboola.com", "outbrain.com", "adnxs.com", "criteo.com", "quantserve.com",
    "mixpanel.com", "segment.io", "amplitude.com", "ads-twitter.com", "analytics.tiktok.com",
    "adform.net", "adsrvr.org", "amazon-adsystem.com", "advertising.com", "doubleverify.com",
    "imrworldwide.com", "media.net", "openx.net", "pubmatic.com", "rubiconproject.com",
    "smartadserver.com", "teads.tv", "thetradedesk.com", "yieldmo.com",
}

SEARCH_URLS = {
    "Google": "https://www.google.com/search?q={query}",
    "DuckDuckGo": "https://duckduckgo.com/?q={query}",
    "Bing": "https://www.bing.com/search?q={query}",
    "Brave Search": "https://search.brave.com/search?q={query}",
}

class Backend(QObject):
    blockedChanged = Signal()
    settingsChanged = Signal()
    historyChanged = Signal()
    downloadsChanged = Signal()
    extensionsChanged = Signal()
    extensionStatusChanged = Signal()
    _bump = Signal()

    def __init__(self):
        super().__init__()
        self._settings = QSettings("QuantumBrowser", "QuantumBrowser")
        self._blocked = 0
        self._trackers = bool(self._settings.value("blockTrackers", True))
        self._https = bool(self._settings.value("httpsOnlyV2", False))
        self._web_rtc = bool(self._settings.value("webRtcProtection", True))
        self._dark_mode = bool(self._settings.value("darkMode", True))
        saved_engine = self._settings.value("searchEngineV2", "Google")
        self._search_engine = saved_engine if saved_engine in SEARCH_URLS else "Google"
        self._session_state = str(self._settings.value("sessionState", "") or "")
        self._history = []
        self._downloads = []
        self._download_requests = {}
        self._private_profiles = {}
        self._extension_status = "No extension action yet"
        download_path = QStandardPaths.writableLocation(QStandardPaths.StandardLocation.DownloadLocation)
        self._download_path = Path(download_path or str(Path.home() / "Downloads"))
        self._download_path.mkdir(parents=True, exist_ok=True)
        self._bump.connect(self._inc)
        self.profile = None
        self._extension_manager = None

    def _configure_profile(self, profile, private_profile_id=None):
        interceptor = Interceptor(self)
        interceptor.setParent(profile)
        profile.setUrlRequestInterceptor(interceptor)
        profile.downloadRequested.connect(
            lambda request, profile_id=private_profile_id: self._download_requested(request, profile_id)
        )

    @Slot(QObject)
    def registerDefaultProfile(self, profile):
        if profile is None:
            return
        if self.profile is profile:
            return
        self.profile = profile
        self._configure_profile(profile)
        self._extension_manager = profile.extensionManager()
        self._extension_manager.loadFinished.connect(self._extension_finished)
        self._extension_manager.installFinished.connect(self._extension_finished)
        self._extension_manager.uninstallFinished.connect(self._extension_finished)

    @Slot()
    def _inc(self):
        self._blocked += 1
        self.blockedChanged.emit()

    blocked = Property(int, lambda s: s._blocked, notify=blockedChanged)

    @Property("QVariantList", notify=historyChanged)
    def history(self):
        return self._history

    @Property("QVariantList", notify=downloadsChanged)
    def downloads(self):
        return self._downloads

    @Property("QVariantList", notify=extensionsChanged)
    def extensions(self):
        if self._extension_manager is None:
            return []
        return [
            {"id": info.id(), "name": info.name(), "enabled": info.isEnabled(), "loaded": info.isLoaded()}
            for info in self._extension_manager.extensions()
        ]

    @Property(str, notify=extensionStatusChanged)
    def extensionStatus(self):
        return self._extension_status

    @Property(str, constant=True)
    def downloadPath(self):
        return str(self._download_path)

    def _get_dark_mode(self):
        return self._dark_mode

    def _set_dark_mode(self, value):
        self._dark_mode = bool(value)
        self._settings.setValue("darkMode", self._dark_mode)
        self.settingsChanged.emit()

    darkMode = Property(bool, _get_dark_mode, _set_dark_mode, notify=settingsChanged)

    def _get_engine(self):
        return self._search_engine

    def _set_engine(self, value):
        if value in SEARCH_URLS and value != self._search_engine:
            self._search_engine = value
            self._settings.setValue("searchEngineV2", value)
            self.settingsChanged.emit()

    searchEngine = Property(str, _get_engine, _set_engine, notify=settingsChanged)

    @Property(str, constant=True)
    def sessionState(self):
        return self._session_state

    @Slot(str, int)
    def saveSession(self, session_json, current_index):
        try:
            session = json.loads(session_json)
        except (TypeError, ValueError):
            return
        if not isinstance(session, dict) or not isinstance(session.get("tabs"), list):
            return
        tabs = []
        for item in session["tabs"][:20]:
            if not isinstance(item, dict):
                continue
            url = str(item.get("url", ""))[:4096]
            if url and QUrl(url).scheme().lower() not in ("http", "https"):
                continue
            tabs.append({"url": url, "title": str(item.get("title", "New Tab"))[:300]})
        if not tabs:
            tabs = [{"url": "", "title": "New Tab"}]
        current = max(0, min(int(current_index), len(tabs) - 1))
        self._session_state = json.dumps({"tabs": tabs, "current": current}, separators=(",", ":"))
        self._settings.setValue("sessionState", self._session_state)

    def _get_t(self): return self._trackers
    def _set_t(self, v):
        self._trackers = bool(v)
        self._settings.setValue("blockTrackers", self._trackers)
        self.settingsChanged.emit()
    def _get_h(self): return self._https
    def _set_h(self, v):
        self._https = bool(v)
        self._settings.setValue("httpsOnlyV2", self._https)
        self.settingsChanged.emit()
    blockTrackers = Property(bool, _get_t, _set_t, notify=settingsChanged)
    httpsOnly = Property(bool, _get_h, _set_h, notify=settingsChanged)

    def _get_web_rtc(self): return self._web_rtc
    def _set_web_rtc(self, value):
        self._web_rtc = bool(value)
        self._settings.setValue("webRtcProtection", self._web_rtc)
        self.settingsChanged.emit()
    webRtcProtection = Property(bool, _get_web_rtc, _set_web_rtc, notify=settingsChanged)

    @Slot(str, result=str)
    def normalize(self, text):
        t = text.strip()
        if not t:
            return ""
        if "://" in t or t.startswith("about:"):
            return t
        if " " not in t and ("." in t or t.startswith("localhost")):
            return ("http://" if t.startswith(("localhost", "127.")) else "https://") + t
        return SEARCH_URLS[self._search_engine].format(query=quote_plus(t))

    @Slot(QObject)
    def registerPrivateProfile(self, profile):
        if profile is None:
            return
        if self._private_profiles.get(0) is profile:
            return
        self._private_profiles[0] = profile
        self._configure_profile(profile, 0)

    @Slot(int, result=QObject)
    def privateProfile(self, profile_id):
        return self._private_profiles.get(profile_id)

    @Slot(int)
    def releasePrivateProfile(self, profile_id):
        profile = self._private_profiles.get(profile_id)
        if profile is None:
            return
        for entry in list(self._downloads):
            if entry["privateProfileId"] == profile_id:
                self.cancelDownload(entry["id"])
                self._downloads.remove(entry)
        profile.cookieStore().deleteAllCookies()
        profile.clearHttpCache()
        self.downloadsChanged.emit()

    @Slot(str, str)
    def recordVisit(self, url, title):
        if not url or url.startswith(("about:", "data:")):
            return
        entry = {"url": url, "title": title or url}
        if self._history and self._history[0]["url"] == url:
            self._history[0] = entry
        else:
            self._history.insert(0, entry)
            del self._history[500:]
        self.historyChanged.emit()

    @Slot()
    def clearHistory(self):
        self._history.clear()
        self.historyChanged.emit()

    def _download_requested(self, request, profile_id):
        download_id = request.id()
        filename = Path(request.downloadFileName() or request.suggestedFileName()).name
        request.setDownloadDirectory(str(self._download_path))
        request.setDownloadFileName(filename or f"download-{download_id}")
        self._downloads.insert(0, {
            "id": download_id,
            "name": filename or f"download-{download_id}",
            "url": request.url().toString(),
            "received": 0,
            "total": request.totalBytes(),
            "state": "Starting",
            "privateProfileId": profile_id,
        })
        self._download_requests[download_id] = request
        request.receivedBytesChanged.connect(lambda key=download_id: self._refresh_download(key))
        request.totalBytesChanged.connect(lambda key=download_id: self._refresh_download(key))
        request.stateChanged.connect(lambda _state, key=download_id: self._refresh_download(key))
        request.accept()
        self.downloadsChanged.emit()

    @Slot(int)
    def _refresh_download(self, download_id):
        request = self._download_requests.get(download_id)
        if request is None:
            return
        for entry in self._downloads:
            if entry["id"] == download_id:
                entry["received"] = request.receivedBytes()
                entry["total"] = request.totalBytes()
                state = request.state()
                state_name = getattr(state, "name", str(state).rsplit(".", 1)[-1])
                entry["state"] = {
                    "DownloadInProgress": "Downloading",
                    "DownloadCompleted": "Complete",
                    "DownloadCancelled": "Cancelled",
                    "DownloadInterrupted": "Failed",
                }.get(state_name, state_name)
                break
        self.downloadsChanged.emit()
        if request.isFinished():
            self._download_requests.pop(download_id, None)

    @Slot(int)
    def cancelDownload(self, download_id):
        request = self._download_requests.get(download_id)
        if request is not None and not request.isFinished():
            request.cancel()

    @Slot()
    def openDownloadsFolder(self):
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(self._download_path)))

    @Slot(str, result=bool)
    def installExtension(self, path):
        extension_path = QUrl(path).toLocalFile() if path.startswith("file:") else path
        if not extension_path:
            self._extension_status = "Choose an extension file or folder"
            self.extensionStatusChanged.emit()
            return False
        try:
            if Path(extension_path).is_dir():
                self._extension_manager.loadExtension(extension_path)
            elif Path(extension_path).suffix.lower() == ".crx":
                self._extension_manager.installExtension(extension_path)
            else:
                self._extension_status = "Choose a .crx file or unpacked extension folder"
                self.extensionStatusChanged.emit()
                return False
        except (OSError, RuntimeError) as error:
            self._extension_status = str(error)
            self.extensionStatusChanged.emit()
            return False
        self._extension_status = "Extension request submitted"
        self.extensionStatusChanged.emit()
        return True

    def _extension_finished(self, info):
        error = info.error()
        self._extension_status = error or f"Extension updated: {info.name() or info.id()}"
        self.extensionsChanged.emit()
        self.extensionStatusChanged.emit()

    @Slot(str, bool)
    def setExtensionEnabled(self, extension_id, enabled):
        self._extension_manager.setExtensionEnabled(extension_id, enabled)
        self.extensionsChanged.emit()

    @Slot(str)
    def uninstallExtension(self, extension_id):
        self._extension_manager.uninstallExtension(extension_id)

    @Slot()
    def clearData(self):
        if self.profile is None:
            return
        self.profile.clearHttpCache()
        try:
            self.profile.cookieStore().deleteAllCookies()
        except Exception:
            pass
        self.clearHistory()


class Interceptor(QWebEngineUrlRequestInterceptor):
    def __init__(self, backend):
        super().__init__()
        self.b = backend

    def interceptRequest(self, info):
        url = info.requestUrl()
        host = url.host()
        if self.b._trackers and any(host == d or host.endswith("." + d) for d in TRACKERS):
            info.block(True)
            self.b._bump.emit()
            return
        if (self.b._https and url.scheme() == "http" and host not in ("localhost", "127.0.0.1")
                and info.resourceType() == QWebEngineUrlRequestInfo.ResourceTypeMainFrame):
            url.setScheme("https")
            info.redirect(url)
            return
        info.setHttpHeader(b"DNT", b"1")
        info.setHttpHeader(b"Sec-GPC", b"1")


if __name__ == "__main__":
    frozen = getattr(sys, "frozen", False)
    bundle_root = Path(getattr(sys, "_MEIPASS", Path(__file__).parent))
    here = bundle_root / "Frontend" if frozen else Path(__file__).parent
    QtWebEngineQuick.initialize()
    app = QGuiApplication(sys.argv)
    app.setApplicationName("Quantum Browser")
    app.setOrganizationName("QuantumBrowser")
    app.setWindowIcon(QIcon(str(bundle_root / "assets" / "logo.png")))
    backend = Backend()
    engine = QQmlApplicationEngine()
    FeatherIconsQML.register(engine)
    engine.addImportPath(str(here))
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(here / "Main.qml")))
    if not engine.rootObjects():
        sys.exit(1)
    sys.exit(app.exec())
