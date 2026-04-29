%% gnss_error_analysis.m
% GNSS Error Analysis — compares GPX-derived positions against Ground Truth.
%
% Loads:
%   gpx_ecef_gpst.mat  → variables: X, Y, Z, gps_sow, gps_week  (from parse_gpx.m)
%   GT_trim.mat        → GT_trim  [Nx4]: col1=GPS_SOW, col2=X, col3=Y, col4=Z  (ECEF)
%   GT_LLA_trim.mat    → GT_LLA_trim [Nx3+]: col2=lat(deg), col3=lon(deg)
%
% Saves:  error.mat  →  rd table + individual error vectors

%% ── 0. Load data ────────────────────────────────────────────────────────────
gpx_mat = 'C:\UrbanNav\Deep Urban\mat\gpx_ecef_gpst.mat';
gt_mat  = 'C:\UrbanNav\Deep Urban\mat\GT_trim.mat';
lla_mat = 'C:\UrbanNav\Deep Urban\mat\GT_LLA_trim.mat';
out_mat = 'C:\UrbanNav\Deep Urban\mat\error.mat';

% GPX data — individual vectors saved by parse_gpx.m
gpx = load(gpx_mat, 'X', 'Y', 'Z', 'gps_sow', 'gps_week');

% Ground truth
gt  = load(gt_mat,  'GT_trim');      GT_trim     = gt.GT_trim;
lla = load(lla_mat, 'GT_LLA_trim');  GT_LLA_trim = lla.GT_LLA_trim;

%% ── 1. Extract GPX ECEF + time ─────────────────────────────────────────────
Xg   = gpx.X;
Yg   = gpx.Y;
Zg   = gpx.Z;
sow_gpx = gpx.gps_sow;          % GPS second-of-week for each GPX point

%% ── 2. Extract Ground Truth ECEF + time ────────────────────────────────────
% GT_trim columns: [GPS_SOW, X_ecef, Y_ecef, Z_ecef]
t_gt  = GT_trim(:,1);
Xgt   = GT_trim(:,2);
Ygt   = GT_trim(:,3);
Zgt   = GT_trim(:,4);

%% ── 3. Time-align GPX to Ground Truth via GPS SOW ──────────────────────────
% Match each GT epoch to the nearest GPX epoch (tolerance: 0.6 s)
TOL = 0.6;   % seconds — tighten if your data is 1 Hz
n_gt  = length(t_gt);
idx_g = nan(n_gt, 1);   % GPX index matched to each GT row

for i = 1:n_gt
    [d, j] = min(abs(sow_gpx - t_gt(i)));
    if d <= TOL
        idx_g(i) = j;
    end
end

valid = ~isnan(idx_g);          % GT rows that found a GPX match

% Aligned arrays
t_valid = t_gt(valid);
Xgt_v   = Xgt(valid);
Ygt_v   = Ygt(valid);
Zgt_v   = Zgt(valid);

Xg_v  = Xg(idx_g(valid));
Yg_v  = Yg(idx_g(valid));
Zg_v  = Zg(idx_g(valid));

lat_gt = deg2rad(GT_LLA_trim(valid, 2));
lon_gt = deg2rad(GT_LLA_trim(valid, 3));

fprintf('Aligned %d / %d GT epochs to GPX data.\n', sum(valid), n_gt);

%% ── 4. ECEF differences ─────────────────────────────────────────────────────
dX = Xg_v - Xgt_v;
dY = Yg_v - Ygt_v;
dZ = Zg_v - Zgt_v;

%% ── 5. ECEF → ENU rotation for each epoch ──────────────────────────────────
N_epoch = length(dX);
E = zeros(N_epoch, 1);
No = zeros(N_epoch, 1);   % 'No' avoids shadowing built-in 'N'
U = zeros(N_epoch, 1);

for i = 1:N_epoch
    slat = sin(lat_gt(i));  clat = cos(lat_gt(i));
    slon = sin(lon_gt(i));  clon = cos(lon_gt(i));

    R = [-slon,          clon,         0;
         -slat*clon,    -slat*slon,    clat;
          clat*clon,     clat*slon,    slat];

    enu      = R * [dX(i); dY(i); dZ(i)];
    E(i)     = enu(1);
    No(i)    = enu(2);
    U(i)     = enu(3);
end

%% ── 6. Error metrics ────────────────────────────────────────────────────────
horizontal_err  = sqrt(E.^2  + No.^2);
vertical_err    = abs(U);
err_3d          = sqrt(E.^2  + No.^2 + U.^2);
err_3d_ecef     = sqrt(dX.^2 + dY.^2 + dZ.^2);

%% ── 7. Statistics ───────────────────────────────────────────────────────────
fprintf('\n===== GNSS Error Statistics (ENU) =====\n');
fprintf('Mean Horizontal Error : %8.3f m\n', mean(horizontal_err));
fprintf('RMSE Horizontal Error : %8.3f m\n', sqrt(mean(horizontal_err.^2)));
fprintf('Mean Vertical Error   : %8.3f m\n', mean(vertical_err));
fprintf('RMSE Vertical Error   : %8.3f m\n', sqrt(mean(vertical_err.^2)));
fprintf('Mean 3D Error         : %8.3f m\n', mean(err_3d));
fprintf('RMSE 3D Error         : %8.3f m\n', sqrt(mean(err_3d.^2)));
fprintf('Max  3D Error         : %8.3f m\n', max(err_3d));

fprintf('\n===== ECEF 3D Error =====\n');
fprintf('Mean 3D Error (ECEF)  : %8.3f m\n', mean(err_3d_ecef));
fprintf('RMSE 3D Error (ECEF)  : %8.3f m\n', sqrt(mean(err_3d_ecef.^2)));
fprintf('Max  3D Error (ECEF)  : %8.3f m\n', max(err_3d_ecef));

%% ── 8. Build result table & save ────────────────────────────────────────────
rd = table(t_valid, E, No, U, horizontal_err, vertical_err, err_3d, err_3d_ecef, ...
    'VariableNames', {'GPS_SOW','East_m','North_m','Up_m', ...
                      'Horiz_err_m','Vert_err_m','Err3D_ENU_m','Err3D_ECEF_m'});

save(out_mat, 'rd', 'E', 'No', 'U', 'horizontal_err', 'vertical_err', ...
     'err_3d', 'err_3d_ecef', 't_valid');
fprintf('\nSaved results to %s\n', out_mat);

%% ── 9. Plots ─────────────────────────────────────────────────────────────────
figure;
plot(t_valid, horizontal_err, 'LineWidth', 1.3);
grid on; xlabel('GPS SOW (s)'); ylabel('Error (m)');
title('Horizontal Position Error');

figure;
plot(t_valid, vertical_err, 'LineWidth', 1.3);
grid on; xlabel('GPS SOW (s)'); ylabel('Error (m)');
title('Vertical Position Error');

figure;
plot(t_valid, err_3d, 'LineWidth', 1.3);
grid on; xlabel('GPS SOW (s)'); ylabel('Error (m)');
title('3D Position Error (ENU)');

figure;
plot(E, No, '.', 'MarkerSize', 6);
grid on; axis equal;
xlabel('East Error (m)'); ylabel('North Error (m)');
title('Horizontal Error Scatter (ENU)');