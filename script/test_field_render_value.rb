require_relative '../lib/submissions/field_render_value'
raise unless Submissions::FieldRenderValue.call({'type'=>'date'}, '{{date}}').nil?
raise unless Submissions::FieldRenderValue.call({'type'=>'date'}, '2026-09-04') == '2026-09-04'
raise unless Submissions::FieldRenderValue.call({'type'=>'text'}, 'captured value') == 'captured value'
puts '3 PDF field rendering checks passed'
