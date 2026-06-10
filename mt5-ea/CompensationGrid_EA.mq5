//+------------------------------------------------------------------+
//|                                        CompensationGrid_EA.mq5    |
//|                              Dashboard Trading - Julien Barange   |
//|                                                                  |
//|  EA de GRILLE DE COMPENSATION a RISQUE BORNE (MT5 / Roboforex)   |
//|                                                                  |
//|  Objectif : cloturer le panier de positions EN PROFIT ou a       |
//|  BREAK-EVEN, en moyennant a la baisse (averaging / DCA).         |
//|                                                                  |
//|  >>> SECURITE CLE : un STOP DUR en euros (% equity) ferme TOUT   |
//|  le panier si la perte flottante depasse la limite. Cela borne   |
//|  la perte maximale (contrairement a une martingale classique     |
//|  qui peut liquider le compte).                                   |
//|                                                                  |
//|  AVERTISSEMENT : aucune strategie de grille n'est "sans risque". |
//|  Cet EA limite le risque, il ne l'elimine pas. Testez TOUJOURS   |
//|  en DEMO avant le reel.                                          |
//+------------------------------------------------------------------+
#property copyright "Julien Barange - Trading Dashboard"
#property version   "1.00"
#property strict
#property description "Grille de compensation a risque borne - sortie profit ou break-even"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>

//==================================================================
//  PARAMETRES
//==================================================================

input group "===== Identite ====="
input long    InpMagic              = 250610;   // Magic number (identifie les trades de cet EA)
input string  InpComment            = "CompGrid"; // Commentaire des ordres

input group "===== Signal d'entree (1ere position) ====="
// 0 = ALTERNE (sens oppose au panier precedent)  1 = SUIT la tendance (MA)
// 2 = CONTRE-tendance (mean reversion MA)         3 = FORCE BUY   4 = FORCE SELL
input int     InpEntryMode          = 1;        // Mode d'entree (0=alterne 1=tendance 2=contre 3=buy 4=sell)
input int     InpMAPeriod           = 50;       // Periode MA (pour modes 1 et 2)
input ENUM_TIMEFRAMES InpMATimeframe= PERIOD_M15;// Timeframe de la MA

input group "===== Dimensionnement des lots ====="
input double  InpFixedStartLot      = 0.0;      // Lot initial fixe (0 = calcul auto via risque)
input double  InpRiskPercentStart   = 0.30;     // Risque lot initial (% du capital) si lot auto
input double  InpLotMultiplier      = 1.30;     // Multiplicateur de lot par palier (1.0 = pas de martingale)
input double  InpLotAdd             = 0.0;      // Ajout lineaire de lot par palier (alternative au multi)
input double  InpMaxSingleLot       = 5.0;      // Lot max d'un seul ordre (garde-fou)
input double  InpMaxTotalLot        = 20.0;     // Volume cumule max du panier (garde-fou)

input group "===== Grille (espacement des paliers) ====="
input int     InpMaxLevels          = 6;        // Nombre MAX de paliers (positions dans le panier)
input double  InpGridStepPips       = 25.0;     // Distance fixe entre paliers (pips)
input bool    InpDynamicStep        = true;     // Espacement adaptatif via ATR
input int     InpATRPeriod          = 14;       // Periode ATR
input double  InpATRStepFactor      = 1.0;      // Facteur ATR (pas = ATR * facteur)

input group "===== Sorties (profit / break-even) ====="
input double  InpProfitTargetMoney  = 30.0;     // Objectif de profit du panier (€ net)
input bool    InpUseBEExit          = true;     // Sortie a break-even quand la grille est pleine
input double  InpBreakEvenMoney     = 2.0;      // Seuil "BE atteint" (€ >= 0, marge anti spread)
input bool    InpTrailBasket        = true;     // Trailing du profit du panier
input double  InpTrailStartMoney    = 20.0;     // Activer le trailing a partir de (€)
input double  InpTrailGiveBackMoney = 10.0;     // Restitution max avant cloture (€)

input group "===== SECURITE / Risque borne ====="
input double  InpMaxBasketLossPct   = 3.0;      // STOP DUR : perte max du panier (% equity)
input double  InpMaxBasketLossMoney = 0.0;      // STOP DUR en € fixe (0 = utilise le %)
input double  InpDailyLossLimitPct  = 5.0;      // Stop journalier (% balance) -> stop trading du jour
input double  InpMinMarginLevel     = 300.0;    // Niveau de marge mini (%) sous lequel on n'ajoute plus

input group "===== Filtres de marche ====="
input double  InpMaxSpreadPoints    = 25.0;     // Spread max autorise (points) pour ouvrir
input double  InpCommissionPerLot   = 7.0;      // Commission aller-retour estimee (€ / 1.0 lot)
input bool    InpUseTradingHours    = true;     // Filtrer les heures de trading
input int     InpStartHour          = 7;        // Heure debut (serveur)
input int     InpEndHour            = 21;       // Heure fin (serveur)
input bool    InpTradeFriday        = false;    // Autoriser l'ouverture le vendredi
input int     InpSlippagePoints     = 20;       // Slippage max (points)

input group "===== Affichage ====="
input bool    InpShowPanel          = true;     // Afficher le panneau d'info
input bool    InpDebug              = false;    // Logs detailles

//==================================================================
//  OBJETS / ETAT GLOBAL
//==================================================================
CTrade        trade;
CPositionInfo pos;
CSymbolInfo   sym;

string  gSymbol;
double  gPoint;
int     gDigits;
double  gPipSize;        // taille d'un pip (10 points si 3/5 digits)
int     gATRHandle = INVALID_HANDLE;
int     gMAHandle  = INVALID_HANDLE;

double  gBasketPeakProfit = 0.0;   // pour le trailing du panier
datetime gLastBarTime     = 0;
datetime gDayStart        = 0;
double  gDayStartBalance  = 0.0;
bool    gTradingHaltedToday = false;
int     gLastBasketDir    = 0;     // pour le mode ALTERNE : +1 buy, -1 sell

//==================================================================
//  INIT
//==================================================================
int OnInit()
{
   gSymbol = _Symbol;

   if(!sym.Name(gSymbol))
   {
      Print("ERREUR: symbole introuvable ", gSymbol);
      return(INIT_FAILED);
   }
   sym.RefreshRates();

   gPoint  = SymbolInfoDouble(gSymbol, SYMBOL_POINT);
   gDigits = (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS);
   gPipSize = (gDigits == 3 || gDigits == 5) ? gPoint * 10.0 : gPoint;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);
   trade.SetTypeFillingBySymbol(gSymbol);
   trade.SetAsyncMode(false);

   if(InpDynamicStep)
   {
      gATRHandle = iATR(gSymbol, InpMATimeframe, InpATRPeriod);
      if(gATRHandle == INVALID_HANDLE)
         Print("ATTENTION: handle ATR invalide, repli sur pas fixe");
   }
   if(InpEntryMode == 1 || InpEntryMode == 2)
   {
      gMAHandle = iMA(gSymbol, InpMATimeframe, InpMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(gMAHandle == INVALID_HANDLE)
         Print("ATTENTION: handle MA invalide");
   }

   ResetDay();

   Print("=== CompensationGrid_EA v1.00 ===");
   Print("Symbole: ", gSymbol, " | Magic: ", InpMagic,
         " | Pip=", DoubleToString(gPipSize, gDigits));
   Print("STOP DUR perte panier: ", DoubleToString(BasketMaxLossMoney(), 2), " €");

   EventSetTimer(2);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(gATRHandle != INVALID_HANDLE) IndicatorRelease(gATRHandle);
   if(gMAHandle  != INVALID_HANDLE) IndicatorRelease(gMAHandle);
   Comment("");
}

//==================================================================
//  TIMER : gestion continue (sorties, securite) meme entre ticks
//==================================================================
void OnTimer()
{
   ManageBasket();   // sorties + stop dur evalues en continu
   if(InpShowPanel) DrawPanel();
}

//==================================================================
//  TICK : logique principale
//==================================================================
void OnTick()
{
   if(!sym.RefreshRates()) return;

   RolloverDayIfNeeded();

   // 1) Gestion des sorties et du stop dur (priorite absolue)
   if(ManageBasket()) return;   // si on a cloture, on s'arrete ce tick

   // 2) Securite : stop journalier
   if(gTradingHaltedToday) return;
   if(DailyLossHit())
   {
      gTradingHaltedToday = true;
      Print("STOP JOURNALIER atteint - plus d'ouverture aujourd'hui.");
      return;
   }

   // 3) Une seule action par bougie pour la logique d'ouverture
   datetime barTime = iTime(gSymbol, InpMATimeframe, 0);
   bool newBar = (barTime != gLastBarTime);

   int basketCount = CountPositions();

   if(basketCount == 0)
   {
      // Ouverture de la 1ere position du panier
      if(newBar && CanOpenNow())
      {
         int dir = DecideDirection();
         if(dir != 0)
         {
            double lot = FirstLot();
            if(OpenMarket(dir, lot, 1))
               gLastBasketDir = dir;
         }
      }
   }
   else
   {
      // Panier en cours : ajout d'un palier si le marche va contre nous
      MaybeAddGridLevel(basketCount);
   }

   if(newBar) gLastBarTime = barTime;
}

//==================================================================
//  DIRECTION D'ENTREE
//==================================================================
int DecideDirection()
{
   switch(InpEntryMode)
   {
      case 3: return +1;                       // force BUY
      case 4: return -1;                       // force SELL
      case 0: return (gLastBasketDir <= 0) ? +1 : -1;  // alterne
      case 1:                                   // suit la tendance
      case 2:                                   // contre-tendance
      {
         double ma[];
         if(gMAHandle == INVALID_HANDLE) return +1;
         if(CopyBuffer(gMAHandle, 0, 0, 2, ma) < 2) return 0;
         double price = sym.Bid();
         int trend = (price > ma[0]) ? +1 : -1;
         return (InpEntryMode == 1) ? trend : -trend;
      }
   }
   return 0;
}

//==================================================================
//  AJOUT D'UN PALIER DE GRILLE (averaging)
//==================================================================
void MaybeAddGridLevel(int basketCount)
{
   if(basketCount >= InpMaxLevels) return;      // grille pleine

   // Securite marge
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(marginLevel > 0 && marginLevel < InpMinMarginLevel) return;

   if(TotalVolume() >= InpMaxTotalLot) return;

   int    dir       = BasketDirection();        // sens du panier
   if(dir == 0) return;

   double worstPrice = WorstEntryPrice(dir);    // pire prix d'entree (le plus loin)
   double step       = CurrentStepPrice();
   double price      = (dir > 0) ? sym.Ask() : sym.Bid();

   bool   adverse = (dir > 0) ? (price <= worstPrice - step)
                              : (price >= worstPrice + step);
   if(!adverse) return;

   if(!CanOpenNow()) return;                     // spread / horaires

   double lot = NextLot(basketCount);
   OpenMarket(dir, lot, basketCount + 1);
}

//==================================================================
//  GESTION DU PANIER : sorties profit / BE / trailing / STOP DUR
//  Retourne true si une cloture a ete declenchee.
//==================================================================
bool ManageBasket()
{
   int n = CountPositions();
   if(n == 0)
   {
      gBasketPeakProfit = 0.0;
      return false;
   }

   double netPL = BasketNetProfit();   // profit flottant net (commission deduite)

   // -- 1) STOP DUR (priorite max) : borne la perte ----------------
   double maxLoss = BasketMaxLossMoney();
   if(maxLoss > 0 && netPL <= -maxLoss)
   {
      Print("!!! STOP DUR DECLENCHE !!! Perte panier=", DoubleToString(netPL, 2),
            " € (limite ", DoubleToString(maxLoss, 2), " €) -> cloture totale");
      CloseBasket("HardStop");
      return true;
   }

   // -- 2) Objectif de profit --------------------------------------
   if(netPL >= InpProfitTargetMoney)
   {
      if(InpDebug) Print("Objectif profit atteint: ", DoubleToString(netPL, 2), " €");
      CloseBasket("TP");
      return true;
   }

   // -- 3) Trailing du profit du panier ----------------------------
   if(InpTrailBasket)
   {
      if(netPL > gBasketPeakProfit) gBasketPeakProfit = netPL;
      if(gBasketPeakProfit >= InpTrailStartMoney &&
         netPL <= gBasketPeakProfit - InpTrailGiveBackMoney &&
         netPL > 0)
      {
         Print("Trailing panier: pic=", DoubleToString(gBasketPeakProfit, 2),
               " now=", DoubleToString(netPL, 2), " € -> cloture");
         CloseBasket("Trail");
         return true;
      }
   }

   // -- 4) Sortie a BREAK-EVEN quand la grille est pleine ----------
   if(InpUseBEExit && n >= InpMaxLevels && netPL >= InpBreakEvenMoney)
   {
      Print("Sortie BREAK-EVEN (grille pleine): ", DoubleToString(netPL, 2), " €");
      CloseBasket("BE");
      return true;
   }

   return false;
}

//==================================================================
//  OUVERTURE D'UN ORDRE MARCHE
//==================================================================
bool OpenMarket(int dir, double lot, int level)
{
   lot = NormalizeLot(lot);
   if(lot <= 0) return false;

   string cmt = InpComment + "_L" + IntegerToString(level);
   bool ok;
   if(dir > 0) ok = trade.Buy(lot, gSymbol, 0.0, 0.0, 0.0, cmt);
   else        ok = trade.Sell(lot, gSymbol, 0.0, 0.0, 0.0, cmt);

   if(!ok)
      Print("ECHEC ouverture ", (dir>0?"BUY":"SELL"), " ", DoubleToString(lot,2),
            " lot - retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   else if(InpDebug)
      Print("Ouvert ", (dir>0?"BUY":"SELL"), " ", DoubleToString(lot,2),
            " lot (palier ", level, ")");
   return ok;
}

//==================================================================
//  CLOTURE COMPLETE DU PANIER
//==================================================================
void CloseBasket(string reason)
{
   // On boucle plusieurs fois : la fermeture peut echouer sur un tick
   for(int attempt = 0; attempt < 3; attempt++)
   {
      bool remaining = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
         if(PositionGetString(POSITION_SYMBOL) != gSymbol) continue;

         if(!trade.PositionClose(ticket, InpSlippagePoints))
         {
            remaining = true;
            if(InpDebug) Print("Echec cloture ticket ", ticket,
                               " retcode=", trade.ResultRetcode());
         }
      }
      if(!remaining) break;
      Sleep(200);
      sym.RefreshRates();
   }
   gBasketPeakProfit = 0.0;
   if(InpDebug) Print("Panier cloture (", reason, ")");
}

//==================================================================
//  CALCULS PANIER
//==================================================================
int CountPositions()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != gSymbol) continue;
      c++;
   }
   return c;
}

// Profit NET flottant du panier = somme(profit + swap) - commission estimee
double BasketNetProfit()
{
   double pl = 0.0;
   double vol = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != gSymbol) continue;
      pl  += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      vol += PositionGetDouble(POSITION_VOLUME);
   }
   pl -= vol * InpCommissionPerLot;   // commission aller-retour estimee
   return pl;
}

double TotalVolume()
{
   double vol = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != gSymbol) continue;
      vol += PositionGetDouble(POSITION_VOLUME);
   }
   return vol;
}

// Sens dominant du panier (+1 buy / -1 sell / 0 vide)
int BasketDirection()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != gSymbol) continue;
      return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? +1 : -1;
   }
   return 0;
}

// Pire prix d'entree (le plus eloigne dans le sens defavorable)
double WorstEntryPrice(int dir)
{
   double worst = 0.0;
   bool first = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != gSymbol) continue;
      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      if(first) { worst = op; first = false; continue; }
      if(dir > 0) worst = MathMin(worst, op);  // buy : on veut le plus bas
      else        worst = MathMax(worst, op);  // sell : on veut le plus haut
   }
   return worst;
}

//==================================================================
//  LOTS
//==================================================================
double FirstLot()
{
   if(InpFixedStartLot > 0) return NormalizeLot(InpFixedStartLot);

   // Lot auto : on dimensionne pour que la perte au STOP DUR ~ risque defini.
   // Approche prudente : lot tel que la valeur d'1 pip * step * (estimation paliers)
   // reste modeste. On part simple : risque% du capital sur la distance stop dur.
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * InpRiskPercentStart / 100.0;

   double tickValue = SymbolInfoDouble(gSymbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(gSymbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return NormalizeLot(0.01);

   double pipValuePerLot = tickValue * (gPipSize / tickSize); // € par pip pour 1 lot
   double refDistancePips = InpGridStepPips * MathMax(1, InpMaxLevels / 2.0);
   if(pipValuePerLot <= 0 || refDistancePips <= 0) return NormalizeLot(0.01);

   double lot = riskMoney / (pipValuePerLot * refDistancePips);
   return NormalizeLot(lot);
}

double NextLot(int currentCount)
{
   double base = FirstLot();
   double lot;
   if(InpLotAdd > 0)
      lot = base + InpLotAdd * currentCount;
   else
      lot = base * MathPow(InpLotMultiplier, currentCount);
   return NormalizeLot(lot);
}

double NormalizeLot(double lot)
{
   double minLot  = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_STEP);

   if(stepLot <= 0) stepLot = 0.01;
   lot = MathFloor(lot / stepLot) * stepLot;

   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   if(lot > InpMaxSingleLot) lot = InpMaxSingleLot;

   // arrondi propre
   int lotDigits = (int)MathRound(MathLog10(1.0 / stepLot));
   if(lotDigits < 0) lotDigits = 2;
   return NormalizeDouble(lot, lotDigits);
}

//==================================================================
//  PAS DE GRILLE (fixe ou ATR)
//==================================================================
double CurrentStepPrice()
{
   double stepPips = InpGridStepPips;
   if(InpDynamicStep && gATRHandle != INVALID_HANDLE)
   {
      double atr[];
      if(CopyBuffer(gATRHandle, 0, 0, 1, atr) == 1 && atr[0] > 0)
      {
         double atrPips = atr[0] / gPipSize;
         stepPips = MathMax(InpGridStepPips * 0.5, atrPips * InpATRStepFactor);
      }
   }
   return stepPips * gPipSize;
}

//==================================================================
//  SECURITE / FILTRES
//==================================================================
double BasketMaxLossMoney()
{
   if(InpMaxBasketLossMoney > 0) return InpMaxBasketLossMoney;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   return equity * InpMaxBasketLossPct / 100.0;
}

bool DailyLossHit()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayPL  = equity - gDayStartBalance;
   double limit  = gDayStartBalance * InpDailyLossLimitPct / 100.0;
   return (dayPL <= -limit);
}

bool CanOpenNow()
{
   // Spread
   double spread = (double)SymbolInfoInteger(gSymbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)
   {
      if(InpDebug) Print("Spread trop large: ", spread, " pts");
      return false;
   }
   // Horaires
   if(InpUseTradingHours)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.hour < InpStartHour || dt.hour >= InpEndHour) return false;
      if(!InpTradeFriday && dt.day_of_week == 5) return false;
      if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
   }
   return true;
}

//==================================================================
//  GESTION DU JOUR
//==================================================================
void ResetDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   gDayStart = StructToTime(dt);
   gDayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   gTradingHaltedToday = false;
}

void RolloverDayIfNeeded()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime today = StructToTime(dt);
   if(today != gDayStart) ResetDay();
}

//==================================================================
//  PANNEAU D'INFO
//==================================================================
void DrawPanel()
{
   int    n      = CountPositions();
   double netPL  = (n > 0) ? BasketNetProfit() : 0.0;
   double vol    = TotalVolume();
   double maxLoss= BasketMaxLossMoney();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dayPL  = equity - gDayStartBalance;
   double spread = (double)SymbolInfoInteger(gSymbol, SYMBOL_SPREAD);

   string s = "";
   s += "===== CompensationGrid EA =====\n";
   s += "Symbole: " + gSymbol + "   Spread: " + DoubleToString(spread,0) + " pts\n";
   s += "Equity: " + DoubleToString(equity,2) + " €\n";
   s += "-------------------------------\n";
   s += "Positions panier: " + IntegerToString(n) + " / " + IntegerToString(InpMaxLevels) + "\n";
   s += "Volume cumule: " + DoubleToString(vol,2) + " lots\n";
   s += "P&L panier (net): " + DoubleToString(netPL,2) + " €\n";
   s += "Objectif: +" + DoubleToString(InpProfitTargetMoney,2) + " €\n";
   s += "STOP DUR: -" + DoubleToString(maxLoss,2) + " €\n";
   s += "-------------------------------\n";
   s += "P&L du jour: " + DoubleToString(dayPL,2) + " €\n";
   s += "Trading jour: " + (gTradingHaltedToday ? "STOPPE" : "actif") + "\n";
   Comment(s);
}
//+------------------------------------------------------------------+
