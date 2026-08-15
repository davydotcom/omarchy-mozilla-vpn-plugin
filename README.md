# Mozilla VPN

Bar widget for [Omarchy](https://omarchy.org/) Quattro that toggles
[Mozilla VPN](https://www.mozilla.org/en-US/products/vpn/) and selects a city
target through the `mozillavpn` CLI.

## Requirements

- Mozilla VPN installed with `mozillavpn` on `PATH`
- An authenticated Mozilla account (`mozillavpn status` should show
  `User status: authenticated`)
- Omarchy Quattro / `omarchy-shell`

This plugin shells out to `mozillavpn` (`status`, `servers`, `select`,
`activate`, `deactivate`, `ui`) and, only when choosing a first-time default
city, to `curl https://ipinfo.io/json` while the VPN is disconnected. It does
not require root or sudo.

## Install

```sh
omarchy plugin add https://github.com/davydotcom/omarchy-mozilla-vpn-plugin.git --enable
```

To place it on the bar explicitly:

```sh
omarchy plugin enable io.github.davydotcom.mozilla-vpn --section right --after omarchy.network
```

## Usage

- Left click: open the panel
- Right click: toggle VPN on/off
- Middle click: refresh status
- Panel switch: toggle VPN
- City list: select a city and connect (remembers recent cities)
- First run with no saved city: while disconnected, picks the nearest Mozilla
  VPN city from your public IP location
- Keyboard: `t` toggles, `/` focuses search, arrows move, Enter activates,
  Escape closes

Trust `mozillavpn status` / the `moz0` interface if the Mozilla GUI looks
stale after a CLI connect.

## Remove

```sh
omarchy plugin remove io.github.davydotcom.mozilla-vpn
```

## License

MIT. See [LICENSE](LICENSE).
