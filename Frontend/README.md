# Quantum Browser

![Quantum Browser logo](../assets/logo.jpeg)

A desktop web browser built with Python, PySide6, Qt Quick, and QtWebEngine. Chromium renders websites; QML provides the tabbed browser interface.

**[Open the styled HTML guide](README.html)**

## Why It Exists

Quantum Browser is intended to be a straightforward desktop browser with visible privacy controls, session restore for ordinary tabs, isolated private tabs, and a familiar Chromium-based web engine. It uses QtWebEngine rather than implementing a custom page renderer.

## Quick Start

### Run From Source

Requirements: Python 3.12 or newer, Qt 6.9 or newer, and a graphical desktop session with QtWebEngine runtime libraries.

From the workspace root:

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r Frontend/requirements.txt
python Frontend/main.py
```

### Install the Debian Package

On a compatible amd64 Ubuntu 24.04 or Linux Mint 22 system, install the locally built package with:

```bash
sudo apt install ./Frontend/dist/quantum-browser_0.1.0_amd64.deb
```

It installs the app under `/opt/quantum-browser` and adds a desktop launcher. The package is about 188 MB compressed because it bundles QtWebEngine and Chromium; administrator permission is required to install it.

## Using the Browser

- **Search or open a site:** enter a search phrase or URL in the address field. Google is the initial search provider; choose Google, DuckDuckGo, Bing, or Brave Search in **Settings > General**.
- **Open a normal tab:** select the plus button or press `Ctrl+T`.
- **Open a private tab:** select the eye-off button or press `Ctrl+Shift+N`.
- **Close a tab:** select its close button, middle-click the tab, or press `Ctrl+W`.
- **Switch tabs:** press `Ctrl+Tab`.
- **Focus the address field:** press `Ctrl+L`.
- **Navigate:** use the back/forward buttons or `Alt+Left` and `Alt+Right`; reload with `Ctrl+R`.
- **Bookmarks, history, and downloads:** use the star, clock, and download buttons in the toolbar.
- **Reveal hidden browser chrome:** after 30 seconds without pointer movement, the title/address bars hide while the tab strip remains. Move the pointer over the window to reveal them.

## Tabs and Saved State

Normal open-tab URLs, titles, and the selected-tab position are saved in the user's Qt settings. At most 20 ordinary tabs are restored at the next launch. Web navigation history is kept separately in memory for the current run.

Private tabs use an off-the-record profile with in-memory cookies and cache. Their URLs are excluded from session restore and the history list. When the final private tab closes, private cookies, cache, and private download entries are cleared. Downloaded files themselves are saved to the system Downloads folder and remain on disk; private mode does not remove files a user explicitly downloaded.

Private mode limits data saved by this browser profile. It does not hide traffic from websites, search providers, network operators, or an internet service provider.

## Privacy and Security

Settings are grouped under **General**, **Privacy**, **Security**, and **Extensions**.

- **Tracker blocking:** the built-in domain list is enabled by default. It is not a replacement for a maintained filter-list extension.
- **HTTPS upgrade:** optional in **Settings > Privacy**, and off by default so HTTP-only sites remain reachable. Users may type explicit `http://` or `https://` URLs.
- **Certificate errors:** non-overridable certificate failures are rejected. For errors Qt marks as overridable, the browser offers a one-time continue action. Continuing bypasses certificate validation for that connection and should only be used when the site is trusted.
- **Web permissions:** requests for camera, microphone, location, notifications, and supported site features prompt for an explicit allow/block choice.
- **WebRTC:** **Settings > Security** can restrict WebRTC to public interfaces. This reduces local IP exposure but can affect some calls.
- **Clear data:** **Settings > Privacy** clears the normal profile's HTTP cache, cookies, and in-memory browser history.

A Chromium `net_error -202` commonly indicates an untrusted certificate authority. The lasting fix is to correct the server certificate or install the legitimate CA certificate in the operating system's trust store, not to disable certificate checks globally.

## Video and Media

Websites use QtWebEngine's Chromium media stack. HTML5 playback, autoplay, fullscreen support, and the bundled Qt FFmpeg multimedia plugin are enabled. Downloads are managed by the browser.

Playback compatibility depends on codecs and media support included with the QtWebEngine build. Some services require Widevine or other DRM components; this project does not bundle or guarantee them. No setting can add a codec or DRM module that is absent from the runtime.

Fullscreen requests are handled by the browser window. A certificate error can still prevent media from loading until the site or trust configuration is fixed.

## Extensions

Open **Settings > Extensions** to load a local Chromium `.crx` file or an unpacked extension directory, toggle an extension, or remove it. Direct Chrome Web Store installation is not implemented. Extensions receive the permissions declared by their manifests.

AdGuard is not bundled. The built-in tracker blocker is enabled by default; install an extension only from a trusted source and review its permissions.

## Project Layout

- `main.py`: PySide6 application startup, WebEngine profile configuration, request blocking, search routing, session persistence, certificate-related profile setup, and downloads.
- `Main.qml`: window, tabs, address bar, settings, history/download views, and WebEngine pages.
- `Icon.qml`, `Icons.qml`: icon component and Feather icon names.
- `Theme.qml`: colors and light/dark appearance.
- `qmldir`: local QML module registration.
- `requirements.txt`: Python dependencies.
- `../assets/logo.png`: application window/start-page logo.
- `../assets/logo.jpeg`: logo shown in this README and the HTML guide.

## Build Notes

The checked-in Linux package is built for amd64 Ubuntu 24.04/Linux Mint 22-compatible systems. It is a self-contained PyInstaller bundle packaged as a Debian archive. Its size is largely QtWebEngine/Chromium; stripping symbols has little impact on that engine library.

The repository's source-only publication branch is `quantum-browser-source`. The generated `.deb` is intentionally excluded from that branch.

## Compatibility Notes

- Websites can change their behavior; console messages such as `chat.init: chat button not found` come from website JavaScript and do not necessarily indicate a browser failure.
- Some sites reject embedded browsers, require DRM, or rely on codecs unavailable in QtWebEngine.
- Certificate overrides are per connection and do not make an invalid certificate trustworthy.
- The bundled browser is larger than source-only projects because it contains the QtWebEngine runtime.
