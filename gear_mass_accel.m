%% -1.3 kg/wheel projected mass loss, across the buildable ratios.
%% Uses accel_tc_core (TC active, the model that matches the 150 Nm traction-limited case).
%% NOTE: accel_tc_core lumps only the DRIVEN axle inertia (2 wheels, line 20), so the
%% rotational half of the gain here is understated by the two front wheels. Translational
%% mass (4 x dkg off m_car) is fully counted. Read the numbers as a LOWER BOUND.
%% Two inertia assumptions for where the mass comes off:
%%   EDGE dI = dm*r^2 (tyre/rim, k=1)   DIST dI = k^2*dm*r^2 (k=0.60, conservative)
clear; p = params_cfr26();
tc = struct('enabled',true,'target_slip',0.10,'kp',0.470,'ki',0.0,'kd',0.110, ...
            'ilim',0.0,'maxlim',0.75,'ileak_ms',500,'rate_hz',100, ...
            'speed_gate',0.5,'emulate_firmware_pure_p',true);
ty.mu_scale = 0.853;
DKG = [0, 0.65, 1.3];
fprintf('base: m_car %.1f kg, m_wheel %.2f kg, I_wheel %.5f kgm2, r %.4f m\n', ...
    p.m_car, p.m_wheel, p.I_wheel, p.r_wheel);
fprintf('-1.3 kg/wheel = -%.1f kg on the car (%.1f%% of mass)\n\n', 4*1.3, 100*4*1.3/p.m_car);
res=[];
for mode = ["EDGE","DIST"]
  fprintf('=== %s ===\n%-8s |', mode, 'ratio');
  for d = DKG, fprintf(' %9s', sprintf('-%.2fkg',d)); end
  fprintf(' | %9s\n','gain@1.3');
  for N2 = [26 27 28 29 30 31 32]
    g = 2.0*N2/13; ts = zeros(size(DKG));
    for k = 1:numel(DKG)
      d = DKG(k); ps = p;
      ps.m_car = p.m_car - 4*d;
      if mode == "EDGE", ps.I_wheel = p.I_wheel - d*p.r_wheel^2;
      else,              ps.I_wheel = p.I_wheel - p.kFactor^2*d*p.r_wheel^2; end
      R = accel_tc_core(ps, tc, ty, g); ts(k) = R.t75;
    end
    fprintf('%-8.4f |', g);
    for k = 1:numel(DKG), fprintf(' %9.4f', ts(k)); end
    fprintf(' | %+9.4f\n', ts(end)-ts(1));
    if mode=="EDGE", res(end+1,:)=[g ts ts(end)-ts(1)]; end
  end
  fprintf('\n');
end
T=array2table(res,'VariableNames',{'ratio','t75_base','t75_m065','t75_m130','gain_s'});
writetable(T,'output/gear_mass_accel.csv');
fprintf('Saved output/gear_mass_accel.csv\n');
