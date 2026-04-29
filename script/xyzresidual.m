% %% Residual Computation Script
% clear; clc;
% 
% %% Load Data
% load('/MATLAB Drive/Thesis-data/residual/satellite_data.mat'); % satelliteTable
% load('/MATLAB Drive/Thesis-data/residual/GNSS_interp.mat', 'GNSS_interp'); % estimated user position
% load('/MATLAB Drive/Thesis-data/residual/GT_trim.mat', 'GT_trim'); % ground truth
% 
% traceSat = satelliteTable;
% 
% %% Extract time vectors
% t_gnss_interp = GNSS_interp(:,1);
% t_gt = GT_trim(:,1);
% 
% %% Output buffer
% result = {};
% 
% %% Loop through TRACE satellite data
% for i = 1:height(traceSat)
% 
%     try
%         % --- Satellite info ---
%         week = traceSat.gpst_week(i);
%         tow  = traceSat.gpst_sec(i);
%         satID = traceSat.satID{i};
% 
%         % --- Satellite position ---
%         s = [...
%             traceSat.satPosX(i), ...
%             traceSat.satPosY(i), ...
%             traceSat.satPosZ(i)];
% 
%         recvTime = traceSat.recvTime_str{i};
%         txTime   = traceSat.txTime_str{i};
% 
%         % --- Estimated user position ---
%         [~, idx_e] = min(abs(t_gnss_interp - tow));
%         e = GNSS_interp(idx_e, 2:4);
% 
%         % --- Ground truth position ---
%         [~, idx_gt] = min(abs(t_gt - tow));
%         t = GT_trim(idx_gt, 2:4);
% 
%         % --- Range computation ---
%         true_range = norm(s - t);
%         est_range  = norm(s - e);
%         residual   = est_range - true_range;
% 
%         % --- NEW: Position residuals (x, y, z) ---
%         dx = t(1) - e(1);
%         dy = t(2) - e(2);
%         dz = t(3) - e(3);
% 
%         % --- Store ---
%         result = [result; {
%             week, tow, satID, ...
%             e(1), e(2), e(3), ...
%             t(1), t(2), t(3), ...
%             dx, dy, dz, ...
%             true_range, est_range, residual, ...
%             recvTime, txTime
%         }];
% 
%     catch
%         continue;
%     end
% end
% 
% %% Convert to table
% varNames = {...
%     'Week','GPST_TOW','SatID', ...
%     'EstX','EstY','EstZ', ...
%     'GT_X','GT_Y','GT_Z', ...
%     'dX','dY','dZ', ...
%     'TrueRange','EstimatedRange','RangeResidual', ...
%     'RecvTime','TxTime'};
% 
% finalTable = cell2table(result, 'VariableNames', varNames);
% 
% %% Save
% save('/MATLAB Drive/Thesis-data/residual/final_residuals.mat', 'finalTable');
% 
% fprintf('Done. Computed %d residuals.\n', height(finalTable));
% 
% %% Preview
% head(finalTable)
% 
% %% Histogram of scalar residual
% res = finalTable.RangeResidual;
% 
% figure;
% histogram(res, 50);
% xlabel('Range Residual (m)');
% ylabel('Frequency');
% title('Histogram of Range Residuals');
% grid on;
% 
% %% Threshold analysis
% idx = (res > 1);
% 
% num_epochs = sum(idx);
% fprintf('Number of epochs with residual > 1 m: %d\n', num_epochs);
% 
% percentage = (num_epochs / height(finalTable)) * 100;
% fprintf('Percentage: %.2f%%\n', percentage);
% 
% %% Epoch-wise mean (receiver bias insight)
% epochSummary = groupsummary(finalTable, 'GPST_TOW', 'mean', 'RangeResidual');
% 
% meanResiduals = epochSummary.mean_RangeResidual;
% 
% totalMean = mean(meanResiduals);
% fprintf('Overall Mean Offset: %.4f m\n', totalMean);


%% Residual Computation Script (FUSED DATASET) — OPTIMIZED
clear; clc;

%% Load Data
load('C:\UrbanNav\DeepUrban\mat\satellite_data.mat');        % satelliteTable
load('C:\UrbanNav\DeepUrban\mat\satellite_obs_extended.mat');       % obsTable
load('C:\UrbanNav\DeepUrban\mat\GNSS_interp.mat','GNSS_interp');
load('C:\UrbanNav\DeepUrban\mat\GT_trim.mat','GT_trim');

traceSat = satelliteTable;
N = height(traceSat);

%% Time vectors (column vectors for vectorized ops)
t_gnss_interp = GNSS_interp(:,1);
t_gt           = GT_trim(:,1);

%% ---------------------------------------------------------------
%  OPT 1: Build a lookup map for obsTable rows
%  Key = "TOW_SatID" string — O(1) lookup instead of find() each loop
%% ---------------------------------------------------------------
disp('Building OBS lookup map...');
obsKeys = cellstr(string(obsTable.GPST_TOW) + "_" + string(obsTable.SatID));
obsMap  = containers.Map(obsKeys, (1:height(obsTable))');

%% ---------------------------------------------------------------
%  OPT 2: Vectorized nearest-neighbour indices for GNSS & GT
%  Uses sorted interp1 trick — computes ALL indices before the loop
%% ---------------------------------------------------------------
disp('Vectorizing time index lookups...');
tow_all = traceSat.GPST_TOW;   % Nx1

% Nearest index in t_gnss_interp for every TOW
idx_e_all = knnsearch(t_gnss_interp, tow_all);   % requires Stats Toolbox
% Fallback if no Stats Toolbox:
% idx_e_all = arrayfun(@(t) find_nearest(t_gnss_interp, t), tow_all);

% Nearest index in t_gt for every TOW
idx_gt_all = knnsearch(t_gt, tow_all);

%% ---------------------------------------------------------------
%  OPT 3: Pre-allocate output arrays (avoids dynamic cell growth)
%% ---------------------------------------------------------------
disp('Pre-allocating output arrays...');

% Numeric columns
Week        = traceSat.Week;
TOW         = traceSat.GPST_TOW;
SatID_col   = string(traceSat.satID);
RecvTime    = string(traceSat.recvTime_str);
TxTime      = string(traceSat.txTime_str);

pr_col   = nan(N,1);
dop_col  = nan(N,1);
snr_col  = nan(N,1);
az_col   = traceSat.Azimuth;
el_col   = traceSat.Elevation;

% Satellite positions (already in table — extract once as matrix)
S = [traceSat.satPosX, traceSat.satPosY, traceSat.satPosZ];   % Nx3

% Estimated & ground-truth positions (pre-fetched via vectorised indices)
E = GNSS_interp(idx_e_all,  2:4);   % Nx3
T = GT_trim    (idx_gt_all, 2:4);   % Nx3

%% ---------------------------------------------------------------
%  OPT 4: Vectorized OBS lookup (map-based, no find() inside loop)
%% ---------------------------------------------------------------
disp('Fetching OBS values...');
queryKeys = cellstr(string(tow_all) + "_" + SatID_col);   % cell array required by containers.Map
validMask = isKey(obsMap, queryKeys);                      % logical Nx1

validIdx               = cell2mat(values(obsMap, queryKeys(validMask)));
pr_col (validMask)     = obsTable.Pseudorange_L1(validIdx);
dop_col(validMask)     = obsTable.Doppler_L1    (validIdx);
snr_col(validMask)     = obsTable.SNR_L1        (validIdx);

%% ---------------------------------------------------------------
%  OPT 5: Fully vectorized range & residual computation (no loop!)
%% ---------------------------------------------------------------
disp('Computing ranges and residuals...');

diff_true = S - T;           % Nx3  satellite minus ground truth
diff_est  = S - E;           % Nx3  satellite minus estimate

true_range = sqrt(sum(diff_true.^2, 2));   % Nx1
est_range  = sqrt(sum(diff_est .^2, 2));   % Nx1
residual   = est_range - true_range;       % Nx1

dX = E(:,1) - T(:,1);               % keep same sign as residual
dY = E(:,2) - T(:,2);
dZ = E(:,3) - T(:,3);

%% ---------------------------------------------------------------
%  OPT 6: Assemble table directly from arrays (no cell accumulation)
%% ---------------------------------------------------------------
disp('Assembling final table...');

finalTable = table(...
    Week, TOW, SatID_col, ...
    pr_col, dop_col, snr_col, ...
    az_col, el_col, ...
    E(:,1), E(:,2), E(:,3), ...
    T(:,1), T(:,2), T(:,3), ...
    dX, dY, dZ, ...
    true_range, est_range, residual, ...
    RecvTime, TxTime, ...
    'VariableNames', { ...
        'Week','GPST_TOW','SatID', ...
        'Pseudorange','Doppler','SNR', ...
        'Azimuth','Elevation', ...
        'EstX','EstY','EstZ', ...
        'GT_X','GT_Y','GT_Z', ...
        'dX','dY','dZ', ...
        'TrueRange','EstimatedRange','RangeResidual', ...
        'RecvTime','TxTime'});

%% Save
save('C:\UrbanNav\DeepUrban\mat\final_residuals_fused.mat','finalTable');
fprintf('Done. Computed %d fused observations.\n', height(finalTable));
head(finalTable)

%% =============================================================
%  CREATE ML DATASET (CLEAN)
%% =============================================================
ML_table = finalTable(:, { ...
        'Week','GPST_TOW','SatID', ...
        'Pseudorange','Doppler','SNR', ...
        'Azimuth','Elevation', ...
        'EstX','EstY','EstZ', ...
        'GT_X','GT_Y','GT_Z', ...
        'dX','dY','dZ', ...
        'TrueRange','EstimatedRange','RangeResidual', ...
        'RecvTime','TxTime'});

ML_table = rmmissing(ML_table);
fprintf('ML dataset size after cleaning: %d samples\n', height(ML_table));

save('C:\UrbanNav\DeepUrban\mat\ML_dataset.mat', 'ML_table');
writetable(ML_table, 'C:\UrbanNav\DeepUrban\mat\ML_dataset.csv');
fprintf('Saved ML dataset as MAT and CSV ✔\n');
head(ML_table)


%% =============================================================
%  LOCAL HELPER  (used as fallback if Stats Toolbox unavailable)
%% =============================================================
function idx = find_nearest(vec, val)
    [~, idx] = min(abs(vec - val));
end

%% =============================================================
%  Combined Plot: SNR vs Elevation + Residual Histogram
%% =============================================================
figure;

% --- Subplot 1: SNR vs Elevation ---
subplot(2,1,1);   % 1 row, 2 columns, position 1
scatter(finalTable.Elevation, finalTable.SNR, 10, 'filled');
xlabel('Elevation (deg)');
ylabel('SNR (dB-Hz)');
title('SNR vs Elevation');
grid on;

% --- Subplot 2: Histogram of Range Residuals ---
subplot(2,1,2);   % position 2
res = finalTable.RangeResidual;

histogram(res, 50);
xlabel('Range Residual (m)');
ylabel('Frequency');
title('Residual Histogram');
grid on;


figure;
scatter(finalTable.Elevation, finalTable.RangeResidual, 10, 'filled');
xlabel('Elevation (deg)');
ylabel('Range Residual (m)');
title('Residual vs Elevation');
grid on;

figure;
scatter(finalTable.SNR, finalTable.RangeResidual, 10, 'filled');
xlabel('SNR (dB-Hz)');
ylabel('Range Residual (m)');
title('Residual vs SNR');
grid on;