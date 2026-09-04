%% PACK heating vs gear ratio. The 2026 endurance DNF was pack overheat, so this is
%% the axis that actually matters. Pack heat ~ I_pack^2 * R_internal.
%% Mechanical power at the wheel is ratio-INDEPENDENT for a given driving state, so
%% pack current only changes through DRIVETRAIN+MOTOR EFFICIENCY. Better efficiency
%% at the operating points = less pack current = less pack heat.
clear; p = params_cfr26();
D = readtable('data/comp_june20_data.csv');
wheelRpm = mean([D.VCFRONT_wheelSpeedFL,D.VCFRONT_wheelSpeedFR,D.VCREAR_wheelSpeedRL,D.VCREAR_wheelSpeedRR],2,'omitnan');
mRpm=D.PM100DX_motorSpeed; mTq=D.PM100DX_torqueFeedback;
if median(mTq(mRpm>1000),'omitnan')<0, mTq=-mTq; end
pV=D.BMSB_packVoltage; pI=D.BMSB_packCurrent;
if median(pI(mRpm>1000),'omitnan')<0, pI=-pI; end
mot = mRpm>500 & wheelRpm>50 & mTq>2 & pV>100 & isfinite(pI);
wR=wheelRpm(mot); wT=mTq(mot)*p.gear_current; V=pV(mot); Imeas=pI(mot);
% mechanical power at the wheel, ratio-invariant
Pmech = wT .* (wR*2*pi/60);                     % W
fprintf('MEASURED pack current: rms %.1f A, p95 %.1f A, max %.1f A, mean V %.0f\n', ...
  rms(Imeas), prctile(Imeas,95), max(Imeas), mean(V));
fprintf('Pack heat scales with I^2. Baseline = current ratio %.4f.\n\n', p.gear_current);
fprintf('%-8s | %-9s %-9s %-9s | %-10s %-11s %-11s\n','ratio','eta_mot','I_rms A','I_p95 A','I^2 rel','pack heat','vs 4.6154');
res=[];
for N2=26:34
  g=2.0*N2/13; rN=wR*g; tN=wT/g;
  env=arrayfun(@(r)motor_peak_torque(min(r,p.redline),p),rN);
  infeas=(rN>p.redline)|(tN>env+1e-9);
  eN=emrax208_efficiency(rN,tN,p);
  eN(infeas)=NaN; eN=fillmissing(eN,'nearest');
  Pelec = Pmech ./ (eN * p.eta_drivetrain * p.eta_inverter);   % W drawn from pack
  I = Pelec ./ V;
  res(end+1,:)=[g, 100*mean(eN,'omitnan'), rms(I), prctile(I,95), mean(I.^2)];
end
base = res(abs(res(:,1)-4.6154)<1e-3,5);
for i=1:size(res,1)
  fprintf('%-8.4f | %-9.2f %-9.1f %-9.1f | %-10.0f %-11.4f %+-10.2f%%\n', ...
    res(i,1),res(i,2),res(i,3),res(i,4),res(i,5),res(i,5)/base,100*(res(i,5)/base-1));
end
T=array2table(res,'VariableNames',{'ratio','motor_eff_pct','I_rms_A','I_p95_A','I_squared_mean'});
T.pack_heat_rel = T.I_squared_mean/base;
writetable(T,'output/gear_pack_thermal.csv');
fprintf('\nSaved output/gear_pack_thermal.csv\n');
