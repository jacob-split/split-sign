# Align master input options with Portal's typed-only signing policy.
# Dry-run unless APPLY=1; never alters a submission snapshot.
require 'json'
require 'digest'
expected={
 1=>'8929bda2f86ac7f2d3c0da7ab3793e3fe52b8d0a21727f41d1c9d417697893ac',
 94=>'66830c1dbbdfe1df2fe42bc4fee2a39447cc94f0034845a196a6933507cea058',
 95=>'79c4c958428701c24950ec3578aadf475442cfdfb101dbc79070e9da2f209561'
}
snapshot=->{Digest::SHA256.hexdigest(Submission.where(template_id:expected.keys).order(:id).pluck(:id,:template_fields,:template_schema,:template_submitters).to_json)}
before=snapshot.call
changed=[]
Template.transaction do
 templates=expected.map{|id,hash| t=Template.lock.find(id);raise 'Master changed since review' unless Digest::SHA256.hexdigest(t.fields.to_json)==hash;t}
 templates.each do |t|
  raise 'Wrong master scope' unless t.preferences['merchant_id'].blank? && t.folder&.full_name=='Portal Agreements'
 end
 if ENV['APPLY']=='1'
  File.open(ENV.fetch('BACKUP_PATH'),File::WRONLY|File::CREAT|File::EXCL,0600){|f|f.write(JSON.pretty_generate(templates.map{|t|{id:t.id,fields:t.fields}}))}
 end
 templates.each do |t|
  fields=t.fields.deep_dup
  controls=fields.select{|f|%w[signature initials].include?(f['type'])}
  controls.each do |f|
   raise 'Unknown signer' unless t.submitters.any?{|s|s['uuid']==f['submitter_uuid']}
   f['preferences']=(f['preferences']||{}).merge('format'=>'typed')
  end
  t.update!(fields:fields) if ENV['APPLY']=='1'
  changed << {id:t.id,typed_controls:controls.size}
 end
 raise 'Submission snapshots changed' unless snapshot.call==before
end
puts JSON.generate({applied:ENV['APPLY']=='1',masters:changed,existing_submissions_unchanged:snapshot.call==before})
