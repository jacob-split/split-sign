#!/usr/bin/env python3
"""Export the owner Signature API, preserving native schemas and all routed API actions."""
import copy,hashlib,json,pathlib,sys
root=pathlib.Path(__file__).resolve().parents[1]
doc=json.loads((root/'docs/openapi.json').read_text())
doc['openapi']='3.1.0'
doc['info']['title']='Split Signature complete owner API'
doc['servers']=[{'url':'https://sign.split-llc.com'}]
doc['paths']={'/api'+p:copy.deepcopy(v) for p,v in doc['paths'].items()}
obj=lambda props={},required=[]:{'type':'object','properties':props,'additionalProperties':True,**({'required':required} if required else {})}
extras=[
 ('get','/api/user','getCurrentUser',None),
 ('post','/api/attachments','createAttachment',obj({'submitter_slug':{'type':'string'},'type':{'type':'string'},'file':obj({'base64':{'type':'string'},'filename':{'type':'string'},'contentType':{'type':'string'}},['base64','filename'])},['submitter_slug','file'])),
 ('post','/api/submitter_email_clicks','recordSubmitterEmailClick',obj({'submitter_slug':{'type':'string'}},['submitter_slug'])),
 ('post','/api/submitter_form_views','recordSubmitterFormView',obj({'submitter_slug':{'type':'string'}},['submitter_slug'])),
 ('post','/api/submissions/{submission_id}/audit_events','createSubmissionAuditEvent',obj({'event_type':{'type':'string','enum':['send_2fa_sms','phone_verified','complete_verification']},'submitter_id':{'type':'integer'},'data':{'type':'object','additionalProperties':True},'event_timestamp':{'type':'string'}},['event_type'])),
 ('post','/api/submissions/init','initializeSubmission',None),
 ('post','/api/templates','createTemplate',None),
 ('get','/api/templates/{template_id}/submissions','getTemplateSubmissions',None),
 ('post','/api/templates/{template_id}/submissions','createTemplateSubmission',None),
 ('post','/api/templates/doc','createTemplateFromDoc',None),
 ('post','/api/tools/merge','mergePdfFiles',obj({'files':{'type':'array','minItems':2,'items':{'type':'string', 'contentEncoding':'base64'}}},['files'])),
 ('post','/api/tools/verify','verifyPdfSignature',obj({'file':{'type':'string','contentEncoding':'base64'}},['file'])),
 ('get','/api/events/form/{type}','getFormEvents',None),
 ('get','/api/events/submission/{type}','getSubmissionEvents',None),
]
import re
for method,path,name,body in extras:
 parameters=[{'name':p,'in':'path','required':True,'schema':{'type':'string' if p=='type' else 'integer'}} for p in re.findall(r'{([^}]+)}',path)]
 if method=='get' and name!='getCurrentUser':
  parameters += [{'name':p,'in':'query','schema':{'type':'integer'}} for p in ['limit','after','before']]
 op={'operationId':name,'summary':re.sub(r'([a-z])([A-Z])',r'\1 \2',name),'description':'Existing Rails owner API. Native account authorization, object ownership and signing/SMS proof rules still apply. Audit evidence must come from the original provider; never manufacture verification events.','parameters':parameters,'responses':{'200':{'description':'Native owner response'}}}
 if method!='get':
  op['requestBody']={'required':True,'content':{'multipart/form-data' if name=='createAttachment' else 'application/json':{'schema':body or obj()}}}
 doc['paths'].setdefault(path,{})[method]=op
for path,item in doc['paths'].items():
 for method,op in item.items():
  if method not in ['get','post','put','patch','delete']:continue
  op['x-split-effect']='read' if method=='get' or op['operationId'] in ['verifyPdfSignature','mergePdfFiles'] else 'write'
  op['x-split-auth']={'scheme':'AuthToken','header':'X-Auth-Token','owner':'existing Signature account','signingProof':'Existing native SMS and signing proof enforcement is authoritative.'}
  op['security']=[{'AuthToken':[]}]
  if op['operationId'] in ['createAttachment','recordSubmitterEmailClick','recordSubmitterFormView']:
   op['security']=[]
   op['x-split-auth']={'scheme':'native_submitter_slug','owner':'exact existing submitter','risk':'live_world'}
# Explicit API routes are part of the reviewed contract; route changes force regeneration.
sources=[root/'config/routes.rb',root/'docs/openapi.json',root/'lib/split_agent_contract.rb',root/'lib/submissions/serialize_for_api.rb',root/'lib/submitters/serialize_for_api.rb',*sorted((root/'app/controllers/api').glob('*.rb'))]
doc['x-split-owner-sources']=[{'path':str(p.relative_to(root)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sources]
doc['x-split-sdk']={'package':'@split/sdk','namespace':'signature','transport':'existing authenticated owner HTTP API','retry':'never','coverage':'36 distinct method/path operations; source-backed schemas from native API docs plus routed owner extensions. Unknown extension fields remain owner-validated.'}
text=json.dumps(doc,indent=2)+'\n'
out=root/'contracts/hq-api.openapi.json'
if '--check' in sys.argv:
 assert out.read_text()==text,'Signature API contract drift; regenerate and review.'
else:
 out.parent.mkdir(exist_ok=True);out.write_text(text)
print(json.dumps({'operations':sum(len(v) for v in doc['paths'].values()),'check':'--check' in sys.argv}))
