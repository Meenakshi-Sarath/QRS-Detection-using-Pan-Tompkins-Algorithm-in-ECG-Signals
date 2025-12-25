
%Validation of algorithm on all records 

clc;
clear;

records = [100:109 111:119 121:124 200:234];
allResults = struct('record', {}, 'Sensitivity', {}, 'Precision', {}, 'F1', {});k=1;

for r = records
    rec=['database/mitdb/' num2str(r)];
    fprintf('Processing record %s \n',rec);

    try
        res = run_pt_record(rec);
        allResults(k).record = rec;
        allResults(k).Sensitivity = res.Sensitivity;
        allResults(k).Precision = res.Precision;
        allResults(k).F1 = res.F1;
        k = k + 1;
    catch ME
        warning('Record %s failed: %s', rec, ME.message);
    end
end

% -------------------------------
% OVERALL PERFORMANCE
% -------------------------------
Sens = [allResults.Sensitivity]; % 1 - miss rate
Prec = [allResults.Precision]; %accuracy of detected one
F1   = [allResults.F1]; %Overall balance score between sensitivity and precision

fprintf('\nOVERALL PERFORMANCE (48 RECORDS)\n');
fprintf('Mean Sensitivity : %.3f\n', mean(Sens));
fprintf('Mean Precision   : %.3f\n', mean(Prec));
fprintf('Mean F1 Score    : %.3f\n', mean(F1));

%Tells consistency across patients 
fprintf('\nStd Sensitivity  : %.3f\n', std(Sens));
fprintf('Std Precision    : %.3f\n', std(Prec));
fprintf('Std F1 Score     : %.3f\n', std(F1));
