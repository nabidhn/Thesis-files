%% Residual Computation Script
clear; clc;

%% Load Data
load('C:\KLTdataset\data\GNSS\20210610\satellite_data.mat'); % trace → satelliteTable
load('C:\KLTdataset\data\GNSS\20231109\satellite_and_position.mat'); % stat → satTable, posTable
load('C:\KLTdataset\label\0610_KLT2_209\GT_ECEF.mat'); % ground truth → GT_ECEF


% Rename for clarity
traceSat = satelliteTable;
statSat  = satTable;
statPos  = posTable;
gtData   = GT_ECEF;



%% Output buffers
result = {};

%% Loop through STAT satellite data (has az, el, snr)
for i = 1:height(statSat)

    try
        % --- Extract stat satellite info ---
        week = statSat.Week(i);
        tow  = statSat.GPST_TOW(i);
        satID = statSat.SatID{i};

        az  = statSat.Azimuth(i);
        el  = statSat.Elevation(i);
        snr = statSat.SNR(i);
        statRes = statSat.StatRes(i);

        %% --- Find matching satellite in TRACE file ---
        idx_trace = find(...
            strcmp(traceSat.satID, satID) & ...
            traceSat.gpst_week == week & ...
            traceSat.gpst_sec == tow);

        if isempty(idx_trace)
            continue;
        end

        % Take first match
        idx_trace = idx_trace(1);

        s = [...
            traceSat.satPosX(idx_trace), ...
            traceSat.satPosY(idx_trace), ...
            traceSat.satPosZ(idx_trace)];

        recvTime = traceSat.recvTime_str{idx_trace};
        txTime   = traceSat.txTime_str{idx_trace};

        %% --- Estimated user position (from STAT POS) ---
        idx_pos = find(...
            statPos.Week == week & ...
            statPos.GPST_TOW == tow);

        if isempty(idx_pos)
            continue;
        end

        idx_pos = idx_pos(1);

        e = [...
            statPos.X_ECEF(idx_pos), ...
            statPos.Y_ECEF(idx_pos), ...
            statPos.Z_ECEF(idx_pos)];

        %% --- Ground truth position ---
        % GT_ECEF: [time, X, Y, Z]
        % Assume t_gt ~ GPST seconds (approx match)

        [~, idx_gt] = min(abs(gtData(:,3) - tow));

        t = gtData(idx_gt, 4:6);
        unix_time = int64(round(gtData(idx_gt, 1)));

        %% --- Compute ranges ---
        true_range = norm(s - t);   % r
        est_range  = norm(s - e);   % rho

        residual = est_range - true_range;

        %% --- Store ---
        result = [result; {
            unix_time, week, tow, satID, ...
            az, el, snr, ...
            true_range, est_range, residual, ...
            statRes, ...
            recvTime, txTime
        }];

    catch
        continue;
    end
end

%% Convert to table
varNames = {...
    'UnixTime', 'Week','GPST_TOW','SatID', ...
    'Azimuth','Elevation','SNR', ...
    'TrueRange','EstimatedRange','residual', ...
    'StatResidual', ...
    'RecvTime','TxTime'};

finalTable = cell2table(result, 'VariableNames', varNames);

%% Save
save('C:\KLTdataset\label\0610_KLT1_203\final_residuals.mat', 'finalTable');

fprintf('Done. Computed %d residuals.\n', height(finalTable));

%% Preview
head(finalTable)


res = finalTable.residual;
CN0 = finalTable.SNR;

figure;
histogram(res, 50); % 50 bins (you can adjust)

xlabel('Residual (meters)');
ylabel('Frequency');
title('Histogram of Residuals');
grid on;

figure;
histogram(CN0, 100);
% Plot the histogram of CN0 values
xlabel('SNR (dB)');
ylabel('Frequency');
title('Histogram of SNR Values');
grid on;

%% Condition: residual > 5 m AND SNR (C/N0) < 20 dB


% Logical condition
idx = (res > 10);

% Count how many satisfy the condition
num_epochs = sum(idx);

fprintf('Number of epochs with residual > 5 m AND C/N0 < 20 dB: %d\n', num_epochs);


percentage = (num_epochs / height(finalTable)) * 100;

fprintf('Percentage: %.2f%%\n', percentage);

% 1. Group by TOW to find the Mean Residual per Epoch
% This represents the Receiver Clock Bias / Time Offset for that moment
epochSummary = groupsummary(finalTable, 'GPST_TOW', 'mean', 'residual');

% 2. Extract the Mean Residuals
meanResiduals = epochSummary.mean_residual;

% 4. Statistics
totalMean = mean(meanResiduals);
fprintf('Overall Mean Offset: %.4f m\n', totalMean);

%% Histogram per Satellite

satList = unique(finalTable.SatID);

figure;
tiledlayout('flow')   % automatically adjusts subplot layout

for i = 1:length(satList)

    sat = satList{i};

    % Extract residuals for this satellite
    idx = strcmp(finalTable.SatID, sat);
    satResiduals = finalTable.residual(idx);

    nexttile
    histogram(satResiduals, 30)

    title(['Satellite ', sat])
    xlabel('Residual (m)')
    ylabel('Frequency')
    grid on

end

sgtitle('Residual Histogram Per Satellite')

%% Elevation vs Residual (Moving Average)

% Sort by elevation
[el_sorted, idx] = sort(finalTable.Elevation);
res_sorted = finalTable.residual(idx);

% Use absolute residual (recommended)
res_sorted = abs(res_sorted);

% Moving average window size (tune this!)
window = 200;

res_smooth = movmean(res_sorted, window);

figure;
scatter(el_sorted, res_sorted, 5, 'filled'); hold on;
plot(el_sorted, res_smooth, 'r', 'LineWidth', 2);

xlabel('Elevation (degrees)');
ylabel('|Residual| (meters)');
title('Elevation vs Residual (Moving Average)');
legend('Raw Data', 'Moving Average');
grid on;

%% Elevation vs SNR

% Sort by elevation (optional but keeps it clean)
[el_sorted, idx] = sort(finalTable.Elevation);
snr_sorted = finalTable.SNR(idx);

figure;
scatter(el_sorted, snr_sorted, 5, 'filled');

xlabel('Elevation (degrees)');
ylabel('SNR (dB)');
title('Elevation vs SNR');
grid on;