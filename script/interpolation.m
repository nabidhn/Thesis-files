% 
% %% Ground Truth DMSLLA ECEF
% clc; clear;
% 
% gt_file = '/MATLAB Drive/Thesis-data/residual/UrbanNav_whampoa_raw.txt';
% 
% 
% GT = readtable(gt_file, 'VariableNamingRule','preserve');
% 
% % ---- TIME (seconds of week or seconds since start) ----
% 
% t_gt = GT{:,3};
% 
% % ---- LATITUDE (DMS → DEG) ----
% lat_D = GT{:,4};
% lat_M = GT{:,5};
% lat_S = GT{:,6};
% 
% lat = sign(lat_D) .* (abs(lat_D) + lat_M/60 + lat_S/3600);
% 
% % ---- LONGITUDE (DMS → DEG)
% lon_D = GT{:,7};
% lon_M = GT{:,8};
% lon_S = GT{:,9};
% 
% lon = sign(lon_D) .* (abs(lon_D) + lon_M/60 + lon_S/3600);
% 
% % ---- ALTITUDE (meters
% h = GT{:,10};
% % ---- LLA → ECEF (WGS-84)
% lla = [lat, lon, h];
% ecef = lla2ecef(lla);
% 
% X = ecef(:,1);
% Y = ecef(:,2);
% Z = ecef(:,3);
% 
% % Save
% GT_ECEF = [t_gt, X, Y, Z];
% GT_LLA = [t_gt, lat, lon, h];
% save('/MATLAB Drive/Thesis-data/residual/GT_LLA.mat','GT_LLA');
% save('/MATLAB Drive/Thesis-data/residual/GT_ECEF.mat','GT_ECEF');



clc; clear;

POS = load('C:\UrbanNav\DeepUrban\kinem.pos');
t_gnss = POS(:,2);
Xg = POS(:,3);
Yg = POS(:,4);
Zg = POS(:,5);

load('C:\UrbanNav\DeepUrban\mat\GT_ECEF.mat');
load('C:\UrbanNav\DeepUrban\mat\GT_LLA.mat');
t_gt = GT_ECEF(:,1);
t_lla = GT_LLA(:,1);
%% 🔹 Find overlapping time range
t_start = max(min(t_gnss), min(t_gt));
t_end   = min(max(t_gnss), max(t_gt));

%% 🔹 Trim GT to overlap only
mask = (t_gt >= t_start) & (t_gt <= t_end);

t_gt_trim = t_gt(mask);
GT_trim   = GT_ECEF(mask, :);

GT_LLA_trim = GT_LLA(mask, :);

%% 🔹 Interpolation (NO extrapolation)
Xg_i = interp1(t_gnss, Xg, t_gt_trim, 'linear');
Yg_i = interp1(t_gnss, Yg, t_gt_trim, 'linear');
Zg_i = interp1(t_gnss, Zg, t_gt_trim, 'linear');

%% 🔹 Combine results
GNSS_interp = [t_gt_trim, Xg_i, Yg_i, Zg_i];

%% 🔹 Save files
save('C:\UrbanNav\DeepUrban\mat\GNSS_interp.mat', 'GNSS_interp');
save('C:\UrbanNav\DeepUrban\mat\GT_trim.mat', 'GT_trim');
save('C:\UrbanNav\DeepUrban\mat\GT_LLA_trim.mat', 'GT_LLA_trim');
disp('Interpolation done + trimmed GT saved separately');


%% =============================================================
% 3D Trajectory Plot
%% =============================================================
figure;

plot3(GT_trim(:,2), GT_trim(:,3), GT_trim(:,4), 'g', 'LineWidth', 2); hold on;
plot3(GNSS_interp(:,2), GNSS_interp(:,3), GNSS_interp(:,4), 'r--', 'LineWidth', 1.5);

xlabel('X (m)');
ylabel('Y (m)');
zlabel('Z (m)');
title('3D Ground Truth vs GNSS Trajectory');
legend('Ground Truth','GNSS Estimate');
grid on;
axis equal;
view(3);

%% =============================================================
% Ground Truth vs Estimated Track (ECEF XY)
%% =============================================================
figure;

plot(GT_trim(:,2), GT_trim(:,3), 'g', 'LineWidth', 2); hold on;
plot(GNSS_interp(:,2), GNSS_interp(:,3), 'r--', 'LineWidth', 1.5);

xlabel('X (ECEF)');
ylabel('Y (ECEF)');
title('Ground Truth vs Estimated Trajectory (XY)');
legend('Ground Truth','GNSS Estimate');
grid on;
axis equal;