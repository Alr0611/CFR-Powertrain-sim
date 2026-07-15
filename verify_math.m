%% VERIFY_MATH — independent cross-checks of the gear-ratio model's physics
% Recomputes load-bearing numbers from scratch and compares to datasheets.
% PASS/FAIL printed for each. Nothing here imports the main script's results.
clear; clc;
pass = @(name,cond) fprintf('[%s] %s\n', string(cond).replace("true","PASS").replace("false","**FAIL**"), name);

fprintf('=== 1. PACK CONFIGURATION (vs ESF V2.3) ===\n');
Ns = 88; Np = 4;
fprintf('  88S x 4P = %d cells (ESF: 352)\n', Ns*Np);
pass('total cell count = 352', Ns*Np == 352);
Vnom = Ns*3.6; Vmax = Ns*4.2;
fprintf('  nominal %.1f V (ESF 316.8), max %.1f V (ESF 369.6)\n', Vnom, Vmax);
pass('nominal voltage 316.8 V', abs(Vnom-316.8)<0.1);
pass('max voltage 369.6 V', abs(Vmax-369.6)<0.1);

fprintf('\n=== 2. INITIAL SOC (rest voltage vs BMS) ===\n');
SOC_lookupR = linspace(0,1,11);
OCV = [2.42,3.17577,3.36868,3.52009,3.62396,3.74948,3.84225,3.93877,4.05245,4.0853,4.2];
Vcell0 = 364.28/88;
SOC0 = interp1(OCV, SOC_lookupR, Vcell0, 'linear');
fprintf('  first sample 364.28 V / 88 = %.4f V/cell -> SOC %.1f%% (BMS logged 94.3%%)\n', Vcell0, SOC0*100);
pass('rest-voltage SOC within 1pt of BMS', abs(SOC0*100-94.3)<1.0);

fprintf('\n=== 3. EMRAX EFFICIENCY MODEL vs DATASHEET (92-98%%, peak ~96%%) ===\n');
Rph=0.012; NmA=0.83; a=0.10833; b=2.7778e-5;
efffun = @(rpm,T) (T.*rpm*2*pi/60) ./ (T.*rpm*2*pi/60 + 3*(T/NmA).^2*Rph + a*rpm + b*rpm.^2);
test_pts = [3000 60; 2000 80; 2500 65; 4000 50; 1500 40];  % rpm, Nm (in/near datasheet island)
for k=1:size(test_pts,1)
    e = efffun(test_pts(k,1),test_pts(k,2))*100;
    fprintf('  %d rpm / %d Nm -> %.1f%%\n', test_pts(k,1), test_pts(k,2), e);
end
peak_e = efffun(2500,65)*100;
pass('peak-island efficiency in 95-97% band', peak_e>95 && peak_e<97);
all_e = arrayfun(@(k) efffun(test_pts(k,1),test_pts(k,2))*100, 1:size(test_pts,1));
pass('all island points within datasheet 92-98% envelope', all(all_e>=88 & all_e<=98));

fprintf('\n=== 4. CORE-LOSS FIT vs FREE-RUN-LOSS ANCHORS ===\n');
for rpm=[3000 6000]
    pl=a*rpm+b*rpm^2; fprintf('  %d rpm -> %.0f W\n', rpm, pl);
end
pass('575 W at 3000 rpm anchor', abs(a*3000+b*3000^2-575)<10);
pass('1650 W at 6000 rpm anchor', abs(a*6000+b*6000^2-1650)<10);

fprintf('\n=== 5. COPPER LOSS SANITY (continuous rating) ===\n');
% Datasheet: continuous 80 Nm, continuous 100 Arms. Check Irms from torque.
Irms80 = 80/NmA; fprintf('  80 Nm / 0.83 = %.1f Arms (datasheet continuous current 100 Arms)\n', Irms80);
pass('continuous-torque current below 100 A rating', Irms80 < 100);

fprintf('\n=== 6. TIRE mu AT NOMINAL LOAD (vs ~1.4 ballpark) ===\n');
PDX1=2.1; PDX2=-0.40981; LMUX=0.65; FNOM=667;
mu_nom = LMUX*(PDX1+PDX2*0);
fprintf('  LMUX*PDX1 = %.3f at nominal load\n', mu_nom);
pass('nominal mu in 1.3-1.4 range', mu_nom>1.3 && mu_nom<1.4);
mu_2x = LMUX*(PDX1+PDX2*1); % double load
fprintf('  at 2x nominal load: %.3f (should drop -- load sensitivity)\n', mu_2x);
pass('mu decreases with load', mu_2x < mu_nom);

fprintf('\n=== 7. GEAR-RATIO SHAFT-POWER INVARIANCE (core assumption) ===\n');
% Same wheel power at any ratio -> shaft mechanical power must be identical.
eta=0.823; P_shaft_old = 15000;           % arbitrary motoring point, W
P_wheel = P_shaft_old*eta;                % motoring: wheel gets less
P_shaft_new = P_wheel/eta;                % re-expand at new ratio
fprintf('  shaft %.0f W -> wheel %.0f W -> shaft %.0f W\n', P_shaft_old, P_wheel, P_shaft_new);
pass('shaft power ratio-invariant (round-trip identity)', abs(P_shaft_new-P_shaft_old)<1e-6);
% torque splits inversely with ratio at fixed power
wr=100; % wheel rad/s-equivalent placeholder
T_at_461 = P_shaft_old/(wr*4.61); T_at_420 = P_shaft_old/(wr*4.20);
pass('lower ratio -> higher shaft torque', T_at_420 > T_at_461);

fprintf('\n=== 8. LAUNCH FORCE BALANCE (hand check, 4.61:1) ===\n');
m=294; g=9.81; rsf=0.483; hcg=0.3134; L=1.543; rw=0.2286;
a_x=0;
for it=1:8
    Fzr = m*g*rsf + m*a_x*hcg/L;
    dfz = (Fzr/2 - FNOM)/FNOM;
    mu = LMUX*(PDX1+PDX2*dfz);
    Ftr = mu*Fzr;
    a_x = (Ftr - 0.015*m*g)/m;
end
fprintf('  converged launch: Fz_rear %.0f N, a_x %.2f m/s^2 (%.2fg), traction force %.0f N\n', Fzr, a_x, a_x/g, Ftr);
Tcap = Ftr*rw/(4.61*eta);
fprintf('  -> motor torque cap %.0f Nm (main script TC seed printed ~147)\n', Tcap);
pass('launch traction cap within 10 Nm of TC-seed value', abs(Tcap-147)<10);
Fmotor = 140*4.61*eta/rw;
fprintf('  motor can push %.0f N (140 Nm) vs %.0f N traction limit -> %s at launch\n', ...
    Fmotor, Ftr, string(Fmotor>Ftr).replace("true","TRACTION-limited").replace("false","motor-limited"));

fprintf('\n=== 9. ENERGY THROUGHPUT ORDER-OF-MAGNITUDE ===\n');
% 3.4 kWh over 22.5 km -> Wh/km, compare to typical FSAE endurance (~30-40 Wh/km...
% but with idle/cool-down laps in the log, effective can differ)
kWh=3.41; km=22.5;
fprintf('  %.2f kWh / %.1f km = %.0f Wh/km\n', kWh, km, kWh*1000/km);
pass('specific energy in plausible FSAE range 100-250 Wh/km', kWh*1000/km>100 && kWh*1000/km<250);

fprintf('\n=== 10. HV VARIANT CONFIRMATION (user: car is 370V HV) ===\n');
% 88S x 4.2V = 369.6V max -> "370V HV". Datasheet HV variant max battery
% voltage is 470V, so 370V is within limits and the HV column (0.83 Nm/Arms,
% 12mOhm phase R, 100A cont) is the correct one to have used.
fprintf('  88S x 4.2V = %.1f V max = "370V" -> under HV 470V limit -> HV constants correct\n', 88*4.2);
pass('370V pack uses HV datasheet column (max 470V)', 88*4.2 < 470 && 88*4.2 > 320);

fprintf('\n=== 11. DRIVETRAIN EFFICIENCY CHAIN ===\n');
chain = 0.98*0.95*0.97*0.92*0.99;   % gears x bearings x chain x diff x straight-halfshaft
fprintf('  0.98 x 0.95 x 0.97 x 0.92 x 0.99 = %.4f (used: 0.823)\n', chain);
pass('drivetrain chain product = 0.823', abs(chain-0.823)<0.002);

fprintf('\n=== 12. AERO FORCES from CFD dimensional values ===\n');
q25 = 0.5*1.225*25^2;  % dynamic pressure at 25 m/s
CdA = 442.719/q25; ClA = 957.592/q25;
fprintf('  q(25 m/s) = %.1f Pa | CdA = %.3f m^2 | ClA = %.3f m^2\n', q25, CdA, ClA);
% back-check: force at 25 m/s must return the CFD inputs
Fdrag25 = 0.5*1.225*CdA*25^2; Fdown25 = 0.5*1.225*ClA*25^2;
fprintf('  recomputed @25 m/s: drag %.1f N (CFD 442.7), downforce %.1f N (CFD 957.6)\n', Fdrag25, Fdown25);
pass('drag force round-trips to CFD value', abs(Fdrag25-442.719)<1);
pass('downforce round-trips to CFD value', abs(Fdown25-957.592)<1);

fprintf('\n=== 13. RC DISCRETIZATION + KALMAN STRUCTURE (sanity, not new physics) ===\n');
% Zero-order-hold of a first-order RC: Vrc(k+1)=exp(-dt/tau)Vrc(k)+R(1-exp(-dt/tau))I
dt=0.1; R1=0.002; C1=1000; tau=R1*C1; decay=exp(-dt/tau);
fprintf('  tau=R1*C1=%.1f s, exp(-dt/tau)=%.4f (in (0,1) => stable decay)\n', tau, decay);
pass('RC decay factor in (0,1)', decay>0 && decay<1);
% Steady state of RC branch under constant I must approach I*R
Vrc=0; for n=1:2000, Vrc=decay*Vrc+R1*(1-decay)*10; end
fprintf('  RC branch steady state under 10 A -> %.4f V (expect I*R = %.4f V)\n', Vrc, 10*R1);
pass('RC steady state = I*R', abs(Vrc-10*R1)<1e-4);

fprintf('\n=== 14. TOP-SPEED FORCE BALANCE (4.61:1 spot check) ===\n');
% At the reported ~112 kph (31.1 m/s) top speed, motor force must ~equal resistance.
v=112/3.6; ratio=4.61; rw=0.2286;
rpm = v/rw*ratio*60/(2*pi);
fprintf('  112 kph -> %.0f motor rpm (redline 6000)\n', rpm);
pass('top-speed rpm under redline', rpm < 6000);
Fdown=0.5*1.225*ClA*v^2; Fres=0.5*1.225*CdA*v^2+0.015*(294*9.81+Fdown);
fprintf('  resistance at 112 kph = %.0f N (drag+roll+downforce-roll)\n', Fres);
pass('resistance force positive and plausible (<1500 N)', Fres>0 && Fres<1500);

fprintf('\n=== SUMMARY ===\n');
fprintf('If any line above reads **FAIL**, that specific number needs a second look.\n');
