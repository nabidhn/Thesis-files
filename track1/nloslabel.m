%% GNSS Label Merging and Analysis Script
clear; clc;

%% 1. Load the Residual Data
resPath = 'C:\KLTdataset\label\0610_KLT1_203\final_residuals.mat';
if ~exist(resPath, 'file')
    error('Residual file not found. Please run the computation script first.');
end
load(resPath); % This loads 'finalTable'

%% 2. Load the CSV Label Data
csvPath = 'C:\KLTdataset\data\GNSS\20210610\track1\satellite_labels.csv';
if ~exist(csvPath, 'file')
    error('CSV label file not found. Please run the Python parser first.');
end

% readtable automatically handles the headers
csvTable = readtable(csvPath);

%% 3. Prepare Tables for Joining
% Ensure the CSV column names match finalTable for the join keys
csvTable.Properties.VariableNames{'Timestamp_UTC'} = 'UnixTime';
csvTable.Properties.VariableNames{'Satellite_Name'} = 'SatID';

% Convert UnixTime in both tables to the same data type (int64) to ensure match
finalTable.UnixTime = int64(finalTable.UnixTime);
csvTable.UnixTime = int64(csvTable.UnixTime);

%% 4. Merge Tables
% We use 'inner' join to only keep satellites that have both GNSS data AND image labels
% Use 'left' join if you want to keep all GNSS data even if no image label exists
mergedTable = innerjoin(finalTable, csvTable, 'Keys', {'UnixTime', 'SatID'});

fprintf('Merge complete. Records before: %d | Records after: %d\n', ...
    height(finalTable), height(mergedTable));

%% 5. Analysis: LOS vs NLOS Statistics
% Separate residuals based on the label
losIdx  = strcmp(mergedTable.Label, 'LOS');
nlosIdx = strcmp(mergedTable.Label, 'NLOS');

resLOS  = mergedTable.Residual(losIdx);
resNLOS = mergedTable.Residual(nlosIdx);

fprintf('\n--- Statistics ---\n');
fprintf('LOS  Mean Error: %.2f m | Std: %.2f m\n', mean(resLOS), std(resLOS));
fprintf('NLOS Mean Error: %.2f m | Std: %.2f m\n', mean(resNLOS), std(resNLOS));

%% 6. Visualization
figure('Name', 'GNSS Error Analysis by Image Labels');

% --- Subplot 1: Residual Distribution ---
subplot(2,1,1);
hold on;
histogram(resLOS, 'BinWidth', 1, 'DisplayName', 'LOS (Clear Sky)', 'FaceColor', 'g');
histogram(resNLOS, 'BinWidth', 1, 'DisplayName', 'NLOS (Obstructed)', 'FaceColor', 'r');
xlabel('Residual Error (meters)');
ylabel('Frequency');
title('Residual Error Distribution by Visibility Label');
legend();
grid on;

% --- Subplot 2: Elevation vs SNR (Colored by Label) ---
subplot(2,1,2);
gscatter(mergedTable.Elevation, mergedTable.SNR, mergedTable.Label, 'rg', 'o+', 5);
xlabel('Elevation (degrees)');
ylabel('SNR (dB-Hz)');
title('SNR vs Elevation colored by Image Label');
grid on;

%% 7. Save the Final Labeled Dataset

%% 7. Save the Final Labeled Dataset

% Save as MAT (for MATLAB use)
mergedStruct = table2struct(mergedTable);
savePath = 'C:\KLTdataset\label\0610_KLT1_203\final_labeled_residuals.mat';
save(savePath, 'mergedStruct');

% Save as CSV (for Python / ML)
csvSavePath = 'C:\KLTdataset\label\0610_KLT1_203\final_labeled_residuals.csv';
writetable(mergedTable, csvSavePath);

fprintf('\nSaved MAT to: %s\n', savePath);
fprintf('Saved CSV to: %s\n', csvSavePath);

numLOS  = sum(strcmp(mergedTable.Label, 'LOS'));
numNLOS = sum(strcmp(mergedTable.Label, 'NLOS'));

fprintf('\n--- Label Counts ---\n');
fprintf('LOS  count : %d\n', numLOS);
fprintf('NLOS count : %d\n', numNLOS);