%% FATIGUE TORQUE SPECTRUM rebuilt from comp data, extended to 150 Nm
% Rebuilds the "Sum" column of CFR24 'Fatigue Load Cases.xlsx' (Load Case
% sheet) from real June 20 comp endurance telemetry instead of the old
% Motec data, and extends the bins from 140 Nm to 150 Nm (motor peak) so
% peak-torque events are captured for the driveline fatigue check.
%
% Output: normalized time-fraction per torque bin (sums to 1.0) -> paste
% into the fatigue tool's Sum column. Also a what-if showing how a lower
% final-drive ratio pushes the spectrum toward higher torque (more fatigue).
%
% *** PENDING DATA: run after export_influx_chunked.py produces
%     comp_june20_data.csv. ***

clear; clc; close all;
cd(fileparts(mfilename('fullpath')));   % run from the repo root so data/ and output/ paths resolve
if ~exist('output','dir'), mkdir('output'); end   % fresh copy may have no output/ folder

% Exact bin edges from 'Fatigue Load Cases.xlsx' (Load Case), + new 140-150 bin
edges = [0.1 15.1 30.1 45.1 60.1 75 90 105 120 130 140 150];
old_sum = [0.3132 0.2301 0.1509 0.0995 0.0686 0.042 0.0218 0.02615 0.0218 0.02615 0]; % Motec, 140-150 was 0
gear_comp = 4.61;    % ratio the comp run was driven at
gear_new  = 4.20;    % candidate ratio for the what-if

if ~isfile('data/comp_june20_data.csv')
    error('comp_june20_data.csv not found. Run export_influx_chunked.py (June 20 window) first.');
end

%% ---- LOAD (wide, MATLAB-ready straight from export_influx_chunked.py) ----
W = readtable('data/comp_june20_data.csv');   % columns: t_s + one per channel
W = sortrows(W,'t_s'); dt = [diff(W.t_s); median(diff(W.t_s))];

torque = W.PM100DX_torqueFeedback;
rs = corrcoef(W.PM100DX_motorSpeed(~isnan(torque)), torque(~isnan(torque)));
if rs(1,2)<0, torque = -torque; end
T = abs(torque);                    % magnitude drives tooth loading
moving = abs(W.PM100DX_motorSpeed) > 100;   % endurance driving only (drop idle/paddock)
T = T(moving); w = dt(moving);

%% ---- BUILD NORMALIZED SPECTRUM (time-fraction per bin) ----
% Normalize over LOADED time (torque in-bins), matching how the old Motec
% "Torque Request" spectrum sums to 100%% -> drop-in for the tool's Sum col.
% Near-zero-torque coasting (below the 0.1 Nm first bin) is reported
% separately; it produces negligible tooth stress (infinite fatigue life).
bin_time = zeros(1, numel(edges)-1);
for k = 1:numel(edges)-1
    bin_time(k) = sum(w(T >= edges(k) & T < edges(k+1)));
end
over150 = sum(w(T >= 150));
loaded = sum(bin_time);
coast_frac = 1 - loaded/sum(w);      % fraction of driving time at ~0 torque
spec = bin_time / loaded;            % normalize to 1.0 over the loaded bins
frac_peak = sum(spec(edges(1:end-1) >= 120));

fprintf('=== COMP ENDURANCE TORQUE SPECTRUM (%.0f min driving, %.0f%% coasting <0.1Nm) ===\n', ...
    sum(w)/60, 100*coast_frac);
fprintf(' Peak motor torque observed: %.1f Nm (motor cap 150 Nm)\n', max(T));
fprintf(' Bin (Nm)        Comp %%   (old Motec %%)\n');
for k = 1:numel(edges)-1
    fprintf('  %5.1f - %5.1f   %5.1f     %5.1f\n', edges(k), edges(k+1), spec(k)*100, old_sum(k)*100);
end
fprintf(' >=150 Nm (over peak): %.2f%% of loaded time\n', 100*over150/loaded);
fprintf(' Time above 120 Nm (high-fatigue): comp %.1f%% vs Motec %.1f%%\n', ...
    100*frac_peak, 100*sum(old_sum(edges(1:end-1)>=120)));

%% ---- WHAT-IF: lower ratio shifts motor torque up (fatigue cost) ----
% Same wheel demand, motor torque scales by gear_comp/gear_new (power-invariant).
T_new = T * gear_comp/gear_new;
bin_time_new = zeros(1, numel(edges)-1);
for k = 1:numel(edges)-1
    bin_time_new(k) = sum(w(T_new >= edges(k) & T_new < edges(k+1)));
end
over150_new = sum(w(T_new >= 150));
loaded_new = sum(bin_time_new);
spec_new = bin_time_new / loaded_new;
fprintf('\nWHAT-IF at %.2f:1 -> time above 120 Nm rises to %.1f%%, >=150 Nm to %.2f%%\n', ...
    gear_new, 100*sum(spec_new(edges(1:end-1)>=120)), 100*over150_new/loaded_new);
fprintf('  -> lower ratio = higher DT fatigue loading; feed both columns through P2121/P2127.\n');

%% ---- EXPORT: bin table for the fatigue tool ----
BinStart = edges(1:end-1)'; BinEnd = edges(2:end)';
Sum_comp = spec'; Sum_at_new_ratio = spec_new';
Tspec = table(BinStart, BinEnd, Sum_comp, Sum_at_new_ratio);
writetable(Tspec, 'output/fatigue_spectrum_comp.csv');

%% ---- FIGURE ----
ctr = (edges(1:end-1)+edges(2:end))/2;
fig = figure('Name','Fatigue torque spectrum','Position',[60 60 900 500]);
b = bar(ctr, [old_sum; spec; spec_new]'*100, 'grouped');
b(1).DisplayName='Old Motec (140 cap)'; b(2).DisplayName=sprintf('Comp %.2f:1',gear_comp);
b(3).DisplayName=sprintf('What-if %.2f:1',gear_new);
xline(140,'k--','old 140 cap','HandleVisibility','off');
xline(150,'r--','motor peak 150','HandleVisibility','off');
xlabel('Motor torque bin (Nm)'); ylabel('% of endurance driving time');
title('Driveline torque load spectrum â€” real comp data, extended to 150 Nm');
subtitle(sprintf('Comp endurance peaked at %.0f Nm; time >120 Nm only %.1f%%. 4.2:1 shifts it slightly right (small fatigue increase).', max(T), 100*frac_peak));
legend('show'); grid on;
savefig(fig,'output/fatigue_spectrum.fig'); try, saveas(fig,'output/fatigue_spectrum.png'); catch, end
fprintf('\nSaved: fatigue_spectrum_comp.csv, fatigue_spectrum.fig/png\n');
