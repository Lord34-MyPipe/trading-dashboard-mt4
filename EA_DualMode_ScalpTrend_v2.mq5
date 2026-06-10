//+------------------------------------------------------------------+
//|                                  EA_DualMode_ScalpTrend_v2.mq5    |
//|              Expert Advisor double mode pour MetaTrader 5 - V2    |
//|                                                                  |
//|  NOUVEAUTES V2 (correction de la structure des pertes)           |
//|  -----------------------------------------------------          |
//|  Diagnostic V1 : taux de reussite correct MAIS pertes moyennes   |
//|  4 a 5 fois plus grosses que les gains -> esperance negative.    |
//|  La V2 attaque la TAILLE DES PERTES, pas le taux de reussite :   |
//|   1. Sortie anticipee sur cassure opposee : si une bougie cloture|
//|      au-dela du niveau oppose de la bougie d'entree, on coupe    |
//|      immediatement (perte reduite, sans attendre le SL plein).   |
//|   2. Time-stop : un trade encore negatif apres N bougies est     |
//|      coupe (les trades "morts" saignent du swap et du temps).    |
//|   3. SL base sur l'ATR + plafond de SL : plus de SL geant pose   |
//|      sur l'extreme d'une bougie de panique.                      |
//|   4. Prise de profit PARTIELLE a 1R + passage break-even :       |
//|      on encaisse une partie, le reste court avec le trailing.    |
//|   5. Trailing base ATR : distance adaptee a la volatilite reelle |
//|      du symbole (corrige le probleme des pips sur XAUUSD).       |
//|   6. Taille de lot par % de risque : chaque trade risque le meme |
//|      montant quel que soit la distance du SL.                    |
//|                                                                  |
//|  AUCUNE martingale, AUCUN doublement, AUCUN hedge de recuperation|
//|  (un hedge a taille egale equivaut a une cloture, en payant un   |
//|  deuxieme spread : c'est volontairement exclu).                  |
//|                                                                  |
//|  DEUX MODES (parametre InpMode)                                  |
//|  ------------------------------                                  |
//|  MODE A - "Scalp Rebate"  : rotations rapides, sorties BE.       |
//|  MODE B - "Trend Follow"  : laisser courir, trailing large.      |
//|  Sentinelle -1 sur les parametres specifiques au mode.           |
//|                                                                  |
//|  NOTE PIPS / XAUUSD : sur un symbole a 2 decimales (or), 1 pip   |
//|  EA = 1 point = 0.01 USD de mouvement. Preferez les options ATR  |
//|  (SL, trailing) qui s'adaptent automatiquement au symbole.       |
//|                                                                  |
//|  *****************************************************************|
//|  *  AVERTISSEMENT : A TESTER EXCLUSIVEMENT SUR COMPTE DEMO       *|
//|  *  AVANT TOUT USAGE REEL. Le passe ne prejuge pas du futur.    *|
//|  *  Aucune garantie de profit. Utilisation a vos risques.       *|
//|  *****************************************************************|
//+------------------------------------------------------------------+
#property copyright "EA DualMode ScalpTrend"
#property version   "2.00"
#property strict
#property description "EA double mode V2 - breakout + controle strict de la taille des pertes. DEMO uniquement."

#include <Trade/Trade.mqh>

//==================================================================//
//                            ENUMS                                 //
//==================================================================//

// Mode de fonctionnement (preselection des defauts)
enum ENUM_EA_MODE
  {
   MODE_A_SCALP_REBATE = 0,   // Mode A - Scalp Rebate (max rotations)
   MODE_B_TREND_FOLLOW = 1    // Mode B - Trend Follow (gains de mouvement)
  };

// Etat tri-etat pour le reverse
enum ENUM_REVERSE_STATE
  {
   REVERSE_DEFAULT_MODE = 0,  // Defaut du mode (A=ON, B=OFF)
   REVERSE_FORCE_ON     = 1,  // Forcer ON
   REVERSE_FORCE_OFF    = 2   // Forcer OFF
  };

// Mode de calcul du stop loss initial
enum ENUM_SL_MODE
  {
   SL_CANDLE     = 0,         // Extreme de la bougie de reference
   SL_FIXED_PIPS = 1,         // Distance fixe en pips
   SL_ATR        = 2          // ATR x multiplicateur (recommande)
  };

//==================================================================//
//                            INPUTS                                //
//==================================================================//

input group "=== Mode & Timeframe ==="
input ENUM_EA_MODE     InpMode            = MODE_B_TREND_FOLLOW; // Mode de strategie
input ENUM_TIMEFRAMES  InpRefTimeframe    = PERIOD_M15;          // Timeframe de reference

input group "=== Volume & Risque ==="
input double           InpLotSize         = 0.10;   // Lot fixe (si InpRiskPercent=0)
input double           InpRiskPercent     = 0.0;    // % du solde risque/trade (0 = lot fixe)
input double           InpBufferPips      = 1.0;    // Buffer au-dela de l'extreme (pips)
input int              InpMaxPositions    = 5;      // Nb max de positions simultanees

input group "=== Filtre de tendance (ADX) ==="
input bool             InpUseADXFilter    = true;   // Activer le filtre ADX
input int              InpADXPeriod       = 14;     // Periode ADX
input double           InpADXThreshold    = -1.0;   // Seuil ADX (-1 = defaut mode : A=20 / B=25)

input group "=== Stop loss initial ==="
input ENUM_SL_MODE     InpSLMode          = SL_ATR; // Mode de calcul du SL initial
input double           InpInitialSLPips   = 15.0;   // SL fixe (pips) si SL_FIXED_PIPS
input int              InpATRPeriod       = 14;     // Periode ATR (SL et trailing ATR)
input double           InpATRSLMult       = 1.5;    // Multiplicateur ATR pour le SL
input double           InpMaxSLPips       = 0.0;    // Plafond du SL en pips (0 = aucun)

input group "=== Reduction des pertes (NOUVEAU V2) ==="
input bool             InpExitOppositeBreak = true; // Sortie anticipee sur cassure opposee
input int              InpTimeStopBars      = 8;    // Time-stop : couper si negatif apres N bougies (0=off)

input group "=== Prise de profit partielle (NOUVEAU V2) ==="
input bool             InpUsePartialClose   = true; // Activer la cloture partielle
input double           InpPartialTriggerRR  = 1.0;  // Declenchement en multiple de R (1.0 = +1R)
input double           InpPartialClosePct   = 50.0; // % du volume clos (necessite lot >= 2x lot min)

input group "=== Break-even & Trailing (sentinelle -1 = defaut du mode) ==="
input double           InpBETriggerPips   = -1.0;   // Profit declenchant le BE (pips) (-1 = A:3 / B:8)
input double           InpBELockPips      = 1.0;    // Verrou au-dessus de l'entree (pips)
input double           InpTrailingPips    = -1.0;   // Distance trailing (pips) (-1 = A:3 / B:12)
input bool             InpUseATRTrailing  = true;   // Trailing base ATR (prioritaire sur les pips)
input double           InpTrailATRMult    = 1.0;    // Multiplicateur ATR du trailing

input group "=== Reverse (Stop-and-Reverse) ==="
input ENUM_REVERSE_STATE InpReverseState  = REVERSE_DEFAULT_MODE; // Reverse a la fermeture sur stop

input group "=== Session horaire (heure serveur) ==="
input int              InpSessionStartHour   = 8;     // Heure de debut de session
input int              InpSessionEndHour     = 21;    // Heure de fin de session
input bool             InpCloseAtSessionEnd  = false; // Forcer la cloture en fin de session

input group "=== Gestion journaliere collective (devise du compte) ==="
input double           InpDailyTargetMoney   = 0.0;   // Cible jour (0 = BE strict)
input double           InpDailyMaxLossMoney  = 200.0; // Plafond catastrophe jour

input group "=== Divers ==="
input long             InpMagicNumber     = 20260601; // Magic number
input bool             InpVerboseLog      = true;      // Logs detailles

//==================================================================//
//                       VARIABLES GLOBALES                         //
//==================================================================//

CTrade   trade;
int      g_adxHandle = INVALID_HANDLE;
int      g_atrHandle = INVALID_HANDLE;

datetime g_lastBarTime = 0;
datetime g_currentDay  = 0;

double   g_realizedPLToday    = 0.0;
bool     g_tradingHaltedToday = false;

// Parametres effectifs resolus (mode + sentinelles)
double   g_BETriggerPips = 0.0;
double   g_TrailingPips  = 0.0;
double   g_ADXThreshold  = 0.0;
bool     g_ReverseOn     = false;

// Cache conversion pips <-> prix
double   g_pipSize      = 0.0;
double   g_pointsPerPip = 1.0;

// Suivi par position : risque initial (R), niveau oppose, partiel fait
struct STrack
  {
   ulong  ticket;        // ticket de la position
   double initRiskPrice; // distance entree -> SL initial (definit 1R)
   double oppLevel;      // niveau de cassure opposee (sortie anticipee)
   bool   partialDone;   // cloture partielle deja effectuee
  };
STrack   g_tracks[];

//==================================================================//
//                         INITIALISATION                           //
//==================================================================//
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(20);

   g_pointsPerPip = PointsPerPip();
   g_pipSize      = _Point * g_pointsPerPip;

   ResolveModeDefaults();

   //--- Handle ADX
   if(InpUseADXFilter)
     {
      g_adxHandle = iADX(_Symbol, InpRefTimeframe, InpADXPeriod);
      if(g_adxHandle == INVALID_HANDLE)
        {
         Print("ERREUR : impossible de creer le handle ADX.");
         return(INIT_FAILED);
        }
     }

   //--- Handle ATR (utilise pour SL_ATR et/ou trailing ATR)
   g_atrHandle = iATR(_Symbol, InpRefTimeframe, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("ERREUR : impossible de creer le handle ATR.");
      return(INIT_FAILED);
     }

   //--- Validation des inputs
   if(InpSessionStartHour < 0 || InpSessionStartHour > 23 ||
      InpSessionEndHour   < 0 || InpSessionEndHour   > 23)
     {
      Print("ERREUR : heures de session invalides (0-23).");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpRiskPercent <= 0.0 && NormalizeLot(InpLotSize) <= 0.0)
     {
      Print("ERREUR : InpLotSize invalide pour ce symbole.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpPartialClosePct <= 0.0 || InpPartialClosePct >= 100.0)
     {
      Print("ERREUR : InpPartialClosePct doit etre entre 0 et 100 exclus.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   g_currentDay  = DayStart(TimeCurrent());
   g_lastBarTime = iTime(_Symbol, InpRefTimeframe, 0);
   UpdateRealizedPL();
   g_tradingHaltedToday = false;
   ArrayResize(g_tracks, 0);

   Log(StringFormat("OnInit V2 OK | Mode=%s | TF=%s | SLmode=%s | BETrig=%.1f Trail=%.1f(ATR=%s) ADX=%.1f Rev=%s | pip=%.5f",
                    (InpMode==MODE_A_SCALP_REBATE ? "A-Scalp" : "B-Trend"),
                    EnumToString(InpRefTimeframe), EnumToString(InpSLMode),
                    g_BETriggerPips, g_TrailingPips, (InpUseATRTrailing ? "oui" : "non"),
                    g_ADXThreshold, (g_ReverseOn ? "ON" : "OFF"), g_pipSize));

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Resolution des defauts de mode (sentinelles -1)                  |
//+------------------------------------------------------------------+
void ResolveModeDefaults()
  {
   double defBETrig, defTrail, defADX;
   bool   defReverse;

   if(InpMode == MODE_A_SCALP_REBATE)
     {
      defBETrig  = 3.0;
      defTrail   = 3.0;
      defADX     = 20.0;
      defReverse = true;
     }
   else // MODE_B_TREND_FOLLOW
     {
      defBETrig  = 8.0;
      defTrail   = 12.0;
      defADX     = 25.0;
      defReverse = false;
     }

   g_BETriggerPips = (InpBETriggerPips < 0.0 ? defBETrig : InpBETriggerPips);
   g_TrailingPips  = (InpTrailingPips  < 0.0 ? defTrail  : InpTrailingPips);
   g_ADXThreshold  = (InpADXThreshold  < 0.0 ? defADX    : InpADXThreshold);

   switch(InpReverseState)
     {
      case REVERSE_FORCE_ON:  g_ReverseOn = true;  break;
      case REVERSE_FORCE_OFF: g_ReverseOn = false; break;
      default:                g_ReverseOn = defReverse; break;
     }
  }

//==================================================================//
//                          DESINITIALISATION                       //
//==================================================================//
void OnDeinit(const int reason)
  {
   if(g_adxHandle != INVALID_HANDLE)
      IndicatorRelease(g_adxHandle);
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   Log(StringFormat("OnDeinit | raison=%d | realise_jour=%.2f", reason, g_realizedPLToday));
  }

//==================================================================//
//                            ON TICK                               //
//==================================================================//
void OnTick()
  {
   //--- 1) Reinitialisation quotidienne
   CheckNewDay();

   //--- 2) P&L realise du jour
   UpdateRealizedPL();

   //--- 3) Controle des seuils journaliers (cible / plafond)
   double totalToday = CalcDailyPL();
   if(CheckDailyTargets(totalToday))
      return;

   //--- 4) Halte journaliere active : ne rien faire
   if(g_tradingHaltedToday)
      return;

   //--- 5) Reduction des pertes : time-stop puis prise partielle
   ManageTimeStop();
   ManagePartialClose();

   //--- 6) Gestion BE / trailing
   ManageBreakEven();
   ManageTrailing();

   //--- 7) Filet de securite : pending oppose restant
   ManagePendingPair();

   //--- 8) Session horaire
   if(!IsTradingSession())
     {
      RemovePendingOrders();
      if(InpCloseAtSessionEnd)
         CloseAllPositions("Fin de session");
      return;
     }

   //--- 9) Nouvelle bougie de reference
   if(IsNewBar())
      OnNewBar();
  }

//==================================================================//
//                  GESTION DU JOUR / SEUILS                        //
//==================================================================//

//+------------------------------------------------------------------+
//| Detecte un changement de jour serveur et reinitialise l'etat     |
//+------------------------------------------------------------------+
void CheckNewDay()
  {
   datetime today = DayStart(TimeCurrent());
   if(today != g_currentDay)
     {
      g_currentDay         = today;
      g_realizedPLToday    = 0.0;
      g_tradingHaltedToday = false;
      Log("Nouveau jour serveur : reinitialisation (realise=0, halte levee).");
     }
  }

//+------------------------------------------------------------------+
//| Timestamp du debut du jour (00:00 serveur)                       |
//+------------------------------------------------------------------+
datetime DayStart(datetime t)
  {
   MqlDateTime st;
   TimeToStruct(t, st);
   st.hour = 0;
   st.min  = 0;
   st.sec  = 0;
   return(StructToTime(st));
  }

//+------------------------------------------------------------------+
//| Cumule le P&L realise du jour (deals fermes depuis 00:00)        |
//+------------------------------------------------------------------+
void UpdateRealizedPL()
  {
   double realized = 0.0;
   datetime from = g_currentDay;
   if(from == 0)
      from = DayStart(TimeCurrent());

   if(!HistorySelect(from, TimeCurrent() + 1))
      return;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
         continue;

      realized += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      realized += HistoryDealGetDouble(ticket, DEAL_SWAP);
      realized += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
     }
   g_realizedPLToday = realized;
  }

//+------------------------------------------------------------------+
//| total_jour = realise du jour + flottant des positions de l'EA    |
//+------------------------------------------------------------------+
double CalcDailyPL()
  {
   double floating = 0.0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(!SelectMyPosition(ticket))
         continue;
      floating += PositionGetDouble(POSITION_PROFIT);
      floating += PositionGetDouble(POSITION_SWAP);
     }
   return(g_realizedPLToday + floating);
  }

//+------------------------------------------------------------------+
//| Cible jour / plafond catastrophe. true si cloture collective.    |
//+------------------------------------------------------------------+
bool CheckDailyTargets(double totalToday)
  {
   if(g_tradingHaltedToday)
      return(false);

   //--- Plafond catastrophe (prioritaire, non negociable)
   if(InpDailyMaxLossMoney > 0.0 && totalToday <= -InpDailyMaxLossMoney)
     {
      Log(StringFormat("PLAFOND CATASTROPHE : total_jour=%.2f <= -%.2f -> cloture totale + halte.",
                       totalToday, InpDailyMaxLossMoney));
      CloseAllPositions("Plafond catastrophe");
      RemovePendingOrders();
      g_tradingHaltedToday = true;
      return(true);
     }

   //--- Cible jour
   if(totalToday >= InpDailyTargetMoney &&
      (InpDailyTargetMoney > 0.0 || HasAnyActivityToday()))
     {
      Log(StringFormat("CIBLE JOUR atteinte : total_jour=%.2f >= %.2f -> cloture totale + halte.",
                       totalToday, InpDailyTargetMoney));
      CloseAllPositions("Cible jour");
      RemovePendingOrders();
      g_tradingHaltedToday = true;
      return(true);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Activite aujourd'hui ? (evite la cible 0 declenchee a vide)      |
//+------------------------------------------------------------------+
bool HasAnyActivityToday()
  {
   if(g_realizedPLToday != 0.0)
      return(true);
   return(CountEAPositions() > 0);
  }

//==================================================================//
//              REDUCTION DES PERTES (NOUVEAU V2)                   //
//==================================================================//

//+------------------------------------------------------------------+
//| Time-stop : coupe une position encore negative apres N bougies   |
//+------------------------------------------------------------------+
void ManageTimeStop()
  {
   if(InpTimeStopBars <= 0)
      return;

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!SelectMyPosition(ticket))
         continue;

      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      int bars = iBarShift(_Symbol, InpRefTimeframe, opened);
      if(bars < InpTimeStopBars)
         continue;

      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(profit < 0.0)
        {
         if(trade.PositionClose(ticket))
            Log(StringFormat("TIME-STOP #%I64u : negatif (%.2f) apres %d bougies -> coupe. total_jour=%.2f",
                             ticket, profit, bars, CalcDailyPL()));
        }
     }
  }

//+------------------------------------------------------------------+
//| Sortie anticipee : la bougie a cloture au-dela du niveau oppose  |
//| de la bougie d'entree -> le marche prouve qu'on a tort, on coupe |
//| sans attendre le SL plein. Appele sur nouvelle bougie.           |
//+------------------------------------------------------------------+
void CheckOppositeBreakExit()
  {
   if(!InpExitOppositeBreak)
      return;

   double closePrev = iClose(_Symbol, InpRefTimeframe, 1);
   if(closePrev <= 0.0)
      return;

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!SelectMyPosition(ticket))
         continue;

      int idx = GetTrackIndex(ticket);
      if(idx < 0)
         continue; // pas de suivi (ex. redemarrage) : on laisse le SL gerer
      double opp = g_tracks[idx].oppLevel;
      if(opp <= 0.0)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      bool exitNow = false;

      if(type == POSITION_TYPE_BUY && closePrev < opp)
         exitNow = true;
      if(type == POSITION_TYPE_SELL && closePrev > opp)
         exitNow = true;

      if(exitNow)
        {
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(trade.PositionClose(ticket))
            Log(StringFormat("SORTIE ANTICIPEE #%I64u : cloture au-dela du niveau oppose %.5f (P&L %.2f). total_jour=%.2f",
                             ticket, opp, profit, CalcDailyPL()));
        }
     }
  }

//+------------------------------------------------------------------+
//| Cloture partielle a +X R : encaisse une partie, SL au BE,        |
//| le reste court avec le trailing.                                 |
//+------------------------------------------------------------------+
void ManagePartialClose()
  {
   if(!InpUsePartialClose)
      return;

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(!SelectMyPosition(ticket))
         continue;

      int idx = GetTrackIndex(ticket);
      if(idx < 0 || g_tracks[idx].partialDone)
         continue;

      double risk = g_tracks[idx].initRiskPrice;
      if(risk <= 0.0)
        {
         g_tracks[idx].partialDone = true; // pas de R defini : on ne tente pas
         continue;
        }

      long   type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double tp   = PositionGetDouble(POSITION_TP);
      double vol  = PositionGetDouble(POSITION_VOLUME);

      double profitDist;
      double refPrice;
      bool   isBuy = (type == POSITION_TYPE_BUY);
      if(isBuy)
        {
         refPrice   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         profitDist = refPrice - open;
        }
      else
        {
         refPrice   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         profitDist = open - refPrice;
        }

      //--- Seuil +X R atteint ?
      if(profitDist < risk * InpPartialTriggerRR)
         continue;

      //--- Volume a clore (doit laisser au moins le lot min en place)
      double closeVol = NormalizeLot(vol * InpPartialClosePct / 100.0);
      if(closeVol < minLot || (vol - closeVol) < minLot)
        {
         g_tracks[idx].partialDone = true;
         Log(StringFormat("Partiel impossible #%I64u : volume %.2f trop petit (min %.2f). SL au BE seulement.",
                          ticket, vol, minLot));
         //--- A defaut de partiel, on verrouille au moins le BE
         double lockSL = NormalizePrice(isBuy ? open + PipToPrice(InpBELockPips)
                                              : open - PipToPrice(InpBELockPips));
         ModifyPositionSL(ticket, lockSL, tp, refPrice, isBuy);
         continue;
        }

      if(trade.PositionClosePartial(ticket, closeVol))
        {
         g_tracks[idx].partialDone = true;
         Log(StringFormat("PARTIEL #%I64u : %.2f lots clos a +%.1fR, SL -> BE. total_jour=%.2f",
                          ticket, closeVol, InpPartialTriggerRR, CalcDailyPL()));
         //--- SL au break-even + verrou sur le reste
         double lockSL = NormalizePrice(isBuy ? open + PipToPrice(InpBELockPips)
                                              : open - PipToPrice(InpBELockPips));
         ModifyPositionSL(ticket, lockSL, tp, refPrice, isBuy);
        }
      else
         Log(StringFormat("Echec partiel #%I64u (ret=%d %s)",
                          ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription()));
     }
  }

//==================================================================//
//                 GESTION DES POSITIONS (BE / TRAIL)               //
//==================================================================//

//+------------------------------------------------------------------+
//| Passe le SL au break-even + verrou quand +BETrigger atteint      |
//+------------------------------------------------------------------+
void ManageBreakEven()
  {
   double trig = PipToPrice(g_BETriggerPips);
   double lock = PipToPrice(InpBELockPips);

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(!SelectMyPosition(ticket))
         continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);

      if(type == POSITION_TYPE_BUY)
        {
         double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double newSL = NormalizePrice(open + lock);
         if(bid - open >= trig && (sl < newSL - _Point/2.0 || sl == 0.0))
           {
            if(ModifyPositionSL(ticket, newSL, tp, bid, true))
               Log(StringFormat("BE BUY #%I64u : SL -> %.5f", ticket, newSL));
           }
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double newSL = NormalizePrice(open - lock);
         if(open - ask >= trig && (sl > newSL + _Point/2.0 || sl == 0.0))
           {
            if(ModifyPositionSL(ticket, newSL, tp, ask, false))
               Log(StringFormat("BE SELL #%I64u : SL -> %.5f", ticket, newSL));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Trailing : distance ATR (recommande) ou pips. Ne recule jamais.  |
//+------------------------------------------------------------------+
void ManageTrailing()
  {
   double trailDist = PipToPrice(g_TrailingPips);
   if(InpUseATRTrailing)
     {
      double atr = GetATR();
      if(atr > 0.0)
         trailDist = atr * InpTrailATRMult;
     }
   double trig = PipToPrice(g_BETriggerPips);

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(!SelectMyPosition(ticket))
         continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);

      if(type == POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid - open < trig)
            continue;
         double newSL = NormalizePrice(bid - trailDist);
         if(newSL > sl + _Point/2.0)
           {
            if(ModifyPositionSL(ticket, newSL, tp, bid, true))
               Log(StringFormat("TRAIL BUY #%I64u : SL -> %.5f", ticket, newSL));
           }
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(open - ask < trig)
            continue;
         double newSL = NormalizePrice(ask + trailDist);
         if(newSL < sl - _Point/2.0 || sl == 0.0)
           {
            if(ModifyPositionSL(ticket, newSL, tp, ask, false))
               Log(StringFormat("TRAIL SELL #%I64u : SL -> %.5f", ticket, newSL));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Modifie le SL d'une position en respectant le stops level        |
//+------------------------------------------------------------------+
bool ModifyPositionSL(ulong ticket, double desiredSL, double tp, double refPrice, bool isBuy)
  {
   double adjSL = AdjustStopDistance(desiredSL, refPrice, isBuy);
   adjSL = NormalizePrice(adjSL);
   if(!trade.PositionModify(ticket, adjSL, tp))
     {
      Log(StringFormat("Echec PositionModify #%I64u SL=%.5f (ret=%d %s)",
                       ticket, adjSL, trade.ResultRetcode(), trade.ResultRetcodeDescription()));
      return(false);
     }
   return(true);
  }

//==================================================================//
//                       ENTREE / NOUVELLE BOUGIE                   //
//==================================================================//

//+------------------------------------------------------------------+
//| Detecte une nouvelle bougie sur le timeframe de reference        |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime t = iTime(_Symbol, InpRefTimeframe, 0);
   if(t != g_lastBarTime)
     {
      g_lastBarTime = t;
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Traitement a la cloture d'une nouvelle bougie de reference       |
//+------------------------------------------------------------------+
void OnNewBar()
  {
   //--- Nettoyage du suivi des positions disparues
   CleanupTracks();

   //--- Sortie anticipee AVANT tout (meme si ADX en range)
   CheckOppositeBreakExit();

   //--- Filtre ADX
   if(InpUseADXFilter && !PassADXFilter())
     {
      RemovePendingOrders();
      Log("Filtre ADX : marche en range, pas d'ordres (pending retires).");
      return;
     }

   //--- Limite de positions
   if(CountEAPositions() >= InpMaxPositions)
     {
      Log(StringFormat("Limite de positions atteinte (%d) : pas de nouveaux pending.", InpMaxPositions));
      RemovePendingOrders();
      return;
     }

   //--- Extremes de la bougie close (shift 1)
   double high = iHigh(_Symbol, InpRefTimeframe, 1);
   double low  = iLow(_Symbol, InpRefTimeframe, 1);
   if(high <= 0.0 || low <= 0.0)
      return;

   RemovePendingOrders();
   PlacePendingOrders(high, low);
  }

//+------------------------------------------------------------------+
//| Filtre ADX : true si ADX > seuil sur la bougie close             |
//+------------------------------------------------------------------+
bool PassADXFilter()
  {
   if(g_adxHandle == INVALID_HANDLE)
      return(true);

   double buf[];
   if(CopyBuffer(g_adxHandle, 0, 1, 1, buf) < 1)
     {
      Log("ADX : donnees indisponibles, ordres non poses par prudence.");
      return(false);
     }
   return(buf[0] > g_ADXThreshold);
  }

//+------------------------------------------------------------------+
//| ATR de la bougie close (0.0 si indisponible)                     |
//+------------------------------------------------------------------+
double GetATR()
  {
   if(g_atrHandle == INVALID_HANDLE)
      return(0.0);
   double buf[];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) < 1)
      return(0.0);
   return(buf[0]);
  }

//+------------------------------------------------------------------+
//| Distance du SL initial selon le mode choisi, plafonnee.          |
//| entryPrice : prix d'entree prevu ; candleHigh/Low : bougie ref.  |
//+------------------------------------------------------------------+
double ComputeSLDistance(double entryPrice, bool isBuy, double candleHigh, double candleLow)
  {
   double dist = 0.0;

   switch(InpSLMode)
     {
      case SL_FIXED_PIPS:
         dist = PipToPrice(InpInitialSLPips);
         break;

      case SL_ATR:
        {
         double atr = GetATR();
         if(atr > 0.0)
            dist = atr * InpATRSLMult;
         else // repli : extreme de bougie si ATR indisponible
            dist = (isBuy ? entryPrice - candleLow : candleHigh - entryPrice);
         break;
        }

      default: // SL_CANDLE
         dist = (isBuy ? entryPrice - candleLow : candleHigh - entryPrice);
         break;
     }

   //--- Plafond de SL : limite la taille de la pire perte
   if(InpMaxSLPips > 0.0)
     {
      double cap = PipToPrice(InpMaxSLPips);
      if(dist > cap)
        {
         Log(StringFormat("SL plafonne : %.5f -> %.5f (InpMaxSLPips=%.1f).", dist, cap, InpMaxSLPips));
         dist = cap;
        }
     }

   if(dist <= 0.0)
      dist = PipToPrice(InpInitialSLPips); // dernier repli de securite

   return(dist);
  }

//+------------------------------------------------------------------+
//| Lot par % de risque : meme montant risque quel que soit le SL    |
//+------------------------------------------------------------------+
double CalcLotByRisk(double slDistance)
  {
   if(InpRiskPercent <= 0.0)
      return(NormalizeLot(InpLotSize));

   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;

   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0.0 || tickSize <= 0.0 || slDistance <= 0.0)
      return(NormalizeLot(InpLotSize));

   double lossPerLot = slDistance / tickSize * tickVal; // perte pour 1 lot si SL touche
   if(lossPerLot <= 0.0)
      return(NormalizeLot(InpLotSize));

   return(NormalizeLot(riskMoney / lossPerLot));
  }

//+------------------------------------------------------------------+
//| Pose un Buy Stop et un Sell Stop sur les extremes de la bougie   |
//+------------------------------------------------------------------+
void PlacePendingOrders(double high, double low)
  {
   double buffer = PipToPrice(InpBufferPips);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //------------------- BUY STOP --------------------
   double buyPrice = NormalizePrice(high + buffer);
   buyPrice = AdjustPendingPrice(buyPrice, ask, true);

   double buyDist = ComputeSLDistance(buyPrice, true, high, low);
   double buySL   = AdjustStopDistance(NormalizePrice(buyPrice - buyDist), buyPrice, true);
   buySL = NormalizePrice(buySL);

   double buyLot = CalcLotByRisk(buyPrice - buySL);

   if(buyLot > 0.0 && trade.BuyStop(buyLot, buyPrice, _Symbol, buySL, 0.0, ORDER_TIME_GTC, 0, "BREAKOUT_BUY"))
      Log(StringFormat("Buy Stop @ %.5f SL=%.5f lot=%.2f (risque %.5f)", buyPrice, buySL, buyLot, buyPrice - buySL));
   else
      Log(StringFormat("Echec Buy Stop (ret=%d %s)", trade.ResultRetcode(), trade.ResultRetcodeDescription()));

   //------------------- SELL STOP -------------------
   double sellPrice = NormalizePrice(low - buffer);
   sellPrice = AdjustPendingPrice(sellPrice, bid, false);

   double sellDist = ComputeSLDistance(sellPrice, false, high, low);
   double sellSL   = AdjustStopDistance(NormalizePrice(sellPrice + sellDist), sellPrice, false);
   sellSL = NormalizePrice(sellSL);

   double sellLot = CalcLotByRisk(sellSL - sellPrice);

   if(sellLot > 0.0 && trade.SellStop(sellLot, sellPrice, _Symbol, sellSL, 0.0, ORDER_TIME_GTC, 0, "BREAKOUT_SELL"))
      Log(StringFormat("Sell Stop @ %.5f SL=%.5f lot=%.2f (risque %.5f)", sellPrice, sellSL, sellLot, sellSL - sellPrice));
   else
      Log(StringFormat("Echec Sell Stop (ret=%d %s)", trade.ResultRetcode(), trade.ResultRetcodeDescription()));
  }

//+------------------------------------------------------------------+
//| Supprime tous les ordres en attente de l'EA                      |
//+------------------------------------------------------------------+
void RemovePendingOrders()
  {
   int total = OrdersTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;

      long otype = OrderGetInteger(ORDER_TYPE);
      if(otype == ORDER_TYPE_BUY_STOP || otype == ORDER_TYPE_SELL_STOP ||
         otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_SELL_LIMIT)
        {
         if(!trade.OrderDelete(ticket))
            Log(StringFormat("Echec suppression pending #%I64u (ret=%d)", ticket, trade.ResultRetcode()));
        }
     }
  }

//+------------------------------------------------------------------+
//| Si une position est ouverte, supprime le pending oppose restant  |
//+------------------------------------------------------------------+
void ManagePendingPair()
  {
   bool hasBuyPos  = false;
   bool hasSellPos = false;

   int totalP = PositionsTotal();
   for(int i = 0; i < totalP; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(!SelectMyPosition(ticket))
         continue;
      long t = PositionGetInteger(POSITION_TYPE);
      if(t == POSITION_TYPE_BUY)  hasBuyPos  = true;
      if(t == POSITION_TYPE_SELL) hasSellPos = true;
     }

   if(!hasBuyPos && !hasSellPos)
      return;

   int totalO = OrdersTotal();
   for(int i = totalO - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;

      long otype = OrderGetInteger(ORDER_TYPE);
      if(hasBuyPos && otype == ORDER_TYPE_SELL_STOP)
        {
         if(trade.OrderDelete(ticket))
            Log(StringFormat("Pending oppose retire (Sell Stop #%I64u).", ticket));
        }
      else if(hasSellPos && otype == ORDER_TYPE_BUY_STOP)
        {
         if(trade.OrderDelete(ticket))
            Log(StringFormat("Pending oppose retire (Buy Stop #%I64u).", ticket));
        }
     }
  }

//==================================================================//
//                         CLOTURE / REVERSE                        //
//==================================================================//

//+------------------------------------------------------------------+
//| Ferme toutes les positions de l'EA                               |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
  {
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!SelectMyPosition(ticket))
         continue;
      if(!trade.PositionClose(ticket))
         Log(StringFormat("Echec cloture #%I64u (ret=%d %s)",
                          ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription()));
      else
         Log(StringFormat("Cloture #%I64u (%s).", ticket, reason));
     }
  }

//+------------------------------------------------------------------+
//| Reverse : ouvre l'oppose a taille EGALE (jamais superieure)      |
//+------------------------------------------------------------------+
void DoReverse(bool positionWasBuy, double volume)
  {
   if(g_tradingHaltedToday)                   return;
   if(!IsTradingSession())                    return;
   if(CountEAPositions() >= InpMaxPositions)  return;

   double lot = NormalizeLot(volume);
   if(lot <= 0.0)
      return;

   double high = iHigh(_Symbol, InpRefTimeframe, 1);
   double low  = iLow(_Symbol, InpRefTimeframe, 1);

   if(positionWasBuy)
     {
      //--- BUY ferme => on ouvre un SELL
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double dist = ComputeSLDistance(bid, false, high, low);
      double sl   = NormalizePrice(AdjustStopDistance(NormalizePrice(bid + dist), bid, false));
      if(trade.Sell(lot, _Symbol, 0.0, sl, 0.0, "REVERSE_SELL"))
         Log(StringFormat("REVERSE : SELL lot=%.2f SL=%.5f", lot, sl));
      else
         Log(StringFormat("REVERSE SELL echec (ret=%d %s)", trade.ResultRetcode(), trade.ResultRetcodeDescription()));
     }
   else
     {
      //--- SELL ferme => on ouvre un BUY
      double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double dist = ComputeSLDistance(ask, true, high, low);
      double sl   = NormalizePrice(AdjustStopDistance(NormalizePrice(ask - dist), ask, true));
      if(trade.Buy(lot, _Symbol, 0.0, sl, 0.0, "REVERSE_BUY"))
         Log(StringFormat("REVERSE : BUY lot=%.2f SL=%.5f", lot, sl));
      else
         Log(StringFormat("REVERSE BUY echec (ret=%d %s)", trade.ResultRetcode(), trade.ResultRetcodeDescription()));
     }
  }

//==================================================================//
//                      ON TRADE TRANSACTION                        //
//==================================================================//
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong dealTicket = trans.deal;
   if(dealTicket == 0 || !HistoryDealSelect(dealTicket))
      return;

   if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagicNumber)
      return;
   if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol)
      return;

   long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

   //--- A) Ouverture : enregistrer le suivi (R initial + niveau oppose)
   //       et supprimer le pending oppose restant.
   if(entry == DEAL_ENTRY_IN)
     {
      ulong posTicket = trans.position;
      if(posTicket > 0 && PositionSelectByTicket(posTicket))
        {
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl   = PositionGetDouble(POSITION_SL);
         bool   isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

         double risk = (sl > 0.0 ? MathAbs(open - sl) : 0.0);
         double buffer = PipToPrice(InpBufferPips);
         double opp  = (isBuy ? iLow(_Symbol, InpRefTimeframe, 1) - buffer
                              : iHigh(_Symbol, InpRefTimeframe, 1) + buffer);

         AddTrack(posTicket, risk, opp);
         Log(StringFormat("ENTREE %s #%I64u @ %.5f | R=%.5f | niveau oppose=%.5f | total_jour=%.2f",
                          (isBuy ? "BUY" : "SELL"), posTicket, open, risk, opp, CalcDailyPL()));
        }
      ManagePendingPair();
      return;
     }

   //--- B) Sortie : si fermeture sur SL et reverse actif -> reverse
   if(entry == DEAL_ENTRY_OUT)
     {
      long   reason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
      long   dtype  = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      double vol    = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);

      bool positionWasBuy = (dtype == DEAL_TYPE_SELL);

      if(g_ReverseOn && reason == DEAL_REASON_SL)
        {
         Log(StringFormat("Fermeture sur SL (%s) -> REVERSE.", (positionWasBuy ? "BUY" : "SELL")));
         DoReverse(positionWasBuy, vol);
        }
     }
  }

//==================================================================//
//                SUIVI DES POSITIONS (tracking V2)                 //
//==================================================================//

//+------------------------------------------------------------------+
//| Ajoute (ou remplace) une entree de suivi pour un ticket          |
//+------------------------------------------------------------------+
void AddTrack(ulong ticket, double risk, double oppLevel)
  {
   int idx = GetTrackIndex(ticket);
   if(idx < 0)
     {
      idx = ArraySize(g_tracks);
      ArrayResize(g_tracks, idx + 1);
     }
   g_tracks[idx].ticket        = ticket;
   g_tracks[idx].initRiskPrice = risk;
   g_tracks[idx].oppLevel      = oppLevel;
   g_tracks[idx].partialDone   = false;
  }

//+------------------------------------------------------------------+
//| Index du suivi pour un ticket (-1 si absent)                     |
//+------------------------------------------------------------------+
int GetTrackIndex(ulong ticket)
  {
   for(int i = 0; i < ArraySize(g_tracks); i++)
      if(g_tracks[i].ticket == ticket)
         return(i);
   return(-1);
  }

//+------------------------------------------------------------------+
//| Retire du suivi les positions qui n'existent plus                |
//+------------------------------------------------------------------+
void CleanupTracks()
  {
   for(int i = ArraySize(g_tracks) - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(g_tracks[i].ticket))
        {
         //--- decalage du tableau
         for(int j = i; j < ArraySize(g_tracks) - 1; j++)
            g_tracks[j] = g_tracks[j + 1];
         ArrayResize(g_tracks, ArraySize(g_tracks) - 1);
        }
     }
  }

//==================================================================//
//                  FILTRES SESSION / UTILITAIRES                   //
//==================================================================//

//+------------------------------------------------------------------+
//| Vrai si l'heure serveur courante est dans la session             |
//+------------------------------------------------------------------+
bool IsTradingSession()
  {
   MqlDateTime st;
   TimeToStruct(TimeCurrent(), st);
   int h = st.hour;

   if(InpSessionStartHour == InpSessionEndHour)
      return(true);

   if(InpSessionStartHour < InpSessionEndHour)
      return(h >= InpSessionStartHour && h < InpSessionEndHour);

   return(h >= InpSessionStartHour || h < InpSessionEndHour);
  }

//+------------------------------------------------------------------+
//| Selectionne une position si elle appartient a l'EA               |
//+------------------------------------------------------------------+
bool SelectMyPosition(ulong ticket)
  {
   if(ticket == 0)
      return(false);
   if(!PositionSelectByTicket(ticket))
      return(false);
   if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
      return(false);
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| Compte les positions de l'EA                                     |
//+------------------------------------------------------------------+
int CountEAPositions()
  {
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(SelectMyPosition(ticket))
         count++;
     }
   return(count);
  }

//==================================================================//
//              CONVERSION PIPS / POINTS / NORMALISATION            //
//==================================================================//

//+------------------------------------------------------------------+
//| Nombre de points par pip selon les digits du symbole             |
//| ATTENTION : sur XAUUSD 2 decimales, 1 pip EA = 0.01 USD.         |
//| Preferez les options ATR pour les distances sur l'or.            |
//+------------------------------------------------------------------+
double PointsPerPip()
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5)
      return(10.0);
   return(1.0);
  }

//+------------------------------------------------------------------+
//| Convertit une distance en pips vers une distance en prix         |
//+------------------------------------------------------------------+
double PipToPrice(double pips)
  {
   return(pips * g_pipSize);
  }

//+------------------------------------------------------------------+
//| Normalise un prix selon les digits du symbole                    |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return(NormalizeDouble(price, digits));
  }

//+------------------------------------------------------------------+
//| Normalise un volume selon min/max/step du symbole                |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(stepLot <= 0.0)
      stepLot = 0.01;

   double normalized = MathRound(lot / stepLot) * stepLot;
   if(normalized < minLot) normalized = minLot;
   if(normalized > maxLot) normalized = maxLot;

   int lotDigits = (int)MathRound(MathLog10(1.0 / stepLot));
   if(lotDigits < 0) lotDigits = 0;
   return(NormalizeDouble(normalized, lotDigits));
  }

//+------------------------------------------------------------------+
//| Distance minimale des stops (stops level + freeze level)         |
//+------------------------------------------------------------------+
double GetStopsLevelPrice()
  {
   long stopsLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   long lvl = MathMax(stopsLevel, freezeLevel);
   return((double)(lvl + 1) * _Point);
  }

//+------------------------------------------------------------------+
//| Ajuste un SL trop proche du prix de reference                    |
//+------------------------------------------------------------------+
double AdjustStopDistance(double sl, double refPrice, bool isBuy)
  {
   double minDist = GetStopsLevelPrice();

   if(isBuy)
     {
      double maxSL = refPrice - minDist;
      if(sl > maxSL)
        {
         Log(StringFormat("SL BUY trop proche (%.5f), ajuste a %.5f.", sl, maxSL));
         sl = maxSL;
        }
     }
   else
     {
      double minSL = refPrice + minDist;
      if(sl < minSL)
        {
         Log(StringFormat("SL SELL trop proche (%.5f), ajuste a %.5f.", sl, minSL));
         sl = minSL;
        }
     }
   return(sl);
  }

//+------------------------------------------------------------------+
//| Ajuste le prix d'un ordre stop trop proche du marche             |
//+------------------------------------------------------------------+
double AdjustPendingPrice(double price, double refPrice, bool isBuyStop)
  {
   double minDist = GetStopsLevelPrice();

   if(isBuyStop)
     {
      double minPrice = refPrice + minDist;
      if(price < minPrice)
        {
         Log(StringFormat("Buy Stop trop proche (%.5f), ajuste a %.5f.", price, minPrice));
         price = minPrice;
        }
     }
   else
     {
      double maxPrice = refPrice - minDist;
      if(price > maxPrice)
        {
         Log(StringFormat("Sell Stop trop proche (%.5f), ajuste a %.5f.", price, maxPrice));
         price = maxPrice;
        }
     }
   return(NormalizePrice(price));
  }

//+------------------------------------------------------------------+
//| Log conditionnel                                                 |
//+------------------------------------------------------------------+
void Log(string msg)
  {
   if(InpVerboseLog)
      Print(msg);
  }
//+------------------------------------------------------------------+
