function save_tabfig(fig, stem)
%SAVE_TABFIG  Save a tabbed figure to output.
%   Writes <stem>.fig (the whole tabbed figure, reopenable in MATLAB with all
%   tabs) plus one PNG per tab, <stem>_<TabTitle>.png. exportgraphics cannot take
%   a whole figure that contains UI components (the tab bar), so each tab's axes
%   is exported on its own. A plain (non-tabbed) figure just gets <stem>.png.
    savefig(fig, [stem '.fig']);
    tg = findobj(fig, 'Type', 'uitabgroup');
    if isempty(tg)
        try, exportgraphics(fig, [stem '.png']); catch, end
        return;
    end
    tg = tg(1);
    for k = 1:numel(tg.Children)
        tab = tg.Children(k);
        tg.SelectedTab = tab; drawnow;
        ax = findobj(tab, 'Type', 'axes');
        if isempty(ax), continue; end
        png = sprintf('%s_%s.png', stem, matlab.lang.makeValidName(tab.Title));
        try, exportgraphics(ax(end), png); catch, end
    end
end
