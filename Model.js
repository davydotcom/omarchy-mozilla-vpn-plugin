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

// Approximate city centers from Mullvad's public relay location catalog
// (Mozilla VPN uses the same infrastructure). Used only to pick a nearest
// default when the widget has no remembered city yet.
function cityCoords() {
  return {
    "al/tia": [41.327953, 19.819025],
    "ar/bue": [-34.474561, -58.664522],
    "at/vie": [48.210033, 16.363449],
    "au/adl": [-34.92123, 138.599503],
    "au/bne": [-27.471, 153.0234],
    "au/mel": [-37.815018, 144.946014],
    "au/per": [-31.953512, 115.857048],
    "au/syd": [-33.861481, 151.205475],
    "be/bru": [50.833333, 4.333333],
    "bg/sof": [42.683333, 23.316667],
    "br/for": [-3.732714, -38.526997],
    "br/sao": [-23.533773, -46.62529],
    "ca/mtr": [45.5053, -73.5525],
    "ca/tor": [43.666667, -79.416667],
    "ca/van": [49.25, -123.133333],
    "ca/yyc": [51.037007, -114.058315],
    "ch/zrh": [47.366667, 8.55],
    "cl/scl": [-33.448891, -70.669266],
    "co/bog": [4.624335, -74.063644],
    "cy/nic": [35.17025, 33.3587],
    "cz/prg": [50.083333, 14.466667],
    "de/ber": [52.520008, 13.404954],
    "de/dus": [51.233334, 6.783333],
    "de/fra": [50.110924, 8.682127],
    "dk/cph": [55.666667, 12.583333],
    "ee/tll": [59.436961, 24.753575],
    "es/bcn": [41.385063, 2.173404],
    "es/mad": [40.408566, -3.69222],
    "es/vlc": [39.466667, -0.375],
    "fi/hel": [60.192059, 24.945831],
    "fr/bod": [44.837788, -0.57918],
    "fr/mrs": [43.29648, 5.38107],
    "fr/par": [48.866667, 2.333333],
    "gb/glw": [55.86515, -4.25763],
    "gb/lon": [51.514125, -0.093689],
    "gb/mnc": [53.5, -2.216667],
    "gr/ath": [37.98381, 23.727539],
    "hk/hkg": [22.283333, 114.15],
    "hr/zag": [45.821, 15.973],
    "hu/bud": [47.5, 19.083333],
    "id/jpu": [-6.17511, 106.865036],
    "ie/dub": [53.35014, -6.266155],
    "il/tlv": [32.0853, 34.781768],
    "it/mil": [45.466667, 9.2],
    "it/pmo": [38.115688, 13.361267],
    "jp/osa": [34.672314, 135.484802],
    "jp/tyo": [35.685, 139.751389],
    "mx/qro": [20.592774, -100.390225],
    "my/kul": [3.139003, 101.686852],
    "ng/los": [6.524379, 3.379206],
    "nl/ams": [52.35, 4.916667],
    "no/osl": [59.916667, 10.75],
    "no/svg": [58.964432, 5.72625],
    "nz/akl": [-36.848461, 174.763336],
    "pe/lim": [-12.046373, -77.042755],
    "ph/mnl": [14.599512, 120.984222],
    "pl/waw": [52.25, 21.0],
    "pt/lis": [38.736946, -9.142685],
    "ro/buh": [44.433333, 26.1],
    "rs/beg": [44.787197, 20.457273],
    "se/got": [57.70887, 11.97456],
    "se/mma": [55.607075, 13.002716],
    "se/sto": [59.3289, 18.0649],
    "sg/sin": [1.293056, 103.855833],
    "si/lju": [46.0569, 14.5057],
    "sk/bts": [48.148598, 17.107748],
    "th/bkk": [13.756331, 100.501762],
    "tr/ist": [41.00824, 28.978359],
    "ua/iev": [50.4501, 30.5234],
    "us/atl": [33.753746, -84.38633],
    "us/bos": [42.361145, -71.057083],
    "us/chi": [41.881832, -87.623177],
    "us/dal": [32.89748, -97.040443],
    "us/den": [39.739236, -104.990251],
    "us/det": [42.331389, -83.045833],
    "us/hou": [29.749907, -95.358421],
    "us/lax": [34.052235, -118.243683],
    "us/mia": [25.761681, -80.191788],
    "us/mkc": [39.099789, -94.57856],
    "us/nyc": [40.73061, -73.935242],
    "us/phx": [33.448376, -112.074036],
    "us/qas": [39.043757, -77.487442],
    "us/rag": [35.787743, -78.644257],
    "us/sea": [47.608013, -122.335167],
    "us/sfo": [37.723459, -122.397957],
    "us/sjc": [37.338208, -121.886329],
    "us/slc": [40.758701, -111.876183],
    "us/txc": [26.203407, -98.230011],
    "us/uyk": [40.789543, -74.0565],
    "us/was": [38.889484, -77.035278],
    "za/jnb": [-26.195246, 28.034088]
  }
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

function toRadians(degrees) {
  return Number(degrees) * Math.PI / 180
}

function haversineKm(lat1, lon1, lat2, lon2) {
  var r = 6371
  var dLat = toRadians(lat2 - lat1)
  var dLon = toRadians(lon2 - lon1)
  var a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
    + Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2))
    * Math.sin(dLon / 2) * Math.sin(dLon / 2)
  return 2 * r * Math.asin(Math.sqrt(a))
}

function parseUserGeo(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false }

  try {
    var data = JSON.parse(text)
    var lat = NaN
    var lon = NaN
    if (data.loc && typeof data.loc === "string") {
      var parts = data.loc.split(",")
      lat = parseFloat(parts[0])
      lon = parseFloat(parts[1])
    }
    if (!isFinite(lat)) lat = parseFloat(data.latitude)
    if (!isFinite(lon)) lon = parseFloat(data.longitude)
    if (!isFinite(lat) || !isFinite(lon)) return { ok: false }

    return {
      ok: true,
      lat: lat,
      lon: lon,
      city: String(data.city || ""),
      region: String(data.region || ""),
      country: String(data.country || data.country_code || "").toLowerCase()
    }
  } catch (e) {
    return { ok: false }
  }
}

function findNearestCity(cities, lat, lon) {
  var source = Array.isArray(cities) ? cities : []
  var coords = cityCoords()
  var best = null
  var bestDistance = Infinity

  for (var i = 0; i < source.length; i++) {
    var city = source[i]
    if (!city || !city.id) continue
    var point = coords[String(city.id)]
    if (!point) continue
    var distance = haversineKm(lat, lon, point[0], point[1])
    if (distance < bestDistance) {
      bestDistance = distance
      best = city
    }
  }

  if (best) {
    return { city: best, distanceKm: bestDistance }
  }
  return null
}

function findCityInCountry(cities, countryCode, preferredCityName) {
  var code = String(countryCode || "").toLowerCase()
  var preferred = String(preferredCityName || "").toLowerCase()
  if (code === "") return null
  var source = Array.isArray(cities) ? cities : []
  var countryCities = []
  for (var i = 0; i < source.length; i++) {
    if (String(source[i].countryCode || "").toLowerCase() === code) countryCities.push(source[i])
  }
  if (countryCities.length === 0) return null
  if (preferred !== "") {
    for (var j = 0; j < countryCities.length; j++) {
      var label = String(countryCities[j].city || "").toLowerCase()
      if (label === preferred || label.indexOf(preferred) === 0 || preferred.indexOf(label) === 0) {
        return countryCities[j]
      }
    }
  }
  return countryCities[0]
}

function resolveDefaultCity(cities, geo) {
  if (!geo || geo.ok !== true) return null
  var nearest = findNearestCity(cities, geo.lat, geo.lon)
  if (nearest && nearest.city) return nearest.city
  return findCityInCountry(cities, geo.country, geo.city)
}

function parsePrivacy(raw) {
  var text = String(raw || "").trim()
  var empty = { ads: false, trackers: false, malware: false, flags: 0 }
  if (text === "") return empty
  try {
    var data = JSON.parse(text)
    return {
      ads: data.ads === true,
      trackers: data.trackers === true,
      malware: data.malware === true,
      flags: parseInt(String(data.flags || 0), 10) || 0
    }
  } catch (e) {
    return empty
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    field: field,
    parseStatus: parseStatus,
    cityId: cityId,
    cityCoords: cityCoords,
    parseServers: parseServers,
    filterCities: filterCities,
    pickHostname: pickHostname,
    locationLabel: locationLabel,
    matchesCurrent: matchesCurrent,
    findCurrentCity: findCurrentCity,
    haversineKm: haversineKm,
    parseUserGeo: parseUserGeo,
    findNearestCity: findNearestCity,
    findCityInCountry: findCityInCountry,
    resolveDefaultCity: resolveDefaultCity,
    parsePrivacy: parsePrivacy
  }
}
