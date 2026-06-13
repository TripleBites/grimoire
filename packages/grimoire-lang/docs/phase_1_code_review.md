# Phase 1 Code Review

> Review of the grimoire-lang MVP (Lexer → Reader → Emitter → CLI) after getting the first `.gr` files compiling to native binaries and WASM.

---

## 1. Architecture Overview

```
.gr ──► Lexer ──► Reader ──► Form AST ──► Emitter ──► .zig ──► zig build ──► binary/wasm
```

The pipeline is admirably simple. We made the right call to **transpile to Zig** rather than build a custom backend. The codebase is ~1,100 lines across 8 source files. That is exactly the kind of restraint an MVP needs.

---

## 2. What Works Well ✅

### 2.1 The Transpilation Strategy

This was the single best architectural decision. By emitting Zig source, we get:

- **Free WASM** (`-target wasm32-wasi`)
- **Free FFI** (`extern`, `@cImport` equivalents via `zig/extern`)
- **Free comptime** (Zag compile-time → Zig `comptime`)
- **Native-speed binaries** with zero language runtime

The Emitter generates readable Zig. That is invaluable for debugging.

### 2.2 Zero-Copy Lexer

The Lexer stores `Token.text` as slices into the original source string. No per-token allocations. For a language where tokens are small and numerous, this is the right call.

### 2.3 Explicit Memory Management

No GC, no hidden allocator threading. The `Form.destroy(allocator)` pattern is Zig-idiomatic and keeps memory predictable.

### 2.4 Minimal Test Surface

Tests are embedded in-source (`test` blocks) and run through `zig build test`. This keeps the test infrastructure from becoming its own project.

### 2.5 Zig 0.17 Compatibility

We correctly navigated the volatile Zig 0.17 API (unmanaged `ArrayList`, `std.Io.Dir`, `std.process.Init`). The code compiles and runs on the bleeding-edge compiler.

---

## 3. What I Would Have Done Differently ⚠️

### 3.1 Lexer: Silent Failure on Unknown Characters

**Current:**
```zig
else => {
    // Unknown character — skip and return next token
    return self.nextToken();
}
```

**Problem:** An errant Unicode byte or `@` in the wrong place is silently swallowed. The user gets no error message; the parser just sees an unexpected EOF three lines later.

**Better:** Return a proper `LexerError{ .InvalidCharacter = c, .line = line, .col = col }` and surface it through the compiler.

### 3.2 Lexer: String Escapes Are Hand-Waved

```zig
if (self.peek() == '\\') {
    _ = self.advance(); // skip backslash
    if (!self.isAtEnd()) _ = self.advance(); // skip escaped char
}
```

This treats `\"` and `\n` identically — it just skips the next char. The emitted Zig will contain the raw escape sequence, which Zig happens to understand, but this is accidental correctness. If we ever want to process strings at compile time (e.g., for macros), we need real unescaping.

### 3.3 Reader: Using `EmptyInput` for Loop Control

```zig
const form = reader.readForm() catch |err| switch (err) {
    ReaderError.EmptyInput => break,
    else => return err,
};
```

`EmptyInput` is semantically an error ("I expected a form but got EOF"). Using it to signal "done reading" conflates error flow with control flow. A cleaner pattern is `peek()` to check for EOF before reading, or have `readForm()` return `?*Form`.

### 3.4 Reader: Error Messages Are Useless

The `ReaderError` enum has variants like `.UnexpectedToken` and `.UnmatchedDelimiter`, but carries **no source location, no expected token, no file name**. When a user writes `(defn foo [x y` and forgets the `]`, they get:

```
error: UnmatchedDelimiter
```

That is not actionable. At minimum, errors should carry `(file, line, col, message)`.

### 3.5 Emitter: The `main` Hack

```zig
const is_main = std.mem.eql(u8, name_form.data.symbol, "main");
if (is_main) {
    try self.write(") void {\n");
} else {
    try self.write(") i64 {\n");
}
```

Hardcoding the string `"main"` is a smell. It also means `_ = ` is prepended to every expression in `main`, which is noisy and misleading (it suppresses "value ignored" warnings by explicitly ignoring values).

**Better options:**
- Require explicit type annotations: `(defn main [] -> void ...)`
- Or emit `main` as a special top-level form, not a `defn`
- Or make `defn` default to `void` and require `-> i64` for value-returning functions

### 3.6 Emitter: `if` Emits a Ternary, Not a Block

```zig
(if cond then else)
```

emits as:
```zig
(if (cond) then else null)
```

This is the **Zig ternary operator**, not an `if` statement. It means:
- You cannot have multi-expression branches
- Side effects in the `else` branch get the value `null` when omitted
- It is structurally different from every other Lisp `if`

**Better:** Emit a proper Zig `if` block:
```zig
if (cond) {
    then_expr
} else {
    else_expr
}
```

### 3.7 Emitter: `let` and `do` Duplicate Block Logic

Both `emitLet` and `emitDo` contain identical `blk:` emission logic. That should be a shared helper:

```zig
fn emitBlock(self: *Emitter, body: []*Form) EmitError!void
```

### 3.8 Emitter: `emitCall` Allocates for Namespace Translation

```zig
const zig_name = try self.allocator.dupe(u8, name);
defer self.allocator.free(zig_name);
for (zig_name) |*c| {
    if (c.* == '/') c.* = '.';
}
```

This allocates just to replace `/` → `.`. A small stack buffer or a `std.mem.replace` in-place approach would avoid the heap trip entirely.

### 3.9 Emitter: `str` Builtin References Nonexistent `self.allocator`

```zig
// In emitCall for "str"
try self.write("std.fmt.allocPrint(self.allocator, ...");
```

In the generated Zig, there is no `self.allocator`. This code would not compile if anyone used `(str ...)`. It was added speculatively and never tested.

### 3.10 Form AST: Using `undefined` in `Form.create`

```zig
form.* = .{
    .type = ftype,
    .data = undefined,
    .line = line,
    .col = col,
};
```

`undefined` is a footgun. If the caller forgets to set `form.data` before using the form, we get UB. A safer API would take `data` as a parameter:

```zig
pub fn create(allocator, ftype, data, line, col) !*Form
```

### 3.11 Compiler: No Integration Tests

The test suite checks that substrings appear in generated Zig (`"const x = 42;"`). It does **not** verify that:
- The generated Zig compiles
- The compiled program runs correctly
- The output matches expectations

A single integration test that compiles a `.gr` file and asserts on its stdout would catch half the bugs in this review.

### 3.12 CLI: `hello()` Stub Still Exists

```zig
// grimoire_lang.zig
pub fn hello() void {
    std.debug.print("hello grimoire-lang\n", .{});
}
```

Dead code from the original package scaffold. It should be removed.

---

## 4. File-by-File Notes

| File | Lines | Verdict | Key Issue |
|------|-------|---------|-----------|
| `lexer/Lexer.zig` | 209 | Good | Needs real error reporting |
| `lexer/Token.zig` | 56 | Clean | — |
| `reader/Reader.zig` | 249 | Okay | `EmptyInput` hack; no error messages |
| `reader/Form.zig` | 120 | Okay | `undefined` in `create`; `format` can stack-overflow |
| `compiler/Emitter.zig` | 661 | Needs work | `main` hack; ternary `if`; duplicated block logic |
| `compiler/Compiler.zig` | 65 | Clean | Missing integration tests |
| `main.zig` | 37 | Clean | Arg parsing is manual but functional |
| `grimoire_lang.zig` | 18 | Clean | Remove `hello()` |
| `build.zig` | 47 | Clean | Correct for Zig 0.17 |

---

## 5. Performance & Memory Observations

### 5.1 Per-Form Heap Allocation

Every `Form` is a separate `allocator.create()`. For a 1,000-line source file, that is thousands of tiny allocations. An **arena allocator** per compilation unit would be dramatically faster and simpler — just `arena.deinit()` at the end instead of traversing the AST to `destroy()` every node.

### 5.2 Emitter Output Buffer

The Emitter accumulates into an `ArrayList(u8)` and then `toOwnedSlice()`. This is fine for MVP-scale outputs (<1MB). For larger files, streaming directly to the output file via a buffered writer would use less peak memory.

### 5.3 `Form.format` is Recursive

The `format` method recurses through nested forms with no depth limit. A maliciously deep input (e.g., `((((...))))`) will stack-overflow during debug printing.

---

## 6. Recommendations for Phase 2

### High Priority

1. **Add integration tests** — Compile `.gr` → `.zig` → binary, run it, assert stdout.
2. **Replace `main` hack with explicit return types** — `(defn foo [x] -> i64 ...)` or similar.
3. **Fix `if` to emit blocks** — Enable multi-expression branches.
4. **Add source locations to errors** — `error{ .message = "expected )", .loc = .{ .line = 5, .col = 12 } }`
5. **Remove dead code** — `hello()`, `str` builtin, unused imports.

### Medium Priority

6. **Factor out `emitBlock`** — Shared helper for `let`, `do`, and eventually `if`.
7. **Arena allocation for Forms** — One arena per `compile()` call.
8. **Better string literal handling** — Unescape in the Lexer, re-escape in the Emitter.
9. **Namespace translation without allocation** — Write char-by-char or use a stack buffer.

### Low Priority

10. **NaN-boxed runtime values** — Only needed when we add interpreter/REPL mode.
11. **Persistent data structures** — Vectors and maps currently compile to anonymous Zig structs/arrays.
12. **Self-hosted core library** — `lib/core.gr` is still empty.

---

## 7. Summary

The MVP achieves its goal: **grimoire-lang compiles to working Zig, which compiles to native and WASM**. The architecture is sound. The main issues are:

- **Error reporting is basically nonexistent**
- **The Emitter has too many special-case hacks** (`main`, ternary `if`, duplicated block logic)
- **Testing stops at substring matching** — it does not verify runnable output
- **Memory management is correct but not optimized** (per-node allocation vs. arena)

None of these are fatal. They are exactly the kinds of shortcuts you expect in an MVP, and they are all well-contained enough to refactor incrementally in Phase 2.
