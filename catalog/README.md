# Demo catalog

`demos.tsv` inventories problem-solving mini-apps and `tests.tsv` inventories
their mlplunit conformance files. Both use the shared nine-column schema:
`id`, `path`, `data_structure`, `algorithm`, `dynamic_size`, `explicit_loops`,
`target_loops`, `required_features`, and `status`.

IDs and paths must be unique within a catalog. Runnable and constrained rows
must name existing `.mlpl` files under the matching `demos/` or `tests/` tree.
Loop counts are non-negative and `target_loops` cannot exceed
`explicit_loops`. Status is `runnable`, `constrained`, or `gated`.
