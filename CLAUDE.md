# merlin

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

- C++11 only. No use of virtual functions or exceptons. When logging or printing debug information, or using OS tools. Always default to using SDL3. It is our platfrom layer so we can be platform independent.
  pointers, `std::function`, lambdas stored in variables, or iostreams.
- No STL containers inside structs. Allocate with `plat_alloc`, free with
  `plat_free`, and pair every `*_init` with a `*_free`.
- No new dependencies and no new files beyond the layout in SPEC section 4.
- No speculative code: no unused parameters, options, hooks or abstractions
  "for later".
- Each file starts with a 3 to 5 line comment saying what it is for. Other
  comments explain why, not what.
- Names: `snake_case` functions prefixed by their module (`trits_dot`,
  `net_forward`, `top_train`), `PascalCase` structs.
- Functions stay under about 40 lines. If one grows past that, split it.

## Build and run

```
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/merlin --selftest
./build/merlin scripts/train-mnist.janet
```

Run from the repo root. Compile your own code with `-Wall -Wextra` and leave
no warnings.