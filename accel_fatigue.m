%% ACCEL FATIGUE + LAUNCH ANALYSIS June 19 comp accel runs
% Accel is where the driveline sees peak torque (endurance topped out at
% 132 Nm; accel hits ~159 Nm). This builds the PEAK-LOAD torque spectrum
% that fills the 140-150+ Nm bins the endurance spectrum left empty, plus:
%   - detects individual launch events and their peak torque / 0-75m time
%   - requested (command) vs delivered (feedback) torque = TC + drivetrain
%     dynamics, incl. the transient overshoot above the 150 Nm cap
%
% Feeds the same CFR24 fatigue tool (P2121/P2127) as the endurance spectrum,
% but this is the WORST-CASE load case for gear-tooth fatigue.

clear; clc; close all;
cd(fileparts(mfilename('fullpath')));   % run from the repo root so data/ and output/ paths resolve

edges = [0.1 15.1 30.1 45.1 60.1 75 90 105 120 130 140 150 160];  % +150-160 bin for overshoot
r_wheel = 0.2286;

W = readtable('data/comp_june19_accel.csv');
W = sortrows(W,'t_s'); t = W.t_s; dt = [diff(t); median(diff(t))];

% Sign convention: positive torque = motoring (matches motor rpm direction)
tf = W.PM100DX_torqueFeedback; tc = W.PM100DX_torqueCommand;
rpm = W.PM100DX_motorSpeed; v = W.VCFRONT_vehicleSpeed;   % v in m/s
sg = corrcoef(rpm(~isnan(tf)), tf(~isnan(tf)));
if sg(1,2) < 0, tf = -tf; tc = -tc; end
Tf_raw = abs(tf);
% Glitch-robust torque: 3-sample median filter removes isolated 1-sample
% spikes (likely sensor artifacts) while preserving real sustained loads.
Tf = medfilt1(Tf_raw, 3);
% Is the >150 Nm content real (sustained) or glitchy (isolated spikes)?
over_raw = Tf_raw > 150;
d = diff([0; over_raw; 0]); runlen = find(d<0) - find(d>0);   % length of each >150 run
n_isolated = sum(runlen == 1); n_sustained = sum(runlen >= 3);
fprintf('>150 Nm content: %d isolated 1-sample spikes (glitch-like), %d runs >=3 samples (real).\n', ...
    n_isolated, n_sustained);
fprintf('Raw peak %.0f Nm -> after de-spike %.0f Nm.\n\n', max(Tf_raw), max(Tf));

%% ---- HIGH-LOAD SEGMENT DETECTION (for fatigue) + CLEAN accel runs (for timing) ----
% The June 19 afternoon is mostly practice/autocross, so most "launches" are
% corner exits, not straight-line runs. For FATIGUE we take all high-torque
% loaded time (loads are loads). For a valid 0-75m TIME we require a CLEAN
% run: monotonic rise from standstill to >90 kph with no braking.
launching = Tf > 40 & abs(rpm) > 100;   % loaded, moving -> fatigue-relevant time
starts = find(v(1:end-1) < 2 & v(2:end) >= 2) + 1;
n_launch = 0; n_clean = 0; peakT = []; t75 = []; vtrap = []; clean_idx = [];
for s = starts'
    e = s;
    while e < numel(v) && v(e) < 30 && (e - s) < 120, e = e + 1; end
    seg = s:e;
    if max(v(seg)) < 15 || max(Tf(seg)) < 80, continue; end
    n_launch = n_launch + 1;
    peakT(end+1) = max(Tf(seg)); %#ok<SAGROW>
    % Clean accel run test: reaches 25 m/s (90 kph) and never drops >3 m/s en route
    i90 = find(v(seg) >= 25, 1);
    if ~isempty(i90)
        rise = v(seg(1:i90));
        if all(diff(rise) > -0.3)   % essentially monotonic to 90 kph = straight-line pull
            n_clean = n_clean + 1;
            dist = cumtrapz(t(seg), v(seg)); i75 = find(dist >= 75, 1);
            if ~isempty(i75)
                t75(end+1) = t(seg(i75))-t(seg(1)); vtrap(end+1) = v(seg(i75))*3.6; %#ok<SAGROW>
                clean_idx(end+1) = s; %#ok<SAGROW>
            end
        end
    end
end
fprintf('=== SEGMENTS: %d launches/corner-exits, %d CLEAN straight-line accel runs ===\n', n_launch, n_clean);
fprintf(' Peak torque across all: max %.0f Nm, median %.0f Nm\n', max(peakT), median(peakT));
if ~isempty(t75)
    fprintf(' CLEAN 0-75m runs: %d | best %.2fs, median %.2fs, trap %.0f-%.0f kph\n', ...
        numel(t75), min(t75), median(t75), min(vtrap), max(vtrap));
else
    fprintf(' No clean straight-line 0-75m runs in this window (data is mostly cornering).\n');
end

%% ---- REQUESTED vs DELIVERED torque ----
hi = Tf > 100;
overshoot = Tf - abs(tc);
fprintf('\n=== REQUESTED (command) vs DELIVERED (feedback) ===\n');
fprintf(' Command capped at %.0f Nm | de-spiked feedback peak %.0f Nm\n', max(abs(tc)), max(Tf));
if n_sustained == 0
    fprintf(' The >150 Nm samples are isolated spikes -> LIKELY SENSOR GLITCH, not real load.\n');
    fprintf(' Treat 150 Nm (the command cap) as the real worst-case tooth load.\n');
else
    fprintf(' %d sustained runs above 150 Nm -> real transient overshoot beyond the command cap.\n', n_sustained);
end

%% ---- PEAK-LOAD TORQUE SPECTRUM (from launch events) ----
w = dt(launching); Tl = Tf(launching);
bin_time = zeros(1, numel(edges)-1);
for k = 1:numel(edges)-1
    bin_time(k) = sum(w(Tl >= edges(k) & Tl < edges(k+1)));
end
spec = bin_time / sum(bin_time);
fprintf('\n=== ACCEL PEAK-LOAD TORQUE SPECTRUM (%.1f s of launches) ===\n', sum(w));
fprintf(' Bin (Nm)        Accel %%   (endurance had ~0%% above 120)\n');
for k = 1:numel(edges)-1
    fprintf('  %5.1f - %5.1f   %5.1f\n', edges(k), edges(k+1), spec(k)*100);
end
fprintf(' Time above 140 Nm: %.1f%% of launch time (endurance: 0%%)\n', 100*sum(spec(edges(1:end-1)>=140)));

BinStart = edges(1:end-1)'; BinEnd = edges(2:end)'; Sum_accel = spec';
writetable(table(BinStart, BinEnd, Sum_accel), 'output/fatigue_spectrum_accel.csv');

%% ---- FIGURES ----
% 1) hardest launch: torque + speed trace
[~, ih] = max(peakT); s = starts(1);   % re-find hardest launch window
cnt = 0;
for si = starts'
    e = si; while e<numel(v) && v(e)<30 && (e-si)<120, e=e+1; end
    seg = si:e;
    if max(v(seg))<15 || max(Tf(seg))<80, continue; end
    cnt = cnt+1; if cnt==ih, s = si; ee = e; break; end
end
seg = s:ee; tt = t(seg)-t(s);
% One window: top row = the hardest launch (torque + speed), bottom = the
% accel-vs-endurance load spectrum spanning the width.
fF = figure('Name','Accel fatigue','Position',[40 40 1200 760]);
tl = tiledlayout(fF,2,2,'TileSpacing','compact','Padding','compact');

nexttile(tl);
plot(tt, abs(tc(seg)), 'LineWidth',1.3,'DisplayName','Requested (command)'); hold on;
plot(tt, Tf(seg), 'LineWidth',1.3,'DisplayName','Delivered (feedback)');
yline(150,'r--','150 Nm spec peak','HandleVisibility','off');
ylabel('Motor torque (Nm)'); xlabel('Time (s)'); legend('Location','northeast'); grid on;
title(sprintf('Hardest segment -- de-spiked peak %.0f Nm (raw %.0f)', max(Tf(seg)), max(Tf_raw(seg))));

nexttile(tl);
plot(tt, v(seg)*3.6, 'LineWidth',1.3); ylabel('Speed (kph)'); xlabel('Time (s)'); grid on;
title('Vehicle speed');

nexttile(tl,[1 2]);
ctr = (edges(1:end-1)+edges(2:end))/2;
% comp endurance spectrum (from fatigue_spectrum.m), 11 bins + 150-160 bin = 0
end_spec = [41.5 17.1 15.6 13.1 6.6 2.8 3.1 0.2 0.1 0 0 0];   % 12 values = 12 accel bins
bar(ctr, [end_spec; spec*100]', 'grouped');
legend('Endurance (comp)','Accel (comp)','Location','northeast');
xline(150,'r--','spec peak','HandleVisibility','off');
xlabel('Motor torque bin (Nm)'); ylabel('% of loaded time');
title('Driveline load: endurance stays low; accel fills 120-160 Nm -- the fatigue-critical case');

title(tl,'Accel fatigue: hardest launch + torque load spectrum');
nm = fullfile('output', matlab.lang.makeValidName(fF.Name));
savefig(fF,[nm '.fig']); try, saveas(fF,[nm '.png']); catch, end
fprintf('\nSaved: output/fatigue_spectrum_accel.csv + 1 figure window (AccelFatigue)\n');
