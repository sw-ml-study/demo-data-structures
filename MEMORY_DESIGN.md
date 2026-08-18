# Memory Design for Dynamic sw-MLPL Values

## Desired programmer contract

sw-MLPL should support dynamically sized structures without exposing
`malloc`, `free`, ownership annotations, lifetimes, or a borrow checker. The
target is Clojure-like persistent immutable data: versions share unchanged
structure safely, and an update returns a new root.
Programs use value semantics:

```text
ys = u:push(xs, 4)
# xs is still valid and unchanged; ys is the new value
```

Memory management is an implementation responsibility. “No language-level
allocator” does not mean “no heap allocation”: vectors, records, strings, and
function environments already allocate in the Rust host. It means allocation
and reclamation are automatic and unobservable except through resource use.

## Current model and its boundary

As documented in adjacent sw-MLPL's `docs/memory-model.md`, current values are
owned Rust trees. Arrays own `Vec<f64>`, records own their field values, Results
own their payload, and environment maps own bindings. Rust RAII drops an old
value on reassignment and all values at session teardown. User programs cannot
create references or cycles, so tracing garbage collection is unnecessary.

This model is safe and simple, but dynamic demos expose two costs:

1. `concat`, `scatter`, record rebuilding, and assignment may copy an entire
   value for a one-element logical change.
2. A persistent list/tree retains old versions semantically, but naive deep
   cloning duplicates unchanged tails/subtrees instead of sharing them.

The problem today is performance and representation, not memory safety.

## Separate three different graphs

Confusing these leads to unnecessary GC or unsafe pointers.

| Graph | Example | Must runtime references cycle? |
|---|---|---|
| Logical data graph | Graph algorithm with edge `(7, 3)` | No; edges can be integer IDs in arrays |
| Immutable value DAG | Two tree versions share an unchanged subtree | No; sharing is directed from roots to children |
| Runtime object graph | Closure captures record that contains the closure | Potentially; this is the dangerous kind |

A cyclic user graph does not require cyclic host pointers. Store node payloads
and integer edges in arrays, CSR, or an arena-like value. The entire graph is
one ordinary acyclic MLPL value and drops as a unit.

## Recommended staged design

### Stage M0 — retain owned values, measure copies

Use today's semantics for the first executable baselines. Add internal
instrumentation (not semantic output) or benchmarks for:

- bytes allocated/copied by append, update, persistent-list prepend, and AVL
  insertion;
- peak live bytes while old and new versions coexist;
- recursion depth and maximum structure size;
- full reclamation after the script/session ends.

This supplies evidence before changing the runtime. Demos should state their
asymptotic logical complexity and current copy complexity separately.

### Stage M1 — copy-on-write buffers

Back dense array data with host-managed shared storage such as
`Arc<[f64]>`/`Arc<Vec<f64>>` or an equivalent internal buffer. Cloning an MLPL
array then increments a reference count. A pure update:

- mutates in place internally when the buffer is uniquely owned;
- otherwise copies once, updates the copy, and returns it.

Observable value semantics remain unchanged. There is no user-visible borrow
checker and no tracing GC. Reference counting is an implementation technique,
not a new language concept.

For growing vectors, a persistent chunked vector/rope may outperform repeated
contiguous `concat`. Keep the public sequence protocol independent of its
layout so representations can change later.

### Stage M2 — Clojure-style immutable structural sharing

Represent recursive immutable values with reference-counted nodes:

```text
Node = Empty | Cons(value, Node)
Tree = Empty | Branch(value, Tree, Tree)
```

Internally, child links may be `Arc<ValueNode>` or compact immutable handles.
Operations allocate only the changed path and share unchanged children. Normal
persistent construction points from a new root to already-existing immutable
children, producing a DAG. Reference counting reclaims such values exactly and
makes old versions cheap, like Clojure's persistent collections.

Required invariant: after publication, a node's child links never mutate.
Sharing is visible semantically only as persistence; pointer identity and
reference counts are not language operations.

### Stage M3 — first-class functions with cycle diagnostics

First-class functions create the largest design risk. Start with two forms:

1. **Named function reference:** `{function_id}` points to an immutable global
   definition by stable symbol ID. It does not capture the environment.
2. **Bound function:** `{function_id, captures}` owns an immutable capture
   record containing ordinary values.

Avoid common cycles by representation and diagnose them statically:

- capture records are snapshots, not mutable references to an Environment;
- recursive functions call their stable function ID rather than capturing
  themselves;
- module values contain function IDs, not closures holding the module record;
- Observer/Mediator registries return new registries and should not contain a
  closure that strongly captures that same registry.

The compiler/linter should construct a conservative ownership/capture graph,
find strongly connected components, and report paths such as
`registry -> callback -> captures registry`. Named recursion through a symbol
ID is not an owning edge and should not warn. Intentional logical cycles using
integer node IDs are also not ownership cycles.

This analysis is a diagnostic, not a proof. In a higher-order language, a cycle
can depend on runtime branching, returned functions, module loading, or
data-dependent construction. Exact cycle detection is not generally possible
at compile time. The compiler can catch direct and conservatively inferred
cycles; a linter can warn on uncertain ones and explain how to break each
ownership path.

The language does not prohibit a warned program. If strong runtime cycles are
legal and storage uses ordinary reference counting, unreachable cycles will
not be reclaimed. Managing that lifetime is the application's responsibility;
a leak or memory exhaustion caused by it is an application bug.

## Cycle policy and avoidance guidance

### Diagnostic levels

- **No finding:** ordinary persistent DAG construction or logical cycles by
  integer ID.
- **Advice:** a value retains substantially more structure than expected; use
  a smaller explicit capture record.
- **Warning:** a possible strong ownership cycle crosses higher-order code.
- **Definite-cycle warning:** a statically evident strong cycle, including its
  ownership path. Applications may optionally promote it to an error in their
  own lint policy.

Diagnostics should print the owning-edge path, allocation/capture sites, and a
specific rewrite. A bare “cycle detected” is not actionable.

### How applications manage ownership cycles

1. Prefer numeric IDs/handles inside an owning graph/arena value when the whole
   cyclic structure has one lifetime. Dropping the arena releases it in bulk.
2. Capture only required immutable fields, not an entire registry, module,
   history, or environment.
3. Express recursion through a named function ID, not a closure capturing
   itself.
4. Keep parent links as derived traversal context, integer IDs, or weak
   internal links; children may remain strong.
5. Store subscriber/command IDs in state and resolve behavior through a
   separate function table passed into the operation.
6. Return effects as data so callbacks do not retain the runtime that executes
   them.
7. Break caches into key/value data owned by an outer scope rather than having
   cached values point strongly back to the cache.
8. If strong reference cycles are intentional, bound their creation, retain
   their owning session intentionally, and monitor the configured memory limit.
   With plain reference counting, rebinding the last external root does not
   reclaim the unreachable cycle.

These rules should appear in compiler help, the language guide, and the
relevant GoF demos (Observer, Mediator, Command, Composite, Proxy, Decorator).

### Application representation choices for cycles

| Policy | Benefit | Cost / limitation |
|---|---|---|
| Strong references + diagnosed leak risk | Direct representation | Unreachable cycles are not reclaimed; exhaustion/leaks are application bugs |
| Weak/non-owning edge type | Deterministic RC and explicit cycle breaking | Adds an advanced reference concept; upgrading can fail after target reclamation |
| Handle/arena topology | Cyclic logical structures without ownership cycles | Indirection and arena threading; excellent for graphs, less natural for arbitrary closures |
| Trial-deletion/cycle-collecting RC | Keeps RC behavior for normal values and collects cycles | Runtime complexity and pause/work scheduling |
| Tracing GC for general values | Complete reclamation of unreachable cycles | Larger runtime change; tracing roots, pauses, FFI/resource rules |

Recommended baseline: ship persistent structural sharing plus cycle linting;
support intentional cycles; make handle/arena topology the documented choice
when bulk reclamation is desired; and state plainly that unreachable strong
cycles remain allocated. Cycle collection or tracing may be considered later,
but is not required for language correctness under this contract.

### Stage M4 — scoped transients/builders (optional optimization)

Some algorithms need many local updates. Offer an implementation optimization
or explicit scoped construct with this semantic shape:

```text
result = build(seed) { b -> ...updates to b... }
```

Inside the scope, a uniquely owned buffer may update efficiently. It cannot
escape, be aliased, or be captured. On exit it freezes into an ordinary
immutable value. The interpreter/compiler enforces this restriction; the user
does not manage lifetimes or prove borrows.

Prefer making this an optimizer for pure `fold`/`unfold` pipelines before
adding surface syntax. If escape analysis can prove uniqueness, identical pure
source can receive the same benefit invisibly.

## Dynamic collection representations

| Structure | Recommended value representation | Reclamation |
|---|---|---|
| Growable packed vector | COW contiguous buffer + length/capacity | Refcount drops buffer |
| Persistent vector | Branching tree or chunked vector | Refcount drops unreachable DAG nodes |
| List / tree | Immutable shared nodes | Refcount drops unreachable paths/subtrees |
| Queue / deque | Pair of persistent sequences or chunked deque | Same as components |
| Numeric hash map | Persistent hash-trie eventually; COW parallel arrays initially | Refcount / owned value drop |
| Logical cyclic graph | Node/edge/CSR arrays using integer IDs | Whole value drops normally |
| History / Memento | Vector/tree of immutable roots | Dropping history releases unreferenced versions |

Do not represent graph edges, linked-list `next`, or tree parents as raw host
pointers visible to MLPL. Integer handles are ordinary values, serializable,
easy to display, and incapable of use-after-free while their owning arena value
is intact.

## Handle/arena alternative

An immutable arena value can store nodes plus integer handles. An operation
returns `{arena: arena2, root: handle2}`. This is useful for graphs and compact
trees, but handles must never be globally dereferenceable:

- a handle is meaningful only with its arena value;
- use a generational pair `{slot, generation}` if deletion/reuse is exposed;
- bounds/generation failures return `Err`, never stale memory;
- serialization carries arena and handles together;
- compaction returns a handle remapping or is invisible while no handles
  escape.

This is automatic storage, not manual allocation. Avoid public `alloc/free`
operations; use collection operations such as `insert/remove` that maintain
the arena invariant.

## Optional automatic cycle reclamation

The language contract does not require automatic reclamation of cycles. If a
future runtime elects to provide it, the motivating cases would include:

- mutable general references/cells;
- objects or records with mutable child links;
- unrestricted closures that capture environments by reference;
- recursive lazy values/promises that point back to themselves;
- channels/tasks whose callbacks and state strongly retain each other;
- foreign objects with cyclic ownership not broken by explicit host handles.

That would be an optional runtime guarantee rather than a prerequisite for
supporting cyclic data. A practical design could use a generational tracing GC
for general
`Value`/closure objects while dense numeric buffers remain separately managed
by COW reference-counted storage. Do not trace every tensor element.

Cycle-detecting reference counting is another option but is more complex and
usually less predictable than a small tracing heap once arbitrary cycles are
legal.

## Resource safety without `free`

Memory is only one resource. Files, sockets, GPU buffers, and remote handles
need deterministic release even in a GC-free/value language. Prefer scoped
capability functions:

```text
with_file(path, :u:consume)
with_device("mlx", :u:run)
```

The host opens, calls, and closes with `finally` semantics. Do not make users
call `close` correctly on every Result path. Long-lived external handles need
host finalizers as a backstop plus explicit scoped APIs for timely release.
Pure algorithm demos should return effect descriptions as data and leave
resource interpretation at the program boundary.

## Limits and diagnostics

Automatic memory management still needs predictable failure behavior:

- configurable heap/array/session byte limits;
- maximum rank, dimensions, collection length, and recursion depth;
- checked size arithmetic before allocation;
- `try/catch`-compatible structured allocation-limit errors;
- introspection such as value kind, logical size, storage kind, approximate
  retained bytes, and sharing count in debug mode;
- cancellation checks in long folds/unfolds and allocation-heavy operations.

Out-of-memory must never become an unchecked shape overflow or partial
mutation. A failed pure operation leaves all input values valid.

## Pattern-specific memory notes

- **Flyweight:** COW/shared immutable tables are the direct implementation;
  clients hold indices or shared values.
- **Prototype/Memento:** structural sharing makes snapshots cheap while value
  semantics guarantee isolation.
- **Composite/Interpreter/Visitor:** immutable trees are DAG-safe; folds do not
  retain parent links.
- **Observer/Mediator:** immutable subscriber IDs plus a separate function
  table avoid callback/state cycles.
- **Command:** store stable function IDs and immutable argument values, not a
  closure over the entire command history.
- **Proxy/Decorator:** wrappers hold the wrapped function ID/value in one
  direction only; a wrapped function must not strongly retain its wrapper.
- **State:** state transitions return new values; no state object points to a
  mutable context that points back.
- **Singleton:** prefer module constants or explicitly passed capabilities;
  hidden immortal heap objects are neither necessary nor desirable.

## Acceptance tests for the language/runtime

1. Keep `xs`, derive `ys = push(xs, x)`, and prove both values remain correct.
2. Build 10,000 persistent list/tree versions, retain only selected roots, and
   verify retained memory falls after the others leave scope/rebind.
3. Insert one AVL key and show allocation proportional to tree height rather
   than total node count once sharing lands.
4. Build and discard a cyclic *logical* graph represented by CSR; verify the
   whole allocation is reclaimed without tracing.
5. Lint a self-capturing closure with the full ownership path without rejecting
   it; represent named recursion by symbol ID without a false positive.
6. Cancel a large unfold/build and verify no partial result or external
   resource remains live.
7. Hit a configured memory limit and receive a structured error while all
   inputs remain usable.
8. Run the GoF event-workflow case study repeatedly and demonstrate that
   Observer/Mediator registries do not leak histories or closures.

## Recommendation

Do not add `malloc/free`. Do not expose a borrow checker. Do not add tracing GC
yet. Preserve immutable value semantics; introduce COW for dense buffers and
Clojure-style reference-counted structural sharing for persistent collections;
represent ordinary logical cycles with indices/handles; and detect likely
strong ownership cycles at compile/lint time with actionable rewrite guidance.

Allowing a diagnostic does not make its memory reclaimable. Document that
unreachable strong cycles remain live, provide memory limits and retained-size
diagnostics, and classify leaks or exhaustion caused by application-created
cycles as application bugs. Automatic cycle collection remains an optional
future runtime feature, not part of the correctness contract.
