//! The op table and register map. This file is the single source of truth for
//! what a rule can do; `docs/ops.md` is generated from it by `rulelab docs`.

/// One entry of the op table.
pub struct OpInfo {
    pub code: u8,
    pub name: &'static str,
    /// Whether the `b` operand is read. Unary ops take `op dst a`.
    pub uses_b: bool,
    /// Whether the old value of `dst` is read (`sel`, `ema`).
    pub reads_dst: bool,
    /// Whether `a` and `b` can be swapped; canonicalization sorts them.
    pub commutative: bool,
    pub semantics: &'static str,
}

const fn op(
    code: u8,
    name: &'static str,
    uses_b: bool,
    reads_dst: bool,
    commutative: bool,
    semantics: &'static str,
) -> OpInfo {
    OpInfo { code, name, uses_b, reads_dst, commutative, semantics }
}

pub const OPS: [OpInfo; 16] = [
    op(0x0, "mov", false, false, false, "d = a"),
    op(0x1, "add", true, false, true, "d = a + b"),
    op(0x2, "sub", true, false, false, "d = a − b"),
    op(0x3, "mul", true, false, true, "d = a × b"),
    op(0x4, "neg", false, false, false, "d = −a"),
    op(0x5, "sign", false, false, false, "d = sign(a), sign(0) = 0"),
    op(0x6, "abs", false, false, false, "d = abs(a)"),
    op(0x7, "min", true, false, true, "d = min(a, b)"),
    op(0x8, "max", true, false, true, "d = max(a, b)"),
    op(0x9, "gt", true, false, false, "d = 1 if a > b else 0"),
    op(0xa, "sel", true, true, false, "d = a if d ≠ 0 else b (d is the condition)"),
    op(0xb, "ema", true, true, false, "d = (1 − b) × d + b × a"),
    op(0xc, "thr", true, false, false, "d = a if abs(a) > abs(b) else 0"),
    op(0xd, "clip", true, false, false, "d = a clamped to ±abs(b)"),
    op(0xe, "relu", false, false, false, "d = max(a, 0)"),
    op(0xf, "tanh", false, false, false, "d = tanh(a)"),
];

/// Applies op `code` to the old destination value `d` and operands `a`, `b`.
pub fn eval(code: u8, d: f32, a: f32, b: f32) -> f32 {
    match code {
        0x0 => a,
        0x1 => a + b,
        0x2 => a - b,
        0x3 => a * b,
        0x4 => -a,
        0x5 => sign(a),
        0x6 => a.abs(),
        0x7 => a.min(b),
        0x8 => a.max(b),
        0x9 => (a > b) as u8 as f32,
        0xa => {
            if d != 0.0 {
                a
            } else {
                b
            }
        }
        0xb => (1.0 - b) * d + b * a,
        0xc => {
            if a.abs() > b.abs() {
                a
            } else {
                0.0
            }
        }
        // Not f32::clamp, which panics when the bound is NaN.
        0xd => a.max(-b.abs()).min(b.abs()),
        0xe => a.max(0.0),
        0xf => a.tanh(),
        _ => unreachable!("op codes are 4 bits"),
    }
}

fn sign(a: f32) -> f32 {
    if a > 0.0 {
        1.0
    } else if a < 0.0 {
        -1.0
    } else {
        0.0
    }
}

/// One entry of the register map.
pub struct RegInfo {
    pub name: &'static str,
    pub meaning: &'static str,
    pub init: &'static str,
}

const fn reg(name: &'static str, meaning: &'static str, init: &'static str) -> RegInfo {
    RegInfo { name, meaning, init }
}

pub const REGS: [RegInfo; 16] = [
    reg("pre", "presynaptic activation x_i", "input"),
    reg("post", "postsynaptic output y_j", "input"),
    reg("agg", "postsynaptic pre-activation a_j", "input"),
    reg("w", "current weight (dequantized)", "input"),
    reg("tr", "current per-synapse trace", "input"),
    reg("sig", "signal at unit j", "input"),
    reg("nbr", "mean output of j's layer", "input"),
    reg("noise", "uniform in (−1, 1), fresh per synapse per step", "input"),
    reg("one", "1.0", "constant"),
    reg("neg", "−1.0", "constant"),
    reg("k1", "spec constant", "constant"),
    reg("k2", "spec constant", "constant"),
    reg("dw", "output: weight delta, applied as w ← Q(w + η·dw)", "0"),
    reg("ntr", "output: new trace", "tr"),
    reg("t0", "scratch", "0"),
    reg("t1", "scratch", "0"),
];

pub const DW: u8 = 12;
pub const NTR: u8 = 13;
/// The only registers an instruction may write: `dw`, `ntr`, `t0`, `t1`.
pub const WRITABLE: std::ops::RangeInclusive<u8> = 12..=15;

pub fn op_code(name: &str) -> Option<u8> {
    OPS.iter().position(|o| o.name == name).map(|i| i as u8)
}

pub fn reg_index(name: &str) -> Option<u8> {
    REGS.iter().position(|r| r.name == name).map(|i| i as u8)
}
