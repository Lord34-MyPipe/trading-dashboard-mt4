export const dynamic = 'force-dynamic';
export const revalidate = 0;

export async function GET(request) {
  const { searchParams } = new URL(request.url);
  const password = searchParams.get('key') || request.headers.get('x-dashboard-key');

  if (process.env.DASHBOARD_PASSWORD && password !== process.env.DASHBOARD_PASSWORD) {
    return Response.json({ error: 'Non autorisé' }, { status: 401 });
  }

  const VPS_URL = process.env.VPS_API_URL;

  // OPTION A : Fetch depuis le serveur Node.js sur le VPS
  if (VPS_URL) {
    try {
      const response = await fetch(`${VPS_URL}/api/accounts`, {
        cache: 'no-store',
        signal: AbortSignal.timeout(8000),
      });
      if (!response.ok) throw new Error(`VPS responded ${response.status}`);
      const data = await response.json();
      return Response.json(data, {
        headers: { 'Cache-Control': 'no-cache, no-store, must-revalidate' },
      });
    } catch (err) {
      console.error('Erreur connexion VPS:', err.message);
      return Response.json({ error: 'VPS non joignable', details: err.message, fallback: true }, { status: 503 });
    }
  }

  // OPTION B : MetaApi.cloud direct
  const METAAPI_TOKEN = process.env.METAAPI_TOKEN;
  const ACCOUNT_IDS = (process.env.METAAPI_ACCOUNT_IDS || '').split(',').filter(Boolean);

  if (METAAPI_TOKEN && ACCOUNT_IDS.length > 0) {
    try {
      const BASE = 'https://mt-client-api-v1.agiliumtrade.agiliumtrade.ai';
      const headers = { 'auth-token': METAAPI_TOKEN };

      const accounts = await Promise.all(
        ACCOUNT_IDS.map(async (id) => {
          const [infoRes, posRes] = await Promise.all([
            fetch(`${BASE}/users/current/accounts/${id.trim()}/account-information`, { headers, cache: 'no-store' }),
            fetch(`${BASE}/users/current/accounts/${id.trim()}/positions`, { headers, cache: 'no-store' }),
          ]);
          const info = await infoRes.json();
          const positions = await posRes.json();
          return {
            accountId: info.login,
            alias: info.name || `Account ${info.login}`,
            broker: info.broker, server: info.server,
            currency: info.currency, leverage: info.leverage,
            balance: info.balance, equity: info.equity,
            margin: info.margin, freeMargin: info.freeMargin,
            marginLevel: info.marginLevel || (info.margin > 0 ? (info.equity / info.margin) * 100 : 0),
            floatingPL: info.equity - info.balance,
            positions: (Array.isArray(positions) ? positions : []).map((p) => ({
              ticket: p.id, symbol: p.symbol,
              type: p.type === 'POSITION_TYPE_BUY' ? 'BUY' : 'SELL',
              lots: p.volume, openPrice: p.openPrice, currentPrice: p.currentPrice,
              pips: 0, profit: p.profit, swap: p.swap || 0,
              commission: p.commission || 0, sl: p.stopLoss || 0, tp: p.takeProfit || 0,
              openTime: p.time,
            })),
            lastUpdate: new Date().toISOString(),
          };
        })
      );
      return Response.json({ accounts, lastUpdate: new Date().toISOString(), count: accounts.length });
    } catch (err) {
      return Response.json({ error: 'MetaApi error', details: err.message }, { status: 503 });
    }
  }

  return Response.json({
    error: 'Aucune source configurée',
    help: 'Configure VPS_API_URL ou METAAPI_TOKEN dans les variables Vercel',
  }, { status: 500 });
}
