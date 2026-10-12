# grimoire

A small C++11 program that trains a ternary neural network, driven by Janet
scripts. The full project spec is imported below; follow it exactly.

@SPEC.md

## How to work here

- Do one milestone from SPEC.md per request. Stop when it is done and report
  in the format of SPEC section 10. Never start the next milestone unprompted.
- Before writing code, state your plan for the milestone in 10 lines or fewer.
- If the spec is ambiguous or seems wrong, stop and ask. Do not guess.
- Do not commit. The owner reviews the diff and commits.
- The owner reads every line. Fewer lines is better than more features.

## Code rules

- C++11 only. Classes are welcome; no inheritance, virtual functions,
  exceptions, RTTI, function pointers, `std::function`, lambdas stored in
  variables, or iostreams.
- Classes that own memory follow one pattern: an empty constructor,
  `bool init(...)` that allocates and returns false on failure, `free()` that
  is safe to call twice, a destructor that calls `free()`, and copying
  deleted. Constructors never allocate, because without exceptions they
  cannot report failure.
- No STL containers inside classes or structs. Allocate with `plat_alloc`,
  free with `plat_free` (64-byte aligned, over SDL3).
- SDL3 is the platform layer: use it for logging (`SDL_Log`), allocation and
  any OS calls, so the code stays platform independent.
- Keep hot loops fast: contiguous arrays, no allocation per sample, no
  branches inside word loops. Measure before optimizing anything else.
- No new dependencies and no new files beyond the layout in SPEC section 4.
- No speculative code: no unused parameters, options, hooks or abstractions
  "for later".
- Each file starts with a 3 to 5 line comment saying what it is for. Other
  comments explain why, not what.
- Names: `PascalCase` classes and structs, `snake_case` methods, members and
  functions. Free functions are prefixed by their module (`plat_alloc`,
  `grimoire_register`).
- Keep clear human readable comments around code that is not trivial.

## Build and run

```
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/grimoire src/scripts/hello.janet
./build/grimoire --selftest                      # from M2
./build/grimoire src/scripts/train-mnist.janet   # from M4
```

Run from the repo root. Our code builds with `-Wall -Wextra` and must have no
warnings (the vendored Janet is a separate target without them). New source
files must be added to `CMakeLists.txt` by hand.
