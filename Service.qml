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

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property bool busy: whichProcess.running
    || statusProcess.running
    || serversProcess.running
    || actionProcess.running
    || selectProcess.running

  property string _statusOutput: ""
  property string _statusError: ""
  property string _serversOutput: ""
  property string _serversError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _selectOutput: ""
  property string _selectError: ""
  property bool _activateAfterSelect: false
  property double _lastServersRefreshMs: 0

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
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = root.elideStatus(stderr || stdout || "Mozilla VPN command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
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
      root._activateAfterSelect = false
      root.selectingCityId = ""

      if (exitCode !== 0) {
        root.lastError = root.elideStatus(stderr || stdout || "Server selection failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
        delayedRefresh.restart()
        return
      }

      root.lastError = ""
      if (shouldActivate) {
        root.activate()
      } else {
        root.actionStatus = "Server selected"
        actionStatusTimer.restart()
        delayedRefresh.restart()
      }
    }
  }
}
