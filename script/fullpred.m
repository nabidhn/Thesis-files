%% =============================================================
%  GNSS ML MODEL USING XGBOOST (BOOSTED TREES)
%  FULL DATASET 3D ERROR (CROSS-VALIDATED, NO LEAKAGE)
%% =============================================================

clear; clc;

%% =========================
% Load Data
%% =========================
load('C:\UrbanNav\DeepUrban\mat\final_residuals_fused.mat');
disp('Dataset loaded');

%% =========================
% FEATURES (NO LEAKAGE!)
%% =========================
X = [ ...
    finalTable.SNR, ...
    finalTable.Azimuth, ...
    finalTable.Elevation, ...
    finalTable.Pseudorange ...
    finalTable.Doppler...
];

% Normalize
X = normalize(X);

%% TARGETS
Yx = finalTable.dX;
Yy = finalTable.dY;
Yz = finalTable.dZ;

%% Remove NaNs
valid = all(~isnan(X),2) & ~isnan(Yx) & ~isnan(Yy) & ~isnan(Yz);

X = X(valid,:);
Yx = Yx(valid);
Yy = Yy(valid);
Yz = Yz(valid);
finalTable = finalTable(valid,:);

fprintf('Valid dataset size: %d samples\n', size(X,1));

%% =========================
% MODEL TEMPLATE
%% =========================
t = templateTree('MaxNumSplits',20);

%% =============================================================
% PART 1 — TRAIN/TEST (FOR BASELINE EVALUATION)
%% =============================================================

cv = cvpartition(size(X,1),'HoldOut',0.2);

idxTrain = training(cv);
idxTest  = test(cv);

X_train = X(idxTrain,:);
X_test  = X(idxTest,:);

Yx_train = Yx(idxTrain); Yx_test = Yx(idxTest);
Yy_train = Yy(idxTrain); Yy_test = Yy(idxTest);
Yz_train = Yz(idxTrain); Yz_test = Yz(idxTest);

disp('Training baseline models...');

mdlX = fitrensemble(X_train, Yx_train, ...
    'Method','LSBoost','NumLearningCycles',200,'Learners',t,'LearnRate',0.05);

mdlY = fitrensemble(X_train, Yy_train, ...
    'Method','LSBoost','NumLearningCycles',200,'Learners',t,'LearnRate',0.05);

mdlZ = fitrensemble(X_train, Yz_train, ...
    'Method','LSBoost','NumLearningCycles',200,'Learners',t,'LearnRate',0.05); 

%% Prediction (test only)
pred_dx = predict(mdlX, X_test);
pred_dy = predict(mdlY, X_test);
pred_dz = predict(mdlZ, X_test);

%% RMSE
rmse_dx = sqrt(mean((pred_dx - Yx_test).^2));
rmse_dy = sqrt(mean((pred_dy - Yy_test).^2));
rmse_dz = sqrt(mean((pred_dz - Yz_test).^2));

fprintf('\nTEST RMSE:\n');
fprintf('dX: %.3f m | dY: %.3f m | dZ: %.3f m\n', rmse_dx, rmse_dy, rmse_dz);

%% =========================
% TEST 3D ERROR
%% =========================
finalTest = finalTable(idxTest,:);

EstX = finalTest.EstX; EstY = finalTest.EstY; EstZ = finalTest.EstZ;
GTX = finalTest.GT_X;  GTY = finalTest.GT_Y;  GTZ = finalTest.GT_Z;

err_before = sqrt((EstX - GTX).^2 + (EstY - GTY).^2 + (EstZ - GTZ).^2);

corrX = EstX - pred_dx;
corrY = EstY - pred_dy;
corrZ = EstZ - pred_dz;

err_after = sqrt((corrX - GTX).^2 + (corrY - GTY).^2 + (corrZ - GTZ).^2);

fprintf('\nTEST 3D ERROR:\n');
fprintf('Mean BEFORE: %.3f m\n', mean(err_before));
fprintf('Mean AFTER : %.3f m\n', mean(err_after));

%% =============================================================
% PART 2 — FULL DATASET (CROSS-VALIDATED, NO LEAKAGE)
%% =============================================================

disp('Running K-Fold cross-validation on full dataset...');

k = 5;
cv_full = cvpartition(size(X,1),'KFold',k);

pred_dx_all = zeros(size(Yx));
pred_dy_all = zeros(size(Yy));
pred_dz_all = zeros(size(Yz));

for i = 1:k
    fprintf('Fold %d/%d\n', i, k);

    idxTrain = training(cv_full, i);
    idxTest  = test(cv_full, i);

    mdlX_cv = fitrensemble(X(idxTrain,:), Yx(idxTrain), ...
        'Method','LSBoost','NumLearningCycles',200,'Learners',t,'LearnRate',0.05);

    mdlY_cv = fitrensemble(X(idxTrain,:), Yy(idxTrain), ...
        'Method','LSBoost','NumLearningCycles',200,'Learners',t,'LearnRate',0.05);

    mdlZ_cv = fitrensemble(X(idxTrain,:), Yz(idxTrain), ...
        'Method','LSBoost','NumLearningCycles',200,'Learners',t,'LearnRate',0.05);

    pred_dx_all(idxTest) = predict(mdlX_cv, X(idxTest,:));
    pred_dy_all(idxTest) = predict(mdlY_cv, X(idxTest,:));
    pred_dz_all(idxTest) = predict(mdlZ_cv, X(idxTest,:));
end

%% =========================
% FULL DATASET 3D ERROR
%% =========================

EstX = finalTable.EstX;
EstY = finalTable.EstY;
EstZ = finalTable.EstZ;

GTX = finalTable.GT_X;
GTY = finalTable.GT_Y;
GTZ = finalTable.GT_Z;

% BEFORE
err_before_all = sqrt((EstX - GTX).^2 + ...
                      (EstY - GTY).^2 + ...
                      (EstZ - GTZ).^2);

% AFTER
corrX_all = EstX - pred_dx_all;
corrY_all = EstY - pred_dy_all;
corrZ_all = EstZ - pred_dz_all;

err_after_all = sqrt((corrX_all - GTX).^2 + ...
                     (corrY_all - GTY).^2 + ...
                     (corrZ_all - GTZ).^2);

%% =========================
% FINAL RESULTS
%% =========================

fprintf('\nFULL DATASET RESULTS:\n');
fprintf('Mean BEFORE: %.3f m\n', mean(err_before_all));
fprintf('Mean AFTER : %.3f m\n', mean(err_after_all));

fprintf('\nRMSE 3D BEFORE: %.3f m\n', sqrt(mean(err_before_all.^2)));
fprintf('RMSE 3D AFTER : %.3f m\n', sqrt(mean(err_after_all.^2)));

fprintf('\n95th percentile BEFORE: %.3f m\n', prctile(err_before_all,95));
fprintf('95th percentile AFTER : %.3f m\n', prctile(err_after_all,95));

%% =========================
% PLOTS
%% =========================

% Time series
figure;
plot(err_before_all,'r'); hold on;
plot(err_after_all,'g');
legend('Before','After');
title('3D Position Error (Full Dataset)');
xlabel('Sample'); ylabel('Error (m)');
grid on;

% Boxplot
figure;
boxplot([err_before_all err_after_all], 'Labels', {'Before','After'});
ylabel('Error (m)');
title('Error Distribution');
grid on;

% CDF (important for GNSS)
figure;
cdfplot(err_before_all); hold on;
cdfplot(err_after_all);
legend('Before','After');
title('CDF of 3D Position Error');
xlabel('Error (m)');
grid on;

%% =========================
% FEATURE IMPORTANCE
%% =========================
figure;
imp = predictorImportance(mdlX);
bar(imp);
set(gca,'XTickLabel',{'SNR','Az','El','Residual', 'statres','ISPDR'});
title('Feature Importance');
grid on;

%% =========================
% SAVE MODEL
%% =========================
save('C:\UrbanNav\DeepUrban\mat\xgboost_model.mat', ...
    'mdlX','mdlY','mdlZ');



