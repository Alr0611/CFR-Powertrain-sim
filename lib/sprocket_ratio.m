function [ratio, N_driven] = sprocket_ratio(N_driven)
%SPROCKET_RATIO  Total final-drive ratio from a driven sprocket tooth count.
%   ratio = sprocket_ratio(N_driven)  gives 2.000 * N_driven / 13.
%   [ratio, N] = sprocket_ratio()     with no argument returns all nine
%   buildable configs (26T to 34T) and their ratios.
%
%   THE POINT OF THIS FILE. The sweep in gear_ratio_optimization.m is continuous
%   from 4.00 to 5.20. The car is not. The final drive is a FIXED 15:30 gearbox
%   (2.000) times a chain reduction (driven/driver), the driver is 13T and stays
%   13T, so the only ratios you can actually bolt on are 2.000*N/13 for integer N.
%   That is nine values, spaced about 0.154 apart. Every ratio in between is a
%   number the sim can print and the shop cannot build.
%
%   Keep the sweep and the sprocket list from drifting apart by generating the
%   buildable ratios HERE rather than typing them twice.
%
%   Inputs, and where they come from:
%     gearbox 15:30 = 2.000   CFR24 Driveline Tool - Final Geometry.xlsx,
%                             '1. Gear Design'!D15/D16/D17            (from-SHEET)
%     driver 13T              cfr24 dt/Sprocket Gearing and Forces.xlsx!M8
%                             and KHK/Euro 'Sheet1'!B15               (from-SHEET)
%
%   Current car is 30T -> 4.6154, which is the 4.61 in params_cfr26.m. This
%   function does NOT set the ratio anywhere. params_cfr26.m stays the single
%   source of truth; changing the recommended ratio is a one-line edit there.
%
%   See sprocket_configs.md for the full Mott Ch.7 geometry and strength work,
%   and CFR27_Sprocket_Study.xlsx for the live PASS/FAIL version.

    GEARBOX = 2.000;    % 15:30, fixed, not part of the sweep
    N_DRIVER = 13;      % keep it, changing it is the only way to get between-step
                        % ratios and that was ruled out

    if nargin < 1
        N_driven = (26:34).';        % the nine that land in the 4.00-5.20 window
    end

    if ~isnumeric(N_driven) || any(N_driven(:) ~= round(N_driven(:))) || any(N_driven(:) < 9)
        error('sprocket_ratio:badTeeth', ...
              'Driven tooth count must be a whole number >= 9. Got something else.');
    end

    ratio = GEARBOX .* N_driven ./ N_DRIVER;
end
