// ============================================================
// SERVEUR NODE.JS — Trading Dashboard API
// Tourne sur le VPS, lit les JSON exportés par les EAs MT4
// ============================================================
// Installation: npm install express cors chokidar
// Lancement:    node server.js
// ============================================================

const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const chokidar = require('chokidar');

const app = express();
app.use(cors());
app.use(express.json());

// ============================================================
// CONFIGURATION
// ============================================================
const PORT = process.env.PORT || 3001;
const API_KEY = process.env.API_KEY || 'jb-trading-2026'; // Change ce mot de passe !

// Dossier où les EAs exportent les JSON
// Par défaut: C:\TradingDashboard\data\
// Les EAs écrivent aussi dans le dossier Common MT4:
// C:\Users\[User]\AppData\Roaming\MetaQuotes\Terminal\Common\Files\
const DATA_DIRS = [
  'C:\\TradingDashboard\\data',
  path.join(process.env.APPDATA || '', 'MetaQuotes', 'Terminal', 'Common', 'Files'),
];

// ============================================================
// STOCKAGE EN MÉMOIRE
// ============================================================
let accountsData = {};
let lastUpdateTime = null;
let serverStartTime = new Date();

// ============================================================
// LECTURE DES FICHIERS JSON
// ============================================================
function loadFile(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    const stat = fs.statSync(filePath);
    // Ignorer les fichiers de plus de 5 minutes (EA probablement arrêté)
    const ageMinutes = (Date.now() - stat.mtimeMs) / 60000;

    const raw = fs.readFileSync(filePath, 'utf8');
    const data = JSON.parse(raw);
    data._filePath = filePath;
    data._fileAge = Math.round(ageMinutes);
    data._isStale = ageMinutes > 5;
    return data;
  } catch (err) {
    console.error(`[ERROR] Lecture ${filePath}: ${err.message}`);
    return null;
  }
}

function scanAllAccounts() {
  const found = [];

  for (const dir of DATA_DIRS) {
    try {
      if (!fs.existsSync(dir)) {
        // Créer le dossier s'il n'existe pas
        fs.mkdirSync(dir, { recursive: true });
        console.log(`[INFO] Dossier créé: ${dir}`);
        continue;
      }

      const files = fs.readdirSync(dir)
        .filter(f => f.startsWith('dashboard_') && f.endsWith('.json'));

      for (const file of files) {
        const data = loadFile(path.join(dir, file));
        if (data && data.accountId) {
          accountsData[data.accountId] = data;
          found.push(data.alias || `#${data.accountId}`);
        }
      }
    } catch (err) {
      console.error(`[ERROR] Scan ${dir}: ${err.message}`);
    }
  }

  if (found.length > 0) {
    lastUpdateTime = new Date().toISOString();
  }
  return found;
}

// ============================================================
// FILE WATCHER
// ============================================================
function startWatcher() {
  const watchPatterns = DATA_DIRS
    .filter(d => fs.existsSync(d))
    .map(d => path.join(d, 'dashboard_*.json'));

  if (watchPatterns.length === 0) {
    console.log('[WARN] Aucun dossier de données trouvé. En attente...');
    return;
  }

  const watcher = chokidar.watch(watchPatterns, {
    persistent: true,
    ignoreInitial: true,
    awaitWriteFinish: { stabilityThreshold: 500, pollInterval: 100 },
  });

  watcher.on('change', (filePath) => {
    const data = loadFile(filePath);
    if (data && data.accountId) {
      accountsData[data.accountId] = data;
      lastUpdateTime = new Date().toISOString();
      console.log(`[UPDATE] ${data.alias || data.accountId} — Bal: $${data.balance} | Eq: $${data.equity}`);
    }
  });

  watcher.on('add', (filePath) => {
    console.log(`[NEW] Nouveau fichier détecté: ${path.basename(filePath)}`);
    const data = loadFile(filePath);
    if (data && data.accountId) {
      accountsData[data.accountId] = data;
      lastUpdateTime = new Date().toISOString();
    }
  });

  console.log(`[OK] Surveillance active sur ${watchPatterns.length} dossier(s)`);
}

// ============================================================
// MIDDLEWARE AUTH
// ============================================================
function auth(req, res, next) {
  const key = req.query.key || req.headers['x-api-key'] || req.headers['x-dashboard-key'];
  if (API_KEY && key !== API_KEY) {
    return res.status(401).json({ error: 'Non autorisé. Ajoute ?key=TON_MOT_DE_PASSE' });
  }
  next();
}

// ============================================================
// API ENDPOINTS
// ============================================================

// Health check (pas d'auth)
app.get('/api/health', (req, res) => {
  const accounts = Object.values(accountsData);
  res.json({
    status: 'ok',
    uptime: Math.round(process.uptime()),
    accounts: accounts.length,
    activeAccounts: accounts.filter(a => !a._isStale).length,
    lastUpdate: lastUpdateTime,
    serverStart: serverStartTime.toISOString(),
    dataDirs: DATA_DIRS.map(d => ({ path: d, exists: fs.existsSync(d) })),
  });
});

// Toutes les données des comptes
app.get('/api/accounts', auth, (req, res) => {
  let accounts = Object.values(accountsData);

  // Si aucune donnée, re-scanner
  if (accounts.length === 0) {
    scanAllAccounts();
    accounts = Object.values(accountsData);
  }

  // Nettoyer les champs internes
  const clean = accounts.map(a => {
    const { _filePath, _fileAge, _isStale, ...rest } = a;
    return { ...rest, isStale: _isStale, dataAge: _fileAge };
  });

  res.json({
    accounts: clean,
    lastUpdate: lastUpdateTime,
    count: clean.length,
    activeCount: clean.filter(a => !a.isStale).length,
  });
});

// Résumé global
app.get('/api/summary', auth, (req, res) => {
  const accounts = Object.values(accountsData);
  const active = accounts.filter(a => !a._isStale);

  res.json({
    totalBalance: active.reduce((s, a) => s + (a.balance || 0), 0),
    totalEquity: active.reduce((s, a) => s + (a.equity || 0), 0),
    totalFloatingPL: active.reduce((s, a) => s + (a.floatingPL || 0), 0),
    totalDailyPL: active.reduce((s, a) => s + (a.dailyPL || 0), 0),
    totalMonthlyPL: active.reduce((s, a) => s + (a.monthlyPL || 0), 0),
    totalPositions: active.reduce((s, a) => s + (a.positions?.length || 0), 0),
    accountCount: accounts.length,
    activeCount: active.length,
    maxDrawdown: active.length > 0 ? Math.max(...active.map(a => a.drawdown || 0)) : 0,
    lastUpdate: lastUpdateTime,
  });
});

// Un compte spécifique
app.get('/api/accounts/:id', auth, (req, res) => {
  const account = accountsData[req.params.id];
  if (!account) return res.status(404).json({ error: 'Compte non trouvé' });
  const { _filePath, _fileAge, _isStale, ...rest } = account;
  res.json({ ...rest, isStale: _isStale, dataAge: _fileAge });
});

// ============================================================
// DÉMARRAGE
// ============================================================
app.listen(PORT, '0.0.0.0', () => {
  console.log('');
  console.log('╔══════════════════════════════════════════╗');
  console.log('║     TRADING DASHBOARD — API SERVER       ║');
  console.log('║     Julien Barange                       ║');
  console.log('╠══════════════════════════════════════════╣');
  console.log(`║  Port:     ${PORT}                            ║`);
  console.log(`║  API Key:  ${API_KEY.substring(0, 6)}...                     ║`);
  console.log(`║  URL:      http://localhost:${PORT}           ║`);
  console.log('╚══════════════════════════════════════════╝');
  console.log('');

  // Scan initial
  const found = scanAllAccounts();
  console.log(`[INIT] ${found.length} compte(s) trouvé(s): ${found.join(', ') || 'aucun'}`);

  // Watcher
  startWatcher();

  // Re-scan toutes les 30s
  setInterval(() => {
    scanAllAccounts();
  }, 30000);

  console.log('');
  console.log('[OK] Serveur prêt. En attente des données MT4...');
  console.log(`[INFO] Les EAs doivent exporter dans: ${DATA_DIRS[0]}`);
  console.log('');
});
