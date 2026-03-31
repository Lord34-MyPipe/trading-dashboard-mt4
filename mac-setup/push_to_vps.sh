#!/bin/bash
# ============================================================
# PUSH TO VPS — Envoie les données MT4 du Mac vers le VPS
# Tourne en boucle, envoie le JSON toutes les 10 secondes
# ============================================================
# Usage: ./push_to_vps.sh
# Pour lancer en arrière-plan: nohup ./push_to_vps.sh > ~/push_vps.log 2>&1 &
# ============================================================

VPS_URL="http://23.109.152.205:3001"
API_KEY="jb-trading-2026"
INTERVAL=10

# Dossier MT4 sur Mac (via Wine/CrossOver)
MT4_DATA_DIR="/Users/julienbarange/Library/Application Support/net.metaquotes.wine.metatrader4/drive_c/Program Files (x86)/MetaTrader 4/MQL4/Files"

echo "============================================"
echo "  PUSH TO VPS — Trading Dashboard"
echo "============================================"
echo "  VPS:      $VPS_URL"
echo "  Dossier:  $MT4_DATA_DIR"
echo "  Interval: ${INTERVAL}s"
echo "============================================"
echo ""

while true; do
    for jsonfile in "$MT4_DATA_DIR"/dashboard_*.json; do
        [ -f "$jsonfile" ] || continue

        # Vérifier que le fichier a été modifié dans les 2 dernières minutes
        if [ "$(find "$jsonfile" -mmin -2 2>/dev/null)" ]; then
            response=$(curl -s -w "\n%{http_code}" -X POST \
                "${VPS_URL}/api/push?key=${API_KEY}" \
                -H "Content-Type: application/json" \
                -d @"$jsonfile" 2>&1)

            http_code=$(echo "$response" | tail -1)
            filename=$(basename "$jsonfile")
            timestamp=$(date '+%H:%M:%S')

            if [ "$http_code" = "200" ]; then
                echo "[$timestamp] OK $filename → VPS"
            else
                echo "[$timestamp] ERREUR $filename → HTTP $http_code"
            fi
        fi
    done

    sleep $INTERVAL
done
