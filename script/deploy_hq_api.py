#!/usr/bin/env python3
"""Deploy only the reviewed HQ discovery overlay, preserving exact existing container config and data volumes."""
import argparse,datetime,http.client,json,os,pathlib,socket,subprocess,tempfile,time,urllib.request,shutil,hashlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
NAME='split-target-docuseal-app-1'
FILES=['lib/split_agent_contract.rb','contracts/hq-api.openapi.json','app/views/layouts/application.html.erb','public/openapi.json']
class Docker(http.client.HTTPConnection):
 def __init__(self):super().__init__('localhost',timeout=60)
 def connect(self):
  self.sock=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);self.sock.connect('/var/run/docker.sock')
def api(method,path,body=None):
 c=Docker()
 try:
  c.request(method,path,json.dumps(body) if body is not None else None,{'Content-Type':'application/json'})
  r=c.getresponse();raw=r.read()
  if r.status>=400:raise RuntimeError('Docker operation failed: HTTP '+str(r.status))
  return json.loads(raw) if raw else None
 finally:c.close()
def run(*args,cwd=None):
 return subprocess.run(args,cwd=cwd,check=True,capture_output=True,text=True).stdout.strip()
def private_write(path,data):
 fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
 with os.fdopen(fd,'w') as f:json.dump(data,f)
def endpoints(state):
 return {name:{k:v for k,v in value.items() if k in ['IPAMConfig','Links','Aliases','DriverOpts','GwPriority'] and v is not None} for name,value in state['NetworkSettings']['Networks'].items()}
def config(state,image):
 body=dict(state['Config']);body['Image']=image
 body['HostConfig']=state['HostConfig']
 body['NetworkingConfig']={'EndpointsConfig':endpoints(state)}
 return body
def inspect(name):return api('GET','/containers/'+name+'/json')
def probe(address):
 url='http://'+address+':3000/api/agent/openapi.json'
 deadline=time.monotonic()+100
 while time.monotonic()<deadline:
  try:
   with urllib.request.urlopen(url,timeout=5) as r:doc=json.load(r)
   count=sum(1 for p,v in doc['paths'].items() if p.startswith('/api/') and not p.startswith('/api/agent/') for m in v if m in ['get','post','put','patch','delete'])
   if count==36:return count
  except Exception:pass
  time.sleep(2)
 raise RuntimeError('Published Signature contract did not pass health readback.')
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--revision',required=True);args=p.parse_args()
 revision=run('git','rev-parse','HEAD',cwd=ROOT)
 if args.revision!=revision or len(revision)!=40:raise RuntimeError('Use current full reviewed source revision.')
 if run('git','status','--porcelain',cwd=ROOT):raise RuntimeError('Source is dirty; no deployment started.')
 run('python3','script/export_hq_api.py','--check',cwd=ROOT);run('ruby','script/test_hq_api.rb',cwd=ROOT)
 state=inspect(NAME)
 if not state['State']['Running']:raise RuntimeError('Expected existing running Signature container.')
 if not any(m.get('Name')=='split-target-docuseal-data' and m['Destination']=='/data/docuseal' for m in state['Mounts']):raise RuntimeError('Data volume identity changed.')
 stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
 recovery=pathlib.Path.home()/'.local/state/split-sign/hq-releases'/stamp;recovery.mkdir(parents=True,mode=0o700)
 private_write(recovery/'original.json',state)
 base='split-sign:hq-recovery-'+stamp.lower();image='split-sign:hq-'+revision[:12]
 # Snapshot retains earlier runtime overlays; mounted document/database data is excluded.
 run('docker','commit','--pause=false',state['Id'],base)
 with tempfile.TemporaryDirectory(prefix='split-sign-hq-',dir=pathlib.Path.home()/'.cache') as tmp:
  context=pathlib.Path(tmp)
  for relative in FILES:
   dest=context/relative;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/relative,dest)
  dockerfile='FROM '+base+'\n'+''.join('COPY '+f+' /app/'+f+'\n' for f in FILES)+'LABEL org.opencontainers.image.revision="'+revision+'"\n'
  (context/'Dockerfile').write_text(dockerfile)
  run('docker','build','-t',image,str(context))
 private_write(recovery/'images.json',{'base':base,'image':image,'revision':revision})
 if inspect(NAME)['Id']!=state['Id']:raise RuntimeError('Concurrent runtime change; new image retained, no switch.')
 oldname=NAME+'-hq-rollback-'+stamp.lower();created=None;renamed=False;disconnected=[]
 try:
  api('POST','/containers/'+state['Id']+'/stop?t=30')
  for network in endpoints(state):
   api('POST','/networks/'+network+'/disconnect',{'Container':state['Id'],'Force':False});disconnected.append(network)
  run('docker','rename',state['Id'],oldname);renamed=True
  created=api('POST','/containers/create?name='+NAME,config(state,image))['Id']
  api('POST','/containers/'+created+'/start');count=probe(state['NetworkSettings']['Networks']['split-target-docuseal-data']['IPAddress'])
  live=inspect(NAME)
  if live['Id']!=created or live['Config']['Image']!=image:raise RuntimeError('Runtime revision changed during readback.')
  if sorted((m.get('Name'),m['Destination']) for m in live['Mounts'])!=sorted((m.get('Name'),m['Destination']) for m in state['Mounts']):raise RuntimeError('Mounted data identity changed.')
  expected={f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in FILES}
  actual={line.split()[1].removeprefix('/app/'):line.split()[0] for line in run('docker','exec',created,'sha256sum',*['/app/'+f for f in FILES]).splitlines()}
  if actual!=expected:raise RuntimeError('Runtime overlay file hashes differ from source.')
  result={'sourceHashes':expected,'published':True,'revision':revision,'image':image,'baseImage':base,'containerId':created,'nativeOperations':count,'recovery':str(recovery),'sourceFiles':FILES}
  private_write(recovery/'receipt.json',result)
  # Recovery is the private original config plus immutable filesystem snapshot; do not leave a stale monitored container.
  api('DELETE','/containers/'+state['Id'])
  print(json.dumps(result))
 except Exception:
  if created:
   try:api('POST','/containers/'+created+'/stop?t=20')
   except Exception:pass
   api('DELETE','/containers/'+created)
  if renamed:run('docker','rename',state['Id'],NAME)
  for network in disconnected:api('POST','/networks/'+network+'/connect',{'Container':state['Id'],'EndpointConfig':endpoints(state)[network]})
  api('POST','/containers/'+state['Id']+'/start')
  raise
if __name__=='__main__':main()
