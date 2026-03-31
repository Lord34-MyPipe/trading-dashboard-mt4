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
            drawdownAmount: a.drawdownAmount || 0,
            // Profits encaissés (trades fermés uniquement)
            dailyProfit: a.dailyProfit || 0,
            monthlyProfit: a.monthlyProfit || 0,
            yearlyProfit: a.yearlyProfit || 0,
            // Rendements en %
            dailyReturnPct: a.dailyReturnPct || 0,
            monthlyReturnPct: a.monthlyReturnPct || 0,
            yearlyReturnPct: a.yearlyReturnPct || 0,
            // Anciens champs (fallback)
            dailyPL: a.dailyPL || 0,
            monthlyPL: a.monthlyPL || 0,
            marginLevel: a.marginLevel || 0,
            initialDeposit: a.initialDeposit || a.balance || 0,
          }));
          normalized.sort((a, b) => b.balance - a.balance);
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

  // Helper: récupère le profit encaissé (nouveaux champs, avec fallback sur les anciens)
  const getDaily = (a) => a.dailyProfit || 0;
  const getMonthly = (a) => a.monthlyProfit || 0;
  const getYearly = (a) => a.yearlyProfit || 0;

  // ============================================================
  // GLOBAL — tout converti en EUR
  // ============================================================
  const global = useMemo(() => {
    if (!accounts.length) return null;
    const totalBalance = accounts.reduce((s, a) => s + toEUR(a.balance, a.currency), 0);
    const totalEquity = accounts.reduce((s, a) => s + toEUR(a.equity, a.currency), 0);

    // Profits encaissés convertis en EUR
    const totalDailyProfit = accounts.reduce((s, a) => s + toEUR(getDaily(a), a.currency), 0);
    const totalMonthlyProfit = accounts.reduce((s, a) => s + toEUR(getMonthly(a), a.currency), 0);
    const totalYearlyProfit = accounts.reduce((s, a) => s + toEUR(getYearly(a), a.currency), 0);

    // Floating global (encours positions ouvertes)
    const totalFloating = accounts.reduce((s, a) => s + toEUR(a.floatingPL || 0, a.currency), 0);
    const globalFloatingPct = totalBalance > 0 ? (totalFloating / totalBalance) * 100 : 0;

    // Rendements globaux en %
    const startDay = totalBalance - totalDailyProfit;
    const startMonth = totalBalance - totalMonthlyProfit;
    const startYear = totalBalance - totalYearlyProfit;
    const dailyReturnPct = startDay > 0 ? (totalDailyProfit / startDay) * 100 : 0;
    const monthlyReturnPct = startMonth > 0 ? (totalMonthlyProfit / startMonth) * 100 : 0;
    const yearlyReturnPct = startYear > 0 ? (totalYearlyProfit / startYear) * 100 : 0;

    return { totalBalance, totalEquity, totalFloating, globalFloatingPct, totalDailyProfit, totalMonthlyProfit, totalYearlyProfit, dailyReturnPct, monthlyReturnPct, yearlyReturnPct };
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
              <div className={`bg-white border rounded-xl p-3 ${global.totalFloating >= 0 ? 'border-green-200' : 'border-red-300'}`}>
                <div className="text-xs text-blue-500 font-medium mb-1">Floating</div>
                <div className={`text-xl font-bold ${plColor(global.totalFloating)}`}>{mask(fmtMoney(global.totalFloating))}</div>
                <div className={`text-xs mt-0.5 ${plColor(global.globalFloatingPct)}`}>{mask(fmtPct(global.globalFloatingPct))}</div>
              </div>
            </div>

            {/* Profits encaissés Jour / Mois / Année */}
            <div className="grid grid-cols-3 gap-3">
              <div className={`border rounded-xl p-3 ${plBg(global.totalDailyProfit)}`}>
                <div className="text-xs text-gray-500 font-medium mb-1">Profit Jour</div>
                <div className={`text-lg font-bold ${plColor(global.totalDailyProfit)}`}>{mask(fmtMoney(global.totalDailyProfit))}</div>
                <div className={`text-xs mt-0.5 ${plColor(global.dailyReturnPct)}`}>{mask(fmtPct(global.dailyReturnPct))}</div>
              </div>
              <div className={`border rounded-xl p-3 ${plBg(global.totalMonthlyProfit)}`}>
                <div className="text-xs text-gray-500 font-medium mb-1">Profit Mois</div>
                <div className={`text-lg font-bold ${plColor(global.totalMonthlyProfit)}`}>{mask(fmtMoney(global.totalMonthlyProfit))}</div>
                <div className={`text-xs mt-0.5 ${plColor(global.monthlyReturnPct)}`}>{mask(fmtPct(global.monthlyReturnPct))}</div>
              </div>
              <div className={`border rounded-xl p-3 ${plBg(global.totalYearlyProfit)}`}>
                <div className="text-xs text-gray-500 font-medium mb-1">Profit Année</div>
                <div className={`text-lg font-bold ${plColor(global.totalYearlyProfit)}`}>{mask(fmtMoney(global.totalYearlyProfit))}</div>
                <div className={`text-xs mt-0.5 ${plColor(global.yearlyReturnPct)}`}>{mask(fmtPct(global.yearlyReturnPct))}</div>
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
            const daily = getDaily(acc);
            const monthly = getMonthly(acc);
            const yearly = getYearly(acc);
            const floating = acc.floatingPL || 0;
            const floatingPct = acc.floatingPct || (acc.balance > 0 ? (floating / acc.balance) * 100 : 0);
            const isOpen = expanded[acc.id];

            return (
              <div key={acc.id} className="bg-white border border-gray-200 rounded-2xl overflow-hidden shadow-sm">
                <button className="w-full p-4 text-left active:bg-gray-50 transition-colors" onClick={() => toggle(acc.id)}>
                  {/* Header */}
                  <div className="flex items-center justify-between mb-3">
                    <div className="flex items-center gap-2.5 min-w-0">
                      <div className={`w-2.5 h-2.5 rounded-full shrink-0 ${cur === 'USD' ? 'bg-orange-500' : 'bg-blue-500'}`} />
                      <div className="min-w-0">
                        <h3 className="text-blue-900 font-bold text-sm truncate">{acc.name}</h3>
                        <span className="text-xs text-gray-400">{acc.broker} • {cur}</span>
                      </div>
                    </div>
                    <div className="flex items-center gap-2 shrink-0">
                      {isOpen ? <ChevronUp size={16} className="text-gray-400" /> : <ChevronDown size={16} className="text-gray-400" />}
                    </div>
                  </div>

                  {/* Balance + DD */}
                  <div className="grid grid-cols-2 gap-2 mb-2">
                    <div className="bg-blue-50 border border-blue-100 rounded-lg p-2">
                      <div className="text-[10px] text-blue-500 font-medium">Balance</div>
                      <div className="text-base font-bold text-blue-900">{mask(fmtMoney(acc.balance, cur))}</div>
                    </div>
                    <div className={`border rounded-lg p-2 ${floating >= 0 ? 'bg-green-50 border-green-200' : 'bg-red-50 border-red-200'}`}>
                      <div className="text-[10px] text-blue-500 font-medium">Floating</div>
                      <div className={`text-base font-bold ${plColor(floating)}`}>{mask(fmtMoney(floating, cur))}</div>
                      <div className={`text-[10px] ${plColor(floatingPct)}`}>{mask(fmtPct(floatingPct))}</div>
                    </div>
                  </div>

                  {/* Profits encaissés */}
                  <div className="grid grid-cols-3 gap-2">
                    <div className={`border rounded-lg p-2 ${plBg(daily)}`}>
                      <div className="text-[10px] text-gray-500 font-medium">Profit Jour</div>
                      <div className={`text-sm font-bold ${plColor(daily)}`}>{mask(fmtMoney(daily, cur))}</div>
                      <div className={`text-[10px] ${plColor(acc.dailyReturnPct)}`}>{mask(fmtPct(acc.dailyReturnPct))}</div>
                    </div>
                    <div className={`border rounded-lg p-2 ${plBg(monthly)}`}>
                      <div className="text-[10px] text-gray-500 font-medium">Profit Mois</div>
                      <div className={`text-sm font-bold ${plColor(monthly)}`}>{mask(fmtMoney(monthly, cur))}</div>
                      <div className={`text-[10px] ${plColor(acc.monthlyReturnPct)}`}>{mask(fmtPct(acc.monthlyReturnPct))}</div>
                    </div>
                    <div className={`border rounded-lg p-2 ${plBg(yearly)}`}>
                      <div className="text-[10px] text-gray-500 font-medium">Profit Année</div>
                      <div className={`text-sm font-bold ${plColor(yearly)}`}>{mask(fmtMoney(yearly, cur))}</div>
                      <div className={`text-[10px] ${plColor(acc.yearlyReturnPct)}`}>{mask(fmtPct(acc.yearlyReturnPct))}</div>
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
                                <td className={`py-1.5 pl-1 text-right font-bold ${(p.netProfit || p.profit || 0) >= 0 ? 'text-green-600' : 'text-red-500'}`}>
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
