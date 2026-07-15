function lib_figs(R, op_points, gears, soc_curves, time, voltage, Vs_kf, SOC_ol, SOC_kf, bms_soc, p)
%LIB_FIGS  The four keeper figures for the gear-ratio study. Saved to output/.
ratios = [R.ratio];

%% Fig 1: Battery-model validation (voltage + SOC), 2 panels
f1 = figure('Name','Validation','Position',[60 60 1000 420]);
subplot(1,2,1);
plot(time/60, voltage, 'b'); hold on; plot(time/60, Vs_kf, 'r', 'LineWidth', 0.9);
xlabel('Time (min)'); ylabel('Per-cell V'); grid on; legend('Actual','Kalman sim');
title('Voltage: actual vs model (July 11)');
subplot(1,2,2);
plot(time/60, SOC_ol*100, 'LineWidth',1.1); hold on;
plot(time/60, SOC_kf*100, 'LineWidth',1.1); plot(time/60, bms_soc, 'k--', 'LineWidth',1.1);
xlabel('Time (min)'); ylabel('SOC (%)'); grid on;
legend('Open-loop','Kalman','BMS','Location','southwest');
title('SOC cross-validation (3 estimators)');

%% Fig 2: Operating points on efficiency map (4 ratios)
[rg, tg] = meshgrid(50:50:6000, 1:2:150);
emap = emrax208_efficiency(rg, tg, p);
mr = [4.00, 4.20, p.gear_current, 5.20];
f2 = figure('Name','Operating points on efficiency map','Position',[40 40 1400 400]);
for j = 1:4
    subplot(1,4,j);
    contourf(rg, tg, emap*100, [70 80 85 88 90 92 94 95 96 97], 'LineColor',[.4 .4 .4]);
    colormap(parula); caxis([70 98]); hold on;
    k = find(abs([op_points.ratio]-mr(j))<1e-6,1);
    ds = 1:5:numel(op_points(k).rpm);
    scatter(op_points(k).rpm(ds), op_points(k).torque(ds), 4, 'r', 'filled', 'MarkerFaceAlpha',0.25);
    yline(80,'w--'); xline(p.redline,'w:');
    xlabel('Motor rpm'); ylabel('Torque (Nm)'); xlim([0 6000]); ylim([0 150]);
    ttl = sprintf('%.2f:1',mr(j)); if abs(mr(j)-p.gear_current)<1e-6, ttl=[ttl ' (current)']; end
    title(ttl);
end
cb = colorbar; cb.Label.String = 'Motor eff (%)';
sgtitle('Comp op-points on EMRAX efficiency map: higher ratio pushes the cloud out of the 96% island');

%% Fig 3: Trade-off summary (5 panels)
f3 = figure('Name','Trade-off summary','Position',[80 80 1200 680]);
mk = @(y,ttl,yl) deal(plot(ratios, y, 'o-'), title(ttl), ylabel(yl));
subplot(2,3,1); plot(ratios,[R.avg_eff],'o-'); xline(p.gear_current,'r--'); grid on;
    xlabel('Gear ratio'); ylabel('Avg eff (%)'); title('Motor efficiency');
subplot(2,3,2); plot(ratios,[R.hi_eff],'o-'); xline(p.gear_current,'r--'); grid on;
    xlabel('Gear ratio'); ylabel('% traction energy'); title('High-eff energy fraction (\eta\geq95%)');
subplot(2,3,3); plot(ratios,[R.SOC],'o-'); xline(p.gear_current,'r--'); grid on;
    xlabel('Gear ratio'); ylabel('Final SOC (%)'); title('Endurance pack charge');
subplot(2,3,4); plot(ratios,[R.accel],'o-'); xline(p.gear_current,'r--'); grid on;
    xlabel('Gear ratio'); ylabel('0-75m (s)'); title('Accel proxy (lower better)');
subplot(2,3,5); plot(ratios,[R.top_kph],'o-'); xline(p.gear_current,'r--'); grid on;
    xlabel('Gear ratio'); ylabel('Top speed (kph)'); title('Top speed');
sgtitle('Left favors LOW ratio (efficiency); accel favors HIGH. Red dash = current 4.61.');

%% Fig 4: SOC depletion vs ratio (5 curves)
f4 = figure('Name','SOC vs ratio'); hold on;
sel = [4.00 4.20 p.gear_current 4.80 5.20];
for s = sel
    i = find(abs(gears-s)<1e-6,1);
    plot(time/60, soc_curves{i}*100, 'LineWidth',1.3, 'DisplayName', sprintf('%.2f:1', gears(i)));
end
xlabel('Time (min)'); ylabel('SOC (%)'); grid on; legend('show','Location','best');
title('SOC depletion vs gear ratio (July 11 cycle)');

for fh = [f1 f2 f3 f4]
    nm = fullfile('output', matlab.lang.makeValidName(fh.Name));
    savefig(fh, [nm '.fig']); try, saveas(fh, [nm '.png']); catch, end
end
end
