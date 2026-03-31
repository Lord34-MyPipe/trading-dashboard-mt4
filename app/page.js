'use client';

import { useState, useEffect, useCallback, useMemo } from 'react';
import {
  AreaChart, Area, BarChart, Bar, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, Cell,
} from 'recharts';
import {
  RefreshCw, TrendingUp, TrendingDown, DollarSign, Activity,
  AlertTriangle, BarChart3, Eye, EyeOff, ChevronDown, ChevronUp,
  Clock, Wallet, Target, Percent, Zap, Shield,
} from 'lucide-react';

// ============================================================
// CONFIG — Remplace par tes vrais comptes
// ============================================================
const ACCOUNTS_CONFIG = [
  { id: 'RF-001', name: 'RoboForex #1', broker: 'RoboForex', server: 'RoboForex-ECN', login: '600XXXX1' },
  { id: 'RF-002', name: 'RoboForex #2', broker: 'RoboForex', server: 'RoboForex-ECN', login: '600XXXX2' },
  { id: 'RF-003', name: 'RoboForex #3', broker: 'RoboForex', server: 'RoboForex-Prime', login: '600XXXX3' },
  { id: 'RF-004', name: 'RoboForex #4', broker: 'RoboForex', server: 'RoboForex-Prime', login: '600XXXX4' },
  { id: 'FM-001', name: 'FusionMarkets', broker: 'FusionMarkets', server: 'FusionMarkets-Live', login: '700XXXX1' },
];

const REFRESH_INTERVAL = 10000;

// ============================================================
// MOCK DATA (actif tant que l'API n'est pas connectée)
// ============================================================
const generateMockData = (accounts) => {
  const symbols = ['EURUSD', 'GBPUSD', 'USDJPY', 'XAUUSD', 'GBPJPY', 'AUDUSD', 'NZDUSD'];
  const types = ['BUY', 'SELL'];

  return accounts.map((acc) => {
    const balance = 5000 + Math.random() * 45000;
    const floatingPL = (Math.random() - 0.45) * balance * 0.08;
    const equity = balance + floatingPL;
    const margin = balance * (0.05 + Math.random() * 0.15);
    const freeMargin = equity - margin;
    const marginLevel = margin > 0 ? (equity / margin) * 100 : 0;
    const dailyPL = (Math.random() - 0.4) * balance * 0.03;
    const monthlyPL = (Math.random() - 0.3) * balance * 0.12;
    const initialDeposit = balance * (0.7 + Math.random() * 0.2);
    const totalProfit = balance - initialDeposit + floatingPL;
    const maxEquity = equity * (1 + Math.random() * 0.05);
    const drawdown = ((maxEquity - equity) / maxEquity) * 100;

    const numPos = Math.floor(Math.random() * 5) + 1;
    const positions = Array.from({ length: numPos }, () => {
      const symbol = symbols[Math.floor(Math.random() * symbols.length)];
      const type = types[Math.floor(Math.random() * 2)];
      const lots = +(0.01 + Math.random() * 2).toFixed(2);
      const isJPY = symbol.includes('JPY');
      const isGold = symbol === 'XAUUSD';
      const openPrice = isJPY ? 140 + Math.random() * 20 : isGold ? 2200 + Math.random() * 200 : 0.8 + Math.random() * 0.8;
      const digits = isJPY ? 3 : isGold ? 2 : 5;
      const pips = (Math.random() - 0.45) * 80;
      const profit = pips * lots * (isJPY ? 0.7 : isGold ? 10 : 10);
      return {
        ticket: 10000000 + Math.floor(Math.random() * 9000000),
        symbol, type, lots,
        openPrice: +openPrice.toFixed(digits),
        currentPrice: +(openPrice + (type === 'BUY' ? 1 : -1) * pips * (isJPY ? 0.01 : isGold ? 1 : 0.0001)).toFixed(digits),
        pips: +pips.toFixed(1),
        profit: +profit.toFixed(2),
        swap: +((Math.random() - 0.5) * 5).toFixed(2),
        openTime: new Date(Date.now() - Math.random() * 7 * 86400000).toISOString(),
      };
    });

    const equityCurve = Array.from({ length: 30 }, (_, i) => {
      const d = new Date(); d.setDate(d.getDate() - (29 - i));
      return {
        date: d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' }),
        equity: +(initialDeposit + (totalProfit / 30) * (i + 1) + (Math.random() - 0.5) * balance * 0.02).toFixed(2),
      };
    });

    return {
      ...acc, balance: +balance.toFixed(2), equity: +equity.toFixed(2),
      floatingPL: +floatingPL.toFixed(2), margin: +margin.toFixed(2),
      freeMargin: +freeMargin.toFixed(2), marginLevel: +marginLevel.toFixed(1),
      dailyPL: +dailyPL.toFixed(2), monthlyPL: +monthlyPL.toFixed(2),
      drawdown: +drawdown.toFixed(2), profitability: +((totalProfit / initialDeposit) * 100).toFixed(2),
      totalProfit: +totalProfit.toFixed(2), initialDeposit: +initialDeposit.toFixed(2),
      positions, equityCurve, lastUpdate: new Date().toISOString(),
    };
  });
};

// ============================================================
// HELPERS
// ============================================================
const fmt = (v) => v == null ? '$0' : new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'USD', minimumFractionDigits: 0, maximumFractionDigits: 0 }).format(v);
const fmt2 = (v) => v == null ? '$0.00' : new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'USD', minimumFractionDigits: 2 }).format(v);
const fmtPct = (v) => `${v >= 0 ? '+' : ''}${v?.toFixed(2) ?? '0.00'}%`;

// ============================================================
// UI COMPONENTS
// ============================================================
const PLBadge = ({ value, size = 'sm' }) => {
  const pos = value >= 0;
  const cls = size === 'lg' ? 'text-base sm:text-lg font-bold px-3 py-1.5' : 'text-xs sm:text-sm font-semibold px-2 py-0.5';
  return (
    <span className={`inline-flex items-center gap-1 rounded-full ${cls} ${pos ? 'bg-emerald-500/20 text-emerald-400' : 'bg-red-500/20 text-red-400'}`}>
      {pos ? <TrendingUp size={size === 'lg' ? 14 : 10} /> : <TrendingDown size={size === 'lg' ? 14 : 10} />}
      {fmt2(value)}
    </span>
  );
};

const MiniStat = ({ icon: Icon, label, value, color = 'gray', sub }) => {
  const colors = { blue: 'text-blue-400', green: 'text-emerald-400', red: 'text-red-400', amber: 'text-amber-400', purple: 'text-purple-400', cyan: 'text-cyan-400', gray: 'text-gray-400' };
  const bgs = { blue: 'bg-blue-500/10 border-blue-500/20', green: 'bg-emerald-500/10 border-emerald-500/20', red: 'bg-red-500/10 border-red-500/20', amber: 'bg-amber-500/10 border-amber-500/20', purple: 'bg-purple-500/10 border-purple-500/20', cyan: 'bg-cyan-500/10 border-cyan-500/20', gray: 'bg-gray-500/10 border-gray-500/20' };
  return (
    <div className={`${bgs[color]} border rounded-xl p-3 min-w-0`}>
      <div className="flex items-center gap-1.5 mb-1">
        <Icon size={13} className={colors[color]} />
        <span className="text-[10px] sm:text-xs text-gray-500 uppercase tracking-wider truncate">{label}</span>
      </div>
      <div className="text-sm sm:text-base font-bold text-white truncate">{value}</div>
      {sub && <div className="text-[10px] text-gray-500 mt-0.5 truncate">{sub}</div>}
    </div>
  );
};

// ============================================================
// ACCOUNT CARD
// ============================================================
const AccountCard = ({ account, isExpanded, onToggle, showBal }) => {
  const mask = (v) => showBal ? v : '•••••';
  const ddColor = account.drawdown > 10 ? 'red' : account.drawdown > 5 ? 'amber' : 'green';

  return (
    <div className="bg-gray-900/70 border border-gray-800 rounded-2xl overflow-hidden">
      <button className="w-full p-4 text-left active:bg-gray-800/50 transition-colors" onClick={onToggle}>
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2.5 min-w-0">
            <div className={`w-2.5 h-2.5 rounded-full shrink-0 ${account.broker === 'RoboForex' ? 'bg-blue-500' : 'bg-orange-500'}`} />
            <div className="min-w-0">
              <h3 className="text-white font-bold text-sm sm:text-base truncate">{account.name}</h3>
              <span className="text-[10px] text-gray-600">{account.login}</span>
            </div>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            <PLBadge value={account.floatingPL} />
            {isExpanded ? <ChevronUp size={16} className="text-gray-500" /> : <ChevronDown size={16} className="text-gray-500" />}
          </div>
        </div>
        <div className="grid grid-cols-3 sm:grid-cols-6 gap-2">
          <MiniStat icon={Wallet} label="Balance" value={mask(fmt(account.balance))} color="blue" />
          <MiniStat icon={DollarSign} label="Equity" value={mask(fmt(account.equity))} color="cyan" />
          <MiniStat icon={TrendingUp} label="P&L Jour" value={mask(fmt2(account.dailyPL))} color={account.dailyPL >= 0 ? 'green' : 'red'} />
          <MiniStat icon={BarChart3} label="P&L Mois" value={mask(fmt2(account.monthlyPL))} color={account.monthlyPL >= 0 ? 'green' : 'red'} />
          <MiniStat icon={AlertTriangle} label="DD" value={fmtPct(-account.drawdown)} color={ddColor} />
          <MiniStat icon={Percent} label="Rentab." value={fmtPct(account.profitability)} color={account.profitability >= 0 ? 'green' : 'red'} />
        </div>
      </button>

      {isExpanded && (
        <div className="border-t border-gray-800 p-4 space-y-4">
          {/* Positions */}
          <div>
            <h4 className="text-gray-400 font-semibold text-sm mb-2 flex items-center gap-1.5">
              <Target size={14} className="text-blue-400" />
              Positions ({account.positions.length})
            </h4>
            <div className="overflow-x-auto -mx-4 px-4">
              <table className="w-full text-xs sm:text-sm min-w-[500px]">
                <thead>
                  <tr className="text-gray-600 text-[10px] uppercase border-b border-gray-800">
                    <th className="text-left py-1.5 pr-2">Symbole</th>
                    <th className="text-center py-1.5 px-1">Type</th>
                    <th className="text-right py-1.5 px-1">Lots</th>
                    <th className="text-right py-1.5 px-1">Open</th>
                    <th className="text-right py-1.5 px-1">Now</th>
                    <th className="text-right py-1.5 px-1">Pips</th>
                    <th className="text-right py-1.5 pl-1">Profit</th>
                  </tr>
                </thead>
                <tbody>
                  {account.positions.map((p) => (
                    <tr key={p.ticket} className="border-b border-gray-800/50">
                      <td className="py-1.5 pr-2 text-white font-semibold">{p.symbol}</td>
                      <td className="py-1.5 px-1 text-center">
                        <span className={`px-1.5 py-0.5 rounded text-[10px] font-bold ${p.type === 'BUY' ? 'bg-emerald-500/20 text-emerald-400' : 'bg-red-500/20 text-red-400'}`}>{p.type}</span>
                      </td>
                      <td className="py-1.5 px-1 text-right text-gray-300">{p.lots}</td>
                      <td className="py-1.5 px-1 text-right text-gray-500 font-mono text-[10px]">{p.openPrice}</td>
                      <td className="py-1.5 px-1 text-right text-gray-300 font-mono text-[10px]">{p.currentPrice}</td>
                      <td className={`py-1.5 px-1 text-right font-semibold ${p.pips >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>{p.pips > 0 ? '+' : ''}{p.pips}</td>
                      <td className={`py-1.5 pl-1 text-right font-bold ${p.profit >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>{fmt2(p.profit)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          {/* Equity Curve */}
          {account.equityCurve && account.equityCurve.length > 0 && (
          <div>
            <h4 className="text-gray-400 font-semibold text-sm mb-2 flex items-center gap-1.5">
              <TrendingUp size={14} className="text-emerald-400" /> Equity 30j
            </h4>
            <ResponsiveContainer width="100%" height={160}>
              <AreaChart data={account.equityCurve}>
                <defs>
                  <linearGradient id={`g-${account.id}`} x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor={account.profitability >= 0 ? '#10b981' : '#ef4444'} stopOpacity={0.3} />
                    <stop offset="95%" stopColor={account.profitability >= 0 ? '#10b981' : '#ef4444'} stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="#1f2937" />
                <XAxis dataKey="date" tick={{ fill: '#4b5563', fontSize: 9 }} interval="preserveStartEnd" />
                <YAxis tick={{ fill: '#4b5563', fontSize: 9 }} domain={['auto', 'auto']} width={50} />
                <Tooltip contentStyle={{ backgroundColor: '#111827', border: '1px solid #374151', borderRadius: 8, color: '#fff', fontSize: 12 }} formatter={(v) => [fmt2(v), 'Equity']} />
                <Area type="monotone" dataKey="equity" stroke={account.profitability >= 0 ? '#10b981' : '#ef4444'} fill={`url(#g-${account.id})`} strokeWidth={2} />
              </AreaChart>
            </ResponsiveContainer>
          </div>
          )}

          {/* Margin stats */}
          <div className="grid grid-cols-3 gap-2">
            <div className="bg-gray-800/50 rounded-lg p-2 text-center">
              <div className="text-[10px] text-gray-500">Marge</div>
              <div className="text-xs font-semibold text-white">{fmt(account.margin)}</div>
            </div>
            <div className="bg-gray-800/50 rounded-lg p-2 text-center">
              <div className="text-[10px] text-gray-500">Libre</div>
              <div className="text-xs font-semibold text-white">{fmt(account.freeMargin)}</div>
            </div>
            <div className="bg-gray-800/50 rounded-lg p-2 text-center">
              <div className="text-[10px] text-gray-500">Niv. marge</div>
              <div className={`text-xs font-semibold ${account.marginLevel > 500 ? 'text-emerald-400' : account.marginLevel > 200 ? 'text-amber-400' : 'text-red-400'}`}>{(account.marginLevel || 0).toFixed(0)}%</div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

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
          // Normalise les champs VPS → format attendu par le frontend
          const normalized = json.accounts.map((a) => ({
            ...a,
            id: a.id || a.accountId || String(a.accountId),
            name: a.name || a.alias || `Account ${a.accountId}`,
            login: a.login || String(a.accountId),
            positions: a.positions || [],
            equityCurve: a.equityCurve || [],
            drawdown: a.drawdown || 0,
            dailyPL: a.dailyPL || 0,
            monthlyPL: a.monthlyPL || 0,
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
    setAccounts(generateMockData(ACCOUNTS_CONFIG));
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

  const global = useMemo(() => {
    if (!accounts.length) return null;
    const sum = (fn) => accounts.reduce((s, a) => s + (fn(a) || 0), 0);
    const totalBalance = sum(a => a.balance);
    const totalEquity = sum(a => a.equity);
    const totalFloating = sum(a => a.floatingPL);
    const totalDailyPL = sum(a => a.dailyPL);
    const totalMonthlyPL = sum(a => a.monthlyPL);
    const totalPositions = sum(a => a.positions?.length);
    const totalDeposit = sum(a => a.initialDeposit);
    const totalProfit = sum(a => a.totalProfit);
    const maxDD = Math.max(...accounts.map(a => a.drawdown || 0));
    const avgDD = sum(a => a.drawdown) / accounts.length;
    const profitability = totalDeposit > 0 ? (totalProfit / totalDeposit) * 100 : 0;
    const dailyBreakdown = accounts.map(a => ({
      name: a.name.replace('RoboForex ', 'RF').replace('FusionMarkets', 'FM'),
      value: a.dailyPL,
      color: a.dailyPL >= 0 ? '#10b981' : '#ef4444',
    }));
    return { totalBalance, totalEquity, totalFloating, totalDailyPL, totalMonthlyPL, totalPositions, maxDD, avgDD, profitability, dailyBreakdown };
  }, [accounts]);

  const mask = (v) => showBal ? v : '•••••';

  return (
    <div className="min-h-screen bg-[#0a0e1a]">
      {/* HEADER */}
      <header className="bg-gray-900/90 border-b border-gray-800 sticky top-0 z-50 backdrop-blur-md">
        <div className="max-w-5xl mx-auto px-3 sm:px-4 py-2.5 flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 bg-gradient-to-br from-blue-500 to-purple-600 rounded-xl flex items-center justify-center font-bold text-sm shadow-lg shadow-blue-500/20">JB</div>
            <div>
              <h1 className="text-sm sm:text-base font-bold text-white">Trading Dashboard</h1>
              <div className="flex items-center gap-1.5">
                <span className="text-[10px] text-gray-500">{accounts.length} comptes</span>
                {apiConnected
                  ? <span className="text-[10px] text-emerald-500 flex items-center gap-0.5"><Zap size={8} /> Live</span>
                  : <span className="text-[10px] text-amber-500 flex items-center gap-0.5"><Shield size={8} /> Démo</span>
                }
              </div>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <button onClick={() => setShowBal(!showBal)} className="p-2 rounded-lg bg-gray-800 active:bg-gray-700 text-gray-400">
              {showBal ? <Eye size={16} /> : <EyeOff size={16} />}
            </button>
            <button onClick={() => setAutoRefresh(!autoRefresh)}
              className={`flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-[10px] sm:text-xs font-medium border ${autoRefresh ? 'bg-emerald-500/15 text-emerald-400 border-emerald-500/30' : 'bg-gray-800 text-gray-500 border-gray-700'}`}>
              <div className={`w-1.5 h-1.5 rounded-full ${autoRefresh ? 'bg-emerald-400 pulse-dot' : 'bg-gray-600'}`} />
              {autoRefresh ? 'Live' : 'Pause'}
            </button>
            <button onClick={fetchData} disabled={loading} className="p-2 rounded-lg bg-blue-600 active:bg-blue-500 text-white">
              <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
            </button>
          </div>
        </div>
      </header>

      <main className="max-w-5xl mx-auto px-3 sm:px-4 py-4 space-y-4">
        {/* VUE GLOBALE */}
        {global && (
          <section className="bg-gradient-to-br from-blue-950/50 via-gray-900/50 to-purple-950/50 border border-blue-500/15 rounded-2xl p-4">
            <h2 className="text-base sm:text-lg font-bold text-white mb-3 flex items-center gap-2">
              <BarChart3 size={18} className="text-blue-400" /> Vue Globale
            </h2>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 mb-4">
              <div className="bg-blue-500/10 border border-blue-500/20 rounded-xl p-3">
                <div className="text-[10px] text-blue-400 uppercase mb-0.5">Balance</div>
                <div className="text-lg sm:text-xl font-bold text-white">{mask(fmt(global.totalBalance))}</div>
              </div>
              <div className="bg-cyan-500/10 border border-cyan-500/20 rounded-xl p-3">
                <div className="text-[10px] text-cyan-400 uppercase mb-0.5">Equity</div>
                <div className="text-lg sm:text-xl font-bold text-white">{mask(fmt(global.totalEquity))}</div>
              </div>
              <div className={`${global.totalDailyPL >= 0 ? 'bg-emerald-500/10 border-emerald-500/20' : 'bg-red-500/10 border-red-500/20'} border rounded-xl p-3`}>
                <div className={`text-[10px] uppercase mb-0.5 ${global.totalDailyPL >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>P&L Jour</div>
                <div className={`text-lg sm:text-xl font-bold ${global.totalDailyPL >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>{mask(fmt2(global.totalDailyPL))}</div>
              </div>
              <div className={`${global.totalMonthlyPL >= 0 ? 'bg-emerald-500/10 border-emerald-500/20' : 'bg-red-500/10 border-red-500/20'} border rounded-xl p-3`}>
                <div className={`text-[10px] uppercase mb-0.5 ${global.totalMonthlyPL >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>P&L Mois</div>
                <div className={`text-lg sm:text-xl font-bold ${global.totalMonthlyPL >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>{mask(fmt2(global.totalMonthlyPL))}</div>
              </div>
            </div>
            <div className="grid grid-cols-3 gap-2 mb-4">
              <MiniStat icon={Activity} label="Floating" value={mask(fmt2(global.totalFloating))} color={global.totalFloating >= 0 ? 'green' : 'red'} />
              <MiniStat icon={AlertTriangle} label="Max DD" value={fmtPct(-global.maxDD)} sub={`Moy: ${fmtPct(-global.avgDD)}`} color={global.maxDD > 10 ? 'red' : 'amber'} />
              <MiniStat icon={Percent} label="Rentab." value={fmtPct(global.profitability)} sub={`${global.totalPositions} pos.`} color={global.profitability >= 0 ? 'green' : 'red'} />
            </div>
            <div className="bg-gray-900/60 rounded-xl p-3">
              <h4 className="text-xs text-gray-500 mb-2 font-semibold">P&L jour / compte</h4>
              <ResponsiveContainer width="100%" height={110}>
                <BarChart data={global.dailyBreakdown} layout="vertical">
                  <CartesianGrid strokeDasharray="3 3" stroke="#1f2937" horizontal={false} />
                  <XAxis type="number" tick={{ fill: '#6b7280', fontSize: 10 }} tickFormatter={(v) => `$${v.toFixed(0)}`} />
                  <YAxis type="category" dataKey="name" tick={{ fill: '#9ca3af', fontSize: 10 }} width={40} />
                  <Tooltip contentStyle={{ backgroundColor: '#111827', border: '1px solid #374151', borderRadius: 8, color: '#fff', fontSize: 11 }} formatter={(v) => [fmt2(v), 'P&L']} />
                  <Bar dataKey="value" radius={[0, 4, 4, 0]} barSize={14}>
                    {global.dailyBreakdown.map((e, i) => <Cell key={i} fill={e.color} />)}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>
          </section>
        )}

        {/* COMPTES */}
        <section className="space-y-3">
          <h2 className="text-sm sm:text-base font-bold text-gray-400 flex items-center gap-1.5">
            <Target size={15} className="text-purple-400" /> Détail par compte
          </h2>
          {accounts.map((acc) => (
            <AccountCard key={acc.id} account={acc} isExpanded={expanded[acc.id]} onToggle={() => toggle(acc.id)} showBal={showBal} />
          ))}
        </section>

        <footer className="text-center text-[10px] text-gray-700 py-3 border-t border-gray-900">
          {lastRefresh && (
            <span className="flex items-center justify-center gap-1">
              <Clock size={10} /> Dernière maj: {lastRefresh.toLocaleTimeString('fr-FR')} — Refresh: {REFRESH_INTERVAL / 1000}s
            </span>
          )}
        </footer>
      </main>
    </div>
  );
}
