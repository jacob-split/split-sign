#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Python 3.11+ supplies tomllib; no network, provider or model changes occur here.
exec python3 "$script_dir/cloud-policy.py" --directory "$script_dir"
