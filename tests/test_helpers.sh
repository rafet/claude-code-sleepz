#!/usr/bin/env bash
# Shared test helpers for sleepz test suite

PASS=0
FAIL=0

assert_contains() {
    local test_name="$1" expected="$2" actual="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        echo "  PASS: $test_name"
        ((PASS++))
    else
        echo "  FAIL: $test_name (expected to contain '$expected', got '$actual')"
        ((FAIL++))
    fi
}

assert_empty() {
    local test_name="$1" actual="$2"
    if [[ -z "$actual" ]]; then
        echo "  PASS: $test_name"
        ((PASS++))
    else
        echo "  FAIL: $test_name (expected empty, got '$actual')"
        ((FAIL++))
    fi
}

assert_not_empty() {
    local test_name="$1" actual="$2"
    if [[ -n "$actual" ]]; then
        echo "  PASS: $test_name"
        ((PASS++))
    else
        echo "  FAIL: $test_name (expected non-empty output)"
        ((FAIL++))
    fi
}

assert_matches() {
    local test_name="$1" pattern="$2" actual="$3"
    if [[ "$actual" =~ $pattern ]]; then
        echo "  PASS: $test_name"
        ((PASS++))
    else
        echo "  FAIL: $test_name (expected to match '$pattern', got '$actual')"
        ((FAIL++))
    fi
}

assert_not_contains() {
    local test_name="$1" unexpected="$2" actual="$3"
    if [[ "$actual" != *"$unexpected"* ]]; then
        echo "  PASS: $test_name"
        ((PASS++))
    else
        echo "  FAIL: $test_name (expected NOT to contain '$unexpected')"
        ((FAIL++))
    fi
}

report_results() {
    echo ""
    echo "=== Results: $PASS passed, $FAIL failed ==="
    exit $FAIL
}
