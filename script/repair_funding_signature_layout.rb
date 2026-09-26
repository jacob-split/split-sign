require 'json'
require 'digest'
plan=JSON.parse(File.read(ENV.fetch('LAYOUT_PLAN')))
snapshot=->{Digest::SHA256.hexdigest(Submission.where(template_id:[94,95]).order(:id).pluck(:id,:template_fields,:template_schema,:template_submitters).to_json)}
before=snapshot.call
preview=ENV['PREVIEW']=='1'
Template.transaction do
 frpa=Template.lock.find(95);lod=Template.lock.find(94)
 raise 'FRPA master changed' unless Digest::SHA256.hexdigest(frpa.fields.to_json)=='f4f4114d7b3366cfa7a1e716f61c76956d1dfb5bc4a6e747d39f501a4dbdab6e'
 raise 'LOD master changed' unless Digest::SHA256.hexdigest(lod.fields.to_json)=='5e148f38e9413be8956b00682a9ad61b20fb1100d6ca52c1f53077b563cda53e'
 [frpa,lod].each{|t|raise 'Merchant-bound or wrong folder' unless t.preferences['merchant_id'].blank? && t.folder&.full_name=='Portal Agreements'}
 doc=frpa.documents.find{|a|frpa.schema.any?{|s|s['attachment_uuid']==a.uuid}}
 raise 'Source PDF changed' unless Digest::SHA256.hexdigest(doc.download)==plan['sourcePdfSha256']
 if ENV['APPLY']=='1'
  File.open(ENV.fetch('BACKUP_PATH'),File::WRONLY|File::CREAT|File::EXCL,0600){|f|f.write(JSON.pretty_generate([frpa,lod].map{|t|{id:t.id,fields:t.fields}}))}
 end
 fields=frpa.fields.deep_dup
 {'9adf6a74-5f57-4eb2-9fef-114d5e576c77'=>'Merchant Signature - Fee Appendix','a742c0e0-4d71-49a5-928e-77951ada5127'=>'Merchant Signature - Bank Verification'}.each do |uuid,name|
  field=fields.find{|f|f['uuid']==uuid};raise 'Unnamed field changed' unless field && field['name'].blank?
  field['name']=name
 end
 merchant_waiver=fields.find{|f|f['name']=='Guarantor Signature - Service Waiver'}.deep_dup
 merchant_waiver['uuid']='55751f2b-3661-4159-b794-d7084cf0b392'
 raise 'New field UUID collision' if fields.any?{|f|f['uuid']==merchant_waiver['uuid']}
 merchant_waiver['name']='Merchant Signature - Service Waiver';fields << merchant_waiver
 plan['fields'].each do |entry|
  matches=fields.select{|f|f['name']==entry['name']};raise 'Signing identity mismatch' unless matches.size==1
  f=matches.first;raise 'Invalid native signing control' unless f['type']=='signature' && f['required']==true && f['readonly']!=true && f.dig('preferences','format')=='typed' && frpa.submitters.any?{|s|s['uuid']==f['submitter_uuid']}
  x0,y0,x1,y1=entry['rect'].map(&:to_f)
  f['areas']=[f['areas'].first.merge('page'=>entry['page'],'x'=>x0/612,'y'=>(792-y1)/792,'w'=>(x1-x0)/612,'h'=>(y1-y0)/792)]
 end
 frpa.fields=fields
 fields=lod.fields.deep_dup
 field=fields.find{|f|f['name']=='Merchant Signature - Letter of Direction'}
 raise 'LOD field mismatch' unless field && field['type']=='signature'
 field['areas']=[field['areas'].first.merge('x'=>344.0/612,'y'=>687.0/792,'w'=>116.0/612,'h'=>18.0/792)]
 lod.fields=fields
 [frpa,lod].each(&:save!) if ENV['APPLY']=='1'
 if preview
  [frpa,lod].each do |t|
   submission=t.submissions.new(template_fields:t.fields,template_schema:t.schema,template_submitters:t.submitters,account:t.account)
   signer=Submitter.new(uuid:t.submitters.first['uuid'],name:'QA SIGNATURE',email:nil,account:t.account,submission:submission,values:{})
   image=Submitters::GenerateFontImage.call('QA Signature',font:'signature')
   attachment=Struct.new(:uuid,:created_at,:content_type,:byte_size) do
    attr_accessor :bytes
    def download;bytes;end
    def image?;true;end
   end.new('qa-layout-signature',Time.current,'image/png',image.bytesize)
   attachment.bytes=image
   signer.define_singleton_method(:attachments){[attachment]}
   signer.values=t.fields.select{|f|f['type']=='signature'}.to_h{|f|[f['uuid'],attachment.uuid]}
   index=t.documents.select{|a|t.schema.any?{|s|s['attachment_uuid']==a.uuid}}.to_h{|a|[a.uuid,HexaPDF::Document.new(io:StringIO.new(a.download))]}
   index.each_value{|pdf|Submissions::GenerateResultAttachments.maybe_flatten_pdf(pdf)}
   Submissions::GenerateResultAttachments.fill_submitter_fields(signer,t.account,index,with_signature_id:true,is_flatten:true,with_headings:true,with_signature_id_reason:true)
   index.each_value do |pdf|
    pdf.pages.each{|page|page.canvas(type: :overlay).font('Helvetica',size:10).fill_color('red').text('QA LAYOUT PREVIEW - NOT LEGALLY BINDING',at:[160,781])}
    pdf.write("/tmp/fleet-signature-review-20260926/funding-#{t.id}-layout-preview.pdf",validate:false)
   end
  end
 end
 raise 'Existing submissions changed' unless snapshot.call==before
 puts JSON.generate({applied:ENV['APPLY']=='1',preview:preview,frpa_signatures:frpa.fields.count{|f|f['type']=='signature'},lod_signatures:1,existing_submissions_unchanged:true})
end
