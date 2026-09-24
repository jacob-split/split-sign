# Run with `bin/rails runner scripts/repair_payzli_owner_two.rb` in the Split
# Signature runtime. This adds only the missing owner-2 fields on the verified
# three-page Payzli source PDF; existing submissions are not rewritten.
require 'digest'

template = Template.find(136)
expected_pdf = '997629392b0bb3947cae2c046462077620a3d76cbd9b34321188b94b48d88f5e'
raise 'Unexpected Payzli PDF' unless Digest::SHA256.hexdigest(template.documents.first.blob.download) == expected_pdf
raise 'Unexpected Payzli master' unless template.name == 'Payzli MPA'

# Coordinates are normalized from the original AcroForm owner-2 widgets on
# page one. The source PDF has all thirteen cells, but this master omitted them.
widgets = [
  ['first_name', 'ad7e59be-7603-4877-a958-ce26943858f2', 0.517645, 0.698362, 0.208913, 0.020385],
  ['last_name', 'f4870d91-cb56-4c46-a77c-3ef9e20f2032', 0.735827, 0.697519, 0.211765, 0.021487],
  ['title', '61865f4a-77d8-45d1-958f-52994ea80035', 0.517645, 0.737740, 0.208913, 0.020936],
  ['email', 'e2acccb9-d1cb-4ce4-88cf-0a12f9e47f58', 0.734402, 0.737740, 0.213190, 0.021487],
  ['phone', 'a68b274d-428c-4aff-88ef-db05aafa8ab8', 0.520498, 0.777960, 0.132619, 0.022039],
  ['ownership_pct', '3cc4f86d-dccd-4b69-b63e-83fec54b1afd', 0.659180, 0.778650, 0.051158, 0.020523],
  ['dob', 'ea06bd26-4adf-47fe-b30a-4aef4a7bf3ea', 0.736186, 0.778513, 0.102673, 0.020662],
  ['ssn', 'ab9fc604-28d7-4305-91f4-72dc970c39d3', 0.846523, 0.777686, 0.099466, 0.023140],
  ['street', '613a0ff0-07aa-446e-bfd3-eba090aa3807', 0.517647, 0.816115, 0.207487, 0.021902],
  ['street2', 'd9060f58-293a-4ad3-8e6a-75e6ba432374', 0.735828, 0.815702, 0.210694, 0.021900],
  ['city', 'fd62bf4f-6767-44af-a47d-2ee18f97bca9', 0.516913, 0.852479, 0.209090, 0.022314],
  ['state', 'b2d16376-d994-4993-b006-f8100570cd05', 0.735294, 0.852893, 0.104278, 0.022313],
  ['zip', '36cef692-5d7a-442e-95af-0fef85c5a316', 0.845989, 0.854545, 0.100000, 0.019834]
].freeze

fields = template.fields
existing = fields.map { |field| field['uuid'] }
new_uuids = widgets.map { |widget| widget[1] }
if new_uuids.all? { |uuid| existing.include?(uuid) }
  raise 'Partial owner-2 repair' unless new_uuids.all? { |uuid| existing.count(uuid) == 1 }
  raise 'Owner-1 optional fields require review' unless [4, 11, 12, 13].all? { |index| fields[index]['required'] == false }
  puts 'payzli_owner_two=already_present'
  exit
end
raise 'Partial owner-2 repair' if new_uuids.any? { |uuid| existing.include?(uuid) }
raise "Unexpected Payzli field count #{fields.length}" unless fields.length == 154
submitter_uuid = fields.first.fetch('submitter_uuid')
attachment_uuid = fields.first.fetch('areas').first.fetch('attachment_uuid')

added = widgets.map do |key, uuid, x, y, w, h|
  {
    'uuid' => uuid,
    'submitter_uuid' => submitter_uuid,
    'name' => "payzli_owner2_#{key}",
    'type' => 'text',
    'required' => false,
    'readonly' => false,
    'preferences' => { 'data_path' => "beneficialOwner.1.#{key}" },
    'areas' => [{ 'x' => x, 'y' => y, 'w' => w, 'h' => h, 'page' => 0, 'attachment_uuid' => attachment_uuid }]
  }
end
for index in [4, 11, 12, 13]
  fields[index] = { **fields[index], 'required' => false }
end
template.update!(fields: fields + added)
raise 'Owner-2 repair verification failed' unless template.reload.fields.length == 167
puts 'payzli_owner_two=added fields=13'
