function M = measured_efficiency_map(rpm, torque, packV, packI, varargin)
%MEASURED_EFFICIENCY_MAP  Efficiency map from TELEMETRY, not physics.
%
%   M = measured_efficiency_map(rpm, torque, packV, packI)
%   M = measured_efficiency_map(..., 'keep', steadyMask, 'minSamples', 30)
%
% WHERE THIS COMES FROM
%   This is the method from freeman803/Full-Car-Simulation, branch
%   user/af/dteff (Drive_efficiency.m): instantaneous efficiency =
%   mechanical power / pack electrical power, averaged into a 10x10
%   torque-vs-speed grid. Their file builds the grid with 100 hand-written
%   masks; this is the same math vectorized, so the grid is configurable
%   and reusable against any telemetry export.
%
% ONE IMPORTANT HONESTY NOTE (verified against our June 20 comp data)
%   The driveline is rigid, so axle speed = motor rpm / gear ratio. Their
%   "wheel power" = axleSpeed * (motorTorque * 4.6) -- the ratio cancels and
%   what's left is MOTOR SHAFT power. So this map is MOTOR + INVERTER
%   efficiency (pack -> shaft). It does NOT see the gearbox/chain/diff
%   losses (that's p.eta_drivetrain, a separate number).
%
% SECOND HONESTY NOTE
%   Race telemetry is nearly all transients. During accel, pack power also
%   feeds rotor/wheel inertia, which this ratio wrongly books as "loss";
%   during regen-free coasting the reverse. Bins built from raw race data
%   read LOW and flat (we measured ~0.82 raw vs ~0.86 steady-state).
%   Pass a steady-state mask via 'keep' when you want truth, and treat the
%   unmasked map as a duty-cycle-weighted picture, not a motor property.
%
% OUTPUT struct M:
%   .eff          10x10 (or custom) map, rows = torque bin, cols = speed band,
%                 NaN where a bin has < minSamples points
%   .n            samples per bin
%   .tqCenters    torque bin centers (Nm)
%   .rpmCenters   speed band centers (rpm)
%   .eff_overall  energy-weighted overall eff, sum(mech)/sum(elec) -- the
%                 single number the af/dteff script prints as "mean eff"
%   .point.eff    per-sample instantaneous efficiency (all samples)
%   .point.keep   the motoring mask actually used

ip = inputParser;
ip.addParameter('tqEdges',  2.5:15:152.5);   % af/dteff grid: 10 torque bins
ip.addParameter('rpmEdges', 15:600:6015);    % af/dteff grid: 10 speed bands
ip.addParameter('minSamples', 20);           % below this a bin is noise -> NaN
ip.addParameter('keep', []);                 % optional extra mask (steady-state)
ip.parse(varargin{:});
o = ip.Results;

motorSpeed  = abs(rpm(:));  motorTorque = abs(torque(:));
packPower       = abs(packV(:) .* packI(:));        % pack electrical power, W
mechanicalPower = motorTorque .* motorSpeed * 2*pi/60;   % motor shaft power, W
instantEfficiency = mechanicalPower ./ max(packPower, 1e-6);

% clean motoring points only: real speed, real load, physical efficiency.
% MOTORING FILTER -- TODO (design review, STUBBED): driver-intent (>15% accelerator)
% needs VCFRONT_acceleratorPosition, which the efficiency exports do not carry
% (needs DAQ access). Keep the existing motorSpeed>500 & torque>5 gate; do not fake it.
motoringMask = motorSpeed>500 & motorTorque>5 & packPower>500 & instantEfficiency>0.3 & instantEfficiency<1.0;
if ~isempty(o.keep), motoringMask = motoringMask & logical(o.keep(:)); end

numTorqueBins = numel(o.tqEdges)-1;  numSpeedBands = numel(o.rpmEdges)-1;
torqueBin = discretize(motorTorque, o.tqEdges);    % which torque bin each sample is in
speedBand = discretize(motorSpeed,  o.rpmEdges);   % which speed band
binnedMask = motoringMask & ~isnan(torqueBin) & ~isnan(speedBand);

linearIndex = sub2ind([numTorqueBins numSpeedBands], torqueBin(binnedMask), speedBand(binnedMask));
binCount    = accumarray(linearIndex, 1,                          [numTorqueBins*numSpeedBands 1]);
binEffSum   = accumarray(linearIndex, instantEfficiency(binnedMask), [numTorqueBins*numSpeedBands 1]);
binEffMean  = binEffSum ./ max(binCount, 1);
binEffMean(binCount < o.minSamples) = NaN;

M.eff         = reshape(binEffMean, [numTorqueBins numSpeedBands]);
M.n           = reshape(binCount,   [numTorqueBins numSpeedBands]);
M.tqCenters   = (o.tqEdges(1:end-1)  + o.tqEdges(2:end))  / 2;
M.rpmCenters  = (o.rpmEdges(1:end-1) + o.rpmEdges(2:end)) / 2;
M.eff_overall = sum(mechanicalPower(motoringMask)) / sum(packPower(motoringMask));
M.point.eff   = instantEfficiency;
M.point.keep  = motoringMask;
end
