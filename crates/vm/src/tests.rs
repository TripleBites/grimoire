use super::*;
use std::collections::BTreeSet;

fn asm(src: &str) -> Program {
    Program::assemble(src).unwrap()
}

fn inputs() -> Inputs {
    Inputs {
        pre: 0.5,
        post: -2.0,
        agg: 1.5,
        w: 0.25,
        tr: 0.75,
        sig: 3.0,
        nbr: 0.1,
        noise: -0.3,
        k1: 0.1,
        k2: 0.5,
    }
}

/// The word with its unused `b` field zeroed, which is what disassembly keeps.
fn zero_unused_b(word: u16) -> u16 {
    if OPS[(word >> 12) as usize].uses_b {
        word
    } else {
        word & 0xfff0
    }
}

// M0: invalid dst is rejected everywhere.

#[test]
fn decode_rejects_every_word_with_read_only_dst() {
    for word in 0..=u16::MAX {
        let dst = ((word >> 8) & 0xf) as u8;
        match decode(word) {
            Err(VmError::InvalidDst { word: w, dst: d }) => {
                assert!(dst < 12 && w == word && d == dst)
            }
            Ok(i) => assert!(dst >= 12 && i.encode() == word),
            Err(e) => panic!("unexpected error {e}"),
        }
    }
}

#[test]
fn valid_words_never_emits_read_only_dst() {
    let words: Vec<u16> = valid_words().collect();
    assert_eq!(words.len(), 16 * 4 * 256);
    assert!(words.iter().all(|&w| (w >> 8) & 0xf >= 12));
    assert!(words.iter().all(|&w| decode(w).is_ok()));
    assert!(words.windows(2).all(|p| p[0] < p[1]));
}

#[test]
fn programs_with_invalid_words_are_rejected() {
    assert!(matches!(Program::from_words(&[0x3c01, 0x3001]), Err(VmError::InvalidDst { .. })));
    assert!(Program::parse_number("R1-3001").is_err());
}

#[test]
fn assembler_rejects_read_only_dst() {
    let err = Program::assemble("mul pre pre post").unwrap_err();
    assert_eq!(err.to_string(), "line 1: cannot write to `pre`: read-only register");
    for name in ["pre", "post", "agg", "w", "tr", "sig", "nbr", "noise", "one", "neg", "k1", "k2"] {
        let msg = Program::assemble(&format!("mov {name} pre")).unwrap_err().to_string();
        assert!(msg.contains("read-only register"), "{msg}");
    }
}

// M0: assemble and disassemble round-trip for all 16 ops.

#[test]
fn every_valid_word_round_trips_through_assembly() {
    let mut ops_seen = BTreeSet::new();
    for word in valid_words() {
        let p = Program::from_words(&[word]).unwrap();
        let back = Program::assemble(&p.disassemble()).unwrap();
        assert_eq!(back.words(), vec![zero_unused_b(word)], "{}", p.disassemble());
        ops_seen.insert(word >> 12);
    }
    assert_eq!(ops_seen.len(), 16);
}

#[test]
fn multi_instruction_programs_round_trip() {
    let src = "mul t0 pre sig\nema ntr t0 k1\nthr t1 ntr k2\nsign dw t1";
    let p = asm(src);
    assert_eq!(p.disassemble(), src);
    assert_eq!(asm("mul t0 pre sig · ema ntr t0 k1; thr t1 ntr k2 # c\nsign dw t1"), p);
    assert_eq!(Program::parse_number(&p.number()).unwrap(), p);
}

// M0: the empty program is the identity.

#[test]
fn empty_program_is_identity() {
    let p = asm("");
    assert_eq!(p.number(), "R0");
    assert_eq!(Program::parse_number("R0").unwrap(), p);
    for tr in [-3.0, 0.0, 0.75, 1e6] {
        let out = p.run(&Inputs { tr, ..inputs() });
        assert_eq!(out, Outputs { dw: 0.0, ntr: tr });
    }
}

// M0: Hebbian canonicalizes to R1-3c01 with operands in either order.

#[test]
fn hebbian_operand_order_does_not_matter() {
    assert_eq!(asm("mul dw post pre").number(), "R1-3c01");
    assert_eq!(asm("mul dw pre post").number(), "R1-3c01");
}

#[test]
fn reference_rule_numbers() {
    let rules = [
        ("mul dw pre sig", "R1-3c05"),
        ("mul t0 post w; sub t0 pre t0; mul dw t0 post", "R3-3e13.2e0e.3c1e"),
        ("mul t0 pre sig; ema ntr t0 k1; thr t1 ntr k2; sign dw t1", "R4-3e05.bdea.cfdb.5cf0"),
    ];
    for (src, number) in rules {
        assert_eq!(asm(src).number(), number, "{src}");
    }
}

#[test]
fn canonicalization_drops_dead_code_and_unused_b() {
    assert_eq!(asm("mul t0 pre post").number(), "R0");
    assert_eq!(asm("mov dw pre; mov dw post").number(), "R1-0c10");
    assert_eq!(asm("mov t1 sig; mov t0 pre; mul dw t0 post").number(), "R2-0e00.3c1e");
    assert_eq!(Program::from_words(&[0x6c1f]).unwrap().number(), "R1-6c10");
    // sel and ema read their destination, so the earlier write stays live.
    assert_eq!(asm("mov dw pre; sel dw post sig").canonical().instrs().len(), 2);
    assert_eq!(asm("mov ntr pre; ema ntr post k1").canonical().instrs().len(), 2);
}

#[test]
fn canonical_form_is_idempotent_and_preserves_behavior() {
    let mut numbers = BTreeSet::new();
    for word in valid_words() {
        let p = Program::from_words(&[word]).unwrap();
        let c = p.canonical();
        assert_eq!(c.canonical(), c);
        assert_eq!(p.run(&inputs()), c.run(&inputs()), "{}", p.disassemble());
        numbers.insert(p.number());
    }
    // 16 x 2 x 16 x 16 = 8,192 raw programs writing dw or ntr collapse to 4,352
    // distinct rules, plus R0 from the dead writes to t0 and t1.
    assert_eq!(numbers.len(), 4353);
}

#[test]
fn assembler_errors_are_clear() {
    let cases = [
        ("foo dw pre", "unknown op `foo`"),
        ("mul dw pre bar", "unknown register `bar`"),
        ("mul dw pre", "`mul` takes `mul dst a b`"),
        ("abs dw pre post", "`abs` takes `abs dst a`"),
        ("mov dw pre\nmov ntr tr\nadd dw pre", "line 3:"),
    ];
    for (src, want) in cases {
        let msg = Program::assemble(src).unwrap_err().to_string();
        assert!(msg.contains(want), "{src}: {msg}");
    }
    let long = ["mov dw pre"; MAX_LEN + 1].join("\n");
    assert_eq!(Program::assemble(&long), Err(VmError::TooLong(MAX_LEN + 1)));
}

#[test]
fn bad_numbers_are_rejected() {
    for s in ["", "3c01", "R1", "R2-3c01", "R1-3c0", "R1-3c01.", "Rx-3c01", "R1-zzzz"] {
        assert!(matches!(Program::parse_number(s), Err(VmError::BadNumber(_))), "{s}");
    }
}

// Interpreter semantics.

#[test]
fn op_semantics() {
    let cases: [(&str, f32); 16] = [
        ("mov dw sig", 3.0),
        ("add dw pre sig", 3.5),
        ("sub dw pre sig", -2.5),
        ("mul dw pre post", -1.0),
        ("neg dw post", 2.0),
        ("sign dw post", -1.0),
        ("abs dw post", 2.0),
        ("min dw pre post", -2.0),
        ("max dw pre post", 0.5),
        ("gt dw pre post", 1.0),
        ("sel dw pre post", -2.0), // dw starts at 0, so b
        ("ema ntr pre k2", 0.625), // 0.5 x 0.75 + 0.5 x 0.5
        ("thr dw post sig", 0.0),
        ("clip dw sig post", 2.0),
        ("relu dw post", 0.0),
        ("tanh dw pre", 0.5f32.tanh()),
    ];
    for (src, want) in cases {
        let out = asm(src).run(&inputs());
        let got = if src.contains("ntr") { out.ntr } else { out.dw };
        assert_eq!(got, want, "{src}");
    }
    assert_eq!(asm("sign dw t0").run(&inputs()).dw, 0.0);
    assert_eq!(asm("mov t0 one; sel dw pre post").run(&inputs()).dw, -2.0);
    assert_eq!(asm("mov dw one; sel dw pre post").run(&inputs()).dw, 0.5);
    assert_eq!(asm("mov dw neg").run(&inputs()).dw, -1.0);
    let nan = Inputs { sig: f32::NAN, ..inputs() };
    asm("clip dw pre sig").run(&nan); // must not panic
}

#[test]
fn reference_rules_compute_expected_deltas() {
    let x = inputs();
    assert_eq!(asm("mul dw pre post").run(&x).dw, x.pre * x.post);
    assert_eq!(asm("mul dw pre sig").run(&x).dw, x.pre * x.sig);
    let oja = asm("mul t0 post w; sub t0 pre t0; mul dw t0 post").run(&x).dw;
    assert_eq!(oja, x.post * (x.pre - x.post * x.w));
    let bop = asm("mul t0 pre sig; ema ntr t0 k1; thr t1 ntr k2; sign dw t1").run(&x);
    let ntr = (1.0 - x.k1) * x.tr + x.k1 * (x.pre * x.sig);
    assert_eq!(bop, Outputs { dw: 1.0, ntr });
}
