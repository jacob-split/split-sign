import contextlib
import io
import json
import unittest
from unittest import mock

import isolated_agent_request_test as runner


class FixtureRunnerTest(unittest.TestCase):
    def run_fixture(self, smoke=False, exit_code=0, attach_error=False):
        calls=[]
        def docker(*args, **kwargs):
            calls.append(args)
            if args[:2] == ('network','create'):return 'owned-network-id'
            if args[0] == 'create':return 'owned-db-id' if '-db' in args[2] else 'owned-app-id'
            if args[0] == 'exec':return '1'
            if args[:3] == ('inspect','--format','{{json .State}}'):
                return json.dumps({'Status':'exited','ExitCode':exit_code})
            return 'image-id'
        with mock.patch.object(runner,'docker',side_effect=docker), \
             mock.patch.object(runner.subprocess,'run',side_effect=OSError('attachment failed') if attach_error else None), \
             mock.patch('sys.argv',['fixture']+(['--smoke'] if smoke else [])), \
             contextlib.redirect_stdout(io.StringIO()):
            if attach_error:
                with self.assertRaises(OSError):runner.main()
                result=None
            else:result=runner.main()
        return result,calls

    def test_preserves_failed_spec_status_and_cleans_only_owned_ids(self):
        result,calls=self.run_fixture(exit_code=7)
        self.assertEqual(result,7)
        self.assertEqual([c for c in calls if c[0]=='rm'],
                         [('rm','owned-app-id'),('rm','owned-db-id')])
        for c in calls:
            if c[0]=='create':
                self.assertIn('split.watch.test=isolated',c)
                self.assertIn('split.test.owner=split-sign',c)
                self.assertRegex(c[2],r'^split-sign-test-[a-f0-9]{32}-(db|app)$')
        self.assertEqual(calls[-1],('network','rm','owned-network-id'))

    def test_smoke_checks_database_without_creating_app(self):
        result,calls=self.run_fixture(smoke=True)
        self.assertEqual(result,0)
        self.assertEqual(sum(c[0]=='create' for c in calls),1)
        self.assertTrue(any(c[0]=='exec' and c[-1]=='SELECT 1' for c in calls))

    def test_attachment_error_still_cleans_owned_ids(self):
        _,calls=self.run_fixture(attach_error=True)
        self.assertEqual([c for c in calls if c[0]=='rm'],
                         [('rm','owned-app-id'),('rm','owned-db-id')])


if __name__ == '__main__':
    unittest.main()
