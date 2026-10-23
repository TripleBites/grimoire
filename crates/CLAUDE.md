# rulelab: developer instructions

Loaded when working in crates/. The spec is the v0 design; milestones M0 to M6
each close with a `cargo test`.

## Crates
vm (no deps) ← net ← search ← cli; tasks and metrics have no rulelab deps; io depends on vm.
Nothing may depend on a crate above it. The viewer (M6) stays out of default-members.

## Conventions
- The op table and register map live only in `crates/vm/src/ops.rs`. After any change,
  run `cargo run -p rulelab -- docs`; a test fails if docs/ops.md is stale.
- Invalid `dst` (r0 to r11) is an error at every entry point: `decode` returns
  `InvalidDst`, the assembler rejects it, enumerators iterate `ops::WRITABLE` only
  (use `vm::valid_words`), and the evolver mutates `dst` within `ops::WRITABLE`.
- Determinism: all randomness from the run's ChaCha8 RNG, no threads inside a run,
  no unordered map iteration on any path that writes results.
- Line budgets (non-test lines, excluding blanks and comments) are in the spec.
  Tests are outside the budget. Growth needs a reason in the commit message.
- Every milestone acceptance test is a `cargo test`, named after what it proves.
- Plain, readable Rust: no `unsafe`, no macro-generated cell types, clarity over speed.
- Run `cargo fmt` and `cargo clippy --all-targets` before committing.
