#!/usr/bin/env python3
"""Build an immutable backend-only image from a reviewed commit and existing pinned base.
Reject dependency, asset or database changes: those require the full Dockerfile release.
"""
import argparse,hashlib,io,json,os,pathlib,subprocess,tarfile,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
def run(*args,**kwargs):
 return subprocess.run(args,check=True,text=True,capture_output=True,**kwargs).stdout.strip()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--base-image',required=True);p.add_argument('--revision',required=True);p.add_argument('--tag',required=True);a=p.parse_args()
 if len(a.revision)!=40 or any(c not in '0123456789abcdef' for c in a.revision):p.error('Use a full commit SHA.')
 if run('git','-C',str(ROOT),'rev-parse','HEAD')!=a.revision:raise ValueError('Source HEAD changed.')
 if run('git','-C',str(ROOT),'status','--porcelain'):raise ValueError('Commit owned changes before building.')
 base=json.loads(run('docker','image','inspect',a.base_image))[0]
 base_revision=base['Config']['Labels']['org.opencontainers.image.revision']
 changed=run('git','-C',str(ROOT),'diff','--name-only',base_revision,a.revision).splitlines()
 prefixes=('app/controllers/','app/models/','app/jobs/','app/mailers/','app/helpers/','app/services/','lib/','script/','native-plugin/','spec/','docs/','deploy/')
 allowed={'AGENTS.md','README.md'}
 unexpected=[f for f in changed if f not in allowed and not f.startswith(prefixes)]
 if unexpected:raise ValueError('Full build required for changed paths: '+', '.join(unexpected))
 base_tag='split-sign-build-base:'+base['Id'].split(':')[1][:20]
 subprocess.run(['docker','image','tag',base['Id'],base_tag],check=True)
 try:
  with tempfile.TemporaryDirectory(prefix='split-sign-backend-build-') as tmp:
   temp=pathlib.Path(tmp)
   archive=subprocess.run(['git','-C',str(ROOT),'archive',a.revision,'app','lib','script'],check=True,capture_output=True).stdout
   with tarfile.open(fileobj=io.BytesIO(archive)) as tar:tar.extractall(temp,filter='data')
   dockerfile='FROM '+base_tag+'\nWORKDIR /app\n'
   dockerfile+='COPY --chown=docuseal:docuseal app /app/app\nCOPY --chown=docuseal:docuseal lib /app/lib\nCOPY --chown=docuseal:docuseal script /app/script\n'
   dockerfile+='RUN /app/bin/bundle exec bootsnap precompile -j 1 --gemfile app/ lib/\n'
   dockerfile+='LABEL org.opencontainers.image.revision="'+a.revision+'" org.opencontainers.image.base.digest="'+base['Id']+'"\n'
   dockerfile+='WORKDIR '+base['Config']['WorkingDir']+'\n'
   (temp/'Dockerfile').write_text(dockerfile)
   subprocess.run(['docker','build','--pull=false','--network=none','--tag',a.tag,str(temp)],check=True)
  image=json.loads(run('docker','image','inspect',a.tag))[0]
  if image['Config']['Labels']['org.opencontainers.image.revision']!=a.revision:raise ValueError('Image revision mismatch.')
  expected=hashlib.sha256((ROOT/'app/controllers/api/submissions_controller.rb').read_bytes()).hexdigest()
  actual=run('docker','run','--rm','--network','none','--entrypoint','ruby',image['Id'],'-rdigest','-e','puts Digest::SHA256.file("/app/app/controllers/api/submissions_controller.rb").hexdigest')
  if actual!=expected:raise ValueError('Image controller bytes differ from reviewed source.')
  print(json.dumps({'ok':True,'revision':a.revision,'image':image['Id'],'tag':a.tag,'baseImage':base['Id'],'baseRevision':base_revision,'controllerSha256':actual,'databaseMigration':False}))
 finally:
  subprocess.run(['docker','image','rm',base_tag],capture_output=True)
if __name__=='__main__':main()
