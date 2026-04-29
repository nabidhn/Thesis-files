%% =============================================================
%  GNSS ML MODEL — LSBoost
%  CORRECTED RECEIVER POSITION SAVED AS LLA
%% =============================================================
clear; clc;

%% =========================
%  LOAD DATA
%% =========================
load('C:\UrbanNav\DeepUrban\mat\final_residuals_fused.mat');
disp('Dataset loaded');

%% =========================
%  FEATURES
%% =========================
X = [ ...
    finalTable.SNR,         ...
    finalTable.Azimuth,     ...
    finalTable.Elevation,   ...
    finalTable.Pseudorange, ...
    finalTable.Doppler      ...
];

X = normalize(X);

%% TARGETS
Yx = finalTable.dX;
Yy = finalTable.dY;
Yz = finalTable.dZ;

%% Remove NaNs
valid      = all(~isnan(X),2) & ~isnan(Yx) & ~isnan(Yy) & ~isnan(Yz);
X          = X(valid,:);
Yx         = Yx(valid);
Yy         = Yy(valid);
Yz         = Yz(valid);
finalTable = finalTable(valid,:);

fprintf('Valid dataset size: %d samples\n', size(X,1));

%% =========================
%  MODEL TEMPLATE
%% =========================
t = templateTree('MaxNumSplits', 20);

%% =============================================================
%  PART 1 — TRAIN / TEST  (baseline evaluation)
%% =============================================================
cv       = cvpartition(size(X,1), 'HoldOut', 0.2);
idxTrain = training(cv);
idxTest  = test(cv);

X_train  = X(idxTrain,:);
X_test   = X(idxTest,:);

Yx_train = Yx(idxTrain);  Yx_test = Yx(idxTest);
Yy_train = Yy(idxTrain);  Yy_test = Yy(idxTest);
Yz_train = Yz(idxTrain);  Yz_test = Yz(idxTest);

disp('Training baseline models...');

mdlX = fitrensemble(X_train, Yx_train, ...
    'Method','LSBoost','NumLearningCycles',200,'Learners',t,'LearnRate',0.02);
mdlY = fitrensemble(X_train, Yy_train, ...
    'Method','LSBoost','NumLearningCycles',200,'Learners',t,'LearnRate',0.02);
mdlZ = fitrensemble(X_train, Yz_train, ...
    'Method','LSBoost','NumLearningCycles',200,'Learners',t,'LearnRate',0.02);

pred_dx = predict(mdlX, X_test);
pred_dy = predict(mdlY, X_test);
pred_dz = predict(mdlZ, X_test);

rmse_dx = sqrt(mean((pred_dx - Yx_test).^2));
rmse_dy = sqrt(mean((pred_dy - Yy_test).^2));
rmse_dz = sqrt(mean((pred_dz - Yz_test).^2));

fprintf('\nTEST RMSE:\n');
fprintf('dX: %.3f m | dY: %.3f m | dZ: %.3f m\n', rmse_dx, rmse_dy, rmse_dz);

%% Test 3D error
finalTest = finalTable(idxTest,:);
EstX = finalTest.EstX;  EstY = finalTest.EstY;  EstZ = finalTest.EstZ;
GTX  = finalTest.GT_X;  GTY  = finalTest.GT_Y;  GTZ  = finalTest.GT_Z;

err_before = sqrt((EstX-GTX).^2 + (EstY-GTY).^2 + (EstZ-GTZ).^2);

corrX_test = EstX - pred_dx;
corrY_test = EstY - pred_dy;
corrZ_test = EstZ - pred_dz;

err_after = sqrt((corrX_test-GTX).^2 + (corrY_test-GTY).^2 + (corrZ_test-GTZ).^2);

fprintf('\nTEST 3D ERROR:\n');
fprintf('Mean BEFORE: %.3f m\n', mean(err_before));
fprintf('Mean AFTER : %.3f m\n', mean(err_after));

%% =============================================================
%  PART 2 — FULL DATASET  (5-fold cross-validated, no leakage)
%% =============================================================
disp('Running 5-fold cross-validation on full dataset...');

k       = 5;
cv_full = cvpartition(size(X,1), 'KFold', k);

pred_dx_all = zeros(size(Yx));
pred_dy_all = zeros(size(Yy));
pred_dz_all = zeros(size(Yz));

for i = 1:k
    fprintf('Fold %d/%d\n', i, k);
    idxTr = training(cv_full, i);
    idxTe = test(cv_full,     i);

    mdlX_cv = fitrensemble(X(idxTr,:), Yx(idxTr), ...
        'Method','LSBoost','NumLearningCycles',200,'Learners',t,'LearnRate',0.05);
    mdlY_cv = fitrensemble(X(idxTr,:), Yy(idxTr), ...
        'Method','LSBoost','NumLearningCycles',200,'Learners',t,'LearnRate',0.05);
    mdlZ_cv = fitrensemble(X(idxTr,:), Yz(idxTr), ...
        'Method','LSBoost','NumLearningCycles',200,'Learners',t,'LearnRate',0.05);

    pred_dx_all(idxTe) = predict(mdlX_cv, X(idxTe,:));
    pred_dy_all(idxTe) = predict(mdlY_cv, X(idxTe,:));
    pred_dz_all(idxTe) = predict(mdlZ_cv, X(idxTe,:));
end

%% =============================================================
%  PART 3 — CORRECTED RECEIVER POSITION + ECEF → LLA
%% =============================================================

%% Corrected ECEF
corrX_all = finalTable.EstX - pred_dx_all;
corrY_all = finalTable.EstY - pred_dy_all;
corrZ_all = finalTable.EstZ - pred_dz_all;

%% ECEF → LLA using Aerospace Toolbox
%  ecef2lla([x y z]) → [lat(deg) lon(deg) alt(m)]  WGS-84
lla_corr = ecef2lla([corrX_all,       corrY_all,       corrZ_all      ]);
lla_est  = ecef2lla([finalTable.EstX, finalTable.EstY, finalTable.EstZ]);
lla_gt   = ecef2lla([finalTable.GT_X, finalTable.GT_Y, finalTable.GT_Z]);

%% =========================
%  3D ERROR  (full dataset)
%% =========================
EstX = finalTable.EstX;  EstY = finalTable.EstY;  EstZ = finalTable.EstZ;
GTX  = finalTable.GT_X;  GTY  = finalTable.GT_Y;  GTZ  = finalTable.GT_Z;

err_before_all = sqrt((EstX-GTX).^2      + (EstY-GTY).^2      + (EstZ-GTZ).^2);
err_after_all  = sqrt((corrX_all-GTX).^2 + (corrY_all-GTY).^2 + (corrZ_all-GTZ).^2);

fprintf('\nFULL DATASET RESULTS:\n');
fprintf('Mean  BEFORE : %.3f m\n', mean(err_before_all));
fprintf('Mean  AFTER  : %.3f m\n', mean(err_after_all));
fprintf('RMSE  BEFORE : %.3f m\n', sqrt(mean(err_before_all.^2)));
fprintf('RMSE  AFTER  : %.3f m\n', sqrt(mean(err_after_all.^2)));
fprintf('95pct BEFORE : %.3f m\n', prctile(err_before_all, 95));
fprintf('95pct AFTER  : %.3f m\n', prctile(err_after_all,  95));

%% =========================
%  BUILD LLA TABLE
%% =========================
LLA_table = table( ...
    finalTable.GPST_TOW,                          ...                          ...
    lla_corr(:,1), lla_corr(:,2), lla_corr(:,3),  ...
    lla_est(:,1),  lla_est(:,2),  lla_est(:,3),   ...
    lla_gt(:,1),   lla_gt(:,2),   lla_gt(:,3),    ...
    err_before_all, err_after_all,                 ...
    'VariableNames', { ...
        'GPST_TOW',  ...
        'Corr_Lat',  'Corr_Lon',  'Corr_Alt', ...
        'Est_Lat',   'Est_Lon',   'Est_Alt',  ...
        'GT_Lat',    'GT_Lon',    'GT_Alt',   ...
        'Err3D_Before', 'Err3D_After'});

%% One row per epoch (positions are epoch-level)
[~, epochIdx] = unique(LLA_table.GPST_TOW, 'stable');
LLA_table     = LLA_table(epochIdx, :);

fprintf('\nUnique epochs saved: %d\n', height(LLA_table));

%% =========================
%  SAVE
%% =========================
save('C:\UrbanNav\DeepUrban\mat\corrected_positions_lla.mat', 'LLA_table');
fprintf('Saved: corrected_positions_lla.mat\n');

%% =========================
%  PLOTS
%% =========================

% 1. Time series
figure;
plot(err_before_all, 'r', 'DisplayName','Before'); hold on;
plot(err_after_all,  'g', 'DisplayName','After');
xlabel('Sample'); ylabel('3D Error (m)');
title('3D Position Error — Before vs After');
legend; grid on;

% 2. CDF
figure;
cdfplot(err_before_all); hold on;
cdfplot(err_after_all);
legend('Before','After','Location','southeast');
xlabel('3D Error (m)');
title('CDF of 3D Position Error');
grid on;

% 3. Boxplot
figure;
boxplot([err_before_all, err_after_all], 'Labels', {'Before','After'});
ylabel('3D Error (m)');
title('Error Distribution');
grid on;

% 4. Trajectory (Lat/Lon)
figure;
plot(LLA_table.Est_Lon,  LLA_table.Est_Lat,  'r.',  'DisplayName','Estimated');  hold on;
plot(LLA_table.Corr_Lon, LLA_table.Corr_Lat, 'g.',  'DisplayName','Corrected');
plot(LLA_table.GT_Lon,   LLA_table.GT_Lat,   'b--', 'DisplayName','Ground Truth','LineWidth',1.5);
xlabel('Longitude (deg)'); ylabel('Latitude (deg)');
title('Trajectory — Estimated vs Corrected vs Ground Truth');
legend; grid on; axis equal;

% 5. Altitude
figure;
plot(LLA_table.GPST_TOW, LLA_table.Est_Alt,  'r',   'DisplayName','Estimated');  hold on;
plot(LLA_table.GPST_TOW, LLA_table.Corr_Alt, 'g',   'DisplayName','Corrected');
plot(LLA_table.GPST_TOW, LLA_table.GT_Alt,   'b--', 'DisplayName','Ground Truth');
xlabel('GPST TOW (s)'); ylabel('Altitude (m)');
title('Altitude Over Time');
legend; grid on;

% 6. Feature importance
figure;
imp = predictorImportance(mdlX);
bar(imp);
set(gca,'XTickLabel',{'SNR','Azimuth','Elevation','Pseudorange','Doppler'});
xtickangle(30);
ylabel('Importance');
title('Feature Importance (dX model)');
grid on;

%% =========================
%  SAVE MODELS
%% =========================
save('C:\UrbanNav\harshurban\mat\lsboost_models.mat', 'mdlX','mdlY','mdlZ');

disp('Done.');
