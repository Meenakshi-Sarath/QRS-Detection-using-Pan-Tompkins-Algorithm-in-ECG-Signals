# ECG_ROM

## RTL

### CLock divider logic
The FPGA clock we take is 100MHz, usually defevlopment boards have 50/100/125MHz as their standard clock values, but this 
depends on the external crystal oscillator (PLL) which is soldered on the PCB next to the chip, since FPGA doesnt have a built-
in clock. 
We can find the value in the board's datasheet.  <br>
We are basically creating a 200Hz virtual clock. Should keep in mind that MIT-BIH recordings are sampled at 360Hz, but we are 
resampling it to 200Hz, so that we can verify our results with the paper I a referring

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

