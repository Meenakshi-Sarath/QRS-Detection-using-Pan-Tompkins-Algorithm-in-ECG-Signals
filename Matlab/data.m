clc;
clear;
% -------------------------------------------------
% 1. Load ONE ECG record (same as run_pt_record)
% -------------------------------------------------
recordName = 'database/mitdb/100';   % choose ONE record
lead = 1;
[signal, Fs, tm] = rdsamp(recordName, lead);
signal = double(signal);
fprintf('Loaded ECG: %d samples at %.1f Hz\n', length(signal), Fs);
 
% -------------------------------------------------
% 2. Resample to 200 Hz to match the RTL's sample_rate
%    (this step was missing -- without it, ecg.mem stays at the
%    record's native rate, e.g. 360Hz for MIT-BIH, which silently
%    scales every downstream BPM calculation by 360/200 = 1.8x)
% -------------------------------------------------
Fs_target = 200;
signal = resample(signal, Fs_target, Fs);
Fs = Fs_target;
fprintf('Resampled to: %d samples at %.1f Hz\n', length(signal), Fs);
 
% -------------------------------------------------
% 3. Limit samples (ROM size control) -- AFTER resampling, so this
%    truncates to 4096 samples of the TARGET 200Hz signal (~20.48s),
%    not 4096 samples of the original 360Hz signal (~11.4s)
% -------------------------------------------------
MAX_SAMPLES = 4096;   % match ADDR_WIDTH = 12
signal = signal(1:MAX_SAMPLES);
 
% -------------------------------------------------
% 4. Normalize to fixed-point range (signed)
% -------------------------------------------------
DATA_WIDTH = 16;
MAX_VAL = 2^(DATA_WIDTH-1) - 1;   % 32767
MIN_VAL = -2^(DATA_WIDTH-1);      % -32768
signal_norm = signal / max(abs(signal));  % [-1, 1]
signal_q = round(signal_norm * MAX_VAL);
% Saturation safety
signal_q(signal_q > MAX_VAL) = MAX_VAL;
signal_q(signal_q < MIN_VAL) = MIN_VAL;
 
% -------------------------------------------------
% 5. Write ecg.mem (HEX, two's complement)
% -------------------------------------------------
fid = fopen('ecg.mem', 'w');
for i = 1:length(signal_q)
    val = signal_q(i);
    if val < 0
        val = val + 2^DATA_WIDTH; % two's complement
    end
    fprintf(fid, '%04X\n', val);
end
fclose(fid);
fprintf('ecg.mem generated successfully (%d samples at %.1f Hz)\n', length(signal_q), Fs);
