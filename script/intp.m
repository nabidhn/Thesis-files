clc; clear;

POS = load('/MATLAB Drive/Thesis-data/residual/deep urban/hi.pos');
t_gnss = POS(:,2);
Xg = POS(:,3);
Yg = POS(:,4);
Zg = POS(:,5);

load('MATLAB Drive/Thesis-data/residual/GT_ECEF.mat');
t_gt = GT_ECEF(:,1);

gap_threshold = 15;

% normal interpolation
Xg_i = interp1(t_gnss, Xg, t_gt, 'linear', NaN);
Yg_i = interp1(t_gnss, Yg, t_gt, 'linear', NaN);
Zg_i = interp1(t_gnss, Zg, t_gt, 'linear', NaN);
% 
% remove interpolations across large gaps
dt = diff(t_gnss);

for i = 1:length(dt)
    if dt(i) > gap_threshold
        mask = t_gt > t_gnss(i) & t_gt < t_gnss(i+1);
        Xg_i(mask) = NaN;
        Yg_i(mask) = NaN;
        Zg_i(mask) = NaN;
    end
end

GNSS_interp = [t_gt, Xg_i, Yg_i, Zg_i];

save('/MATLAB Drive/Thesis-data/residual/GNSS_interp.mat','GNSS_interp');

disp('Interpolation done with gap threshold');