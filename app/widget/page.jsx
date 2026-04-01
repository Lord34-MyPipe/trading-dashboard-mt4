"use client";

import { useEffect, useState } from "react";

const fmtEur = (n, currency = "€") => {
  const abs = Math.abs(Number(n)).toLocaleString("fr-FR", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  return `${Number(n) >= 0 ? "+" : "-"}${abs} ${currency}`;
};

const fmtPct = (n) => `${Number(n) >= 0 ? "+" : ""}${Number(n).toFixed(2)}%`;

export default function Widget() {
  const [data, setData] = useState(null);
  const [lastUpdate, setLastUpdate] = useState(null);
  const [error, setError] = useState(null);

  const fetchData = async () => {
    try {
      const res = await fetch("/api/accounts");
      if (!res.ok) throw new Error("fetch failed");
      const json = await res.json();
      setData(json);
      setLastUpdate(new Date());
      setError(null);
    } catch (e) {
      setError("Connexion perdue");
    }
  };

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 30_000);
    return () => clearInterval(interval);
  }, []);

  const global = data?.accounts
    ? data.accounts.reduce(
        (acc, a) => ({
          balance: acc.balance + (a.balance || 0),
          equity: acc.equity + (a.equity || 0),
          floatingPL: acc.floatingPL + (a.floatingPL || 0),
          profitDay: acc.profitDay + (a.profitDay || 0),
          profitMonth: acc.profitMonth + (a.profitMonth || 0),
          profitYear: acc.profitYear + (a.profitYear || 0),
        }),
        { balance: 0, equity: 0, floatingPL: 0, profitDay: 0, profitMonth: 0, profitYear: 0 }
      )
    : null;

  const floatingPct = global?.balance
    ? (global.floatingPL / global.balance) * 100
    : 0;

  return (
    <>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@300;400;600&family=IBM+Plex+Sans:wght@300;400;600&display=swap');
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { background: transparent; font-family: 'IBM Plex Sans', sans-serif; -webkit-font-smoothing: antialiased; }

        .widget {
          width: 320px;
          background: rgba(10, 14, 26, 0.92);
          backdrop-filter: blur(20px);
          border: 1px solid rgba(255,255,255,0.08);
          border-radius: 16px;
          padding: 16px;
          color: #e2e8f0;
          box-shadow: 0 24px 60px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,255,255,0.06);
        }
        .header {
          display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px;
        }
        .title {
          font-size: 11px; font-weight: 600; letter-spacing: 0.12em;
          text-transform: uppercase; color: rgba(255,255,255,0.4);
        }
        .live-dot {
          display: flex; align-items: center; gap: 5px;
          font-size: 10px; color: rgba(255,255,255,0.35); font-family: 'IBM Plex Mono', monospace;
        }
        .dot {
          width: 6px; height: 6px; border-radius: 50%;
          background: #22c55e; box-shadow: 0 0 6px #22c55e; animation: pulse 2s infinite;
        }
        .dot.error { background: #ef4444; box-shadow: 0 0 6px #ef4444; animation: none; }
        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.4; } }

        .balance-row { display: flex; gap: 10px; margin-bottom: 10px; }

        .card {
          flex: 1;
          background: rgba(255,255,255,0.04);
          border: 1px solid rgba(255,255,255,0.07);
          border-radius: 10px; padding: 10px 12px;
        }
        .card-label {
          font-size: 9px; font-weight: 600; letter-spacing: 0.1em;
          text-transform: uppercase; color: rgba(255,255,255,0.3); margin-bottom: 4px;
        }
        .card-value {
          font-family: 'IBM Plex Mono', monospace;
          font-size: 15px; font-weight: 600; color: #f1f5f9;
          line-height: 1.2; white-space: nowrap;
        }
        .card-sub {
          font-family: 'IBM Plex Mono', monospace; font-size: 10px; margin-top: 3px;
        }
        .neg { color: #f87171; }
        .pos { color: #4ade80; }
        .neutral { color: #94a3b8; }

        .profits { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }
        .profit-card {
          background: rgba(255,255,255,0.03);
          border: 1px solid rgba(255,255,255,0.06);
          border-radius: 8px; padding: 8px 10px;
        }
        .profit-label {
          font-size: 8px; font-weight: 600; letter-spacing: 0.1em;
          text-transform: uppercase; color: rgba(255,255,255,0.25); margin-bottom: 4px;
        }
        .profit-value {
          font-family: 'IBM Plex Mono', monospace; font-size: 11px; font-weight: 600;
        }
        .profit-pct {
          font-family: 'IBM Plex Mono', monospace; font-size: 9px; margin-top: 2px;
          color: rgba(255,255,255,0.2);
        }
        .skeleton {
          background: linear-gradient(90deg, rgba(255,255,255,0.04) 25%, rgba(255,255,255,0.08) 50%, rgba(255,255,255,0.04) 75%);
          background-size: 200% 100%; animation: shimmer 1.5s infinite; border-radius: 4px; height: 20px;
        }
        @keyframes shimmer { 0% { background-position: 200% 0; } 100% { background-position: -200% 0; } }

        .equity-bar { margin-bottom: 10px; }
        .equity-label {
          display: flex; justify-content: space-between;
          font-size: 9px; color: rgba(255,255,255,0.25); margin-bottom: 4px;
          font-family: 'IBM Plex Mono', monospace;
        }
        .bar-track {
          height: 3px; background: rgba(255,255,255,0.07); border-radius: 2px; overflow: hidden;
        }
        .bar-fill {
          height: 100%; border-radius: 2px; transition: width 0.5s ease;
        }
      `}</style>

      <div className="widget">
        <div className="header">
          <span className="title">Vue Globale</span>
          <div className="live-dot">
            <div className={`dot ${error ? "error" : ""}`} />
            {lastUpdate
              ? lastUpdate.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit", second: "2-digit" })
              : "—"}
          </div>
        </div>

        {!global ? (
          <>
            <div className="balance-row">
              <div className="card"><div className="skeleton" /></div>
              <div className="card"><div className="skeleton" /></div>
            </div>
            <div className="profits">
              {[1,2,3].map(i => <div key={i} className="profit-card"><div className="skeleton" /></div>)}
            </div>
          </>
        ) : (
          <>
            <div className="balance-row">
              {/* Balance */}
              <div className="card">
                <div className="card-label">Balance Totale</div>
                <div className="card-value">
                  {Number(global.balance).toLocaleString("fr-FR", { minimumFractionDigits: 2 })} €
                </div>
              </div>
              {/* Floating P&L */}
              <div className="card">
                <div className="card-label">Floating P&L</div>
                <div className={`card-value ${global.floatingPL >= 0 ? "pos" : "neg"}`}>
                  {fmtEur(global.floatingPL)}
                </div>
                <div className={`card-sub ${floatingPct >= 0 ? "pos" : "neg"}`}>
                  {fmtPct(floatingPct)}
                </div>
              </div>
            </div>

            {/* Barre Equity vs Balance */}
            <div className="equity-bar">
              <div className="equity-label">
                <span>Equity</span>
                <span style={{ color: global.equity >= global.balance ? "#4ade80" : "#f87171" }}>
                  {Number(global.equity).toLocaleString("fr-FR", { minimumFractionDigits: 2 })} €
                </span>
              </div>
              <div className="bar-track">
                <div
                  className="bar-fill"
                  style={{
                    width: `${Math.min(100, Math.max(0, (global.equity / global.balance) * 100))}%`,
                    background: global.equity >= global.balance ? "#4ade80" : "#f87171",
                  }}
                />
              </div>
            </div>

            {/* Profits */}
            <div className="profits">
              {[
                { label: "Jour",  val: global.profitDay,   pct: global.balance ? (global.profitDay / global.balance) * 100 : 0 },
                { label: "Mois",  val: global.profitMonth, pct: global.balance ? (global.profitMonth / global.balance) * 100 : 0 },
                { label: "Année", val: global.profitYear,  pct: global.balance ? (global.profitYear / global.balance) * 100 : 0 },
              ].map(({ label, val, pct }) => (
                <div key={label} className="profit-card">
                  <div className="profit-label">{label}</div>
                  <div className={`profit-value ${val > 0 ? "pos" : val < 0 ? "neg" : "neutral"}`}>
                    {val === 0 ? "0,00 €" : fmtEur(val)}
                  </div>
                  <div className={`profit-pct ${pct > 0 ? "pos" : pct < 0 ? "neg" : ""}`}>
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
