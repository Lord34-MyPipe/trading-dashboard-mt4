'use client';

import { useState, useEffect, useCallback, useMemo } from 'react';
import {
  RefreshCw, TrendingUp, TrendingDown, Eye, EyeOff,
  ChevronDown, ChevronUp, Clock, Zap, Shield,
} from 'lucide-react';

// ============================================================
// CONFIG
// ============================================================
const REFRESH_INTERVAL = 10000;
const EUR_USD_RATE = 1.08; // Taux approximatif pour conversion USD→EUR

// ============================================================
// HELPERS
// ============================================================
const toEUR = (value, currency) => currency === 'USD' ? value / EUR_USD_RATE : value;

const fmtMoney = (v, currency = 'EUR') => {
  if (v == null) return '0.00 €';
  const sym = currency === 'USD' ? '$' : '€';
  const formatted = Math.abs(v).toLocaleString('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return `${v < 0 ? '-' : ''}${formatted} ${sym}`;
};

const fmtPct = (v) => `${v >= 0 ? '+' : ''}${(v || 0).toFixed(2)}%`;

const plColor = (v) => v >= 0 ? 'text-green-600' : 'text-red-500';
const plBg = (v) => v >= 0 ? 'bg-green-50 border-green-200' : 'bg-red-50 border-red-200';

// ============================================================
// MAIN DASHBOARD
// ============================================================
export default function Dashboard() {
  const [accounts, setAccounts] = useState([]);
  const [expanded, setExpanded] = useState({});
  const [loading, setLoading] = useState(true);
  const [lastRefresh, setLastRefresh] = useState(null);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [showBal, setShowBal] = useState(true);
  const [apiConnected, setApiConnected] = useState(false);

  const fetchData = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetch('/api/accounts');
      if (res.ok) {
        const json = await res.json();
        if (json.accounts && json.accounts.length > 0) {
          const normalized = json.accounts.map((a) => ({
            ...a,
            id: a.id || a.accountId || String(a.accountId),
            name: a.name || a.alias || `Account ${a.accountId}`,
            login: a.login || String(a.accountId),
            currency: a.currency || 'EUR',
            positions: a.positions || [],
            drawdown: a.drawdown || 0,
            dailyPL: a.dailyPL || 0,
            monthlyPL: a.monthlyPL || 0,
            yearlyPL: a.yearlyPL || 0,
            profitability: a.profitability || 0,
            totalProfit: a.totalProfit || 0,
            initialDeposit: a.initialDeposit || a.balance || 0,
            marginLevel: a.marginLevel || 0,
          }));
          setAccounts(normalized);
          setApiConnected(true);
          setLastRefresh(new Date());
          setLoading(false);
          return;
        }
      }
    } catch (e) { /* fallback */ }
    setApiConnected(false);
    setLastRefresh(new Date());
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);
  useEffect(() => {
    if (!autoRefresh) return;
    const id = setInterval(fetchData, REFRESH_INTERVAL);
    return () => clearInterval(id);
  }, [autoRefresh, fetchData]);

  const toggle = (id) => setExpanded((p) => ({ ...p, [id]: !p[id] }));

  // ============================================================
  // GLOBAL — tout converti en EUR
  // ============================================================
  const global = useMemo(() => {
    if (!accounts.length) return null;
    const totalBalance = accounts.reduce((s, a) => s + toEUR(a.balance, a.currency), 0);
    const totalEquity = accounts.reduce((s, a) => s + toEUR(a.equity, a.currency), 0);
    const totalDailyPL = accounts.reduce((s, a) => s + toEUR(a.dailyPL, a.currency), 0);
    const totalMonthlyPL = accounts.reduce((s, a) => s + toEUR(a.monthlyPL, a.currency), 0);
    const totalYearlyPL = accounts.reduce((s, a) => s + toEUR(a.yearlyPL, a.currency), 0);
    // DD global pondéré par equity
    const totalDDeur = accounts.reduce((s, a) => {
      const eqEUR = toEUR(a.equity, a.currency);
      const ddEUR = eqEUR * (a.drawdown / 100) / (1 - a.drawdown / 100);
      return s + ddEUR;
    }, 0);
    const globalDDpct = totalEquity > 0 ? (totalDDeur / (totalEquity + totalDDeur)) * 100 : 0;
    return { totalBalance, totalEquity, totalDailyPL, totalMonthlyPL, totalYearlyPL, globalDDpct, totalDDeur };
  }, [accounts]);

  const mask = (v) => showBal ? v : '•••••';

  return (
    <div className="min-h-screen bg-white">
      {/* HEADER */}
      <header className="bg-blue-700 sticky top-0 z-50 shadow-lg">
        <div className="max-w-3xl mx-auto px-4 py-3 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 bg-white/20 rounded-xl flex items-center justify-center font-bold text-sm text-white">JB</div>
            <div>
              <h1 className="text-base font-bold text-white">Trading Dashboard</h1>
              <div className="flex items-center gap-2">
                <span className="text-xs text-blue-200">{accounts.length} comptes</span>
                {apiConnected
                  ? <span className="text-xs text-green-300 flex items-center gap-0.5"><Zap size={10} /> Live</span>
                  : <span className="text-xs text-yellow-300 flex items-center gap-0.5"><Shield size={10} /> Démo</span>
                }
              </div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <button onClick={() => setShowBal(!showBal)} className="p-2 rounded-lg bg-white/10 active:bg-white/20 text-white">
              {showBal ? <Eye size={16} /> : <EyeOff size={16} />}
            </button>
            <button onClick={() => setAutoRefresh(!autoRefresh)}
              className={`flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs font-medium ${autoRefresh ? 'bg-green-500/30 text-green-200' : 'bg-white/10 text-blue-200'}`}>
              <div className={`w-1.5 h-1.5 rounded-full ${autoRefresh ? 'bg-green-300' : 'bg-gray-400'}`} />
              {autoRefresh ? 'Live' : 'Pause'}
            </button>
            <button onClick={fetchData} disabled={loading} className="p-2 rounded-lg bg-white/20 active:bg-white/30 text-white">
              <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
            </button>
          </div>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-4 py-4 space-y-4">
        {/* ============================================================ */}
        {/* VUE GLOBALE */}
        {/* ============================================================ */}
        {global && (
          <section className="bg-blue-50 border border-blue-200 rounded-2xl p-4">
            <h2 className="text-base font-bold text-blue-800 mb-3">Vue Globale</h2>

            {/* Balance + DD */}
            <div className="grid grid-cols-2 gap-3 mb-3">
              <div className="bg-white border border-blue-200 rounded-xl p-3">
                <div className="text-xs text-blue-500 font-medium mb-1">Balance Totale</div>
                <div className="text-xl font-bold text-blue-900">{mask(fmtMoney(global.totalBalance))}</div>
              </div>
              <div className={`bg-white border rounded-xl p-3 ${global.globalDDpct > 5 ? 'border-red-300' : 'border-blue-200'}`}>
                <div className="text-xs text-blue-500 font-medium mb-1">Drawdown</div>
                <div className={`text-xl font-bold ${global.globalDDpct > 5 ? 'text-red-500' : 'text-blue-900'}`}>{mask(fmtPct(-global.globalDDpct))}</div>
                <div className={`text-xs ${global.globalDDpct > 5 ? 'text-red-400' : 'text-gray-400'}`}>{mask(fmtMoney(-global.totalDDeur))}</div>
              </div>
            </div>

            {/* P&L Jour / Mois / Année */}
            <div className="grid grid-cols-3 gap-3">
              <div className={`border rounded-xl p-3 ${plBg(global.totalDailyPL)}`}>
                <div className="text-xs text-gray-500 font-medium mb-1">P&L Jour</div>
                <div className={`text-lg font-bold ${plColor(global.totalDailyPL)}`}>{mask(fmtMoney(global.totalDailyPL))}</div>
              </div>
              <div className={`border rounded-xl p-3 ${plBg(global.totalMonthlyPL)}`}>
                <div className="text-xs text-gray-500 font-medium mb-1">P&L Mois</div>
                <div className={`text-lg font-bold ${plColor(global.totalMonthlyPL)}`}>{mask(fmtMoney(global.totalMonthlyPL))}</div>
              </div>
              <div className={`border rounded-xl p-3 ${plBg(global.totalYearlyPL)}`}>
                <div className="text-xs text-gray-500 font-medium mb-1">P&L Année</div>
                <div className={`text-lg font-bold ${plColor(global.totalYearlyPL)}`}>{mask(fmtMoney(global.totalYearlyPL))}</div>
              </div>
            </div>
          </section>
        )}

        {/* ============================================================ */}
        {/* COMPTES INDIVIDUELS */}
        {/* ============================================================ */}
        <section className="space-y-3">
          <h2 className="text-sm font-bold text-gray-500 uppercase tracking-wider">Détail par compte</h2>
          {accounts.map((acc) => {
            const cur = acc.currency || 'EUR';
            const ddEUR = toEUR(acc.equity, cur) * (acc.drawdown / 100) / Math.max(1 - acc.drawdown / 100, 0.001);
            const isOpen = expanded[acc.id];

            return (
              <div key={acc.id} className="bg-white border border-gray-200 rounded-2xl overflow-hidden shadow-sm">
                <button className="w-full p-4 text-left active:bg-gray-50 transition-colors" onClick={() => toggle(acc.id)}>
                  {/* Header ligne */}
                  <div className="flex items-center justify-between mb-3">
                    <div className="flex items-center gap-2.5 min-w-0">
                      <div className={`w-2.5 h-2.5 rounded-full shrink-0 ${cur === 'USD' ? 'bg-orange-500' : 'bg-blue-500'}`} />
                      <div className="min-w-0">
                        <h3 className="text-blue-900 font-bold text-sm truncate">{acc.name}</h3>
                        <span className="text-xs text-gray-400">{acc.broker} • {cur}</span>
                      </div>
                    </div>
                    <div className="flex items-center gap-2 shrink-0">
                      <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${acc.floatingPL >= 0 ? 'bg-green-100 text-green-600' : 'bg-red-100 text-red-500'}`}>
                        {acc.floatingPL >= 0 ? <TrendingUp size={10} className="inline mr-0.5" /> : <TrendingDown size={10} className="inline mr-0.5" />}
                        {fmtMoney(acc.floatingPL, cur)}
                      </span>
                      {isOpen ? <ChevronUp size={16} className="text-gray-400" /> : <ChevronDown size={16} className="text-gray-400" />}
                    </div>
                  </div>

                  {/* Stats principales */}
                  <div className="grid grid-cols-2 gap-2 mb-2">
                    <div className="bg-blue-50 border border-blue-100 rounded-lg p-2">
                      <div className="text-[10px] text-blue-500 font-medium">Balance</div>
                      <div className="text-base font-bold text-blue-900">{mask(fmtMoney(acc.balance, cur))}</div>
                    </div>
                    <div className={`border rounded-lg p-2 ${acc.drawdown > 5 ? 'bg-red-50 border-red-200' : 'bg-blue-50 border-blue-100'}`}>
                      <div className="text-[10px] text-blue-500 font-medium">Drawdown</div>
                      <div className={`text-base font-bold ${acc.drawdown > 5 ? 'text-red-500' : 'text-blue-900'}`}>{mask(fmtPct(-acc.drawdown))}</div>
                      <div className="text-[10px] text-gray-400">{mask(fmtMoney(-ddEUR))}</div>
                    </div>
                  </div>

                  <div className="grid grid-cols-3 gap-2">
                    <div className={`border rounded-lg p-2 ${plBg(acc.dailyPL)}`}>
                      <div className="text-[10px] text-gray-500 font-medium">P&L Jour</div>
                      <div className={`text-sm font-bold ${plColor(acc.dailyPL)}`}>{mask(fmtMoney(acc.dailyPL, cur))}</div>
                    </div>
                    <div className={`border rounded-lg p-2 ${plBg(acc.monthlyPL)}`}>
                      <div className="text-[10px] text-gray-500 font-medium">P&L Mois</div>
                      <div className={`text-sm font-bold ${plColor(acc.monthlyPL)}`}>{mask(fmtMoney(acc.monthlyPL, cur))}</div>
                    </div>
                    <div className={`border rounded-lg p-2 ${plBg(acc.yearlyPL)}`}>
                      <div className="text-[10px] text-gray-500 font-medium">P&L Année</div>
                      <div className={`text-sm font-bold ${plColor(acc.yearlyPL)}`}>{mask(fmtMoney(acc.yearlyPL, cur))}</div>
                    </div>
                  </div>
                </button>

                {/* POSITIONS OUVERTES */}
                {isOpen && (
                  <div className="border-t border-gray-100 p-4">
                    <h4 className="text-gray-500 font-semibold text-xs mb-2 uppercase tracking-wider">
                      Positions ouvertes ({acc.positions.length})
                    </h4>
                    {acc.positions.length > 0 ? (
                      <div className="overflow-x-auto -mx-4 px-4">
                        <table className="w-full text-xs min-w-[480px]">
                          <thead>
                            <tr className="text-gray-400 text-[10px] uppercase border-b border-gray-100">
                              <th className="text-left py-1.5 pr-2">Symbole</th>
                              <th className="text-center py-1.5 px-1">Type</th>
                              <th className="text-right py-1.5 px-1">Lots</th>
                              <th className="text-right py-1.5 px-1">Open</th>
                              <th className="text-right py-1.5 px-1">Actuel</th>
                              <th className="text-right py-1.5 pl-1">Profit</th>
                            </tr>
                          </thead>
                          <tbody>
                            {acc.positions.map((p) => (
                              <tr key={p.ticket} className="border-b border-gray-50">
                                <td className="py-1.5 pr-2 text-blue-900 font-semibold">{p.symbol}</td>
                                <td className="py-1.5 px-1 text-center">
                                  <span className={`px-1.5 py-0.5 rounded text-[10px] font-bold ${p.type === 'BUY' ? 'bg-green-100 text-green-600' : 'bg-red-100 text-red-500'}`}>{p.type}</span>
                                </td>
                                <td className="py-1.5 px-1 text-right text-gray-600">{p.lots}</td>
                                <td className="py-1.5 px-1 text-right text-gray-400 font-mono text-[10px]">{p.openPrice}</td>
                                <td className="py-1.5 px-1 text-right text-gray-600 font-mono text-[10px]">{p.currentPrice}</td>
                                <td className={`py-1.5 pl-1 text-right font-bold ${(p.profit || p.netProfit || 0) >= 0 ? 'text-green-600' : 'text-red-500'}`}>
                                  {fmtMoney(p.netProfit || p.profit || 0, cur)}
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    ) : (
                      <p className="text-gray-400 text-xs">Aucune position ouverte</p>
                    )}

                    {/* Stats margin */}
                    <div className="grid grid-cols-3 gap-2 mt-3">
                      <div className="bg-gray-50 rounded-lg p-2 text-center">
                        <div className="text-[10px] text-gray-400">Marge</div>
                        <div className="text-xs font-semibold text-gray-700">{fmtMoney(acc.margin, cur)}</div>
                      </div>
                      <div className="bg-gray-50 rounded-lg p-2 text-center">
                        <div className="text-[10px] text-gray-400">Libre</div>
                        <div className="text-xs font-semibold text-gray-700">{fmtMoney(acc.freeMargin, cur)}</div>
                      </div>
                      <div className="bg-gray-50 rounded-lg p-2 text-center">
                        <div className="text-[10px] text-gray-400">Niv. marge</div>
                        <div className={`text-xs font-semibold ${acc.marginLevel > 500 ? 'text-green-600' : acc.marginLevel > 200 ? 'text-yellow-600' : 'text-red-500'}`}>
                          {(acc.marginLevel || 0).toFixed(0)}%
                        </div>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </section>

        {/* FOOTER */}
        <footer className="text-center text-xs text-gray-400 py-3 border-t border-gray-100">
          {lastRefresh && (
            <span className="flex items-center justify-center gap-1">
              <Clock size={10} /> {lastRefresh.toLocaleTimeString('fr-FR')} — Refresh: {REFRESH_INTERVAL / 1000}s
            </span>
          )}
        </footer>
      </main>
    </div>
  );
}
