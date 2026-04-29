%% Ground Truth Processing Script (Updated)
% This script reads gt.csv, converts GPS time to UTC, and saves to .mat

% 1. Setup File Paths
input_file = 'C:\KLTdataset\label\0610_KLT1_203\gt.csv'; 
output_file = 'C:\KLTdataset\label\0610_KLT1_203\ground_truth_data.mat';
leap_seconds = 18; % Constant for data after Jan 2017

% 2. Read the CSV Data
if exist(input_file, 'file')
    raw_data = readmatrix(input_file);
else
    error('File not found: %s', input_file);
end

% 3. Extract and Convert
% Column 1: GPS Timestamp (Absolute Seconds since Jan 6, 1980)
% Column 2: Latitude
% Column 3: Longitude
% Column 4: Height
gps_time_abs = raw_data(:, 1); 
latitude = raw_data(:, 2);
longitude = raw_data(:, 3);
height = raw_data(:, 4);

% --- CORRECTED LEAP SECOND MATH ---
% GPS is ahead of UTC. To get UTC, we subtract the offset.
utc_time_seconds = round(gps_time_abs - leap_seconds);

% Convert to MATLAB datetime objects for plotting and inspection
% Using 'posixtime' for 1970-based Unix comparison, but adjusting for 
% the GPS-Unix epoch difference (315964800 seconds).
% However, the simplest way is to use 'gps' directly if your toolbox supports it,
% otherwise, we treat it as Unix time for standard labeling:
utc_datetime = datetime(utc_time_seconds, 'ConvertFrom', 'posixtime', 'TimeZone', 'UTC');

% 4. Save to .mat file
% We include the absolute GPS time because that is what you need for GNSS fusion.
save(output_file, 'utc_time_seconds', 'latitude', 'longitude', 'height');

fprintf('Successfully processed %d records.\n', size(raw_data, 1));
fprintf('Saved to: %s\n', output_file);

%% 5. Quick Visualization
figure('Name', 'Ground Truth Verification');
subplot(2,1,1);
plot(longitude, latitude, 'b', 'LineWidth', 1.5);
grid on; axis equal;
title('Trajectory (Horizontal)');
xlabel('Longitude (deg)'); ylabel('Latitude (deg)');

subplot(2,1,2);
plot(utc_datetime, height, 'r');
grid on; 
title('Height Profile (UTC Time)');
xlabel('Time (UTC)'); ylabel('Height (m)');