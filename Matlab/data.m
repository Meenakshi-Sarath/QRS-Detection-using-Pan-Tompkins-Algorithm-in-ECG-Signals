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
% 2. Optional: limit samples (ROM size control)
% -------------------------------------------------
MAX_SAMPLES = 4096;   % match ADDR_WIDTH = 12
signal = signal(1:MAX_SAMPLES);

% -------------------------------------------------
% 3. Normalize to fixed-point range (signed)
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
% 4. Write ecg.mem (HEX, two's complement)
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

fprintf('ecg.mem generated successfully (%d samples)\n', length(signal_q));
