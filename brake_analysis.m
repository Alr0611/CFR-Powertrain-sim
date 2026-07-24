%% BRAKE ANALYSIS July 11 endurance (NO REGEN on this car)
% The car has no regenerative braking: every braking event dumps kinetic
% energy as friction heat. This script quantifies:
%   1. Brake usage: event count, time on brakes, front/rear pressure balance
%   2. Energy shed to friction heat over the run + brake temperatures
%   3. WHAT-IF: the theoretical ceiling of energy that regen could have
%      recovered -- a design input for whether regen is ever worth adding,
%      NOT a claim about the current car.
%
% Inputs:  july11_brake_data.csv              (long format, from export_influx_chunked.py)
%          endurance_july11_with_odo_wide.csv (pack voltage, same 0.1s time base)

clear; clc; close all;
cd(fileparts(mfilename('fullpath')));   % run from the repo root so data/ and output/ paths resolve
if ~exist('output','dir'), mkdir('output'); end   % fresh copy may have no output/ folder

m_car = 294;           % kg, scales-with-driver (CG Calculator.xlsx)
r_wheel = 0.2286;      % m

%% ---- LOAD + PIVOT LONG -> WIDE ----
opts = detectImportOptions('data/july11_brake_data.csv');
opts = setvartype(opts, 'time', 'string');
L = readtable('data/july11_brake_data.csv', opts);
tt = datetime(L.time, 'TimeZone', 'UTC', ...
    'InputFormat', "uuuu-MM-dd'T'HH:mm:ss.SSSSSSxxxxx");
L.t_s = seconds(tt - tt(1));                    % 0.1s grid, t=0 at 15:00:00.100Z
W = unstack(L(:, {'t_s','field','value'}), 'value', 'field', 'AggregationFunction', @mean);
W = sortrows(W, 't_s');
fprintf('Pivoted %d long rows -> %d wide samples, %.1f min\n', height(L), height(W), (W.t_s(end)-W.t_s(1))/60);

% Join pack voltage from the endurance export (same time base)
E = readtable('data/endurance_july11_with_odo_wide.csv');
W.packVoltage = interp1(E.t_s, E.BMSB_packVoltage, W.t_s, 'linear', 'extrap');

t   = W.t_s;
dt  = [diff(t); median(diff(t))];

% Unit sanity for vehicleSpeed: compare with motor-derived road speed
spd_raw = W.VCFRONT_vehicleSpeed;
v_from_motor = abs(W.PM100DX_motorSpeed) / 4.61 * (2*pi/60) * r_wheel; % m/s
ratio_med = median(spd_raw(v_from_motor > 5) ./ v_from_motor(v_from_motor > 5), 'omitnan');
if ratio_med > 2.5
    v = spd_raw / 3.6;
    fprintf('VCFRONT_vehicleSpeed detected as kph (ratio %.2f) -> converted to m/s\n', ratio_med);
else
    v = spd_raw;
    fprintf('VCFRONT_vehicleSpeed detected as m/s (ratio %.2f)\n', ratio_med);
end

% Sanity check: car has NO regen -> pack should essentially never charge
I_pack = -W.BMSB_packCurrent;                 % positive = discharge
P_elec = W.packVoltage .* I_pack;             % W
E_charge_seen = -sum(P_elec(P_elec < -50) .* dt(P_elec < -50), 'omitnan') / 3.6e6;
E_drive_elec  =  sum(P_elec(P_elec > 0) .* dt(P_elec > 0), 'omitnan') / 3.6e6;
fprintf('No-regen sanity: charging energy seen = %.4f kWh (should be ~0) vs %.2f kWh drawn\n', ...
    E_charge_seen, E_drive_elec);

%% ---- BRAKE EVENT DETECTION + FRICTION ENERGY ----
bp_f = W.VCFRONT_brakePressure;
bp_r = W.VCREAR_brakePressure;
bp_thresh = 0.05 * prctile(bp_f(bp_f > 0), 95);   % 5% of P95 (sensor units uncalibrated)
braking = (bp_f > bp_thresh) & (v > 2);

d_braking = diff([false; braking]);
starts = find(d_braking == 1); ends = find(d_braking == -1) - 1;
if length(ends) < length(starts), ends(end+1) = length(braking); end

E_heat = 0; n_events = 0; ev_E = []; ev_vpeak = [];
for e = 1:length(starts)
    v1 = v(starts(e)); v2 = v(ends(e));
    if v1 > v2 && (t(ends(e)) - t(starts(e))) > 0.3
        dE = 0.5*m_car*(v1^2 - v2^2)/3.6e6;   % kWh
        E_heat = E_heat + dE;
        n_events = n_events + 1;
        ev_E(end+1) = dE; ev_vpeak(end+1) = v1*3.6; %#ok<SAGROW>
    end
end
brake_time = sum(dt(braking));

% Front/rear hydraulic balance while braking (raw sensor ratio -- same
% sensor type front/rear assumed; calibrate before quoting as true bias)
fr_balance = median(bp_f(braking) ./ max(bp_r(braking), 1e-6), 'omitnan');

fprintf('\n=== BRAKE USAGE SUMMARY (July 11, %.0f min, NO regen) ===\n', (t(end)-t(1))/60);
fprintf('Brake events                  : %d  (%.1f min total on brakes, %.1f%% of run)\n', ...
    n_events, brake_time/60, 100*brake_time/(t(end)-t(1)));
fprintf('Kinetic energy shed (friction + drag during braking): %.2f kWh\n', E_heat);
fprintf('  vs %.2f kWh total drawn from pack -> braking sheds ~%.0f%% of traction energy as heat\n', ...
    E_drive_elec, 100*E_heat/max(E_drive_elec,1e-9));
fprintf('Median event: %.4f kWh from %.0f kph | hardest event: %.3f kWh\n', ...
    median(ev_E), median(ev_vpeak), max(ev_E));
fprintf('Front/rear brake pressure ratio while braking (raw): %.2f\n', fr_balance);

%% ---- WHAT-IF: regen recovery ceiling (design input, not current car) ----
% Ceiling = kinetic energy shed through the DRIVEN axle only (RWD, so only
% the rear axle's share of braking could ever be recovered), minus
% low-speed events where regen is ineffective (<15 kph cutoff typical).
rear_brake_share = 1 - fr_balance/(1+fr_balance);   % crude split from hydraulic ratio
E_recoverable = 0;
for e = 1:length(starts)
    v1 = v(starts(e)); v2 = max(v(ends(e)), 15/3.6);
    if v1 > v2 && (t(ends(e)) - t(starts(e))) > 0.3
        E_recoverable = E_recoverable + 0.5*m_car*(v1^2 - v2^2)/3.6e6;
    end
end
E_recoverable = E_recoverable * rear_brake_share * 0.85;  % 85% motor+drivetrain regen path eff
fprintf('\nWHAT-IF regen ceiling (rear axle share %.0f%%, >15 kph, 85%% path eff): ~%.2f kWh\n', ...
    100*rear_brake_share, E_recoverable);
fprintf('  = %.1f%% of the %.2f kWh drawn -- the most a future regen system could give back\n', ...
    100*E_recoverable/max(E_drive_elec,1e-9), E_drive_elec);

%% ---- FIGURE 1: hardest braking event detail ----
[~, i_peak] = max(bp_f .* (v > 2));
win = t > t(i_peak)-20 & t < t(i_peak)+20;
% One TABBED window: the hardest-braking event (40 s) + the whole-run overview.
fB = figure('Name','Brake analysis','Position',[40 40 1000 560]);
tg = uitabgroup(fB);

ax = axes(uitab(tg,'Title','Speed (event)'));
plot(ax, t(win), v(win)*3.6, 'LineWidth', 1.2); ylabel(ax,'Speed (kph)'); xlabel(ax,'Time (s)'); grid(ax,'on');
title(ax,'Speed -- 40 s around the hardest braking event');

ax = axes(uitab(tg,'Title','Brake pressure (event)'));
plot(ax, t(win), bp_f(win), 'r', 'LineWidth', 1.2); hold(ax,'on');
plot(ax, t(win), bp_r(win), 'b', 'LineWidth', 1.0);
ylabel(ax,'Brake pressure (raw)'); xlabel(ax,'Time (s)'); legend(ax,'Front','Rear'); grid(ax,'on');
title(ax,'Front/rear pressure -- hydraulic balance under real braking');

ax = axes(uitab(tg,'Title','Pack power (event)'));
plot(ax, t(win), P_elec(win)/1000, 'LineWidth', 1.2);
yline(ax,0, 'k:'); ylabel(ax,'Pack power (kW)'); xlabel(ax,'Time (s)'); grid(ax,'on');
title(ax,'No regen: pack power drops to ~0 in braking, never negative');

ax = axes(uitab(tg,'Title','Brake temps (run)'));
plot(ax, t/60, W.VCFRONT_brakeTempFL, 'DisplayName','FL'); hold(ax,'on');
plot(ax, t/60, W.VCFRONT_brakeTempFR, 'DisplayName','FR');
plot(ax, t/60, W.VCREAR_brakeTempRL, 'DisplayName','RL');
plot(ax, t/60, W.VCREAR_brakeTempRR, 'DisplayName','RR');
ylabel(ax,'Brake temp (raw/degC)'); xlabel(ax,'Time (min)'); legend(ax,'show'); grid(ax,'on');
title(ax,'Brake temperatures over the run (all braking energy -> heat)');

ax = axes(uitab(tg,'Title','Cumulative heat (run)'));
ev_t = t(starts(1:length(ev_E)));
stairs(ax, ev_t/60, cumsum(ev_E), 'LineWidth', 1.4); grid(ax,'on');
xlabel(ax,'Time (min)'); ylabel(ax,'Cumulative friction heat (kWh)');
title(ax,'Cumulative kinetic energy shed in braking events');

save_tabfig(fB, fullfile('output','BrakeAnalysis'));
fprintf('\nSaved: output/BrakeAnalysis.fig + per-tab PNGs (1 tabbed window)\n');
