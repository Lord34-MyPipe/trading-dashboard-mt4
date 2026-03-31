@echo off
echo ============================================
echo   Ouverture du port 3001 dans le pare-feu
echo   (Executer en tant qu'Administrateur!)
echo ============================================
echo.

netsh advfirewall firewall add rule name="Trading Dashboard API" dir=in action=allow protocol=tcp localport=3001

echo.
echo   OK - Port 3001 ouvert
echo   Le dashboard peut maintenant se connecter au VPS
echo.
pause
