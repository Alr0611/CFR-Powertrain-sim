"""Render the Mott key/shaft equations as PNGs so they sit next to the numbers in
CFR27 Shafts.xlsx -- the way our tools traditionally show their work.

Drawn with matplotlib mathtext rather than cropped out of the textbook: the repo is on
GitHub and cropped book figures are someone else's copyright. Same equations, our
styling, and every one cites its Mott number so anyone can check it against the book.

Mott, Machine Elements in Mechanical Design, 6th ed.:
    Section 11-4  Eq 11-1 .. 11-4   keys: shear and bearing, and the lengths they need
    Table 11-1                      key width and height vs shaft diameter
    Section 12-8  Eq 12-24          shaft diameter, fluctuating bending + steady torsion
    Chapter 5                       modified endurance limit

Run:  python tools/make_key_eq_images.py
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "eq_img_keys")
os.makedirs(OUT, exist_ok=True)

NAVY = "#1F3864"

EQS = {
    "shear_stress": (
        r"$\tau = \dfrac{F}{A_s} = \dfrac{T}{(D/2)(W L)} = \dfrac{2T}{D\,W\,L}$",
        "Mott Eq. 11-1  --  shear across the W x L section of the key"),
    "tau_design": (
        r"$\tau_d = \dfrac{0.5\,s_y}{N}$",
        "Mott 11-4  --  design shear stress, maximum shear stress theory"),
    "L_shear": (
        r"$L_{min} = \dfrac{2T}{\tau_d\,D\,W}$",
        "Mott Eq. 11-2  --  minimum key length against SHEAR"),
    "bearing_stress": (
        r"$\sigma = \dfrac{F}{A_c} = \dfrac{T}{(D/2)(L)(H/2)} = \dfrac{4T}{D\,L\,H}$",
        "Mott Eq. 11-3  --  bearing on the L x H/2 flank"),
    "sigma_design": (
        r"$\sigma_d = \dfrac{s_y}{N}$",
        "Mott 11-4  --  design bearing stress, on the WEAKEST of key / shaft / hub"),
    "L_bearing": (
        r"$L_{min} = \dfrac{4T}{\sigma_d\,D\,H}$",
        "Mott Eq. 11-4  --  minimum key length against BEARING"),
    "L_governing": (
        r"$L_{min} = \max\left[\dfrac{4TN}{s_{y,key}\,D\,W},\ \ \dfrac{4TN}{s_{y,bear}\,D\,H}\right]$",
        "the two above with the design stresses substituted -- this is the number to spec"),
    "N_actual": (
        r"$N = \min\left[\dfrac{0.5\,s_{y,key}\,D\,W\,L}{2T},\ \ \dfrac{s_{y,bear}\,D\,H\,L}{4T}\right]$",
        "Mott 11-2 / 11-4 solved for N  --  the factor a given key length actually achieves"),
    "which_governs": (
        r"$\dfrac{L_{bearing}}{L_{shear}} = \dfrac{s_{y,key}}{s_{y,bear}}\cdot\dfrac{W}{H}$",
        "square key (W = H) with key no harder than hub  ->  the two modes tie exactly"),
    "bearing_length": (
        r"$L_{eff} = L - W \ \ (\mathrm{Form\ A}), \quad "
        r"L - W/2 \ \ (\mathrm{Form\ AB}), \quad "
        r"L \ \ (\mathrm{Form\ B})$",
        "DIN 6885-1 end forms -- a radiused end does not bear over its projection"),
    "shaft_dia": (
        r"$D = \left[\dfrac{32N}{\pi}\sqrt{\left(\dfrac{K_t M}{s_n}\right)^{2} + "
        r"\dfrac{3}{4}\left(\dfrac{T}{s_y}\right)^{2}}\ \right]^{1/3}$",
        "Mott Eq. 12-24  --  fluctuating bending with steady torsion"),
    "endurance": (
        r"$s_n = s_n'\cdot C_s\cdot C_R\cdot C_m, \qquad C_s = (D/7.62)^{-0.11}$",
        "Mott Ch.5  --  modified endurance limit, D in mm"),
    "torsion": (
        r"$\tau = \dfrac{16\,T}{\pi D^{3}}, \qquad N = \dfrac{0.5\,s_y}{\tau}$",
        "static torsion screen -- NO Kt: stress concentration is a fatigue quantity"),
    "gear_loads": (
        r"$W_t = \dfrac{2T}{d}, \qquad W_r = W_t\tan\phi, \qquad W = \sqrt{W_t^2 + W_r^2}$",
        "gear tooth loads that bend the shaft (a chain sprocket has no W_r)"),
    "bending": (
        r"$M_{inner} = R_1\,a, \qquad M_{overhang} = W\,e$",
        "two-bearing bending, plus the cantilever term for an overhung sprocket"),
}


def render(name, latex, cite, width=6.2):
    fig = plt.figure(figsize=(width, 1.02), dpi=200)
    fig.patch.set_alpha(0)
    fig.text(0.01, 0.64, latex, fontsize=15, color="black", va="center", ha="left")
    fig.text(0.01, 0.12, cite, fontsize=7.5, color=NAVY, va="center", ha="left",
             style="italic")
    p = os.path.join(OUT, name + ".png")
    fig.savefig(p, transparent=True, bbox_inches="tight", pad_inches=0.05)
    plt.close(fig)
    return p


if __name__ == "__main__":
    for n, (l, c) in EQS.items():
        print("rendered", os.path.basename(render(n, l, c)))
