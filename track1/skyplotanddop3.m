clc; clear;

%% ------------------------ INPUT --------------------------------------------
statFile = "C:\KLTdataset\data\GNSS\20210610\gt1.pos.stat"; 

fid = fopen(statFile,'r');
lines = textscan(fid,'%s','Delimiter','\n');
fclose(fid);
lines = lines{1};

%% ------------------------ PARSE $SAT ---------------------------------------
epochData = struct();
week = []; sow = []; prn = {}; az = []; el = [];

for i = 1:length(lines)
    line = strtrim(lines{i});
    if startsWith(line,'$SAT')
        parts = strsplit(line,',');
        w = str2double(parts{2});
        s = str2double(parts{3});
        a = str2double(parts{6});
        e = str2double(parts{7});
        p = parts{4};

        % store for matrix computations
        week(end+1,1) = w;
        sow(end+1,1)  = s;
        prn{end+1,1}  = p;
        az(end+1,1)   = a;
        el(end+1,1)   = e;

        % store per-epoch for skyplot
        epochKey = sprintf('e%d_%d', w, round(s*1000));
        if ~isfield(epochData,epochKey)
            epochData.(epochKey).az = [];
            epochData.(epochKey).el = [];
            epochData.(epochKey).prn = {};
            epochData.(epochKey).gpst = s;
        end
        epochData.(epochKey).az(end+1) = a;
        epochData.(epochKey).el(end+1) = e;
        epochData.(epochKey).prn{end+1} = p;
    end
end

%% ------------------------ DOP COMPUTATION -----------------------------------
epochKeys = fieldnames(epochData);
nEpochs = length(epochKeys);

GDOPs = zeros(nEpochs,1);
PDOPs = zeros(nEpochs,1);
HDOPs = zeros(nEpochs,1);
VDOPs = zeros(nEpochs,1);
TDOPs = zeros(nEpochs,1);
GPST  = zeros(nEpochs,1);   
NumSatellites = zeros(nEpochs,1);   

for k = 1:nEpochs
    data = epochData.(epochKeys{k});
    GPST(k) = data.gpst;   
    NumSatellites(k) = length(unique(data.prn));  

    nSat = length(data.az);
    if nSat < 4
        GDOPs(k)=NaN; PDOPs(k)=NaN; HDOPs(k)=NaN;
        VDOPs(k)=NaN; TDOPs(k)=NaN;
        continue;
    end

    elRad = deg2rad(data.el);
    azRad = deg2rad(data.az);

    uEast  = cos(elRad).*sin(azRad);
    uNorth = cos(elRad).*cos(azRad);
    uUp    = sin(elRad);

    G = [-uEast' -uNorth' -uUp' ones(nSat,1)];
    Q = inv(G'*G);

    GDOPs(k) = sqrt(trace(Q));
    PDOPs(k) = sqrt(Q(1,1)+Q(2,2)+Q(3,3));
    HDOPs(k) = sqrt(Q(1,1)+Q(2,2));
    VDOPs(k) = sqrt(Q(3,3));
    TDOPs(k) = sqrt(Q(4,4));
end

%% ------------------------ CREATE TABLE --------------------------------------
EpochIndex = (1:nEpochs)';
T = table(EpochIndex, GPST, NumSatellites, GDOPs, PDOPs, HDOPs, VDOPs, TDOPs, ...
    'VariableNames',{'EpochIndex','GPST_sec','NumSatellites','GDOP','PDOP','HDOP','VDOP','TDOP'});
disp(T);

%% ------------------------ RUNNING AVERAGE PLOT ------------------------------
avgPDOP = cumsum(PDOPs) ./ (1:nEpochs)';
avgHDOP = cumsum(HDOPs) ./ (1:nEpochs)';
avgVDOP = cumsum(VDOPs) ./ (1:nEpochs)';
avgGDOP = cumsum(GDOPs) ./ (1:nEpochs)';

figure;
plot(EpochIndex, avgPDOP,'-o','LineWidth',1.5); hold on;
plot(EpochIndex, avgHDOP,'-x','LineWidth',1.5);
plot(EpochIndex, avgVDOP,'-s','LineWidth',1.5);
plot(EpochIndex, avgGDOP,'-k','LineWidth',1.5);
xlabel('Epoch Index');
ylabel('Average DOP');
legend('Avg PDOP','Avg HDOP','Avg VDOP','Avg GDOP');
grid on;
title('Running Average DOP');

%% ------------------------ MEAN SATELLITE SKY PLOT ---------------------------
% Build matrices as in your original logic
[unique_epochs,~,idx_epoch] = unique([week sow],'rows');
unique_sats = unique(prn);
n_epochs = size(unique_epochs,1);
n_sats = length(unique_sats);

az_matrix = NaN(n_epochs,n_sats);
el_matrix = NaN(n_epochs,n_sats);

for i=1:length(prn)
    e = idx_epoch(i);
    s = find(strcmp(unique_sats,prn{i}));
    az_matrix(e,s)=az(i);
    el_matrix(e,s)=el(i);
end

% Mean az/el per satellite
mean_az_sat = nanmean(az_matrix,1);
mean_el_sat = nanmean(el_matrix,1);

%% ------------------------ MEAN SATELLITE SKY PLOT (MATLAB skyplot) ---------------------------
% Use SkyPlotChart for mean satellite positions
mean_az_sat = nanmean(az_matrix,1);
mean_el_sat = nanmean(el_matrix,1);

figure
hMean = skyplot(mean_az_sat, mean_el_sat, unique_sats);
title('Mean Satellite Sky Plot');


% Satellite geometry table (fixed)
satellite_stats = table( ...
    unique_sats(:), ...
    mean_az_sat(:), ...
    mean_el_sat(:), ...
    'VariableNames', {'Satellite_ID','Mean_Azimuth_deg','Mean_Elevation_deg'});
disp('Satellite Mean Geometry:')
disp(satellite_stats)

function plotSkyplotEpoch(epochData, epochKeys, idx)
    data = epochData.(epochKeys{idx});
    if isempty(data.az)
        warning('No satellites for this epoch');
        return
    end
    figure
    hEpoch = skyplot(data.az, data.el, string(data.prn));
    title(sprintf('Skyplot - Epoch %d (GPST %.2f s)', idx, data.gpst));
end