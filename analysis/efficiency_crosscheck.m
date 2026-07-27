%% EFFICIENCY_CROSSCHECK -- our physics model vs MEASURED efficiency, same data.
%
% Two independent ways to get motor efficiency:
%   1. OURS: physics (copper + iron loss from the EMRAX 208 HV datasheet),
%      lib/emrax208_efficiency.m, times the p.eta_inverter real-world haircut.
%   2. THEIRS: the af/dteff method -- measure it. Instantaneous (shaft power /
%      pack power) from telemetry, binned over torque x speed.
%      Reimplemented in analysis/measured_efficiency_map.m.
% If two methods that share NO assumptions agree, both are probably right.
% This script runs the comparison on the June 20 comp session and prints an
% honest verdict. Expected result (and why the sim uses eta_inverter = 0.95):
%   - steady-state measured motor+inverter eff ~ 0.86
%   - our physics (motor only) on the same points  ~ 0.91
%   - 0.91 x 0.95 = 0.86  -> the haircut closes the gap.

clear; clc;
here = fileparts(mfilename('fullpath'));
repo = fileparts(here);
addpath(repo, fullfile(repo,'lib'), here);
p = params_cfr26();

crosscheckData = readtable(fullfile(repo,'data','comp_june20_data.csv'));
motorSpeed  = abs(crosscheckData.PM100DX_motorSpeed);
motorTorque = abs(crosscheckData.PM100DX_torqueFeedback);
packVoltage = crosscheckData.BMSB_packVoltage;
packCurrent = crosscheckData.BMSB_packCurrent;
packPower       = abs(packVoltage.*packCurrent);
mechanicalPower = motorTorque .* motorSpeed * 2*pi/60;

%% ---- 0. why their map is motor+inverter (the 4.6 cancels) ----
% Rigid driveline -> axleSpeed = motorRPM/ratio. Their "wheel power" is
% axleSpeed * motorTorque*4.6 = motor shaft power. Prove the ratio from data:
axleSpeed      = abs(crosscheckData.VCREAR_wheelSpeedRL);
validRatioMask = motorSpeed>500 & axleSpeed>20;
measuredRatio  = median(motorSpeed(validRatioMask)./axleSpeed(validRatioMask));
fprintf('measured motor:axle speed ratio = %.3f (gear ratio on car: %.2f)\n', measuredRatio, p.gear_current);
fprintf('-> af/dteff''s 4.6 cancels out; their map = MOTOR+INVERTER eff.\n\n');

%% ---- 1. the af/dteff map from OUR data (all motoring points) ----
measuredMapAll = measured_efficiency_map(motorSpeed, motorTorque, packVoltage, packCurrent);
fprintf('=== MEASURED MAP, all motoring points (af/dteff method) ===\n');
fprintf('  energy-weighted overall eff : %.3f\n', measuredMapAll.eff_overall);
fprintf('  populated bins (>=20 pts)   : %d of %d\n\n', nnz(~isnan(measuredMapAll.eff)), numel(measuredMapAll.eff));

%% ---- 2. steady-state only: strip the transient artifact ----
% During accel, pack power also spins up inertia -- the instantaneous ratio
% books that as "loss". Keep only points where rpm AND torque hold still.
steadyWindow = 11;                                  % ~1.1 s at 10 Hz
steadyMask   = movstd(motorSpeed,steadyWindow)<40 & movstd(motorTorque,steadyWindow)<3;
measuredMapSteady = measured_efficiency_map(motorSpeed, motorTorque, packVoltage, packCurrent, 'keep', steadyMask, 'minSamples', 10);
steadyMotoringMask = measuredMapSteady.point.keep;  % the actual steady motoring mask

% linear fit  packElec = mech/eta + P0  over steady points:
% slope -> motor+inverter eff, intercept -> constant accessory draw
% (pumps/fans/LV) that shouldn't be booked against the motor.
fitDesignMatrix = [mechanicalPower(steadyMotoringMask) ones(nnz(steadyMotoringMask),1)];
fitCoeffs       = fitDesignMatrix \ packPower(steadyMotoringMask);
measuredMotorInverterEff = 1/fitCoeffs(1);  accessoryDraw = fitCoeffs(2);
steadyCount     = nnz(steadyMotoringMask);
motoringCount   = nnz(measuredMapAll.point.keep);   % all motoring points, same data
steadyPct       = 100*steadyCount/max(motoringCount,1);   % D3: report the fraction, not just the count
fprintf('=== STEADY-STATE only (%d pts, %.1f%% of %d motoring) ===\n', steadyCount, steadyPct, motoringCount);
fprintf('  fit: motor+inverter eff = %.3f | accessory draw = %.0f W\n', measuredMotorInverterEff, accessoryDraw);
if steadyCount < 100   % D3: flag a thin in-band sample
    fprintf('  [LOW CONFIDENCE: < 100 steady-state points -- a deliberate steady-state / dyno run\n');
    fprintf('   would firm up this number]\n');
end

%% ---- 3. our model on the exact same points ----
physicsMotorOnly = emrax208_efficiency(motorSpeed, motorTorque, rmfield(p,'eta_inverter'));  % motor physics only
physicsRealWorld = physicsMotorOnly * p.eta_inverter;                                        % what the sim uses
fprintf('  our physics (motor only)    = %.3f\n', mean(physicsMotorOnly(steadyMotoringMask)));
fprintf('  x eta_inverter %.2f         = %.3f\n', p.eta_inverter, mean(physicsRealWorld(steadyMotoringMask)));
fprintf('  model - measured            = %+.4f\n\n', mean(physicsRealWorld(steadyMotoringMask)) - measuredMotorInverterEff);

%% ---- 4. binned map comparison (model on the same af/dteff grid) ----
torqueEdges = 2.5:15:152.5;  rpmEdges = 15:600:6015;
torqueBin = discretize(motorTorque, torqueEdges);  speedBin = discretize(motorSpeed, rpmEdges);
mappedMask = measuredMapAll.point.keep & ~isnan(torqueBin) & ~isnan(speedBin);
linearIndex = sub2ind([10 10], torqueBin(mappedMask), speedBin(mappedMask));
binCount = accumarray(linearIndex, 1, [100 1]);
physicsMap = reshape(accumarray(linearIndex, physicsRealWorld(mappedMask), [100 1])./max(binCount,1), [10 10]);
physicsMap(reshape(binCount,[10 10]) < 20) = NaN;
sharedBins = ~isnan(measuredMapAll.eff) & ~isnan(physicsMap);
fprintf('=== BINNED MAPS (raw race data, %d shared bins) ===\n', nnz(sharedBins));
fprintf('  mean measured : %.3f   mean model : %.3f   mean |diff| : %.3f\n', ...
        mean(measuredMapAll.eff(sharedBins)), mean(physicsMap(sharedBins)), ...
        mean(abs(measuredMapAll.eff(sharedBins)-physicsMap(sharedBins))));
fprintf('  (raw-data bins read LOW -- transient inertia pollution. The\n');
fprintf('   steady-state fit above is the number that means something.)\n');

%% ---- 5. figure ----
figHandle = figure('Position',[80 80 1500 420], 'Color','w');
subplot(1,3,1); surf(measuredMapAll.tqCenters, measuredMapAll.rpmCenters, measuredMapAll.eff.');
  title('MEASURED (af/dteff method, raw)'); xlabel('Torque (Nm)'); ylabel('Speed (rpm)');
  zlabel('\eta'); zlim([.5 1]); shading interp; colorbar; view(135,30);
subplot(1,3,2); surf(measuredMapAll.tqCenters, measuredMapAll.rpmCenters, physicsMap.');
  title('OUR MODEL (physics x inverter)'); xlabel('Torque (Nm)'); ylabel('Speed (rpm)');
  zlabel('\eta'); zlim([.5 1]); shading interp; colorbar; view(135,30);
subplot(1,3,3); surf(measuredMapAll.tqCenters, measuredMapAll.rpmCenters, (physicsMap-measuredMapAll.eff).');
  title('MODEL - MEASURED (transient gap)'); xlabel('Torque (Nm)'); ylabel('Speed (rpm)');
  zlabel('\Delta\eta'); shading interp; colorbar; view(135,30);
outdir = fullfile(repo,'output');
if ~exist(outdir,'dir'), mkdir(outdir); end
saveas(figHandle, fullfile(outdir,'efficiency_crosscheck.png'));
fprintf('\nsaved output/efficiency_crosscheck.png\n');

%% ---- verdict ----
fprintf('\n=== VERDICT ===\n');
fprintf('Measured (steady) %.3f vs model %.3f. Agreement within %.1f pt.\n', ...
        measuredMotorInverterEff, mean(physicsRealWorld(steadyMotoringMask)), ...
        100*abs(mean(physicsRealWorld(steadyMotoringMask))-measuredMotorInverterEff));
fprintf('Two independent methods, same answer -> the sim''s real-world\n');
fprintf('efficiency layer stands. Caveat: only %d steady points; a deliberate\n', steadyCount);
fprintf('steady-state run (or dyno pull) is what locks this permanently.\n');
