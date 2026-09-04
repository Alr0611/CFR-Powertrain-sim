function [W, H, isSquare] = mott_key_size(D)
%MOTT_KEY_SIZE  Standard parallel key W x H for a shaft diameter, SI metric.
%   [W, H] = mott_key_size(D)  with D in mm, returns key width and height in mm.
%
%   Source: Mott, Machine Elements in Mechanical Design, 6th ed., Table 11-1
%   "Key Size vs. Shaft Diameter", SI metric column. Same table as ISO/R 773 and
%   DIN 6885-1, so a key ordered to this is a stock part, not a special.
%
%   THE KEY SIZE IS NOT A FREE VARIABLE. Once the shaft diameter is set, W and H
%   are set with it (W is about D/4). The only things left to choose are the key
%   LENGTH and the key MATERIAL, which is exactly what shaft_key_calc.m solves for.
%   So do not "pick a bigger key" to fix a short-length problem: pick a bigger
%   SHAFT, and the key grows with it.
%
%   Rows above 30 mm shaft are rectangular (H < W); at or below, square (H = W).
%   D outside 6-500 mm errors rather than extrapolating, because there is no such
%   standard key and silently inventing one is how a drawing ends up uncuttable.

    % over(mm)  toIncl(mm)  W(mm)  H(mm)
    T = [   6     8     2     2
            8    10     3     3
           10    12     4     4
           12    17     5     5
           17    22     6     6
           22    30     8     7
           30    38    10     8
           38    44    12     8
           44    50    14     9
           50    58    16    10
           58    65    18    11
           65    75    20    12
           75    85    22    14
           85    95    25    14
           95   110    28    16
          110   130    32    18
          130   150    36    20
          150   170    40    22
          170   200    45    25
          200   230    50    28
          230   260    56    32
          260   290    63    32
          290   330    70    36
          330   380    80    40
          380   440    90    45
          440   500   100    50 ];

    if D <= T(1,1) || D > T(end,2)
        error('mott_key_size:outOfRange', ...
            ['Shaft D = %.2f mm is outside Mott Table 11-1 (%g-%g mm). There is no ' ...
             'standard parallel key this size.'], D, T(1,1), T(end,2));
    end
    k = find(D > T(:,1) & D <= T(:,2), 1);
    W = T(k,3);
    H = T(k,4);
    isSquare = (W == H);
end
