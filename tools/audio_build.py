"""Generate game audio with ElevenLabs from audio/catalog.yaml.

Each sound is generated once and locked in audio.lock.json. Rebuilding only
creates sounds that don't exist yet — approved sounds are never re-rolled.

    py tools/audio_build.py                   generate missing sfx
    py tools/audio_build.py --music           also generate missing music (uses more credits)
    py tools/audio_build.py --regen shoot     re-roll one sound (after editing its prompt)
    py tools/audio_build.py --check           verify files match the lock

API key: ELEVENLABS_API_KEY environment variable (user-level on Windows).
"""
import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

import requests
import yaml

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "audio" / "catalog.yaml"
LOCK_PATH = ROOT / "audio.lock.json"
OUT = ROOT / "game" / "assets"
API = "https://api.elevenlabs.io/v1"


def api_key():
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key and sys.platform == "win32":
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
                key = winreg.QueryValueEx(k, "ELEVENLABS_API_KEY")[0]
        except OSError:
            pass
    if not key:
        sys.exit("ELEVENLABS_API_KEY is not set.")
    return key


def sha(data):
    return hashlib.sha256(data).hexdigest()


def spec_hash(entry):
    return sha(json.dumps(entry, sort_keys=True).encode())


def generate(kind, entry, key):
    headers = {"xi-api-key": key, "Content-Type": "application/json"}
    if kind == "sfx":
        body = {"text": entry["prompt"], "duration_seconds": entry.get("duration"),
                "prompt_influence": entry.get("prompt_influence", 0.6)}
        r = requests.post(f"{API}/sound-generation", headers=headers, json=body, timeout=120)
    else:
        body = {"prompt": entry["prompt"], "music_length_ms": int(entry.get("duration", 30) * 1000)}
        r = requests.post(f"{API}/music", headers=headers, json=body, timeout=600)
    if r.status_code != 200:
        raise RuntimeError(f"HTTP {r.status_code}: {r.text[:300]}")
    return r.content


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--music", action="store_true")
    ap.add_argument("--regen", action="append", default=[])
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    catalog = yaml.safe_load(CATALOG.read_text(encoding="utf-8"))
    lock = json.loads(LOCK_PATH.read_text()) if LOCK_PATH.exists() else {}

    if args.check:
        bad = []
        for lid, entry in lock.items():
            path = ROOT / entry["file"]
            if not path.exists() or sha(path.read_bytes()) != entry["file_sha"]:
                bad.append(lid)
        sys.exit("CHECK FAILED: " + ", ".join(bad)) if bad else print(f"OK - {len(lock)} sounds match lock.")
        return

    key = None
    failed = []
    for kind, entries in catalog.items():
        if kind == "music" and not args.music:
            continue
        for name, entry in entries.items():
            lid = f"{kind}/{name}"
            path = OUT / kind / f"{name}.mp3"
            locked = lock.get(lid)
            if locked and path.exists() and name not in args.regen:
                if locked["spec_sha"] != spec_hash(entry):
                    print(f"  ! {lid}: prompt changed but sound is locked — run with --regen {name} to re-roll")
                continue
            key = key or api_key()
            print(f"  generating {lid} ...", flush=True)
            try:
                data = generate(kind, entry, key)
            except Exception as err:  # keep going; report at the end
                print(f"    failed: {err}")
                failed.append(lid)
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            lock[lid] = {"file": path.relative_to(ROOT).as_posix(), "file_sha": sha(data), "spec_sha": spec_hash(entry)}
            LOCK_PATH.write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n")
    print(f"Done. {len(lock)} sounds locked." + (f" Failed: {', '.join(failed)}" if failed else ""))
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
