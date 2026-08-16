# sw-MLPL Data Structures

Small, executable data-structure lessons written in
[sw-MLPL](https://sw-ml-study.github.io/sw-mlpl/). Each lesson separates a
reusable implementation under `src/`, a problem-solving example under
`demos/`, and deterministic conformance coverage under `tests/`.

This repository teaches representations, operations, invariants, and honest
costs. Searching, sorting, graph, numeric, dynamic-programming, serialization,
and matrix algorithms remain in
[`demo-algorithms`](https://github.com/sw-ml-study/demo-algorithms). Advanced
memory and hashing measurements remain in
[`demo-memory`](https://github.com/sw-ml-study/demo-memory).

## Start here

The migration is being delivered in this order:

1. vectors, stacks, queues, deques, linked lists, and persistent lists;
2. sets, maps, foundational hashing, heaps, priority queues, and LRU caches;
3. binary/search/balanced trees, tries, B-trees, and indexed range structures.

Once the first batch lands, run:

```sh
just demos
just tests
just check
```

`just` is the preferred task runner. The recipes are thin delegates to scripts
and there is intentionally no Makefile.

## Repository structure

```text
catalog/   machine-readable demo and test inventories
demos/     small applications with meaningful output
src/       reusable pure data-structure definitions
tests/     mlplunit conformance tests and shell contracts
scripts/   thin catalog, demo, and test runners
docs/      focused representation and complexity notes
```

Every executable lesson documents dynamic-size behavior, representation
invariants, logical complexity, current copy complexity, and explicit-loop
count. Builtins may be correctness oracles, but not substitutes for the
structure being taught. The current runtime copies composite values, so these
lessons do not claim structural sharing.

## Interpreter and tests

Scripts use the explicitly configured `MLPL` executable or the adjacent
release build at `../sw-mlpl/target/release/mlpl-repl`; they never install or
replace a stable binary. Native tests are discovered through `mlplunit.conf`.
Set `MLPLUNIT` when `mlplunit` is not on `PATH`.

Development is coordinated through the tracked AgentRail saga. Agents must
read `AGENTS.md` or `CLAUDE.md` and follow `agentrail next`, `begin`, test,
commit, and `complete` in that order.
