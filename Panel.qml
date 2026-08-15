import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.davydotcom.mozilla-vpn"
  ipcTarget: "io.github.davydotcom.mozilla-vpn"
  manageIpc: false

  property string focusSection: "header"
  property int cityIndex: 0
  property bool cursorActive: false
  property string cityQuery: ""
  property int phraseIndex: 0

  readonly property var activePhrases: [
    "Routing packets",
    "Sealing tunnels",
    "Masking hops",
    "Guarding egress",
    "Polishing wire",
    "Hiding trails"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: vpn.active ? foreground : dim
  readonly property color barIconColor: vpn.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property string toggleHint: {
    if (!vpn.installed) return "Mozilla VPN is not installed"
    if (!vpn.authenticated) return "Sign in with Mozilla VPN"
    return vpn.active ? "Turn Mozilla VPN off" : "Turn Mozilla VPN on"
  }
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && vpn.installed && vpn.authenticated
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  readonly property var recentCityIds: settings.recentCityIds instanceof Array ? settings.recentCityIds : []
  readonly property bool nearestDefaultApplied: settings.nearestDefaultApplied === true
  readonly property var filteredCities: displayCities()
  readonly property string icon: vpn.active ? "󰖂" : "󰦞"

  function cityById(id) {
    var key = String(id || "")
    for (var i = 0; i < vpn.cities.length; i++) {
      if (String(vpn.cities[i].id || "") === key) return vpn.cities[i]
    }
    return null
  }

  function currentCity() {
    return Model.findCurrentCity(vpn.cities, vpn.countryCode, vpn.city)
  }

  function displayCities() {
    var filtered = Model.filterCities(vpn.cities, cityQuery)
    var query = String(cityQuery || "").trim()
    if (query !== "") return filtered

    // Pin order: Mozilla's currently selected city, then cities you picked
    // in this panel, then the rest of the catalog.
    var pinned = []
    var seen = {}
    function pushUnique(city) {
      if (!city) return
      var id = String(city.id || "")
      if (id === "" || seen[id]) return
      pinned.push(city)
      seen[id] = true
    }

    pushUnique(currentCity())
    for (var i = 0; i < recentCityIds.length; i++) pushUnique(cityById(recentCityIds[i]))

    var rest = []
    for (var j = 0; j < filtered.length; j++) {
      var item = filtered[j]
      var itemId = String(item.id || "")
      if (seen[itemId]) continue
      rest.push(item)
    }
    return pinned.concat(rest)
  }

  function selectedCity() {
    if (filteredCities.length === 0) return null
    return filteredCities[Math.max(0, Math.min(cityIndex, filteredCities.length - 1))]
  }

  function isCurrentCity(city) {
    return Model.matchesCurrent(city, vpn.countryCode, vpn.city)
  }

  function writeSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function persistRecentCity(city, opts) {
    var id = String((city && city.id) || "")
    if (id === "") return
    var seedOnly = opts && opts.seedOnly === true
    if (seedOnly && recentCityIds.indexOf(id) !== -1) return

    var next = seedOnly ? recentCityIds.slice() : [id]
    if (seedOnly) {
      next = [id].concat(next.filter(function(existing) { return existing !== id }))
    } else {
      for (var i = 0; i < recentCityIds.length && next.length < 6; i++) {
        var existing = String(recentCityIds[i] || "")
        if (existing !== "" && existing !== id && next.indexOf(existing) === -1) next.push(existing)
      }
    }
    if (next.length > 6) next = next.slice(0, 6)
    writeSettings({ recentCityIds: next })
  }

  function syncRememberedCity() {
    // Wait for the one-shot nearest-default pass before seeding Mozilla's
    // current target into recent, or a leftover Romania/etc. would look like
    // a user preference and block auto-locate.
    if (!nearestDefaultApplied && recentCityIds.length === 0) return
    var city = currentCity()
    if (city) persistRecentCity(city, { seedOnly: true })
  }

  function tryNearestDefault() {
    if (nearestDefaultApplied) return
    if (recentCityIds.length > 0) {
      writeSettings({ nearestDefaultApplied: true })
      return
    }
    vpn.maybeRequestNearestDefault()
  }

  function markNearestDefaultApplied(city) {
    var values = { nearestDefaultApplied: true }
    if (city) {
      var id = String(city.id || "")
      if (id !== "") values.recentCityIds = [id].concat(recentCityIds.filter(function(existing) { return existing !== id })).slice(0, 6)
    }
    writeSettings(values)
  }

  function chooseCity(city) {
    if (!city || vpn.busy) return
    persistRecentCity(city)
    writeSettings({ nearestDefaultApplied: true })
    vpn.selectCity(city, true)
  }

  function ensureCursor() {
    if (cityIndex >= filteredCities.length) cityIndex = Math.max(0, filteredCities.length - 1)
    if (focusSection === "cities" && filteredCities.length === 0) focusSection = "header"
    if (focusSection === "auth" && vpn.authenticated) focusSection = "header"
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return

    if (focusSection === "header") {
      if (dy > 0) {
        if (!vpn.authenticated) focusSection = "auth"
        else if (filteredCities.length > 0) focusSection = "cities"
      }
    } else if (focusSection === "auth") {
      if (dy < 0) focusSection = "header"
    } else if (focusSection === "cities") {
      if (dy < 0) {
        if (cityIndex <= 0) focusSection = "header"
        else cityIndex--
      } else if (cityIndex < filteredCities.length - 1) {
        cityIndex++
      }
    }
    ensureCursor()
    scrollCursorIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") vpn.toggleVpn()
    else if (focusSection === "auth") vpn.openUi()
    else if (focusSection === "cities") chooseCity(selectedCity())
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
  }

  function setAuthCursor() {
    cursorActive = true
    focusSection = "auth"
  }

  function setCityCursor(index) {
    cursorActive = true
    focusSection = "cities"
    cityIndex = index
    scrollCursorIntoView()
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "cities" && cityColumn && cityIndex >= 0 && cityIndex < cityColumn.children.length)
      scrollItemIntoView(cityColumn.children[cityIndex])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    cityQuery = ""
    if (panelFlick) panelFlick.contentY = 0
    vpn.refresh(true)
    root.tryNearestDefault()
    root.syncRememberedCity()
    Qt.callLater(function() {
      var current = root.currentCity()
      if (current) {
        for (var i = 0; i < root.filteredCities.length; i++) {
          if (String(root.filteredCities[i].id || "") === String(current.id || "")) {
            root.cityIndex = i
            break
          }
        }
      }
      keyCatcher.forceActiveFocus()
    })
  }
  onFilteredCitiesChanged: ensureCursor()
  onCityIndexChanged: scrollCursorIntoView()

  Service {
    id: vpn
    settings: root.settings
  }

  Connections {
    target: vpn
    function onCitiesChanged() {
      root.tryNearestDefault()
      root.syncRememberedCity()
      root.ensureCursor()
    }
    function onCityChanged() { root.syncRememberedCity() }
    function onCountryCodeChanged() { root.syncRememberedCity() }
    function onAuthenticatedChanged() {
      root.tryNearestDefault()
      root.ensureCursor()
    }
    function onActiveChanged() {
      if (!vpn.active) root.tryNearestDefault()
    }
    function onNearestDefaultFinished(city) {
      // Do not seed vpn.city here — status is still the previous target
      // until the delayed refresh lands.
      root.markNearestDefaultApplied(city)
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { vpn.refresh(true); return "ok" }
    function activate(): string { vpn.activate(); return "ok" }
    function deactivate(): string { vpn.deactivate(); return "ok" }
    function toggleVpn(): string { vpn.toggleVpn(); return "ok" }
    function status(): string { return vpn.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    foreground: root.barIconColor
    useActiveColor: false
    tooltipText: vpn.active ? ("Mozilla VPN · " + vpn.locationText) : "Mozilla VPN"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) vpn.toggleVpn()
      else if (buttonCode === Qt.MiddleButton) vpn.refresh(true)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") vpn.toggleVpn()
        else if (t === "/") {
          citySearch.forceActiveFocus()
          citySearch.selectAll()
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Mozilla VPN"
              meta: {
                if (!vpn.installed) return "CLI not installed"
                if (!vpn.authenticated) return "Sign in required"
                if (vpn.active) return root.heroPhraseText
                return vpn.locationText
              }
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: vpn.active ? 1.0 : 0.5
              iconComponent: Component {
                Text {
                  text: root.icon
                  color: root.iconColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: vpn.installed && vpn.authenticated
                  checked: vpn.active
                  busy: vpn.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: vpn.toggleVpn()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: vpn.authenticated && vpn.locationText !== ""
            width: parent.width
            text: vpn.active ? ("Connected · " + vpn.locationText) : ("Target · " + vpn.locationText)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: vpn.actionStatus !== "" || vpn.lastError !== ""
            width: parent.width
            text: vpn.actionStatus !== "" ? vpn.actionStatus : vpn.lastError
            color: vpn.lastError !== "" && vpn.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          CursorSurface {
            visible: !vpn.installed
            width: parent.width
            implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground

            Text {
              id: missingText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: "mozillavpn is not installed or not on PATH."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
          }

          CursorSurface {
            visible: vpn.installed && !vpn.authenticated
            width: parent.width
            hasCursor: root.cursorActive && root.focusSection === "auth"
            foreground: root.foreground
            fill: root.hoverFill
            implicitHeight: authRow.implicitHeight + Style.spacing.rowPaddingX

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.setAuthCursor()
              onClicked: vpn.openUi()
            }

            RowLayout {
              id: authRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              Text {
                text: "󰌋"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(1)

                Text {
                  Layout.fillWidth: true
                  text: "Sign in to Mozilla VPN"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  Layout.fillWidth: true
                  text: "Opens the Mozilla VPN app"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }

          PanelSeparator {
            visible: vpn.installed && vpn.authenticated
            foreground: root.foreground
          }

          Column {
            visible: vpn.installed && vpn.authenticated
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "SERVERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            TextField {
              id: citySearch
              width: parent.width
              foreground: root.foreground
              placeholderText: "Search cities"
              text: root.cityQuery
              onTextChanged: {
                root.cityQuery = text
                root.cityIndex = 0
              }
              onAccepted: root.chooseCity(root.selectedCity())
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Down || event.text === "j") {
                  root.setCityCursor(Math.min(root.filteredCities.length - 1, root.cityIndex + 1))
                  event.accepted = true
                  return
                }
                if (event.key === Qt.Key_Up || event.text === "k") {
                  root.setCityCursor(Math.max(0, root.cityIndex - 1))
                  event.accepted = true
                  return
                }
                if (event.key === Qt.Key_Escape) {
                  root.cityQuery = ""
                  text = ""
                  keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
              }
            }

            Text {
              visible: root.filteredCities.length === 0
              width: parent.width
              text: vpn.cities.length === 0 ? "Loading servers…" : "No cities match that search."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: cityColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.filteredCities
                CityRow {
                  required property var modelData
                  required property int index
                  width: cityColumn.width
                  city: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && vpn.active
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  component CityRow: CursorSurface {
    id: cityRow
    property var city: null
    property int rowIndex: 0
    readonly property bool currentCity: root.isCurrentCity(city)
    readonly property bool selectingCity: city && vpn.selectingCityId === String(city.id || "")
    readonly property string cityName: city ? String(city.city || "Unknown") : "Unknown"
    readonly property string countryName: city ? String(city.country || "") : ""

    hasCursor: root.cursorActive && root.focusSection === "cities" && root.cityIndex === rowIndex
    current: currentCity || selectingCity
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: cityInner.implicitHeight + Style.spacing.xl

    Row {
      id: cityInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: cityRow.currentCity || cityRow.selectingCity ? "󰖂" : "󰍒"
        color: cityRow.currentCity || cityRow.selectingCity ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter

        NumberAnimation on rotation {
          running: cityRow.selectingCity
          from: 0
          to: 360
          duration: 900
          loops: Animation.Infinite
        }
        onRotationChanged: if (!cityRow.selectingCity && rotation !== 0) rotation = 0
      }

      Column {
        width: parent.width - Style.space(30)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: cityRow.cityName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: cityRow.currentCity
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: cityRow.countryName
          visible: text !== ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCityCursor(cityRow.rowIndex)
      onClicked: root.chooseCity(cityRow.city)
    }
  }
}
