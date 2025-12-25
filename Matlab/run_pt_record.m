%Algorithm

function results = run_pt_record(recordName)

%Load ECG (Lead 1 only) 
[signal, Fs,~]=rdsamp(recordName,1);
signal = double(signal);

%Load annotations
[ann,~]=rdann(recordName,'atr');

%--------------------------------------------
%PAN TOMPKINS ALGORITHM
%--------------------------------------------

%Bandpass filter 
bpFilt = designfilt('bandpassiir','FilterOrder',4,'Halfpowerfrequency1',5,'Halfpowerfrequency2',15,'SampleRate',Fs);
%Apply bpf to the signal 
% If filtfilt doesn't accept bpFilt on your Matlab version use [b,a]=tf(bpFilt);
filteredSignal = filtfilt(bpFilt, signal);

%Compute derivative between adjacent samples
der = diff(filteredSignal);
der = der(:);
%Adds one extra value at end to match length of samples 
der(end+1) = der(end);

%Squaring
sq = der.^2;

%Moving window integration
N = max(1, round(0.15*Fs));
mwi = movmean(sq, N); %Highlights QRS Energy pattern

%Pan-Tompkins Adaptive Thresholding

%Initialise parameters
SPLE = 0; %Signal peak level estimate
NPLE = 0; %Noise peak level estimate

% ---------- Smart initialization for SPLE/NPLE and thresholds ----------
% Use first 2 seconds (or available samples) to get initial peak/noise stats
initDur = min(numel(mwi), round(2 * Fs)); % 2 seconds worth of MWI samples
[pks, locs] = findpeaks(mwi(1:initDur));   % MATLAB's findpeaks
if isempty(pks)
    % fallback: use robust summary stats
    SPLE = max(mwi(1:initDur));
    NPLE = median(mwi(1:initDur));
else
    % Use highest peaks as "signal", median of small peaks as "noise"
    % Keep SPLE robust to outliers
    SPLE = median(prctile(pks, max(1,numel(pks)-2))); % robust top estimate
    NPLE = median(pks); 
end

% Initialize thresholds from these estimates
Threshold_1 = NPLE + 0.25 * (SPLE - NPLE);
Threshold_2 = 0.5 * Threshold_1;

%Values used for initialisation (useful only in matlab not fpga) 
RR_missed = round(1.66 * Fs);
RR_low = 0.92 * RR_missed;
RR_high = 1.16 * RR_missed;

last_R_index = 1; %Stores the last detected R peak
r_peaks = []; %Stores indices of detected R peaks
min_refractory = round(0.20 * Fs); % 200 ms minimum distance between beats

for i = 2 : length(mwi)-1
    % Peak detection in MWI
    if (mwi(i) > mwi(i-1)) && (mwi(i) >= mwi(i+1))
        peak_value = mwi(i);
        peak_index = i;

        % Threshold test
        if (peak_value > Threshold_1)
            % Search nearby in the bandpassed ECG signal for the exact R peak
            search_radius = round(0.03 * Fs); % allows +-30 ms
            L = max(1, peak_index - search_radius);
            R = min(numel(filteredSignal), peak_index + search_radius);

            % Guard: ensure window is not empty
            if L > R 
                continue; % skip this candidate
            end

            win = signal(L:R);
            if isempty(win)
                continue; % extra safety
            end

            [x, imax] = max(abs(win));
            if x<0
                continue
            end
            true_R = L + imax - 1;

            % clamp true_R within valid index range
            true_R = min(max(1, true_R), numel(filteredSignal));

            % store as column
            if isempty(r_peaks)
                % first stored peak
                r_peaks(end+1,1) = true_R;
            else
                % if new detection is close to last stored peak
                if (true_R - r_peaks(end)) <= min_refractory
                    % keep the one with larger raw-amplitude (use absolute ECG)
                    if abs(signal(true_R)) > abs(signal(r_peaks(end)))
                        r_peaks(end) = true_R; % replace last with this stronger index
                    end
                    % else ignore this weaker candidate (do not add)
                else
                    % far enough to be a new beat -> append
                    r_peaks(end+1,1) = true_R;
                end
            end
            SPLE = 0.125 * peak_value + 0.875 * SPLE; % Update signal peak

            last_R_index = true_R;

        else
            NPLE = 0.125 * peak_value + 0.875 * NPLE;
        end

        % Update thresholds adaptively
        Threshold_1 = NPLE + 0.25 * (SPLE - NPLE);
        Threshold_2 = 0.5 * Threshold_1;
    end

    % Missed-beat logic (search-back)
    if (i - last_R_index > RR_missed)
        sL = max(1, last_R_index);
        sR = min(i, numel(mwi));
        if sL <= sR
            [val, ind] = max(mwi(sL:sR));
        else
            val = [];
            ind = [];
        end

        if ~isempty(val) && (val > Threshold_2)
            true_R = last_R_index + ind - 1;
            true_R = min(max(1, true_R), numel(filteredSignal));
            if isempty(r_peaks)
                 r_peaks(end+1,1) = true_R;
            else
                if (true_R - r_peaks(end)) <= min_refractory
                    if abs(signal(true_R)) > abs(signal(r_peaks(end)))
                        r_peaks(end) = true_R;
                    end
                else
                    r_peaks(end+1,1) = true_R;
                end
            end
            SPLE = 0.25 * val + 0.75 * SPLE;
        end
        last_R_index = i; % stability: advance the timer
    end
end

r_peaks = unique(r_peaks, 'stable');
if isempty(r_peaks)
    results.Sensitivity = 0;
    results.Precision = 0;
    results.F1 = 0;
    return;
end

%-----------------------------------------------
%Performance evaluation
%-----------------------------------------------

tolerance = round(0.15 * Fs); % +- 150 ms
TP = 0; FP = 0; FN = 0;
matched = false(length(r_peaks),1);

for j = 1:length(ann)
    [minDiff, idx] = min(abs(r_peaks - ann(j)));
    if minDiff <= tolerance
        TP = TP + 1;
        matched(idx) = true;
    else
        FN = FN + 1;
    end
end
FP = sum(~matched);

results.Sensitivity = TP/(TP+FN);
results.Precision   = TP/(TP+FP);
results.F1          = 2*(results.Precision*results.Sensitivity) / ...
                       (results.Precision + results.Sensitivity);
end
