#!/usr/bin/env python3
"""Read/toggle Mozilla VPN DNS privacy flags in ~/.config/mozilla/vpn.moz.

Flags match SettingsHolder::DNSProviderFlags in the Mozilla VPN client:
  BlockAds=0x02, BlockTrackers=0x04, BlockMalware=0x08
"""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
from pathlib import Path

SETTINGS_PATH = Path.home() / ".config/mozilla/vpn.moz"
ADS = 0x02
TRACKERS = 0x04
MALWARE = 0x08
CUSTOM = 0x01
BLOCK_MASK = ADS | TRACKERS | MALWARE
BITS = {"ads": ADS, "trackers": TRACKERS, "malware": MALWARE}


def split_file(raw: bytes) -> tuple[bytes, str]:
    brace = raw.find(b"{")
    if brace < 0:
        raise ValueError("Mozilla VPN settings are not JSON")
    return raw[:brace], raw[brace:].decode("utf-8")


def read_flags(body: str) -> int:
    data = json.loads(body)
    try:
        return int(data.get("dnsProviderFlags") or 0)
    except (TypeError, ValueError):
        return 0


def state(flags: int) -> dict:
    bits = flags & BLOCK_MASK
    return {
        "ads": bool(bits & ADS),
        "trackers": bool(bits & TRACKERS),
        "malware": bool(bits & MALWARE),
        "flags": bits,
    }


def apply_toggle(flags: int, kind: str) -> int:
    bit = BITS[kind]
    flags &= ~CUSTOM
    if flags & bit:
        flags &= ~bit
    else:
        flags |= bit
    return flags & BLOCK_MASK


def write_flags(prefix: bytes, body: str, flags: int) -> None:
    if re.search(r'"dnsProviderFlags"\s*:', body):
        next_body = re.sub(
            r'"dnsProviderFlags"\s*:\s*-?\d+',
            f'"dnsProviderFlags":{flags}',
            body,
            count=1,
        )
    else:
        next_body = body.replace("{", f'{{"dnsProviderFlags":{flags},', 1)
    payload = prefix + next_body.encode("utf-8")
    directory = str(SETTINGS_PATH.parent)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".vpn.moz.")
    try:
        os.write(fd, payload)
        os.fsync(fd)
        os.close(fd)
        os.replace(tmp, SETTINGS_PATH)
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def print_state(flags: int) -> None:
    sys.stdout.write(json.dumps(state(flags), separators=(",", ":")) + "\n")


def main(argv: list[str]) -> int:
    cmd = argv[1] if len(argv) > 1 else "get"
    if cmd == "get":
        if not SETTINGS_PATH.exists():
            print_state(0)
            return 0
        _prefix, body = split_file(SETTINGS_PATH.read_bytes())
        print_state(read_flags(body))
        return 0

    if cmd == "toggle" and len(argv) >= 3:
        kind = argv[2]
        if kind not in BITS:
            sys.stderr.write("privacy.py: kind must be ads, trackers, or malware\n")
            return 2
        if not SETTINGS_PATH.exists():
            sys.stderr.write("privacy.py: Mozilla VPN settings file not found\n")
            return 1
        prefix, body = split_file(SETTINGS_PATH.read_bytes())
        flags = apply_toggle(read_flags(body), kind)
        write_flags(prefix, body, flags)
        print_state(flags)
        return 0

    sys.stderr.write("usage: privacy.py get | toggle ads|trackers|malware\n")
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
