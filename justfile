set shell := ["sh", "-cu"]

default:
    @just --list

demos:
    ./scripts/run-all

tests *args:
    ./scripts/run-tests {{args}}

audit:
    ./scripts/validate-catalog catalog/demos.tsv
    ./scripts/validate-catalog catalog/tests.tsv
    ./scripts/check-web-standalone
    ./scripts/check-format
    ./scripts/check-docstrings
    ./tests/test-bootstrap
    ./tests/test-sequential-migration
    ./tests/test-associative-priority-migration
    ./tests/test-tree-indexed-migration

check: audit demos tests
