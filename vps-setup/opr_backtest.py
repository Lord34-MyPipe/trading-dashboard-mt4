"""
OPR Strategy Backtest - XAU/USD
===============================
Backtest fidele de la strategie OPR (Opening Range Breakout) sur 3 ans
de donnees M1 XAU/USD avec les regles exactes du prompt utilisateur.

Sources de donnees supportees (par ordre de preference) :
  1. Dukascopy via `dukascopy-python` (3+ ans M1 gratuit, recommande)
  2. yfinance (M1 limite a 7 jours, M5 a 60 jours - demo seulement)
  3. CSV local au format HistData.com (telechargement manuel mensuel)

Usage :
    pip install pandas numpy matplotlib dukascopy-python pyarrow
    python opr_backtest.py

    # Avec yfinance fallback :
    python opr_backtest.py --source yfinance

    # Avec CSV HistData :
    python opr_backtest.py --source csv --csv-path histdata_xauusd_*.csv

Sortie :
  - opr_backtest_trades.csv   (toutes les transactions)
  - opr_equity_curve.png      (courbe d'equity)
  - statistiques sur stdout
"""

import argparse
import sys
import warnings
from datetime import datetime, timedelta, time
from pathlib import Path

import numpy as np
import pandas as pd

warnings.filterwarnings('ignore')

# ============================================================
# CONFIGURATION
# ============================================================
CFG = {
    # --- Timing (heures en ET, fuseau America/New_York) ---
    'NY_open_ET_hour':       9,
    'NY_open_ET_min':        30,
    'range_duration_min':    30,
    'eod_ET_hour':           15,
    'eod_ET_min':            30,

    # --- Filtres techniques ---
    'atr_period':            14,
    'atr_sma_period':        20,
    'min_body_ratio':        0.60,
    'filter_atr':            True,
    'min_range_pips':        200,
    'max_range_pips':        600,

    # --- Conversions Gold ---
    'pip_size_price':        0.10,    # 1 pip = $0.10 mouvement de prix
    'lot_contract_size':     100.0,   # 1 lot XAUUSD = 100 oz
    'min_lot':               0.01,
    'lot_step':              0.01,

    # --- Gestion du trade ---
    'rr_tp1':                1.75,
    'scale_out_pct':         0.75,
    'trail_multiplier':      0.50,

    # --- Filtres calendrier ---
    'no_friday':             True,

    # --- Capital / risque ---
    'initial_capital':       15000.0,
    'risk_pct':              0.01,

    # --- Data ---
    'years_history':         3,
    'cache_path':            'gold_m1_cache.parquet',
}

# ============================================================
# DATA LOADERS
# ============================================================

def fetch_dukascopy():
    """3+ ans de XAUUSD M1 via dukascopy-python (gratuit)."""
    try:
        from dukascopy_python import fetch
        from dukascopy_python.instruments import (
            INSTRUMENT_FX_METALS_XAU_USD,
        )
        from dukascopy_python import INTERVAL_MIN_1, OFFER_SIDE_BID
    except ImportError:
        print("[!] dukascopy-python non installe : pip install dukascopy-python")
        return None

    end = datetime.utcnow()
    start = end - timedelta(days=365 * CFG['years_history'])
    print(f"[Dukascopy] Telechargement XAUUSD M1 {start.date()} -> {end.date()}")
    print("            (peut prendre 5-15 min sur 3 ans)")

    try:
        df = fetch(
            INSTRUMENT_FX_METALS_XAU_USD,
            INTERVAL_MIN_1,
            OFFER_SIDE_BID,
            start,
            end,
        )
        df.index = pd.to_datetime(df.index, utc=True)
        df.columns = [c.lower() for c in df.columns]
        cols = [c for c in ['open', 'high', 'low', 'close', 'volume'] if c in df.columns]
        return df[cols]
    except Exception as e:
        print(f"[!] Dukascopy a echoue : {e}")
        return None


def fetch_yfinance():
    """Fallback yfinance - donnees tres limitees."""
    try:
        import yfinance as yf
    except ImportError:
        print("[!] yfinance non installe : pip install yfinance")
        return None

    print("[yfinance] AVERT : limite a 60 jours en M5, 7 jours en M1.")
    print("[yfinance] Telechargement GC=F (Gold futures) en M5 sur 60 jours...")
    df = yf.download('GC=F', period='60d', interval='5m', progress=False, auto_adjust=False)
    if df.empty:
        return None
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = [c[0].lower() for c in df.columns]
    else:
        df.columns = [c.lower() for c in df.columns]
    if df.index.tz is None:
        df.index = df.index.tz_localize('UTC')
    else:
        df.index = df.index.tz_convert('UTC')
    return df[['open', 'high', 'low', 'close', 'volume']]


def fetch_csv(path_pattern):
    """Charge des CSV au format HistData.com (point-virgules)."""
    files = sorted(Path('.').glob(path_pattern))
    if not files:
        print(f"[!] Aucun CSV ne match {path_pattern}")
        return None
    print(f"[CSV] {len(files)} fichier(s) trouve(s)")
    frames = []
    for f in files:
        df = pd.read_csv(f, sep=';', header=None,
                         names=['datetime', 'open', 'high', 'low', 'close', 'volume'])
        df['datetime'] = pd.to_datetime(df['datetime'], format='%Y%m%d %H%M%S')
        df = df.set_index('datetime').tz_localize('UTC')
        frames.append(df)
    return pd.concat(frames).sort_index()


def load_data(source='dukascopy', csv_path=None):
    cache = Path(CFG['cache_path'])
    if cache.exists():
        print(f"[Cache] Chargement depuis {cache}")
        return pd.read_parquet(cache)

    df = None
    if source == 'dukascopy':
        df = fetch_dukascopy()
    elif source == 'yfinance':
        df = fetch_yfinance()
    elif source == 'csv':
        df = fetch_csv(csv_path)

    if df is None or df.empty:
        raise RuntimeError(f"Source '{source}' n'a fourni aucune donnee.")

    df = df[~df.index.duplicated(keep='first')].sort_index()
    df.to_parquet(cache)
    print(f"[Cache] {len(df):,} bougies sauvees dans {cache}")
    return df


# ============================================================
# INDICATEURS
# ============================================================

def compute_atr(df, period):
    """ATR de Wilder (rolling mean True Range, suffisamment fidele)."""
    h, l, c = df['high'], df['low'], df['close']
    pc = c.shift(1)
    tr = pd.concat([h - l, (h - pc).abs(), (l - pc).abs()], axis=1).max(axis=1)
    return tr.rolling(period).mean()


# ============================================================
# BACKTEST ENGINE
# ============================================================

def backtest(df_m1):
    """
    Execute le backtest OPR fidele a la specification MT4.
    df_m1: DataFrame UTC, OHLC M1.
    Returns: (trades_df, equity_df)
    """
    # Resampling
    df_m5 = df_m1.resample('5min').agg({
        'open': 'first', 'high': 'max', 'low': 'min', 'close': 'last',
    }).dropna()
    df_h1 = df_m1.resample('1h').agg({
        'open': 'first', 'high': 'max', 'low': 'min', 'close': 'last',
    }).dropna()

    df_h1['atr14'] = compute_atr(df_h1, CFG['atr_period'])
    df_h1['atr14_sma'] = df_h1['atr14'].rolling(CFG['atr_sma_period']).mean()
    df_m5['atr14_m5'] = compute_atr(df_m5, CFG['atr_period'])

    # Reindex en heure de New York pour le calcul des sessions
    df_m1_et = df_m1.copy()
    df_m1_et.index = df_m1_et.index.tz_convert('America/New_York')
    df_m5_et = df_m5.copy()
    df_m5_et.index = df_m5_et.index.tz_convert('America/New_York')
    df_h1_et = df_h1.copy()
    df_h1_et.index = df_h1_et.index.tz_convert('America/New_York')

    trades = []
    equity = CFG['initial_capital']
    equity_curve = [(df_m1.index[0].date(), equity)]

    dates = sorted({ts.date() for ts in df_m1_et.index})
    for d in dates:
        dow = d.weekday()
        if dow >= 5:
            continue
        if CFG['no_friday'] and dow == 4:
            equity_curve.append((d, equity))
            continue

        ny_open = pd.Timestamp.combine(d, time(CFG['NY_open_ET_hour'], CFG['NY_open_ET_min']))
        ny_open = ny_open.tz_localize('America/New_York')
        range_end = ny_open + pd.Timedelta(minutes=CFG['range_duration_min'])
        eod = pd.Timestamp.combine(d, time(CFG['eod_ET_hour'], CFG['eod_ET_min']))
        eod = eod.tz_localize('America/New_York')

        # 1) Construire le range OPR depuis M1
        rb = df_m1_et[(df_m1_et.index >= ny_open) & (df_m1_et.index < range_end)]
        if len(rb) < 5:
            continue
        opr_high = rb['high'].max()
        opr_low = rb['low'].min()
        range_price = opr_high - opr_low
        range_pips = range_price / CFG['pip_size_price']
        if not (CFG['min_range_pips'] <= range_pips <= CFG['max_range_pips']):
            equity_curve.append((d, equity))
            continue

        # 2) Filtre ATR H1
        if CFG['filter_atr']:
            h1_pre = df_h1_et[df_h1_et.index <= range_end]
            if len(h1_pre) == 0:
                continue
            atr_now = h1_pre['atr14'].iloc[-1]
            atr_sma = h1_pre['atr14_sma'].iloc[-1]
            if pd.isna(atr_now) or pd.isna(atr_sma) or atr_now <= atr_sma:
                equity_curve.append((d, equity))
                continue

        # 3) Recherche signal M5 entre range_end et eod
        m5_search = df_m5_et[(df_m5_et.index >= range_end) & (df_m5_et.index < eod)]

        signal = None
        for ts, bar in m5_search.iterrows():
            rng = bar['high'] - bar['low']
            if rng <= 0:
                continue
            body = abs(bar['close'] - bar['open'])
            if body / rng < CFG['min_body_ratio']:
                continue
            if bar['close'] > opr_high:
                signal = ('long', ts, bar)
                break
            if bar['close'] < opr_low:
                signal = ('short', ts, bar)
                break

        if signal is None:
            equity_curve.append((d, equity))
            continue

        direction, sig_ts, sig_bar = signal
        atr_m5 = sig_bar['atr14_m5'] if pd.notna(sig_bar['atr14_m5']) else 0.5
        entry = sig_bar['close']
        if direction == 'long':
            sl = opr_low - atr_m5 * 0.5
            tp1 = entry + abs(entry - sl) * CFG['rr_tp1']
        else:
            sl = opr_high + atr_m5 * 0.5
            tp1 = entry - abs(entry - sl) * CFG['rr_tp1']
        sl_dist = abs(entry - sl)
        if sl_dist <= 0:
            continue

        # 4) Lot sizing (1% du capital courant)
        risk_money = equity * CFG['risk_pct']
        money_per_price_per_lot = CFG['lot_contract_size']
        raw_lot = risk_money / (sl_dist * money_per_price_per_lot)
        total_lot = max(CFG['min_lot'],
                        np.floor(raw_lot / CFG['lot_step']) * CFG['lot_step'])
        lot_tp1 = np.floor(total_lot * CFG['scale_out_pct'] / CFG['lot_step']) * CFG['lot_step']
        lot_trail = total_lot - lot_tp1
        if lot_trail < CFG['min_lot']:
            lot_tp1 = total_lot
            lot_trail = 0.0

        # 5) Simulation barre par barre (M1) jusqu'a SL/TP1/Trail/EOD
        post = df_m1_et[(df_m1_et.index > sig_ts) & (df_m1_et.index <= eod)]

        tp1_filled = False
        trail_sl = sl
        trail_step = range_price * CFG['trail_multiplier']
        max_fav_price = entry
        exit_tp1 = None
        exit_trail = None

        for ts2, bar2 in post.iterrows():
            h, l = bar2['high'], bar2['low']

            if direction == 'long':
                # ordre du test : SL avant TP pour conservatisme intra-bougie
                if not tp1_filled and l <= sl:
                    exit_tp1 = ('SL', sl, ts2)
                    if lot_trail > 0:
                        exit_trail = ('SL', sl, ts2)
                    break
                if tp1_filled and lot_trail > 0 and l <= trail_sl:
                    exit_trail = ('TRAIL', trail_sl, ts2)
                    break
                if not tp1_filled and h >= tp1:
                    exit_tp1 = ('TP1', tp1, ts2)
                    tp1_filled = True
                if tp1_filled and lot_trail > 0:
                    max_fav_price = max(max_fav_price, h)
                    new_trail = max_fav_price - trail_step
                    if new_trail > trail_sl:
                        trail_sl = new_trail
            else:  # short
                if not tp1_filled and h >= sl:
                    exit_tp1 = ('SL', sl, ts2)
                    if lot_trail > 0:
                        exit_trail = ('SL', sl, ts2)
                    break
                if tp1_filled and lot_trail > 0 and h >= trail_sl:
                    exit_trail = ('TRAIL', trail_sl, ts2)
                    break
                if not tp1_filled and l <= tp1:
                    exit_tp1 = ('TP1', tp1, ts2)
                    tp1_filled = True
                if tp1_filled and lot_trail > 0:
                    max_fav_price = min(max_fav_price, l) if max_fav_price != entry else l
                    new_trail = max_fav_price + trail_step
                    if new_trail < trail_sl:
                        trail_sl = new_trail

        last_price = post['close'].iloc[-1] if len(post) > 0 else entry
        last_ts = post.index[-1] if len(post) > 0 else sig_ts
        if exit_tp1 is None:
            exit_tp1 = ('EOD', last_price, last_ts)
        if lot_trail > 0 and exit_trail is None:
            exit_trail = ('EOD', last_price, last_ts)

        sign = 1 if direction == 'long' else -1
        pnl_tp1 = sign * (exit_tp1[1] - entry) * CFG['lot_contract_size'] * lot_tp1
        pnl_trail = 0.0
        if lot_trail > 0 and exit_trail is not None:
            pnl_trail = sign * (exit_trail[1] - entry) * CFG['lot_contract_size'] * lot_trail
        pnl = pnl_tp1 + pnl_trail

        equity += pnl

        trades.append({
            'date': d,
            'direction': direction,
            'entry_time': sig_ts,
            'entry': round(entry, 3),
            'sl': round(sl, 3),
            'tp1': round(tp1, 3),
            'range_pips': round(range_pips, 1),
            'lot_tp1': round(lot_tp1, 2),
            'lot_trail': round(lot_trail, 2),
            'exit_tp1': exit_tp1[0],
            'exit_tp1_px': round(exit_tp1[1], 3),
            'exit_trail': exit_trail[0] if exit_trail else '-',
            'exit_trail_px': round(exit_trail[1], 3) if exit_trail else 0.0,
            'pnl': round(pnl, 2),
            'equity': round(equity, 2),
        })
        equity_curve.append((d, equity))

    trades_df = pd.DataFrame(trades)
    eq_df = pd.DataFrame(equity_curve, columns=['date', 'equity']).set_index('date')
    eq_df = eq_df[~eq_df.index.duplicated(keep='last')]
    return trades_df, eq_df


# ============================================================
# STATISTIQUES
# ============================================================

def compute_stats(trades, eq):
    if len(trades) == 0:
        return {'error': 'Aucun trade genere'}

    n = len(trades)
    wins = (trades['pnl'] > 0).sum()
    losses = (trades['pnl'] < 0).sum()
    gross_p = trades.loc[trades['pnl'] > 0, 'pnl'].sum()
    gross_l = -trades.loc[trades['pnl'] < 0, 'pnl'].sum()
    pf = gross_p / gross_l if gross_l > 0 else float('inf')

    e = eq['equity']
    rm = e.cummax()
    dd = (e - rm) / rm
    max_dd = dd.min()

    tdf = trades.copy()
    tdf['month'] = pd.to_datetime(tdf['date']).dt.to_period('M')
    by_month = tdf.groupby('month').agg(
        pnl=('pnl', 'sum'),
        trades=('pnl', 'count'),
        win_rate=('pnl', lambda x: (x > 0).mean()),
    )

    return {
        'total_trades': n,
        'wins': int(wins),
        'losses': int(losses),
        'win_rate_pct': 100 * wins / n,
        'profit_factor': pf,
        'gross_profit_eur': gross_p,
        'gross_loss_eur': -gross_l,
        'net_pnl_eur': trades['pnl'].sum(),
        'final_equity_eur': e.iloc[-1],
        'return_pct': 100 * (e.iloc[-1] / CFG['initial_capital'] - 1),
        'max_drawdown_pct': 100 * max_dd,
        'avg_monthly_gain_eur': by_month['pnl'].mean(),
        'avg_monthly_trades': by_month['trades'].mean(),
        'months': len(by_month),
        'by_month': by_month,
    }


def print_stats(s):
    if 'error' in s:
        print("\n!!", s['error'])
        return
    print("\n" + "=" * 60)
    print("RESULTATS BACKTEST OPR XAU/USD")
    print("=" * 60)
    rows = [
        ('Trades totaux',            f"{s['total_trades']}"),
        ('Wins / Losses',            f"{s['wins']} / {s['losses']}"),
        ('Win Rate',                 f"{s['win_rate_pct']:.1f} %"),
        ('Profit Factor',            f"{s['profit_factor']:.2f}"),
        ('Gross Profit',             f"{s['gross_profit_eur']:>+10.2f} EUR"),
        ('Gross Loss',               f"{s['gross_loss_eur']:>+10.2f} EUR"),
        ('Net P&L',                  f"{s['net_pnl_eur']:>+10.2f} EUR"),
        ('Capital final',            f"{s['final_equity_eur']:>10.2f} EUR"),
        ('Return total',             f"{s['return_pct']:>+10.2f} %"),
        ('Drawdown max',             f"{s['max_drawdown_pct']:>+10.2f} %"),
        ('Gain mensuel moyen',       f"{s['avg_monthly_gain_eur']:>+10.2f} EUR"),
        ('Trades / mois (moyen)',    f"{s['avg_monthly_trades']:.1f}"),
        ('Mois couverts',            f"{s['months']}"),
    ]
    for k, v in rows:
        print(f"  {k:28s}: {v}")
    print("\nP&L mensuel detaille :")
    print(s['by_month'].round(2).to_string())


# ============================================================
# EQUITY CURVE
# ============================================================

def plot_equity(eq, out='opr_equity_curve.png'):
    import matplotlib.pyplot as plt
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(13, 8), sharex=True,
                                   gridspec_kw={'height_ratios': [3, 1]})
    dates = pd.to_datetime(eq.index)
    ax1.plot(dates, eq['equity'], lw=1.4, color='#2c5fa6')
    ax1.axhline(CFG['initial_capital'], color='gray', ls='--', lw=0.8)
    ax1.set_ylabel('Equity (EUR)')
    ax1.set_title(f"OPR XAU/USD - {dates.min().date()} -> {dates.max().date()} "
                  f"- {CFG['risk_pct']*100:.1f}% risque")
    ax1.grid(True, alpha=0.3)

    rm = eq['equity'].cummax()
    dd = 100 * (eq['equity'] - rm) / rm
    ax2.fill_between(dates, dd, 0, color='#c0392b', alpha=0.6)
    ax2.set_ylabel('Drawdown %')
    ax2.set_xlabel('Date')
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(out, dpi=120)
    print(f"\n[Plot] Equity curve sauvegardee : {out}")


# ============================================================
# MAIN
# ============================================================

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--source', choices=['dukascopy', 'yfinance', 'csv'],
                   default='dukascopy',
                   help='Source des donnees (dukascopy recommande pour 3 ans M1)')
    p.add_argument('--csv-path', default='histdata_xauusd_*.csv',
                   help='Pattern pour les CSV HistData (si --source csv)')
    p.add_argument('--no-cache', action='store_true',
                   help='Ignorer le cache parquet existant')
    args = p.parse_args()

    if args.no_cache and Path(CFG['cache_path']).exists():
        Path(CFG['cache_path']).unlink()

    print("=" * 60)
    print(f"OPR XAU/USD - Backtest {CFG['years_history']} ans")
    print(f"Capital initial : {CFG['initial_capital']:.0f} EUR")
    print(f"Risque / trade  : {CFG['risk_pct']*100:.2f} %")
    print(f"Source data     : {args.source}")
    print("=" * 60)

    df = load_data(source=args.source, csv_path=args.csv_path)
    print(f"\n[Data] {len(df):,} bougies | {df.index.min()} -> {df.index.max()}")
    span_days = (df.index.max() - df.index.min()).days
    print(f"[Data] Periode couverte : {span_days} jours")
    if span_days < 365:
        print("[!] ATTENTION : moins d'un an de donnees, resultats peu significatifs.")

    trades, eq = backtest(df)
    print(f"\n[Backtest] {len(trades)} trades generes")
    if len(trades) > 0:
        trades.to_csv('opr_backtest_trades.csv', index=False)
        print("[Backtest] Trades sauves : opr_backtest_trades.csv")

    stats = compute_stats(trades, eq)
    print_stats(stats)

    if len(eq) > 1:
        try:
            plot_equity(eq)
        except Exception as e:
            print(f"[!] Plot non genere : {e}")


if __name__ == '__main__':
    main()
