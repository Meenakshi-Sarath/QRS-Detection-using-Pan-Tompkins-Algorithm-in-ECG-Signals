# ECG R-Peak Detection, Heart Rate & Arrhythmia Classification (Verilog)

A hardware implementation of the Pan-Tompkins QRS detection algorithm in
Verilog, taking a raw single-lead ECG signal through a filter pipeline to
detect heartbeats, compute instantaneous heart rate, and classify basic
rhythm abnormalities (bradycardia, tachycardia, irregular rhythm).

Verified against real ECG recordings from the MIT-BIH Arrhythmia Database.

## Pipeline

<svg width="700" height="380" viewBox="0 0 700 380" xmlns="http://www.w3.org/2000/svg" role="img">
<title>ECG signal processing pipeline flowchart</title>
<desc>Snake-pattern flowchart: ECG signal, low-pass filter, high-pass filter, derivative, squaring, moving window integrator, peak detection, heart rate, arrhythmia classification</desc>
<defs>
<marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
<path d="M2 1L8 5L2 9" fill="none" stroke="#5F5E5A" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
</marker>
</defs>

<rect width="700" height="380" fill="#FFFFFF"/>

<!-- Row 1 -->
<g>
<rect x="40" y="40" width="180" height="60" rx="8" fill="#E6F1FB" stroke="#185FA5" stroke-width="1"/>
<text x="130" y="70" text-anchor="middle" dominant-baseline="central" font-family="Helvetica, Arial, sans-serif" font-size="14" fill="#0C447C">ECG signal</text>
</g>
<g>
<rect x="260" y="40" width="180" height="60" rx="8" fill="#E6F1FB" stroke="#185FA5" stroke-width="1"/>
<text x="350" y="70" text-anchor="middle" dominant-baseline="central" font-family="Helvetica, Arial, sans-serif" font-size="14" fill="#0C447C">Low-pass filter</text>
</g>
<g>
<rect x="480" y="40" width="180" height="60" rx="8" fill="#E6F1FB" stroke="#185FA5" stroke-width="1"/>
<text x="570" y="70" text-anchor="middle" dominant-baseline="central" font-family="Helvetica, Arial, sans-serif" font-size="14" fill="#0C447C">High-pass filter</text>
</g>

<!-- Row 2 (reversed) -->
<g>
<rect x="480" y="160" width="180" height="60" rx="8" fill="#E6F1FB" stroke="#185FA5" stroke-width="1"/>
<text x="570" y="190" text-anchor="middle" dominant-baseline="central" font-family="Helvetica, Arial, sans-serif" font-size="14" fill="#0C447C">Derivative</text>
</g>
<g>
<rect x="260" y="160" width="180" height="60" rx="8" fill="#E6F1FB" stroke="#185FA5" stroke-width="1"/>
<text x="350" y="190" text-anchor="middle" dominant-baseline="central" font-family="Helvetica, Arial, sans-serif" font-size="14" fill="#0C447C">Squaring</text>
</g>
<g>
<rect x="40" y="160" width="180" height="60" rx="8" fill="#E6F1FB" stroke="#185FA5" stroke-width="1"/>
<text x="130" y="190" text-anchor="middle" dominant-baseline="central" font-family="Helvetica, Arial, sans-serif" font-size="14" fill="#0C447C">Moving window integrator</text>
</g>

<!-- Row 3 -->
<g>
<rect x="40" y="280" width="180" height="60" rx="8" fill="#E6F1FB" stroke="#185FA5" stroke-width="1"/>
<text x="130" y="310" text-anchor="middle" dominant-baseline="central" font-family="Helvetica, Arial, sans-serif" font-size="14" fill="#0C447C">Peak detection</text>
</g>
<g>
<rect x="260" y="280" width="180" height="60" rx="8" fill="#E1F5EE" stroke="#0F6E56" stroke-width="1"/>
<text x="350" y="310" text-anchor="middle" dominant-baseline="central" font-family="Helvetica, Arial, sans-serif" font-size="14" fill="#085041">Heart rate</text>
</g>
<g>
<rect x="480" y="280" width="180" height="60" rx="8" fill="#E1F5EE" stroke="#0F6E56" stroke-width="1"/>
<text x="570" y="310" text-anchor="middle" dominant-baseline="central" font-family="Helvetica, Arial, sans-serif" font-size="14" fill="#085041">Arrhythmia classify</text>
</g>

<!-- Row 1 arrows (left to right) -->
<line x1="220" y1="70" x2="256" y2="70" stroke="#5F5E5A" stroke-width="1.5" marker-end="url(#arrow)"/>
<line x1="440" y1="70" x2="476" y2="70" stroke="#5F5E5A" stroke-width="1.5" marker-end="url(#arrow)"/>

<!-- Row1 -> Row2 (down, right column) -->
<line x1="570" y1="100" x2="570" y2="156" stroke="#5F5E5A" stroke-width="1.5" marker-end="url(#arrow)"/>

<!-- Row 2 arrows (right to left) -->
<line x1="480" y1="190" x2="444" y2="190" stroke="#5F5E5A" stroke-width="1.5" marker-end="url(#arrow)"/>
<line x1="260" y1="190" x2="224" y2="190" stroke="#5F5E5A" stroke-width="1.5" marker-end="url(#arrow)"/>

<!-- Row2 -> Row3 (down, left column) -->
<line x1="130" y1="220" x2="130" y2="276" stroke="#5F5E5A" stroke-width="1.5" marker-end="url(#arrow)"/>

<!-- Row 3 arrows (left to right) -->
<line x1="220" y1="310" x2="256" y2="310" stroke="#5F5E5A" stroke-width="1.5" marker-end="url(#arrow)"/>
<line x1="440" y1="310" x2="476" y2="310" stroke="#5F5E5A" stroke-width="1.5" marker-end="url(#arrow)"/>

</svg>

| Stage | Purpose |
| --- | --- |
| ecg_rom | Sample source (ROM-based stand-in for a live ADC feed) |
| lpf | Low-pass filter: removes high-frequency noise |
| hpf | High-pass filter: removes baseline wander / DC offset |
| derivative | Amplifies steep slopes characteristic of the QRS complex |
| squaring | Nonlinear amplification, emphasizes true QRS energy |
| mwi | Moving window integrator: smooths into a QRS-width energy pulse |
| peak_detect |Adaptive-threshold R-peak detection with refractory lockout |
| heart_rate | Converts peak-to-peak timing into BPM |
| arrhythmia_classify | Rule-based rhythm classification (NORMAL / BRADYCARDIA / TACHYCARDIA / IRREGULAR) |

Full block diagram and design rationale: see docs/ (or inline module
comments — each module's header explains what it computes and why).

## Repo structure

ecg-fpga/
├── README.md
├── rtl/
│   ├── ecg_rom.v
│   ├── lpf.v
│   ├── hpf.v
│   ├── derivative.v
│   ├── squaring.v
│   ├── mwi.v
│   ├── peak_detect.v
│   ├── heart_rate.v
│   ├── arrhythmia_classify.v
│   └── ecg_top.v
├── tb/
│   ├── tb_lpf.v
│   ├── tb_hpf.v
│   ├── ... (one per module)
│   └── tb_ecg_top.v
├── sim/
|   ├── generate_ecg_mem.m
|   └── ecg.mem
└── docs/                 block diagrams, design notes
|   ├── FILL IN
|   └── FILL IN 

## Verification approach

Every module has an independent, self-checking testbench, no manual
waveform inspection required. Each testbench builds its own reference
model (not copy-pasted from the DUT) and asserts a PASS/FAIL with a
mismatch count.

* Unit level: lpf, hpf, derivative, squaring, mwi, peak_detect, heart_rate, arrhythmia_classify — each verified in
isolation against directed test cases, impulse/step responses where applicable, and randomized regression.
* Integration level: tb_ecg_top.v runs the full chain against real MIT-BIH data (ecg.mem) and checks end-to-end behavior.
R-peak spacing tracks the real signal, reported HR falls in a physiologically plausible range, and rhythm classification
produces real output.

## CAN PUT IN DOCS 
A real finding worth knowing about

Two of the filter stages (lpf, hpf) were originally implemented as
recursive/IIR-style difference equations, matching the textbook
Pan-Tompkins formulas. Both passed unit testing with random and directed
inputs. Both failed on real ECG data — not because the equations were
wrong, but because realizing a marginal-stability, repeated-pole-at-DC
filter recursively is numerically fragile: small per-cycle truncation
(hpf) or even just correlated real input (lpf) caused the recursive
state to diverge over hundreds of samples, corrupting every downstream
stage. Confirmed via a "wide shadow register" technique — running the
same computation in parallel with an oversized (64-bit) accumulator to
distinguish genuine overflow from genuine algorithmic instability.

Fixed by re-deriving each filter's exact FIR-equivalent form (bounded
windowed sums, no feedback path) — same intended frequency response,
provably can't diverge. See comments at the top of lpf.v / hpf.v for
the full derivation.

This is a good illustration of why integration testing with realistic
data matters even when every unit test passes — a unit test built on a
reference model of the same (possibly flawed) formula will happily
agree with a flawed DUT forever.

Running the tests

Each tb_<module>.v is self-contained — pair it with its matching
<module>.v as simulation sources, set the testbench as the simulation
top, run, and check the console/Tcl output for PASS/FAIL.

For tb_ecg_top.v, also add ecg.mem to the simulation working
directory (generated by sim/generate_ecg_mem.m — see script for the
MATLAB → MIT-BIH → 200Hz resampling pipeline). Note: clk_freq is
overridden to a small value in the testbench purely for simulation
speed; use the real target frequency (default 100MHz) for synthesis.

## Known limitations / possible extensions

* Single-lead only.
* peak_detect requires a quiet ~1.3s warm-up window to calibrate its adaptive threshold before trusting detections.
* Arrhythmia classification is simple threshold/rule-based, not validated against clinical sensitivity/precision metrics
(a companion MATLAB reference implementation computes those against PhysioNet annotations — see sim/).
* No explicit lead-off / motion-artifact detection.


## Background

Based on: Pan J, Tompkins WJ. A Real-Time QRS Detection Algorithm.
IEEE Trans Biomed Eng. 1985.

Test data: MIT-BIH Arrhythmia Database (PhysioNet).
