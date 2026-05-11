================================================================
 OPR Strategy MT4 - XAU/USD & NAS100
 Expert Advisors : OPR_Gold.mq4 / OPR_Nas100.mq4
 Version 1.00
================================================================

OBJET
-----
Deux EA MT4 implementant la strategie Opening Range Breakout
(OPR) sur le range des 30 premieres minutes apres l'ouverture
de Wall Street (NY 9h30 ET).

Logique commune :
  - Capture HIGH/LOW M1 des 30 min suivant l'ouverture NY
  - Filtre ATR(14) H1 > SMA(ATR, 20) H1
  - Entree sur cloture M5 au-dessus du High / sous le Low du range
  - Body de la M5 > 60 % du range total
  - SL : extreme oppose du range +/- ATR(14) M5 * 0.5
  - TP1 (75 %) : entree + (SL distance * 1.75)
  - TP2 (25 %) : trailing stop = range OPR * 0.5
  - 1 trade max / jour / EA, magic number par symbole
  - Aucune trade le vendredi ni les jours macro
  - Fermeture forcee a 15h30 NY


----------------------------------------------------------------
1. INSTALLATION DANS METATRADER 4
----------------------------------------------------------------

1) Ouvrir MT4.
2) Menu Fichier > Ouvrir le repertoire de donnees.
3) Aller dans MQL4 > Experts.
4) Copier les fichiers OPR_Gold.mq4 et OPR_Nas100.mq4 dans
   ce dossier.
5) Redemarrer MT4 (ou clic droit "Actualiser" dans le
   Navigator > Experts).
6) Compiler chaque fichier (clic droit > Modifier puis F7
   dans MetaEditor). Aucun warning critique attendu.
7) Glisser OPR_Gold sur un graphique XAU/USD.
   Glisser OPR_Nas100 sur un graphique NAS100 (US100).
   Timeframe recommande : M5 (la strategie utilise M1/M5/H1
   en interne, le TF du chart n'a pas d'impact).
8) Onglet Options : cocher
      - Autoriser le trading automatique
      - Autoriser le DLL : NON (aucune DLL utilisee)
      - Autoriser la lecture des reglages : non requis
9) Activer l'AutoTrading (bouton vert en haut).


----------------------------------------------------------------
2. HEURE SERVEUR ROBOFOREX (UTC+3 ETE / UTC+2 HIVER)
----------------------------------------------------------------

L'ouverture NY (9h30 ET) doit etre correctement mappee a
l'heure serveur de votre courtier RoboForex.

  ETE  (DST US active, ~mi-mars a debut novembre) :
      Serveur RoboForex = UTC+3
      9h30 NY = 16h30 serveur
      => NYOpen_ServerHour = 16
         NYOpen_ServerMin  = 30
         TradeEnd_ServerHour = 22  (= 15h30 NY)
         TradeEnd_ServerMin  = 30

  HIVER (DST US inactive, debut novembre a mi-mars) :
      Serveur RoboForex = UTC+2 (Europe DST encore active
      jusqu'a fin octobre) OU UTC+3 selon la periode.
      Verifier dans MT4 : Outils > Options > Serveur
      pour confirmer l'offset reel.

      Cas typique fin novembre - mi-mars :
      9h30 NY (EST) = 15h30 serveur (UTC+2) ou 16h30 (UTC+3)
      Ajuster NYOpen_ServerHour selon ce qui est constate.

VERIFICATION SIMPLE :
  Sur le chart, regarder l'heure d'une bougie M5 dont vous
  connaissez l'heure NY (ex: cloture US 16h00 NY).
  La difference donne l'offset serveur courant.

Apres chaque changement d'heure (mars / novembre / decalage
DST asymetrique entre US et Europe pendant ~2 semaines),
verifier et ajuster les inputs.


----------------------------------------------------------------
3. PARAMETRES RECOMMANDES POUR LE FORWARD TEST (DEMO 0.5 %)
----------------------------------------------------------------

Pour le forward test prudent en mode demo :

  --- OPR_Gold (XAU/USD) ---
  RiskPercent         = 0.5
  MinRangeSize        = 200
  MaxRangeSize        = 600
  MaxSpreadPoints     = 50     (spread Gold parfois large)
  RR_TP1              = 1.75
  ScaleOut_TP1_Pct    = 75.0
  TrailMultiplier     = 0.5
  FilterATR           = true
  MinBodyRatio        = 0.60
  NoFriday            = true
  NoTradeNewsDay      = true
  MagicNumber         = 20250101

  --- OPR_Nas100 ---
  RiskPercent         = 0.5
  MinRangeSize        = 30
  MaxRangeSize        = 120
  MaxSpreadPoints     = 80     (spread NAS100 souvent eleve)
  RR_TP1              = 1.75
  ScaleOut_TP1_Pct    = 75.0
  TrailMultiplier     = 0.5
  FilterATR           = true
  MinBodyRatio        = 0.60
  NoFriday            = true
  NoTradeNewsDay      = true
  MagicNumber         = 20250102      <- different de Gold !

Duree de forward test recommandee : 30 jours minimum.

Apres validation forward (drawdown maitrise, win rate stable),
basculer en live et passer RiskPercent a 1.0.


----------------------------------------------------------------
4. JOURS MACRO (NFP / CPI / FOMC)
----------------------------------------------------------------

Avant chaque journee macro a fort impact, mettre a jour le
parametre NewsDate dans les deux EA :

  NewsDate = "2026.05.14"   (format YYYY.MM.DD)
  NoTradeNewsDay = true

Calendrier macro mensuel typique a surveiller :
  - NFP : 1er vendredi du mois (deja exclu par NoFriday)
  - CPI : mi-mois
  - FOMC : 8 fois par an (verifier l'agenda Fed)
  - PCE, PPI, retail sales : voir Forex Factory

Si plusieurs jours sont a exclure dans le mois, modifier
NewsDate chaque matin avant 16h30 serveur.


----------------------------------------------------------------
5. CHECKLIST DE VERIFICATION AVANT LANCEMENT LIVE
----------------------------------------------------------------

  [ ] EA compile sans erreur (F7 dans MetaEditor)
  [ ] Bouton AutoTrading actif (vert)
  [ ] "Autoriser le trading automatique" coche dans
      les proprietes de l'EA
  [ ] Symbole correct (XAU/USD pour Gold, NAS100/US100 pour
      l'autre - verifier le nom exact chez RoboForex)
  [ ] NYOpen_ServerHour / Min coherent avec l'heure serveur
      courante (DST verifie)
  [ ] MagicNumber different pour Gold et Nas100
  [ ] RiskPercent <= 0.5 pour le premier mois live
  [ ] MaxSpreadPoints adapte aux conditions broker
  [ ] Le dashboard apparait en haut a gauche du chart
  [ ] Solde du compte coherent (15 000 EUR / 1 % = 150 EUR
      max de perte par trade)
  [ ] VPS lance 24/7 si possible (latence faible vers RoboForex)
  [ ] Capacite de couper l'EA a distance (mobile MT4 ou VPS)
  [ ] Sauvegarde des templates et set files dans
      MQL4/Presets
  [ ] Journal MT4 verifie chaque soir pour traces TRADE OPENED
      et erreurs eventuelles
  [ ] News calendrier verifie chaque soir pour le lendemain


----------------------------------------------------------------
6. STRUCTURE DES LOGS (journal MT4)
----------------------------------------------------------------

Chaque trade ouvert produit une ligne :

  OPR_Gold TRADE OPENED >>> 2026.05.11 16:42:13 | XAUUSD |
  LONG | lot1=0.08 lot2=0.02 | entry=2345.67 | SL=2340.12 |
  TP1=2355.39 | range=287.5 pips | ATR_M5=1.234

Pour exporter : MT4 > onglet Experts (en bas) > clic droit >
Ouvrir.


----------------------------------------------------------------
7. NOTES TECHNIQUES
----------------------------------------------------------------

- Aucune DLL, aucun include externe.
- Compatible MT4 build 1380+.
- Le scale-out 75/25 est implemente en deux ordres distincts
  partageant le meme magic number (commentaires OPR_TP1 et
  OPR_TRAIL pour les identifier).
- Si le volume calcule (25 % de la position totale) tombe
  sous le minLot du broker, l'EA bascule automatiquement
  en mode "ordre unique" et le trailing 25 % n'est pas
  applique. Verifier le journal apres chaque trade.
- Tous les ordres sont fermes a 15h30 NY (TradeEnd_*), meme
  ceux qui sont en trailing.
- En cas de redemarrage de MT4 en milieu de journee avec une
  position ouverte : la fonction RecoverState() reconstruit
  les variables d'etat depuis les ordres existants (memes
  symbole + magic number).
- Slippage fixe a 5 points sur chaque OrderSend / OrderClose.

================================================================
                       FIN DU README
================================================================
