%% Residual Computation Script
clear; clc;

%% Load Data
load('/MATLAB Drive/Thesis-data/residual/satellite_data.mat'); % satelliteTable
load('/MATLAB Drive/Thesis-data/residual/GNSS_interp.mat', 'GNSS_interp'); % estimated user position
load('/MATLAB Drive/Thesis-data/residual/GT_trim.mat', 'GT_trim'); % ground truth

traceSat = satelliteTable;

%% Extract data
t_gnss_interp = GNSS_interp(:,1);
t_gt = GT_trim(:,1);

%% Output buffer
result = {};

%% Loop through TRACE satellite data
for i = 1:height(traceSat)

    try
        % --- Satellite info ---
        week = traceSat.Week(i);
        tow  = traceSat.GPST_TOW(i);
        satID = traceSat.satID{i};

        %% --- Satellite position ---
        s = [...
            traceSat.satPosX(i), ...
            traceSat.satPosY(i), ...
            traceSat.satPosZ(i)];

        recvTime = traceSat.recvTime_str{i};
        txTime   = traceSat.txTime_str{i};

        %% --- Estimated user position (from GNSS_interp) ---
        [~, idx_e] = min(abs(t_gnss_interp - tow));

        e = GNSS_interp(idx_e, 2:4);

        %% --- Ground truth position ---
        [~, idx_gt] = min(abs(t_gt - tow));

        t = GT_trim(idx_gt, 2:4);

        %% --- Compute ranges ---
        true_range = norm(s - t);
        est_range  = norm(s - e);

        residual = est_range - true_range;

        %% --- Store ---
        result = [result; {
            week, tow, satID, ...
            true_range, est_range, residual, ...
            recvTime, txTime
        }];

    catch
        continue;
    end
end

%% Convert to table
varNames = {...
    'Week','GPST_TOW','SatID', ...
    'TrueRange','EstimatedRange','Residual', ...
    'RecvTime','TxTime'};

finalTable = cell2table(result, 'VariableNames', varNames);

%% Save
save('/MATLAB Drive/Thesis-data/residual/final_residuals.mat', 'finalTable');

fprintf('Done. Computed %d residuals.\n', height(finalTable));

%% Preview
head(finalTable)


res = finalTable.Residual;

figure;
histogram(res, 50); % 50 bins (you can adjust)

xlabel('Residual (meters)');
ylabel('Frequency');
title('Histogram of Residuals');
grid on;


% Condition: residual > 5 m AND SNR (C/N0) < 20 dB


%% Threshold analysis
idx = (res > 10);

num_epochs = sum(idx);
fprintf('Number of epochs with residual > 5 m: %d\n', num_epochs);

percentage = (num_epochs / height(finalTable)) * 100;
fprintf('Percentage: %.2f%%\n', percentage);

%% Epoch-wise mean (receiver bias insight)
epochSummary = groupsummary(finalTable, 'GPST_TOW', 'mean', 'Residual');

meanResiduals = epochSummary.mean_Residual;

totalMean = mean(meanResiduals);
fprintf('Overall Mean Offset: %.4f m\n', totalMean);
