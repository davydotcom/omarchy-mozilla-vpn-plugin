import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool authenticated: false
  property bool running: false
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)

  property bool refreshing: false
  property string vpnState: "unknown"
  property string statusText: "Checking…"
  property string email: ""
  property string countryCode: ""
  property string country: ""
  property string city: ""
  readonly property string locationText: Model.locationLabel(city, country)

  property var cities: []
  property string selectingCityId: ""
  property string actionStatus: ""
  property string lastError: ""
  property bool nearestDefaultBusy: false
  property bool _nearestSelectPending: false

  signal nearestDefaultFinished(var city)

  property bool blockAds: false
  property bool blockTrackers: false
  property bool blockMalware: false
  property bool privacyBusy: false
  property bool _reconnectAfterPrivacy: false

  readonly property string privacyHelper: {
    var url = String(Qt.resolvedUrl("privacy.py"))
    if (url.indexOf("file://") === 0) url = decodeURIComponent(url.substring(7))
    return url
  }

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property bool busy: whichProcess.running
    || statusProcess.running
    || serversProcess.running
    || actionProcess.running
    || selectProcess.running
    || geoProcess.running
    || privacyGetProcess.running
    || privacySetProcess.running
    || nearestDefaultBusy
    || privacyBusy

  property string _statusOutput: ""
  property string _statusError: ""
  property string _serversOutput: ""
  property string _serversError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _selectOutput: ""
  property string _selectError: ""
  property string _geoOutput: ""
  property string _geoError: ""
  property bool _activateAfterSelect: false
  property double _lastServersRefreshMs: 0
  property var _pendingNearestCity: null

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function refresh(forceServers) {
    if (installed) {
      refreshStatus(forceServers === true)
      refreshPrivacy()
      return
    }
    if (!whichProcess.running) {
      refreshing = true
      whichProcess.command = ["which", "mozillavpn"]
      whichProcess.running = true
    }
  }

  function refreshStatus(forceServers) {
    if (!installed) return
    var launched = false
    if (!statusProcess.running) {
      _statusOutput = ""
      _statusError = ""
      refreshing = true
      statusProcess.command = ["mozillavpn", "status"]
      statusProcess.running = true
      launched = true
    }

    var now = Date.now()
    var shouldRefreshServers = forceServers === true
      || cities.length === 0
      || now - _lastServersRefreshMs > 300000
    if (shouldRefreshServers && !serversProcess.running) {
      _serversOutput = ""
      _serversError = ""
      _lastServersRefreshMs = now
      serversProcess.command = ["mozillavpn", "servers", "-j", "-c"]
      serversProcess.running = true
      launched = true
    }

    if (launched && !pollWatchdog.running) pollWatchdog.start()
  }

  function resetUnavailable(message) {
    authenticated = false
    running = false
    _desired = -1
    vpnState = "unavailable"
    statusText = message
    email = ""
    countryCode = ""
    country = ""
    city = ""
  }

  function parseStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      resetUnavailable(parsed.message || "Status error")
      lastError = parsed.error || "Failed to parse mozillavpn status"
      console.warn("mozilla-vpn", lastError)
      return
    }

    authenticated = parsed.authenticated === true
    running = parsed.running === true
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    vpnState = parsed.vpnState
    email = parsed.email
    countryCode = parsed.countryCode
    country = parsed.country
    city = parsed.city
    statusText = parsed.message
    lastError = ""
  }

  function parseServers(raw) {
    cities = Model.parseServers(raw)
  }

  function toggleVpn() {
    if (!installed || !authenticated) return
    if (active) deactivate()
    else activate()
  }

  function activate() {
    if (!installed || !authenticated || actionProcess.running) return
    _desired = 1
    runAction(["mozillavpn", "activate"])
  }

  function deactivate() {
    if (!installed || actionProcess.running) return
    _desired = 0
    runAction(["mozillavpn", "deactivate"])
  }

  function selectCity(city, connectIfNeeded) {
    if (!installed || !authenticated || !city || selectProcess.running) return
    var hostname = Model.pickHostname(city)
    if (hostname === "") return

    _selectOutput = ""
    _selectError = ""
    selectingCityId = String(city.id || "")
    _activateAfterSelect = connectIfNeeded === true || active === true
    actionStatus = "Selecting " + String(city.city || hostname) + "…"
    selectProcess.command = ["mozillavpn", "select", hostname]
    selectProcess.running = true
  }

  // One-shot: when the widget has no remembered city and the tunnel is down,
  // geolocate the public IP and select the nearest Mozilla VPN city.
  // Skips while connected so the exit IP is not mistaken for the user.
  function maybeRequestNearestDefault() {
    if (!installed || !authenticated || active || cities.length === 0) return
    if (geoProcess.running || nearestDefaultBusy || selectProcess.running) return

    nearestDefaultBusy = true
    _nearestSelectPending = true
    _pendingNearestCity = null
    _geoOutput = ""
    _geoError = ""
    actionStatus = "Finding nearest city…"
    geoProcess.command = ["curl", "-fsS", "--max-time", "8", "https://ipinfo.io/json"]
    geoProcess.running = true
  }

  function finishNearestDefault(city, message) {
    nearestDefaultBusy = false
    _nearestSelectPending = false
    _pendingNearestCity = null
    if (city) {
      actionStatus = message || ("Nearest city · " + String(city.city || city.id || ""))
      actionStatusTimer.restart()
    } else if (message) {
      actionStatus = message
      actionStatusTimer.restart()
    } else {
      actionStatus = ""
    }
    nearestDefaultFinished(city || null)
  }

  function runAction(command) {
    if (actionProcess.running) return
    _actionOutput = ""
    _actionError = ""
    actionStatus = ""
    actionProcess.command = command
    actionProcess.running = true
  }

  function openUi() {
    Quickshell.execDetached(["mozillavpn", "ui"])
  }

  function applyPrivacy(raw) {
    var parsed = Model.parsePrivacy(raw)
    blockAds = parsed.ads
    blockTrackers = parsed.trackers
    blockMalware = parsed.malware
  }

  function refreshPrivacy() {
    if (privacyGetProcess.running || privacySetProcess.running) return
    if (privacyHelper === "") return
    privacyGetProcess.command = ["python3", privacyHelper, "get"]
    privacyGetProcess.running = true
  }

  function togglePrivacy(kind) {
    var key = String(kind || "")
    if (key !== "ads" && key !== "trackers" && key !== "malware") return
    if (!installed || privacySetProcess.running) return
    privacyBusy = true
    actionStatus = "Updating privacy features…"
    privacySetProcess.command = ["python3", privacyHelper, "toggle", key]
    privacySetProcess.running = true
  }

  function bounceTunnelForPrivacy() {
    if (!active && _desired !== 1) {
      privacyBusy = false
      delayedRefresh.restart()
      return
    }
    _reconnectAfterPrivacy = true
    runAction(["mozillavpn", "deactivate"])
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 700
    repeat: false
    onTriggered: root.refresh(true)
  }

  Timer {
    id: pollWatchdog
    interval: 20000
    repeat: false
    onTriggered: {
      if (statusProcess.running) statusProcess.running = false
      if (serversProcess.running) serversProcess.running = false
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refreshStatus(true)
      else {
        root.refreshing = false
        root.resetUnavailable("Not installed")
      }
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.parseStatus(stdout)
      else {
        root.resetUnavailable("Unavailable")
        root.lastError = root.elideStatus(stderr || stdout || "mozillavpn status failed")
      }
    }
  }

  Process {
    id: serversProcess
    running: false
    command: []
    stdout: StdioCollector { id: serversStdout; waitForEnd: true; onStreamFinished: root._serversOutput = text }
    stderr: StdioCollector { id: serversStderr; waitForEnd: true; onStreamFinished: root._serversError = text }
    onExited: function(exitCode) {
      var stdout = String(serversStdout.text || root._serversOutput || "")
      if (exitCode === 0) root.parseServers(stdout)
      else root.parseServers("")
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || root._actionOutput || "")
      var stderr = String(actionStderr.text || root._actionError || "")
      if (root._reconnectAfterPrivacy) {
        root._reconnectAfterPrivacy = false
        if (exitCode === 0) {
          root.activate()
        } else {
          root.privacyBusy = false
          root._desired = -1
          root.lastError = root.elideStatus(stderr || stdout || "Could not reconnect after privacy change")
          root.actionStatus = root.lastError
          actionStatusTimer.restart()
        }
        delayedRefresh.restart()
        return
      }
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = root.elideStatus(stderr || stdout || "Mozilla VPN command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
        if (root.privacyBusy) root.privacyBusy = false
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: selectProcess
    running: false
    command: []
    stdout: StdioCollector { id: selectStdout; waitForEnd: true; onStreamFinished: root._selectOutput = text }
    stderr: StdioCollector { id: selectStderr; waitForEnd: true; onStreamFinished: root._selectError = text }
    onExited: function(exitCode) {
      var stdout = String(selectStdout.text || root._selectOutput || "")
      var stderr = String(selectStderr.text || root._selectError || "")
      var shouldActivate = root._activateAfterSelect
      var nearestCity = root._pendingNearestCity
      var nearestPending = root._nearestSelectPending
      root._activateAfterSelect = false
      root.selectingCityId = ""

      if (exitCode !== 0) {
        root.lastError = root.elideStatus(stderr || stdout || "Server selection failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
        if (nearestPending) root.finishNearestDefault(null, root.lastError)
        delayedRefresh.restart()
        return
      }

      root.lastError = ""
      if (nearestPending) {
        root.finishNearestDefault(nearestCity)
        delayedRefresh.restart()
        return
      }

      if (shouldActivate) {
        root.activate()
      } else {
        root.actionStatus = "Server selected"
        actionStatusTimer.restart()
        delayedRefresh.restart()
      }
    }
  }

  Process {
    id: geoProcess
    running: false
    command: []
    stdout: StdioCollector { id: geoStdout; waitForEnd: true; onStreamFinished: root._geoOutput = text }
    stderr: StdioCollector { id: geoStderr; waitForEnd: true; onStreamFinished: root._geoError = text }
    onExited: function(exitCode) {
      var stdout = String(geoStdout.text || root._geoOutput || "")
      var stderr = String(geoStderr.text || root._geoError || "")
      if (!root._nearestSelectPending) {
        root.nearestDefaultBusy = false
        return
      }

      if (exitCode !== 0) {
        root.finishNearestDefault(null, root.elideStatus(stderr || "Could not locate this network"))
        return
      }

      var geo = Model.parseUserGeo(stdout)
      var city = Model.resolveDefaultCity(root.cities, geo)
      if (!city) {
        root.finishNearestDefault(null, "No nearby Mozilla VPN city found")
        return
      }

      root._pendingNearestCity = city
      root.selectCity(city, false)
    }
  }

  Process {
    id: privacyGetProcess
    running: false
    command: []
    stdout: StdioCollector { id: privacyGetStdout; waitForEnd: true }
    stderr: StdioCollector { id: privacyGetStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var stdout = String(privacyGetStdout.text || "")
      if (exitCode === 0) root.applyPrivacy(stdout)
    }
  }

  Process {
    id: privacySetProcess
    running: false
    command: []
    stdout: StdioCollector { id: privacySetStdout; waitForEnd: true }
    stderr: StdioCollector { id: privacySetStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var stdout = String(privacySetStdout.text || "")
      var stderr = String(privacySetStderr.text || "")
      if (exitCode !== 0) {
        root.privacyBusy = false
        root.lastError = root.elideStatus(stderr || stdout || "Could not update privacy features")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
        return
      }
      root.applyPrivacy(stdout)
      root.lastError = ""
      root.actionStatus = "Privacy features updated"
      actionStatusTimer.restart()
      root.bounceTunnelForPrivacy()
    }
  }
}
