function field(raw, name) {
  var match = String(raw || "").match(new RegExp("^" + name + ":\\s*(.*)$", "mi"))
  return match ? String(match[1] || "").trim() : ""
}

function parseStatus(raw) {
  var text = String(raw || "")
  if (text.trim() === "") {
    return {
      ok: false,
      unavailable: true,
      message: "No status",
      error: "Empty mozillavpn status"
    }
  }

  var userStatus = field(text, "User status").toLowerCase()
  var vpnState = field(text, "VPN state").toLowerCase()
  var authenticated = userStatus === "authenticated"
  var running = vpnState === "on" || vpnState === "connecting" || vpnState === "switching"

  return {
    ok: true,
    unavailable: false,
    authenticated: authenticated,
    running: running,
    vpnState: vpnState || "unknown",
    email: field(text, "User email"),
    displayName: field(text, "User displayName"),
    countryCode: field(text, "Server country code").toLowerCase(),
    country: field(text, "Server country"),
    city: field(text, "Server city"),
    message: authenticated
      ? (running ? "Connected" : "Disconnected")
      : (userStatus ? userStatus : "Not authenticated")
  }
}

function cityId(countryCode, cityCode) {
  return String(countryCode || "").toLowerCase() + "/" + String(cityCode || "").toLowerCase()
}

function parseServers(raw) {
  var text = String(raw || "").trim()
  if (text === "") return []

  try {
    var countries = JSON.parse(text)
    if (!countries || typeof countries.length !== "number") return []

    var cities = []
    for (var i = 0; i < countries.length; i++) {
      var country = countries[i] || {}
      var countryCode = String(country.code || "").toLowerCase()
      var countryName = String(country.name || countryCode)
      var countryCities = country.cities || []
      for (var j = 0; j < countryCities.length; j++) {
        var city = countryCities[j] || {}
        var cityCode = String(city.code || "").toLowerCase()
        var cityName = String(city.name || cityCode)
        var servers = city.servers || []
        var hostnames = []
        for (var k = 0; k < servers.length; k++) {
          var hostname = String((servers[k] && servers[k].hostname) || "")
          if (hostname !== "") hostnames.push(hostname)
        }
        if (hostnames.length === 0) continue
        cities.push({
          id: cityId(countryCode, cityCode),
          countryCode: countryCode,
          country: countryName,
          cityCode: cityCode,
          city: cityName,
          label: cityName,
          detail: countryName,
          hostnames: hostnames,
          hostname: hostnames[0]
        })
      }
    }

    cities.sort(function(a, b) {
      var countryCompare = String(a.country).localeCompare(String(b.country))
      if (countryCompare !== 0) return countryCompare
      return String(a.city).localeCompare(String(b.city))
    })
    return cities
  } catch (e) {
    return []
  }
}

function filterCities(cities, query) {
  var q = String(query || "").trim().toLowerCase()
  var source = Array.isArray(cities) ? cities : []
  if (q === "") return source.slice()

  var result = []
  for (var i = 0; i < source.length; i++) {
    var city = source[i] || {}
    var haystack = [
      city.city,
      city.country,
      city.cityCode,
      city.countryCode,
      city.label,
      city.detail
    ].join(" ").toLowerCase()
    if (haystack.indexOf(q) !== -1) result.push(city)
  }
  return result
}

function pickHostname(city) {
  if (!city) return ""
  var hostnames = city.hostnames
  if (hostnames && typeof hostnames.length === "number" && hostnames.length > 0) {
    var index = Math.floor(Math.random() * hostnames.length)
    return String(hostnames[index] || hostnames[0] || "")
  }
  return String(city.hostname || "")
}

function locationLabel(city, country) {
  var cityName = String(city || "").trim()
  var countryName = String(country || "").trim()
  if (cityName !== "" && countryName !== "") return cityName + ", " + countryName
  return cityName || countryName || "No server selected"
}

function matchesCurrent(city, countryCode, cityName) {
  if (!city) return false
  var code = String(countryCode || "").toLowerCase()
  var name = String(cityName || "").toLowerCase()
  if (code !== "" && String(city.countryCode || "").toLowerCase() === code) {
    if (name === "") return true
    var cityLabel = String(city.city || "").toLowerCase()
    if (cityLabel === name) return true
    // Status often uses "Chicago, IL" while the catalog is "Chicago, IL" or
    // a shorter "Bucharest" — accept either direction of prefix match.
    if (name.indexOf(cityLabel) === 0 || cityLabel.indexOf(name) === 0) return true
  }
  return false
}

function findCurrentCity(cities, countryCode, cityName) {
  var source = Array.isArray(cities) ? cities : []
  for (var i = 0; i < source.length; i++) {
    if (matchesCurrent(source[i], countryCode, cityName)) return source[i]
  }
  return null
}

if (typeof module !== "undefined") {
  module.exports = {
    field: field,
    parseStatus: parseStatus,
    cityId: cityId,
    parseServers: parseServers,
    filterCities: filterCities,
    pickHostname: pickHostname,
    locationLabel: locationLabel,
    matchesCurrent: matchesCurrent,
    findCurrentCity: findCurrentCity
  }
}
