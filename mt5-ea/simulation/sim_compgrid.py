#!/usr/bin/env python3
"""
Simulation Monte Carlo de CompensationGrid_EA sur XAUUSD (preset 10k prudent).
Reproduit la logique exacte de l'EA sur des chemins de prix M15 synthetiques
calibres sur les proprietes statistiques du gold (vol ~20% ann., GARCH,
queues epaisses, regimes de tendance, effet de session).
"""
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

rng = np.random.default_rng(42)

# ----------------------------- Parametres EA (preset XAUUSD_10k_prudent)
CAPITAL0        = 10000.0      # EUR
START_LOT       = 0.01
LOT_MULT        = 1.30
MAX_LEVELS      = 6
GRID_STEP_FLOOR = 1.50         # $ (300 pips * 0.5, pip=0.01$)
ATR_FACTOR      = 1.2
ATR_PERIOD      = 14
EMA_PERIOD      = 50
TP_MONEY        = 25.0         # EUR
BE_MONEY        = 2.0
TRAIL_START     = 15.0
TRAIL_GIVEBACK  = 8.0
HARDSTOP_PCT    = 3.0          # % equity
DAILY_LOSS_PCT  = 5.0
START_H, END_H  = 9, 21
TRADE_FRIDAY    = False
MAX_TOTAL_LOT   = 0.50

# ----------------------------- Couts Roboforex (ECN, gold)
SPREAD_USD      = 0.18         # spread moyen XAUUSD ECN ($)
COMMISSION_EUR  = 15.0         # EUR / 1.0 lot aller-retour
SLIP_STOP_USD   = 0.30         # slippage additionnel sur stop dur ($)
USD_EUR         = 0.92
OZ_PER_LOT      = 100.0

# ----------------------------- Modele de prix XAUUSD M15
P0        = 4100.0             # niveau de l'once
ANN_VOL   = 0.20               # vol annualisee ~20%
BARS_DAY  = 96                 # bougies M15 / jour
DAYS_MON  = 22                 # jours de trading / mois
N_BARS    = BARS_DAY * DAYS_MON

BAR_STD = ANN_VOL / np.sqrt(252 * BARS_DAY)   # std d'un retour M15

def session_vol(hour):
    """Profil de vol intraday: Asie calme, Londres/NY actifs."""
    if 0 <= hour < 7:   return 0.55
    if 7 <= hour < 13:  return 1.10
    if 13 <= hour < 18: return 1.45   # overlap Londres/NY
    if 18 <= hour < 22: return 0.95
    return 0.60

def gen_month(rng):
    """Genere un mois de bougies M15 (OHLC + heure + jour semaine)."""
    n = N_BARS
    hours = np.tile(np.repeat(np.arange(24), 4), DAYS_MON)[:n]
    dows  = np.repeat((np.arange(DAYS_MON) % 5) + 1, BARS_DAY)[:n]  # 1=lun..5=ven

    # GARCH-like vol clustering
    h = np.empty(n); h[0] = BAR_STD**2
    omega = 0.10 * BAR_STD**2; alpha = 0.12; beta = 0.78
    # regimes de drift (tendances qui durent ~2-5 jours)
    drift = np.empty(n); d = 0.0
    for i in range(n):
        if rng.random() < 1.0 / (3.5 * BARS_DAY):    # changement de regime
            d = rng.choice([-1.0, -0.4, 0.0, 0.4, 1.0]) * 0.35 * BAR_STD
        drift[i] = d

    z = rng.standard_t(df=4, size=n) / np.sqrt(2.0)  # queues epaisses, var~1
    rets = np.empty(n)
    for i in range(n):
        sv = session_vol(hours[i])
        sig = np.sqrt(h[i]) * sv
        rets[i] = drift[i] * sv + sig * z[i]
        if i + 1 < n:
            h[i+1] = omega + alpha * (rets[i] / sv)**2 + beta * h[i]

    closes = P0 * np.exp(np.cumsum(rets))
    opens  = np.empty(n); opens[0] = P0; opens[1:] = closes[:-1]
    span   = np.abs(closes - opens)
    wick   = np.abs(rng.normal(0, 0.6, n)) * np.maximum(span, P0 * BAR_STD * 0.5)
    highs  = np.maximum(opens, closes) + wick * 0.6
    lows   = np.minimum(opens, closes) - wick * 0.6
    return opens, highs, lows, closes, hours, dows

def ema(arr, period):
    out = np.empty_like(arr); k = 2.0 / (period + 1)
    out[0] = arr[0]
    for i in range(1, len(arr)):
        out[i] = arr[i] * k + out[i-1] * (1 - k)
    return out

def atr(h, l, c, period):
    n = len(c)
    tr = np.empty(n); tr[0] = h[0] - l[0]
    for i in range(1, n):
        tr[i] = max(h[i] - l[i], abs(h[i] - c[i-1]), abs(l[i] - c[i-1]))
    out = np.empty(n); out[0] = tr[0]
    for i in range(1, n):
        out[i] = (out[i-1] * (period - 1) + tr[i]) / period
    return out

def bar_path(o, hi, lo, c, step=0.5):
    """Chemin intrabar approxime O->L->H->C (haussier) / O->H->L->C sinon."""
    pts = [o, lo, hi, c] if c >= o else [o, hi, lo, c]
    path = []
    for a, b in zip(pts[:-1], pts[1:]):
        seg = max(2, int(abs(b - a) / step) + 1)
        path.extend(np.linspace(a, b, seg)[:-1])
    path.append(pts[-1])
    return path

def simulate_month(rng, start_lot=START_LOT):
    o, h, l, c, hours, dows = gen_month(rng)
    e50  = ema(c, EMA_PERIOD)
    a14  = atr(h, l, c, ATR_PERIOD)

    equity = CAPITAL0
    positions = []          # list of (dir, entry, lot)
    peak = 0.0
    halted_day = -1
    day_start_eq = CAPITAL0
    cur_day = 0
    baskets = {"TP": 0, "BE": 0, "Trail": 0, "HardStop": 0}
    closed_pl = []
    eq_curve = [equity]
    max_dd = 0.0; eq_high = equity

    def net_pl(price_mid):
        pl_usd = 0.0; vol = 0.0
        for d, e, v in positions:
            px = (price_mid - SPREAD_USD/2) if d > 0 else (price_mid + SPREAD_USD/2)
            pl_usd += (px - e) * OZ_PER_LOT * v * d
            vol += v
        return pl_usd * USD_EUR - vol * COMMISSION_EUR, vol

    for i in range(EMA_PERIOD, N_BARS):
        day = i // BARS_DAY
        if day != cur_day:
            cur_day = day; day_start_eq = equity
        hour, dow = hours[i], dows[i]
        in_hours = (START_H <= hour < END_H) and (TRADE_FRIDAY or dow != 5)
        step = max(GRID_STEP_FLOOR, a14[i-1] * ATR_FACTOR)
        hardstop = equity * HARDSTOP_PCT / 100.0
        new_bar = True

        for px in bar_path(o[i], h[i], l[i], c[i]):
            if positions:
                pl, vol = net_pl(px)
                # 1) stop dur
                if pl <= -hardstop:
                    pl -= vol * SLIP_STOP_USD * OZ_PER_LOT * USD_EUR / 100.0 * 100 / 100  # slippage
                    pl = pl - vol * SLIP_STOP_USD * 0  # (slippage deja integre ci-dessus)
                    equity += pl; closed_pl.append(pl); baskets["HardStop"] += 1
                    positions = []; peak = 0.0
                # 2) objectif profit
                elif pl >= TP_MONEY:
                    equity += pl; closed_pl.append(pl); baskets["TP"] += 1
                    positions = []; peak = 0.0
                else:
                    # 3) trailing
                    if pl > peak: peak = pl
                    if peak >= TRAIL_START and pl <= peak - TRAIL_GIVEBACK and pl > 0:
                        equity += pl; closed_pl.append(pl); baskets["Trail"] += 1
                        positions = []; peak = 0.0
                    # 4) BE grille pleine
                    elif len(positions) >= MAX_LEVELS and pl >= BE_MONEY:
                        equity += pl; closed_pl.append(pl); baskets["BE"] += 1
                        positions = []; peak = 0.0

            # stop journalier
            if equity - day_start_eq <= -day_start_eq * DAILY_LOSS_PCT / 100.0:
                halted_day = day

            if positions and len(positions) < MAX_LEVELS and in_hours and halted_day != day:
                d0 = positions[0][0]
                worst = min(p[1] for p in positions) if d0 > 0 else max(p[1] for p in positions)
                adverse = (px <= worst - step) if d0 > 0 else (px >= worst + step)
                tot = sum(p[2] for p in positions)
                if adverse and tot < MAX_TOTAL_LOT:
                    lot = round(start_lot * LOT_MULT ** len(positions), 2)
                    entry = px + SPREAD_USD/2 if d0 > 0 else px - SPREAD_USD/2
                    positions.append((d0, entry, max(0.01, lot)))

            if not positions and new_bar and in_hours and halted_day != day:
                d0 = 1 if o[i] > e50[i-1] else -1
                entry = px + SPREAD_USD/2 if d0 > 0 else px - SPREAD_USD/2
                positions = [(d0, entry, start_lot)]
                peak = 0.0
            new_bar = False

        eq_now = equity + (net_pl(c[i])[0] if positions else 0.0)
        eq_curve.append(eq_now)
        eq_high = max(eq_high, eq_now)
        max_dd = max(max_dd, eq_high - eq_now)

    # cloture fin de mois au marche
    if positions:
        pl, _ = net_pl(c[-1])
        equity += pl; closed_pl.append(pl)
        baskets["TP" if pl >= TP_MONEY else ("HardStop" if pl <= -hardstop else "BE")] += 0
    return equity - CAPITAL0, baskets, closed_pl, eq_curve, max_dd

# ============================ MONTE CARLO ============================
N_RUNS = 1000
results, dds, all_baskets = [], [], {"TP":0,"BE":0,"Trail":0,"HardStop":0}
sample_curves = []
for run in range(N_RUNS):
    pnl, b, pls, curve, dd = simulate_month(rng)
    results.append(pnl); dds.append(dd)
    for k in all_baskets: all_baskets[k] += b[k]
    if run < 8: sample_curves.append(curve)

results = np.array(results); dds = np.array(dds)
total_baskets = sum(all_baskets.values())

def pct(x): return 100.0 * x / max(total_baskets, 1)
q = np.percentile(results, [5, 25, 50, 75, 95])

print("=" * 64)
print(" SIMULATION MONTE CARLO - CompensationGrid_EA - XAUUSD - 1 MOIS")
print(" Preset prudent 10 000 EUR | 1000 mois simules | couts Roboforex")
print("=" * 64)
print(f" Resultat mensuel MEDIAN   : {q[2]:+8.0f} EUR  ({q[2]/100:+.1f}%)")
print(f" Fourchette 50% des mois   : {q[1]:+8.0f} a {q[3]:+.0f} EUR")
print(f" Fourchette 90% des mois   : {q[0]:+8.0f} a {q[4]:+.0f} EUR")
print(f" Pire mois simule          : {results.min():+8.0f} EUR")
print(f" Meilleur mois simule      : {results.max():+8.0f} EUR")
print(f" Mois positifs             : {100*np.mean(results>0):8.1f} %")
print(f" Drawdown median (intra-mois): {np.median(dds):6.0f} EUR | pire: {dds.max():.0f} EUR")
print("-" * 64)
print(f" Paniers/mois (moyenne)    : {total_baskets/N_RUNS:8.1f}")
print(f"   fermes en PROFIT (TP)   : {pct(all_baskets['TP']):5.1f} %")
print(f"   fermes en TRAILING      : {pct(all_baskets['Trail']):5.1f} %")
print(f"   fermes a BREAK-EVEN     : {pct(all_baskets['BE']):5.1f} %")
print(f"   fermes au STOP DUR      : {pct(all_baskets['HardStop']):5.1f} %")
print("=" * 64)

# ============================ GRAPHIQUE ============================
fig, axes = plt.subplots(1, 2, figsize=(14, 5.5))
ax = axes[0]
for curve in sample_curves:
    ax.plot(np.array(curve), lw=0.9, alpha=0.8)
ax.axhline(CAPITAL0, color="k", ls="--", lw=0.8)
ax.set_title("8 mois simulés (exemples de courbes d'equity)")
ax.set_xlabel("Bougies M15"); ax.set_ylabel("Equity (€)")
ax.grid(alpha=0.3)

ax = axes[1]
ax.hist(results, bins=60, color="#3b82f6", edgecolor="white", lw=0.3)
ax.axvline(0, color="k", lw=1)
ax.axvline(q[2], color="#16a34a", lw=2, label=f"Médiane {q[2]:+.0f} €")
ax.axvline(q[0], color="#dc2626", lw=1.5, ls="--", label=f"5e centile {q[0]:+.0f} €")
ax.axvline(q[4], color="#16a34a", lw=1.5, ls="--", label=f"95e centile {q[4]:+.0f} €")
ax.set_title("Distribution du résultat mensuel (1000 mois simulés)")
ax.set_xlabel("P&L mensuel (€)"); ax.set_ylabel("Nombre de mois")
ax.legend(); ax.grid(alpha=0.3)

fig.suptitle("CompensationGrid_EA — XAUUSD — Capital 10 000 € — Coûts Roboforex ECN (spread 0,18$ + 15€/lot)",
             fontsize=11)
fig.tight_layout()
fig.savefig("/tmp/simulation_compgrid_xauusd.png", dpi=130)
print("Graphique: /tmp/simulation_compgrid_xauusd.png")
