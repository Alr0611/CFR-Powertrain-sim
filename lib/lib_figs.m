function lib_figs(R, op_points, gears, soc_curves, time, voltage, Vs_kf, SOC_ol, SOC_kf, bms_soc, p)
%LIB_FIGS  Two windows for the gear-ratio study, saved to output/:
%   1. "Gear study dashboard" -- battery-model validation + the 5 trade-off panels
%      + SOC-vs-ratio, ALL swept ratios, in one tiled window.
%   2. "Operating points on efficiency map" -- its own window, one panel per ratio
%      (the whole 4.00-5.20 sweep, not a hand-picked few).
ratios = [R.ratio];
ng = numel(gears);

%% ===== WINDOW 1: DASHBOARD (everything except the operating-point maps) =====
fD = figure('Name','Gear study dashboard','Position',[30 30 1500 860]);
tl = tiledlayout(fD, 3, 3, 'TileSpacing','compact', 'Padding','compact');

% -- battery validation: per-cell voltage, real vs model --
nexttile(tl);
plot(time/60, voltage, 'b'); hold on; plot(time/60, Vs_kf, 'r','LineWidth',0.9);
xlabel('Time (min)'); ylabel('Per-cell V'); grid on; legend('Actual','Kalman','Location','best');
title('Voltage: actual vs model (July 11)');

% -- battery validation: SOC three ways --
nexttile(tl);
plot(time/60, SOC_ol*100,'LineWidth',1.1); hold on;
plot(time/60, SOC_kf*100,'LineWidth',1.1); plot(time/60, bms_soc,'k--','LineWidth',1.1);
xlabel('Time (min)'); ylabel('SOC (%)'); grid on;
legend('Open-loop','Kalman','BMS','Location','southwest');
title('SOC cross-validation (3 estimators)');

% -- SOC depletion vs ratio: ALL swept ratios, colored by ratio --
nexttile(tl); hold on;
cmap = turbo(ng);
for i = 1:ng
    plot(time/60, soc_curves{i}*100, 'Color', cmap(i,:), 'LineWidth', 1);
end
xlabel('Time (min)'); ylabel('SOC (%)'); grid on;
colormap(gca, turbo); clim([gears(1) gears(end)]);
cb = colorbar; cb.Label.String = 'Gear ratio';
title(sprintf('SOC depletion, all %d ratios (%.2f-%.2f)', ng, gears(1), gears(end)));

% -- the 5 trade-off panels (all ratios; red dash = current) --
nexttile(tl); plot(ratios,[R.avg_eff],'o-'); xline(p.gear_current,'r--'); grid on;
    xlabel('Gear ratio'); ylabel('Avg eff (%)'); title('Motor efficiency');
nexttile(tl); plot(ratios,[R.hi_eff],'o-'); xline(p.gear_current,'r--'); grid on;
    xlabel('Gear ratio'); ylabel('% traction energy'); title(sprintf('High-eff fraction (\\eta\\geq%.0f%%)', p.eff_sweet*100));
nexttile(tl); plot(ratios,[R.SOC],'o-'); xline(p.gear_current,'r--'); grid on;
    xlabel('Gear ratio'); ylabel('Final SOC (%)'); title('Endurance pack charge');
nexttile(tl); plot(ratios,[R.accel],'o-'); xline(p.gear_current,'r--'); grid on;
    xlabel('Gear ratio'); ylabel('0-75m (s)'); title('Accel proxy (lower better)');
nexttile(tl); plot(ratios,[R.top_kph],'o-'); xline(p.gear_current,'r--'); grid on;
    xlabel('Gear ratio'); ylabel('Top speed (kph)'); title('Top speed');

title(tl, 'CFR27 gear-ratio study: low/left favors efficiency + charge, accel favors high. Red dash = current 4.61');

%% ===== WINDOW 2: OPERATING POINTS ON THE EFFICIENCY MAP (all ratios) =====
[rg, tg] = meshgrid(50:50:6000, 1:2:150);
emap = emrax208_efficiency(rg, tg, p);
fO = figure('Name','Operating points on efficiency map','Position',[50 50 1500 820]);
tlo = tiledlayout(fO, 'flow', 'TileSpacing','compact', 'Padding','compact');
for j = 1:ng
    nexttile(tlo);
    contourf(rg, tg, emap*100, [70 80 85 88 90 92 94 95 96 97], 'LineColor',[.4 .4 .4]);
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

%% ===== save both windows =====
for fh = [fD fO]
    nm = fullfile('output', matlab.lang.makeValidName(fh.Name));
    savefig(fh, [nm '.fig']); try, saveas(fh, [nm '.png']); catch, end
end
end
