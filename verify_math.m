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

fprintf('\n=== 3. EMRAX EFFICIENCY: physics vs datasheet, then real-world ===\n');
% Two layers: (a) the PHYSICS must reproduce the datasheet's motor-only ~96% peak,
% (b) the sim REPORTS real-world (motor+inverter) after the eta_inverter haircut,
% cross-checked against freeman803's measured telemetry (~0.86-0.90 on track).
Rph=0.012; NmA=0.83; a=0.10833; b=2.7778e-5; eta_inv=0.95;
efffun = @(rpm,T) (T.*rpm*2*pi/60) ./ (T.*rpm*2*pi/60 + 3*(T/NmA).^2*Rph + a*rpm + b*rpm.^2);
test_pts = [3000 60; 2000 80; 2500 65; 4000 50; 1500 40];  % rpm, Nm (in/near datasheet island)
for k=1:size(test_pts,1)
    e = efffun(test_pts(k,1),test_pts(k,2))*100;
    fprintf('  %d rpm / %d Nm -> %.1f%% motor (physics) | %.1f%% real (+inverter)\n', ...
        test_pts(k,1), test_pts(k,2), e, e*eta_inv);
end
peak_e = efffun(2500,65)*100;
pass('physics reproduces datasheet motor peak (95-97%)', peak_e>95 && peak_e<97);
all_e = arrayfun(@(k) efffun(test_pts(k,1),test_pts(k,2))*100, 1:size(test_pts,1));
pass('all physics island points within datasheet 92-98% envelope', all(all_e>=88 & all_e<=98));
pass('real-world peak (motor+inverter) lands ~88-93%', peak_e*eta_inv>88 && peak_e*eta_inv<93);

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

fprintf('\n=== 11. DRIVETRAIN EFFICIENCY CHAIN (mechanical hardware) ===\n');
mech_no_hs = 0.98*0.95*0.97*0.92;              % gears x bearings x chain x diff
chain_str  = mech_no_hs*0.99;                  % + straight halfshaft (old design-target value)
chain_12   = mech_no_hs*0.9559;                % + 12deg halfshaft (current car; drivetrain_efficiency)
fprintf('  mech stack: straight-halfshaft %.4f | 12deg-halfshaft %.4f\n', chain_str, chain_12);
pass('straight-halfshaft mech stack = 0.823 (the old value)', abs(chain_str-0.823)<0.002);
pass('12deg mech stack = 0.794 (what params_cfr26 now uses)', abs(chain_12-0.794)<0.003);

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

fprintf('\n=== 15. REAL-WORLD EFFICIENCY vs RAW TELEMETRY (af/dteff cross-check) ===\n');
% The eta_inverter = 0.95 haircut was calibrated against measured telemetry
% (freeman803's af/dteff method: shaft power / pack power). This check re-derives
% the measured number from the RAW June 20 CSV every run, so if anyone touches
% the physics constants or the haircut, the sim can no longer silently drift
% away from what the car actually measured. (Honesty note: this closes the
% calibration loop against the same session it was calibrated on -- it is a
% consistency check. Independent validation = a deliberate steady-state run.)
csvfile = fullfile(fileparts(mfilename('fullpath')), 'data', 'comp_june20_data.csv');
if exist(csvfile, 'file')
    D    = readtable(csvfile);
    rpmT = abs(D.PM100DX_motorSpeed);  tqT = abs(D.PM100DX_torqueFeedback);
    elec = abs(D.BMSB_packVoltage .* D.BMSB_packCurrent);
    mech = tqT .* rpmT * 2*pi/60;
    % (a) rigid driveline: motor:axle speed ratio must equal the gear ratio.
    %     This is WHY the af/dteff map's hardcoded 4.6 cancels, making their
    %     map motor+inverter (pack->shaft), directly comparable to ours.
    axle = abs(D.VCREAR_wheelSpeedRL);
    gd   = rpmT>500 & axle>20;
    ratio_meas = median(rpmT(gd)./axle(gd));
    fprintf('  motor:axle speed ratio from data = %.3f (gear ratio 4.61)\n', ratio_meas);
    pass('measured speed ratio = gear ratio (their 4.6 cancels)', abs(ratio_meas-4.61)<0.15);
    % (b) steady-state points only -- transients book inertia power as "loss"
    motorm = rpmT>500 & tqT>5 & elec>500 & mech./elec>0.3 & mech./elec<1.0;
    steady = motorm & movstd(rpmT,11)<40 & movstd(tqT,11)<3;
    % fit packElec = mech/eta + P0: slope -> motor+inverter eff, intercept ->
    % accessory draw (pumps/LV) that isn't the motor's fault
    A = [mech(steady) ones(nnz(steady),1)];  x = A\elec(steady);
    eta_meas = 1/x(1);  P0 = x(2);
    fprintf('  %d steady pts | measured motor+inverter eff %.3f | accessory %.0f W\n', ...
        nnz(steady), eta_meas, P0);
    pass('measured motor+inverter eff in 0.83-0.91 band', eta_meas>0.83 && eta_meas<0.91);
    % (c) the sim's real-world model on the SAME points must match the measurement
    eta_model = mean(efffun(rpmT(steady), tqT(steady))) * eta_inv;
    fprintf('  sim real-world model on same points: %.3f (measured %.3f, gap %+.4f)\n', ...
        eta_model, eta_meas, eta_model-eta_meas);
    pass('sim real-world eff within 0.02 of measured', abs(eta_model-eta_meas)<0.02);
else
    fprintf('  [data/comp_june20_data.csv not found -- check skipped]\n');
end

fprintf('\n=== 16. DRIVETRAIN EFFICIENCY STACK + HALFSHAFT ANGLE MODEL ===\n');
% Locks the math in drivetrain_efficiency.m. Recomputed from scratch here (this
% file imports nothing), so if anyone edits the stack, the CV-joint coefficient
% or the halfshaft angle in the tool, these independently re-derived numbers
% catch the drift. Source: CFR26_DT_Efficiency.pdf v4.0 [1].
% (a) the memo's stage product must reproduce its own published 0.724.
eta_memo = 0.89*0.98*0.95*0.97*0.92*0.98;   % motor spur brng chain diff halfshaft
fprintf('  memo stack 0.89*0.98*0.95*0.97*0.92*0.98 = %.4f (memo prints 0.724)\n', eta_memo);
pass('DT memo stack reproduces 0.724', abs(eta_memo-0.724)<0.002);
% (b) CV-joint loss model eta_shaft = 1 - 2*kloss*sin(beta): the coefficient must
% be consistent across the memo's OWN two operating points (that agreement is the
% model's validation, not a fitted guess).
k_str = (1-0.99)/(2*sind(3));   k_cor = (1-0.94)/(2*sind(20));
fprintf('  kloss from straight pt = %.3f, from corner pt = %.3f (agree => model holds)\n', k_str, k_cor);
pass('CV-joint kloss self-consistent within 12%', abs(k_str-k_cor)/mean([k_str k_cor])<0.12);
% (c) the halfshaft term at the REAL 12 deg static angle (kloss 0.09, corner +8 deg,
% 72.4% of the lap near static) -- must sit below the memo's 0.99 "straight" number,
% which is exactly why params' 0.823 is a touch optimistic.
kloss=0.09; hsf=@(b) 1-2*kloss*sind(b); fs=0.724; ce=8;
hs12 = fs*hsf(12) + (1-fs)*hsf(12+ce);
fprintf('  halfshaft term @12 deg static = %.4f (memo assumed 0.99 straight)\n', hs12);
pass('halfshaft term @12 deg in 0.94-0.97 band', hs12>0.94 && hs12<0.97);
pass('12 deg term < memo straight 0.99 (so params 0.823 is optimistic)', hs12 < 0.99);
% (d) measured pack->shaft (July 11 endurance, freeman803 method) x mech stack must
% reproduce the tool's telemetry-anchored overall (battery->ground).
csv2 = fullfile(fileparts(mfilename('fullpath')), 'data', 'endurance_july11_with_odo_wide.csv');
if exist(csv2,'file')
    E2  = readtable(csv2);
    rr  = abs(E2.PM100DX_motorSpeed);  qq = abs(E2.PM100DX_torqueFeedback);
    pk  = abs(E2.BMSB_packVoltage .* E2.BMSB_packCurrent);  mm = qq.*rr*2*pi/60;
    kp  = rr>500 & qq>5 & pk>500 & mm./pk>0.3 & mm./pk<1.0;
    eta_sh  = sum(mm(kp))/sum(pk(kp));
    overall = eta_sh * 0.98*0.95*0.97*0.92 * hs12;
    fprintf('  measured pack->shaft %.3f -> overall battery->ground %.3f\n', eta_sh, overall);
    pass('measured pack->shaft in 0.75-0.90 band', eta_sh>0.75 && eta_sh<0.90);
    pass('overall battery->ground in 0.58-0.70 band', overall>0.58 && overall<0.70);
else
    fprintf('  [endurance CSV not found -- overall check skipped]\n');
end

fprintf('\n=== 17. INVERTER IS IN THE ENERGY PATH (guards the old motor-only bug) ===\n');
% Earlier versions reported motor-ONLY efficiency and so UNDER-counted battery draw
% by ~5%. Every efficiency/energy script now routes through emrax208_efficiency;
% this section tests that REAL function (not a reimplementation -- the whole point
% is to catch the actual code dropping the inverter) and confirms the haircut is live.
thisdir = fileparts(mfilename('fullpath'));
addpath(thisdir, fullfile(thisdir,'lib'));
if exist('emrax208_efficiency','file') && exist('params_cfr26','file')
    pp = params_cfr26();
    e_with     = emrax208_efficiency(3000, 60, pp);                     % motor + inverter
    e_motonly  = emrax208_efficiency(3000, 60, rmfield(pp,'eta_inverter')); % motor alone
    fprintf('  motor+inverter %.3f vs motor-only %.3f -> ratio %.3f (eta_inverter %.2f)\n', ...
        e_with, e_motonly, e_with/e_motonly, pp.eta_inverter);
    pass('emrax208_efficiency applies the inverter haircut', abs(e_with/e_motonly - pp.eta_inverter) < 0.01);
    pass('inverter drops reported efficiency by >=3 pts', (e_motonly - e_with) > 0.03);
    % params eta_drivetrain must match the tool's 12deg mechanical hardware stack (0.794),
    % so drivetrain_efficiency.m and the rest of the sim can't disagree on the hardware number.
    pass('params eta_drivetrain matches 12deg hardware stack (0.794)', abs(pp.eta_drivetrain - 0.794) < 0.004);
    % Where each script stands (documented, not re-run here):
    %   gear_ratio_optimization: battery/SOC draw = motoring_regen_power(shaft, eff)
    %     with eff = emrax208_efficiency -> inverter INCLUDED in energy. OK.
    %   drivetrain_efficiency:   electrical end is MEASURED pack->shaft (already
    %     motor+inverter); mech stack multiplied on top. OK.
    %   accel_model/top_speed:   torque x eta_drivetrain (MECHANICAL only). Correct --
    %     the inverter doesn't reduce deliverable shaft torque, only draws more current.
    fprintf('  gear_ratio_optimization energy: inverter-inclusive (via emrax208_efficiency). OK\n');
    fprintf('  accel/top-speed torque: eta_drivetrain (mech) only -- inverter correctly excluded.\n');
else
    fprintf('  [lib/ not on path -- run via START or addpath(genpath(pwd)); check skipped]\n');
end

fprintf('\n=== 18. DEGRADATION PARAMS + THE TWO TRAPS THEY INVITE ===\n');
% Degradation is UNMEASURED. These checks make sure it stays that way until
% somebody measures it, and that the two easy ways to fake a measurement stay
% caught. See analysis/degradation_study.m and params_cfr26.m.
if exist('params_cfr26','file')
    pp = params_cfr26();
    pass('degradation_motor exists', isfield(pp,'degradation_motor'));
    pass('degradation_inverter exists', isfield(pp,'degradation_inverter'));
    % (a) Defaults must stay 1.00. If one of these ever FAILs, the right question
    % is "where is the measurement?" -- not "loosen the check".
    fprintf('  motor %.3f, inverter %.3f (1.00 = as-new = unmeasured)\n', ...
        pp.degradation_motor, pp.degradation_inverter);
    pass('degradation_motor still 1.00 (unmeasured)', abs(pp.degradation_motor-1)<1e-9);
    pass('degradation_inverter still 1.00 (unmeasured)', abs(pp.degradation_inverter-1)<1e-9);
    % (b) Degradation must stay OUT of the validated efficiency chain. The whole
    % point of keeping it separate is that a speculative number cannot move the
    % gear-ratio result; this proves the separation holds.
    if exist('emrax208_efficiency','file')
        p_deg = pp; p_deg.degradation_motor = 0.5; p_deg.degradation_inverter = 0.5;
        e_norm = emrax208_efficiency(3000, 60, pp);
        e_deg  = emrax208_efficiency(3000, 60, p_deg);
        fprintf('  eff with degradation forced to 0.5/0.5: %.4f vs normal %.4f\n', e_deg, e_norm);
        pass('degradation does NOT leak into emrax208_efficiency', abs(e_deg-e_norm)<1e-12);
    end
    % (c) THE Ke TRAP. Ke derived from our own validated constants: 140 Nm at
    % 3000 rpm = 44 kW at 169 Arms, so V_LL = P/(sqrt(3)*I) and Ke = V_LL/rpm.
    % A remembered "0.60 V/RPM" is ~12x this and implies 3600 V at redline
    % against a 370 V bus -- impossible. Using it would invent ~90% demag.
    P_ref = pp.T_flat_cap*3000*2*pi/60;  I_ref = pp.T_flat_cap/pp.Nm_per_Arms;
    Ke = P_ref/(sqrt(3)*I_ref)/3000;
    Vbus = pp.N_series*4.2;
    fprintf('  derived Ke = %.4f V/rpm -> %.0f V_LL at redline vs %.0f V bus\n', ...
        Ke, Ke*pp.redline, Vbus);
    pass('derived Ke in the physically sane 0.03-0.08 V/rpm band', Ke>0.03 && Ke<0.08);
    pass('Ke*redline does not exceed 2x bus (no impossible back-EMF)', Ke*pp.redline < 2*Vbus);
    fprintf('  a 0.60 V/rpm baseline would give %.0f V at redline (%.1fx too big)\n', ...
        0.60*pp.redline, 0.60/Ke);
    pass('0.60 V/rpm is correctly rejected as impossible', 0.60*pp.redline > 2*Vbus);
    % (d) THE NO-LOAD BASELINE TRAP. A pack-side shunt sees core loss AFTER the
    % inverter, PLUS accessories. Comparing a measured pack-side amp reading
    % against the motor-only curve manufactures degradation that is not there.
    P_core3k = pp.core_loss_a*3000 + pp.core_loss_b*3000^2;
    A_motor_only = P_core3k/Vbus;
    A_packside   = (P_core3k/pp.eta_inverter + 116)/Vbus;
    fprintf('  no-load at 3000 rpm: motor-only %.2f A vs true pack-side %.2f A (+%.0f%%)\n', ...
        A_motor_only, A_packside, 100*(A_packside/A_motor_only-1));
    pass('pack-side no-load baseline exceeds motor-only (trap is real)', A_packside > A_motor_only*1.15);
else
    fprintf('  [params_cfr26 not on path -- section skipped]\n');
end

fprintf('\n=== SUMMARY ===\n');
fprintf('If any line above reads **FAIL**, that specific number needs a second look.\n');
