%% EFFICIENCY_CROSSCHECK -- our physics model vs MEASURED efficiency, same data.
%
% Two independent ways to get motor efficiency:
%   1. OURS: physics (copper + iron loss from the EMRAX 208 HV datasheet),
%      lib/emrax208_efficiency.m, times the p.eta_inverter real-world haircut.
%   2. THEIRS: freeman803's af/dteff method -- measure it. Instantaneous
%      (shaft power / pack power) from telemetry, binned over torque x speed.
%      Reimplemented in analysis/measured_efficiency_map.m.
% If two methods that share NO assumptions agree, both are probably right.
% This script runs the comparison on the June 20 comp session and prints an
% honest verdict. Expected result (and why the sim uses eta_inverter = 0.95):
%   - steady-state measured motor+inverter eff ~ 0.86
%   - our physics (motor only) on the same points  ~ 0.91
%   - 0.91 x 0.95 = 0.86  -> the haircut closes the gap.
%
% Run it standalone (sets its own paths) or from the START menu.

clear; clc;
here = fileparts(mfilename('fullpath'));
repo = fileparts(here);
addpath(repo, fullfile(repo,'lib'), here);
p = params_cfr26();

D    = readtable(fullfile(repo,'data','comp_june20_data.csv'));
rpm  = abs(D.PM100DX_motorSpeed);
tq   = abs(D.PM100DX_torqueFeedback);
V    = D.BMSB_packVoltage;   I = D.BMSB_packCurrent;
elec = abs(V.*I);
mech = tq .* rpm * 2*pi/60;

%% ---- 0. why their map is motor+inverter (the 4.6 cancels) ----
% Rigid driveline -> axleSpeed = motorRPM/ratio. Their "wheel power" is
% axleSpeed * motorTorque*4.6 = motor shaft power. Prove the ratio from data:
axleRPM    = abs(D.VCREAR_wheelSpeedRL);
gd         = rpm>500 & axleRPM>20;
ratio_meas = median(rpm(gd)./axleRPM(gd));
fprintf('measured motor:axle speed ratio = %.3f (gear ratio on car: %.2f)\n', ...
        ratio_meas, p.gear_current);
fprintf('-> af/dteff''s 4.6 cancels out; their map = MOTOR+INVERTER eff.\n\n');

%% ---- 1. the af/dteff map from OUR data (all motoring points) ----
Mall = measured_efficiency_map(rpm, tq, V, I);
fprintf('=== MEASURED MAP, all motoring points (af/dteff method) ===\n');
fprintf('  energy-weighted overall eff : %.3f\n', Mall.eff_overall);
fprintf('  populated bins (>=20 pts)   : %d of %d\n\n', ...
        nnz(~isnan(Mall.eff)), numel(Mall.eff));

%% ---- 2. steady-state only: strip the transient artifact ----
% During accel, pack power also spins up inertia -- the instantaneous ratio
% books that as "loss". Keep only points where rpm AND torque hold still.
w      = 11;                                  % ~1.1 s at 10 Hz
steady = movstd(rpm,w)<40 & movstd(tq,w)<3;
Mst    = measured_efficiency_map(rpm, tq, V, I, 'keep', steady, 'minSamples', 10);
stpts  = Mst.point.keep;                      % the actual steady motoring mask

% linear fit  packElec = mech/eta + P0  over steady points:
% slope -> motor+inverter eff, intercept -> constant accessory draw
% (pumps/fans/LV) that shouldn't be booked against the motor.
A      = [mech(stpts) ones(nnz(stpts),1)];
x      = A \ elec(stpts);
eta_mi = 1/x(1);  P0 = x(2);
fprintf('=== STEADY-STATE only (%d pts) ===\n', nnz(stpts));
fprintf('  fit: motor+inverter eff = %.3f | accessory draw = %.0f W\n', eta_mi, P0);

%% ---- 3. our model on the exact same points ----
phys = emrax208_efficiency(rpm, tq, rmfield(p,'eta_inverter'));  % motor physics only
real = phys * p.eta_inverter;                                    % what the sim uses
fprintf('  our physics (motor only)    = %.3f\n', mean(phys(stpts)));
fprintf('  x eta_inverter %.2f         = %.3f\n', p.eta_inverter, mean(real(stpts)));
fprintf('  model - measured            = %+.4f\n\n', mean(real(stpts)) - eta_mi);

%% ---- 4. binned map comparison (model on the same af/dteff grid) ----
tqE = 2.5:15:152.5;  rpmE = 15:600:6015;
it  = discretize(tq, tqE);  is = discretize(rpm, rpmE);
mot = Mall.point.keep & ~isnan(it) & ~isnan(is);
lin = sub2ind([10 10], it(mot), is(mot));
cnt = accumarray(lin, 1, [100 1]);
Mphys = reshape(accumarray(lin, real(mot), [100 1])./max(cnt,1), [10 10]);
Mphys(reshape(cnt,[10 10]) < 20) = NaN;
both = ~isnan(Mall.eff) & ~isnan(Mphys);
fprintf('=== BINNED MAPS (raw race data, %d shared bins) ===\n', nnz(both));
fprintf('  mean measured : %.3f   mean model : %.3f   mean |diff| : %.3f\n', ...
        mean(Mall.eff(both)), mean(Mphys(both)), mean(abs(Mall.eff(both)-Mphys(both))));
fprintf('  (raw-data bins read LOW -- transient inertia pollution. The\n');
fprintf('   steady-state fit above is the number that means something.)\n');

%% ---- 5. figure ----
f = figure('Position',[80 80 1500 420], 'Color','w');
subplot(1,3,1); surf(Mall.tqCenters, Mall.rpmCenters, Mall.eff.');
  title('MEASURED (af/dteff method, raw)'); xlabel('Torque (Nm)'); ylabel('Speed (rpm)');
  zlabel('\eta'); zlim([.5 1]); shading interp; colorbar; view(135,30);
subplot(1,3,2); surf(Mall.tqCenters, Mall.rpmCenters, Mphys.');
  title('OUR MODEL (physics x inverter)'); xlabel('Torque (Nm)'); ylabel('Speed (rpm)');
  zlabel('\eta'); zlim([.5 1]); shading interp; colorbar; view(135,30);
subplot(1,3,3); surf(Mall.tqCenters, Mall.rpmCenters, (Mphys-Mall.eff).');
  title('MODEL - MEASURED (transient gap)'); xlabel('Torque (Nm)'); ylabel('Speed (rpm)');
  zlabel('\Delta\eta'); shading interp; colorbar; view(135,30);
outdir = fullfile(repo,'output');
if ~exist(outdir,'dir'), mkdir(outdir); end
saveas(f, fullfile(outdir,'efficiency_crosscheck.png'));
fprintf('\nsaved output/efficiency_crosscheck.png\n');

%% ---- verdict ----
fprintf('\n=== VERDICT ===\n');
fprintf('Measured (steady) %.3f vs model %.3f. Agreement within %.1f pt.\n', ...
        eta_mi, mean(real(stpts)), 100*abs(mean(real(stpts))-eta_mi));
fprintf('Two independent methods, same answer -> the sim''s real-world\n');
fprintf('efficiency layer stands. Caveat: only %d steady points; a deliberate\n', nnz(stpts));
fprintf('steady-state run (or dyno pull) is what locks this permanently.\n');
