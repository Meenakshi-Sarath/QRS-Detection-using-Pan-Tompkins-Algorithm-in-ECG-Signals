# ALGORTIHM OVERVIEW 

This project implements the Pan-Tompkins algorithm (Pan J, Tompkins WJ, A Real-Time QRS Detection Algorithm, IEEE Trans 
Biomed Eng, 1985) in Verilog. This doc explains why the pipeline is shaped the way it is.

## The core problem

A raw ECG signal is just a voltage waveform. There's no built-in marker
saying "a heartbeat happened here." The QRS complex (the sharp spike
corresponding to ventricular depolarization — the actual heartbeat) has a
distinctive shape signature — steep slope, specific frequency content —
that differs from noise, baseline wander, muscle artifact, and even the
P-wave/T-wave parts of the same ECG cycle. Pan-Tompkins is a chain of
filters, each designed to amplify that one signature and suppress
everything else, until what remains is a clean energy pulse exactly where
each heartbeat occurred.

## Stage-by-stage rationale

### ecg_rom - sample source

Stand-in for a live ADC. See 03-bugs-and-fixes.md for the sample-rate
bug this project hit here (data generated at 360Hz, RTL assumed 200Hz).

### lpf - low-pass filter

Removes high-frequency noise and muscle artifact. Passes content below
roughly 11Hz. Implemented in this project as an 11-tap triangular FIR
(taps [1,2,3,4,5,6,5,4,3,2,1]), realized as a cascaded double
moving-sum rather than the textbook recursive form — see
03-bugs-and-fixes.md for why.

### hpf - high-pass filter

Removes baseline wander and DC offset. Passes content above roughly 5Hz.
lpf + hpf together form a bandpass roughly covering 5-11Hz — right
where QRS energy concentrates. Implemented here as
x[n-16] - moving_average(32-sample window), a standard DC-blocking
structure, again avoiding the textbook recursive form.

### derivative - slope detector

QRS complexes are defined more by their slope than their amplitude — a
tall, slow-moving artifact can have similar amplitude to a QRS complex
but a much smaller derivative. Taking the derivative converts "amplitude
difference" into "slope difference," a more QRS-specific signature.

### squaring - nonlinear amplifier

Makes the signal non-negative (needed since the next stage sums it — you
want accumulated energy, not a signal that can cancel itself). Also
nonlinearly emphasizes large values over small ones: a derivative twice
as large becomes four times the energy after squaring, sharpening the
contrast between genuine QRS slopes and smaller noise-driven ones.

### mwi - moving window integrator

Smooths the sharp squared-derivative spike into a wider "energy pulse"
whose width roughly matches the QRS complex's actual duration. This
matters because it makes the threshold-crossing decision in the next
stage robust to a single noisy sample — you're thresholding on
accumulated energy over a window, not one instantaneous value.

### peak_detect - decision maker

Adaptive threshold set between two running estimates: SPKI (signal/peak
level) and NPKI (noise level), with TH1 = NPKI + 0.25*(SPKI-NPKI).
Adaptive because ECG amplitude varies a lot between patients, electrode
placement, and even over time for the same patient — a fixed threshold
tuned for one recording fails on another.

Includes a refractory period (currently 300ms, see
03-bugs-and-fixes.md for why it's not the textbook 200ms) — a lockout
window after each detected peak, preventing a single wide QRS pulse (or
a T-wave following closely behind) from being counted as multiple
heartbeats. Mirrors the heart's own physiological refractory period.

Also includes a warm-up/calibration phase (256 samples, ~1.3s) before
enabling peak decisions — see 03-bugs-and-fixes.md for why this was
added.

### heart_rate - timer

Converts peak-to-peak sample spacing into BPM: hr = 60*SAMPLE_RATE / RR_interval_in_samples.
Requires two detected peaks before producing a valid reading (needs one
full RR interval to measure).

### arrhythmia_classify - rule-based classifier

Simple priority-ordered rules: IRREGULAR (RR varies >~25% from previous)
takes priority over BRADYCARDIA (HR<60) and TACHYCARDIA (HR>100), which
take priority over NORMAL. Not validated against a clinical
sensitivity/precision benchmark - see limitations in the README.

## Why hardware (Verilog/FPGA) instead of software?

* Deterministic, real-time timing — fixed clock cycles per sample,
no OS scheduling jitter or garbage-collection pauses, which matters for
a medical device.

* Power/size — a low-clock-speed FPGA/ASIC pipeline can be far more
power-efficient than a general-purpose CPU running the same algorithm
continuously (relevant for wearables/implantables).

* Clean parallelism potential — this design is a single serial
pipeline, but the same style extends naturally to multiple concurrent
channels/leads.
