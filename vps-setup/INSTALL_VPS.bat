@echo off
echo ============================================
echo   TRADING DASHBOARD - Installation VPS
echo   Julien Barange
echo ============================================
echo.

:: Créer le dossier principal
echo [1/5] Creation des dossiers...
mkdir C:\TradingDashboard 2>nul
mkdir C:\TradingDashboard\data 2>nul
echo       OK - C:\TradingDashboard\data cree

:: Copier les fichiers
echo [2/5] Copie des fichiers serveur...
copy /Y server.js C:\TradingDashboard\ >nul
copy /Y package.json C:\TradingDashboard\ >nul
echo       OK - Fichiers copies

:: Vérifier Node.js
echo [3/5] Verification de Node.js...
node --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo       ERREUR: Node.js n'est pas installe!
    echo       Telecharge-le sur https://nodejs.org
    echo       Puis relance ce script.
    pause
    exit /b 1
)
echo       OK - Node.js detecte

:: Installer les dépendances
echo [4/5] Installation des dependances npm...
cd C:\TradingDashboard
call npm install
echo       OK - Dependances installees

:: Installer PM2 pour garder le serveur actif
echo [5/5] Installation de PM2 (process manager)...
call npm install -g pm2 >nul 2>&1
call pm2 start server.js --name trading-dashboard
call pm2 save
echo       OK - Serveur demarre avec PM2

echo.
echo ============================================
echo   INSTALLATION TERMINEE!
echo ============================================
echo.
echo   Serveur: http://localhost:3001
echo   API Key: jb-trading-2026
echo.
echo   Test: http://localhost:3001/api/health
echo.
echo   PROCHAINE ETAPE:
echo   1. Ouvre le pare-feu Windows (port 3001)
echo   2. Copie AccountExporter_EA.mq4 dans chaque MT4
echo   3. Glisse l'EA sur un graphique de chaque MT4
echo.
echo   Pour voir les logs: pm2 logs trading-dashboard
echo   Pour redemarrer:    pm2 restart trading-dashboard
echo.
pause
