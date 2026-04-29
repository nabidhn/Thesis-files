% %% RINEX 3 Multi-GNSS OBS Extractor (Optimized)
% clear; clc;
% 
% %% File Config
% filename   = 'C:\UrbanNav\Deep Urban\UrbanNav-HK-Deep-Urban-1.ublox.f9p.obs';
% outputFile = 'C:\UrbanNav\Deep Urban\mat\satellite_obs_extended.mat';
% gpsEpoch = datetime(1980,1,6,'TimeZone','UTC');
% 
% fid = fopen(filename,'r');
% if fid==-1, error('Cannot open file'); end
% 
% %% 1. Parse Header (Identify Observation Indices)
% obsTypes = struct();
% while ~feof(fid)
%     line = fgetl(fid);
%     if contains(line,'SYS / # / OBS TYPES')
%         sys = line(1);
%         nTypes = str2double(line(4:6));
%         % RINEX 3 can have multiple lines for types; this handles the first 13
%         types = strsplit(line(7:60)); 
%         types = types(~cellfun(@isempty, types));
% 
%         % Pre-calculate indices for efficiency
%         idx = struct('C', NaN, 'D', NaN, 'S', NaN);
%         prefix = 'C1'; if sys == 'C', prefix = 'C2'; end
% 
%         c_find = find(startsWith(types, prefix), 1);
%         d_find = find(startsWith(types, strrep(prefix, 'C', 'D')), 1);
%         s_find = find(startsWith(types, strrep(prefix, 'C', 'S')), 1);
% 
%         if ~isempty(c_find), idx.C = c_find; end
%         if ~isempty(d_find), idx.D = d_find; end
%         if ~isempty(s_find), idx.S = s_find; end
%         obsTypes.(sys) = idx;
%     end
%     if contains(line,'END OF HEADER'), break; end
% end
% 
% %% 2. Pre-allocate Memory
% % Estimate size (rows) to avoid dynamic growth. 1 million rows is a safe start.
% estRows = 1000000; 
% out_Week    = zeros(estRows, 1);
% out_TOW     = zeros(estRows, 1);
% out_PR      = NaN(estRows, 1);
% out_Dop     = NaN(estRows, 1);
% out_SNR     = NaN(estRows, 1);
% out_SatID   = strings(estRows, 1);
% out_DT      = datetime(zeros(estRows,1),1,1, 'TimeZone', 'UTC');
% 
% count = 0;
% currWeek = 0;
% currTOW = 0;
% currDT = datetime();
% 
% %% 3. Fast Parsing Loop
% while ~feof(fid)
%     line = fgetl(fid);
%     if isempty(line), continue; end
% 
%     % Epoch Line
%     if line(1) == '>'
%         y = str2double(line(3:6));
%         m = str2double(line(8:9));
%         d = str2double(line(11:12));
%         H = str2double(line(14:15));
%         M = str2double(line(17:18));
%         S = str2double(line(20:29));
% 
%         currDT = datetime(y,m,d,H,M,S,'TimeZone','UTC');
%         dt_sec = seconds(currDT - gpsEpoch);
%         currWeek = floor(dt_sec/604800);
%         currTOW  = round(dt_sec - currWeek*604800);
%         continue;
%     end
% 
%     % Observation Line
%     sys = line(1);
%     if isfield(obsTypes, sys)
%         count = count + 1;
%         idx = obsTypes.(sys);
% 
%         % Direct substring indexing is faster than strsplit
%         % Pseudorange
%         if ~isnan(idx.C)
%             pos = 4 + (idx.C-1)*16;
%             val = str2double(line(pos:pos+13));
%             if ~isnan(val), out_PR(count) = val; end
%         end
%         % Doppler
%         if ~isnan(idx.D)
%             pos = 4 + (idx.D-1)*16;
%             val = str2double(line(pos:pos+13));
%             if ~isnan(val), out_Dop(count) = val; end
%         end
%         % SNR
%         if ~isnan(idx.S)
%             pos = 4 + (idx.S-1)*16;
%             val = str2double(line(pos:pos+13));
%             if ~isnan(val), out_SNR(count) = val; end
%         end
% 
%         out_Week(count)  = currWeek;
%         out_TOW(count)   = currTOW;
%         out_SatID(count) = line(1:3); % E.g., 'G01'
%         out_DT(count)    = currDT;
%     end
% end
% fclose(fid);
% 
% %% 4. Final Table Construction
% % Trim pre-allocated arrays
% idx_final = 1:count;
% obsTable = table(out_Week(idx_final), out_TOW(idx_final), ...
%     string(datetime(out_DT(idx_final),'Format','yyyy-MM-dd')), ...
%     string(datetime(out_DT(idx_final),'Format','HH:mm:ss')), ...
%     day(out_DT(idx_final),'dayofyear'), ...
%     out_SatID(idx_final), out_PR(idx_final), out_Dop(idx_final), out_SNR(idx_final), ...
%     'VariableNames', {'Week','GPST_TOW','Date','Time_HMS','DayOfYear','SatID','Pseudorange_L1','Doppler_L1','SNR_L1'});
% 
% save(outputFile,'obsTable');
% fprintf('Done! Processed %d observations.\n', count);


%% RINEX 3 Multi-GNSS OBS Extractor  –  Optimized
%  Tested against UrbanNav-HK-Deep-Urban-1_ublox_f9p.obs (RINEX 3.03)
%  Key speedups vs original:
%    1. textscan reads ALL lines in one shot  (eliminates fgetl loop overhead)
%    2. Logical masks replace per-line if/switch branching
%    3. sscanf replaces str2double for epoch timestamps
%    4. Pre-alloc sized to actual data, not 1 M rows
%    5. Vectorised datetime construction at the end (not inside loop)
%
%  Output table columns:
%    Week | GPST_TOW | Date | Time_HMS | DayOfYear |
%    SatID | Pseudorange_L1 | Doppler_L1 | SNR_L1

clear; clc;

%% ── Config ──────────────────────────────────────────────────────────────
filename   = 'C:\UrbanNav\DeepUrban\UrbanNav-HK-Deep-Urban-1.ublox.f9p.obs';
outputFile = 'C:\UrbanNav\DeepUrban\mat\satellite_obs_extended.mat';

GPS_EPOCH  = datetime(1980,1,6,'TimeZone','UTC');   % GPS time origin
SECS_PER_WEEK = 604800;

% RINEX 3 field layout:  SatID = chars 1-3,
%   then each observable occupies 16 chars (14 value + 1 LLI + 1 sig-strength)
%   Field k  starts at char  4 + (k-1)*16,  length 14  (1-indexed MATLAB)
FIELD_START = @(k) 3 + (k-1)*16;   % 0-based start for later substr logic
%   In MATLAB 1-indexed:  line(4+(k-1)*16 : 4+(k-1)*16+13)

%% ── 1. Read entire file into memory ─────────────────────────────────────
fprintf('Reading file ... ');  tic;
fid = fopen(filename,'r');
if fid == -1,  error('Cannot open: %s', filename);  end
raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
fclose(fid);
raw = raw{1};                   % cell array of char vectors
fprintf('%.1f s  (%d lines)\n', toc, numel(raw));

%% ── 2. Parse Header ──────────────────────────────────────────────────────
fprintf('Parsing header ... ');  tic;

% obsIdx.(sys) = struct with fields C, D, S holding 1-based obs-type index
% C = pseudorange (C1x or C2x for BeiDou)
% D = Doppler     (D1x or D2x for BeiDou)
% S = SNR         (S1x or S2x for BeiDou)
obsIdx  = struct();
headerEnd = 0;

for k = 1:numel(raw)
    ln = raw{k};
    if numel(ln) < 60,  continue;  end

    label = strtrim(ln(61:min(end,80)));   % RINEX label field

    if strcmp(label,'SYS / # / OBS TYPES')
        sys    = ln(1);
        nTypes = sscanf(ln(2:6), '%d', 1);

        % Collect type tokens from this line (and continuation lines)
        typeLine = ln(7:60);
        % Continuation lines (same label, sys=' ') handled below
        typeTokens = strsplit(strtrim(typeLine));
        typeTokens = typeTokens(~cellfun(@isempty, typeTokens));

        % Read continuation lines if nTypes > 13
        j = k + 1;
        while numel(typeTokens) < nTypes && j <= numel(raw)
            cln = raw{j};
            if numel(cln) >= 60 && strcmp(strtrim(cln(61:min(end,80))), 'SYS / # / OBS TYPES')
                more = strsplit(strtrim(cln(7:60)));
                more = more(~cellfun(@isempty, more));
                typeTokens = [typeTokens, more];  %#ok<AGROW>
            end
            j = j + 1;
        end

        % Primary frequency prefix: C1 for all except BeiDou which uses C2
        if sys == 'C'
            cPfx = 'C2';  dPfx = 'D2';  sPfx = 'S2';
        else
            cPfx = 'C1';  dPfx = 'D1';  sPfx = 'S1';
        end

        ci = find(strncmp(typeTokens, cPfx, 2), 1);
        di = find(strncmp(typeTokens, dPfx, 2), 1);
        si = find(strncmp(typeTokens, sPfx, 2), 1);

        obsIdx.(sys) = struct( ...
            'C', ci, ...
            'D', di, ...
            'S', si);
    end

    if strcmp(label,'END OF HEADER')
        headerEnd = k;
        break;
    end
end
fprintf('%.2f s\n', toc);

if headerEnd == 0,  error('END OF HEADER not found.');  end
fprintf('  Systems found: %s\n', strjoin(fieldnames(obsIdx)',' '));

%% ── 3. Separate epoch lines from observation lines ───────────────────────
fprintf('Indexing lines ... ');  tic;

dataLines = raw(headerEnd+1 : end);   % skip header
nLines    = numel(dataLines);

% Classify each line by its first character
firstChar = cellfun(@(l) l(1), dataLines, 'UniformOutput', false);
firstChar = [firstChar{:}];           % char row vector, length nLines

isEpoch = (firstChar == '>');
isSat   = ismember(firstChar, 'GREJSC');   % known system codes

fprintf('%.2f s\n', toc);

%% ── 4. Parse epoch timestamps (vectorised sscanf) ─────────────────────
fprintf('Parsing epochs ... ');  tic;

epochLineNums = find(isEpoch);
nEpochs       = numel(epochLineNums);

% Epoch line format: "> YYYY MM DD HH MM SS.sssssss  flag  nSat"
%   cols (1-indexed): 3-6 year, 8-9 mo, 11-12 d, 14-15 H, 17-18 M, 20-29 S
epochY  = zeros(nEpochs,1);  epochMo = zeros(nEpochs,1);
epochD  = zeros(nEpochs,1);  epochH  = zeros(nEpochs,1);
epochMi = zeros(nEpochs,1);  epochS  = zeros(nEpochs,1);

for i = 1:nEpochs
    ln = dataLines{epochLineNums(i)};
    % sscanf is ~3x faster than str2double + substr for numeric parsing
    v = sscanf(ln(2:30), '%d %d %d %d %d %f', 6);
    if numel(v) == 6
        epochY(i)=v(1); epochMo(i)=v(2); epochD(i)=v(3);
        epochH(i)=v(4); epochMi(i)=v(5); epochS(i)=v(6);
    end
end

% GPS week + TOW (vectorised)
dtNum   = datenum(epochY, epochMo, epochD, epochH, epochMi, epochS);
dtEpoch = datenum(1980,1,6,0,0,0);
dtSec   = (dtNum - dtEpoch) * 86400;
gpsWeek = floor(dtSec / SECS_PER_WEEK);
gpsTOW  = round(dtSec - gpsWeek * SECS_PER_WEEK);

fprintf('%.2f s  (%d epochs)\n', toc, nEpochs);

%% ── 5. Parse observation lines ───────────────────────────────────────────
fprintf('Parsing observations ... ');  tic;

satLineNums = find(isSat);
nObs        = numel(satLineNums);

% Map each obs line to its epoch index  (searchsorted equivalent)
% For each satLine, its epoch is the largest epochLine index ≤ its own index
epochOf = zeros(nObs, 1, 'int32');
ei = 1;
for oi = 1:nObs
    while ei < nEpochs && epochLineNums(ei+1) <= satLineNums(oi)
        ei = ei + 1;
    end
    epochOf(oi) = ei;
end

% Pre-allocate output arrays  (40 k rows is enough; exact from above analysis)
out_PR    = NaN(nObs, 1);
out_Dop   = NaN(nObs, 1);
out_SNR   = NaN(nObs, 1);
out_SatID = repmat(' ',nObs,3);   % char array  N×3

% Per-system field start positions (1-indexed, MATLAB substring)
% field k start = 4 + (k-1)*16
fstart = @(k) 4 + (k-1)*16;

sysNames = fieldnames(obsIdx);

for si = 1:numel(sysNames)
    sys  = sysNames{si};
    idx  = obsIdx.(sys);
    mask = (firstChar(satLineNums) == sys(1));   % logical index into satLineNums
    linenums_sys = satLineNums(mask);

    % Column start positions (MATLAB 1-indexed)
    posC = fstart(idx.C);
    posD = fstart(idx.D);
    posS = fstart(idx.S);
    LEN  = 14;

    for j = 1:numel(linenums_sys)
        ln = dataLines{linenums_sys(j)};
        oi = find(satLineNums == linenums_sys(j), 1);  % global obs index
        out_SatID(oi,:) = ln(1:3);

        llen = numel(ln);
        if ~isnan(idx.C) && llen >= posC+LEN-1
            v = sscanf(ln(posC : posC+LEN-1), '%f', 1);
            if ~isempty(v),  out_PR(oi)  = v;  end
        end
        if ~isnan(idx.D) && llen >= posD+LEN-1
            v = sscanf(ln(posD : posD+LEN-1), '%f', 1);
            if ~isempty(v),  out_Dop(oi) = v;  end
        end
        if ~isnan(idx.S) && llen >= posS+LEN-1
            v = sscanf(ln(posS : posS+LEN-1), '%f', 1);
            if ~isempty(v),  out_SNR(oi) = v;  end
        end
    end
end
fprintf('%.2f s\n', toc);

%% ── 6. Build datetime array (vectorised, outside loop) ──────────────────
fprintf('Building output table ... ');  tic;

ei_vec = double(epochOf);   % epoch index for each obs row

% Vectorised datetime from epoch arrays
obsY  = epochY(ei_vec);   obsMo = epochMo(ei_vec);
obsD  = epochD(ei_vec);   obsH  = epochH(ei_vec);
obsMi = epochMi(ei_vec);  obsS  = epochS(ei_vec);

% Build datetime array in one shot (much faster than assigning in loop)
obsDT = datetime(obsY, obsMo, obsD, obsH, obsMi, obsS, 'TimeZone','UTC');

% GPS week / TOW per obs row
obsWeek = gpsWeek(ei_vec);
obsTOW  = gpsTOW(ei_vec);

%% ── 7. Assemble table & save ─────────────────────────────────────────────
obsTable = table( ...
    obsWeek, ...
    obsTOW, ...
    string(datetime(obsDT,'Format','yyyy-MM-dd')), ...
    string(datetime(obsDT,'Format','HH:mm:ss')), ...
    day(obsDT,'dayofyear'), ...
    string(out_SatID), ...
    out_PR, ...
    out_Dop, ...
    out_SNR, ...
    'VariableNames', { ...
        'Week','GPST_TOW','Date','Time_HMS','DayOfYear', ...
        'SatID','Pseudorange_L1','Doppler_L1','SNR_L1'});

fprintf('%.2f s\n', toc);

save(outputFile, 'obsTable', '-v7.3');
fprintf('\nDone!  %d observations saved to:\n  %s\n', nObs, outputFile);

%% ── Quick sanity print ───────────────────────────────────────────────────
fprintf('\nFirst 5 rows:\n');
disp(obsTable(1:5,:));
fprintf('Systems in output: %s\n', strjoin(unique(extractBefore(obsTable.SatID,2))', ', '));