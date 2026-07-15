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
*To detect just one heartbeat cycle (see one RR interval, confirm heart_rate produces a reading): you need at least two peaks,
so a bare minimum of somewhat over one RR interval — roughly 170+ samples at 72bpm, i.e. under a second of real ECG time. But
peak_detect's warm-up phase alone eats 256 samples (1.28s) before it'll even start making decisions, so realistically you need at
least ~2 seconds of samples before you'd see a single valid HR reading.
*To meaningfully evaluate rhythm classification, average HR stability, and catch bugs like the fixed-cadence lock we found:
That's why tb_ecg_top.v runs across ~4000 samples (20 seconds) — enough to capture roughly 24 real beats at 72bpm, giving a
statistically meaningful pattern rather than a lucky single data point.

## Testbench 

The clock generated hausing always #5 clk =~clk, has a 10ns periods = 100MHz frequency.

## How the ecg_mem file was generated


