# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# The canonical stub: every repo copies these bytes, so they must not drift.
STUB_SHA256=970130f7d55c07f5b86d4f5b6f392330427ff923eb34f93553656bcd4b893d9c
got=$(sha256sum "$STUB" | cut -d' ' -f1)
if [ "$got" = "$STUB_SHA256" ]; then
  pass "stub checksum"
else
  fail "stub checksum" "$STUB has sha256 $got, want $STUB_SHA256"
fi
check "stub is executable" test -x "$STUB"
check "resolver is executable" test -x "$R"
