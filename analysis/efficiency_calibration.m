%% EFFICIENCY_CALIBRATION -- the "rich export" version of the cross-check.
%
% efficiency_crosscheck.m answers "do measured and physics agree?" with the
% channels we already have. THIS script is what you run when the richer
% InfluxDB export finally lands: it auto-detects the extra channels and uses each
% one to remove a known artifact:
%
%   PM100DX_dcBusVoltage/Current -> true inverter INPUT power (accessory removal).
%                                   *** DISABLED (design review, see below) ***
%   PM100DX_motorTemp            -> copper resistance rises ~0.4%/degC; correct
%                                   R_phase to the real winding temperature.
%   PM100DX_currentPhaseA/B/C    -> independent torque cross-check.
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

csvPath        = fullfile(repo,'data','comp_june20_data.csv');   % <-- point at the rich export when it lands
calibrationData = readtable(csvPath);
hasChannel = @(n) ismember(n, calibrationData.Properties.VariableNames);

motorSpeed = abs(calibrationData.PM100DX_motorSpeed);
if hasChannel('PM100DX_feedbackTorque'), motorTorque = abs(calibrationData.PM100DX_feedbackTorque);   % their channel name
else,                                    motorTorque = abs(calibrationData.PM100DX_torqueFeedback);   % ours
end
packPower       = abs(calibrationData.BMSB_packVoltage .* calibrationData.BMSB_packCurrent);
mechanicalPower = motorTorque .* motorSpeed * 2*pi/60;

fprintf('channels present:\n');
fprintf('  dc-bus power (accessory removal): %s  [DISABLED -- untrustworthy, see below]\n', tf(hasChannel('PM100DX_dcBusCurrent')));
fprintf('  motor temp (temp correction)    : %s\n',   tf(hasChannel('PM100DX_motorTemp')));
fprintf('  phase currents (torque check)   : %s\n\n', tf(hasChannel('PM100DX_currentPhaseA')));

%% ---- inverter-input power ----
% DISABLED (design review): the dc-bus accessory-removal path needs
% PM100DX_dcBusCurrent, which reads ~100 A too high (a DBC scale-factor error).
% Using it would mis-book accessory draw and corrupt the measured efficiency. So we
% do NOT remove accessories here -- electricalInput is pack electrical power
% (accessories still in it). Re-enable with a corrected dc-bus signal or a dyno.
electricalInput = packPower;
fprintf('dc-bus accessory removal DISABLED (dcBusCurrent untrustworthy) -> electricalInput = pack power.\n');
measuredEfficiency = mechanicalPower ./ electricalInput;

%% ---- physics, temperature-corrected if motor temp is available ----
if hasChannel('PM100DX_motorTemp')
    motorTemp       = calibrationData.PM100DX_motorTemp;
    copperTempCoeff = 0.00393;                       % copper temp coeff, /degC
    hotPhaseResistance = p.R_phase * (1 + copperTempCoeff*(motorTemp - 25));
    currentRms = motorTorque / p.Nm_per_Arms;
    copperLoss = 3 * currentRms.^2 .* hotPhaseResistance;      % hot copper loss
    coreLoss   = p.core_loss_a*motorSpeed + p.core_loss_b*motorSpeed.^2;
    physicsEfficiency = mechanicalPower ./ max(mechanicalPower + copperLoss + coreLoss, 1e-6);
    fprintf('physics: temperature-corrected (motor %.0f-%.0f C).\n', min(motorTemp), max(motorTemp));
else
    physicsEfficiency = emrax208_efficiency(motorSpeed, motorTorque, rmfield(p,'eta_inverter'));  % motor only, cold R
    fprintf('[no motor-temp channel -> physics uses fixed cold resistance]\n');
end

%% ---- phase-current torque cross-check, if available ----
if hasChannel('PM100DX_currentPhaseA')
    phaseCurrentRms = sqrt((calibrationData.PM100DX_currentPhaseA.^2 + calibrationData.PM100DX_currentPhaseB.^2 + ...
                            calibrationData.PM100DX_currentPhaseC.^2)/3);        % rms of the three phases
    torqueFromCurrent = phaseCurrentRms * p.Nm_per_Arms;                        % torque implied by current
    loadedMask = motorTorque>20;
    fprintf('torque check: feedbackTorque vs current-implied, median ratio %.3f\n', ...
            median(motorTorque(loadedMask)./max(torqueFromCurrent(loadedMask),1e-6)));
end

%% ---- steady-state mask: rpm AND torque near-constant over ~1 s ----
% MOTORING FILTER -- TODO (design review, STUBBED): driver-intent (>15% accelerator)
% needs VCFRONT_acceleratorPosition, absent from this export (needs DAQ access).
% Keep the existing motorSpeed>500 & torque>5 gate; do not fake it.
steadyWindow = 11;                                   % ~1.1 s window at 10 Hz
motoringMask = motorSpeed>500 & motorTorque>5 & electricalInput>500 & measuredEfficiency>0.3 & measuredEfficiency<1.0;
steadyMask   = motoringMask & movstd(motorSpeed,steadyWindow)<40 & movstd(motorTorque,steadyWindow)<3;
steadyCount  = nnz(steadyMask);
fprintf('\nmotoring samples: %d   |   of those, STEADY-STATE: %d (%.1f%%)\n', ...
        nnz(motoringMask), steadyCount, 100*steadyCount/max(nnz(motoringMask),1));
if steadyCount < 100
    fprintf('  [LOW CONFIDENCE: < 100 steady-state points -- a deliberate steady-state / dyno run\n');
    fprintf('   would firm up the in-band number]\n');
end

%% ---- the comparison: all motoring vs steady-only ----
fprintf('\n                         measured   physics    gap\n');
report('ALL motoring points', measuredEfficiency(motoringMask),  physicsEfficiency(motoringMask));
report('STEADY-STATE only  ', measuredEfficiency(steadyMask), physicsEfficiency(steadyMask));

fprintf('\nby power band, STEADY-STATE only:\n');
powerBandEdges = [3 6 10 15 25 60]*1000;
for k = 1:numel(powerBandEdges)-1
  bandMask = steadyMask & mechanicalPower>=powerBandEdges(k) & mechanicalPower<powerBandEdges(k+1);
  if nnz(bandMask) > 15
    fprintf('  %2d-%2d kW : measured %.3f | physics %.3f | gap %+.3f  (n=%d)\n', ...
      powerBandEdges(k)/1000, powerBandEdges(k+1)/1000, mean(measuredEfficiency(bandMask)), ...
      mean(physicsEfficiency(bandMask)), mean(physicsEfficiency(bandMask))-mean(measuredEfficiency(bandMask)), nnz(bandMask));
  end
end

function report(lbl, measuredEff, physicsEff)
  fprintf('  %s   %.3f      %.3f    %+.3f\n', lbl, mean(measuredEff), mean(physicsEff), mean(physicsEff)-mean(measuredEff));
end
function s = tf(b); if b, s='YES'; else, s='no'; end; end
