% save('/MATLAB Drive/Thesis-data/residual/GNSS_interp.mat', 'GNSS_interp');
% save('/MATLAB Drive/Thesis-data/residual/GT_trim.mat', 'GT_trim');
% save('/MATLAB Drive/Thesis-data/residual/GT_LLA_trim.mat', 'GT_LLA_trim');


load('C:\UrbanNav\DeepUrban\mat\GNSS_interp.mat', 'GNSS_interp');
load('C:\UrbanNav\DeepUrban\mat\GT_trim.mat', 'GT_trim');
load('C:\UrbanNav\DeepUrban\mat\GT_LLA_trim.mat', 'GT_LLA_trim');

%% GNSS Error Analysis (3D, Horizontal, Vertical, ENU)

% Extract coordinates
t_gt = GT_trim(:,1);

Xgt = GT_trim(:,2);
Ygt = GT_trim(:,3);
Zgt = GT_trim(:,4);

Xg = GNSS_interp(:,2);
Yg = GNSS_interp(:,3);
Zg = GNSS_interp(:,4);

% Remove NaNs
valid = ~isnan(Xg);

Xgt = Xgt(valid);
Ygt = Ygt(valid);
Zgt = Zgt(valid);

Xg = Xg(valid);
Yg = Yg(valid);
Zg = Zg(valid);

t_valid = t_gt(valid);

%% Compute ECEF differences
dX = Xg - Xgt;
dY = Yg - Ygt;
dZ = Zg - Zgt;

%% Convert GT reference position to LLA
% Also filter LLA
lat_gt = deg2rad(GT_LLA_trim(valid,2));
lon_gt = deg2rad(GT_LLA_trim(valid,3));


%% Allocate ENU arrays
N_epoch = length(dX);

E = zeros(N_epoch,1);
N = zeros(N_epoch,1);
U = zeros(N_epoch,1);
%% Convert ECEF → ENU for each epoch (moving receiver)

for i = 1:N_epoch

    R = [ -sin(lon_gt(i))             cos(lon_gt(i))              0;
          -sin(lat_gt(i))*cos(lon_gt(i))  -sin(lat_gt(i))*sin(lon_gt(i))   cos(lat_gt(i));
           cos(lat_gt(i))*cos(lon_gt(i))   cos(lat_gt(i))*sin(lon_gt(i))   sin(lat_gt(i))];

    enu = R * [dX(i); dY(i); dZ(i)];

    E(i) = enu(1);
    N(i) = enu(2);
    U(i) = enu(3);

end



%% Error metrics
horizontal_err = sqrt(E.^2 + N.^2);
vertical_err   = abs(U);
err_3d         = sqrt(E.^2 + N.^2 + U.^2);

%% Statistics
fprintf('\n===== GNSS Error Statistics =====\n');

fprintf('Mean Horizontal Error : %.2f m\n', mean(horizontal_err));
fprintf('RMSE Horizontal Error : %.2f m\n', sqrt(mean(horizontal_err.^2)));

fprintf('Mean Vertical Error   : %.2f m\n', mean(vertical_err));
fprintf('RMSE Vertical Error   : %.2f m\n', sqrt(mean(vertical_err.^2)));

fprintf('Mean 3D Error         : %.2f m\n', mean(err_3d));
fprintf('RMSE 3D Error         : %.2f m\n', sqrt(mean(err_3d.^2)));

fprintf('Max 3D Error          : %.2f m\n', max(err_3d));

%% Save results
rd = [t_valid, E, N, U, horizontal_err, vertical_err, err_3d];

save('C:\UrbanNav\DeepUrban\mat\error.mat', 'rd');

%% Plots

% Horizontal error
figure;
plot(t_valid, horizontal_err,'LineWidth',1.3);
grid on;
xlabel('Time (s)');
ylabel('Horizontal Error (m)');
title('Horizontal Position Error');

% Vertical error
figure;
plot(t_valid, vertical_err,'LineWidth',1.3);
grid on;
xlabel('Time (s)');
ylabel('Vertical Error (m)');
title('Vertical Position Error');

% 3D error
figure;
plot(t_valid, err_3d,'LineWidth',1.3);
grid on;
xlabel('Time (s)');
ylabel('3D Error (m)');
title('3D Position Error');

% ENU scatter
figure;
plot(E,N,'.');
grid on;
xlabel('East Error (m)');
ylabel('North Error (m)');
title('ENU Horizontal Error Scatter');
axis equal;

%% 3D Error directly in ECEF
err_3d_ecef = sqrt(dX.^2 + dY.^2 + dZ.^2);
fprintf('\n===== ECEF 3D Error =====\n');
fprintf('Mean 3D Error (ECEF) : %.2f m\n', mean(err_3d_ecef));
fprintf('RMSE 3D Error (ECEF) : %.2f m\n', sqrt(mean(err_3d_ecef.^2)));
fprintf('Max 3D Error (ECEF)  : %.2f m\n', max(err_3d_ecef));