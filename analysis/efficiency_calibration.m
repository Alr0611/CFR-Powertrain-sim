%% EFFICIENCY_CALIBRATION -- the "rich export" version of the cross-check.
%
% efficiency_crosscheck.m answers "do measured and physics agree?" with the
% channels we already have. THIS script is what you run when the richer
% InfluxDB export finally lands (see tools/export_influx_chunked.py and the
% handoff doc): it auto-detects the extra channels and uses each one to
% remove a known artifact:
%
%   PM100DX_dcBusVoltage/Current -> true inverter INPUT power, so the pack's
%                                   accessory draw (pumps/fans/LV) stops being
%                                   booked as motor loss.
%   PM100DX_motorTemp            -> copper resistance rises ~0.4%/degC; correct
%                                   R_phase to the real winding temperature.
%   PM100DX_currentPhaseA/B/C    -> independent torque cross-check (is
%                                   torqueFeedback biased?).
%
% With none of those present it still runs -- it strips the biggest artifact
% (transients) via a steady-state mask and tells you what it couldn't do.
%
% Swap CSV below for the new export when it exists. Nothing else changes.

clear; clc;
here = fileparts(mfilename('fullpath'));
repo = fileparts(here);
addpath(repo, fullfile(repo,'lib'), here);
p = params_cfr26();

CSV = fullfile(repo,'data','comp_june20_data.csv');   % <-- point at the rich export when it lands
D   = readtable(CSV);
has = @(n) ismember(n, D.Properties.VariableNames);

rpm = abs(D.PM100DX_motorSpeed);
if has('PM100DX_feedbackTorque'), tq = abs(D.PM100DX_feedbackTorque);   % their channel name
else,                             tq = abs(D.PM100DX_torqueFeedback);   % ours
end
packElec = abs(D.BMSB_packVoltage .* D.BMSB_packCurrent);
mech     = tq .* rpm * 2*pi/60;

fprintf('channels present:\n');
fprintf('  dc-bus power (accessory removal): %s\n',   tf(has('PM100DX_dcBusCurrent')));
fprintf('  motor temp (temp correction)    : %s\n',   tf(has('PM100DX_motorTemp')));
fprintf('  phase currents (torque check)   : %s\n\n', tf(has('PM100DX_currentPhaseA')));

%% ---- inverter-input power: accessories removed if dc-bus is available ----
if has('PM100DX_dcBusCurrent') && has('PM100DX_dcBusVoltage')
    elecIn = abs(D.PM100DX_dcBusVoltage .* D.PM100DX_dcBusCurrent);  % true inverter input
    accessory = median(packElec - elecIn, 'omitnan');
    fprintf('accessory draw (pack - dcBus) = %.0f W, removed.\n', accessory);
else
    elecIn = packElec;   % still has accessories in it
    fprintf('[no dc-bus channel -> accessories NOT removed this run]\n');
end
eff_meas = mech ./ elecIn;

%% ---- physics, temperature-corrected if motor temp is available ----
if has('PM100DX_motorTemp')
    Tm    = D.PM100DX_motorTemp;
    alpha = 0.00393;                       % copper temp coeff, /degC
    Rhot  = p.R_phase * (1 + alpha*(Tm - 25));
    Irms  = tq / p.Nm_per_Arms;
    Pcu   = 3 * Irms.^2 .* Rhot;           % hot copper loss
    Pfe   = p.core_loss_a*rpm + p.core_loss_b*rpm.^2;
    eff_phys = mech ./ max(mech + Pcu + Pfe, 1e-6);
    fprintf('physics: temperature-corrected (motor %.0f-%.0f C).\n', min(Tm), max(Tm));
else
    eff_phys = emrax208_efficiency(rpm, tq, rmfield(p,'eta_inverter'));  % motor only, cold R
    fprintf('[no motor-temp channel -> physics uses fixed cold resistance]\n');
end

%% ---- phase-current torque cross-check, if available ----
if has('PM100DX_currentPhaseA')
    Iph  = sqrt((D.PM100DX_currentPhaseA.^2 + D.PM100DX_currentPhaseB.^2 + ...
                 D.PM100DX_currentPhaseC.^2)/3);        % rms of the three phases
    tqI  = Iph * p.Nm_per_Arms;                          % torque implied by current
    ld   = tq>20;
    fprintf('torque check: feedbackTorque vs current-implied, median ratio %.3f\n', ...
            median(tq(ld)./max(tqI(ld),1e-6)));
end

%% ---- steady-state mask: rpm AND torque near-constant over ~1 s ----
w = 11;                                   % ~1.1 s window at 10 Hz
motor  = rpm>500 & tq>5 & elecIn>500 & eff_meas>0.3 & eff_meas<1.0;
steady = motor & movstd(rpm,w)<40 & movstd(tq,w)<3;
fprintf('\nmotoring samples: %d   |   of those, STEADY-STATE: %d (%.1f%%)\n', ...
        nnz(motor), nnz(steady), 100*nnz(steady)/nnz(motor));

%% ---- the comparison: all motoring vs steady-only ----
fprintf('\n                         measured   physics    gap\n');
report('ALL motoring points', eff_meas(motor),  eff_phys(motor));
report('STEADY-STATE only  ', eff_meas(steady), eff_phys(steady));

fprintf('\nby power band, STEADY-STATE only:\n');
edges = [3 6 10 15 25 60]*1000;
for k = 1:numel(edges)-1
  b = steady & mech>=edges(k) & mech<edges(k+1);
  if nnz(b) > 15
    fprintf('  %2d-%2d kW : measured %.3f | physics %.3f | gap %+.3f  (n=%d)\n', ...
      edges(k)/1000, edges(k+1)/1000, mean(eff_meas(b)), mean(eff_phys(b)), ...
      mean(eff_phys(b))-mean(eff_meas(b)), nnz(b));
  end
end

function report(lbl, m, ph)
  fprintf('  %s   %.3f      %.3f    %+.3f\n', lbl, mean(m), mean(ph), mean(ph)-mean(m));
end
function s = tf(b); if b, s='YES'; else, s='no'; end; end
