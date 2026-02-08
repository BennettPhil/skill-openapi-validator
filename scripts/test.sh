#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="${SCRIPT_DIR}/validate.py"
TMPDIR_TEST=$(mktemp -d)
PASS=0
FAIL=0

cleanup() {
    rm -rf "$TMPDIR_TEST"
}
trap cleanup EXIT

pass_test() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail_test() {
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
    if [ -n "${2:-}" ]; then
        echo "        $2"
    fi
}

# Run validator and capture both output and exit code safely
run_validator() {
    set +e
    output=$(python3 "$VALIDATE" "$@" 2>&1)
    rc=$?
    set -e
}

echo "=== openapi-validator test suite ==="
echo ""

# ---------- Test 1: Valid minimal spec ----------
echo "Test 1: Valid minimal spec (no errors, no warnings)"
cat > "${TMPDIR_TEST}/valid.json" << 'SPECEOF'
{
  "openapi": "3.0.3",
  "info": {
    "title": "Test API",
    "description": "A test API",
    "version": "1.0.0"
  },
  "paths": {
    "/health": {
      "get": {
        "summary": "Health check",
        "responses": {
          "200": {
            "description": "OK"
          }
        }
      }
    }
  }
}
SPECEOF

run_validator "${TMPDIR_TEST}/valid.json"
if [ "$rc" -eq 0 ]; then
    pass_test "exit code 0"
else
    fail_test "expected exit code 0, got $rc" "$output"
fi
if echo "$output" | grep -qF -- "No issues found"; then
    pass_test "output says no issues"
else
    fail_test "expected 'No issues found'" "$output"
fi

# ---------- Test 2: Missing info.title (error) ----------
echo ""
echo "Test 2: Missing info.title (error)"
cat > "${TMPDIR_TEST}/no_title.json" << 'SPECEOF'
{
  "openapi": "3.0.3",
  "info": {
    "description": "A test API",
    "version": "1.0.0"
  },
  "paths": {}
}
SPECEOF

run_validator "${TMPDIR_TEST}/no_title.json"
if [ "$rc" -eq 1 ]; then
    pass_test "exit code 1"
else
    fail_test "expected exit code 1, got $rc" "$output"
fi
if echo "$output" | grep -qF -- "info.title"; then
    pass_test "reports missing info.title"
else
    fail_test "expected mention of info.title" "$output"
fi
if echo "$output" | grep -qF -- "[ERROR]"; then
    pass_test "severity is ERROR"
else
    fail_test "expected [ERROR] tag" "$output"
fi

# ---------- Test 3: Missing descriptions (warnings) ----------
echo ""
echo "Test 3: Missing descriptions (warnings)"
cat > "${TMPDIR_TEST}/no_desc.json" << 'SPECEOF'
{
  "openapi": "3.1.0",
  "info": {
    "title": "Test API",
    "version": "1.0.0"
  },
  "paths": {
    "/items": {
      "get": {
        "responses": {
          "200": {
            "description": "OK"
          }
        }
      }
    }
  }
}
SPECEOF

run_validator "${TMPDIR_TEST}/no_desc.json"
if [ "$rc" -eq 0 ]; then
    pass_test "exit code 0 (warnings only)"
else
    fail_test "expected exit code 0, got $rc" "$output"
fi
if echo "$output" | grep -qF -- "[WARNING]"; then
    pass_test "has WARNING findings"
else
    fail_test "expected [WARNING] findings" "$output"
fi
if echo "$output" | grep -qF -- "info.description"; then
    pass_test "warns about missing info.description"
else
    fail_test "expected warning about info.description" "$output"
fi
if echo "$output" | grep -qF -- "summary"; then
    pass_test "warns about missing summary/description on operation"
else
    fail_test "expected warning about missing operation summary" "$output"
fi

# ---------- Test 4: Unused schemas (warning) ----------
echo ""
echo "Test 4: Unused schemas (warning)"
cat > "${TMPDIR_TEST}/unused_schema.json" << 'SPECEOF'
{
  "openapi": "3.0.3",
  "info": {
    "title": "Test API",
    "description": "A test API",
    "version": "1.0.0"
  },
  "paths": {
    "/items": {
      "get": {
        "summary": "List items",
        "responses": {
          "200": {
            "description": "OK"
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "UnusedModel": {
        "type": "object",
        "properties": {
          "id": { "type": "integer" }
        }
      },
      "UsedModel": {
        "type": "object"
      }
    }
  }
}
SPECEOF

run_validator "${TMPDIR_TEST}/unused_schema.json"
if [ "$rc" -eq 0 ]; then
    pass_test "exit code 0 (warnings only)"
else
    fail_test "expected exit code 0, got $rc" "$output"
fi
if echo "$output" | grep -qF -- "UnusedModel"; then
    pass_test "warns about unused UnusedModel"
else
    fail_test "expected warning about UnusedModel" "$output"
fi
if echo "$output" | grep -qF -- "UsedModel"; then
    pass_test "warns about unused UsedModel (also unreferenced)"
else
    fail_test "expected warning about UsedModel" "$output"
fi

# ---------- Test 5: Inconsistent naming (warning) ----------
echo ""
echo "Test 5: Inconsistent path naming (warning)"
cat > "${TMPDIR_TEST}/mixed_naming.json" << 'SPECEOF'
{
  "openapi": "3.0.3",
  "info": {
    "title": "Test API",
    "description": "A test API",
    "version": "1.0.0"
  },
  "paths": {
    "/userProfiles": {
      "get": {
        "summary": "Get user profiles",
        "responses": { "200": { "description": "OK" } }
      }
    },
    "/order_items": {
      "get": {
        "summary": "Get order items",
        "responses": { "200": { "description": "OK" } }
      }
    }
  }
}
SPECEOF

run_validator "${TMPDIR_TEST}/mixed_naming.json"
if [ "$rc" -eq 0 ]; then
    pass_test "exit code 0 (warnings only)"
else
    fail_test "expected exit code 0, got $rc" "$output"
fi
if echo "$output" | grep -qF -- "Inconsistent path naming"; then
    pass_test "warns about inconsistent naming"
else
    fail_test "expected inconsistent naming warning" "$output"
fi

# ---------- Test 6: Strict mode turns warnings to errors ----------
echo ""
echo "Test 6: Strict mode (warnings become errors)"
run_validator "${TMPDIR_TEST}/no_desc.json" --strict
if [ "$rc" -eq 1 ]; then
    pass_test "exit code 1 in strict mode"
else
    fail_test "expected exit code 1, got $rc" "$output"
fi
if echo "$output" | grep -qF -- "[ERROR]"; then
    pass_test "warnings promoted to ERROR"
else
    fail_test "expected [ERROR] tags in strict mode" "$output"
fi
# Should NOT have any [WARNING] in strict mode
if echo "$output" | grep -qF -- "[WARNING]"; then
    fail_test "should not have [WARNING] in strict mode" "$output"
else
    pass_test "no [WARNING] tags in strict mode"
fi

# ---------- Test 7: Non-existent file (exit 2) ----------
echo ""
echo "Test 7: Non-existent file"
run_validator "/tmp/does_not_exist_ever.json"
if [ "$rc" -eq 2 ]; then
    pass_test "exit code 2"
else
    fail_test "expected exit code 2, got $rc" "$output"
fi
if echo "$output" | grep -qF -- "File not found"; then
    pass_test "reports file not found"
else
    fail_test "expected 'File not found' message" "$output"
fi

# ---------- Test 8: Invalid JSON (exit 2) ----------
echo ""
echo "Test 8: Invalid JSON"
echo "not valid json {{{" > "${TMPDIR_TEST}/bad.json"
run_validator "${TMPDIR_TEST}/bad.json"
if [ "$rc" -eq 2 ]; then
    pass_test "exit code 2"
else
    fail_test "expected exit code 2, got $rc" "$output"
fi
if echo "$output" | grep -qF -- "Invalid JSON"; then
    pass_test "reports invalid JSON"
else
    fail_test "expected 'Invalid JSON' message" "$output"
fi

# ---------- Test 9: JSON output format ----------
echo ""
echo "Test 9: JSON output format"
run_validator "${TMPDIR_TEST}/no_title.json" --format=json
if [ "$rc" -eq 1 ]; then
    pass_test "exit code 1"
else
    fail_test "expected exit code 1, got $rc" "$output"
fi
if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    pass_test "output is valid JSON"
else
    fail_test "expected valid JSON output" "$output"
fi
if echo "$output" | grep -qF -- '"findings"'; then
    pass_test "JSON has 'findings' key"
else
    fail_test "expected 'findings' key in JSON" "$output"
fi
if echo "$output" | grep -qF -- '"summary"'; then
    pass_test "JSON has 'summary' key"
else
    fail_test "expected 'summary' key in JSON" "$output"
fi
if echo "$output" | grep -qF -- '"severity"'; then
    pass_test "findings have 'severity' field"
else
    fail_test "expected 'severity' field in findings" "$output"
fi

# ---------- Summary ----------
echo ""
echo "=== Results ==="
TOTAL=$((PASS + FAIL))
echo "Passed: ${PASS}/${TOTAL}"
echo "Failed: ${FAIL}/${TOTAL}"

if [ "$FAIL" -gt 0 ]; then
    echo "SOME TESTS FAILED"
    exit 1
else
    echo "ALL TESTS PASSED"
    exit 0
fi
