import importlib.util
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location('funding',Path(__file__).with_name('restore_funding_agreement_templates.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class SigningOptionTests(unittest.TestCase):
 def test_generated_funding_controls_use_native_typed_signature_option(self):
  for build in [module.frpa_fields,module.lod_fields]:
   fields=build('merchant-role','source-document')
   signing=[f for f in fields if f['type'] in ['signature','initials']]
   self.assertTrue(signing)
   for f in signing:
    self.assertEqual(f['preferences']['format'],'typed')
    self.assertTrue(f['required']);self.assertFalse(f['readonly'])
    self.assertEqual(f['submitter_uuid'],'merchant-role')
   for f in fields:
    if f['type'] not in ['signature','initials']:self.assertNotEqual(f['preferences'].get('format'),'typed')
if __name__=='__main__':unittest.main()
