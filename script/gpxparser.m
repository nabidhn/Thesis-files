%% parse_gpx.m
% Reads a GPX file, extracts lat/lon/altitude, converts to ECEF (WGS-84),
% extracts timestamps and converts to GPS Week + GPS Second of Week (GPST).
% Saves all results to a .mat file.
%
% Output .mat variables:
%   lat        [Nx1] Geodetic latitude  (degrees)
%   lon        [Nx1] Geodetic longitude (degrees)
%   alt        [Nx1] Ellipsoidal height / altitude (metres)
%   X, Y, Z    [Nx1] ECEF coordinates (metres)
%   gps_week   [Nx1] GPS week number
%   gps_sow    [Nx1] GPS second of week (seconds)
%   utc_time   [Nx1] MATLAB datetime array (UTC)
%   T          MATLAB table with all variables

%% ── 0. Configuration ────────────────────────────────────────────────────────
mat_file = 'C:\UrbanNav\Deep Urban\mat\gpx_ecef_gpst.mat';   % output .mat filename

% Auto file picker: opens a dialog if the file is not found
gpx_file = 'C:\UrbanNav\Deep Urban\UrbanNav-HK-Deep-Urban-1.xiaomi.mi8.gpx';
if ~isfile(gpx_file)
    [fn, fp] = uigetfile({'*.gpx;*.txt', 'GPX files (*.gpx, *.txt)'; ...
                           '*.*',         'All files (*.*)'}, ...
                          'Select your GPX file');
    if isequal(fn, 0)
        error('No file selected. Please provide a valid GPX file.');
    end
    gpx_file = fullfile(fp, fn);
end
fprintf('Reading: %s\n', gpx_file);

%% ── 1. Parse GPX (XML) ──────────────────────────────────────────────────────
doc  = xmlread(gpx_file);
tpts = doc.getElementsByTagName('trkpt');
N    = tpts.getLength;

lat      = zeros(N, 1);
lon      = zeros(N, 1);
alt      = zeros(N, 1);
utc_time = NaT(N, 1, 'TimeZone', 'UTC');

for k = 0 : N-1
    node     = tpts.item(k);
    lat(k+1) = str2double(node.getAttribute('lat'));
    lon(k+1) = str2double(node.getAttribute('lon'));

    % elevation
    ele_nodes = node.getElementsByTagName('ele');
    if ele_nodes.getLength > 0
        alt(k+1) = str2double(ele_nodes.item(0).getFirstChild.getData);
    end

    % time  (ISO 8601: "2021-05-21T06:28:44.000Z")
    t_nodes = node.getElementsByTagName('time');
    if t_nodes.getLength > 0
        t_str = char(t_nodes.item(0).getFirstChild.getData);
        t_str = strrep(t_str, 'Z', '+00:00');
        utc_time(k+1) = datetime(t_str, 'InputFormat', ...
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXX", 'TimeZone', 'UTC');
    end
end

fprintf('Parsed %d track points from %s\n', N, gpx_file);

%% ── 2. Geodetic -> ECEF using MATLAB built-in lla2ecef ─────────────────────
% lla2ecef expects [lat, lon, alt] in degrees/degrees/metres (WGS-84)
% and returns [X, Y, Z] in metres.
ecef = lla2ecef([lat, lon, alt]);   % [Nx3]
X = ecef(:,1);
Y = ecef(:,2);
Z = ecef(:,3);

%% ── 3. UTC -> GPS Time (week + second of week) ──────────────────────────────
% Timestamps in the GPX file are UTC. Convert to GPS time by adding the
% leap-second offset (18 seconds, valid from 2017-01-01 onward).
GPS_EPOCH    = datetime(1980, 1, 6, 0, 0, 0, 'TimeZone', 'UTC');
LEAP_SECONDS = 18;   % GPS is ahead of UTC by 18 s as of 2017-01-01

gps_time_sec = seconds(utc_time - GPS_EPOCH) + LEAP_SECONDS;

gps_week = floor(gps_time_sec / 604800);   % 604800 s per week
gps_sow  = gps_time_sec - gps_week * 604800;

%% ── 4. Build MATLAB Table ───────────────────────────────────────────────────
T = table(gps_week, gps_sow, lat, lon, alt, X, Y, Z, ...
    'VariableNames', {'GPS_Week','GPS_SOW_s','Lat_deg','Lon_deg', ...
                      'Alt_m','X_m','Y_m','Z_m'});

disp(T);

%% ── 5. Save to .mat ─────────────────────────────────────────────────────────
save(mat_file, 'lat', 'lon', 'alt', 'X', 'Y', 'Z', ...
               'gps_week', 'gps_sow', 'utc_time', 'T');
fprintf('Saved to %s\n', mat_file);

%% ── 6. Quick sanity-check printout ─────────────────────────────────────────
fprintf('\n%-5s  %-14s %-14s %-8s  %-16s %-16s %-16s  %-6s  %-12s\n', ...
        'Idx','Lat(deg)','Lon(deg)','Alt(m)','X(m)','Y(m)','Z(m)', ...
        'GPSWeek','GPSSOW(s)');
for k = 1:N
    fprintf('%-5d  %-14.8f %-14.8f %-8.2f  %-16.3f %-16.3f %-16.3f  %-6d  %-12.3f\n', ...
        k, lat(k), lon(k), alt(k), X(k), Y(k), Z(k), ...
        gps_week(k), gps_sow(k));
end

%% 🔹 Combine results
GNSS_interp = [gps_sow, X, Y, Z];

%% 🔹 Save files
save('C:\UrbanNav\Deep Urban\mat\GNSS_interp.mat', 'GNSS_interp');