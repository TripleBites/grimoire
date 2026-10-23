//! rulelab-vm: the rule VM. A rule is a short program of 16-bit instructions
//! that computes a weight delta and a new trace for one synapse.

pub mod ops;

use ops::{OPS, REGS, WRITABLE};
use std::fmt;

/// Longest allowed program, in instructions.
pub const MAX_LEN: usize = 8;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VmError {
    /// `dst` is r0 to r11, which are read-only.
    InvalidDst {
        word: u16,
        dst: u8,
    },
    TooLong(usize),
    BadNumber(String),
    Asm {
        line: usize,
        msg: String,
    },
}

impl fmt::Display for VmError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            VmError::InvalidDst { word, dst } => write!(
                f,
                "invalid instruction {word:04x}: cannot write to `{}`: read-only register",
                REGS[*dst as usize].name
            ),
            VmError::TooLong(n) => {
                write!(f, "program has {n} instructions; the limit is {MAX_LEN}")
            }
            VmError::BadNumber(s) => write!(f, "bad rule number: {s}"),
            VmError::Asm { line, msg } => write!(f, "line {line}: {msg}"),
        }
    }
}

impl std::error::Error for VmError {}

/// A decoded instruction. Only `decode` and `assemble` build one, so `dst`
/// is always writable.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct Instr {
    pub op: u8,
    pub dst: u8,
    pub a: u8,
    pub b: u8,
}

impl Instr {
    pub fn encode(self) -> u16 {
        (self.op as u16) << 12 | (self.dst as u16) << 8 | (self.a as u16) << 4 | self.b as u16
    }

    /// Registers this instruction reads.
    fn reads(self) -> impl Iterator<Item = u8> {
        let info = &OPS[self.op as usize];
        [Some(self.a), info.uses_b.then_some(self.b), info.reads_dst.then_some(self.dst)]
            .into_iter()
            .flatten()
    }
}

pub fn decode(word: u16) -> Result<Instr, VmError> {
    let f = |shift: u16| ((word >> shift) & 0xf) as u8;
    let instr = Instr { op: f(12), dst: f(8), a: f(4), b: f(0) };
    if !WRITABLE.contains(&instr.dst) {
        return Err(VmError::InvalidDst { word, dst: instr.dst });
    }
    Ok(instr)
}

/// Every valid instruction word, in increasing order. Words with `dst` < 12
/// are never produced, so enumerators built on this never see one.
pub fn valid_words() -> impl Iterator<Item = u16> {
    (0..16u16).flat_map(|op| {
        WRITABLE.flat_map(move |dst| (0..256u16).map(move |ab| op << 12 | (dst as u16) << 8 | ab))
    })
}

/// Values the VM reads for one synapse.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Inputs {
    pub pre: f32,
    pub post: f32,
    pub agg: f32,
    pub w: f32,
    pub tr: f32,
    pub sig: f32,
    pub nbr: f32,
    pub noise: f32,
    pub k1: f32,
    pub k2: f32,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Outputs {
    pub dw: f32,
    pub ntr: f32,
}

/// A learn program of 0 to `MAX_LEN` valid instructions.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Program {
    instrs: Vec<Instr>,
}

impl Program {
    pub fn new(instrs: Vec<Instr>) -> Result<Program, VmError> {
        if instrs.len() > MAX_LEN {
            return Err(VmError::TooLong(instrs.len()));
        }
        Ok(Program { instrs })
    }

    pub fn from_words(words: &[u16]) -> Result<Program, VmError> {
        Program::new(words.iter().map(|&w| decode(w)).collect::<Result<_, _>>()?)
    }

    pub fn instrs(&self) -> &[Instr] {
        &self.instrs
    }

    pub fn words(&self) -> Vec<u16> {
        self.instrs.iter().map(|i| i.encode()).collect()
    }

    /// Runs the program for one synapse.
    pub fn run(&self, x: &Inputs) -> Outputs {
        let mut r = [
            x.pre, x.post, x.agg, x.w, x.tr, x.sig, x.nbr, x.noise, 1.0, -1.0, x.k1, x.k2, 0.0, x.tr, 0.0,
            0.0,
        ];
        for i in &self.instrs {
            let d = i.dst as usize;
            r[d] = ops::eval(i.op, r[d], r[i.a as usize], r[i.b as usize]);
        }
        Outputs { dw: r[ops::DW as usize], ntr: r[ops::NTR as usize] }
    }

    /// Drops dead instructions, zeroes unused `b` fields and sorts the
    /// operands of commutative ops. Programs with equal canonical forms
    /// compute the same thing.
    pub fn canonical(&self) -> Program {
        // Backward liveness: only dw and ntr are live at the end.
        let mut live = 1u16 << ops::DW | 1u16 << ops::NTR;
        let mut kept = Vec::new();
        for &i in self.instrs.iter().rev() {
            if live & 1 << i.dst == 0 {
                continue;
            }
            live &= !(1 << i.dst);
            live |= i.reads().fold(0, |m, r| m | 1 << r);
            kept.push(i);
        }
        kept.reverse();
        for i in &mut kept {
            let info = &OPS[i.op as usize];
            if !info.uses_b {
                i.b = 0;
            } else if info.commutative && i.a > i.b {
                std::mem::swap(&mut i.a, &mut i.b);
            }
        }
        Program { instrs: kept }
    }

    /// The canonical rule number, such as `R1-3c01`.
    pub fn number(&self) -> String {
        let words = self.canonical().words();
        if words.is_empty() {
            return "R0".into();
        }
        let hex: Vec<String> = words.iter().map(|w| format!("{w:04x}")).collect();
        format!("R{}-{}", words.len(), hex.join("."))
    }

    /// Parses a rule number. The number need not be canonical.
    pub fn parse_number(s: &str) -> Result<Program, VmError> {
        let bad = || VmError::BadNumber(s.to_string());
        let body = s.trim().strip_prefix('R').ok_or_else(bad)?;
        if body == "0" {
            return Ok(Program::default());
        }
        let (len, hex) = body.split_once('-').ok_or_else(bad)?;
        let len: usize = len.parse().map_err(|_| bad())?;
        let words: Vec<u16> = hex
            .split('.')
            .map(|h| if h.len() == 4 { u16::from_str_radix(h, 16).ok() } else { None })
            .collect::<Option<_>>()
            .ok_or_else(bad)?;
        if words.len() != len {
            return Err(bad());
        }
        Program::from_words(&words)
    }

    /// Parses assembly: one instruction per line, or separated by `;` or `·`.
    /// `#` starts a comment.
    pub fn assemble(src: &str) -> Result<Program, VmError> {
        let mut instrs = Vec::new();
        for (n, line) in src.lines().enumerate() {
            let code = line.split('#').next().unwrap_or("");
            for stmt in code.split([';', '·']).filter(|s| !s.trim().is_empty()) {
                let err = |msg: String| VmError::Asm { line: n + 1, msg };
                instrs.push(assemble_one(stmt).map_err(err)?);
            }
        }
        Program::new(instrs)
    }

    /// One instruction per line, in the form `assemble` reads.
    pub fn disassemble(&self) -> String {
        self.instrs.iter().map(|i| disassemble_one(*i)).collect::<Vec<_>>().join("\n")
    }
}

fn assemble_one(stmt: &str) -> Result<Instr, String> {
    let toks: Vec<&str> = stmt.split_whitespace().collect();
    let op = ops::op_code(toks[0]).ok_or_else(|| format!("unknown op `{}`", toks[0]))?;
    let info = &OPS[op as usize];
    let want = if info.uses_b { 4 } else { 3 };
    if toks.len() != want {
        let form = if info.uses_b { "dst a b" } else { "dst a" };
        return Err(format!("`{}` takes `{} {form}`, got `{}`", info.name, info.name, stmt.trim()));
    }
    let reg = |t: &str| ops::reg_index(t).ok_or_else(|| format!("unknown register `{t}`"));
    let dst = reg(toks[1])?;
    if !WRITABLE.contains(&dst) {
        return Err(format!("cannot write to `{}`: read-only register", toks[1]));
    }
    let b = if info.uses_b { reg(toks[3])? } else { 0 };
    Ok(Instr { op, dst, a: reg(toks[2])?, b })
}

fn disassemble_one(i: Instr) -> String {
    let info = &OPS[i.op as usize];
    let name = |r: u8| REGS[r as usize].name;
    let mut s = format!("{} {} {}", info.name, name(i.dst), name(i.a));
    if info.uses_b {
        s = s + " " + name(i.b);
    }
    s
}

#[cfg(test)]
mod tests;
