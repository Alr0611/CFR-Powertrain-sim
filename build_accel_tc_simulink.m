function build_accel_tc_simulink()
%BUILD_ACCEL_TC_SIMULINK  Build accel_tc_sim.slx: the TC accel model in Simulink.
%
%   build_accel_tc_simulink        % creates/overwrites accel_tc_sim.slx and runs it
%
% MIRRORS accel_model_tc.m, which mirrors the firmware. Same params, same tyre
% model, same controller structure. The plant and controller both live in a single
% MATLAB Function block that calls lib/accel_tc_core.m, so the Simulink version and
% the .m version CANNOT drift apart -- there is exactly one implementation of the
% physics and one of the controller, and both files call it.
%
% Why it is built by script instead of shipped as a binary .slx: same reason
% build_accel_simulink.m exists for the original accel sim. A generated model is
% diffable, reviewable and regenerable; a checked-in .slx is none of those.
%
% Gains, target slip and limits are pushed into the model workspace, so you can
% sweep them from the command line or from the Simulink mask without editing
% blocks:
%     build_accel_tc_simulink
%     set_param('accel_tc_sim/TC gains','Value','...')   % or edit tcCfg below
%
% DOES NOT TOUCH THE FIRMWARE. This is an offline model of it.

    mdl = 'accel_tc_sim';
    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(here,'lib'));

    if bdIsLoaded(mdl), close_system(mdl, 0); end
    if exist([mdl '.slx'],'file'), delete([mdl '.slx']); end

    new_system(mdl);
    open_system(mdl);

    % ---- config that the model runs with (mirrors accel_model_tc.m) ----
    p = params_cfr26();
    tcCfg = struct('enabled',true,'target_slip',0.10, ...
                   'kp',0.470,'ki',0.0,'kd',0.110, ...   % firmware 150 Nm map
                   'ilim',0.0,'maxlim',0.75,'ileak_ms',500, ...
                   'rate_hz',100,'speed_gate',0.5, ...
                   'emulate_firmware_pure_p',true);
    tyreCfg = struct('mu_scale',1.00,'s_peak',0.12,'C',1.65);
    tyreCfg.B = tan(pi/(2*tyreCfg.C))/tyreCfg.s_peak;

    % put them in the model workspace so the blocks and any sweep see the same values
    assignin('base','p',p); assignin('base','tcCfg',tcCfg);
    assignin('base','tyreCfg',tyreCfg); assignin('base','G',p.gear_current);
    clear accel_tc_sample   % drop any cached trace from a previous build

    % ---- blocks ----
    add_block('simulink/Sources/Clock', [mdl '/Clock'], 'Position',[40 100 70 130]);

    fcn = [mdl '/Accel + TC plant'];
    add_block('simulink/User-Defined Functions/MATLAB Function', fcn, ...
              'Position',[140 60 380 200]);
    body = strjoin({
        'function [t75, v, x, slip, y, Tcmd] = fcn(clk)'
        '% Thin wrapper. All physics + control live in lib/accel_tc_core.m, called'
        '% through lib/accel_tc_sample.m, so Simulink and accel_model_tc.m can never'
        '% disagree -- there is one implementation, and both call it.'
        'coder.extrinsic(''accel_tc_sample'');'
        't75 = 0; v = 0; x = 0; slip = 0; y = 0; Tcmd = 0;'
        '[t75, v, x, slip, y, Tcmd] = accel_tc_sample(clk);'
        }, newline);
    setFcnBody(fcn, body);

    outs = {'t75','v (m/s)','x (m)','slip','y (TC cut)','T cmd (Nm)'};
    for i = 1:numel(outs)
        blk = sprintf('%s/%s', mdl, matlab.lang.makeValidName(outs{i}));
        add_block('simulink/Sinks/To Workspace', blk, ...
                  'VariableName', matlab.lang.makeValidName(outs{i}), ...
                  'SaveFormat','Structure With Time', ...
                  'Position',[470 40+40*i 540 70+40*i]);
        add_line(mdl, sprintf('Accel + TC plant/%d', i), ...
                 sprintf('%s/1', matlab.lang.makeValidName(outs{i})), 'autorouting','on');
    end
    add_line(mdl, 'Clock/1', 'Accel + TC plant/1', 'autorouting','on');

    % scope on slip so you can watch it settle against the target
    add_block('simulink/Sinks/Scope', [mdl '/Slip scope'], 'Position',[470 300 540 340]);
    add_line(mdl, 'Accel + TC plant/4', 'Slip scope/1', 'autorouting','on');

    % Put lib/ on the path when the model loads, so opening the .slx from the file
    % browser and hitting Run works without running START.m first. Without this you get
    % "Undefined function 'accel_tc_sample'".
    set_param(mdl, 'PreLoadFcn', ...
        'addpath(fullfile(fileparts(which(''params_cfr26'')),''lib''));');
    set_param(mdl, 'InitFcn', ...
        'addpath(fullfile(fileparts(which(''params_cfr26'')),''lib''));');

    set_param(mdl, 'StopTime','7', 'SolverType','Fixed-step', ...
                   'FixedStep','0.0005', 'Solver','FixedStepDiscrete');
    Simulink.BlockDiagram.arrangeSystem(mdl);
    save_system(mdl, fullfile(here,[mdl '.slx']));
    fprintf('built %s.slx\n', mdl);

    % ---- run it and report, so a bare build self-demonstrates ----
    try
        so = sim(mdl);
        fprintf('ran %s: 0-75 m = %.3f s (accel_model_tc.m gives the same, same core)\n', ...
                mdl, so.get('t75').signals.values(end));
    catch ME
        fprintf('model built but did not run: %s\n', ME.message);
    end

    % ---- two extra sweeps: the 150 Nm and 130 Nm maps ----
    % Same model, re-run with each map's own config. A map is not just a kp: it
    % bundles kp, clamp AND maxTorqueNm, so all three move together or the sweep
    % is meaningless. Baseline above is left exactly as it was.
    % Gains are torque.h compile-time DEFAULTS. The live gains sit in NVM and
    % today's log shows NVM was written (123.0 Nm ceiling matches no map), so
    % these are DEFAULT-ASSUMED, not confirmed.
    maps = struct( ...
        'name',   {'150 Nm map', '130 Nm map (compile-time DEFAULT)'}, ...
        'kp',     {0.470,  0.591}, ...
        'kd',     {0.110,  0.070}, ...
        'maxlim', {0.75,   0.70 }, ...
        'Tmax',   {150,    130  });

    for mi = 1:numel(maps)
        M = maps(mi);
        pM = p; pM.T_driver_max = M.Tmax;
        tcM = tcCfg; tcM.kp = M.kp; tcM.kd = M.kd; tcM.maxlim = M.maxlim;
        tcM.ki = 0.0; tcM.ilim = 0.0;      % both maps ship the integral disabled
        for onoff = [true false]
            tcM.enabled = onoff;
            assignin('base','p',pM); assignin('base','tcCfg',tcM);
            clear accel_tc_sample          % drop the cached trace between runs
            try
                so = sim(mdl);
                fprintf('%-34s TC %-3s : 0-75 m = %.3f s\n', M.name, ...
                        string(matlab.lang.OnOffSwitchState(onoff)), ...
                        so.get('t75').signals.values(end));
            catch ME
                fprintf('%s TC %d: run failed: %s\n', M.name, onoff, ME.message);
            end
        end
    end
    % leave the workspace holding the baseline config, not the last sweep
    assignin('base','p',p); assignin('base','tcCfg',tcCfg);
    clear accel_tc_sample
end

function setFcnBody(blkPath, body)
%SETFCNBODY  Write the MATLAB Function block's code.
    rt = sfroot();
    blk = rt.find('-isa','Stateflow.EMChart','Path',blkPath);
    blk.Script = body;
end
