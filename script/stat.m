%% RTKLIB .pos.stat Satellite & User Position Extractor with Time Conversion
clear; clc;

% Configuration
filename = 'C:\UrbanNav\DeepUrban\novatel.pos.stat'; 
outputFile = 'C:\UrbanNav\DeepUrban\mat\satellite_and_position.mat';

% GPS Start Epoch (Jan 6, 1980)
gpsEpoch = datetime(1980, 1, 6, 'TimeZone', 'UTC');

% Open the file
fid = fopen(filename, 'r');
if fid == -1
    error('Cannot open file: %s', filename);
end

% Buffers
satBuffer = {};
posBuffer = {};

while ~feof(fid)
    line = fgetl(fid);
    
    % --- Satellite Data ---
    if startsWith(line, '$SAT')
        parts = strsplit(line, ',');
        try
            week   = str2double(parts{2});
            tow    = str2double(parts{3});
            satID  = parts{4};
            az     = str2double(parts{6});
            el     = str2double(parts{7});
            resid  = str2double(parts{8});
            snr    = str2double(parts{11});
            
            % Time conversion
            fullDate = gpsEpoch + days(week*7) + seconds(tow);
            dateStr  = datestr(fullDate, 'yyyy-mm-dd');
            timeStr  = datestr(fullDate, 'HH:MM:SS');
            doy      = day(fullDate, 'dayofyear');
            
            % Append satellite data
            satBuffer = [satBuffer; {week, tow, dateStr, timeStr, doy, satID, az, el, resid, snr}];
        catch
            continue;
        end
        
    % --- User Position Data ---
    elseif startsWith(line, '$POS')
        parts = strsplit(line, ',');
        try
            week   = str2double(parts{2});
            tow    = str2double(parts{3});
            x      = str2double(parts{5});
            y      = str2double(parts{6});
            z      = str2double(parts{7});
            
            % Time conversion
            fullDate = gpsEpoch + days(week*7) + seconds(tow);
            dateStr  = datestr(fullDate, 'yyyy-mm-dd');
            timeStr  = datestr(fullDate, 'HH:MM:SS');
            doy      = day(fullDate, 'dayofyear');
            
            % Append user position
            posBuffer = [posBuffer; {week, tow, dateStr, timeStr, doy, x, y, z}];
        catch
            continue;
        end
    end
end

fclose(fid);

% Create tables
satVarNames = {'Week', 'GPST_TOW', 'Date', 'Time_HMS', 'DayOfYear', 'SatID', 'Azimuth', 'Elevation', 'StatRes', 'SNR'};
posVarNames = {'Week', 'GPST_TOW', 'Date', 'Time_HMS', 'DayOfYear', 'X_ECEF', 'Y_ECEF', 'Z_ECEF'};

satTable = cell2table(satBuffer, 'VariableNames', satVarNames);
posTable = cell2table(posBuffer, 'VariableNames', posVarNames);

% Save both tables
save(outputFile, 'satTable', 'posTable');

fprintf('Successfully extracted %d satellite observations and %d user positions.\n', ...
        height(satTable), height(posTable));

% Preview
head(satTable)
head(posTable)