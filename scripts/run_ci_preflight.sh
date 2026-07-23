#!/usr/bin/env bash
set -euo pipefail

run_module() {
  node scripts/test_version_consistency_contract.mjs
}

run_i18n() {
  python3 scripts/check_i18n_duplicates.py
}

run_v2() {
  node scripts/test_v1_decorator_inventory_contract.mjs
}

run_severe() {
  node scripts/test_error_classification_contract.mjs
  node scripts/test_cookie_roundtrip_contract.mjs
  node scripts/test_cookie_import_contract.mjs
  node scripts/test_remote_write_retry_contract.mjs
  node scripts/test_persistence_inventory_contract.mjs
  node scripts/test_public_clipboard_build_contract.mjs
  node scripts/test_local_only_incident_boundary_contract.mjs
}

case "${1:-all}" in
  all)
    run_module
    run_i18n
    run_v2
    run_severe
    ;;
  module)
    run_module
    ;;
  i18n)
    run_i18n
    ;;
  v2)
    run_v2
    ;;
  severe)
    run_severe
    ;;
  *)
    echo "usage: $0 [all|module|i18n|v2|severe]" >&2
    exit 2
    ;;
esac
