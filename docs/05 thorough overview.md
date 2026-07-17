# ECG_ROM

## RTL

### CLock divider logic
The FPGA clock we take is 100MHz, usually defevlopment boards have 50/100/125MHz as their standard clock values, but this 
depends on the external crystal oscillator (PLL) which is soldered on the PCB next to the chip, since FPGA doesnt have a built-
in clock. 
We can find the value in the board's datasheet.  <br>
We are basically creating a 200Hz virtual clock. Should keep in mind that MIT-BIH recordings are sampled at 360Hz, but we are 
resampling it to 200Hz, so that we can verify our results with the paper I am referring

### Rom declaration

$readmemh, loads the ecg_mem file created using MATLAB, into our rom. But this is only a simulation construct.
For real synthesis/FPGA deployment, ROM contents are typically loaded via a different mechanism — e.g. a 
.coe/.mif file for Vivado's Block Memory Generator, or the FPGA bitstream itself if using inferred block RAM with an 
initial value 

* We have chosen ROM depth= 4096 samples ~ 20.48s of recording.
* Also, each heart beat takes 833ms of time. So no of samples in each heartbeat = 833/5 = 167 samples.
* To detect just one heartbeat cycle (see one RR interval, confirm heart_rate produces a reading): you need at least two peaks,
so a bare minimum of somewhat over one RR interval — roughly 170+ samples at 72bpm, i.e. under a second of real ECG time. But
peak_detect's warm-up phase alone eats 256 samples (1.28s) before it'll even start making decisions, so realistically you need at
least ~2 seconds of samples before you'd see a single valid HR reading.
* To meaningfully evaluate rhythm classification, average HR stability, and catch bugs like the fixed-cadence lock we found:
That's why tb_ecg_top.v runs across ~4000 samples (20 seconds) — enough to capture roughly 24 real beats at 72bpm, giving a
statistically meaningful pattern rather than a lucky single data point.

## Testbench 

The clock generated hausing always #5 clk =~clk, has a 10ns periods = 100MHz frequency.
<img width="221" height="137" alt="image" src="https://github.com/user-attachments/assets/8c4be45b-8d29-447c-8976-dde4fe412983" />

#### Why the original signal isn't centered at zero in the first place

Real ECG recordings commonly have a DC bias — the electrode-skin interface itself introduces an offset voltage that isn't part of the actual cardiac signal, plus slow baseline wander from breathing, electrode movement, or skin impedance changes. This is a completely normal, well-known characteristic of raw ECG recordings — it's not something wrong with the MIT-BIH data or your script, it's just what real, unprocessed biosignal data looks like before any conditioning.
We actually already found and measured this earlier for one of your ecg.mem files — the mean was around −10,832 (roughly a third of the full 16-bit range), consistently negative rather than centered at 0. What you're seeing on screen now (−3820, −5264, −4730...) is that same phenomenon — different specific values since this looks like a different run/record, but same underlying cause.

#### Is this a problem for the design?
No — and here's the important part: this is exactly what hpf exists to remove. A high-pass filter's whole job is stripping out DC offset and slow baseline wander, keeping only the higher-frequency content where QRS energy lives. So a raw, offset-biased ecg_sample at this very first stage of the pipeline is normal and expected — by the time the signal reaches hpf's output, that consistent negative bias should be gone (we confirmed this back when validating the fixed hpf on real data — its output oscillated around zero, unlike the raw input, unlike lpf's output which still carries the amplified DC offset through since lpf doesn't remove DC, only hpf does).

## How the ecg_mem file was generated

* rdsamp() is a WFDB toolbox function — it reads one MIT-BIH record (out of the 48 records, each 30 mins long) and returns three things: 
- signal (the actual waveform samples, already converted to physical units — millivolts — as floating-point doubles)
- Fs (the sampling frequency the record was captured at — 360Hz for MIT-BIH)
- tm (a time vector, one timestamp per sample, which this script loads but never actually uses). lead=1 selects the first of the (usually two) simultaneously-recorded channels in that record — MIT-BIH records typically have a "modified limb lead II" and a second, record-specific lead; lead=1 picks whichever one is stored first.

* Now, we resample it to 200Hz using resample() function
Internally, MATLAB's resample does this properly (not just "keep every Nth sample," which would distort the signal) — it applies an anti-aliasing low-pass filter before changing the rate, so frequency content above the new, lower Nyquist limit (100Hz here) doesn't fold back into the passband as spurious noise. After this line, signal genuinely represents the same waveform at 200 samples/second instead of 360, and Fs is updated to 200 so the rest of the script (and its print statements) stay consistent with reality.

* Truncates to the first 4096 samples — MATLAB array indexing (1:4096) grabs elements 1 through 4096 (MATLAB is 1-indexed, unlike Verilog/most languages). Since this now happens after resampling, those 4096 samples represent 20.48 seconds of real time at the corrected 200Hz rate, matching what addr_width=12 in ecg_rom expects to hold.

* We set the max and min value for 16 bit data (-32678 to 32677)

* We perform normalisation and then use round() to perform quantisation.

* We install a safety net or saturdation for (in case) outlier values (above max or below min)

* Now we open ecg.mem for writing, then loops through every sample. For any negative value, val + 2^16 produces the correct two's complement bit pattern (e.g. −1 + 65536 = 65535 = 0xFFFF, the standard all-ones representation of −1 in 16-bit two's complement). %04X formats the number as exactly 4 hexadecimal digits, uppercase, zero-padded — exactly the plain-text format $readmemh expects. fclose releases the file handle once done.

### What is WFDB and rdsamp() actually doing?

WFDB is the translator between "an obscure packed binary format from decades-old medical equipment" and "a clean floating-point array MATLAB can actually work with." rdsamp is the specific function that does the translation — unpack the bytes, look up the gain/baseline from the header, apply the conversion formula, return real millivolts.

WFDB (WaveForm DataBase) is PhysioNet's official software toolkit for reading, writing, and analyzing physiological signal data — it's the standard tooling the entire biomedical signal processing research community uses to work with databases like MIT-BIH. It exists because raw physiological recordings (ECG, EEG, blood pressure, etc.) aren't stored as simple flat files of numbers — they use a specific packed binary format 

(for MIT-BIH: 
- .dat files holding the actual sample data,
- .hea header files holding metadata like sampling rate/gain/number of channels
-  .atr files holding cardiologist-annotated beat labels used as ground truth for algorithm validation).
  
rdsamp specifically is WFDB's core signal-reading function. What it does under the hood, conceptually:
1) Parses the .hea header file to find the record's sampling rate, number of channels, and — critically — the gain and baseline values needed to convert raw stored integer codes back into real physical units.
2) Reads the raw, bit-packed .dat file (recall MIT-BIH's "format 212" packs two 12-bit samples into 3 bytes — genuinely awkward to parse by hand) and unpacks it into plain integer sample values.
3) Applies the gain/baseline conversion: physical_value = (raw_integer - baseline) / gain, converting those unpacked integers into real millivolt values as floating-point doubles.
4) Returns that clean, ready-to-use floating-point signal to your script, along with the sampling rate.

#### Why you can't just read the raw file yourself
Here's the part that makes WFDB genuinely necessary, not just convenient: MIT-BIH's raw .dat files don't even store one clean integer per sample — format 212 packs two 12-bit samples into 3 bytes (crammed together, splitting bits across byte boundaries) to save storage space, since these recordings are from the 1970s-80s when storage was expensive. (So like each sample is 12 bits (actually 11 + 1 extra room) instead of 16 bits (2 samples = 4 bytes).
So before you can even get to the "raw stored value = 1074" step above, you'd first need to:

- Read 3 raw bytes at a time
- Bit-shift and mask them apart to extract two separate 12-bit numbers
- Then apply the gain/baseline formula to each

Trying to hand-write that bit-unpacking logic yourself (in MATLAB, Python, or anywhere) is exactly the kind of tedious, error-prone, "someone already solved this correctly" problem that a shared toolkit exists for. rdsamp does all three steps invisibly and just hands you signal = [0.25, 0.31, 0.18, ...] (in mV) directly.

----------
WFDB is the translator between "an obscure packed binary format from decades-old medical equipment" and "a clean floating-point array MATLAB can actually work with." rdsamp is the specific function that does the translation — unpack the bytes, look up the gain/baseline from the header, apply the conversion formula, return real millivolts.

# LPF 

## RTL 
Cascaded double moving sum method (FIR not IIR)
* output reg [data_width+5:0] lpf_out: size is increased by 6 bits from 16 to 22
* It is a 2 stage structure
  - x_delay[0:5] — a 6-slot shift register holding the 6 most recent raw input samples. This is stage 1's "window."
  - stage1_sum — the running sum of those 6 samples (a simple 6-sample moving average, un-divided — it's a sum, not an average, since we're not dividing by 6 anywhere).
  - s1_delay[0:5] — a second 6-slot shift register, but this one holds the 6 most recent stage-1 sums (not raw samples) — this is stage 2's window.
  - stage2_sum — the running sum of those 6 stage-1 sums. This final value is lpf_out

 #### Why +3 bits of headroom at each stage:
 summing 6 terms can produce a result up to 6× larger than any single term. $clog2(6) = 3 (since 2³=8 ≥ 6), so 3 extra bits safely covers a 6-term sum without overflow, applied twice (once per stage), hence +3 for stage1_sum, another +3 on top of that for stage2_sum, totaling +6

 #### To reduce the number of computations (additions) we are doing in summing the elements:
 * we use the add-new, drop-oldest, running sum technique.
 * it maintains a running total and just updates it incrementally: subtract whatever's about to fall out of the 6-sample window (x_delay[5], the oldest sample currently held) and add the brand-new sample (ecg_in) coming in.
 * Same add-new/drop-oldest pattern, one level up — but notice the expression (stage1_sum - x_delay[5] + ecg_in) appears three separate times here. That's deliberate, not accidental repetition: it's this cycle's freshly-updated stage-1 sum, recomputed explicitly each time it's needed, rather than trying to read stage1_sum itself (which, due to non-blocking assignment, would still hold last cycle's stale value at this point in the same always block). This is the exact same "recompute rather than trust the lagging register" technique you correctly identified in your own mwi module's comment

## Testbench 

* The actual test sequence: reset, then three phases — a single impulse (apply(1000) followed by 20 zeros, to observe the filter's impulse response settle out), a step input (20 samples of a constant 500, to check steady-state behavior), then 500 fully random samples for broad regression coverage.

* The checker runs as a separate, concurrently-executing always block — triggered on negedge clk (the falling edge) specifically so it checks values after they've fully settled from the posedge update, avoiding any race condition where you'd be comparing a value against itself mid-update. 

#### Why sliding one boxcar across another gives a triangle
A boxcar function is just a flat-topped rectangle — constant height for some stretch, zero everywhere else.
Picture two identical rectangular blocks, each 6 units wide. Slide one across the other, and at every position, measure how much they overlap.

When they're far apart, overlap = 0.
As one starts sliding into the other, the overlap grows a little at a time — 1 unit, then 2, then 3...
When they're perfectly aligned, overlap is maximal — the full 6 units.
Then as it keeps sliding past, the overlap shrinks back down the same way it grew — 5, 4, 3, 2, 1, 0.

Plot "amount of overlap" against "how far you've slid" and you get exactly a triangle — rising linearly, peaking in the middle, falling linearly. That's not a coincidence or a special property of this particular filter — it's a completely general geometric fact: the convolution of a rectangle with itself is always a triangle, regardless of what the rectangle represents.

#### Why a boxcar average acts as a low-pass filter, conceptually
Think about what averaging does to a fast-wiggling signal versus a slowly-changing one, over any given 6-sample window:

A high-frequency signal swings up and down rapidly — within a short 6-sample window, it likely has samples with large variations. Averaging them together, those swings largely cancel out, leaving something small/ mean. High frequencies get suppressed and might cause a DC offset. This can then be removed using hpf.

A low-frequency (slowly varying) signal barely changes at all across 6 samples — they're all pointing roughly the same direction. Averaging them barely changes anything — the value passes through close to unaffected.

### Where the cutoff frequency actually comes from

<img width="250" height="251" alt="image" src="https://github.com/user-attachments/assets/1e1b46a4-3d44-4e75-9db0-16dd6c65210e" />

#### Frequency response:
* Imagine an experiment: feed a pure, single-frequency tone into your filter, measure how big the output wave is compared to the input.
* For each frequency, you get one number: what fraction of the input amplitude survived. That collection of numbers, plotted against frequency, is the frequency response.
  
* With N=6 and F_s=200Hz (this project's sample rate): f_null = 200/6 ≈ 33Hz. Beyond that point, the filter isn't cleanly rejecting anymore — sinc functions have ripply sidelobes past the first null — but everything meaningfully above roughly that frequency is heavily attenuated.

* A boxcar's frequency response doesn't switch off suddenly — it tapers down gradually, hits zero once (the null), then ripples back up a bit, tapers again, and so on. "Cutoff frequency" conventionally means something much gentler than "total rejection": it's the -3dB point, where the signal's power has dropped to half its original value — equivalently, where the amplitude has dropped to 1/√2 ≈ 0.707 of its original size. That's a much less strict condition than "completely zeroed out" (the null). So naturally, the -3dB point occurs at a lower frequency than the null — the signal is already noticeably weakened well before it's fully rejected.

* For our LPF, that ~11Hz number tells you: "below this, the QRS energy mostly survives; above this, it's being suppressed.

  <img width="157" height="44" alt="image" src="https://github.com/user-attachments/assets/49bd9f48-1564-4e46-978a-61f5b65f1878" />
 Plug in the specific case "output power is exactly half the input power
<img width="280" height="27" alt="image" src="https://github.com/user-attachments/assets/9bfd7bb7-bbd8-4542-87f6-cb9202f1db70" />

<img width="485" height="219" alt="image" src="https://github.com/user-attachments/assets/e75ad489-32e5-4b43-b9a6-dae9246da621" />

A single boxcar needs to attenuate down to 70.7% amplitude to hit its own -3dB point (~14.8Hz); but because this filter uses two boxcars in series, each one only needs to attenuate down to 84.1% amplitude to reach the combined system's -3dB point, and since less attenuation always happens at a lower frequency for a low-pass filter, that combined -3dB point ends up lower (~11Hz) than either single stage's own cutoff would be.

f_-3dB ≈ 0.443 × Fs/N = 0.443 × 33.3 ≈ 14.8 Hz <br>
- 0.443 is a standard published constant for boxcar filters (Lyon's DSP value for -3db cutoff freq)
- Two identical stages in series means the total response is H(f)². Squaring a response that's already 1/√2 at 14.8 Hz gives 0.5 there — i.e. -6dB, not -3dB. So the true -3dB point of the cascade has to occur earlier (lower frequency), because you're already down 6dB by the time you reach 14.8 Hz. Solving H(f)² = 1/√2 numerically instead of H(f) = 1/√2 moves the crossing down to about 11 Hz.


Cascading identical filter stages always sharpens the rolloff — because you're multiplying magnitude responses. So the -3dB bandwidth always shrinks when you cascade, and 33→14.8→11 Hz is really three different definitions on the same underlying curve: zero-crossing, single-stage half-power point, and two-stage half-power point.

### How my intially realised IIR implementation of lpf is converted to my 11 tap FIR filter

H(z) = Y(z)/X(z) = (1 - 2z⁻⁶ + z⁻¹²) / (1 - 2z⁻¹ + z⁻²) <br>
H(z) = [(1 - z⁻⁶) / (1 - z⁻¹)]²

(1 - z⁻⁶)/(1 - z⁻¹) = 1 + z⁻¹ + z⁻² + z⁻³ + z⁻⁴ + z⁻⁵ = Σ_{k=0}^{5} z⁻ᵏ <br>
This is exactly a 6 sample boxcar (moving-sum) filter

#### Why the recursive form blows up

The transfer function has a repeated pole and a repeated zero at z=1, and in exact arithmetic they cancel exactly, which is why the ideal system is a stable, bounded FIR filter. The problem is that this cancellation only holds in infinite-precision math. In fixed-point RTL, the truncating shifts introduce a small rounding error every cycle that isn't captured by that exact cancellation anymore. Because the pole sits exactly on the unit circle — not inside it — its natural response to any residual error is a ramp, not a decaying transient: a pole inside the unit circle would let that error die out over time, but a pole on the circle has unity gain, so the error just keeps accumulating, unbounded, forever. That growing value eventually exceeds the register's fixed width and wraps around.


* Poles at z=1 are only safe because of an exact matching zero, and that exact match is what breaks under truncation.
* The instability isn't from "having poles at z=1" per se (if they perfectly cancelled always, there'd be no problem) — it's that the cancellation itself isn't achievable in fixed-point arithmetic
* The denominator (1-z⁻¹)² puts a double pole exactly at z = 1, on the unit circle. The numerator (1-z⁻⁶)² happens to have a double zero at z = 1 too (since z=1 is one of the 6th roots of unity), so algebraically they cancel and the true system is FIR (finite, bounded impulse response).
* But in a recursive hardware realization, you're literally instantiating that double pole via feedback (2y[n-1] - y[n-2]). The cancellation with the feedforward zero only happens if the arithmetic is exact. A double pole sitting on the unit circle is marginally unstable — its natural response is a ramp (grows like n, not just a constant), and any tiny truncation/rounding error that isn't perfectly cancelled by the corresponding numerator zero gets integrated by that pole indefinitely.
* In fixed-point (22-bit) arithmetic there's always some residual, so the ramp/growth term never gets cancelled and accumulates — consistent with what you saw diverging within the first ~20–30 samples and then wrapping once it overflows the declared word width.

# HPF 

## RTL 

### Verifying the algebra: recursive form → exact FIR equivalent
y[n] - y[n-1] = -x[n]/32 + x[n-16] - x[n-17] + x[n-32]/32

Y(z)(1 - z⁻¹) = X(z)[ -1/32 + z⁻¹⁶ - z⁻¹⁷ + z⁻³²/32 ] <br>
Group the RHS into two pieces that both have (1-z⁻¹) as a factor:
Y(z)(1 - z⁻¹) = X(z)[ -1/32 + z⁻¹⁶ - z⁻¹⁷ + z⁻³²/32 ]
              = -(1/32)(1-z⁻¹) · S(z),   where S(z) = Σ_{k=0}^{31} z⁻ᵏ

Also z⁻¹⁶ - z⁻¹⁷ = z⁻¹⁶(1 - z⁻¹)

Y(z)(1-z⁻¹) = X(z)(1-z⁻¹)[ z⁻¹⁶ - (1/32)S(z) ] <br>
Y(z) = X(z)[ z⁻¹⁶ - (1/32)S(z) ]

Back to the time domain <br>
y[n] = x[n-16] - (1/32) · Σ_{k=0}^{31} x[n-k]

That's a textbook DC-blocking / high-pass structure: a moving average is a lowpass, so (delayed original) − (lowpass) = highpass.

The instability mechanism is the same story as your LPF: the recursion has a unity-gain pole at z=1 (1-z⁻¹ in the denominator), and it's only cancelled by a matching zero algebraically. In fixed-point RTL with truncating >>>5, the cancellation is never bit-exact, so that undamped pole integrates the leftover rounding error every cycle — which is exactly what produced the ~-86,000,000 drift in simulation.

So running_sum - x_delay[31] + lpf_in

#### Bit widths/ headroom 

- lpf_in, x_delay[]: 22 bits (data_width+5:0)
- running_sum: 27 bits — enough for 32 × 22-bit values
- hpf_out: 24 bits (data_width+7:0) — center tap (22 bits) minus a shifted-down average (~22 bits), needs at most ~23 bits worst case, so 24 bits gives comfortable margin.

No feedback accumulator anywhere — running_sum only ever depends on the last 32 bounded samples via add-newest/drop-oldest, so it's unconditionally bounded regardless of how many cycles run.

## Testbench

This testbench proves the RTL faithfully implements the intended equation — it's a great regression/implementation check. But since both DUT and reference use the same fixed-point formula (>>>5 truncation and all), it can't by itself catch a bug in the derivation

#### Matlab vs RTL implementation
I built a MATLAB reference model of the whole Pan-Tompkins pipeline and ran it against MIT-BIH records to validate the algorithm itself — Sensitivity/Precision against the annotated R-peaks. That gave me confidence the equations were right. I didn't go as far as modeling the exact fixed-point truncation behavior in MATLAB — for that I relied more on reasoning through the pole-zero cancellation analytically, and cross-checking a wide-accumulator ('shadow') version of the recursion in simulation to see the drift directly.

* The recursive (IIR) LPF and HPF forms are algebraically equivalent to bounded FIR filters, but only because a feedback pole exactly cancels a feedforward zero at z=1 — the unit circle.
* That cancellation only holds in infinite-precision arithmetic.
* In fixed-point RTL, the truncating right-shifts (dividing by 32, etc.) introduce a small rounding error every cycle, and because the pole sits exactly on the unit circle with unity gain, that residual error isn't damped (becausepole's natural response isn't bounded oscillation, it's a ramp that grows over time), it gets integrated by the feedback loop indefinitely
* So the true value grows without bound the longer you run it, regardless of how wide you make the registers.
* I confirmed this wasn't just a headroom issue by running a wide 'shadow' version of the same recursion in parallel in simulation — with no truncation, so it can't itself overflow — and watched the true, unclipped value drift into the tens of millions within a couple thousand samples on real ECG data.
* Since no register width can survive unbounded growth if you run long enough, the actual fix is to remove the feedback path entirely and realize the exact same transfer function as a direct FIR — a cascaded/windowed moving-sum structure with no accumulator — which is unconditionally stable for any bounded input

#### Matlab has infinite precision? No no 

* Both are finite precision, but MATLAB's error accumulates ~10^14 times slower, so it never becomes visible at ECG-length timescales, while the RTL's error becomes visible within ~1500 samples.
* A MATLAB double is IEEE 754 double-precision floating point: 64 bits total, giving you about 15-16 significant decimal digits of precision.
* MATLAB's filter() uses double-precision floating point, which is still finite-precision — not truly infinite — but its rounding error per operation is on the order of 10^-16, versus the RTL's >>>5 truncation which discards on the order of 3% of the value every cycle.
* That's about 14 orders of magnitude difference, so over a few thousand ECG samples, the double-precision version's accumulated error stays completely negligible while the RTL's becomes visible within ~1500 samples.
* So MATLAB isn't 'immune' to the underlying instability — it's just far, far slower to reveal it, because the same undamped-pole mechanism is technically present in both

# DERIVATIVE 

## RTL 

* Input and output are the same width (data_width+7:0, 24 bits) — unlike lpf/hpf, this stage doesn't need extra headroom for gain, because a derivative (difference between nearby samples) is typically smaller in magnitude than the samples themselves, not larger.
*  A 5-point numerical derivative estimate, weighted so it emphasizes the near samples.This is a smoothed slope estimate, not a raw single-step difference.

## Testbench 

* The apply() task is for driving one sample at a time.
* TASKS: we can include delays in the body of the task, it can return multiple values and is useful for code reusability.
* In our testbench, we check for an impulse input and randomised input.
* - This is the directed impulse-response test, feed a single impulse (800), then zeros, and hand-verify the exact expected output at each step by walking through the formula manually. Here we are genuinely working through what the module should produce, using an 'expected' variable that stores the expected value, not just re-running the DUT's own logic.
  - A second, independent reference model, running concurrently — its own delay line (rx[]), its own output register (ref_out), written completely separately from the DUT. This exists specifically to cover the randomized portion of the test, since hand-computing expected values for 300 random inputs one at a time isn't practical the way it was for the small directed impulse test above.


----------------
Unit-level self-checking testbenches are necessary but not sufficient — they're cheap to build and reliably catch implementation bugs (typos, indexing, timing), but by construction they can't catch a flawed specification, since a flawed spec implemented twice independently just agrees with itself. That's exactly why this project also needed integration testing against real data — that's the layer that actually found the real bugs, not the unit tests.

# SQUARING

## RTL 

der_in matches der_out's width from the derivative module — 24 bits, signed. sq_out is 2*data_width+15:0 — that's [47:0], 48 bits. the module's width was sized precisely to match squaring's actual worst case

## Testbench 

* test_vals is an array of 7 pre-chosen directed inputs (declared upfront rather than inline, since there are several deliberately curated corner cases to run through in sequence)
* The test_vals has directed corner cases when der_in 0, +-1, +- the boundary of the 24 bit input, and 2 arbitary values.
* After that go for 200 randomised values and see if the sqaured expected value matches the sq_out we get from our rtl module.

# MOVING WINDOW INTEGRATION 

- Coming out of squaring, the signal is a sequence of large, sharp, narrow spikes — one per genuine slope event, but very brief (just a few samples wide)
- mwi fixes this by smearing energy over a window — instead of asking "is this exact sample big," it asks "how much energy has accumulated over the last 32 samples"
- A brief spike gets spread into a wider, smoother "hump" whose width roughly matches a real QRS complex's actual duration (at 200Hz, 32 samples = 160ms — right in the range of a real QRS width).

## RTL 

* Both sq_in and mwi_out size is 48 bits [sq_width-1:0]
* buffer is a 32-slot shift register holding the 32 most recent squared-derivative values — this is the literal "window."
* sum is the running total of everything currently in that window, and this is the width-safety check worth doing explicitly: summing 32 values, each up to 48 bits, could need $clog2(32) = 5 extra bits of headroom to avoid overflow. (53 bits)
* Same "add-new, drop-oldest" running-sum trick used.

## Testbench 

So we are essentially performing 3 checks:
* Feed a constant value for longer than the window size, and the output must converge to exactly that constant, since averaging N copies of the same number gives that number back.
* Same principle, second property: a moving average's impulse response is mathematically guaranteed to be a flat rectangular pulse — height impulse/N, lasting exactly N samples, then dropping to exactly zero the instant the impulse ages out of the window.
* Next is a randomised regression of around 400 values, across the independent reference model that we implemented in the mwi testbench

# PEAK DETECTION 

## RTL 

#### Adaptive Threshold learning 
* The adaptive-threshold learning rule is self-referential, and starting all three state variables (SPKI, NPKI, TH1) at exactly 0 creates a degenerate feedback loop in the decision logic itself.
* Because Th1 starts at 0, the very first sample where mwi_in > 0 (which is essentially the first real sample) satisfies mwi_in > TH1 so the signal level peak estimate gets updated but NPKI doesnt get updated (stays at 0).
* data_width matches mwi_out width = 48.

#### Refractory
* Number of sample_tick cycles to lock out new detections after a peak fires. At 200 Hz, 60 samples = 300 ms. The comment explains this was originally 40 (200 ms, textbook value) but was widened after testing showed the tail-end of a single beat's MWI energy could still exceed threshold right as the shorter refractory period expired, causing a false double-detection on one physical heartbeat.

* We have a ref_cnt counter which counts for a period of refractory samples so that any peak detected in this range can be considered invalid.
* Another register counter counts till warmup samples are done for adaptive threshold learning after which a flag is turned high forever.


## Testbench

* First, drive WARMUP_SAMPLES (8) samples of a large value (90000), checking peak stays 0 every single time. This directly targets the fix: even though 90000 is a value that would trigger detection in normal mode, the calibration phase must ignore it entirely.
* then when this 90000 was applied, we also check that while the peak detected is 0, the SPKI is updated successfully.
* Apply a sample larger than the seeded SPKI (200000 > 90000) — since TH1 was seeded from data topping out at 90000, this new sample should clearly exceed threshold and fire peak.
* Next is a refractory check

### Overview of peak_detect because it might get a little confusing
- Phase A (warm-up, WARMUP_SAMPLES ticks): make zero peak decisions; just observe. Track max_seen (running max) and sum_seen (running sum) of mwi_in.
Seed at end of warm-up (mirrors real Pan-Tompkins learning-phase practice):

NPKI = mean(window) → crude noise-floor estimate
SPKI = max(window) → crude signal-amplitude estimate
TH1 = NPKI + (SPKI − NPKI) >> 2 → same 25%-of-the-gap rule used in steady state


- Phase B (steady state, unchanged Pan-Tompkins adaptive logic):

If mwi_in > TH1: it's a peak → assert peak, enter refractory, update SPKI = (7·SPKI + mwi_in) / 8
Else: treat as noise → update NPKI = (7·NPKI + mwi_in) / 8
Recompute TH1 = NPKI + (SPKI − NPKI) >> 2 every cycle

- Refractory logic

REFRACTORY (300 ms / 60 samples @ 200 Hz) blocks new detections for a fixed window after a peak, to prevent one physiological beat's MWI tail from re-triggering a spurious second detection.
Originally 200 ms (textbook value, 40 samples) — widened after integration testing showed double-detection on real ECG data.

- Why this recursive form is safe (unlike LPF/HPF)

The >>3 (÷8) exponential moving averages have coefficient 7/8, strictly inside the unit circle — not on it.
Truncation error introduced each cycle decays away over time instead of integrating unboundedly, because the feedback gain is <1.
Direct, useful contrast to draw against the LPF/HPF bug: same "recursive averaging" flavor, structurally totally different stability story.

# HEART RATE CALCULATION 

## RTL 

* Outputs of this stage: heartrate (8 bits), heart_rate_valid flag(1/0)- needed because for first peak, we cant calculate hr or rr interval , rr_interval value in terms of samples not seconds(16 bits).
* sample_counter counts samples since the last peak — this is literally the RR interval being measured in real time. last_rr stores the previous RR interval
* Now at every sample_tick we obviously incrememnt sample_counter by 1 and if a peak is detected, we put current rr-interval into last_rr and new rr_interval will be sample_counter +1 (non blocking statements so the current sample has to be added extra: hence the +1)

#### The issue with division
* This module implicitly trusts peak_detect's refractory logic (minimum 60-sample spacing) to prevent pathologically small RR intervals from ever reaching this division; it's not independently defensive.
* The core issue is dividing by a variable, data-dependent value, not a constant — so it can't be turned into a free shift the way the LPF/HPF's divide-by-32 was. My preferred fix would be to not compute BPM in RTL at all — output rr_interval (which is just a counter read, free) and let a downstream processor or display block compute BPM, since heart rate is a low-rate, human-facing output with no real-time constraint.
* If it had to stay in RTL, I'd use Vivado's Divider Generator IP with an explicit multi-cycle handshake rather than trusting the bare / operator to synthesize into something that meets timing, since inferred combinational dividers are a common source of failed timing closure on FPGA.

## Testbench

* We have 2 tasks: run_interval(val1) and check(label,exp_hr,exp_rr)
* run_interval basically runs and keeps the sample_tick high and peak 0 for val1 ticks and then peak is made high for one tick. It directly encodes "the interval between two peaks" as the task's parameter.
* check: Simple directed comparison against expected hr/rr_interval values, with descriptive pass/fail logging via a string label.
* Checks for cases of normal, bradycahrdia and tachycardia. while classification is not done, we are outputeed with the hr and rr values.

### Why use non blocking statements everywhere in our project when we need to add the +1 factor to it?

* In real silicon, every flip-flop in a clocked block samples its input at the same instant (the clock edge) and updates simultaneously. Non-blocking assignments (<=) mimic this exactly
* If you use = for multiple registers in one always block, the order you write the statements in changes the result

So the '+1' pattern isn't a cost of a bad choice — it's the natural, correct cost of accurately modeling one-cycle-latency pipeline registers, and non-blocking is what makes that model safe and predictable rather than order-dependent. I'd only reach for blocking assignments inside a combinational always block, where there's no clock edge and no risk of this kind of race.

# ARRHYTHMIA CLASSIFICATION

## RTL

* A simple 3-bit classification code for pointing out irregular beats, normal, bradychardia and tachycardia.
* So if the rr_diff between prev_rr_interval and new_rr_interval is > 25% of prev_rr_interval : classify as irregular rhythm
* hr<60 bpm: bradychardia hr>100bpm is tachycardia.

#### A fix: <br>
While reviewing this module I noticed the irregularity check reads rr_diff in the same clock edge it's written via a non-blocking assignment — which means it's actually comparing against the previous beat's diff, not the current one, a one-cycle stale read.  The fix was to compute the diff as a combinational expression inline, using the still-valid old prev_rr, rather than storing it in a register and reading it back a cycle late — the same 'recompute pending value inline' pattern I'd already used correctly elsewhere in the pipeline, like the HPF's running sum.

## Testbench 

* pulse_and_capture task: drives hr/rr_interval/hr_valid=1 for one beat, waits one clock (the edge the DUT samples on), then captures rhythm_class/alarm immediately after (#1 delay to clear the NBA update region) — matching the module's "valid for one cycle only" behavior.
* No independent reference model — correctness relies on hand-derived expected values, not a second, differently-implemented check.

# ECG TOP MODULE 

A second, independent initial block running concurrently with the main test — a watchdog timer. If the main test logic ever hangs (e.g., sample_tick never fires because of a misconfigured clk_freq/sample_rate ratio, and the wait statement blocks forever), this block guarantees the simulation still terminates with a diagnostic message instead of running indefinitely and looking like Vivado has simply frozen.

I implemented the Pan-Tompkins QRS detection pipeline — nine stages taking raw ECG through filtering, feature extraction, and adaptive peak detection, down to heart rate and rhythm classification. Every module has an independent, self-checking unit testbench, and the full chain has an integration testbench that runs against real MIT-BIH data. Along the way, I found and fixed four real bugs — two numerical-stability issues in the recursive filter implementations, an adaptive-threshold starvation issue in peak detection, and a sample-rate mismatch in how I generated my test data — none of which were visible from unit testing alone; all of them only showed up once I ran the whole thing against real, sustained data instead of synthetic test vectors. I also found and fixed a fifth, smaller bit-width headroom bug in the derivative stage specifically by deliberately widening my testbenches' randomized coverage after noticing an inconsistency in how much of each port's actual range was being exercised.

* Q: Why does tb_ecg_top.v check statistical properties instead of exact expected values, when your unit tests check exact values?
A: "At the unit level, I control the input completely, so I can compute an exact expected output by hand or with an independent model. At the integration level, the input is a real, messy ECG recording — I don't have an independently-verified exact expected heart rate for every single sample. So the checks shift from 'does this match a known value' to 'does this satisfy properties that must hold if the pipeline is working' — spacing varies, values stay in physiologically plausible ranges, no undefined states propagate. That's a deliberate methodological shift, not a weaker standard."


* Q: If you were deploying this on real hardware instead of simulation, what changes?
A: "ecg_rom gets replaced by a real ADC interface module — reading a live ADC chip over SPI or a parallel bus, with sample_tick generated from the ADC's own conversion-complete signal instead of a clock divider counting toward a target rate. Nothing downstream of that needs to change, because every other module only depends on the ecg_sample + sample_tick handshake, not on where the data comes from. I'd also remove or gate off the debug ports, and I'd need to re-run static timing analysis at the real 100MHz clock target rather than the simulation-only 2kHz override, to confirm every path — especially the wider multiply in squaring and the multi-term sums in mwi/lpf/hpf — actually closes timing at that frequency."


* Q: What about clock domain crossing, if the ADC has its own independent clock?
A: "Right now this design assumes one clock domain throughout — sample_tick is a clock-enable, not a genuine second clock. If a real ADC's conversion-complete signal came from a truly independent clock domain, I'd need a proper synchronizer — at minimum a two-flop synchronizer on that signal before it's used to gate anything in this design's clock domain — to avoid metastability. That's a real gap between what I built (single clock domain, verified in simulation) and a fully real-world-ready design."


* Q: What would you want before calling this production-ready for an actual medical device?
A: "Quite a bit more, honestly — clinical validation against annotated ground truth with computed sensitivity/precision (which my MATLAB reference does, but the RTL hasn't been benchmarked the same rigorous way), multi-lead support for redundancy, lead-off and motion-artifact detection, and given it's a medical device, a much more formal verification and safety-case process than what I did here, which was thorough for a portfolio/interview project but not to a regulatory (e.g. IEC 62304) standard. I'd frame what I built as a solid, well-verified proof-of-concept of the signal-processing core, not a finished product."
