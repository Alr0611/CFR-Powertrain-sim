function J = spur_gear_J(N_teeth, N_mating)
%SPUR_GEAR_J  AGMA bending geometry factor J (Shigley Fig 9-10), 20 deg PA.
%
%   J = spur_gear_J(N_teeth, N_mating) looks up the bending geometry factor
%   for a gear with N_teeth meshing against one with N_mating teeth, and
%   interpolates between the charted curves.
%
%   Why this exists: J used to be read off a chart by eyeball. Now it isn't.
%   You can check any tooth count without squinting at Figure 9-10.
%
%   The table is digitized from the chart (inherited from the Baja team's
%   Shigley workbook -- thanks Baja). Rows = teeth on THIS gear, columns =
%   teeth on the gear it meshes with.
%
%   *** DO NOT TRUST THIS BELOW 18 TEETH ***
%   Baja's sheet floors out at 15 teeth, and it shows: the 12 / 15 / 17-tooth
%   rows are dead flat across every mating size, which the real chart is NOT.
%   Those are filler cells, not chart reads. So this function WARNS below 18
%   teeth -- if you're running a small pinion (like our 15T), go read Shigley
%   Figure 9-10 yourself and pass J in by hand. Don't let a placeholder tell
%   you your gearbox is fine (or that it isn't).
%
%   18 teeth and up: good data, interpolates cleanly, use it freely.

    mating_cols = [17 25 35 50 85 170 1000];
    teeth_rows  = [12 15 17 18 20 24 30 35 40 50 60 80 125 275];
    % J values: rows = teeth_rows, cols = mating_cols
    Jtab = [ ...
      0.210 0.210 0.210 0.210 0.210 0.210 0.210     % 12
      0.250 0.250 0.250 0.250 0.250 0.250 0.250     % 15
      0.292 0.292 0.292 0.292 0.292 0.292 0.292     % 17
      0.300 0.305 0.312 0.317 0.326 0.326 0.326     % 18
      0.312 0.320 0.325 0.330 0.339 0.341 0.346     % 20
      0.333 0.341 0.348 0.355 0.361 0.369 0.372     % 24
      0.357 0.365 0.374 0.381 0.390 0.390 0.394     % 30  (170/1000 cleaned, see note)
      0.370 0.380 0.390 0.397 0.405 0.405 0.410     % 35  (170/1000 cleaned)
      0.380 0.390 0.400 0.410 0.419 0.419 0.425     % 40  (170/1000 cleaned)
      0.394 0.405 0.415 0.436 0.435 0.446 0.457     % 50
      0.405 0.416 0.429 0.440 0.450 0.462 0.471     % 60
      0.417 0.430 0.441 0.455 0.464 0.480 0.490     % 80
      0.430 0.445 0.457 0.470 0.482 0.500 0.510     % 125
      0.445 0.460 0.470 0.490 0.500 0.520 0.530];   % 275
    % NOTE: the source sheet had 30/35/40-tooth rows DROPPING at mating 170 &
    % 1000 (e.g. 0.390 -> 0.348), which is physically backwards -- J should
    % rise with a bigger mate. Looked like a digitizing slip, so those four
    % cells are held flat instead. Everything else is as-digitized.

    if N_teeth < 18
        warning('spur_gear_J:lowToothCount', ...
            ['J for %d teeth is NOT reliable -- the source table is flat below 18 ' ...
             'teeth (filler, not real chart data). Read Shigley Fig 9-10 and pass ' ...
             'J in by hand for small pinions.'], N_teeth);
    end
    N_teeth  = min(max(N_teeth,  teeth_rows(1)),  teeth_rows(end));
    N_mating = min(max(N_mating, mating_cols(1)), mating_cols(end));
    [MC, TR] = meshgrid(mating_cols, teeth_rows);
    J = interp2(MC, TR, Jtab, N_mating, N_teeth, 'linear');
end
