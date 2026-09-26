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
   self.assertEqual(len(signing),9 if build==module.frpa_fields else 1)
   self.assertEqual(len({f["name"] for f in signing}),len(signing))
   for f in signing:
    self.assertEqual(f['preferences']['format'],'typed')
    self.assertTrue(f['required']);self.assertFalse(f['readonly'])
    self.assertEqual(f['submitter_uuid'],'merchant-role')
   for f in fields:
    if f['type'] not in ['signature','initials']:self.assertNotEqual(f['preferences'].get('format'),'typed')
 def test_signatures_stay_below_preceding_printed_rows(self):
  fields={f['name']:f for f in module.SIGNATURE_LAYOUT['fields']}
  # These boundaries are measured from the printed merchant and notice rows.
  for name,top_min,bottom_max in [('Merchant Signature',670,681),('Guarantor Signature - Agreement',734,744),('Merchant Signature - Bank Verification',410,421)]:
   rect=fields[name]['rect']
   self.assertGreaterEqual(792-rect[3],top_min,name)
   self.assertLessEqual(792-rect[1],bottom_max,name)
if __name__=='__main__':unittest.main()
