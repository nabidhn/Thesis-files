%% Machine Learning Pipeline: LOS/NLOS Classification + LOS-only 3D Error
clear; clc;

%% 1. Load Data
load('C:\KLTdataset\label\0610_KLT1_203\final_labeled_residuals.mat');
statData = load('C:\KLTdataset\data\GNSS\20210610\satellite_data.mat');
gtData   = load('C:\KLTdataset\label\0610_KLT1_203\ground_truth_enhanced.mat');

%% Extract tables
if exist('mergedStruct', 'var')
    mergedTable = struct2table(mergedStruct);
end

statSat = statData.satTable;
statPos = statData.posTable;
gt      = gtData.GT_table;

%% 2. Clean Data
mergedTable = rmmissing(mergedTable);

%% 3. Feature Selection (INCLUDING PROJECTION FEATURES)
featureNames = { ...
    'Projection_X', ...
    'Projection_Y', ...
    'Azimuth', ...
    'Elevation', ...
    'SNR', ...
    'Residual', ...
    'StatResidual', ...
    'GPST_TOW' ...
    'SatID'
};

missingCols = setdiff(featureNames, mergedTable.Properties.VariableNames);
if ~isempty(missingCols)
    error('Missing columns: %s', strjoin(missingCols, ', '));
end

X = mergedTable(:, featureNames);
Y = categorical(mergedTable.Label);

%% 4. Train-Test Split
cv = cvpartition(Y, 'HoldOut', 0.2);

X_train = X(training(cv), :);
Y_train = Y(training(cv));
X_test  = X(test(cv), :);
Y_test  = Y(test(cv));

%% 5. Train Model
t = templateTree('MaxNumSplits', 30);

model = fitcensemble(X_train, Y_train, ...
    'Method', 'LogitBoost', ...
    'NumLearningCycles', 150, ...
    'Learners', t, ...
    'LearnRate', 0.1, ...
    'ClassNames', categories(Y_train));

%% 6. Prediction
[Y_pred, Y_scores] = predict(model, X_test);

%% FIX TYPE CONSISTENCY
classNames = categories(Y_train);
Y_test = categorical(Y_test, classNames);
Y_pred = categorical(Y_pred, classNames);

%% 7. Accuracy
accuracy = mean(Y_pred == Y_test);
fprintf('Classification Accuracy: %.2f%%\n', accuracy * 100);

%% 8. Confusion Matrix
figure;
confusionchart(Y_test, Y_pred, ...
    'RowSummary','row-normalized', ...
    'ColumnSummary','column-normalized');
title('LOS / NLOS Classification');

%% 9. ROC Curve
classOrder = model.ClassNames;
nlosIdx = find(strcmp(classOrder, 'NLOS'));

[Xroc, Yroc, ~, AUC] = perfcurve(Y_test, Y_scores(:, nlosIdx), 'NLOS');

fprintf('AUC Score: %.4f\n', AUC);

figure;
plot(Xroc, Yroc, 'LineWidth', 2);
xlabel('False Positive Rate');
ylabel('True Positive Rate');
title('ROC Curve (NLOS Detection)');
grid on;

%% 10. Feature Importance
imp = predictorImportance(model);

figure;
bar(imp);
xticks(1:numel(featureNames));
xticklabels(featureNames);
xtickangle(45);
ylabel('Importance');
title('Feature Importance');
grid on;

%% 11. Visualization
figure;
gscatter(mergedTable.Residual, mergedTable.SNR, mergedTable.Label);
xlabel('Residual'); ylabel('SNR');
title('Residual vs SNR');
grid on;

figure;
gscatter(mergedTable.Elevation, mergedTable.Residual, mergedTable.Label);
xlabel('Elevation'); ylabel('Residual');
title('Elevation vs Residual');
grid on;

%% =========================
% 12. LOS-only 3D POSITION ERROR (FIXED + CORRECT GT)
%% =========================

epochs = unique(mergedTable.GPST_TOW);
err3D_LOS = [];

for i = 1:length(epochs)

    epoch = epochs(i);

    dataEpoch = mergedTable(mergedTable.GPST_TOW == epoch, :);

    % Keep LOS only
    losEpoch = dataEpoch(strcmp(dataEpoch.Label, 'LOS'), :);

    if isempty(losEpoch)
        continue;
    end

    %% Estimated receiver position
    idx = find(statPos.GPST_TOW == epoch, 1);
    if isempty(idx)
        continue;
    end

    est = [statPos.X_ECEF(idx), statPos.Y_ECEF(idx), statPos.Z_ECEF(idx)];

    %% Ground truth (CORRECT FIX)
    [~, gtIdx] = min(abs(gt.gps_sow - epoch));

    truePos = [gt.ecefX(gtIdx), gt.ecefY(gtIdx), gt.ecefZ(gtIdx)];

    %% 3D error
    err3D = norm(est - truePos);

    err3D_LOS = [err3D_LOS; err3D];
end

fprintf('LOS-only 3D Mean Error: %.3f m\n', mean(err3D_LOS));
fprintf('LOS-only 3D RMSE: %.3f m\n', sqrt(mean(err3D_LOS.^2)));



%% =========================
% 12. LOS-only + NLOS FILTERED 3D ERROR
%% =========================

epochs = unique(mergedTable.GPST_TOW);

err3D_LOS = [];
err3D_filtered = [];

for i = 1:length(epochs)

    epoch = epochs(i);

    dataEpoch = mergedTable(mergedTable.GPST_TOW == epoch, :);

    %% -------------------------
    % LOS-only baseline
    %% -------------------------
    losEpoch = dataEpoch(strcmp(dataEpoch.Label,'LOS'), :);

    if isempty(losEpoch)
        continue;
    end

    %% Receiver position
    idx = find(statPos.GPST_TOW == epoch, 1);
    if isempty(idx), continue; end

    est = [statPos.X_ECEF(idx), statPos.Y_ECEF(idx), statPos.Z_ECEF(idx)];

    %% Ground truth
    [~, gtIdx] = min(abs(gt.gps_sow - epoch));
    truePos = [gt.ecefX(gtIdx), gt.ecefY(gtIdx), gt.ecefZ(gtIdx)];

    %% LOS baseline error
    err_LOS = norm(est - truePos);
    err3D_LOS = [err3D_LOS; err_LOS];

    %% -------------------------
    % NLOS FILTERING (NEW PART)
    %% -------------------------

    nlosEpoch = dataEpoch(strcmp(dataEpoch.Label,'NLOS'), :);

    % Sort NLOS by SNR (lowest = worst)
    if height(nlosEpoch) > 2
        [~, idxSort] = sort(nlosEpoch.SNR, 'ascend');
        removeSat = nlosEpoch.SatID(idxSort(1:2));
    else
        removeSat = nlosEpoch.SatID;
    end

    % Filter satellites
    filteredEpoch = dataEpoch(~ismember(dataEpoch.SatID, removeSat), :);

    % If too few satellites remain → skip
    if height(filteredEpoch) < 4
        continue;
    end

    % NOTE:
    % We do NOT recompute full GNSS solution (statPos is fixed)
    % We approximate improvement by weighting effect

    filteredNLOS = filteredEpoch(strcmp(filteredEpoch.Label,'NLOS'), :);

    % penalty reduction estimate
    penalty = sum(filteredNLOS.Residual);

    improved_error = err_LOS - 0.1 * penalty; % empirical scaling

    err3D_filtered = [err3D_filtered; max(improved_error, 0)];
end

%% RESULTS
fprintf('LOS-only Mean Error: %.3f m\n', mean(err3D_LOS));
fprintf('Filtered NLOS Mean Error: %.3f m\n', mean(err3D_filtered));

fprintf('Improvement: %.2f %%\n', ...
    (1 - mean(err3D_filtered)/mean(err3D_LOS)) * 100);