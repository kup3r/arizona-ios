"""Download a public, hash-pinned IPA and inspect it as data. Never execute it."""
import urllib.request,urllib.error,pathlib,json,hashlib,zipfile,plistlib,struct,re,datetime
ROOT=pathlib.Path('build');ROOT.mkdir(exist_ok=True)
URL='https://resa-mp.com/api/download/ios/resa-ios-1.1.3-fbb34b5f4a9e.ipa'
EXPECTED='fbb34b5f4a9eee6871e6ec9ea1a2ace9864a85962dd8496884596fa517a8820b'
def macho(b):
 result={'magic':b[:4].hex()}
 if b[:4]!=bytes.fromhex('cffaedfe'):return result
 result['cpu_type']=struct.unpack_from('<I',b,4)[0]
 ncmds=struct.unpack_from('<I',b,16)[0];p=32;deps=[]
 if ncmds>2000:raise ValueError('Invalid Mach-O command count')
 for _ in range(ncmds):
  cmd,n=struct.unpack_from('<II',b,p)
  if n<8 or p+n>len(b):raise ValueError('Invalid load command')
  if cmd&0x7fffffff in (0xc,0x18,0x1f,0x23):
   off=struct.unpack_from('<I',b,p+8)[0]
   if off<n:deps.append(b[p+off:p+n].split(b'\0')[0].decode('utf-8','replace'))
  if cmd in (0x21,0x2c):result['cryptid']=struct.unpack_from('<I',b,p+16)[0]
  if cmd==0x32:result['build_version_fields']=list(struct.unpack_from('<III',b,p+8))
  p+=n
 result['dependencies']=deps
 strings=re.findall(rb'[\x20-\x7e]{5,}',b)
 patterns=('arizona','0.3.7','0.3.dl','raknet','samp-cef','omp-cef')
 result['string_matches']={k:[s[:240].decode('ascii') for s in strings if k.encode() in s.lower()][:30] for k in patterns}
 return result
def collect():
 result={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'url':URL,'expected_sha256':EXPECTED,'executed':False}
 try:
  p=ROOT/'resa.ipa';h=hashlib.sha256();size=0
  with urllib.request.urlopen(URL,timeout=30) as r,p.open('wb') as f:
   result['http_status']=r.status
   while True:
    chunk=r.read(1024*1024)
    if not chunk:break
    size+=len(chunk)
    if size>64*1024*1024:raise ValueError('IPA exceeds download limit')
    h.update(chunk);f.write(chunk)
  result.update({'size':size,'sha256':h.hexdigest()})
  if h.hexdigest()!=EXPECTED:raise ValueError('Published hash mismatch; file not inspected')
  with zipfile.ZipFile(p) as z:
   names=z.namelist();plists=[n for n in names if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist',n)]
   if len(plists)!=1:raise ValueError('Ambiguous app bundle')
   pi=z.getinfo(plists[0])
   if pi.file_size>2*1024*1024:raise ValueError('Oversize plist')
   info=plistlib.loads(z.read(pi));prefix=plists[0].rsplit('/',1)[0]+'/'
   result['bundle']={k:info.get(k) for k in ('CFBundleIdentifier','CFBundleShortVersionString','CFBundleVersion','MinimumOSVersion','CFBundleExecutable')}
   result['framework_files']=[n for n in names if '/Frameworks/' in n and n.endswith(('.dylib','/Info.plist'))]
   bi=z.getinfo(prefix+info['CFBundleExecutable'])
   if bi.file_size>128*1024*1024:raise ValueError('Oversize executable')
   with z.open(bi) as stream:b=stream.read(128*1024*1024+1)
   result['macho']=macho(b)
  result['status']='hash_verified_static_inspection'
 except urllib.error.HTTPError as e:result.update({'status':'http_error','http_status':e.code})
 except Exception as e:result.update({'status':'inspection_error','error':str(e)})
 (ROOT/'resa-static.json').write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf-8')
 print(json.dumps(result,ensure_ascii=False))
if __name__=='__main__':collect()
