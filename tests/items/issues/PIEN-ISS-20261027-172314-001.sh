#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

env -u PI_EN_INSIDE_SANDBOX bash "$repo_root/tests/pien-dispatcher.sh"
printf 'PIEN-ISS-20261027-172314-001 passed\n'
