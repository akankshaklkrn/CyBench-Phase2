#!/usr/bin/env python3
import hashlib,json,struct,sys
from pathlib import Path
OPS={1:"MOV",2:"XORI",3:"ADDR",4:"MULI",5:"ROLI",6:"JNEI",7:"TAIL",8:"XORR",9:"ADDI",10:"ACCEPT",11:"EXIT"}
def load():
    data=Path(__file__).with_name("programs.bin").read_bytes();p=6;programs={}
    for _ in range(data[5]):
        pid,n=struct.unpack_from("<BH",data,p);p+=3;programs[pid]=data[p:p+n*8];p+=n*8
    return programs,json.loads(Path(__file__).with_name("maps.json").read_text())
def run(raw):
    if len(raw)!=12:return None,[]
    regs=[0]*8;regs[1],regs[2],regs[3]=struct.unpack("<III",raw); programs,maps=load();pid=0;trace=[]
    for _ in range(100):
        code=programs[pid];pc=0
        while pc<len(code)//8:
            op,dst,src,off,imm=struct.unpack_from("<BBBBI",code,pc*8);trace.append([pid,pc,op,regs[dst]])
            if op==1:regs[dst]=regs[src]
            elif op==2:regs[dst]^=imm
            elif op==3:regs[dst]=(regs[dst]+regs[src])&0xffffffff
            elif op==4:regs[dst]=(regs[dst]*imm)&0xffffffff
            elif op==5:regs[dst]=((regs[dst]<<(imm&31))|(regs[dst]>>(32-(imm&31))))&0xffffffff
            elif op==6:
                if regs[dst]!=imm:pc+=off
            elif op==7:pid=int(maps["tail_calls"].get(str(imm),255));break
            elif op==8:regs[dst]^=regs[src]
            elif op==9:regs[dst]=(regs[dst]+imm)&0xffffffff
            elif op==10:return "CYBERBENCH{ebpf_"+hashlib.sha256(raw).hexdigest()[:16]+"}",trace
            elif op==11:return None,trace
            pc+=1
        else:return None,trace
        if pid not in programs:return None,trace
    return None,trace
if __name__=="__main__":
    raw=bytes.fromhex(sys.argv[1]);flag,trace=run(raw);print(json.dumps({"accepted":bool(flag),"flag":flag,"trace_digest":hashlib.sha256(json.dumps(trace,separators=(",",":")).encode()).hexdigest()}))
