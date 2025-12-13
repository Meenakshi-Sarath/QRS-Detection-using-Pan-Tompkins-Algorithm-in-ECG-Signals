
<img width="1823" height="816" alt="image" src="https://github.com/user-attachments/assets/cbf9d303-92ad-42e9-a0cb-38290cf6e6bd" />

BLOCK DIAGRAM OF MODULES ON VIVADO FOR FPGA IMPLEMENTATION
        ┌─────────────────────┐
        │  ECG INPUT SOURCE   │
        │ (ROM / ADC Samples) │
        └─────────┬───────────┘
                  │  (1 sample @ 360 Hz)
                  ▼
        ┌─────────────────────┐
        │   SAMPLE CLOCK       │
        │   (360 Hz Enable)    │
        └─────────┬───────────┘
                  │
                  ▼
        ┌─────────────────────┐
        │  BANDPASS FILTER     │
        │     (5–15 Hz)        │
        └─────────┬───────────┘
                  │
                  ▼
        ┌─────────────────────┐
        │   DERIVATIVE         │
        │ (Slope Enhancement) │
        └─────────┬───────────┘
                  │
                  ▼
        ┌─────────────────────┐
        │    SQUARING          │
        │ (Energy Emphasis)   │
        └─────────┬───────────┘
                  │
                  ▼
        ┌─────────────────────┐
        │ MOVING WINDOW        │
        │ INTEGRATION (150ms)  │
        └─────────┬───────────┘
                  │
                  ▼
        ┌─────────────────────┐
        │   PEAK DETECTOR      │
        │ (Local Max Finder)  │
        └─────────┬───────────┘
                  │
                  ▼
        ┌───────────────────────────┐
        │ ADAPTIVE THRESHOLD + FSM   │
        │ (Pan–Tompkins Decision)   │
        └─────────┬─────────────────┘
                  │
              R-PEAK FLAG
                  │
                  ▼
        ┌─────────────────────┐
        │ RR INTERVAL COUNTER  │
        │ (Time Between Beats)│
        └─────────┬───────────┘
                  │
                  ▼
        ┌─────────────────────┐
        │ HEART RATE CALC      │
        │   (BPM)              │
        └─────────┬───────────┘
                  │
                  ▼
        ┌─────────────────────┐
        │ ARRHYTHMIA DETECTOR  │
        │ (Normal / Brady /   │
        │  Tachy / Irregular) │
        └─────────┬───────────┘
                  │
                  ▼
        ┌─────────────────────┐
        │ OUTPUT INTERFACE     │
        │ (UART / Display)    │
        └─────────────────────┘
