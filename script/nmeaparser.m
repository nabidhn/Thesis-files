% clc; clear;
% 
% filename = '/MATLAB Drive/Thesis-data/pos/UrbanNav-HK-Deep-Urban-1.ublox.f9p.nmea';
% fid = fopen(filename,'r');
% 
% % =========================
% % CONSTANTS
% % =========================
% a = 6378137.0;          % WGS84 semi-major axis
% e2 = 6.69437999014e-3;  % eccentricity squared
% 
% % =========================
% % STORAGE
% % =========================
% data = struct([]);
% i = 0;
% 
% % temp variables
% utcTime = "";
% gpsWeek = NaN;
% gpsTow  = NaN;
% 
% lat = NaN; lon = NaN;
% X = NaN; Y = NaN; Z = NaN;
% 
% while ~feof(fid)
%     line = fgetl(fid);
% 
%     % =========================
%     % PUBX TIME (BEST SOURCE)
%     % =========================
%     if contains(line,'$PUBX,04')
%         parts = split(line,',');
% 
%         utcTime = parts{3};          % hhmmss.ss
%         gpsTow  = str2double(parts{5});
%         gpsWeek = str2double(parts{6});
% 
%         dateStr = parts{4};          % ddmmyy
% 
%         dd = str2double(dateStr(1:2));
%         mm = str2double(dateStr(3:4));
%         yy = 2000 + str2double(dateStr(5:6));
% 
%         dt = datetime(yy,mm,dd);
%         doy = day(dt,'dayofyear');
%     end
% 
%     % =========================
%     % POSITION (GNRMC)
%     % =========================
%     if contains(line,'$GNRMC')
%         parts = split(line,',');
% 
%         % lat
%         rawLat = str2double(parts{4});
%         lat = floor(rawLat/100) + mod(rawLat,100)/60;
%         if contains(parts{5},'S'), lat = -lat; end
% 
%         % lon
%         rawLon = str2double(parts{6});
%         lon = floor(rawLon/100) + mod(rawLon,100)/60;
%         if contains(parts{7},'W'), lon = -lon; end
% 
%         % speed (not stored anymore, optional)
%     end
% 
%     % =========================
%     % FINALIZE EPOCH (triggered by PUBX)
%     % =========================
%     if contains(line,'$PUBX,04')
% 
%         % -------------------------
%         % LLA → ECEF CONVERSION
%         % -------------------------
%         if ~isnan(lat) && ~isnan(lon)
% 
%             latR = deg2rad(lat);
%             lonR = deg2rad(lon);
% 
%             h = 0; % assume sea level (or replace if you have altitude)
% 
%             N = a / sqrt(1 - e2*sin(latR)^2);
% 
%             X = (N + h) * cos(latR) * cos(lonR);
%             Y = (N + h) * cos(latR) * sin(lonR);
%             Z = (N*(1-e2) + h) * sin(latR);
%         end
% 
%         % -------------------------
%         % STORE EPOCH
%         % -------------------------
%         i = i + 1;
% 
%         data(i).Week      = gpsWeek;
%         data(i).GPST_TOW  = gpsTow;
%         data(i).Date      = datestr(datetime(yy,mm,dd),'dd-mmm-yyyy');
%         data(i).Time_HMS  = utcTime;
%         data(i).DayOfYear = doy;
% 
%         data(i).X_ECEF = X;
%         data(i).Y_ECEF = Y;
%         data(i).Z_ECEF = Z;
% 
%         % reset per epoch
%         lat = NaN; lon = NaN;
%         X = NaN; Y = NaN; Z = NaN;
%     end
% end
% 
% fclose(fid);
% 
% % % =========================
% % % %SAVE TO MAT FILE
% % % =========================
% save('/MATLAB Drive/Thesis-data/residual/harsh urban/GNSS_EpochData.mat','data');

% % =========================
% % %OPTIONAL TABLE VERSION
% % =========================
% EpochTable = struct2table(data);
% disp(EpochTable(1:5,:));

% % =========================
% % GNSS Pseudorange Residual Pipeline
% %=========================
% %=========================
% % GNSS Residual Computation (FINAL CLEAN VERSION)
% %=========================
% clear; clc;
% 
% %% Load data
% load('/MATLAB Drive/Thesis-data/residual/satellite_data.mat'); % satelliteTable
% load('/MATLAB Drive/Thesis-data/residual/harsh urban/GNSS_EpochData.mat'); % data (struct)
% load('/MATLAB Drive/Thesis-data/residual/GT_ECEF.mat'); % GT_ECEF
% 
% %% Convert struct → table
% EpochTable = struct2table(data);
% 
% %% Preallocate result (FAST + SAFE)
% N = height(satelliteTable);
% result = cell(N,4);   % Week, TOW, PRN, Residual
% k = 0;
% 
% %% =========================
% % LOOP over satellite obs
% %% =========================
% for i = 1:N
% 
%     try
%         %% ---- Identify epoch ----
%         week = satelliteTable.gpst_week(i);
%         tow  = satelliteTable.gpst_sec(i);
%         prn  = satelliteTable.satID{i};
% 
%         %% ---- Satellite position (s) ----
%         s = [satelliteTable.satPosX(i), ...
%              satelliteTable.satPosY(i), ...
%              satelliteTable.satPosZ(i)];
% 
%         %% ---- Find matching user estimate (e) ----
%         idx_e = find( ...
%             EpochTable.Week == week & ...
%             EpochTable.GPST_TOW == tow, 1);
% 
%         if isempty(idx_e)
%             continue;
%         end
% 
%         e = [EpochTable.X_ECEF(idx_e), ...
%              EpochTable.Y_ECEF(idx_e), ...
%              EpochTable.Z_ECEF(idx_e)];
% 
%         %% ---- Ground truth (t) ----
%         [~, idx_t] = min(abs(GT_ECEF(:,1) - tow));
%         t = GT_ECEF(idx_t,2:4);
% 
%         %% ---- Ranges ----
%         rho = norm(s - e);
%         r   = norm(s - t);
% 
%         residual = rho - r;
% 
%         %% ---- Store ----
%         k = k + 1;
%         result{k,1} = week;
%         result{k,2} = tow;
%         result{k,3} = prn;
%         result{k,4} = residual;
% 
%     catch
%         continue;
%     end
% end
% 
% %% =========================
% % Convert to table (FIXED)
% %% =========================
% result = result(1:k,:);   % IMPORTANT: remove empty rows
% 
% ResidualTable = cell2table(result, ...
%     'VariableNames', {'Week','GPST_TOW','PRN','Residual'});
% 
% %% Save
% save('/MATLAB Drive/Thesis-data/residual/ResidualTable.mat','ResidualTable');
% 
% fprintf('DONE ✔ Residuals computed: %d rows\n', height(ResidualTable));
% 
% %% Quick check
% head(ResidualTable)
% 
% 
% %% =====================================================
% %% RESIDUAL ANALYSIS (ADDED SECTION)
% %% =====================================================
% 
% res = ResidualTable.Residual;
% 
% %% Histogram
% figure;
% histogram(res, 50);
% xlabel('Residual (meters)');
% ylabel('Frequency');
% title('Histogram of Residuals');
% grid on;
% 
% %% Condition: residual > 10 m
% idx = (res > 10);
% 
% num_epochs = sum(idx);
% fprintf('Number of epochs with residual > 10 m: %d\n', num_epochs);
% 
% percentage = (num_epochs / height(ResidualTable)) * 100;
% fprintf('Percentage: %.2f%%\n', percentage);
% 
% %% Epoch-wise mean (receiver bias insight)
% epochSummary = groupsummary(ResidualTable, 'GPST_TOW', 'mean', 'Residual');
% 
% meanResiduals = epochSummary.mean_Residual;
% 
% totalMean = mean(meanResiduals);
% fprintf('Overall Mean Offset: %.4f m\n', totalMean);













% %% Load data
% load('/MATLAB Drive/Thesis-data/residual/satellite_data.mat'); % satelliteTable
% load('/MATLAB Drive/Thesis-data/residual/harsh urban/GNSS_EpochData.mat'); % data (struct)
% load('/MATLAB Drive/Thesis-data/residual/GT_ECEF.mat'); % GT_ECEF
% 
% %% Convert struct → table
% EpochTable = struct2table(data);
% 
% %% Preallocate result (UPDATED → 6 columns)
% N = height(satelliteTable);
% result = cell(N,6);   % Week, TOW, PRN, Residual, Azimuth, Elevation
% k = 0;
% 
% %% =========================
% % LOOP over satellite obs
% %% =========================
% for i = 1:N
% 
%     try
%         %% ---- Identify epoch ----
%         week = satelliteTable.gpst_week(i);
%         tow  = satelliteTable.gpst_sec(i);
%         prn  = satelliteTable.satID{i};
% 
%         %% ---- Satellite position (s) ----
%         s = [satelliteTable.satPosX(i), ...
%              satelliteTable.satPosY(i), ...
%              satelliteTable.satPosZ(i)];
% 
%         %% ---- Find matching user estimate (e) ----
%         idx_e = find( ...
%             EpochTable.Week == week & ...
%             EpochTable.GPST_TOW == tow, 1);
% 
%         if isempty(idx_e)
%             continue;
%         end
% 
%         e = [EpochTable.X_ECEF(idx_e), ...
%              EpochTable.Y_ECEF(idx_e), ...
%              EpochTable.Z_ECEF(idx_e)];
% 
%         %% ---- Ground truth (t) ----
%         [~, idx_t] = min(abs(GT_ECEF(:,1) - tow));
%         t = GT_ECEF(idx_t,2:4);
% 
%         %% ---- Ranges ----
%         rho = norm(s - e);
%         r   = norm(s - t);
% 
%         residual = rho - r;
% 
%         %% ---- Azimuth & Elevation ----
%         az = satelliteTable.Azimuth(i);
%         el = satelliteTable.Elevation(i);
% 
%         %% ---- Store ----
%         k = k + 1;
% 
%         result{k,1} = week;
%         result{k,2} = tow;
%         result{k,3} = prn;
%         result{k,4} = residual;
%         result{k,5} = az;
%         result{k,6} = el;
% 
%     catch
%         continue;
%     end
% end
% 
% %% =========================
% % Convert to table
% %% =========================
% result = result(1:k,:);
% 
% ResidualTable = cell2table(result, ...
%     'VariableNames', {'Week','GPST_TOW','PRN','Residual','Azimuth','Elevation'});
% 
% %% Save
% save('/MATLAB Drive/Thesis-data/residual/ResidualTable.mat','ResidualTable');
% 
% fprintf('DONE ✔ Residuals computed: %d rows\n', height(ResidualTable));
% 
% %% Quick check
% head(ResidualTable)
% 
% %% =====================================================
% %% RESIDUAL ANALYSIS
% %% =====================================================
% 
% res = ResidualTable.Residual;
% 
% %% Histogram
% figure;
% histogram(res, 50);
% xlabel('Residual (meters)');
% ylabel('Frequency');
% title('Histogram of Residuals');
% grid on;
% 
% %% Condition: residual > 10 m
% idx = (res > 10);
% 
% num_epochs = sum(idx);
% fprintf('Number of epochs with residual > 10 m: %d\n', num_epochs);
% 
% percentage = (num_epochs / height(ResidualTable)) * 100;
% fprintf('Percentage: %.2f%%\n', percentage);
% 
% %% Epoch-wise mean
% epochSummary = groupsummary(ResidualTable, 'GPST_TOW', 'mean', 'Residual');
% 
% meanResiduals = epochSummary.mean_Residual;
% 
% totalMean = mean(meanResiduals);
% fprintf('Overall Mean Offset: %.4f m\n', totalMean);











































% %% Residual Computation Script (FUSED DATASET) — OPTIMIZED
% clear; clc;
% 
% %% Load Data
% load('/MATLAB Drive/Thesis-data/residual/satellite_data.mat');        % satelliteTable
% load('/MATLAB Drive/thesis4/matlab/satellite_obs_extended.mat');       % obsTable
% load('/MATLAB Drive/Thesis-data/residual/harsh urban/GNSS_EpochData.mat','data');
% % Extract time + ECEF columns from struct array into plain vectors
% t_gnss_epoch = [data.GPST_TOW]';   % Nx1 TOW
% gnss_X       = [data.X_ECEF]';     % Nx1
% gnss_Y       = [data.Y_ECEF]';     % Nx1
% gnss_Z       = [data.Z_ECEF]';     % Nx1
% load('/MATLAB Drive/Thesis-data/residual/GT_trim.mat','GT_trim');
% 
% traceSat = satelliteTable;
% N = height(traceSat);
% 
% %% Time vectors (column vectors for vectorized ops)
% % t_gnss_epoch already built above from GNSS_EpochData struct
% t_gt = GT_trim(:,1);
% 
% %% ---------------------------------------------------------------
% %  OPT 1: Build a lookup map for obsTable rows
% %  Key = "TOW_SatID" string — O(1) lookup instead of find() each loop
% %% ---------------------------------------------------------------
% disp('Building OBS lookup map...');
% obsKeys = cellstr(string(obsTable.GPST_TOW) + "_" + string(obsTable.SatID));
% obsMap  = containers.Map(obsKeys, (1:height(obsTable))');
% 
% %% ---------------------------------------------------------------
% %  OPT 2: Vectorized nearest-neighbour indices for GNSS & GT
% %  Uses sorted interp1 trick — computes ALL indices before the loop
% %% ---------------------------------------------------------------
% disp('Vectorizing time index lookups...');
% tow_all = traceSat.GPST_TOW;   % Nx1
% 
% % Nearest index in t_gnss_epoch for every TOW
% idx_e_all = knnsearch(t_gnss_epoch, tow_all);   % requires Stats Toolbox
% % Fallback if no Stats Toolbox:
% % idx_e_all = arrayfun(@(t) find_nearest(t_gnss_epoch, t), tow_all);
% 
% % Nearest index in t_gt for every TOW
% idx_gt_all = knnsearch(t_gt, tow_all);
% 
% %% ---------------------------------------------------------------
% %  OPT 3: Pre-allocate output arrays (avoids dynamic cell growth)
% %% ---------------------------------------------------------------
% disp('Pre-allocating output arrays...');
% 
% % Numeric columns
% Week        = traceSat.Week;
% TOW         = traceSat.GPST_TOW;
% SatID_col   = string(traceSat.satID);
% RecvTime    = string(traceSat.recvTime_str);
% TxTime      = string(traceSat.txTime_str);
% 
% pr_col   = nan(N,1);
% dop_col  = nan(N,1);
% snr_col  = nan(N,1);
% az_col   = traceSat.Azimuth;
% el_col   = traceSat.Elevation;
% 
% % Satellite positions (already in table — extract once as matrix)
% S = [traceSat.satPosX, traceSat.satPosY, traceSat.satPosZ];   % Nx3
% 
% % Estimated positions — indexed from GNSS_EpochData struct columns
% E = [gnss_X(idx_e_all), gnss_Y(idx_e_all), gnss_Z(idx_e_all)];   % Nx3
% T = GT_trim    (idx_gt_all, 2:4);   % Nx3
% 
% %% ---------------------------------------------------------------
% %  OPT 4: Vectorized OBS lookup (map-based, no find() inside loop)
% %% ---------------------------------------------------------------
% disp('Fetching OBS values...');
% queryKeys = cellstr(string(tow_all) + "_" + SatID_col);   % cell array required by containers.Map
% validMask = isKey(obsMap, queryKeys);                      % logical Nx1
% 
% validIdx               = cell2mat(values(obsMap, queryKeys(validMask)));
% pr_col (validMask)     = obsTable.Pseudorange_L1(validIdx);
% dop_col(validMask)     = obsTable.Doppler_L1    (validIdx);
% snr_col(validMask)     = obsTable.SNR_L1        (validIdx);
% 
% %% ---------------------------------------------------------------
% %  OPT 5: Fully vectorized range & residual computation (no loop!)
% %% ---------------------------------------------------------------
% disp('Computing ranges and residuals...');
% 
% diff_true = S - T;           % Nx3  satellite minus ground truth
% diff_est  = S - E;           % Nx3  satellite minus estimate
% 
% true_range = sqrt(sum(diff_true.^2, 2));   % Nx1
% est_range  = sqrt(sum(diff_est .^2, 2));   % Nx1
% residual   = est_range - true_range;       % Nx1
% 
% dX = E(:,1) - T(:,1);
% dY = E(:,2) - T(:,2);
% dZ = E(:,3) - T(:,3);
% 
% %% ---------------------------------------------------------------
% %  OPT 6: Assemble table directly from arrays (no cell accumulation)
% %% ---------------------------------------------------------------
% disp('Assembling final table...');
% 
% finalTable = table(...
%     Week, TOW, SatID_col, ...
%     pr_col, dop_col, snr_col, ...
%     az_col, el_col, ...
%     E(:,1), E(:,2), E(:,3), ...
%     T(:,1), T(:,2), T(:,3), ...
%     dX, dY, dZ, ...
%     true_range, est_range, residual, ...
%     RecvTime, TxTime, ...
%     'VariableNames', { ...
%         'Week','GPST_TOW','SatID', ...
%         'Pseudorange','Doppler','SNR', ...
%         'Azimuth','Elevation', ...
%         'EstX','EstY','EstZ', ...
%         'GT_X','GT_Y','GT_Z', ...
%         'dX','dY','dZ', ...
%         'TrueRange','EstimatedRange','RangeResidual', ...
%         'RecvTime','TxTime'});
% 
% %% Save
% save('/MATLAB Drive/Thesis-data/residual/final_residuals_fused.mat','finalTable');
% fprintf('Done. Computed %d fused observations.\n', height(finalTable));
% head(finalTable)
% 
% %% =============================================================
% %  CREATE ML DATASET (CLEAN)
% %% =============================================================
% ML_table = finalTable(:, { ...
%     'Week','GPST_TOW','SatID', ...
%     'dX','dY','dZ', ...
%     'Azimuth','Elevation', ...
%     'SNR','RangeResidual'});
% 
% ML_table = rmmissing(ML_table);
% fprintf('ML dataset size after cleaning: %d samples\n', height(ML_table));
% 
% save('/MATLAB Drive/Thesis-data/residual/ML_dataset.mat', 'ML_table');
% writetable(ML_table, '/MATLAB Drive/Thesis-data/residual/ML_dataset.csv');
% fprintf('Saved ML dataset as MAT and CSV ✔\n');
% head(ML_table)
% 
% 
% %% =============================================================
% %  LOCAL HELPER  (used as fallback if Stats Toolbox unavailable)
% %% =============================================================
% function idx = find_nearest(vec, val)
%     [~, idx] = min(abs(vec - val));
% end


%% =============================================================
%  GNSS ML PIPELINE (FUSED DATASET)
%  Standalone script — loads precomputed MAT file
%% =============================================================

% clear; clc;
% 
% disp('========================================');
% disp(' GNSS ML PIPELINE (FUSED DATASET)');
% disp('========================================');
% 
% %% =========================
% % LOAD DATA
% %% =========================
% disp('Loading dataset...');
% 
% load('/MATLAB Drive/Thesis-data/residual/final_residuals_fused.mat');  % finalTable
% load('/MATLAB Drive/Thesis-data/residual/ML_dataset.mat');             % ML_table
% 
% fprintf('Loaded %d samples\n', height(ML_table));
% 
% %% =========================
% % FEATURE MATRIX (NO LEAKAGE)
% %% =========================
% disp('Preparing features...');
% 
% X = [ ...
%     ML_table.SNR, ...
%     ML_table.Azimuth, ...
%     ML_table.Elevation, ...
%     ML_table.RangeResidual ...
% ];
% 
% % Normalize features
% X = normalize(X);
% 
% %% TARGETS
% Yx = ML_table.dX;
% Yy = ML_table.dY;
% Yz = ML_table.dZ;
% 
% %% CLEAN DATA
% valid = all(~isnan(X),2) & ~isnan(Yx) & ~isnan(Yy) & ~isnan(Yz);
% 
% X = X(valid,:);
% Yx = Yx(valid);
% Yy = Yy(valid);
% Yz = Yz(valid);
% ML_table = ML_table(valid,:);
% 
% fprintf('Clean dataset size: %d samples\n', size(X,1));
% 
% %% =========================
% % TRAIN / TEST SPLIT
% %% =========================
% disp('Splitting dataset...');
% 
% cv = cvpartition(size(X,1),'HoldOut',0.2);
% 
% idxTrain = training(cv);
% idxTest  = test(cv);
% 
% X_train = X(idxTrain,:);
% X_test  = X(idxTest,:);
% 
% Yx_train = Yx(idxTrain); Yx_test = Yx(idxTest);
% Yy_train = Yy(idxTrain); Yy_test = Yy(idxTest);
% Yz_train = Yz(idxTrain); Yz_test = Yz(idxTest);
% 
% %% =========================
% % MODEL TRAINING (BOOSTED TREES)
% %% =========================
% disp('Training models...');
% 
% t = templateTree('MaxNumSplits',20);
% 
% mdlX = fitrensemble(X_train, Yx_train, ...
%     'Method','LSBoost', ...
%     'NumLearningCycles',200, ...
%     'LearnRate',0.05, ...
%     'Learners',t);
% 
% mdlY = fitrensemble(X_train, Yy_train, ...
%     'Method','LSBoost', ...
%     'NumLearningCycles',200, ...
%     'LearnRate',0.05, ...
%     'Learners',t);
% 
% mdlZ = fitrensemble(X_train, Yz_train, ...
%     'Method','LSBoost', ...
%     'NumLearningCycles',200, ...
%     'LearnRate',0.05, ...
%     'Learners',t);
% 
% disp('Training complete ✔');
% 
% %% =========================
% % PREDICTION
% %% =========================
% disp('Running predictions...');
% 
% pred_dx = predict(mdlX, X_test);
% pred_dy = predict(mdlY, X_test);
% pred_dz = predict(mdlZ, X_test);
% 
% %% =========================
% % RMSE EVALUATION
% %% =========================
% rmse_dx = sqrt(mean((pred_dx - Yx_test).^2));
% rmse_dy = sqrt(mean((pred_dy - Yy_test).^2));
% rmse_dz = sqrt(mean((pred_dz - Yz_test).^2));
% 
% fprintf('\n===== RMSE =====\n');
% fprintf('dX: %.3f m\n', rmse_dx);
% fprintf('dY: %.3f m\n', rmse_dy);
% fprintf('dZ: %.3f m\n', rmse_dz);
% 
% %% =========================
% % POSITION CORRECTION
% %% =========================
% disp('Applying position correction...');
% 
% % Align indices with original finalTable
% testIdx_global = find(valid);
% testIdx_global = testIdx_global(idxTest);
% 
% EstX = finalTable.EstX(testIdx_global);
% EstY = finalTable.EstY(testIdx_global);
% EstZ = finalTable.EstZ(testIdx_global);
% 
% GTX = finalTable.GT_X(testIdx_global);
% GTY = finalTable.GT_Y(testIdx_global);
% GTZ = finalTable.GT_Z(testIdx_global);
% 
% %% BEFORE correction
% err_before = sqrt((EstX - GTX).^2 + ...
%                   (EstY - GTY).^2 + ...
%                   (EstZ - GTZ).^2);
% 
% %% AFTER correction
% corrX = EstX - pred_dx;
% corrY = EstY - pred_dy;
% corrZ = EstZ - pred_dz;
% 
% err_after = sqrt((corrX - GTX).^2 + ...
%                  (corrY - GTY).^2 + ...
%                  (corrZ - GTZ).^2);
% 
% %% =========================
% % RESULTS
% %% =========================
% fprintf('\n===== POSITION ERROR =====\n');
% fprintf('Mean BEFORE: %.3f m\n', mean(err_before));
% fprintf('Mean AFTER : %.3f m\n', mean(err_after));
% 
% improvement = mean(err_before) - mean(err_after);
% fprintf('Improvement: %.3f m\n', improvement);
% 
% %% =========================
% % VISUALIZATION
% %% =========================
% 
% figure;
% plot(err_before,'r'); hold on;
% plot(err_after,'g');
% legend('Before','After');
% title('GNSS Position Error Improvement');
% xlabel('Sample'); ylabel('Error (m)');
% grid on;
% 
% figure;
% boxplot([err_before err_after], 'Labels', {'Before','After'});
% ylabel('Error (m)');
% title('Error Distribution');
% grid on;
% 
% %% =========================
% % FEATURE IMPORTANCE
% %% =========================
% figure;
% imp = predictorImportance(mdlX);
% bar(imp);
% set(gca,'XTickLabel',{'SNR','Az','El','Residual'});
% title('Feature Importance');
% grid on;
% 
% %% =========================
% % SAVE MODEL
% %% =========================
% save('/MATLAB Drive/Thesis-data/residual/xgboost_fused_model.mat', ...
%     'mdlX','mdlY','mdlZ');
% 
% disp('Model saved ✔');
% 
% %% =========================
% % SUMMARY
% %% =========================
% disp('========================================');
% disp(' Pipeline Completed Successfully ');
% disp('========================================');