# Known rules

Check a candidate's canonical number (`rulelab asm "<assembly>"`) against this list
before calling it new. A rule in disguise usually differs only by dead code or operand
order, which canonicalization already removes.

| Rule | Number | Assembly | Known for |
| --- | --- | --- | --- |
| Identity | `R0` | (empty) | no learning; the no-learning baseline |
| Hebbian | `R1-3c01` | `mul dw pre post` | correlation learning; unstable without a clip |
| Delta / perceptron | `R1-3c05` | `mul dw pre sig` | supervised with the `target` signal |
| Oja | `R3-3e13.2e0e.3c1e` | `mul t0 post w` · `sub t0 pre t0` · `mul dw t0 post` | normalized Hebbian; finds the first principal component |
| Bop-style (sketch) | `R4-3e05.bdea.cfdb.5cf0` | `mul t0 pre sig` · `ema ntr t0 k1` · `thr t1 ntr k2` · `sign dw t1` | momentum-threshold flips for ternary and binary nets |
