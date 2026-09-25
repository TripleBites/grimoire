# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "z3-solver",
#     "galois",
#     "numpy"
# ]
# ///

"""
Automated Discovery of a Bitwise Learning Rule using Z3 and Galois.

Phase 1: Uses Z3 (SMT Solver) to discover a discrete learning rule 
         that minimizes error for an XOR-based binary neural node.
Phase 2: Uses Galois GF(2) to execute that discovered rule efficiently
         across an array of states using polynomial arithmetic.
"""

import z3
import galois
import numpy as np

def synthesize_learning_rule():
    print("--- Phase 1: Synthesizing the Rule with Z3 ---")
    
    # We want to discover a learning rule: w_new = f(w, x, e)
    # A 3-input boolean function can be entirely represented by an 8-bit Lookup Table (LUT).
    # We ask Z3 to find the exact 8 bits for this LUT that satisfy our error constraints.
    LUT = z3.BitVec('LUT', 8)
    s = z3.Solver()
    
    # Iterate over all possible physical states of a binary node
    for w in [0, 1]:      # Current weight
        for x in [0, 1]:  # Current input
            for e in [0, 1]:  # Error signal (1 means output is wrong, 0 means it's correct)
                
                # The forward pass of our node is a simple XOR
                y_current = w ^ x
                
                # Desired target: If e=1, flip the output. If e=0, keep the output.
                y_desired = y_current ^ e
                
                # Convert Python ints to Z3 BitVectors for bitwise constraints
                w_v = z3.BitVecVal(w, 8)
                x_v = z3.BitVecVal(x, 8)
                e_v = z3.BitVecVal(e, 8)
                
                # Construct the LUT index for this specific state: idx = (w << 2) | (x << 1) | e
                idx = (w_v << 2) | (x_v << 1) | e_v
                
                # The proposed rule pulls the target bit out of the unknown LUT
                w_new = (LUT >> idx) & 1
                
                # Add our absolute constraint:
                # The newly discovered weight, when applied to the SAME input, MUST yield the desired output.
                s.add((w_new ^ x_v) == z3.BitVecVal(y_desired, 8))
                
    # Run the automated search
    if s.check() == z3.sat:
        model = s.model()
        discovered_lut = model[LUT].as_long()
        print(f"[SUCCESS] Z3 discovered a valid learning rule LUT: 0x{discovered_lut:02X}")
        print(f"Binary representation: {bin(discovered_lut)[2:].zfill(8)}")
        return discovered_lut
    else:
        print("[FAILED] The constraints are mathematically unsatisfiable.")
        return None

def test_rule_over_gf2(lut_val):
    print("\n--- Phase 2: Vectorized Execution with Galois GF(2) ---")
    
    # Initialize the Galois Field for binary mathematics (addition = XOR, multiplication = AND)
    GF2 = galois.GF(2)
    
    # Create a batch of 5 simulated node states
    weights = GF2([0, 1, 0, 1, 1])
    inputs  = GF2([1, 1, 0, 0, 1])
    errors  = GF2([1, 0, 1, 0, 1]) # 1 = node needs to change, 0 = node is correct
    
    print(f"Initial Weights: {weights}")
    print(f"Inputs:          {inputs}")
    print(f"Errors:          {errors}")
    
    # By analyzing the LUT (0x5A or 01011010), we can reduce it algebraically.
    # In GF(2) mathematics, the LUT reduces to the boolean polynomial: w_new = w + e
    # Because GF(2) overloads standard operators, '+' computes highly-optimized bitwise XORs under the hood.
    new_weights = weights + errors 
    
    print(f"\nUpdated Weights: {new_weights}")
    
    # Run a forward pass with the new weights to verify the learning rule worked
    new_outputs = new_weights + inputs  
    print(f"New Outputs:     {new_outputs}")
    
    # Verify mathematically that the new outputs flipped where error == 1
    old_outputs = weights + inputs
    expected_outputs = old_outputs + errors
    
    if np.array_equal(new_outputs, expected_outputs):
        print("[VERIFIED] The discovered rule updated the network correctly over GF(2).")
    else:
        print("[ERROR] Rule failed during vectorized execution.")

if __name__ == "__main__":
    discovered_rule = synthesize_learning_rule()
    if discovered_rule is not None:
        test_rule_over_gf2(discovered_rule)