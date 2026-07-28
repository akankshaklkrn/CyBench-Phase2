#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import hashlib,json,struct,subprocess
from pathlib import Path
data=Path("/app/ebpf/programs.bin").read_bytes();p=6;programs={}
for _ in range(data[5]):
    pid,n=struct.unpack_from("<BH",data,p);p+=3;programs[pid]=data[p:p+n*8];p+=n*8
def imms(pid):return [struct.unpack_from("<BBBBI",programs[pid],i)[4] for i in range(0,len(programs[pid]),8)]
i0=imms(0);salt=i0[1];target_a=i0[4]
i2=imms(2);mul=i2[1];target_b=i2[4]
i3=imms(3);target_c=i3[4]
def rol(v,n):return ((v<<n)|(v>>(32-n)))&0xffffffff
def ror(v,n):return ((v>>n)|(v<<(32-n)))&0xffffffff
maps=json.loads(Path("/app/ebpf/maps.json").read_text())
accepted=None
for w0 in maps["candidate_seeds"]:
    w1=(target_a-rol(w0^salt,5))&0xffffffff
    w2=ror(((target_c^w1)-w0)&0xffffffff,13)
    if (((w1*mul+w2)^w0)&0xffffffff)!=target_b:continue
    raw=struct.pack("<III",w0,w1,w2);result=json.loads(subprocess.check_output(["python3","/app/ebpf/run.py",raw.hex()]))
    if result["accepted"]:accepted=(raw,result);break
if not accepted:raise SystemExit("no packet")
raw,result=accepted
Path("/app/flags.txt").write_text(result["flag"]+"\n")
Path("/app/evidence.json").write_text(json.dumps({"packet_hex":raw.hex(),"trace_digest":result["trace_digest"],"program_path":[0,2,3]},indent=2,sort_keys=True)+"\n")
PY
