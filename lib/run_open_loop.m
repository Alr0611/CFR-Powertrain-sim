function [SOC_trace, Vs_trace] = run_open_loop(I_arr, dt_arr, rc)
%RUN_OPEN_LOOP  Open-loop 2-RC Thevenin cell model (per-cell SOC + voltage).
%   Coulomb-counts SOC and integrates two RC branches. rc must carry the
%   HPPC lookup tables, capacity Q, and initial charge SOC0.
    Nk = length(I_arr);
    SOC_trace = zeros(Nk,1); Vs_trace = zeros(Nk,1);
    SOC = rc.SOC0; Vrc1 = 0; Vrc2 = 0;
    for k = 1:Nk
        if I_arr(k) < 0   % charging branch
            Ri = interp1(rc.SOC_lookupR, rc.Ri_c, 1-SOC, 'linear', 'extrap');
            R1 = interp1(rc.SOC_lookupR, rc.R1_c, 1-SOC, 'linear', 'extrap');
            R2 = interp1(rc.SOC_lookupR, rc.R2_c, 1-SOC, 'linear', 'extrap');
            C1 = interp1(rc.SOC_lookupR, rc.C1_c, 1-SOC, 'linear', 'extrap');
            C2 = interp1(rc.SOC_lookupR, rc.C2_c, 1-SOC, 'linear', 'extrap');
        else              % discharging branch
            Ri = interp1(rc.SOC_lookupR, rc.Ri_d, 1-SOC, 'linear', 'extrap');
            R1 = interp1(rc.SOC_lookupR, rc.R1_d, 1-SOC, 'linear', 'extrap');
            R2 = interp1(rc.SOC_lookupR, rc.R2_d, 1-SOC, 'linear', 'extrap');
            C1 = interp1(rc.SOC_lookupR, rc.C1_d, 1-SOC, 'linear', 'extrap');
            C2 = interp1(rc.SOC_lookupR, rc.C2_d, 1-SOC, 'linear', 'extrap');
        end
        SOC = SOC - (I_arr(k)*dt_arr(k)) / rc.Q;
        SOC = min(max(SOC, 0), 1.2);
        VOC = interp1(rc.SOC_lookupR, rc.OCV_lookup, SOC, 'linear', 'extrap');
        tao1 = R1*C1; tao2 = R2*C2;
        Vrc1 = exp(-dt_arr(k)/tao1)*Vrc1 + R1*(1-exp(-dt_arr(k)/tao1))*I_arr(k);
        Vrc2 = exp(-dt_arr(k)/tao2)*Vrc2 + R2*(1-exp(-dt_arr(k)/tao2))*I_arr(k);
        SOC_trace(k) = SOC;
        Vs_trace(k)  = VOC - I_arr(k)*Ri - Vrc1 - Vrc2;
    end
end
