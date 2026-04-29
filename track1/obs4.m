%% RINEX 3 Multi-GNSS OBS Extractor — FAST VERSION
%  Computes per satellite per epoch:
%    PRC1, PRC2  — pseudorange consistency (Eq. 9)
%    CMC1, CMC2  — code-minus-carrier (Eq. 11)
%    dCMC1,dCMC2 — time-differenced CMC (Eq. 12)
%    MP1, MP2    — dual-frequency multipath estimates (point 6)

clear; clc;

%% ── Config ──────────────────────────────────────────────────────────────
filename   = 'C:\UrbanNav\DeepUrban\UrbanNav-HK-Deep-Urban-1.novatel.flexpak6.obs';
outputFile = 'C:\KLTdataset\data\GNSS\20210610\satellite_obs_extended.mat';

%% ── Wavelengths (m) ─────────────────────────────────────────────────────
LAM.G_L1 = 299792458 / 1575.42e6;
LAM.G_L2 = 299792458 / 1227.60e6;
LAM.R_L1 = 299792458 / 1602.00e6;
LAM.R_L2 = 299792458 / 1246.00e6;
LAM.E_L1 = 299792458 / 1575.42e6;
LAM.E_L2 = 299792458 / 1207.14e6;   % E5b
LAM.C_L1 = 299792458 / 1561.098e6;  % B1I
LAM.C_L2 = 299792458 / 1207.14e6;   % B2I
LAM.J_L1 = LAM.G_L1;
LAM.J_L2 = LAM.G_L2;
LAM.S_L1 = LAM.G_L1;
LAM.S_L2 = NaN;

gpsEpoch = datetime(1980,1,6,'TimeZone','UTC');

%% ── Read entire file at once ────────────────────────────────────────────
tic;
fprintf('Reading file... ');
raw    = fileread(filename);
lines  = strsplit(raw, {'\r\n','\n'});
nLines = numel(lines);
fprintf('done. %d lines in %.1f s\n', nLines, toc);

%% ── Parse header ────────────────────────────────────────────────────────
obsTypes  = struct();
headerEnd = 0;

for i = 1:nLines
    ln = lines{i};
    if numel(ln) < 20, continue; end

    if contains(ln, 'SYS / # / OBS TYPES')
        sys   = ln(1);
        nT    = str2double(strtrim(ln(4:6)));
        types = cell(1, nT);
        for k = 1:min(nT,13)
            s = 7 + (k-1)*4;
            types{k} = strtrim(ln(s:min(s+3,end)));
        end
        obsTypes.(sys) = types;
    end

    if contains(ln, 'END OF HEADER')
        headerEnd = i;
        break;
    end
end
fprintf('Header done. Systems: %s\n', strjoin(fieldnames(obsTypes)', ' '));

%% ── Pre-allocate output arrays ──────────────────────────────────────────
MAX = nLines - headerEnd;

out_week  = zeros(MAX,1,'int32');
out_tow   = zeros(MAX,1,'int32');
out_doy   = zeros(MAX,1,'int16');
out_eIdx  = zeros(MAX,1,'int32');
out_satID = repmat("    ", MAX, 1);

out_P1    = nan(MAX,1); out_L1  = nan(MAX,1);
out_D1    = nan(MAX,1); out_S1  = nan(MAX,1);
out_P2    = nan(MAX,1); out_L2  = nan(MAX,1);
out_D2    = nan(MAX,1); out_S2  = nan(MAX,1);
out_CMC1  = nan(MAX,1); out_CMC2  = nan(MAX,1);
out_dCMC1 = nan(MAX,1); out_dCMC2 = nan(MAX,1);
out_PRC1  = nan(MAX,1); out_PRC2  = nan(MAX,1);
out_MP1   = nan(MAX,1); out_MP2   = nan(MAX,1);

epochDates = NaT(floor(MAX/10), 1, 'TimeZone','UTC');

%% ── Previous-epoch state (per satellite) ────────────────────────────────
prevState = struct('valid',false,'satID','', ...
    'P1',NaN,'P2',NaN,'D1',NaN,'D2',NaN,'CMC1',NaN,'CMC2',NaN);
prevState = repmat(prevState, 256, 1);

satHash = @(s) double(s(1))*100 + str2double(s(2:end));

%% ── Observation index cache ─────────────────────────────────────────────
idxCache = struct();

function [iC,iL,iD,iS,lam] = getSignalIdx(sys, band, types, LAM)
    switch sys
        case {'G','J'}
            if band==1; pfx={'C1','L1','D1','S1'}; lam=LAM.G_L1;
            else;        pfx={'C2L','L2L','D2L','S2L'}; lam=LAM.G_L2; end
        case 'R'
            if band==1; pfx={'C1','L1','D1','S1'}; lam=LAM.R_L1;
            else;        pfx={'C2','L2','D2','S2'}; lam=LAM.R_L2; end
        case 'E'
            if band==1; pfx={'C1','L1','D1','S1'}; lam=LAM.E_L1;
            else;        pfx={'C7','L7','D7','S7'}; lam=LAM.E_L2; end
        case 'C'
            if band==1; pfx={'C2I','L2I','D2I','S2I'}; lam=LAM.C_L1;
            else;        pfx={'C7I','L7I','D7I','S7I'}; lam=LAM.C_L2; end
        case 'S'
            if band==1; pfx={'C1','L1','D1','S1'}; lam=LAM.S_L1;
            else;        iC=[];iL=[];iD=[];iS=[];lam=NaN; return; end
        otherwise
            iC=[];iL=[];iD=[];iS=[];lam=NaN; return;
    end
    f = @(p) find(strncmp(types, p, length(p)), 1);
    iC=f(pfx{1}); iL=f(pfx{2}); iD=f(pfx{3}); iS=f(pfx{4});
end

%% ── Main loop ───────────────────────────────────────────────────────────
tic;
fprintf('Parsing observations...\n');

nEpochs = 0;  nObs = 0;
curWeek = 0;  curTow = 0;  curDoy = 0;
curDt   = 1;  curEIdx = 0; prevTow = -999;

for i = headerEnd+1 : nLines

    ln = lines{i};
    if numel(ln) < 3, continue; end

    %% Epoch line
    if ln(1) == '>'
        v = sscanf(ln(2:end), '%d %d %d %d %d %f');
        if numel(v) < 6, continue; end

        dt_abs  = posixtime(datetime(v(1),v(2),v(3),v(4),v(5),v(6),'TimeZone','UTC'));
        dt_gps  = dt_abs - posixtime(gpsEpoch);
        curWeek = int32(floor(dt_gps / (7*86400)));
        curTow  = int32(round(dt_gps - double(curWeek)*7*86400));
        curDoy  = int16(floor(datenum(v(1),v(2),v(3)) - datenum(v(1),1,0)));

        if prevTow > 0
            curDt = double(curTow - prevTow);
            if curDt <= 0 || curDt > 60, curDt = 1; end
        end
        prevTow = curTow;

        nEpochs = nEpochs + 1;
        if nEpochs > numel(epochDates)
            epochDates(end*2) = NaT('TimeZone','UTC');
        end
        epochDates(nEpochs) = datetime(v(1),v(2),v(3),v(4),v(5),v(6),'TimeZone','UTC');
        curEIdx = int32(nEpochs);
        continue
    end

    %% Satellite line
    if curEIdx == 0, continue; end

    sys = ln(1);
    if ~isfield(obsTypes, sys), continue; end

    satNum = str2double(strtrim(ln(2:3)));
    if isnan(satNum), continue; end
    satStr = sprintf('%s%02d', sys, satNum);

    types = obsTypes.(sys);
    nT    = numel(types);

    %% Parse observations (16 chars per field)
    obs = nan(1, nT);
    for k = 1:nT
        s = 4 + (k-1)*16;
        e = s + 13;
        if numel(ln) >= e
            v = sscanf(ln(s:e), '%f', 1);
            if ~isempty(v), obs(k) = v; end
        end
    end

    %% Get cached signal indices
    ckey1 = [sys '1'];  ckey2 = [sys '2'];
    if ~isfield(idxCache, ckey1)
        [iC1,iL1,iD1,iS1,lam1] = getSignalIdx(sys,1,types,LAM);
        [iC2,iL2,iD2,iS2,lam2] = getSignalIdx(sys,2,types,LAM);
        idxCache.(ckey1) = {iC1,iL1,iD1,iS1,lam1};
        idxCache.(ckey2) = {iC2,iL2,iD2,iS2,lam2};
    end
    c1=idxCache.(ckey1); iC1=c1{1};iL1=c1{2};iD1=c1{3};iS1=c1{4};lam1=c1{5};
    c2=idxCache.(ckey2); iC2=c2{1};iL2=c2{2};iD2=c2{3};iS2=c2{4};lam2=c2{5};

    %% Extract observables
    P1=safeObs(obs,iC1); L1v=safeObs(obs,iL1);
    D1=safeObs(obs,iD1); S1=safeObs(obs,iS1);
    P2=safeObs(obs,iC2); L2v=safeObs(obs,iL2);
    D2=safeObs(obs,iD2); S2=safeObs(obs,iS2);

    %% CMC (Eq. 11):  CMC = P - lambda*L
    CMC1 = cmc(P1, L1v, lam1);
    CMC2 = cmc(P2, L2v, lam2);

    %% PRC (Eq. 9) and dCMC (Eq. 12) from previous epoch
    PRC1=NaN; PRC2=NaN; dCMC1=NaN; dCMC2=NaN;
    h = mod(satHash(satStr), 256) + 1;
    if prevState(h).valid && strcmp(prevState(h).satID, satStr)
        dt_ep = curDt;
        PRC1  = prc(P1, prevState(h).P1, D1, prevState(h).D1, lam1, dt_ep);
        PRC2  = prc(P2, prevState(h).P2, D2, prevState(h).D2, lam2, dt_ep);
        dCMC1 = CMC1 - prevState(h).CMC1;
        dCMC2 = CMC2 - prevState(h).CMC2;
    end

    %% MP1 (point 6):  MP1 = R1 - (1 + 2/(a-1))*Phi1 + (2/(a-1))*Phi2
    %% MP2 (point 6):  MP2 = R2 - (1 + 2*a/(a-1))*Phi2 + (2*a/(a-1))*Phi1  (NOT SAME AS CMC)
    %  alpha = f1^2 / f2^2 = (lam2/lam1)^2
    %  Both require dual-frequency phase observations
    MP1_val=NaN; MP2_val=NaN;
    if ~isnan(P1) && ~isnan(L1v) && ~isnan(L2v) && ~isnan(lam1) && ~isnan(lam2)
        alpha   = (lam2/lam1)^2;          % f1^2/f2^2
        Phi1_m  = lam1 * L1v;             % L1 phase in metres
        Phi2_m  = lam2 * L2v;             % L2 phase in metres
        MP1_val = P1 - (1 + 2/(alpha-1))*Phi1_m + (2/(alpha-1))*Phi2_m;
    end
    if ~isnan(P2) && ~isnan(L1v) && ~isnan(L2v) && ~isnan(lam1) && ~isnan(lam2)
        alpha   = (lam2/lam1)^2;
        Phi1_m  = lam1 * L1v;
        Phi2_m  = lam2 * L2v;
        MP2_val = P2 - (1 + 2*alpha/(alpha-1))*Phi2_m + (2*alpha/(alpha-1))*Phi1_m;
    end

    %% Update previous state
    prevState(h).valid = true;
    prevState(h).satID = satStr;
    prevState(h).P1    = P1;   prevState(h).P2   = P2;
    prevState(h).D1    = D1;   prevState(h).D2   = D2;
    prevState(h).CMC1  = CMC1; prevState(h).CMC2 = CMC2;

    %% Store
    nObs = nObs + 1;
    out_week(nObs) = curWeek;  out_tow(nObs)  = curTow;
    out_doy(nObs)  = curDoy;   out_eIdx(nObs) = curEIdx;
    out_satID(nObs) = satStr;
    out_P1(nObs)=P1;  out_L1(nObs)=L1v; out_D1(nObs)=D1; out_S1(nObs)=S1;
    out_P2(nObs)=P2;  out_L2(nObs)=L2v; out_D2(nObs)=D2; out_S2(nObs)=S2;
    out_CMC1(nObs)=CMC1;   out_CMC2(nObs)=CMC2;
    out_dCMC1(nObs)=dCMC1; out_dCMC2(nObs)=dCMC2;
    out_PRC1(nObs)=PRC1;   out_PRC2(nObs)=PRC2;
    out_MP1(nObs)=MP1_val; out_MP2(nObs)=MP2_val;
end

fprintf('Loop done: %d epochs, %d observations in %.1f s\n', nEpochs, nObs, toc);

%% ── Trim & build date strings ───────────────────────────────────────────
idx        = 1:nObs;
epochDates = epochDates(1:nEpochs);

tic; fprintf('Building table...');
eDate    = epochDates(out_eIdx(idx));
dateStrs = string(datestr(eDate, 'yyyy-mm-dd'));
timeStrs = string(datestr(eDate, 'HH:MM:SS'));

%% ── Assemble table ──────────────────────────────────────────────────────
obsTable = table( ...
    int32(out_week(idx)), int32(out_tow(idx)), ...
    dateStrs,             timeStrs, ...
    int16(out_doy(idx)),  out_satID(idx), ...
    out_P1(idx),  out_L1(idx),  out_D1(idx),  out_S1(idx), ...
    out_P2(idx),  out_L2(idx),  out_D2(idx),  out_S2(idx), ...
    out_CMC1(idx),  out_CMC2(idx), ...
    out_dCMC1(idx), out_dCMC2(idx), ...
    out_PRC1(idx),  out_PRC2(idx), ...
    'VariableNames', { ...
    'Week','GPST_TOW','Date','Time_HMS','DayOfYear','SatID', ...
    'P_L1','L_L1','D_L1','SNR_L1', ...
    'P_L2','L_L2','D_L2','SNR_L2', ...
    'CMC_L1','CMC_L2', ...
    'dCMC_L1','dCMC_L2', ...
    'PRC_L1','PRC_L2'});

save(outputFile, 'obsTable', '-v7.3');
fprintf(' done in %.1f s\n', toc);
fprintf('Saved %d rows to:\n  %s\n', height(obsTable), outputFile);
head(obsTable, 10)

%% ════════════════════════════════════════════════════════════════════════
%% Local functions
%% ════════════════════════════════════════════════════════════════════════
function v = safeObs(obs, idx)
    if isempty(idx) || idx > numel(obs), v = NaN; else, v = obs(idx); end
end

function c = cmc(P, L, lambda)
    if isnan(P)||isnan(L)||isnan(lambda), c=NaN; else, c=P-lambda*L; end
end

function r = prc(P_t,P_p,D_t,D_p,lambda,dt)
    if isnan(P_t)||isnan(P_p)||isnan(D_t)||isnan(D_p)||isnan(lambda)||dt<=0
        r=NaN;
    else
        r=((P_t-P_p)+lambda*(D_t+D_p)*dt/2)^2;
    end
end
