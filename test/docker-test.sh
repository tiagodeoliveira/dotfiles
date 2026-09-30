#!/bin/bash
# Runs setup.sh twice (idempotency) in a clean container per distro, then verify-tools.sh.
# Usage: test/docker-test.sh [ubuntu|amazonlinux ...]   (default: both)
# Env:   PLATFORM=linux/amd64  force CPU arch (default: host arch)
#        AS_ROOT=1             run as root with no sudo in the path
#        GITHUB_TOKEN          forwarded, avoids API rate limits
set -o pipefail
cd "$(dirname "$0")/.."

targets=("$@")
[[ ${#targets[@]} -eq 0 ]] && targets=(ubuntu amazonlinux)

platform_args=()
[[ -n "${PLATFORM:-}" ]] && platform_args=(--platform "$PLATFORM")
user_args=()
[[ -n "${AS_ROOT:-}" ]] && user_args=(--user root -e HOME=/root)

results=()
rc=0
for t in "${targets[@]}"; do
  image="dotfiles-test-$t"
  log="$(mktemp -t "dotfiles-$t.XXXXXX")"
  echo "======= [$t] building"
  if ! docker build "${platform_args[@]}" -f "test/Dockerfile.$t" -t "$image" .; then
    results+=("$t: BUILD FAILED")
    rc=1
    continue
  fi
  echo "======= [$t] running setup.sh x2 + verify (log: $log)"
  docker run --rm "${platform_args[@]}" "${user_args[@]}" ${GITHUB_TOKEN:+-e GITHUB_TOKEN} "$image" \
    bash -c 'bash setup.sh && bash setup.sh && bash test/verify-tools.sh' 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  if [[ $status -eq 0 ]] && grep -q "Setup done" "$log" && grep -q "verify-tools: OK" "$log"; then
    results+=("$t: PASS")
  else
    results+=("$t: FAIL (exit $status, log: $log)")
    rc=1
  fi
done
printf '%s\n' "${results[@]}"
exit $rc
