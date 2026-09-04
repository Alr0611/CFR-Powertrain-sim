%% Where the rpm sits across a lap, and efficiency at NON-PEAK points, per ratio.
clear; p = params_cfr26();
D = readtable('data/comp_june20_data.csv');
wheelRpm = mean([D.VCFRONT_wheelSpeedFL,D.VCFRONT_wheelSpeedFR,D.VCREAR_wheelSpeedRL,D.VCREAR_wheelSpeedRR],2,'omitnan');
mRpm=D.PM100DX_motorSpeed; mTq=D.PM100DX_torqueFeedback;
if median(mTq(mRpm>1000),'omitnan')<0, mTq=-mTq; end
mot = mRpm>500 & wheelRpm>50 & mTq>2;
wR=wheelRpm(mot); wT=mTq(mot)*p.gear_current;   % wheel-referenced
rpmGrid=100:25:p.redline; Tenv=arrayfun(@(r)motor_peak_torque(r,p),rpmGrid);
knee=rpmGrid(find(Tenv<p.T_flat_cap-0.5,1));
fprintf('knee = %d rpm | redline = %d rpm | flat cap = %g Nm\n\n',knee,p.redline,p.T_flat_cap);
fprintf('%4s %8s | %7s %7s %7s %7s | %7s %7s %7s | %7s %7s %7s %7s\n', ...
 'N2','ratio','medRPM','p90RPM','maxRPM','%>knee','%>90%rl','%<40%rl','%2-4k','avgEff','effLo','effMid','effHi');
res=[];
for N2=26:34
  g=2.0*N2/13; rN=wR*g; tN=wT/g;
  env=arrayfun(@(r)motor_peak_torque(min(r,p.redline),p),rN);
  infeas=(rN>p.redline)|(tN>env+1e-9);
  eN=emrax208_efficiency(rN,tN,p); eN(infeas)=NaN;
  % efficiency split by how hard the point is working (non-peak vs peak)
  q=prctile(tN,[33 66]);
  lo=tN<=q(1); mid=tN>q(1)&tN<=q(2); hi=tN>q(2);
  fprintf('%4d %8.4f | %7.0f %7.0f %7.0f %6.1f%% %6.1f%% %6.1f%% %6.1f%% | %6.2f %6.2f %6.2f %6.2f\n', ...
    N2,g,median(rN),prctile(rN,90),max(rN), 100*mean(rN>knee), 100*mean(rN>0.9*p.redline), ...
    100*mean(rN<0.4*p.redline), 100*mean(rN>2000&rN<4000), ...
    100*mean(eN,'omitnan'),100*mean(eN(lo),'omitnan'),100*mean(eN(mid),'omitnan'),100*mean(eN(hi),'omitnan'));
  res(end+1,:)=[N2,g,median(rN),prctile(rN,90),max(rN),100*mean(rN>knee),100*mean(rN>0.9*p.redline), ...
    100*mean(rN<0.4*p.redline),100*mean(rN>2000&rN<4000),100*mean(eN,'omitnan'), ...
    100*mean(eN(lo),'omitnan'),100*mean(eN(mid),'omitnan'),100*mean(eN(hi),'omitnan'),100*mean(infeas)];
end
T=array2table(res,'VariableNames',{'driven','ratio','med_rpm','p90_rpm','max_rpm','pct_above_knee', ...
 'pct_above_90pct_redline','pct_below_40pct_redline','pct_in_2k_4k','avg_eff','eff_low_torque', ...
 'eff_mid_torque','eff_high_torque','pct_infeasible'});
writetable(T,'output/gear_rpm_eff_lap.csv');
fprintf('\nSaved output/gear_rpm_eff_lap.csv\n');
