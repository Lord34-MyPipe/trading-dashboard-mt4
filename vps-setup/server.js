// ============================================================
// SERVEUR NODE.JS — Trading Dashboard API v2.1
// Tourne sur le VPS, lit les JSON exportés par les EAs MT4
// + accepte les données envoyées depuis des machines externes
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
app.use(express.json({ limit: '1mb' }));

// ============================================================
// CONFIGURATION
// ============================================================
const PORT = process.env.PORT || 3001;
const API_KEY = process.env.API_KEY || 'jb-trading-2026';

const DATA_DIRS = [
  'C:\\TradingDashboard\\data',
  path.join(process.env.APPDATA || '', 'MetaQuotes', 'Terminal', 'Common', 'Files'),
];

// ============================================================
// STOCKAGE EN MÉMOIRE
// ============================================================
let accountsData = {};      // Comptes lus depuis les fichiers JSON locaux
let remoteAccounts = {};    // Comptes envoyés depuis des machines externes (Mac, etc.)
let lastUpdateTime = null;
let serverStartTime = new Date();

// ============================================================
// LECTURE DES FICHIERS JSON LOCAUX
// ============================================================
function loadFile(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    const stat = fs.statSync(filePath);
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
      console.log(`[UPDATE] ${data.alias || data.accountId} — Bal: ${data.balance} | Eq: ${data.equity}`);
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
  const local = Object.values(accountsData);
  const remote = Object.values(remoteAccounts);
  const all = [...local, ...remote];
  res.json({
    status: 'ok',
    uptime: Math.round(process.uptime()),
    accounts: all.length,
    localAccounts: local.length,
    remoteAccounts: remote.length,
    activeAccounts: all.filter(a => !a._isStale).length,
    lastUpdate: lastUpdateTime,
    serverStart: serverStartTime.toISOString(),
    dataDirs: DATA_DIRS.map(d => ({ path: d, exists: fs.existsSync(d) })),
  });
});

// Toutes les données des comptes (locaux + distants)
app.get('/api/accounts', auth, (req, res) => {
  let local = Object.values(accountsData);
  let remote = Object.values(remoteAccounts);

  // Si aucune donnée locale, re-scanner
  if (local.length === 0) {
    scanAllAccounts();
    local = Object.values(accountsData);
  }

  // Marquer les comptes distants comme stale si pas de mise à jour depuis 2 minutes
  remote = remote.map(a => {
    const age = a._lastReceived ? (Date.now() - a._lastReceived) / 60000 : 999;
    return { ...a, _isStale: age > 2, _fileAge: Math.round(age) };
  });

  // Dédupliquer par accountId — les comptes distants ont priorité (données plus fraîches)
  const merged = {};
  for (const a of local) { merged[a.accountId] = a; }
  for (const a of remote) { merged[a.accountId] = a; }
  const all = Object.values(merged);

  const clean = all.map(a => {
    const { _filePath, _fileAge, _isStale, _lastReceived, _source, ...rest } = a;
    return { ...rest, isStale: _isStale, dataAge: _fileAge, source: _source || 'local' };
  });

  res.json({
    accounts: clean,
    lastUpdate: lastUpdateTime,
    count: clean.length,
    activeCount: clean.filter(a => !a.isStale).length,
  });
});

// ============================================================
// RECEVOIR DES DONNÉES DEPUIS UNE MACHINE EXTERNE (Mac, etc.)
// POST /api/push — envoie le JSON d'un compte
// ============================================================
app.post('/api/push', auth, (req, res) => {
  const data = req.body;

  if (!data || !data.accountId) {
    return res.status(400).json({ error: 'accountId manquant dans le body' });
  }

  data._lastReceived = Date.now();
  data._isStale = false;
  data._fileAge = 0;
  data._source = 'remote';

  remoteAccounts[data.accountId] = data;
  lastUpdateTime = new Date().toISOString();

  console.log(`[REMOTE] ${data.alias || data.accountId} — Bal: ${data.balance} | Eq: ${data.equity} | From: ${req.ip}`);

  res.json({ ok: true, accountId: data.accountId });
});

// Un compte spécifique
app.get('/api/accounts/:id', auth, (req, res) => {
  const account = accountsData[req.params.id] || remoteAccounts[req.params.id];
  if (!account) return res.status(404).json({ error: 'Compte non trouvé' });
  const { _filePath, _fileAge, _isStale, _lastReceived, _source, ...rest } = account;
  res.json({ ...rest, isStale: _isStale, dataAge: _fileAge });
});

// ============================================================
// DÉMARRAGE
// ============================================================
app.listen(PORT, '0.0.0.0', () => {
  console.log('');
  console.log('╔══════════════════════════════════════════╗');
  console.log('║   TRADING DASHBOARD — API SERVER v2.1    ║');
  console.log('║   Julien Barange                         ║');
  console.log('╠══════════════════════════════════════════╣');
  console.log(`║  Port:     ${PORT}                            ║`);
  console.log(`║  API Key:  ${API_KEY.substring(0, 6)}...                     ║`);
  console.log(`║  URL:      http://localhost:${PORT}           ║`);
  console.log('║  Remote:   POST /api/push?key=...        ║');
  console.log('╚══════════════════════════════════════════╝');
  console.log('');

  const found = scanAllAccounts();
  console.log(`[INIT] ${found.length} compte(s) local trouvé(s): ${found.join(', ') || 'aucun'}`);

  startWatcher();

  setInterval(() => { scanAllAccounts(); }, 30000);

  console.log('');
  console.log('[OK] Serveur prêt. Accepte les données locales + distantes.');
  console.log('');
});
