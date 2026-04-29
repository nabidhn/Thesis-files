
%% Ground Truth DMSLLA ECEF
clc; clear;

gt_file = 'C:\UrbanNav\DeepUrban\UrbanNav_whampoa_raw.txt';


GT = readtable(gt_file, 'VariableNamingRule','preserve');

% ---- TIME (seconds of week or seconds since start) ----

t_gt = GT{:,3};

% ---- LATITUDE (DMS → DEG) ----
lat_D = GT{:,4};
lat_M = GT{:,5};
lat_S = GT{:,6};

lat = sign(lat_D) .* (abs(lat_D) + lat_M/60 + lat_S/3600);

% ---- LONGITUDE (DMS → DEG)
lon_D = GT{:,7};
lon_M = GT{:,8};
lon_S = GT{:,9};

lon = sign(lon_D) .* (abs(lon_D) + lon_M/60 + lon_S/3600);

% ---- ALTITUDE (meters
h = GT{:,10};
% ---- LLA → ECEF (WGS-84)
lla = [lat, lon, h];
ecef = lla2ecef(lla);

X = ecef(:,1);
Y = ecef(:,2);
Z = ecef(:,3);

% Save
GT_ECEF = [t_gt, X, Y, Z];
GT_LLA = [t_gt, lat, lon, h];
save('C:\UrbanNav\DeepUrban\mat\GT_LLA.mat','GT_LLA');
save('C:\UrbanNav\DeepUrban\mat\GT_ECEF.mat','GT_ECEF');

