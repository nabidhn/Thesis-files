clc; clear;

%% =========================
% Load Ground Truth (NEW FORMAT)
%% =========================
GT = load('C:\KLTdataset\label\0610_KLT1_203\ground_truth_enhanced.mat');

gt = GT.GT_table;   % ✅ FIX: use table directly

t_gt   = gt.gps_sow;
Xgt    = gt.ecefX;
Ygt    = gt.ecefY;
Zgt    = gt.ecefZ;

lat_gt = gt.latitude;
lon_gt = gt.longitude;

%% =========================
% Load Estimated GNSS
%% =========================
EST = load('C:\KLTdataset\data\GNSS\20210610\track1\GNSS_interp.mat');

t_est = EST.GNSS_interp(:,1);
Xest  = EST.GNSS_interp(:,2);
Yest  = EST.GNSS_interp(:,3);
Zest  = EST.GNSS_interp(:,4);

%% =========================
% Time alignment (GT reference)
%% =========================
Xest_i = interp1(t_est, Xest, t_gt, 'linear', 'extrap');
Yest_i = interp1(t_est, Yest, t_gt, 'linear', 'extrap');
Zest_i = interp1(t_est, Zest, t_gt, 'linear', 'extrap');

%% =========================
% ECEF differences
%% =========================
dX = Xest_i - Xgt;
dY = Yest_i - Ygt;
dZ = Zest_i - Zgt;

%% =========================
% ENU conversion (correct local frame)
%% =========================
N = length(t_gt);

E  = zeros(N,1);
Nn = zeros(N,1);
U  = zeros(N,1);

lat = deg2rad(lat_gt);
lon = deg2rad(lon_gt);

for i = 1:N

    R = [ -sin(lon(i))              cos(lon(i))             0;
          -sin(lat(i))*cos(lon(i)) -sin(lat(i))*sin(lon(i))  cos(lat(i));
           cos(lat(i))*cos(lon(i))  cos(lat(i))*sin(lon(i))  sin(lat(i)) ];

    enu = R * [dX(i); dY(i); dZ(i)];

    E(i)  = enu(1);
    Nn(i) = enu(2);
    U(i)  = enu(3);
end

%% =========================
% Error metrics
%% =========================
horizontal_err = sqrt(E.^2 + Nn.^2);
vertical_err   = abs(U);
err_3d         = sqrt(E.^2 + Nn.^2 + U.^2);

%% =========================
% Statistics
%% =========================
fprintf('\n===== POSITION ERROR STATS (ENU FRAME) =====\n');

fprintf('3D RMSE         : %.3f m\n', sqrt(mean(err_3d.^2)));
fprintf('Horizontal RMSE : %.3f m\n', sqrt(mean(horizontal_err.^2)));
fprintf('Vertical RMSE   : %.3f m\n', sqrt(mean(vertical_err.^2)));

fprintf('\nMean 3D Error   : %.3f m\n', mean(err_3d));
fprintf('Max 3D Error    : %.3f m\n', max(err_3d));

%% =========================
% Plots
%% =========================
figure;

subplot(3,1,1);
plot(t_gt, err_3d,'LineWidth',1.2);
grid on;
title('3D Position Error');
ylabel('Error (m)');

subplot(3,1,2);
plot(t_gt, horizontal_err,'LineWidth',1.2);
grid on;
title('Horizontal Error');
ylabel('Error (m)');

subplot(3,1,3);
plot(t_gt, vertical_err,'LineWidth',1.2);
grid on;
title('Vertical Error');
ylabel('Error (m)');
xlabel('GPS SOW');

%% =========================
% ENU scatter
%% =========================
figure;
plot(E, Nn, '.');
grid on;
axis equal;
title('ENU Horizontal Error Scatter');
xlabel('East (m)');
ylabel('North (m)');