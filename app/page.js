"use client";

import { useEffect, useState, useMemo } from "react";

// ── Exactement les mêmes helpers que page.js ──────────────────
const EUR_USD_RATE = 1.08;
const toEUR = (value, currency) => currency === "USD" ? value / EUR_USD_RATE : value;
const fmtMoney = (v) => {
  if (v == null) return "0,00 €";
  const formatted = Math.abs(v).toLocaleString("fr-FR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return `${v < 0 ? "-" : ""}${formatted} €`;
};
const fmtPct = (v) => `${(v || 0) >= 0 ? "+" : ""}${(v || 0).toFixed(2)}%`;

export default function Widget() {
  const [accounts, setAccounts] = useState([]);
  const [lastUpdate, setLastUpdate] = useState(null);
  const [error, setError] = useState(null);

  const fetchData = async () => {
    try {
      const res = await fetch("/api/accounts");
      if (!res.ok) throw new Error("fetch failed");
      const json = await res.json();
      if (json.accounts?.length > 0) {
        const normalized = json.accounts.map((a) => ({
          ...a,
          currency: a.currency || "EUR",
          floatingPL: a.floatingPL || 0,
          dailyProfit: a.dailyProfit || 0,
          monthlyProfit: a.monthlyProfit || 0,
          yearlyProfit: a.yearlyProfit || 0,
          dailyReturnPct: a.dailyReturnPct || 0,
          monthlyReturnPct: a.monthlyReturnPct || 0,
          yearlyReturnPct: a.yearlyReturnPct || 0,
        }));
        setAccounts(normalized);
        setLastUpdate(new Date());
        setError(null);
      }
    } catch (e) {
      setError("Connexion perdue");
    }
  };

  useEffect(() => {
    fetchData();
    const id = setInterval(fetchData, 30_000);
    return () => clearInterval(id);
  }, []);

  // ── Exactement le même calcul global que page.js ─────────────
  const global = useMemo(() => {
    if (!accounts.length) return null;
    const totalBalance  = accounts.reduce((s, a) => s + toEUR(a.balance, a.currency), 0);
    const totalEquity   = accounts.reduce((s, a) => s + toEUR(a.equity,  a.currency), 0);
    const totalFloating = accounts.reduce((s, a) => s + toEUR(a.floatingPL, a.currency), 0);
    const totalDaily    = accounts.reduce((s, a) => s + toEUR(a.dailyProfit,   a.currency), 0);
    const totalMonthly  = accounts.reduce((s, a) => s + toEUR(a.monthlyProfit, a.currency), 0);
    const totalYearly   = accounts.reduce((s, a) => s + toEUR(a.yearlyProfit,  a.currency), 0);

    const globalFloatingPct  = totalBalance > 0 ? (totalFloating / totalBalance) * 100 : 0;
    const startDay   = totalBalance - totalDaily;
    const startMonth = totalBalance - totalMonthly;
    const startYear  = totalBalance - totalYearly;
    const dailyReturnPct   = startDay   > 0 ? (totalDaily   / startDay)   * 100 : 0;
    const monthlyReturnPct = startMonth > 0 ? (totalMonthly / startMonth) * 100 : 0;
    const yearlyReturnPct  = startYear  > 0 ? (totalYearly  / startYear)  * 100 : 0;

    return { totalBalance, totalEquity, totalFloating, globalFloatingPct,
             totalDaily, totalMonthly, totalYearly,
             dailyReturnPct, monthlyReturnPct, yearlyReturnPct };
  }, [accounts]);

  return (
    <>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans:wght@400;600&display=swap');
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { background: transparent; font-family: 'IBM Plex Sans', sans-serif; -webkit-font-smoothing: antialiased; }

        .w { width: 320px; background: rgba(10,14,26,0.93); backdrop-filter: blur(20px);
             border: 1px solid rgba(255,255,255,0.08); border-radius: 16px; padding: 14px;
             box-shadow: 0 24px 60px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,255,255,0.06); color: #e2e8f0; }

        .hdr { display:flex; align-items:center; justify-content:space-between; margin-bottom:12px; }
        .ttl { font-size:10px; font-weight:600; letter-spacing:.12em; text-transform:uppercase; color:rgba(255,255,255,0.35); }
        .live { display:flex; align-items:center; gap:5px; font-size:10px; color:rgba(255,255,255,0.3); font-family:'IBM Plex Mono',monospace; }
        .dot { width:6px; height:6px; border-radius:50%; background:#22c55e; box-shadow:0 0 6px #22c55e; animation:pulse 2s infinite; }
        .dot.err { background:#ef4444; box-shadow:0 0 6px #ef4444; animation:none; }
        @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:.4} }

        .row2 { display:flex; gap:8px; margin-bottom:8px; }
        .card { flex:1; background:rgba(255,255,255,0.04); border:1px solid rgba(255,255,255,0.07); border-radius:10px; padding:9px 11px; }
        .card.red { border-color:rgba(248,113,113,.3); background:rgba(248,113,113,.05); }
        .card.grn { border-color:rgba(74,222,128,.3); background:rgba(74,222,128,.05); }
        .lbl { font-size:9px; font-weight:600; letter-spacing:.1em; text-transform:uppercase; color:rgba(255,255,255,.28); margin-bottom:3px; }
        .val { font-family:'IBM Plex Mono',monospace; font-size:15px; font-weight:600; color:#f1f5f9; white-space:nowrap; line-height:1.2; }
        .sub { font-family:'IBM Plex Mono',monospace; font-size:10px; margin-top:2px; }
        .pos { color:#4ade80; } .neg { color:#f87171; } .neu { color:#94a3b8; }

        .grid3 { display:grid; grid-template-columns:repeat(3,1fr); gap:7px; }
        .pcrd { background:rgba(255,255,255,.03); border:1px solid rgba(255,255,255,.06); border-radius:8px; padding:7px 9px; }
        .pcrd.pos-bg { border-color:rgba(74,222,128,.2); background:rgba(74,222,128,.04); }
        .pcrd.neg-bg { border-color:rgba(248,113,113,.2); background:rgba(248,113,113,.04); }
        .plbl { font-size:8px; font-weight:600; letter-spacing:.1em; text-transform:uppercase; color:rgba(255,255,255,.22); margin-bottom:3px; }
        .pval { font-family:'IBM Plex Mono',monospace; font-size:11px; font-weight:600; }
        .ppct { font-family:'IBM Plex Mono',monospace; font-size:9px; margin-top:2px; color:rgba(255,255,255,.2); }
        .ppct.pos{color:rgba(74,222,128,.55);} .ppct.neg{color:rgba(248,113,113,.55);}

        .skel { background:linear-gradient(90deg,rgba(255,255,255,.04) 25%,rgba(255,255,255,.08) 50%,rgba(255,255,255,.04) 75%);
                background-size:200% 100%; animation:shim 1.5s infinite; border-radius:4px; height:18px; }
        @keyframes shim{0%{background-position:200% 0}100%{background-position:-200% 0}}
      `}</style>

      <div className="w">
        {/* Header */}
        <div className="hdr">
          <span className="ttl">Vue Globale</span>
          <div className="live">
            <div className={`dot${error ? " err" : ""}`} />
            {lastUpdate ? lastUpdate.toLocaleTimeString("fr-FR") : "—"}
          </div>
        </div>

        {!global ? (
          <>
            <div className="row2">
              <div className="card"><div className="skel" /></div>
              <div className="card"><div className="skel" /></div>
            </div>
            <div className="grid3">{[1,2,3].map(i=><div key={i} className="pcrd"><div className="skel"/></div>)}</div>
          </>
        ) : (
          <>
            {/* Balance + Floating */}
            <div className="row2">
              <div className="card">
                <div className="lbl">Balance Totale</div>
                <div className="val">{fmtMoney(global.totalBalance)}</div>
              </div>
              <div className={`card ${global.totalFloating >= 0 ? "grn" : "red"}`}>
                <div className="lbl">Floating</div>
                <div className={`val ${global.totalFloating >= 0 ? "pos" : "neg"}`}>
                  {fmtMoney(global.totalFloating)}
                </div>
                <div className={`sub ${global.globalFloatingPct >= 0 ? "pos" : "neg"}`}>
                  {fmtPct(global.globalFloatingPct)}
                </div>
              </div>
            </div>

            {/* Profits Jour / Mois / Année */}
            <div className="grid3">
              {[
                { label:"Jour",  val:global.totalDaily,   pct:global.dailyReturnPct },
                { label:"Mois",  val:global.totalMonthly, pct:global.monthlyReturnPct },
                { label:"Année", val:global.totalYearly,  pct:global.yearlyReturnPct },
              ].map(({label,val,pct}) => (
                <div key={label} className={`pcrd ${val>0?"pos-bg":val<0?"neg-bg":""}`}>
                  <div className="plbl">{label}</div>
                  <div className={`pval ${val>0?"pos":val<0?"neg":"neu"}`}>
                    {val===0 ? "0,00 €" : fmtMoney(val)}
                  </div>
                  <div className={`ppct ${pct>0?"pos":pct<0?"neg":""}`}>
                    {fmtPct(pct)}
                  </div>
                </div>
              ))}
            </div>
          </>
        )}
      </div>
    </>
  );
}
