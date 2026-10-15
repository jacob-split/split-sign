#!/usr/bin/env python3
"""Run request specs in labelled disposable containers, never production data.

--smoke checks the real PostgreSQL path and fixture lifecycle without building
the Rails test dependencies. Full runs preserve the RSpec exit status.
"""
import argparse
import json
import pathlib
import subprocess
import time
import uuid

LABELS = {'split.watch.test': 'isolated', 'split.test.owner': 'split-sign'}


def docker(*args, check=True):
    return subprocess.run(['docker', *args], check=check, text=True,
                          capture_output=True, timeout=60).stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--smoke', action='store_true')
    parser.add_argument('specs', nargs='*', default=['spec/requests/submissions_spec.rb:16'])
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    name = 'split-sign-test-' + uuid.uuid4().hex
    labels = [arg for key, value in LABELS.items() for arg in ('--label', key+'='+value)]
    owned = []
    network = None
    try:
        pg = docker('inspect', '--format', '{{.Image}}', 'split-target-docuseal-postgres')
        network = docker('network', 'create', *labels, name)
        db = docker('create', '--name', name+'-db', *labels, '--network', network,
                    '--network-alias', 'test-db', '--memory', '256m', '--cpus', '.5',
                    '--tmpfs', '/var/lib/postgresql/data',
                    '-e', 'POSTGRES_PASSWORD=fixture', '-e', 'POSTGRES_USER=fixture',
                    '-e', 'POSTGRES_DB=fixture', pg)
        owned.append(db)
        docker('start', db)
        deadline = time.monotonic()+30
        while True:
            try:
                assert docker('exec', db, 'psql', '-U', 'fixture', '-d', 'fixture',
                              '-Atqc', 'SELECT 1') == '1'
                break
            except (subprocess.CalledProcessError, AssertionError):
                if time.monotonic() >= deadline:
                    raise RuntimeError('Isolated PostgreSQL SELECT 1 did not pass') from None
                time.sleep(.5)
        if args.smoke:
            print(json.dumps({'passed': True, 'name': name+'-db', 'id': db,
                              'database': 'SELECT 1', 'labels': LABELS}))
            return 0
        image = docker('inspect', '--format', '{{.Image}}', 'split-target-docuseal-app-1')
        script = '''set -eu
cd /app
apk add --no-cache build-base git yaml-dev
cp -a /source/app /source/lib /source/spec /app/
cp /source/.rspec /app/.rspec
bundle config unset without
bundle install --jobs 1 --retry 1
bundle exec rails db:schema:load
exec bundle exec rspec "$@"
'''
        app = docker('create', '--name', name+'-app', *labels, '--network', network,
                     '--memory', '1536m', '--cpus', '1', '--user', 'root',
                     '-e', 'RAILS_ENV=test', '-e', 'BUNDLE_WITHOUT=development',
                     '-e', 'DATABASE_URL=postgresql://fixture:fixture@test-db/fixture',
                     '-e', 'SECRET_KEY_BASE=isolated-fixture-only',
                     '-v', str(root)+':/source:ro', '--entrypoint', 'sh', image,
                     '-c', script, 'request-specs', *args.specs)
        owned.append(app)
        subprocess.run(['docker', 'start', '-a', app], check=False)
        state = json.loads(docker('inspect', '--format', '{{json .State}}', app))
        if state.get('Status') != 'exited':
            raise RuntimeError('Test attachment ended before the container exited')
        return int(state['ExitCode'])
    finally:
        # Use captured IDs only; never delete a concurrent same-name replacement.
        # Stop gracefully before removal; if interrupted, the labels still keep
        # disposable failures owned by the test rather than production Watch.
        for cid in reversed(owned):
            docker('stop', '--time', '10', cid, check=False)
            docker('rm', cid, check=False)
        if network:
            docker('network', 'rm', network, check=False)


if __name__ == '__main__':
    raise SystemExit(main())
