function lib_figs(R, op_points, gears, soc_curves, time, voltage, Vs_kf, SOC_ol, SOC_kf, bms_soc, p)
%LIB_FIGS  Two windows for the gear-ratio study, saved to output/:
%   1. "Gear study dashboard" -- TABBED: battery validation, SOC cross-check,
%      SOC-vs-ratio (all ratios), and the efficiency/charge trade-off panels.
%   2. "Operating points on efficiency map" -- its own separate window, one panel
%      per ratio (the whole 4.00-5.20 sweep).
%   Acceleration / top speed are intentionally NOT here -- see sweep_accel_sim.
ratios = [R.ratio];
ng = numel(gears);

%% ===== WINDOW 1: DASHBOARD (tabbed, one plot per tab) =====
fD = figure('Name','Gear study dashboard','Position',[30 30 1100 640]);
tg = uitabgroup(fD);

ax = axes(uitab(tg,'Title','Voltage validation'));
plot(ax, time/60, voltage, 'b'); hold(ax,'on'); plot(ax, time/60, Vs_kf, 'r','LineWidth',0.9);
xlabel(ax,'Time (min)'); ylabel(ax,'Per-cell V'); grid(ax,'on'); legend(ax,'Actual','Kalman','Location','best');
title(ax,'Voltage: actual vs model (July 11)');

ax = axes(uitab(tg,'Title','SOC cross-check'));
plot(ax, time/60, SOC_ol*100,'LineWidth',1.1); hold(ax,'on');
plot(ax, time/60, SOC_kf*100,'LineWidth',1.1); plot(ax, time/60, bms_soc,'k--','LineWidth',1.1);
xlabel(ax,'Time (min)'); ylabel(ax,'SOC (%)'); grid(ax,'on');
legend(ax,'Open-loop','Kalman','BMS','Location','southwest');
title(ax,'SOC cross-validation (3 estimators)');

ax = axes(uitab(tg,'Title','SOC vs ratio'));
hold(ax,'on'); cmap = turbo(ng);
for i = 1:ng, plot(ax, time/60, soc_curves{i}*100, 'Color', cmap(i,:), 'LineWidth', 1); end
xlabel(ax,'Time (min)'); ylabel(ax,'SOC (%)'); grid(ax,'on');
colormap(ax, turbo); clim(ax,[gears(1) gears(end)]); cb = colorbar(ax); cb.Label.String = 'Gear ratio';
title(ax, sprintf('SOC depletion, all %d ratios (%.2f-%.2f)', ng, gears(1), gears(end)));

ax = axes(uitab(tg,'Title','Motor efficiency'));
plot(ax, ratios,[R.avg_eff],'o-'); xline(ax, p.gear_current,'r--'); grid(ax,'on');
xlabel(ax,'Gear ratio'); ylabel(ax,'Avg eff (%)'); title(ax,'Motor efficiency (red dash = current 4.61)');

ax = axes(uitab(tg,'Title','High-eff fraction'));
plot(ax, ratios,[R.hi_eff],'o-'); xline(ax, p.gear_current,'r--'); grid(ax,'on');
xlabel(ax,'Gear ratio'); ylabel(ax,'% traction energy');
title(ax, sprintf('High-eff fraction (\\eta\\geq%.0f%%)', p.eff_sweet*100));

ax = axes(uitab(tg,'Title','Endurance charge'));
plot(ax, ratios,[R.SOC],'o-'); xline(ax, p.gear_current,'r--'); grid(ax,'on');
xlabel(ax,'Gear ratio'); ylabel(ax,'Final SOC (%)'); title(ax,'Endurance pack charge (lower ratio keeps more)');

save_tabfig(fD, fullfile('output','GearStudyDashboard'));

%% ===== WINDOW 2: OPERATING POINTS ON THE EFFICIENCY MAP (own window, all ratios) =====
[rg, tqg] = meshgrid(50:50:6000, 1:2:150);
emap = emrax208_efficiency(rg, tqg, p);
fO = figure('Name','Operating points on efficiency map','Position',[50 50 1500 820]);
tlo = tiledlayout(fO, 'flow', 'TileSpacing','compact', 'Padding','compact');
for j = 1:ng
    nexttile(tlo);
    contourf(rg, tqg, emap*100, [70 80 85 88 90 92 94 95 96 97], 'LineColor',[.4 .4 .4]);
    colormap(parula); clim([70 98]); hold on;
    k = find(abs([op_points.ratio]-gears(j))<1e-6, 1);
    if ~isempty(k)
        ds = 1:5:numel(op_points(k).rpm);
        scatter(op_points(k).rpm(ds), op_points(k).torque(ds), 4, 'r', 'filled', 'MarkerFaceAlpha',0.25);
    end
    yline(80,'w--'); xline(p.redline,'w:');
    xlim([0 6000]); ylim([0 150]);
    ttl = sprintf('%.2f:1', gears(j)); if abs(gears(j)-p.gear_current)<1e-6, ttl=[ttl ' (current)']; end
    title(ttl);
end
cb = colorbar; cb.Layout.Tile = 'east'; cb.Label.String = 'Motor eff (%)';
xlabel(tlo,'Motor rpm'); ylabel(tlo,'Torque (Nm)');
title(tlo, 'Operating points on EMRAX efficiency map (all ratios): higher ratio pushes the cloud out of the 96% island');
nm = fullfile('output', matlab.lang.makeValidName(fO.Name));
savefig(fO, [nm '.fig']); try, saveas(fO, [nm '.png']); catch, end
end
