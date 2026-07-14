# DEBUGGIN LOG (bugs found and fixed)

Three real bugs were found during verification — none of them from code review, all of them from actually running the design 
against real data. This log captures the root cause, how each was found, and the fix, in enough detail to explain confidently 
without having to re-derive anything.

## Bug 1: lpf numerically diverges on real ECG data

### Symptom: lpf passed its own unit test (randomized + directed
inputs, bit-exact match against an independent reference model). But when the full pipeline ran against real MIT-BIH data, 
lpf_out swung wildly (millions in magnitude, alternating sign) even when the input was nearly flat.

### Root cause: The original implementation was the textbook recursive form:
y[n] = 2y[n-1] - y[n-2] + x[n] - 2x[n-6] + x[n-12]

This is algebraically equivalent (via exact pole-zero cancellation) to a bounded 11-tap triangular FIR filter 
H(z) = [(1-z⁻⁶)/(1-z⁻¹)]², a repeated pole at z=1 exactly cancelled by a repeated zero at the same location. That 
cancellation is mathematically exact in infinite-precision arithmetic. But realizing it via a live feedback loop is 
numerically fragile: a repeated pole sitting exactly on the unit circle is only marginally stable (no damping), so any small
perturbation — here, simply the correlated, non-random nature of real ECG data, not even a rounding error — can excite the
un-cancelled mode. Once excited, nothing damps it back down, so it doesn't decay, it accumulates or even grows.

### Why the unit test didn't catch it: 
the test's reference model used the same recursive formula — a genuine independent re-implementation, but structurally 
identical math. Both sides drifted together, so they matched throughout. Random/directed test data also just never happened
to excite the instability the way real, sustained, correlated ECG data did. Lesson: a unit test built on a reference model 
of the same formula validates "hardware matches its equation," not "the equation itself is numerically sound."

### How it was actually confirmed (not just theorized): 
the "wide shadow-register" technique — see the dedicated section below.

### Fix: 
re-derived the exact FIR-equivalent form directly (no feedback loop at all) via polynomial division, then implemented it as
a cascaded double moving-sum (two 6-sample boxcar running sums in series) — same intended frequency response, provably
bounded for any input since there's no accumulator that can drift.

## Bug 2: hpf accumulates unbounded drift on real ECG data

### Symptom: 
similar to lpf — passed unit testing, but hpf_out overflowed its 24-bit register repeatedly on real data, corrupting
derivative/squaring/mwi downstream.

### Root cause: 
different mechanism from lpf, same category of problem. The original recursive form:
y[n] = y[n-1] - x[n]/32 + x[n-16] - x[n-17] + x[n-32]/32
also has an exact pole-zero cancellation at DC (verified algebraically: the numerator's coefficients sum to zero at z=1).
But the RTL computes x[0]>>>5 and x[32]>>>5 via floor-division (arithmetic right shift), discarding a small remainder every 
single cycle. Because the feedback coefficient is exactly 1 (no decay), this per-cycle truncation error doesn't average out
,it accumulates indefinitely, like integrating non-zero-mean noise produces an unbounded random walk.

### Confirmed via simulation: 
the true (unclipped) value drifted to roughly -86,000,000 within 1650 samples of real ECG data — far past the 24-bit
range (±8.4M).

### Fix:
re-derived the exact FIR-equivalent form via polynomial division, which reduces to a remarkably clean closed form:

y[n] = x[n-16] - (1/32) * sum(x[n] .. x[n-31])

i.e. "the center sample of a 32-sample window, minus the moving average of that window" — a standard DC-blocking structure, 
implemented as a single running sum (add-new/drop-oldest), no feedback path.

## Bug 3: peak_detect's noise floor (NPKI) gets permanently starved

### Symptom:
after fixing lpf/hpf, the full pipeline still locked onto a robotic, fixed detection cadence exactly equal to REFRACTORY+1 
samples — completely ignoring the actual signal.

### Root cause:
SPKI, NPKI, and TH1 (the adaptive threshold) all reset to 0. Since mwi_in (a squared value) is always non-negative, the
very first nonzero sample after reset satisfies mwi_in > TH1(=0), routing into the peak/SPKI branch — never the NPKI (noise)
branch. Once that happens, TH1 becomes NPKI + (SPKI-NPKI)>>2, and with NPKI stuck at 0 this is just SPKI>>2 — a quarter of 
whatever SPKI has climbed to, not a real noise floor. Since SPKI itself keeps chasing large incoming mwi_in values, this 
threshold never gets grounded in a genuine "quiet" baseline estimate, and the detector ends up firing essentially every time 
the refractory lockout clears.

### Fix: 
added an explicit warm-up/calibration phase (256 samples, ~1.3s at 200Hz) — during this window, no peak decisions are made; 
the module instead tracks the running max and mean of mwi_in. At the end of the window, SPKI is seeded from the observed 
max and NPKI from the observed mean — giving the adaptive threshold a real, data-derived starting point instead of 0. 
This mirrors the explicit learning phase used in real Pan-Tompkins implementations.

A related tuning finding (not a bug, a parameter choice): after all three fixes, occasional double-detection remained on a 
single beat (a genuine detection, then a spurious re-trigger the instant refractory cleared, since the tail of that same 
beat's MWI energy was still above threshold). The textbook REFRACTORY=40 (200ms) was too short for this recording's actual
heart rate (~40-50bpm); widening to REFRACTORY=60 (300ms) resolved it. Worth re-checking if used with faster-HR data —
too wide a refractory would start missing genuinely fast/back-to-back beats.


### The "wide shadow-register" debugging technique

A reusable technique, not specific to this project — worth being able to explain in general terms.

The idea: build two copies of the exact same computation side by side in the same simulation, fed identical inputs 
cycle-for-cycle — one using the module's real, narrow declared width, one using an artificially oversized register (64 bits 
here) that's essentially guaranteed to never run out of headroom.

If the two stay identical throughout, the real register's width was never the limiting factor — any wrong behavior observed 
is a deeper algorithmic issue, not overflow. If they diverge, and the divergence coincides with the real register's value 
approaching its max range, that's direct, unambiguous proof that overflow/wraparound is happening and is the cause.

### What it revealed here, two different diagnoses from the same technique:

#### hpf: 
the 64-bit shadow value drifted smoothly to ~-86 million genuine overflow of an otherwise slowly-drifting but well-behaved
computation. A width increase (or a non-accumulating redesign) fixes it.

#### lpf:
even the 64-bit shadow version also exploded, to astronomically large values — proving no amount of extra bits would
have helped. This pointed straight to a genuine numerical instability in the recursive formula itself, meaning the fix had 
to be architectural (the FIR reimplementation), not just "make the register bigger."

"It's the hardware-verification equivalent of switching from fixed-point to arbitrary-precision arithmetic to isolate 
whether an error comes from finite-width truncation or from the algorithm itself — if the bug survives unlimited
precision, it's not a width problem."

## Bug 4 (not RTL): sample-rate mismatch in test data generation

### Symptom: 
after fixing all of the above, the fully-corrected pipeline still reported heart rate roughly 1.8x too slow (~43bpm instead
of an expected ~72bpm).

### Root cause:
not an RTL bug at all. The MATLAB script generating ecg.mem pulled the raw signal directly from rdsamp() — which returns
data at MIT-BIH's native rate, 360Hz — and skipped the resample() step down to 200Hz that the RTL's sample_rate parameter 
assumes.
heart_rate.v computes hr = 60*SAMPLE_RATE / RR_interval_in_samples directly from that assumed rate, so every computed BPM was
silently scaled by 360/200 = 1.8x too slow.

### Fix: 
added signal = resample(signal, 200, Fs); to the MATLAB generation script, applied before truncating to the ROM's 4096-sample
capacity (truncating first would capture a different, shorter real-time window of the recording).

### Lesson worth remembering: 
every module downstream was internally consistent and individually correct — the bug was entirely in test-data provenance, 
not the design. Sanity-checking your test vectors' origin matters as much as testing the RTL itself; a "boring" 
data-generation script can silently invalidate an otherwise fully-correct design.
