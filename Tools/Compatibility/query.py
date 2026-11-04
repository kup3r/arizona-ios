"""Bounded, login-free SA-MP information queries. No game client is executed."""
import socket,struct,time,json,pathlib,datetime,concurrent.futures
SERVERS=json.loads(pathlib.Path(__file__).with_name('targets.json').read_text())
class Reader:
 def __init__(self,b):self.b=b;self.p=0
 def take(self,n):
  if n<0 or self.p+n>len(self.b):raise ValueError('Truncated response')
  r=self.b[self.p:self.p+n];self.p+=n;return r
 def number(self,fmt):return struct.unpack(fmt,self.take(struct.calcsize(fmt)))[0]
 def text(self,n):return self.take(n).decode('cp1251','replace')
def decode(op,payload):
 r=Reader(payload)
 if op=='i':
  result={'password':r.number('<B'),'players':r.number('<H'),'max_players':r.number('<H')}
  for key in ('hostname','gamemode','language'):
   n=r.number('<I')
   if n>4096:raise ValueError('Oversize string')
   result[key]=r.text(n)
 elif op=='r':
  n=r.number('<H')
  if n>128:raise ValueError('Too many rules')
  result={}
  for _ in range(n):key=r.text(r.number('<B'));value=r.text(r.number('<B'));result[key]=value
 elif op=='p':result={'echo':r.take(4).hex()}
 else:raise ValueError('Unsupported query')
 if r.p!=len(payload):raise ValueError('Trailing response data')
 return result
def check(server):
 host=server['ip'];port=server['port'];result={'host':host,'port':port,'queries':[]}
 try:ip=socket.gethostbyname(host);result['resolved_ipv4']=ip
 except OSError as e:result['dns_error']=str(e);return result
 for op in ('i','r','p'):
  header=b'SAMP'+socket.inet_aton(ip)+struct.pack('<H',port)+op.encode('ascii')
  request=header+(b'AZ01' if op=='p' else b'');item={'opcode':op,'request_hex':request.hex()};start=time.monotonic()
  with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
   sock.settimeout(2.5)
   try:
    sock.sendto(request,(ip,port));data,source=sock.recvfrom(16384)
    item.update({'latency_ms':round((time.monotonic()-start)*1000,2),'source':list(source),'response_bytes':len(data),'response_hex':data.hex()})
    if source!=(ip,port) or not data.startswith(header):raise ValueError('Unexpected response source/header')
    item['decoded']=decode(op,data[11:]);item['status']='valid_response'
   except socket.timeout:item['status']='timeout'
   except Exception as e:item['status']='error';item['error']=str(e)
  result['queries'].append(item)
  time.sleep(.25)
 return result
if __name__=='__main__':
 # Check parsing with known, self-generated fixtures before using live replies.
 fields=[b'Test',b'RP',b'Russian']
 fixture=struct.pack('<BHH',0,2,100)+b''.join(struct.pack('<I',len(x))+x for x in fields)
 assert decode('i',fixture)['players']==2
 assert decode('r',b'\x01\x00\x07version\x053.7-R')['version']=='3.7-R'
 results=list(concurrent.futures.ThreadPoolExecutor(max_workers=3).map(check,SERVERS))
 out={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'method':'One i, r and p UDP query per APK-listed host; no retries/login/RCON/client list','results':results}
 pathlib.Path('build/compatibility-query.json').write_text(json.dumps(out,indent=2,ensure_ascii=False),encoding='utf-8')
 for r in results:print(json.dumps(r,ensure_ascii=False))
