"""
Render the AGMA equations as PNGs so they can sit next to the numbers in the
Gear Check sheet -- the way our tools traditionally show their work.

We draw these ourselves (matplotlib mathtext) rather than cropping the textbook:
the repo is on GitHub, and cropped book figures are someone else's copyright.
Same equations, our styling, and every one cites its Shigley number so anyone
can go check it against the book.

Shigley, Mechanical Engineering Design, Ch.14 (Spur and Helical Gears):
    Eq 14-15  bending stress, AGMA
    Eq 14-16  contact stress, AGMA
    Eq 14-23  geometry factor I for external spur gears
    Fig 14-6  geometry factor J
    Eq 14-41/42  safety factors
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "eq_img")
os.makedirs(OUT, exist_ok=True)

NAVY = "#1F3864"

EQS = {
    # name            latex                                                          cite
    "wt":    (r"$W_t = \dfrac{2\,T}{d_P}$",
              "transmitted load"),
    "dp":    (r"$d_P = N_P \cdot m$",
              "pitch diameter"),
    "mg":    (r"$m_G = \dfrac{N_G}{N_P}$",
              "gear ratio"),
    "I":     (r"$I = \dfrac{\cos\phi\,\sin\phi}{2}\cdot\dfrac{m_G}{m_G+1}$",
              "Shigley Eq. 14-23  (external spur)"),
    "bend":  (r"$\sigma = W_t\,K_o\,K_v\,K_s\,\dfrac{1}{b\,m_t}\,\dfrac{K_m K_B}{J}$",
              "Shigley Eq. 14-15  (SI)  -- bending"),
    "cont":  (r"$\sigma_c = C_p\sqrt{W_t\,K_o\,K_v\,K_s\,\dfrac{K_m}{d_P\,b}\,\dfrac{1}{I}}$",
              "Shigley Eq. 14-16  (SI)  -- contact / pitting"),
    "fos":   (r"$S_F = \dfrac{S_t}{\sigma}\qquad S_H = \dfrac{S_c}{\sigma_c}$",
              "Shigley Eq. 14-41 / 14-42  (Y_N = K_T = K_R = 1)"),
}


def render(name, latex, cite):
    fig = plt.figure(figsize=(5.4, 0.92), dpi=200)
    fig.patch.set_alpha(0)
    fig.text(0.01, 0.62, latex, fontsize=15, color="black", va="center", ha="left")
    fig.text(0.01, 0.13, cite, fontsize=7.5, color=NAVY, va="center", ha="left",
             style="italic")
    p = os.path.join(OUT, name + ".png")
    fig.savefig(p, transparent=True, bbox_inches="tight", pad_inches=0.04)
    plt.close(fig)
    return p


if __name__ == "__main__":
    for n, (l, c) in EQS.items():
        print("rendered", os.path.basename(render(n, l, c)))
