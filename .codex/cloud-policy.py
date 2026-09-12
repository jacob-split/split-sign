#!/usr/bin/env python3
"""Compose Cloud policy without copying a live home, credentials or repo skills."""
from __future__ import annotations
import argparse
import hashlib
import os
from pathlib import Path
import re
import tempfile
import tomllib

START = '<!-- split-cloud-policy:start -->'
END = '<!-- split-cloud-policy:end -->'


def atomic_write(path: Path, text: str, before: str | None) -> None:
    if (path.exists() and before is None) or (before is not None and path.read_text() != before):
        raise RuntimeError(f'Concurrent change preserved: {path}')
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    fd, name = tempfile.mkstemp(prefix='.cloud-policy-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            os.fchmod(out.fileno(), mode)
            out.write(text)
        os.replace(name, path)
    finally:
        if os.path.exists(name): os.unlink(name)


def install(directory: Path, home: Path) -> dict:
    policy = (directory / 'cloud-global.md').read_text().strip()
    home.mkdir(parents=True, exist_ok=True)
    config = home / 'config.toml'
    config_before = config.read_text() if config.exists() else None
    if config_before is not None:
        tomllib.loads(config_before)  # validate first; never replace unrelated settings
    legacy_file = directory / 'cloud-legacy-agents.sha256'
    legacy = set(legacy_file.read_text().split()) if legacy_file.exists() else set()
    agents = home / 'AGENTS.md'
    before = agents.read_text() if agents.exists() else None
    existing = before or ''
    migrated = bool(before and hashlib.sha256(before.encode()).hexdigest() in legacy)
    if migrated:
        recovery = home / '.migration-recovery'
        recovery.mkdir(mode=0o700, exist_ok=True)
        old = recovery / ('AGENTS-' + hashlib.sha256(before.encode()).hexdigest()[:16] + '.md')
        if not old.exists(): old.write_text(before)
        existing = ''  # only a reviewed accidental repository-to-global copy
    existing = re.sub(re.escape(START) + r'.*?' + re.escape(END) + r'\n?', '', existing, flags=re.S).rstrip()
    block = START + '\n' + policy + '\n' + END + '\n'
    after = (existing + '\n\n' if existing else '') + block
    if before != after: atomic_write(agents, after, before)
    if config_before is None:
        atomic_write(config, '# Cloud-specific settings belong here. Existing host settings are never copied.\n', None)
    return {'policy': 'current', 'migrated_legacy_global': migrated,
            'existing_config_preserved': config_before is None or config.read_text() == config_before,
            'skills': 'repository-scoped .agents/skills; no copies or implicit downloads'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    home = Path(os.environ.get('CODEX_HOME', str(Path.home()/'.codex'))).expanduser()
    import json
    print(json.dumps(install(args.directory, home)))
