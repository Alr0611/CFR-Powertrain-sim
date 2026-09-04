%% What actually changes with ratio: motor CURRENT, HEAT and REDLINE headroom.
clear; p = params_cfr26();
D = readtable('data/comp_june20_data.csv');
wheelRpm = mean([D.VCFRONT_wheelSpeedFL,D.VCFRONT_wheelSpeedFR,D.VCREAR_wheelSpeedRL,D.VCREAR_wheelSpeedRR],2,'omitnan');
mRpm=D.PM100DX_motorSpeed; mTq=D.PM100DX_torqueFeedback;
if median(mTq(mRpm>1000),'omitnan')<0, mTq=-mTq; end
mot = mRpm>500 & wheelRpm>50 & mTq>2;
wR=wheelRpm(mot); wT=mTq(mot)*p.gear_current;
fprintf('redline %d rpm | Kt-based current, copper loss ~ I^2 ~ T^2\n\n',p.redline);
fprintf('%-8s | %-8s %-9s %-9s | %-9s %-9s %-9s | %-9s %-9s\n', ...
 'ratio','maxRPM','headroom','%overRL','T_rms','T_peak','I2R rel','T_p95','%>cont');
res=[];
Tcont = 80;   % EMRAX 208 continuous torque, DATASHEET
for N2=26:34
  g=2.0*N2/13; rN=wR*g; tN=wT/g;
  over = 100*mean(rN>p.redline);
  Trms=sqrt(mean(tN.^2)); Tpk=max(tN); Tp95=prctile(tN,95);
  res(end+1,:)=[g,max(rN),p.redline-max(rN),over,Trms,Tpk,Trms^2,Tp95,100*mean(tN>Tcont)];
  fprintf('%-8.4f | %-8.0f %+-9.0f %-8.2f%% | %-9.1f %-9.1f %-9.0f | %-9.1f %-8.1f%%\n', ...
    g,max(rN),p.redline-max(rN),over,Trms,Tpk,Trms^2,Tp95,100*mean(tN>Tcont));
end
b=res(res(:,1)>4.61 & res(:,1)<4.62,:);
fprintf('\nvs current 4.6154:\n');
for i=1:size(res,1)
  fprintf('  %.4f : rpm headroom %+5.0f | T_rms %+5.1f%% | copper loss %+6.1f%% | time over %gNm %+5.1f pts\n', ...
    res(i,1), res(i,3)-b(3), 100*(res(i,5)/b(5)-1), 100*(res(i,7)/b(7)-1), Tcont, res(i,9)-b(9));
end
T=array2table(res,'VariableNames',{'ratio','max_rpm','rpm_headroom','pct_over_redline','T_rms_Nm', ...
  'T_peak_Nm','copper_loss_rel','T_p95_Nm','pct_above_cont_torque'});
writetable(T,'output/gear_thermal_headroom.csv');
