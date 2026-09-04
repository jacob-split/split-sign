# frozen_string_literal: true

module Submissions
  module FieldRenderValue
    module_function

    # A preview must not print an unresolved signing-date macro or guess a date.
    def call(field, value)
      return nil if field['type'] == 'date' && value == '{{date}}'

      value
    end
  end
end
