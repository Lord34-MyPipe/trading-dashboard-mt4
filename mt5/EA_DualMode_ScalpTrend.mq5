//+------------------------------------------------------------------+
//|                                     EA_DualMode_ScalpTrend.mq5    |
//|                  Expert Advisor double mode pour MetaTrader 5     |
//|                                                                  |
//|  PHILOSOPHIE                                                      |
//|  ----------                                                      |
//|  L'edge reel de cette strategie ne vient PAS de la prediction    |
//|  de direction, mais de la STRUCTURE DE COUTS : le rebate IB      |
//|  (broker RoboForex Pro, spread seul, sans commission) neutralise |
//|  le spread. L'objectif n'est donc pas de gagner gros, mais de    |
//|  rester proche du break-even BRUT tout en limitant strictement   |
//|  le risque. Chaque sortie au break-even prix devient un leger    |
//|  gain NET grace au rebate.                                        |
//|                                                                  |
//|  -> Aucune martingale, aucun doublement de position, aucun hedge |
//|     a taille superieure. Le reverse eventuel se fait UNIQUEMENT   |
//|     a taille egale.                                               |
//|                                                                  |
//|  DEUX MODES (parametre InpMode)                                  |
//|  ------------------------------                                  |
//|  MODE A - "Scalp Rebate" : sorties rapides et frequentes au BE   |
//|     prix (BETrigger/Trailing courts, reverse ON, ADX bas ~20).   |
//|     Beaucoup de rotations ; le rebate transforme chaque sortie   |
//|     BE en leger gain net.                                         |
//|                                                                  |
//|  MODE B - "Trend Follow" : laisser courir les vraies tendances   |
//|     (BETrigger/Trailing larges, reverse OFF, ADX haut ~25).      |
//|     Moins de trades ; le rebate est un bonus.                    |
//|                                                                  |
//|  Le mode sert de PRESELECTION : si un parametre specifique au    |
//|  mode est laisse a sa valeur sentinelle (-1), le defaut du mode  |
//|  s'applique ; sinon la valeur saisie par l'utilisateur prime.    |
//|                                                                  |
//|  *****************************************************************|
//|  *  AVERTISSEMENT : A TESTER EXCLUSIVEMENT SUR COMPTE DEMO       *|
//|  *  AVANT TOUT USAGE REEL. Le passe ne prejuge pas du futur.    *|
//|  *  Aucune garantie de profit. Utilisation a vos risques.       *|
//|  *****************************************************************|
//+------------------------------------------------------------------+
#property copyright "EA DualMode ScalpTrend"
#property version   "1.00"
#property strict
#property description "EA double mode (Scalp Rebate / Trend Follow) - breakout sur extremes de bougie. DEMO uniquement."

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

// Etat tri-etat pour le reverse (un bool ne peut pas avoir de sentinelle)
enum ENUM_REVERSE_STATE
  {
   REVERSE_DEFAULT_MODE = 0,  // Defaut du mode (A=ON, B=OFF)
   REVERSE_FORCE_ON     = 1,  // Forcer ON
   REVERSE_FORCE_OFF    = 2   // Forcer OFF
  };

//==================================================================//
//                            INPUTS                                //
//==================================================================//

input group "=== Mode & Timeframe ==="
input ENUM_EA_MODE     InpMode            = MODE_B_TREND_FOLLOW; // Mode de strategie
input ENUM_TIMEFRAMES  InpRefTimeframe    = PERIOD_M15;          // Timeframe de reference (bougie de breakout)

input group "=== Volume & Entree ==="
input double           InpLotSize         = 0.10;   // Taille de lot
input double           InpBufferPips      = 1.0;    // Buffer au-dela de l'extreme (pips)
input int              InpMaxPositions    = 5;      // Nb max de positions simultanees de l'EA

input group "=== Filtre de tendance (ADX) ==="
input bool             InpUseADXFilter    = true;   // Activer le filtre ADX
input int              InpADXPeriod       = 14;     // Periode ADX
input double           InpADXThreshold    = -1.0;   // Seuil ADX (-1 = defaut du mode : A=20 / B=25)

input group "=== Stop loss initial ==="
input bool             InpUseCandleSL     = true;   // true = SL sur extreme de bougie ; false = SL fixe en pips
input double           InpInitialSLPips   = 15.0;   // SL fixe (pips) si InpUseCandleSL=false

input group "=== Break-even & Trailing (sentinelle -1 = defaut du mode) ==="
input double           InpBETriggerPips   = -1.0;   // Profit declenchant le BE (pips) (-1 = A:3 / B:8)
input double           InpBELockPips      = 1.0;    // Verrou pose au-dessus de l'entree au BE (pips)
input double           InpTrailingPips    = -1.0;   // Distance de trailing (pips) (-1 = A:3 / B:12)

input group "=== Reverse (Stop-and-Reverse) ==="
input ENUM_REVERSE_STATE InpReverseState  = REVERSE_DEFAULT_MODE; // Reverse a la fermeture sur stop

input group "=== Session horaire (heure serveur) ==="
input int              InpSessionStartHour   = 8;     // Heure de debut de session
input int              InpSessionEndHour     = 21;    // Heure de fin de session
input bool             InpCloseAtSessionEnd  = false; // Forcer la cloture des positions a la fin de session

input group "=== Gestion journaliere collective (devise du compte) ==="
input double           InpDailyTargetMoney   = 0.0;   // Cible jour (0 = BE strict ; >0 = leger profit)
input double           InpDailyMaxLossMoney  = 200.0; // Plafond catastrophe jour (valeur positive)

input group "=== Divers ==="
input long             InpMagicNumber     = 20260601; // Magic number (identifie les ordres de l'EA)
input bool             InpVerboseLog      = true;      // Logs detailles

//==================================================================//
//                       VARIABLES GLOBALES                         //
//==================================================================//

CTrade   trade;                 // Objet de trading
int      g_adxHandle = INVALID_HANDLE; // Handle indicateur ADX

datetime g_lastBarTime = 0;     // Open-time de la derniere bougie traitee (detection nouvelle bougie)
datetime g_currentDay  = 0;     // Jour courant (detection nouveau jour, heure serveur)

double   g_realizedPLToday   = 0.0;   // P&L realise du jour (recalcule chaque tick)
bool     g_tradingHaltedToday = false;// Halte totale du trading jusqu'au lendemain

// Parametres "effectifs" resolus selon le mode et les sentinelles
double   g_BETriggerPips = 0.0;
double   g_TrailingPips  = 0.0;
double   g_ADXThreshold  = 0.0;
bool     g_ReverseOn     = false;

// Cache conversion pips <-> prix
double   g_pipSize       = 0.0;   // Taille d'un pip en prix
double   g_pointsPerPip  = 1.0;   // Nb de points par pip

//==================================================================//
//                         INITIALISATION                           //
//==================================================================//
int OnInit()
  {
   //--- Configuration de l'objet CTrade
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(20);

   //--- Cache pip / point selon le symbole (gere 3 et 5 digits)
   g_pointsPerPip = PointsPerPip();
   g_pipSize      = _Point * g_pointsPerPip;

   //--- Resolution des parametres effectifs (mode + sentinelles)
   ResolveModeDefaults();

   //--- Creation du handle ADX sur le timeframe de reference
   if(InpUseADXFilter)
     {
      g_adxHandle = iADX(_Symbol, InpRefTimeframe, InpADXPeriod);
      if(g_adxHandle == INVALID_HANDLE)
        {
         Print("ERREUR : impossible de creer le handle ADX.");
         return(INIT_FAILED);
        }
     }

   //--- Validation des inputs de base
   if(InpSessionStartHour < 0 || InpSessionStartHour > 23 ||
      InpSessionEndHour   < 0 || InpSessionEndHour   > 23)
     {
      Print("ERREUR : heures de session invalides (0-23).");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(NormalizeLot(InpLotSize) <= 0.0)
     {
      Print("ERREUR : InpLotSize invalide pour ce symbole.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   //--- Initialisation des compteurs journaliers
   g_currentDay  = DayStart(TimeCurrent());
   g_lastBarTime = iTime(_Symbol, InpRefTimeframe, 0);
   UpdateRealizedPL();
   g_tradingHaltedToday = false;

   Log(StringFormat("OnInit OK | Mode=%s | TF=%s | BETrig=%.1f Trail=%.1f ADXseuil=%.1f Reverse=%s | pip=%.5f",
                    (InpMode==MODE_A_SCALP_REBATE ? "A-Scalp" : "B-Trend"),
                    EnumToString(InpRefTimeframe),
                    g_BETriggerPips, g_TrailingPips, g_ADXThreshold,
                    (g_ReverseOn ? "ON" : "OFF"), g_pipSize));

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Resolution des defauts de mode (gestion des sentinelles -1)      |
//+------------------------------------------------------------------+
void ResolveModeDefaults()
  {
   //--- Defauts par mode
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

   //--- Application : sentinelle (-1) => defaut du mode, sinon valeur saisie
   g_BETriggerPips = (InpBETriggerPips < 0.0 ? defBETrig : InpBETriggerPips);
   g_TrailingPips  = (InpTrailingPips  < 0.0 ? defTrail  : InpTrailingPips);
   g_ADXThreshold  = (InpADXThreshold  < 0.0 ? defADX    : InpADXThreshold);

   switch(InpReverseState)
     {
      case REVERSE_FORCE_ON:  g_ReverseOn = true;  break;
      case REVERSE_FORCE_OFF: g_ReverseOn = false; break;
      default:                g_ReverseOn = defReverse; break; // REVERSE_DEFAULT_MODE
     }
  }

//==================================================================//
//                          DESINITIALISATION                       //
//==================================================================//
void OnDeinit(const int reason)
  {
   if(g_adxHandle != INVALID_HANDLE)
      IndicatorRelease(g_adxHandle);
   Log(StringFormat("OnDeinit | raison=%d | realise_jour=%.2f", reason, g_realizedPLToday));
  }

//==================================================================//
//                            ON TICK                               //
//==================================================================//
void OnTick()
  {
   //--- 1) Reinitialisation quotidienne si nouveau jour serveur
   CheckNewDay();

   //--- 2) Mise a jour du P&L realise du jour
   UpdateRealizedPL();

   //--- 3) Calcul du total jour (realise + flottant) et controle des seuils
   double totalToday = CalcDailyPL();
   if(CheckDailyTargets(totalToday))
      return; // tout a ete ferme et le trading est en halte : on s'arrete la

   //--- 4) Si le trading est en halte, ne rien faire d'autre
   if(g_tradingHaltedToday)
      return;

   //--- 5) Gestion des positions ouvertes (BE puis trailing)
   ManageBreakEven();
   ManageTrailing();

   //--- 6) Si un stop est deja en position, supprimer l'eventuel ordre oppose restant
   ManagePendingPair();

   //--- 7) Gestion de la session horaire
   bool inSession = IsTradingSession();
   if(!inSession)
     {
      //--- Hors session : on retire les pending, sans fermer de force (sauf option)
      RemovePendingOrders();
      if(InpCloseAtSessionEnd)
         CloseAllPositions("Fin de session");
      return;
     }

   //--- 8) Detection d'une nouvelle bougie de reference => (re)pose des ordres
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
//| Renvoie le timestamp du debut du jour (00:00 serveur)            |
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

      // On somme profit + swap + commission de tous les deals de l'EA du jour
      realized += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      realized += HistoryDealGetDouble(ticket, DEAL_SWAP);
      realized += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
     }
   g_realizedPLToday = realized;
  }

//+------------------------------------------------------------------+
//| total_jour = realise du jour + flottant de toutes les positions  |
//+------------------------------------------------------------------+
double CalcDailyPL()
  {
   double floating = 0.0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      floating += PositionGetDouble(POSITION_PROFIT);
      floating += PositionGetDouble(POSITION_SWAP);
     }
   return(g_realizedPLToday + floating);
  }

//+------------------------------------------------------------------+
//| Verifie cible jour atteinte ou plafond catastrophe touche        |
//| Renvoie true si une action collective de cloture a ete declenchee|
//+------------------------------------------------------------------+
bool CheckDailyTargets(double totalToday)
  {
   if(g_tradingHaltedToday)
      return(false); // deja en halte, deja traite

   //--- Plafond catastrophe (non negociable, prioritaire)
   if(InpDailyMaxLossMoney > 0.0 && totalToday <= -InpDailyMaxLossMoney)
     {
      Log(StringFormat("PLAFOND CATASTROPHE atteint : total_jour=%.2f <= -%.2f -> cloture totale + halte.",
                       totalToday, InpDailyMaxLossMoney));
      CloseAllPositions("Plafond catastrophe");
      RemovePendingOrders();
      g_tradingHaltedToday = true;
      return(true);
     }

   //--- Cible jour (BE strict si 0, leger profit si >0)
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
//| Y a-t-il eu une activite (position ouverte ou deal) aujourd'hui ?|
//| Evite de declencher la cible "BE strict" (0) des l'ouverture     |
//| alors qu'aucun trade n'a encore eu lieu.                         |
//+------------------------------------------------------------------+
bool HasAnyActivityToday()
  {
   if(g_realizedPLToday != 0.0)
      return(true);
   return(CountEAPositions() > 0);
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

      long   type   = PositionGetInteger(POSITION_TYPE);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);

      if(type == POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double newSL = NormalizePrice(open + lock);
         // Declenchement BE et SL pas encore au verrou
         if(bid - open >= trig && (sl < newSL - _Point/2.0 || sl == 0.0))
           {
            if(ModifyPositionSL(ticket, newSL, tp, bid, true))
               Log(StringFormat("BE BUY #%I64u : SL -> %.5f (entree %.5f, verrou %.1f pip)",
                                ticket, newSL, open, InpBELockPips));
           }
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double newSL = NormalizePrice(open - lock);
         if(open - ask >= trig && (sl > newSL + _Point/2.0 || sl == 0.0))
           {
            if(ModifyPositionSL(ticket, newSL, tp, ask, false))
               Log(StringFormat("BE SELL #%I64u : SL -> %.5f (entree %.5f, verrou %.1f pip)",
                                ticket, newSL, open, InpBELockPips));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Trailing classique au-dela du BE : le SL ne recule jamais        |
//+------------------------------------------------------------------+
void ManageTrailing()
  {
   double trailDist = PipToPrice(g_TrailingPips);
   double trig      = PipToPrice(g_BETriggerPips);

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
         if(bid - open < trig) // trailing actif seulement au-dela du seuil BE
            continue;
         double newSL = NormalizePrice(bid - trailDist);
         if(newSL > sl + _Point/2.0) // ne recule jamais
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
         if(newSL < sl - _Point/2.0 || sl == 0.0) // ne recule jamais (vers le haut)
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
   //--- Filtre ADX : si range, on retire les pending et on ne pose rien
   if(InpUseADXFilter && !PassADXFilter())
     {
      RemovePendingOrders();
      Log("Filtre ADX : marche en range, pas d'ordres (pending retires).");
      return;
     }

   //--- Limite de positions simultanees
   if(CountEAPositions() >= InpMaxPositions)
     {
      Log(StringFormat("Limite de positions atteinte (%d) : pas de nouveaux pending.", InpMaxPositions));
      RemovePendingOrders();
      return;
     }

   //--- Extremes de la bougie qui vient de se clore (shift 1)
   double high = iHigh(_Symbol, InpRefTimeframe, 1);
   double low  = iLow(_Symbol, InpRefTimeframe, 1);
   if(high <= 0.0 || low <= 0.0)
      return;

   //--- On remplace les anciens pending par de nouveaux sur la nouvelle bougie
   RemovePendingOrders();
   PlacePendingOrders(high, low);
  }

//+------------------------------------------------------------------+
//| Filtre ADX : true si ADX > seuil sur la bougie close (shift 1)   |
//+------------------------------------------------------------------+
bool PassADXFilter()
  {
   if(g_adxHandle == INVALID_HANDLE)
      return(true);

   double buf[];
   if(CopyBuffer(g_adxHandle, 0, 1, 1, buf) < 1) // buffer 0 = ligne ADX principale
     {
      Log("ADX : donnees indisponibles, ordres non poses par prudence.");
      return(false);
     }
   double adx = buf[0];
   return(adx > g_ADXThreshold);
  }

//+------------------------------------------------------------------+
//| Pose un Buy Stop et un Sell Stop sur les extremes de la bougie   |
//+------------------------------------------------------------------+
void PlacePendingOrders(double high, double low)
  {
   double lot    = NormalizeLot(InpLotSize);
   double buffer = PipToPrice(InpBufferPips);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //------------------- BUY STOP --------------------
   double buyPrice = NormalizePrice(high + buffer);
   // Le prix d'un Buy Stop doit etre suffisamment au-dessus de l'Ask
   buyPrice = AdjustPendingPrice(buyPrice, ask, true);

   double buySL;
   if(InpUseCandleSL)
      buySL = low;                                  // SL au plus bas de la bougie
   else
      buySL = buyPrice - PipToPrice(InpInitialSLPips);
   buySL = AdjustStopDistance(NormalizePrice(buySL), buyPrice, true);
   buySL = NormalizePrice(buySL);

   if(trade.BuyStop(lot, buyPrice, _Symbol, buySL, 0.0, ORDER_TIME_GTC, 0, "BREAKOUT_BUY"))
      Log(StringFormat("Buy Stop pose @ %.5f SL=%.5f lot=%.2f", buyPrice, buySL, lot));
   else
      Log(StringFormat("Echec Buy Stop (ret=%d %s)", trade.ResultRetcode(), trade.ResultRetcodeDescription()));

   //------------------- SELL STOP -------------------
   double sellPrice = NormalizePrice(low - buffer);
   // Le prix d'un Sell Stop doit etre suffisamment en dessous du Bid
   sellPrice = AdjustPendingPrice(sellPrice, bid, false);

   double sellSL;
   if(InpUseCandleSL)
      sellSL = high;                                // SL au plus haut de la bougie
   else
      sellSL = sellPrice + PipToPrice(InpInitialSLPips);
   sellSL = AdjustStopDistance(NormalizePrice(sellSL), sellPrice, false);
   sellSL = NormalizePrice(sellSL);

   if(trade.SellStop(lot, sellPrice, _Symbol, sellSL, 0.0, ORDER_TIME_GTC, 0, "BREAKOUT_SELL"))
      Log(StringFormat("Sell Stop pose @ %.5f SL=%.5f lot=%.2f", sellPrice, sellSL, lot));
   else
      Log(StringFormat("Echec Sell Stop (ret=%d %s)", trade.ResultRetcode(), trade.ResultRetcodeDescription()));
  }

//+------------------------------------------------------------------+
//| Supprime tous les ordres en attente de l'EA (filtre magic)       |
//+------------------------------------------------------------------+
void RemovePendingOrders()
  {
   int total = OrdersTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
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
//| (filet de securite en plus de OnTradeTransaction)                |
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

   //--- Si un buy est ouvert, on retire les sell stop ; et inversement
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
            Log(StringFormat("Pending oppose retire (Sell Stop #%I64u, un Buy est ouvert).", ticket));
        }
      else if(hasSellPos && otype == ORDER_TYPE_BUY_STOP)
        {
         if(trade.OrderDelete(ticket))
            Log(StringFormat("Pending oppose retire (Buy Stop #%I64u, un Sell est ouvert).", ticket));
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
//| Ouvre une position opposee de meme taille au marche (reverse)    |
//| positionWasBuy = sens de la position qui vient d'etre fermee      |
//+------------------------------------------------------------------+
void DoReverse(bool positionWasBuy, double volume)
  {
   //--- Garde-fous : pas de reverse si halte, hors session, ou limite atteinte
   if(g_tradingHaltedToday)            return;
   if(!IsTradingSession())             return;
   if(CountEAPositions() >= InpMaxPositions) return;

   double lot = NormalizeLot(volume);
   if(lot <= 0.0)
      return;

   if(positionWasBuy)
     {
      //--- Position fermee = BUY  => on ouvre un SELL
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double slRaw = (InpUseCandleSL ? iHigh(_Symbol, InpRefTimeframe, 1)
                                     : bid + PipToPrice(InpInitialSLPips));
      double sl    = NormalizePrice(AdjustStopDistance(NormalizePrice(slRaw), bid, false));
      if(trade.Sell(lot, _Symbol, 0.0, sl, 0.0, "REVERSE_SELL"))
         Log(StringFormat("REVERSE : SELL ouvert lot=%.2f SL=%.5f", lot, sl));
      else
         Log(StringFormat("REVERSE SELL echec (ret=%d %s)", trade.ResultRetcode(), trade.ResultRetcodeDescription()));
     }
   else
     {
      //--- Position fermee = SELL => on ouvre un BUY
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double slRaw = (InpUseCandleSL ? iLow(_Symbol, InpRefTimeframe, 1)
                                     : ask - PipToPrice(InpInitialSLPips));
      double sl    = NormalizePrice(AdjustStopDistance(NormalizePrice(slRaw), ask, true));
      if(trade.Buy(lot, _Symbol, 0.0, sl, 0.0, "REVERSE_BUY"))
         Log(StringFormat("REVERSE : BUY ouvert lot=%.2f SL=%.5f", lot, sl));
      else
         Log(StringFormat("REVERSE BUY echec (ret=%d %s)", trade.ResultRetcode(), trade.ResultRetcodeDescription()));
     }
  }

//==================================================================//
//                      ON TRADE TRANSACTION                        //
//   Detection fiable de la cloture sur stop -> reverse + cancel    //
//==================================================================//
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
  {
   //--- On ne s'interesse qu'a l'ajout d'un deal
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong dealTicket = trans.deal;
   if(dealTicket == 0)
      return;

   if(!HistoryDealSelect(dealTicket))
      return;

   //--- Filtre magic + symbole
   if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagicNumber)
      return;
   if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol)
      return;

   long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

   //--- A) Entree d'une position (un pending stop vient de se declencher) :
   //       on supprime immediatement le pending oppose restant.
   if(entry == DEAL_ENTRY_IN)
     {
      ManagePendingPair();
      return;
     }

   //--- B) Sortie d'une position : si fermeture par STOP LOSS et reverse actif,
   //       on ouvre une position opposee de meme taille.
   if(entry == DEAL_ENTRY_OUT)
     {
      long reason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
      long dtype  = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      double vol  = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);

      // Cloture d'un BUY -> deal de type SELL ; cloture d'un SELL -> deal de type BUY
      bool positionWasBuy = (dtype == DEAL_TYPE_SELL);

      if(g_ReverseOn && reason == DEAL_REASON_SL)
        {
         Log(StringFormat("Position fermee sur SL (sens %s) -> declenche REVERSE.",
                          (positionWasBuy ? "BUY" : "SELL")));
         DoReverse(positionWasBuy, vol);
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
      return(true); // session 24h

   if(InpSessionStartHour < InpSessionEndHour)
      return(h >= InpSessionStartHour && h < InpSessionEndHour);

   // Session a cheval sur minuit (ex. 22 -> 6)
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

//+------------------------------------------------------------------+
//| Compte les ordres en attente de l'EA                             |
//+------------------------------------------------------------------+
int CountEAPending()
  {
   int count = 0;
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetInteger(ORDER_MAGIC) == InpMagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
         count++;
     }
   return(count);
  }

//==================================================================//
//              CONVERSION PIPS / POINTS / NORMALISATION            //
//==================================================================//

//+------------------------------------------------------------------+
//| Nombre de points par pip selon le nombre de digits du symbole    |
//+------------------------------------------------------------------+
double PointsPerPip()
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   // 5 digits (ex 1.23456) ou 3 digits (ex JPY 123.456) -> 1 pip = 10 points
   if(digits == 3 || digits == 5)
      return(10.0);
   return(1.0); // 2 ou 4 digits -> 1 pip = 1 point
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

   // Arrondi propre au nombre de decimales du step
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
   // Marge de securite d'un point
   return((double)(lvl + 1) * _Point);
  }

//+------------------------------------------------------------------+
//| Ajuste un SL trop proche du prix de reference                    |
//|  isBuy=true  -> SL doit etre <= refPrice - minDist               |
//|  isBuy=false -> SL doit etre >= refPrice + minDist               |
//+------------------------------------------------------------------+
double AdjustStopDistance(double sl, double refPrice, bool isBuy)
  {
   double minDist = GetStopsLevelPrice();

   if(isBuy)
     {
      double maxSL = refPrice - minDist;
      if(sl > maxSL)
        {
         Log(StringFormat("SL BUY trop proche (%.5f), ajuste a %.5f (min dist %.5f).", sl, maxSL, minDist));
         sl = maxSL;
        }
     }
   else
     {
      double minSL = refPrice + minDist;
      if(sl < minSL)
        {
         Log(StringFormat("SL SELL trop proche (%.5f), ajuste a %.5f (min dist %.5f).", sl, minSL, minDist));
         sl = minSL;
        }
     }
   return(sl);
  }

//+------------------------------------------------------------------+
//| Ajuste le prix d'un ordre stop trop proche du marche             |
//|  isBuyStop=true  -> prix doit etre >= ask + minDist              |
//|  isBuyStop=false -> prix doit etre <= bid - minDist              |
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
//| Log conditionnel (Print uniquement si InpVerboseLog=true)        |
//+------------------------------------------------------------------+
void Log(string msg)
  {
   if(InpVerboseLog)
      Print(msg);
  }
//+------------------------------------------------------------------+
