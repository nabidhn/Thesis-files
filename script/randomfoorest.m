%% =============================================================
%  GNSS ML MODEL USING XGBOOST (BOOSTED TREES)
%% =============================================================

clear; clc;

%% =========================
% Load Data
%% =========================
load('/MATLAB Drive/Thesis-data/residual/final_residuals_fused.mat');

disp('Dataset loaded');

%% =========================
% FEATURES (NO LEAKAGE!)
%% =========================
X = [ ...
    finalTable.SNR, ...
    finalTable.Azimuth, ...
    finalTable.Elevation, ...
    finalTable.Doppler ...
    finalTable.RangeResidual ...
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
% Train/Test Split
%% =========================
cv = cvpartition(size(X,1),'HoldOut',0.2);

idxTrain = training(cv);
idxTest  = test(cv);

X_train = X(idxTrain,:);
X_test  = X(idxTest,:);

Yx_train = Yx(idxTrain); Yx_test = Yx(idxTest);
Yy_train = Yy(idxTrain); Yy_test = Yy(idxTest);
Yz_train = Yz(idxTrain); Yz_test = Yz(idxTest);

disp('Data split complete');

%% =========================
% XGBOOST-LIKE MODELS
%% =========================
disp('Training XGBoost models...');

t = templateTree('MaxNumSplits',20);

mdlX = fitrensemble(X_train, Yx_train, ...
    'Method','LSBoost', ...
    'NumLearningCycles',200, ...
    'Learners',t, ...
    'LearnRate',0.05);

mdlY = fitrensemble(X_train, Yy_train, ...
    'Method','LSBoost', ...
    'NumLearningCycles',200, ...
    'Learners',t, ...
    'LearnRate',0.05);

mdlZ = fitrensemble(X_train, Yz_train, ...
    'Method','LSBoost', ...
    'NumLearningCycles',200, ...
    'Learners',t, ...
    'LearnRate',0.05);

disp('Training complete');

%% =========================
% Prediction
%% =========================
pred_dx = predict(mdlX, X_test);
pred_dy = predict(mdlY, X_test);
pred_dz = predict(mdlZ, X_test);

%% =========================
% RMSE
%% =========================
rmse_dx = sqrt(mean((pred_dx - Yx_test).^2));
rmse_dy = sqrt(mean((pred_dy - Yy_test).^2));
rmse_dz = sqrt(mean((pred_dz - Yz_test).^2));

fprintf('\nPrediction RMSE:\n');
fprintf('dX: %.3f m\n', rmse_dx);
fprintf('dY: %.3f m\n', rmse_dy);
fprintf('dZ: %.3f m\n', rmse_dz);

%% =========================
% POSITION CORRECTION
%% =========================
finalTest = finalTable(idxTest,:);

EstX = finalTest.EstX;
EstY = finalTest.EstY;
EstZ = finalTest.EstZ;

GTX = finalTest.GT_X;
GTY = finalTest.GT_Y;
GTZ = finalTest.GT_Z;

%% BEFORE
err_before = sqrt((EstX - GTX).^2 + ...
                  (EstY - GTY).^2 + ...
                  (EstZ - GTZ).^2);

%% AFTER (apply correction carefully!)
corrX = EstX - pred_dx;
corrY = EstY - pred_dy;
corrZ = EstZ - pred_dz;

err_after = sqrt((corrX - GTX).^2 + ...
                 (corrY - GTY).^2 + ...
                 (corrZ - GTZ).^2);

%% =========================
% RESULTS
%% =========================
fprintf('\nPosition Error Comparison:\n');
fprintf('Mean error BEFORE: %.3f m\n', mean(err_before));
fprintf('Mean error AFTER : %.3f m\n', mean(err_after));

%% =========================
% PLOTS
%% =========================

figure;
plot(err_before,'r'); hold on;
plot(err_after,'g');
legend('Before','After');
title('Position Error Improvement');
xlabel('Sample'); ylabel('Error (m)');
grid on;

figure;
boxplot([err_before err_after], 'Labels', {'Before','After'});
ylabel('Error (m)');
title('Error Distribution');
grid on;

%% =========================
% FEATURE IMPORTANCE
%% =========================
figure;
imp = predictorImportance(mdlX);
bar(imp);
set(gca,'XTickLabel',{'SNR','Az','El','Doppler','residual'});
title('Feature Importance');
grid on;

%% =========================
% SAVE MODEL
%% =========================
save('/MATLAB Drive/Thesis-data/residual/xgboost_model.mat', ...
    'mdlX','mdlY','mdlZ');

disp('XGBoost model saved ');