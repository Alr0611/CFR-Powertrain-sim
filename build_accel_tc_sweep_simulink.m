function build_accel_tc_sweep_simulink()
%BUILD_ACCEL_TC_SWEEP_SIMULINK  Build accel_tc_sweep_sim.slx, the model the TC sweep drives.
%
%   build_accel_tc_sweep_simulink      % creates/overwrites accel_tc_sweep_sim.slx, runs it
%
% Third of three models, and they do different jobs:
%   accel_sim.slx           baseline accel, no TC.               left alone
%   accel_tc_sim.slx        one TC run, one ratio, one map.      left alone
%   accel_tc_sweep_sim.slx  this one, driven in a loop by sweep_accel_tc_sim.m
%
% Only real difference from accel_tc_sim.slx: it calls lib/accel_tc_sweep_sample.m, whose
% cache is keyed on the config so it can't go stale over the dozens of runs a sweep does.
%
% Physics is lib/accel_tc_core.m, same function accel_model_tc.m calls, so Simulink and
% MATLAB can't disagree. The build checks that numerically instead of assuming it.
%
% Does not touch the firmware. Offline model of it.

    mdl  = 'accel_tc_sweep_sim';
    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(here,'lib'));

    if bdIsLoaded(mdl), close_system(mdl, 0); end
    if exist([mdl '.slx'],'file'), delete([mdl '.slx']); end

    new_system(mdl);

    % Config a bare build starts from. sweep_accel_tc_sim.m overwrites these per run.
    p = params_cfr26();
    tcCfg = struct('enabled',true,'target_slip',0.10, ...
                   'kp',0.470,'ki',0.0,'kd',0.110, ...   % firmware 150 Nm map defaults
                   'ilim',0.0,'maxlim',0.75,'ileak_ms',500, ...
                   'rate_hz',100,'speed_gate',0.5, ...
                   'emulate_firmware_pure_p',true);
    % 1.00 = run the params tyre as measured. accel_tc_core uses the full MF6.1 set via
    % lib/tire_fx_mf.m, so the old s_peak/C/B fields aren't needed any more.
    tyreCfg = struct('mu_scale',1.00);

    assignin('base','p',p);       assignin('base','tcCfg',tcCfg);
    assignin('base','tyreCfg',tyreCfg); assignin('base','G',p.gear_current);

    add_block('simulink/Sources/Clock', [mdl '/Clock'], 'Position',[40 100 70 130]);

    fcn = [mdl '/Accel + TC plant (sweep)'];
    add_block('simulink/User-Defined Functions/MATLAB Function', fcn, ...
              'Position',[140 60 380 200]);
    body = strjoin({
        'function [t75, v, x, slip, y, Tcmd] = fcn(clk)'
        '% Thin wrapper. All physics + control live in lib/accel_tc_core.m, reached'
        '% through lib/accel_tc_sweep_sample.m, whose cache is keyed on the config so a'
        '% sweep cannot silently reuse the previous run''s trace.'
        'coder.extrinsic(''accel_tc_sweep_sample'');'
        't75 = 0; v = 0; x = 0; slip = 0; y = 0; Tcmd = 0;'
        '[t75, v, x, slip, y, Tcmd] = accel_tc_sweep_sample(clk);'
        }, newline);
    setFcnBody(fcn, body);

    outs = {'t75','v (m/s)','x (m)','slip','y (TC cut)','T cmd (Nm)'};
    for i = 1:numel(outs)
        nm  = matlab.lang.makeValidName(outs{i});
        blk = sprintf('%s/%s', mdl, nm);
        add_block('simulink/Sinks/To Workspace', blk, ...
                  'VariableName', nm, 'SaveFormat','Structure With Time', ...
                  'Position',[470 40+40*i 540 70+40*i]);
        add_line(mdl, sprintf('Accel + TC plant (sweep)/%d', i), ...
                 sprintf('%s/1', nm), 'autorouting','on');
    end
    add_line(mdl, 'Clock/1', 'Accel + TC plant (sweep)/1', 'autorouting','on');

    % ---- scopes ----
    % One per thing you actually watch when tuning TC, plus a combined one. Without
    % these the model runs and shows you nothing, which is useless for tuning.
    scopes = { ...
        'Slip',            4, 'rear axle slip vs time'; ...
        'TC reduction y',  5, 'fraction of torque the controller is removing'; ...
        'Speed',           2, 'vehicle speed (m/s)'; ...
        'Distance',        3, 'distance (m), 75 m is the number'; ...
        'Torque cmd',      6, 'motor torque after TC (Nm)'};
    for i = 1:size(scopes,1)
        nm = [mdl '/' scopes{i,1}];
        add_block('simulink/Sinks/Scope', nm, ...
                  'Position',[470 300+55*i 540 340+55*i]);
        set_param(nm, 'OpenAtSimulationStart','on');   % actually pop up when you hit Run
        add_line(mdl, sprintf('Accel + TC plant (sweep)/%d', scopes{i,2}), ...
                 [scopes{i,1} '/1'], 'autorouting','on');
    end

    % Combined scope: slip and TC reduction on one axis pair is how you see whether the
    % controller is chasing the target or fighting it.
    add_block('simulink/Sinks/Scope', [mdl '/TC overview'], ...
              'Position',[640 300 710 340]);
    set_param([mdl '/TC overview'], 'NumInputPorts','3', 'OpenAtSimulationStart','on');
    add_line(mdl, 'Accel + TC plant (sweep)/4', 'TC overview/1', 'autorouting','on');
    add_line(mdl, 'Accel + TC plant (sweep)/5', 'TC overview/2', 'autorouting','on');
    add_line(mdl, 'Accel + TC plant (sweep)/6', 'TC overview/3', 'autorouting','on');

    % Put lib/ on the path whenever the model loads, so opening the .slx from the file
    % browser and hitting Run works without running START.m first.
    set_param(mdl, 'PreLoadFcn', ...
        'addpath(fullfile(fileparts(which(''params_cfr26'')),''lib''));');
    set_param(mdl, 'InitFcn', ...
        'addpath(fullfile(fileparts(which(''params_cfr26'')),''lib''));');

    set_param(mdl, 'StopTime','7', 'SolverType','Fixed-step', ...
                   'FixedStep','0.0005', 'Solver','FixedStepDiscrete');
    Simulink.BlockDiagram.arrangeSystem(mdl);
    save_system(mdl, fullfile(here,[mdl '.slx']));
    fprintf('built %s.slx\n', mdl);

    % Self-demonstrate, and prove against the .m path in the same breath.
    try
        so = sim(mdl);
        tSL = so.get('t75').signals.values(end);
        tM  = accel_tc_core(p, tcCfg, tyreCfg, p.gear_current).t75;
        fprintf('ran %s: 0-75 m = %.4f s | accel_tc_core.m = %.4f s | delta %.2e s\n', ...
                mdl, tSL, tM, abs(tSL-tM));
        if abs(tSL-tM) > 1e-9
            fprintf(2, 'WARNING: Simulink and MATLAB disagree. They share one core, so\n');
            fprintf(2, '         a nonzero delta means the sampler or workspace is stale.\n');
        end
    catch ME
        fprintf('model built but did not run: %s\n', ME.message);
    end
end

function setFcnBody(blkPath, body)
%SETFCNBODY  Write the MATLAB Function block's code.
    rt  = sfroot();
    blk = rt.find('-isa','Stateflow.EMChart','Path',blkPath);
    blk.Script = body;
end
