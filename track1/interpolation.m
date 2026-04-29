clc; clear;

POS = load('C:\KLTdataset\data\GNSS\20210610\gt1.pos');
t_gnss = POS(:,2);
Xg = POS(:,3);
Yg = POS(:,4);
Zg = POS(:,5);


GNSS_interp = [t_gnss, Xg, Yg, Zg];

save('C:\KLTdataset\data\GNSS\20210610\track1\GNSS_interp.mat','GNSS_interp');

disp('Interpolation done with gap threshold');

%% Load MAT file
input_file = 'C:\KLTdataset\label\0610_KLT2_209\ground_truth_data.mat';
load(input_file);

%% Constants
gps_epoch_unix = 315964800;  % 1980-01-06 (Unix reference)
leap_seconds = 18;           % adjust if needed

%% 1. UTC (Unix) → GPS seconds
gps_seconds = utc_time_seconds - gps_epoch_unix + leap_seconds;

%% 2. GPS Week + Seconds of Week (SOW)
gps_week = floor(gps_seconds / 604800);
gps_sow  = mod(gps_seconds, 604800);

%% 3. LLA → ECEF (using MATLAB built-in function)
% Make sure inputs are:
% latitude  = degrees
% longitude = degrees
% height    = meters

ecef = lla2ecef([latitude, longitude, height]);  
% Output: Nx3 [X Y Z] in meters

ecefX = ecef(:,1);
ecefY = ecef(:,2);
ecefZ = ecef(:,3);

%% 4. Save enhanced dataset
output_mat = 'C:\KLTdataset\label\0610_KLT2_209\ground_truth_enhanced.mat';

GT_table = table( ...
    utc_time_seconds, ...
    gps_week, ...
    gps_sow, ...
    latitude, ...
    longitude, ...
    height, ...
    ecefX, ...
    ecefY, ...
    ecefZ);

save(output_mat, ...
    'utc_time_seconds', ...
    'gps_week', ...
    'gps_sow', ...
    'latitude', ...
    'longitude', ...
    'height', ...
    'ecefX', ...
    'ecefY', ...
    'ecefZ', ...
    'GT_table');

fprintf('Saved GNSS dataset with lla2ecef conversion.\n');
fprintf('Output: %s\n', output_mat);

%% 5. Quick check plot
figure;

subplot(2,1,1);
plot(gps_sow, height);
grid on;
title('Height vs GPS Time of Week');
xlabel('GPS SOW (s)');
ylabel('Height (m)');

subplot(2,1,2);
plot3(ecefX, ecefY, ecefZ);  % ✅ FIXED
grid on;
axis equal;
title('ECEF Trajectory');
xlabel('X (m)'); ylabel('Y (m)'); zlabel('Z (m)');
