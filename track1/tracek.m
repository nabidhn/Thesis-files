% %% Parse RTKLIB trace file and extract satellite information
% 
% clear; clc;
% 
% filename = '/MATLAB Drive/Thesis-data/pos/hi1spp.pos.trace';
% 
% fid = fopen(filename,'r');
% 
% % Storage variables
% satID   = {};
% satNumber = [];
% 
% recvTime_str = {};
% txTime_str   = {};
% 
% gpst_week = [];
% gpst_sec  = [];
% 
% satPosX = [];
% satPosY = [];
% satPosZ = [];
% 
% while ~feof(fid)
% 
%     line = fgetl(fid);
% 
%     %% -------- TYPE 1: Epoch line ----------
%     if contains(line,'rtkpos') && contains(line,'time=')
% 
%         tokens = regexp(line,'time=(\d+/\d+/\d+\s+\d+:\d+:\d+\.\d+)','tokens');
% 
%         if ~isempty(tokens)
% 
%             epochTime = tokens{1}{1};
% 
%             t = datetime(epochTime,'InputFormat','yyyy/MM/dd HH:mm:ss.SSS');
% 
%             % GPS epoch
%             gps_epoch = datetime(1980,1,6,0,0,0);
% 
%             dt = seconds(t - gps_epoch);
% 
%             currentWeek = floor(dt/(7*86400));
%             currentSOW  = round(dt - currentWeek*7*86400);
%         end
%     end
% 
% 
%     %% -------- TYPE 2: Observation line ----------
%     if startsWith(strtrim(line),'(')
% 
%         tokens = regexp(line,...
%         '\)\s+(\d+/\d+/\d+\s+\d+:\d+:\d+\.\d+)\s+([A-Z]\d+)',...
%         'tokens');
% 
%         if ~isempty(tokens)
% 
%             recvTimeStr = tokens{1}{1};
%             sat = tokens{1}{2};
% 
%             satID{end+1,1} = sat;
% 
%             % store receive time
%             t_recv = datetime(recvTimeStr,'InputFormat','yyyy/MM/dd HH:mm:ss.SSS');
%             recvTime_str{end+1,1} = datestr(t_recv,'HH:MM:SS.FFF');
% 
%             % GPST info
%             gpst_week(end+1,1) = currentWeek;
%             gpst_sec(end+1,1)  = currentSOW;
%         end
%     end
% 
% 
%     %% -------- TYPE 3: Satellite position + transmit time ----------
%     if contains(line,'sat=') && contains(line,'rs=')
% 
%         tokens = regexp(line,...
%         '\d+/\d+/\d+\s+(\d+:\d+:\d+\.\d+)\s+sat=\s*(\d+)\s+rs=\s*([-\d\.]+)\s+([-\d\.]+)\s+([-\d\.]+)',...
%         'tokens');
% 
%         if ~isempty(tokens)
% 
%             txTime = tokens{1}{1};
%             satNum = str2double(tokens{1}{2});
%             x = str2double(tokens{1}{3});
%             y = str2double(tokens{1}{4});
%             z = str2double(tokens{1}{5});
% 
%             txTime_str{end+1,1} = txTime;
%             satNumber(end+1,1) = satNum;
% 
%             satPosX(end+1,1) = x;
%             satPosY(end+1,1) = y;
%             satPosZ(end+1,1) = z;
%         end
%     end
% 
% end
% 
% fclose(fid);
% 
% 
% %% Align lengths
% N = min([length(satID), length(satNumber)]);
% 
% satID = satID(1:N);
% satNumber = satNumber(1:N);
% recvTime_str = recvTime_str(1:N);
% txTime_str   = txTime_str(1:N);
% 
% gpst_week = gpst_week(1:N);
% gpst_sec  = gpst_sec(1:N);
% 
% satPosX = satPosX(1:N);
% satPosY = satPosY(1:N);
% satPosZ = satPosZ(1:N);
% 
% 
% %% Create MATLAB table
% 
% satelliteTable = table(...
%     satNumber,...
%     satID,...
%     recvTime_str,...
%     txTime_str,...
%     gpst_week,...
%     gpst_sec,...
%     satPosX,...
%     satPosY,...
%     satPosZ);
% 
% 
% disp(satelliteTable)
% 
% 
% %% Save MAT file
% 
% save('/MATLAB Drive/Thesis-data/residual/satellite_data.mat','satelliteTable');
% 
% disp('Data extraction complete. Table saved to satellite_data.mat');


%% =========================================================
%  GNSS TRACE PARSER + AZ/EL EXTRACTION (MERGED PIPELINE)
%% =========================================================

clear; clc;

%% =========================
% INPUT FILES
%% =========================
traceFile = 'C:\KLTdataset\data\GNSS\20210610\gt1.pos.trace';

fid = fopen(traceFile,'r');

%% =========================
% STORAGE VARIABLES
%% =========================
satID       = {};
satNumber   = [];

recvTime_str = {};
txTime_str   = {};

gpst_week = [];
gpst_sec  = [];

satPosX = [];
satPosY = [];
satPosZ = [];

Azimuth   = [];
Elevation = [];

%% =========================
% TEMP VARIABLES
%% =========================
currentWeek = NaN;
currentSOW  = NaN;

disp('Starting parsing RTKLIB trace file...');

%% =========================
% MAIN LOOP
%% =========================
while ~feof(fid)

    line = fgetl(fid);

    %% -------- TYPE 1: Epoch line ----------
    if contains(line,'rtkpos') && contains(line,'time=')

        tokens = regexp(line,'time=(\d+/\d+/\d+\s+\d+:\d+:\d+\.\d+)','tokens');

        if ~isempty(tokens)
            epochTime = tokens{1}{1};

            t = datetime(epochTime,'InputFormat','yyyy/MM/dd HH:mm:ss.SSS');
            gps_epoch = datetime(1980,1,6,0,0,0);

            dt = seconds(t - gps_epoch);

            currentWeek = floor(dt/(7*86400));
            currentSOW  = round(dt - currentWeek*7*86400);
        end
    end

    %% -------- TYPE 2: Observation line ----------
    if startsWith(strtrim(line),'(')

        tokens = regexp(line,...
        '\)\s+(\d+/\d+/\d+\s+\d+:\d+:\d+\.\d+)\s+([A-Z]\d+)',...
        'tokens');

        if ~isempty(tokens)

            recvTimeStr = tokens{1}{1};
            sat = tokens{1}{2};

            satID{end+1,1} = sat;

            t_recv = datetime(recvTimeStr,'InputFormat','yyyy/MM/dd HH:mm:ss.SSS');
            recvTime_str{end+1,1} = datestr(t_recv,'HH:MM:SS.FFF');

            gpst_week(end+1,1) = currentWeek;
            gpst_sec(end+1,1)  = currentSOW;
        end
    end

    %% -------- TYPE 3: Satellite position ----------
    if contains(line,'sat=') && contains(line,'rs=')

        tokens = regexp(line,...
        '\d+/\d+/\d+\s+(\d+:\d+:\d+\.\d+)\s+sat=\s*(\d+)\s+rs=\s*([-\d\.]+)\s+([-\d\.]+)\s+([-\d\.]+)',...
        'tokens');

        if ~isempty(tokens)

            txTime = tokens{1}{1};
            satNum = str2double(tokens{1}{2});

            x = str2double(tokens{1}{3});
            y = str2double(tokens{1}{4});
            z = str2double(tokens{1}{5});

            txTime_str{end+1,1} = txTime;
            satNumber(end+1,1) = satNum;

            satPosX(end+1,1) = x;
            satPosY(end+1,1) = y;
            satPosZ(end+1,1) = z;
        end
    end

    %% -------- TYPE 4: Azimuth & Elevation ----------
    if contains(line,'ionocorr:') && contains(line,'azel=')

        tokens = regexp(line, ...
        'sat=\s*(\d+).*azel=([\d\.-]+)\s+([\d\.-]+)', ...
        'tokens');

        if ~isempty(tokens)

            traceSat = str2double(tokens{1}{1});
            traceAz  = str2double(tokens{1}{2});
            traceEl  = str2double(tokens{1}{3});

            satNumber(end+1,1) = traceSat;   % align indexing style
            Azimuth(end+1,1)   = traceAz;
            Elevation(end+1,1) = traceEl;
        end
    end

end

fclose(fid);

%% =========================
% ALIGN LENGTHS SAFELY
%% =========================
N = min([length(satID), length(satNumber), length(gpst_week)]);

SatID         = satID(1:N);
satNumber     = satNumber(1:N);
recvTime_str  = recvTime_str(1:N);
txTime_str    = txTime_str(1:N);

gpst_week = gpst_week(1:N);
gpst_sec  = gpst_sec(1:N);

satPosX = satPosX(1:N);
satPosY = satPosY(1:N);
satPosZ = satPosZ(1:N);

Azimuth   = Azimuth(1:N);
Elevation = Elevation(1:N);

%% =========================
% CREATE TABLE
%% =========================
satelliteTable = table(...
    satNumber,...
    satID,...
    recvTime_str,...
    txTime_str,...
    gpst_week,...
    gpst_sec,...
    satPosX,...
    satPosY,...
    satPosZ,...
    Azimuth,...
    Elevation);

disp(satelliteTable)

%% =========================
% SAVE OUTPUT
%% =========================
save('C:\KLTdataset\data\GNSS\20210610\track1\satellite_data.mat','satelliteTable');

disp('DONE ✔ Combined extraction complete.');


