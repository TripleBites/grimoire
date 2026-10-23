# grimoire / rulelab

A small Rust workspace for discovering strictly local learning rules by enumerating
short bytecode programs, in the spirit of finding Rule 30 by making the space small.

```sh
cargo test                                   # milestone acceptance tests
cargo run -p rulelab -- asm "mul dw post pre" # → R1-3c01 (Hebbian)
cargo run -p rulelab -- disasm R1-3c05        # → mul dw pre sig (delta)
cargo run -p rulelab -- ops                   # register map and op table
```

Progress: M0 (VM) done. See CLAUDE.md for experimenter instructions and
crates/CLAUDE.md for developer conventions.
