%% Full Residual + IS-DPR Computation Script — UNIFIED & OPTIMIZED
clear; clc;

%% =========================
%  DATA LOADING
%% =========================
traceData = load('C:\UrbanNav\DeepUrban\mat\satellite_data.mat');          % satelliteTable
statData  = load('C:\UrbanNav\DeepUrban\mat\satellite_and_position.mat');  % satTable, posTable
gtECEF    = load('C:\UrbanNav\DeepUrban\mat\GT_ECEF.mat', 'GT_ECEF');     % [t_gt, X, Y, Z]

traceSat = traceData.satelliteTable;
statSat  = statData.satTable;
statPos  = statData.posTable;
GT_ECEF  = gtECEF.GT_ECEF;   % [t_gt, GT_X, GT_Y, GT_Z]

t_gt = GT_ECEF(:,1);

%% =========================
%  BUILD ESTIMATED POSITION LOOKUP MAP
%  Key = TOW (double) → [EstX, EstY, EstZ]
%% =========================
disp('Building estimated position lookup map...');
posKeys = num2cell(statPos.GPST_TOW);
posVals = num2cell([statPos.X_ECEF, statPos.Y_ECEF, statPos.Z_ECEF], 2);
posMap  = containers.Map(cell2mat(posKeys), posVals);

%% =========================
%  BUILD OBS LOOKUP MAP FROM statSat
%  Key = "TOW_SatID" → row index in statSat
%% =========================
disp('Building satellite obs lookup map...');
if iscell(statSat.SatID)
    satID_stat = string(statSat.SatID);
else
    satID_stat = string(statSat.SatID);
end
obsKeys = cellstr(string(statSat.GPST_TOW) + "_" + satID_stat);
obsMap  = containers.Map(obsKeys, (1:height(statSat))');

%% =========================
%  VECTORIZED GT INDEX LOOKUP
%% =========================
disp('Vectorizing GT time index lookups...');
tow_all    = traceSat.GPST_TOW;
idx_gt_all = knnsearch(t_gt, tow_all);   % fallback: arrayfun(@(t) find_nearest(t_gt,t), tow_all)

%% =========================
%  PRE-EXTRACT SATELLITE POSITION COLUMNS
%% =========================
S = [traceSat.satPosX, traceSat.satPosY, traceSat.satPosZ];   % Nx3
T = GT_ECEF(idx_gt_all, 2:4);                                  % Nx3  ground truth

SatID_col = string(traceSat.satID);
Week      = traceSat.Week;
TOW       = traceSat.GPST_TOW;
RecvTime  = string(traceSat.recvTime_str);
TxTime    = string(traceSat.txTime_str);

N = height(traceSat);

%% =========================
%  FETCH ESTIMATED POSITION + OBS PER ROW
%% =========================
disp('Fetching estimated positions and obs values...');

EstX_col = nan(N,1);  EstY_col = nan(N,1);  EstZ_col = nan(N,1);
az_col   = nan(N,1);  el_col   = nan(N,1);  snr_col  = nan(N,1);
statRes_col = nan(N,1);

% Build query keys for satStat map
queryKeys = cellstr(string(tow_all) + "_" + SatID_col);
validMask = isKey(obsMap, queryKeys);
validIdx  = cell2mat(values(obsMap, queryKeys(validMask)));

az_col     (validMask) = statSat.Azimuth  (validIdx);
el_col     (validMask) = statSat.Elevation(validIdx);
snr_col    (validMask) = statSat.SNR      (validIdx);

if ismember('StatRes', statSat.Properties.VariableNames)
    statRes_col(validMask) = statSat.StatRes(validIdx);
end

% Fetch estimated position via posMap (keyed by TOW)
towList_unique = unique(tow_all);
for k = 1:length(towList_unique)
    tow = towList_unique(k);
    if ~isKey(posMap, tow); continue; end
    epos = posMap(tow);             % 1x3: [EstX, EstY, EstZ]
    rows = (tow_all == tow);
    EstX_col(rows) = epos(1);
    EstY_col(rows) = epos(2);
    EstZ_col(rows) = epos(3);
end

%% =========================
%  VECTORIZED RANGE & RESIDUAL  (no loop)
%% =========================
disp('Computing ranges and residuals...');
E = [EstX_col, EstY_col, EstZ_col];   % Nx3

diff_true  = S - T;
diff_est   = S - E;

true_range = sqrt(sum(diff_true.^2, 2));
est_range  = sqrt(sum(diff_est .^2, 2));
residual   = est_range - true_range;

dX = E(:,1) - T(:,1);
dY = E(:,2) - T(:,2);
dZ = E(:,3) - T(:,3);

%% =========================
%  ASSEMBLE BASE TABLE
%% =========================
disp('Assembling base table...');
finalTable = table( ...
    Week, TOW, SatID_col, ...
    snr_col, az_col, el_col, statRes_col, ...
    EstX_col, EstY_col, EstZ_col, ...
    T(:,1), T(:,2), T(:,3), ...
    dX, dY, dZ, ...
    true_range, est_range, residual, ...
    RecvTime, TxTime, ...
    'VariableNames', { ...
        'Week','GPST_TOW','SatID', ...
        'SNR','Azimuth','Elevation','StatResidual', ...
        'EstX','EstY','EstZ', ...
        'GT_X','GT_Y','GT_Z', ...
        'dX','dY','dZ', ...
        'TrueRange','EstimatedRange','RangeResidual', ...
        'RecvTime','TxTime'});

%% =========================
%  PASS 1 — BUILD EPOCH MAP FOR IS-DPR
%% =========================
disp('Building epoch map for IS-DPR...');
epochMap = containers.Map('KeyType','double','ValueType','any');

for i = 1:height(finalTable)
    if isnan(finalTable.EstX(i)); continue; end   % skip rows with no estimated position

    tow   = finalTable.GPST_TOW(i);
    entry = struct( ...
        'row_idx',    i, ...
        'snr',        finalTable.SNR(i), ...
        'est_range',  finalTable.EstimatedRange(i), ...
        'true_range', finalTable.TrueRange(i), ...
        'satID',      finalTable.SatID(i));

    if isKey(epochMap, tow)
        epochMap(tow) = [epochMap(tow), entry];
    else
        epochMap(tow) = entry;
    end
end

%% =========================
%  PASS 2 — COMPUTE IS-DPR
%% =========================
disp('Computing IS-DPR...');
IS_DPR_col   = nan(height(finalTable), 1);
RefSatID_col = repmat("N/A", height(finalTable), 1);

epochTOWs = keys(epochMap);
for k = 1:length(epochTOWs)
    tow     = epochTOWs{k};
    satList = epochMap(tow);

    if length(satList) < 2; continue; end

    snr_vals     = arrayfun(@(x) x.snr, satList);
    [~, ref_idx] = max(snr_vals);

    Pr_ref  = satList(ref_idx).est_range - satList(ref_idx).true_range;
    ref_sat = satList(ref_idx).satID;

    for s = 1:length(satList)
        Pr_i = satList(s).est_range - satList(s).true_range;
        IS_DPR_col  (satList(s).row_idx) = Pr_i - Pr_ref;
        RefSatID_col(satList(s).row_idx) = ref_sat;
    end
end

finalTable.IS_DPR   = IS_DPR_col;
finalTable.RefSatID = RefSatID_col;

%% =========================
%  SAVE
%% =========================
save('C:\UrbanNav\DeepUrban\mat\final_residuals_fused.mat', 'finalTable');
fprintf('Done. Total entries: %d\n', height(finalTable));
head(finalTable)

%% =========================
%  ML DATASET
%% =========================
ML_table = rmmissing(finalTable);
fprintf('ML dataset size after cleaning: %d samples\n', height(ML_table));

save('C:\UrbanNav\DeepUrban\mat\ML_dataset.mat', 'ML_table');
writetable(ML_table, 'C:\UrbanNav\DeepUrban\mat\ML_dataset.csv');
fprintf('Saved ML dataset as MAT and CSV.\n');

%% =========================
%  RESIDUAL ANALYSIS PLOTS
%% =========================
res = finalTable.RangeResidual;
CN0 = finalTable.SNR;

figure;
subplot(2,1,1);
scatter(finalTable.Elevation, CN0, 10, 'filled');
xlabel('Elevation (deg)'); ylabel('SNR (dB-Hz)');
title('SNR vs elevation'); grid on;

subplot(2,1,2);
histogram(res, 50);
xlabel('Range residual (m)'); ylabel('Frequency');
title('Residual histogram'); grid on;

figure;
scatter(finalTable.Elevation, res, 10, 'filled');
xlabel('Elevation (deg)'); ylabel('Range residual (m)');
title('Residual vs elevation'); grid on;

figure;
scatter(CN0, res, 10, 'filled');
xlabel('SNR (dB-Hz)'); ylabel('Range residual (m)');
title('Residual vs SNR'); grid on;

satNames = unique(finalTable.SatID);
figure; tiledlayout('flow');
for i = 1:length(satNames)
    idx = finalTable.SatID == satNames(i);
    nexttile;
    histogram(finalTable.RangeResidual(idx), 30);
    title(['Sat ', char(satNames(i))]); grid on;
end
sgtitle('Residual per satellite');

idx_thresh = abs(res) > 10;
fprintf('|Residual| > 10 m : %d (%.2f%%)\n', ...
    sum(idx_thresh), sum(idx_thresh)/height(finalTable)*100);

%% =========================
%  IS-DPR ANALYSIS PLOTS
%% =========================
valid = ~isnan(finalTable.IS_DPR);

figure;
histogram(finalTable.IS_DPR(valid), 50);
title('IS-DPR distribution');
xlabel('IS-DPR (m)'); ylabel('Count'); grid on;

%% =========================
valid0 = ~isnan(finalTable.StatResidual);

figure;
histogram(finalTable.StatResidual(valid0), 50);
title('Postfitresidual distribution');
xlabel('postfitres (m)'); ylabel('Count'); grid on;

figure;
scatter(finalTable.Elevation(valid), abs(finalTable.IS_DPR(valid)), 5, 'filled');
xlabel('Elevation (deg)'); ylabel('|IS-DPR| (m)');
title('Elevation vs IS-DPR'); grid on;

figure;
scatter(finalTable.GPST_TOW(valid), finalTable.IS_DPR(valid), 5, 'filled');
xlabel('GPST TOW (s)'); ylabel('IS-DPR (m)');
title('IS-DPR over time'); grid on;

figure;
scatter(finalTable.SNR(valid), abs(finalTable.IS_DPR(valid)), 5, 'filled');
xlabel('SNR (dB-Hz)'); ylabel('|IS-DPR| (m)');
title('SNR vs IS-DPR'); grid on;

figure; tiledlayout('flow');
for i = 1:length(satNames)
    idx = (finalTable.SatID == satNames(i)) & valid;
    if sum(idx) < 2; continue; end
    nexttile;
    histogram(finalTable.IS_DPR(idx), 30);
    title(['Sat ', char(satNames(i))]); grid on;
end
sgtitle('IS-DPR per satellite');

fprintf('\n--- IS-DPR summary ---\n');
fprintf('Mean   IS-DPR : %.4f m\n', mean(finalTable.IS_DPR(valid)));
fprintf('Std    IS-DPR : %.4f m\n', std(finalTable.IS_DPR(valid)));
fprintf('Max  |IS-DPR| : %.4f m\n', max(abs(finalTable.IS_DPR(valid))));
fprintf('IS-DPR > 10 m : %d (%.2f%%)\n', ...
    sum(abs(finalTable.IS_DPR(valid)) > 10), ...
    sum(abs(finalTable.IS_DPR(valid)) > 10) / sum(valid) * 100);

%% =========================
%  LOCAL HELPER  (Stats Toolbox fallback)
%% =========================
function idx = find_nearest(vec, val)
    [~, idx] = min(abs(vec - val));
end