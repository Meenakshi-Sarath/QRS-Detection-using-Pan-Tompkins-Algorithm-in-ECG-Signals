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
