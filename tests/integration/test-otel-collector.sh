#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/test-helpers.sh"

if ! command -v docker >/dev/null 2>&1; then
  skip "docker unavailable; skipping real OTel collector smoke"
  print_summary "$(basename "$0")"
  exit 0
fi

CONTAINER="arena-otel-test-$$"
cleanup_container() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup_container EXIT

docker run -d --rm --name "$CONTAINER" -p 4318:4318 -v "$ROOT_DIR/config/otel-collector.yml:/etc/otelcol/config.yaml:ro" otel/opentelemetry-collector:latest --config=/etc/otelcol/config.yaml >/dev/null
for _ in $(seq 1 30); do
  if docker logs "$CONTAINER" 2>&1 | grep -qi "Everything is ready\|Starting"; then
    break
  fi
  sleep 1
done

RUN_ID="otel-collector-test-$$"
(cd "$ROOT_DIR" && python3 scripts/arena-runtime.py harness-event otel.collector.test --phase test --run-id "$RUN_ID" --field ok=true >/dev/null)
output="$(cd "$ROOT_DIR" && python3 scripts/arena-runtime.py otel-push --run-dir "cache/runs/$RUN_ID" --endpoint http://127.0.0.1:4318/v1/traces --timeout 5)"
assert_json_valid "$output" "otel-push collector output is valid JSON"
status_code="$(echo "$output" | jq -r '.status_code')"
assert_eq "$status_code" "200" "otel collector accepts OTLP HTTP traces"

print_summary "$(basename "$0")"
