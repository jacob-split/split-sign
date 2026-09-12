#!/usr/bin/env python3
"""Nonproduction fixtures; never load a user's configuration or credentials."""
from pathlib import Path
import hashlib
import importlib.util
import os
import subprocess
import tempfile
import unittest

DIRECTORY=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('cloud_policy',DIRECTORY/'cloud-policy.py')
policy=importlib.util.module_from_spec(spec);spec.loader.exec_module(policy)

class CloudPolicyTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='cloud-policy-fixture-')
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.source=self.root/'repo/.codex';self.source.mkdir(parents=True)
        (self.source/'cloud-global.md').write_text('# Deliberate Cloud policy\nReviews install nothing; drafts remain unsent.\n')
        self.home=self.root/'home/.codex';self.home.mkdir(parents=True)

    def test_preserves_configuration_authentication_and_scope(self):
        config='model = "fixture-model"\n[model_providers.fixture]\nname = "test"\n[custom]\nkeep = true\n'
        (self.home/'config.toml').write_text(config)
        (self.home/'auth.json').write_text('fixture-auth-sentinel')
        (self.home/'AGENTS.md').write_text('# Owner policy\nKeep my directive.\n')
        skills=self.source.parent/'.agents/skills/local';skills.mkdir(parents=True)
        (skills/'SKILL.md').write_text('fixture repo skill')
        result=policy.install(self.source,self.home)
        first=(self.home/'AGENTS.md').read_bytes()
        policy.install(self.source,self.home)
        self.assertEqual(first,(self.home/'AGENTS.md').read_bytes())
        self.assertIn('Keep my directive.',first.decode())
        self.assertEqual(config,(self.home/'config.toml').read_text())
        self.assertEqual('fixture-auth-sentinel',(self.home/'auth.json').read_text())
        self.assertFalse((self.home/'skills').exists())
        self.assertFalse((self.home.parent/'.agents').exists())
        self.assertTrue(result['existing_config_preserved'])

    def test_migrates_only_known_accidental_global_copy(self):
        old='# Old repository manual\nRepository-only instructions.\n'
        (self.source/'cloud-legacy-agents.sha256').write_text(hashlib.sha256(old.encode()).hexdigest())
        (self.home/'AGENTS.md').write_text(old)
        result=policy.install(self.source,self.home)
        self.assertTrue(result['migrated_legacy_global'])
        self.assertNotIn('Repository-only',(self.home/'AGENTS.md').read_text())
        self.assertEqual(old,next((self.home/'.migration-recovery').glob('*.md')).read_text())

    def test_invalid_config_is_preserved_without_partial_policy_write(self):
        (self.home/'config.toml').write_text('not valid toml')
        with self.assertRaises(Exception):policy.install(self.source,self.home)
        self.assertFalse((self.home/'AGENTS.md').exists())
        self.assertEqual('not valid toml',(self.home/'config.toml').read_text())

    def test_shell_entrypoint_uses_disposable_home(self):
        env={**os.environ,'HOME':str(self.home.parent),'CODEX_HOME':str(self.home)}
        result=subprocess.run(['bash',str(DIRECTORY/'cloud-setup.sh')],env=env,capture_output=True,text=True)
        self.assertEqual(0,result.returncode,result.stderr)
        self.assertIn('split-cloud-policy:start',(self.home/'AGENTS.md').read_text())
        self.assertFalse((self.home/'skills').exists())

if __name__=='__main__':unittest.main()
