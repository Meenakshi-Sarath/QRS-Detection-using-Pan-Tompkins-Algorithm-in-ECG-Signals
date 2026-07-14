# Verification approach

How this project was verified, and why it's structured this way. Useful to re-read before an interview question like "walk me through your verification methodology."

## Two tiers of testing

### Unit-level: independent reference models, not shared code

Every module has its own self-checking testbench. The key discipline: each testbench's reference model is written independently from the DUT — different variable names, written fresh, not copy-pasted — so agreement between the two is genuine evidence of correctness, not just two copies of the same (possibly wrong) code agreeing with itself.

* Pure-math stages (lpf, hpf, derivative, squaring, mwi):
verified via a mix of directed cases (impulse response, step response, hand-computed corner cases) and randomized regression (hundreds of random inputs, checked every cycle against the independent reference).

* Decision-logic stages (peak_detect, heart_rate, arrhythmia_classify):
verified via directed synthetic scenarios with known expected outcomes (e.g. "feed peaks exactly 200 samples apart at
200Hz, expect exactly 60bpm out"), since there's no simple equation to diff against — the correctness criterion is behavioral.


### Integration-level: real data, not just synthetic vectors

tb_ecg_top.v runs the entire chain against real MIT-BIH data
(ecg.mem) and checks meaningful end-to-end properties:

*No X/Z propagation anywhere in the final outputs
*Peak spacing genuinely varies with the signal (the regression check that would have caught Bug 3 in 03-bugs-and-fixes.md — a pipeline locked onto a fixed cadence produces min_spacing == max_spacing, which this test explicitly checks against)
*Reported HR falls in a broad physiologically-plausible band
*Rhythm classification produces a real (non-UNKNOWN) result

This tier is what actually caught the three real bugs. Every module passed its unit test individually. None of the bugs were visible until the whole chain ran against real, sustained, correlated data — not random noise, not short directed sequences.

## Why clk_freq is overridden in simulation

ecg_rom computes sample_div = clk_freq / sample_rate to decide how
many clock edges separate each sample_tick. At the real target
frequency (100MHz) that's 500,000 clock edges per ECG sample — simulating
even a few thousand ECG samples at that rate would take an impractically
long time in a Verilog simulator. tb_ecg_top.v overrides clk_freq to
a small value (2000) purely to shrink that divider for fast simulation.
This is safe because every module's logic triggers off sample_tick
itself, not off any assumption about the absolute clock frequency — so
simulation timing and real hardware timing are functionally equivalent,
just running at different wall-clock speeds. Always use the real
clk_freq=100_000_000 default for synthesis — the override belongs
only in the testbench instantiation.

## Practical debugging techniques used

* Wide shadow-register comparison — see 03-bugs-and-fixes.md for
full detail; run the same computation in parallel at the real width
and at an oversized width to distinguish overflow from genuine
algorithmic instability.

*Cross-checking against an independently-derived closed form — for
both lpf and hpf, the fix was verified two ways: against a
from-scratch Python/MATLAB model of the intended filter equation,
and against the exact FIR-equivalent form derived by hand via
polynomial division — agreement across independently-derived methods
is much stronger evidence than agreement against a single reference.

*Full peak-spacing sequence inspection, not just summary
statistics — when debugging Bug 3, looking at every individual RR
interval (not just min/max) distinguished "genuinely tracking the
real signal with normal beat-to-beat variability" from "detecting
every other beat" — two very different failure signatures that a
single summary number can't tell apart.


## Running the tests

Each tb_<module>.v pairs with its matching <module>.v as simulation
sources — set the testbench as the simulation top in Vivado, run, check
the Tcl console for PASS/FAIL and mismatch counts.

For tb_ecg_top.v, also place ecg.mem in the simulation working
directory (see sim/generate_ecg_mem.m for how it's produced from a
MIT-BIH record — make sure the resample() step is present, see Bug 4
in 03-bugs-and-fixes.md).
