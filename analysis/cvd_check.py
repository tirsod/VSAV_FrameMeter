"""Can two HUD colours be told apart under the common colour vision types?

The light blue and pink first chosen for P1 / P2 landings were reported as
indistinguishable (user, 2026-09-27). Computed: deutan CIEDE2000 0.7 - the
same colour. This is the check that picked the replacement, kept so the next
colour choice is measured instead of guessed.

    python analysis/cvd_check.py "#66CCFF" "#FF9900"

Prints CIEDE2000 between the two as seen normally and with protanopia,
deuteranopia and tritanopia simulated (Machado, Oliveira & Fernandes 2009,
severity 1.0, applied in linear sRGB). Rule of thumb: under 10 is hard to
tell apart, 20 and up is comfortable. Also the text contrast of each against
the dark box AirGap draws on.
"""
import sys

import numpy as np

# Machado, Oliveira & Fernandes (2009), severity 1.0, applied in linear sRGB.
CVD = {
    "normal": np.eye(3),
    "protan": np.array([[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]]),
    "deutan": np.array([[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]),
    "tritan": np.array([[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]]),
}
def hex2rgb(h): return np.array([int(h[i:i+2], 16) for i in (1, 3, 5)]) / 255.0
def lin(c): return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
M = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]])
WHITE = np.array([0.95047, 1.0, 1.08883])
def lab_of_linear(l):
    x = (M @ l) / WHITE
    f = np.where(x > 216/24389, np.cbrt(x), (24389/27 * x + 16) / 116)
    return np.array([116 * f[1] - 16, 500 * (f[0] - f[1]), 200 * (f[1] - f[2])])
def lab(h, kind):
    l = np.clip(CVD[kind] @ lin(hex2rgb(h)), 0, 1)
    return lab_of_linear(l)
def de2000(a, b):
    L1, a1, b1 = a; L2, a2, b2 = b
    C1, C2 = np.hypot(a1, b1), np.hypot(a2, b2); Cm = (C1 + C2) / 2
    G = 0.5 * (1 - np.sqrt(Cm**7 / (Cm**7 + 25**7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = np.hypot(a1p, b1), np.hypot(a2p, b2)
    h1p = np.degrees(np.arctan2(b1, a1p)) % 360; h2p = np.degrees(np.arctan2(b2, a2p)) % 360
    dL, dC = L2 - L1, C2p - C1p
    dh = h2p - h1p
    if C1p * C2p == 0: dh = 0
    elif dh > 180: dh -= 360
    elif dh < -180: dh += 360
    dH = 2 * np.sqrt(C1p * C2p) * np.sin(np.radians(dh / 2))
    Lm, Cmp = (L1 + L2) / 2, (C1p + C2p) / 2
    hm = h1p + h2p
    if C1p * C2p != 0:
        hm = (h1p + h2p) / 2 if abs(h1p - h2p) <= 180 else ((h1p + h2p + 360) / 2 if h1p + h2p < 360 else (h1p + h2p - 360) / 2)
    T = 1 - 0.17*np.cos(np.radians(hm-30)) + 0.24*np.cos(np.radians(2*hm)) + 0.32*np.cos(np.radians(3*hm+6)) - 0.20*np.cos(np.radians(4*hm-63))
    Sl = 1 + 0.015*(Lm-50)**2/np.sqrt(20+(Lm-50)**2); Sc = 1 + 0.045*Cmp; Sh = 1 + 0.015*Cmp*T
    Rt = -2*np.sqrt(Cmp**7/(Cmp**7+25**7)) * np.sin(np.radians(60*np.exp(-((hm-275)/25)**2)))
    return float(np.sqrt((dL/Sl)**2 + (dC/Sc)**2 + (dH/Sh)**2 + Rt*(dC/Sc)*(dH/Sh)))
def dmin(h1, h2): return min(de2000(lab(h1, k), lab(h2, k)) for k in CVD)
def dall(h1, h2): return {k: round(de2000(lab(h1, k), lab(h2, k)), 1) for k in CVD}
def lum(h):
    l = lin(hex2rgb(h)); return float(0.2126*l[0] + 0.7152*l[1] + 0.0722*l[2])
def contrast(h, bg="#1A1A1A"):
    a, b = lum(h), lum(bg); return (max(a, b) + 0.05) / (min(a, b) + 0.05)



if __name__ == "__main__":
    a, b = sys.argv[1], sys.argv[2]
    for k in CVD:
        print("%-7s %5.1f" % (k, de2000(lab(a, k), lab(b, k))))
    print("contrast on the dark box: %s %.1f  %s %.1f" % (a, contrast(a), b, contrast(b)))
