# Marketplace submission draft

Do not open the marketplace issue until the repository is public and you have
explicitly approved the text below.

## Listing metadata

- **Title:** `[Plugin]: Mozilla VPN`
- **Category:** `Widgets`
- **Tags:** `bar`, `quickshell`, `security`
- **Suggested tag:** `vpn` (optional; reviewers decide)
- **Repository:** `https://github.com/davydotcom/omarchy-mozilla-vpn-plugin`

## Issue body

```md
### Repository URL

https://github.com/davydotcom/omarchy-mozilla-vpn-plugin

### Category

Widgets

### Tags

bar, quickshell, security

### Suggest a missing tag

vpn

### Maintainer notes

Requires the Mozilla VPN client (`mozillavpn` on PATH) and an authenticated account. The widget shells out to mozillavpn status/servers/select/activate/deactivate/ui only — no sudo/root.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
```

## Submit command (after approval)

```sh
gh issue create \
  --repo HANCORE-linux/omarchy-plugin-marketplace \
  --title "[Plugin]: Mozilla VPN" \
  --body-file /tmp/omarchy-plugin-submission.md
```

Preview asset: root `preview.png` (fullscreen capture on empty workspace 5).
