% %% Residual Computation Script (ROBUST + FIXED)
% clear; clc;
% 
% %% =========================
% % SAFE DATA LOADING (IMPORTANT FIX)
% %% =========================
% traceData = load('C:\KLTdataset\data\GNSS\20210610\satellite_data.mat');
% statData  = load('C:\KLTdataset\data\GNSS\20210610\satellite_and_position.mat');
% gtDataRaw = load('C:\KLTdataset\label\0610_KLT1_203\ground_truth_enhanced.mat');
% 
% %% Extract variables safely
% traceSat = traceData.satelliteTable;
% statSat  = statData.satTable;
% statPos  = statData.posTable;
% gt       = gtDataRaw.GT_table;
% 
% %% Output buffer
% result = {};
% 
% %% =========================
% % MAIN LOOP
% %% =========================
% for i = 1:height(statSat)
% 
%     try
%         %% --- Extract stat satellite info ---
%         week = statSat.Week(i);
%         tow  = statSat.GPST_TOW(i);
% 
%         % SAFE SatID handling
%         if iscell(statSat.SatID)
%             satID = statSat.SatID{i};
%         else
%             satID = statSat.SatID(i);
%         end
% 
%         az  = statSat.Azimuth(i);
%         el  = statSat.Elevation(i);
%         snr = statSat.SNR(i);
% 
%         % FIX: handle missing field safely
%         if ismember('StatRes', statSat.Properties.VariableNames)
%             statRes = statSat.StatRes(i);
%         else
%             statRes = NaN;
%         end
% 
%         %% --- Find matching satellite in TRACE ---
%         idx_trace = find( ...
%             strcmp(traceSat.satID, satID) & ...
%             traceSat.gpst_week == week & ...
%             traceSat.gpst_sec == tow);
% 
%         if isempty(idx_trace)
%             continue;
%         end
% 
%         idx_trace = idx_trace(1);
% 
%         s = [ ...
%             traceSat.satPosX(idx_trace), ...
%             traceSat.satPosY(idx_trace), ...
%             traceSat.satPosZ(idx_trace)];
% 
%         recvTime = traceSat.recvTime_str{idx_trace};
%         txTime   = traceSat.txTime_str{idx_trace};
% 
%         %% --- Estimated user position ---
%         idx_pos = find( ...
%             statPos.Week == week & ...
%             statPos.GPST_TOW == tow);
% 
%         if isempty(idx_pos)
%             continue;
%         end
% 
%         idx_pos = idx_pos(1);
% 
%         e = [ ...
%             statPos.X_ECEF(idx_pos), ...
%             statPos.Y_ECEF(idx_pos), ...
%             statPos.Z_ECEF(idx_pos)];
% 
%         %% --- Ground Truth (FIXED MATCHING) ---
%         [~, idx_gt] = min(abs(gt.gps_sow - tow));
% 
%         t = [ ...
%             gt.ecefX(idx_gt), ...
%             gt.ecefY(idx_gt), ...
%             gt.ecefZ(idx_gt)];
% 
%         unix_time = int64(gt.utc_time_seconds(idx_gt));
% 
%         %% --- Compute ranges ---
%         true_range = norm(s - t);
%         est_range  = norm(s - e);
% 
%         residual = est_range - true_range;
% 
%         %% --- Store ---
%         result = [result; {
%             unix_time, week, tow, satID, ...
%             az, el, snr, ...
%             true_range, est_range, residual, ...
%             statRes, ...
%             recvTime, txTime
%         }];
% 
%     catch
%         continue;
%     end
% end
% 
% %% =========================
% % CONVERT TO TABLE
% %% =========================
% varNames = { ...
%     'UnixTime','Week','GPST_TOW','SatID', ...
%     'Azimuth','Elevation','SNR', ...
%     'TrueRange','EstimatedRange','Residual', ...
%     'StatResidual', ...
%     'RecvTime','TxTime'};
% 
% finalTable = cell2table(result, 'VariableNames', varNames);
% 
% %% Save
% save('C:\KLTdataset\label\0610_KLT1_203\final_residuals.mat', 'finalTable');
% 
% fprintf('Done. Computed %d residuals.\n', height(finalTable));
% 
% %% =========================
% % ANALYSIS (UNCHANGED LOGIC)
% %% =========================
% res = finalTable.Residual;
% CN0 = finalTable.SNR;
% 
% figure;
% histogram(res, 50);
% title('Residual Histogram'); grid on;
% 
% figure;
% histogram(CN0, 100);
% title('SNR Histogram'); grid on;
% 
% %% Threshold analysis
% idx = (res > 10);
% num_epochs = sum(idx);
% 
% fprintf('Residual > 10 m count: %d\n', num_epochs);
% fprintf('Percentage: %.2f%%\n', (num_epochs/height(finalTable))*100);
% 
% %% Mean residual per epoch
% epochSummary = groupsummary(finalTable, 'GPST_TOW', 'mean', 'Residual');
% fprintf('Overall Mean Offset: %.4f m\n', mean(epochSummary.mean_Residual));
% 
% %% Per-satellite histogram
% satList = unique(finalTable.SatID);
% 
% figure;
% tiledlayout('flow')
% 
% for i = 1:length(satList)
% 
%     sat = satList{i};
%     idx = strcmp(finalTable.SatID, sat);
% 
%     nexttile
%     histogram(finalTable.Residual(idx), 30)
%     title(['Sat ', sat])
%     grid on
% end
% 
% sgtitle('Residual Histogram Per Satellite')
% 
% %% Elevation vs Residual
% [el_sorted, idx] = sort(finalTable.Elevation);
% res_sorted = abs(finalTable.Residual(idx));
% 
% res_smooth = movmean(res_sorted, 200);
% 
% figure;
% scatter(el_sorted, res_sorted, 5, 'filled'); hold on;
% plot(el_sorted, res_smooth, 'r','LineWidth',2);
% 
% xlabel('Elevation'); ylabel('|Residual|');
% title('Elevation vs Residual');
% grid on;
% 
% %% Elevation vs SNR
% figure;
% scatter(el_sorted, finalTable.SNR(idx), 5, 'filled');
% xlabel('Elevation'); ylabel('SNR');
% title('Elevation vs SNR');
% grid on;


%% Full Residual + IS-DPR Computation Script
clear; clc;

%% =========================
% DATA LOADING
%% =========================
traceData = load('C:\KLTdataset\data\GNSS\20210610\track1\satellite_data.mat');
statData  = load('C:\KLTdataset\data\GNSS\20210610\track1\satellite_and_position.mat');
gtDataRaw = load('C:\KLTdataset\label\0610_KLT1_203\ground_truth_enhanced.mat');

traceSat = traceData.satelliteTable;
statSat  = statData.satTable;
statPos  = statData.posTable;
gt       = gtDataRaw.GT_table;

%% =========================
% PASS 1 — COLLECT ALL RESIDUALS PER EPOCH
%% =========================
epochMap = containers.Map('KeyType','double','ValueType','any');

for i = 1:height(statSat)
    try
        week = statSat.Week(i);
        tow  = statSat.GPST_TOW(i);

        if iscell(statSat.SatID)
            satID = statSat.SatID{i};
        else
            satID = statSat.SatID(i);
        end

        az  = statSat.Azimuth(i);
        el  = statSat.Elevation(i);
        snr = statSat.SNR(i);

        if ismember('StatRes', statSat.Properties.VariableNames)
            statRes = statSat.StatRes(i);
        else
            statRes = NaN;
        end

        %% Match in TRACE
        idx_trace = find( ...
            strcmp(traceSat.satID, satID) & ...
            traceSat.gpst_week == week & ...
            traceSat.gpst_sec == tow);

        if isempty(idx_trace)
            continue;
        end
        idx_trace = idx_trace(1);

        s = [ ...
            traceSat.satPosX(idx_trace), ...
            traceSat.satPosY(idx_trace), ...
            traceSat.satPosZ(idx_trace)];

        recvTime = traceSat.recvTime_str{idx_trace};
        txTime   = traceSat.txTime_str{idx_trace};

        %% Estimated position
        idx_pos = find(statPos.Week == week & statPos.GPST_TOW == tow);
        if isempty(idx_pos)
            continue;
        end
        idx_pos = idx_pos(1);

        e = [ ...
            statPos.X_ECEF(idx_pos), ...
            statPos.Y_ECEF(idx_pos), ...
            statPos.Z_ECEF(idx_pos)];

        %% Ground truth
        [~, idx_gt] = min(abs(gt.gps_sow - tow));

        t = [ ...
            gt.ecefX(idx_gt), ...
            gt.ecefY(idx_gt), ...
            gt.ecefZ(idx_gt)];

        unix_time = int64(gt.utc_time_seconds(idx_gt));

        %% Ranges
        true_range = norm(s - t);
        est_range  = norm(s - e);
        residual   = est_range - true_range;

        %% Store into epoch bucket
        entry            = struct();
        entry.unix_time  = unix_time;
        entry.week       = week;
        entry.tow        = tow;
        entry.satID      = satID;
        entry.az         = az;
        entry.el         = el;
        entry.snr        = snr;
        entry.statRes    = statRes;
        entry.true_range = true_range;
        entry.est_range  = est_range;
        entry.residual   = residual;
        entry.recvTime   = recvTime;
        entry.txTime     = txTime;

        if isKey(epochMap, tow)
            epochMap(tow) = [epochMap(tow), entry];
        else
            epochMap(tow) = entry;
        end

    catch
        continue;
    end
end

%% =========================
% PASS 2 — COMPUTE IS-DPR, STORE IN SINGLE TABLE
%% =========================
result  = {};
towList = keys(epochMap);

for k = 1:length(towList)
    tow     = towList{k};
    satList = epochMap(tow);

    if length(satList) < 2
        %% Only 1 satellite — store with NaN IS-DPR fields
        entry = satList(1);
        result = [result; {
            entry.unix_time, entry.week, entry.tow, entry.satID, ...
            entry.az, entry.el, entry.snr, ...
            entry.true_range, entry.est_range, entry.residual, ...
            entry.statRes, entry.recvTime, entry.txTime, ...
            NaN, NaN, NaN, 'N/A'           % Pr_i, Pr_ref, IS_DPR, RefSatID
        }];
        continue;
    end

    %% Find reference satellite — highest SNR
    snr_vals     = arrayfun(@(x) x.snr, satList);
    [~, ref_idx] = max(snr_vals);

    P_ref   = satList(ref_idx).est_range;
    rho_ref = satList(ref_idx).true_range;
    Pr_ref  = P_ref - rho_ref;
    ref_sat = satList(ref_idx).satID;

    %% Loop all satellites in epoch
    for s = 1:length(satList)
        entry = satList(s);

        P_i    = entry.est_range;
        rho_i  = entry.true_range;
        Pr_i   = P_i - rho_i;

        % IS-DPR = (P_i - P_ref) - (rho_ref - rho_i)
        IS_DPR = Pr_i - Pr_ref;

        result = [result; {
            entry.unix_time, entry.week, entry.tow, entry.satID, ...
            entry.az, entry.el, entry.snr, ...
            entry.true_range, entry.est_range, entry.residual, ...
            entry.statRes, entry.recvTime, entry.txTime, ...
            IS_DPR, ref_sat
        }];
    end
end

%% =========================
% CONVERT TO SINGLE TABLE
%% =========================
finalTable = cell2table(result, 'VariableNames', { ...
    'UnixTime', 'Week', 'GPST_TOW', 'SatID', ...
    'Azimuth', 'Elevation', 'SNR', ...
    'TrueRange', 'EstimatedRange', 'Residual', ...
    'StatResidual', 'RecvTime', 'TxTime', ...
    'IS_DPR', 'RefSatID'});

%% =========================
% SAVE
%% =========================
save('C:\KLTdataset\label\0610_KLT1_203\final_residuals.mat', 'finalTable');
fprintf('Done. Total entries: %d\n', height(finalTable));

%% =========================
% RESIDUAL ANALYSIS
%% =========================
res = finalTable.Residual;
CN0 = finalTable.SNR;

figure;
histogram(res, 50);
title('Residual Histogram');
xlabel('Residual (m)'); ylabel('Count');
grid on;

figure;
histogram(CN0, 100);
title('SNR Histogram');
xlabel('SNR (dB-Hz)'); ylabel('Count');
grid on;

idx_thresh = (res > 10);
fprintf('Residual > 10m : %d (%.2f%%)\n', ...
    sum(idx_thresh), sum(idx_thresh)/height(finalTable)*100);

epochSummary = groupsummary(finalTable, 'GPST_TOW', 'mean', 'Residual');
fprintf('Overall Mean Offset: %.4f m\n', mean(epochSummary.mean_Residual));

%% Per-satellite residual
satNames = unique(finalTable.SatID);
figure; tiledlayout('flow');
for i = 1:length(satNames)
    idx = strcmp(finalTable.SatID, satNames{i});
    nexttile;
    histogram(finalTable.Residual(idx), 30);
    title(['Sat ', satNames{i}]);
    grid on;
end
sgtitle('Residual Per Satellite');

%% Elevation vs Residual
[el_sorted, idx_el] = sort(finalTable.Elevation);
res_sorted = abs(finalTable.Residual(idx_el));
res_smooth = movmean(res_sorted, 200);

figure;
scatter(el_sorted, res_sorted, 5, 'filled'); hold on;
plot(el_sorted, res_smooth, 'r', 'LineWidth', 2);
xlabel('Elevation (deg)'); ylabel('|Residual| (m)');
title('Elevation vs Residual');
grid on;

%% Elevation vs SNR

figure;

subplot(2,1,1);
histogram(res, 50);
title('Residual Histogram');
xlabel('Residual (m)'); ylabel('Count');
grid on;

subplot(2,1,2);
scatter(el_sorted, finalTable.SNR(idx_el), 5, 'filled');
xlabel('Elevation (deg)'); ylabel('SNR (dB-Hz)');
title('Elevation vs SNR');
grid on;

%% =========================
% IS-DPR ANALYSIS
%% =========================

% Exclude NaN rows (epochs with single satellite)
valid = ~isnan(finalTable.IS_DPR);

figure;
histogram(finalTable.IS_DPR(valid), 50);
title('IS-DPR Distribution');
xlabel('IS-DPR (m)'); ylabel('Count');
grid on;

figure;
scatter(finalTable.Elevation(valid), abs(finalTable.IS_DPR(valid)), 5, 'filled');
xlabel('Elevation (deg)'); ylabel('|IS-DPR| (m)');
title('Elevation vs IS-DPR');
grid on;

figure;
scatter(finalTable.GPST_TOW(valid), finalTable.IS_DPR(valid), 5, 'filled');
xlabel('GPST TOW (s)'); ylabel('IS-DPR (m)');
title('IS-DPR over Time');
grid on;

figure;
scatter(finalTable.SNR(valid), abs(finalTable.IS_DPR(valid)), 5, 'filled');
xlabel('SNR (dB-Hz)'); ylabel('|IS-DPR| (m)');
title('SNR vs IS-DPR');
grid on;

%% Per-satellite IS-DPR
figure; tiledlayout('flow');
for i = 1:length(satNames)
    idx = strcmp(finalTable.SatID, satNames{i}) & valid;
    if sum(idx) < 2; continue; end
    nexttile;
    histogram(finalTable.IS_DPR(idx), 30);
    title(['Sat ', satNames{i}]);
    grid on;
end
sgtitle('IS-DPR Per Satellite');

%% Summary
fprintf('\n--- IS-DPR Summary ---\n');
fprintf('Mean   IS-DPR : %.4f m\n', mean(finalTable.IS_DPR(valid)));
fprintf('Std    IS-DPR : %.4f m\n', std(finalTable.IS_DPR(valid)));
fprintf('Max  |IS-DPR| : %.4f m\n', max(abs(finalTable.IS_DPR(valid))));
fprintf('IS-DPR > 10m  : %d (%.2f%%)\n', ...
    sum(abs(finalTable.IS_DPR(valid)) > 10), ...
    sum(abs(finalTable.IS_DPR(valid)) > 10) / sum(valid) * 100);