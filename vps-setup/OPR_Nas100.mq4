//+------------------------------------------------------------------+
//|                                                   OPR_Nas100.mq4 |
//|                  Opening Range Breakout - NAS100 - MetaTrader 4 |
//|                                                            v1.00 |
//+------------------------------------------------------------------+
#property copyright "OPR Strategy v1.00"
#property link      ""
#property version   "1.00"
#property strict

//============================================================
//  IDENTITE INSTRUMENT
//============================================================
#define EA_NAME        "OPR_Nas100"
#define EA_VERSION     "1.00"
#define EA_INSTRUMENT  "NAS100"

// Sur NAS100 : 1 "point" utilisateur = 1.0 de mouvement d'indice
// (independant du nombre de decimales du broker)
const double PIP_SIZE_PRICE = 1.0;

//============================================================
//  CONSTANTES INTERNES
//============================================================
#define MAX_RETRIES      3
#define COMMENT_TP1      "OPR_TP1"
#define COMMENT_TRAIL    "OPR_TRAIL"
#define SLIPPAGE_POINTS  5
#define SECONDS_PER_MIN  60

//============================================================
//  INPUTS UTILISATEUR
//============================================================
// --- Timing (heure serveur RoboForex : UTC+3 ete / UTC+2 hiver) ---
extern int    NYOpen_ServerHour   = 16;
extern int    NYOpen_ServerMin    = 30;
extern int    TradeEnd_ServerHour = 22;
extern int    TradeEnd_ServerMin  = 30;

// --- Bornes du range OPR (en points d'indice pour NAS100) ---
extern double MinRangeSize        = 30;
extern double MaxRangeSize        = 120;

// --- Filtres techniques ---
extern bool   FilterATR           = true;
extern int    ATR_Period          = 14;
extern int    ATR_SMA_Period      = 20;
extern double MinBodyRatio        = 0.60;
extern int    MaxSpreadPoints     = 30;

// --- Gestion du risque ---
extern double RiskPercent         = 1.0;
extern double RR_TP1              = 1.75;
extern double ScaleOut_TP1_Pct    = 75.0;
extern double TrailMultiplier     = 0.5;

// --- Filtres calendrier ---
extern bool   NoFriday            = true;
extern bool   NoTradeNewsDay      = true;
extern string NewsDate            = "";   // ex: "2024.12.06"

// --- Identifiants ---
extern int    MagicNumber         = 20250102;
extern bool   ShowDashboard       = true;

//============================================================
//  ETAT GLOBAL
//============================================================
datetime g_dayStart           = 0;
bool     g_rangeBuilt         = false;
double   g_oprHigh            = 0.0;
double   g_oprLow             = 0.0;
double   g_rangeSizeUnits     = 0.0;
double   g_atrM5AtEntry       = 0.0;

bool     g_tradeTakenToday    = false;
bool     g_eodClosed          = false;
bool     g_tp1Filled          = false;
int      g_currentDir         = 0;
int      g_ticketTP1          = -1;
int      g_ticketTrail        = -1;
double   g_entryPrice         = 0.0;
double   g_slPrice            = 0.0;
double   g_tp1Price           = 0.0;
double   g_initialLot1        = 0.0;
double   g_initialLot2        = 0.0;

datetime g_lastM5BarTime      = 0;
int      g_tradesToday        = 0;
double   g_pnlToday           = 0.0;

string   g_state              = "Init...";
string   g_blockReason        = "";

//============================================================
//  PROTOTYPES
//============================================================
datetime SessionStartTime();
datetime SessionEndTime();
datetime ComputeDayStart();
bool     IsNewsDay();
bool     IsFridayBlocked();
bool     IsSpreadOK();
bool     IsWithinTradingWindow();
void     ResetDayState();
void     BuildOPRRange();
void     EvaluateEntry();
bool     CheckEntryConditions(int &direction, double &slPrice);
double   CalculateLotSize(double slDistPrice);
double   NormalizeLotDown(double lot, double step, double minL, double maxL);
bool     OpenTrade(int dir, double slPrice);
int      SendWithRetry(int op, double lot, double price, double sl, double tp, string cmt);
void     ManageTrailingStop();
void     CheckEODClose();
void     CloseAllPositions(string reason);
void     DrawDashboard();
void     LogTrade(int op, double lot1, double lot2, double entry, double sl, double tp1);
void     LogBlocked(string reason);
void     RecoverState();
double   ComputeOpenPnL();

//+------------------------------------------------------------------+
//|                            OnInit                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   if(MinRangeSize <= 0 || MaxRangeSize <= 0 || MinRangeSize >= MaxRangeSize)
   {
      Print(EA_NAME, " ERREUR : MinRangeSize doit etre > 0 et < MaxRangeSize");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(RiskPercent <= 0 || RiskPercent > 10)
   {
      Print(EA_NAME, " ERREUR : RiskPercent hors plage (]0;10])");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(ScaleOut_TP1_Pct <= 0 || ScaleOut_TP1_Pct >= 100)
   {
      Print(EA_NAME, " ERREUR : ScaleOut_TP1_Pct doit etre dans ]0;100[");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(RR_TP1 <= 0)
   {
      Print(EA_NAME, " ERREUR : RR_TP1 doit etre > 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(ATR_Period < 2 || ATR_SMA_Period < 2)
   {
      Print(EA_NAME, " ERREUR : ATR_Period et ATR_SMA_Period doivent etre >= 2");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(NYOpen_ServerHour < 0 || NYOpen_ServerHour > 23 ||
      NYOpen_ServerMin  < 0 || NYOpen_ServerMin  > 59 ||
      TradeEnd_ServerHour < 0 || TradeEnd_ServerHour > 23 ||
      TradeEnd_ServerMin  < 0 || TradeEnd_ServerMin  > 59)
   {
      Print(EA_NAME, " ERREUR : Heures serveur invalides");
      return(INIT_PARAMETERS_INCORRECT);
   }

   ResetDayState();
   g_dayStart = ComputeDayStart();
   RecoverState();

   Print(EA_NAME, " v", EA_VERSION, " initialise sur ", _Symbol,
         " | Magic=", MagicNumber,
         " | Digits=", _Digits,
         " | Point=", DoubleToStr(_Point, _Digits+1));

   if(ShowDashboard) DrawDashboard();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//|                          OnDeinit                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   Print(EA_NAME, " deinitialise (reason=", reason, ")");
}

//+------------------------------------------------------------------+
//|                            OnTick                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime today = ComputeDayStart();
   if(today != g_dayStart)
   {
      g_dayStart = today;
      ResetDayState();
      Print(EA_NAME, " Nouveau jour de trading : ", TimeToString(today, TIME_DATE));
   }

   BuildOPRRange();
   ManageTrailingStop();
   CheckEODClose();

   if(!g_tradeTakenToday && g_rangeBuilt && !g_eodClosed)
   {
      EvaluateEntry();
   }
   else if(g_tradeTakenToday && !g_eodClosed)
   {
      if(g_currentDir > 0) g_state = "In position LONG";
      else if(g_currentDir < 0) g_state = "In position SHORT";
      else                       g_state = "Trade ferme";
   }
   else if(g_eodClosed)
   {
      g_state = "EOD";
   }

   if(ShowDashboard) DrawDashboard();
}

//============================================================
//  EVALUATION DES CONDITIONS D'ENTREE (extrait pour control flow)
//============================================================
void EvaluateEntry()
{
   if(IsFridayBlocked()) { g_state = "No trade today (Friday)"; return; }
   if(IsNewsDay())       { g_state = "No trade today (News day)"; return; }
   if(!IsWithinTradingWindow()) { g_state = "Hors horaire"; return; }

   if(g_rangeSizeUnits < MinRangeSize || g_rangeSizeUnits > MaxRangeSize)
   {
      g_state = "Range hors bornes (" + DoubleToStr(g_rangeSizeUnits,1) + ")";
      return;
   }

   if(!IsSpreadOK())
   {
      g_state = "Spread > max (" +
                DoubleToStr(MarketInfo(_Symbol, MODE_SPREAD),0) + ")";
      return;
   }

   datetime barTime = iTime(_Symbol, PERIOD_M5, 0);
   if(barTime == g_lastM5BarTime)
   {
      g_state = "Waiting breakout...";
      return;
   }
   g_lastM5BarTime = barTime;

   int    dir  = 0;
   double slPx = 0.0;
   if(CheckEntryConditions(dir, slPx))
   {
      g_state = "Opening trade...";
      if(!OpenTrade(dir, slPx))
         g_state = "Open trade FAILED";
   }
   else
   {
      g_state = "Waiting breakout... (" + g_blockReason + ")";
   }
}

//============================================================
//  TIMING
//============================================================
datetime SessionStartTime()
{
   MqlDateTime mdt;
   TimeToStruct(TimeCurrent(), mdt);
   mdt.hour = NYOpen_ServerHour;
   mdt.min  = NYOpen_ServerMin;
   mdt.sec  = 0;
   return StructToTime(mdt);
}

datetime SessionEndTime()
{
   MqlDateTime mdt;
   TimeToStruct(TimeCurrent(), mdt);
   mdt.hour = TradeEnd_ServerHour;
   mdt.min  = TradeEnd_ServerMin;
   mdt.sec  = 0;
   return StructToTime(mdt);
}

datetime ComputeDayStart()
{
   MqlDateTime mdt;
   TimeToStruct(TimeCurrent(), mdt);
   mdt.hour = 0; mdt.min = 0; mdt.sec = 0;
   return StructToTime(mdt);
}

bool IsWithinTradingWindow()
{
   datetime now = TimeCurrent();
   return (now >= SessionStartTime() + 30*SECONDS_PER_MIN && now < SessionEndTime());
}

//============================================================
//  FILTRES
//============================================================
bool IsFridayBlocked()
{
   if(!NoFriday) return false;
   MqlDateTime mdt;
   TimeToStruct(TimeCurrent(), mdt);
   return (mdt.day_of_week == 5);
}

bool IsNewsDay()
{
   if(!NoTradeNewsDay) return false;
   if(StringLen(NewsDate) < 8) return false;
   datetime nd = StringToTime(NewsDate);
   if(nd <= 0) return false;
   MqlDateTime today, news;
   TimeToStruct(TimeCurrent(), today);
   TimeToStruct(nd, news);
   return (today.year == news.year && today.mon == news.mon && today.day == news.day);
}

bool IsSpreadOK()
{
   double spread = MarketInfo(_Symbol, MODE_SPREAD);
   return (spread <= MaxSpreadPoints);
}

//============================================================
//  RESET DE L'ETAT JOURNALIER
//============================================================
void ResetDayState()
{
   g_rangeBuilt       = false;
   g_oprHigh          = 0.0;
   g_oprLow           = 0.0;
   g_rangeSizeUnits   = 0.0;
   g_atrM5AtEntry     = 0.0;
   g_tradeTakenToday  = false;
   g_eodClosed        = false;
   g_tp1Filled        = false;
   g_currentDir       = 0;
   g_ticketTP1        = -1;
   g_ticketTrail      = -1;
   g_entryPrice       = 0.0;
   g_slPrice          = 0.0;
   g_tp1Price         = 0.0;
   g_initialLot1      = 0.0;
   g_initialLot2      = 0.0;
   g_lastM5BarTime    = 0;
   g_tradesToday      = 0;
   g_pnlToday         = 0.0;
   g_state            = "Waiting NY open...";
   g_blockReason      = "";
}

//============================================================
//  CONSTRUCTION DU RANGE OPR
//============================================================
void BuildOPRRange()
{
   if(g_rangeBuilt) return;

   datetime now         = TimeCurrent();
   datetime windowStart = SessionStartTime();
   datetime windowEnd   = windowStart + 30 * SECONDS_PER_MIN;

   if(now < windowStart)
   {
      g_state = "Waiting NY open...";
      return;
   }

   if(now < windowEnd)
   {
      g_state = "Building range...";
      if(g_oprHigh == 0.0) g_oprHigh = Bid;
      if(g_oprLow  == 0.0) g_oprLow  = Bid;
      if(Bid > g_oprHigh) g_oprHigh = Bid;
      if(Bid < g_oprLow ) g_oprLow  = Bid;
      g_rangeSizeUnits = (g_oprHigh - g_oprLow) / PIP_SIZE_PRICE;
      return;
   }

   double h = -1.0e15;
   double l =  1.0e15;
   int    barsScanned = 0;
   for(int i = 0; i < 300; i++)
   {
      datetime bt = iTime(_Symbol, PERIOD_M1, i);
      if(bt == 0) break;
      if(bt + 60 <= windowStart) break;
      if(bt >= windowEnd) continue;
      double bh = iHigh(_Symbol, PERIOD_M1, i);
      double bl = iLow (_Symbol, PERIOD_M1, i);
      if(bh > h) h = bh;
      if(bl < l) l = bl;
      barsScanned++;
   }
   if(barsScanned > 0 && h > 0 && l < 1.0e15)
   {
      g_oprHigh = h;
      g_oprLow  = l;
   }
   g_rangeSizeUnits = (g_oprHigh - g_oprLow) / PIP_SIZE_PRICE;
   g_rangeBuilt = true;

   Print(EA_NAME, " Range OPR construit | High=", DoubleToStr(g_oprHigh, _Digits),
         " Low=", DoubleToStr(g_oprLow, _Digits),
         " Size=", DoubleToStr(g_rangeSizeUnits, 1), " points");
}

//============================================================
//  CONDITIONS D'ENTREE
//============================================================
bool CheckEntryConditions(int &direction, double &slPrice)
{
   direction = 0;
   slPrice   = 0.0;
   g_blockReason = "";

   if(FilterATR)
   {
      double atr_h1  = iATR(_Symbol, PERIOD_H1, ATR_Period, 1);
      double atr_sma = 0.0;
      for(int i = 1; i <= ATR_SMA_Period; i++)
         atr_sma += iATR(_Symbol, PERIOD_H1, ATR_Period, i);
      atr_sma /= ATR_SMA_Period;
      if(atr_h1 <= atr_sma)
      {
         g_blockReason = "ATR H1 <= SMA";
         return false;
      }
   }

   double m5_open  = iOpen (_Symbol, PERIOD_M5, 1);
   double m5_high  = iHigh (_Symbol, PERIOD_M5, 1);
   double m5_low   = iLow  (_Symbol, PERIOD_M5, 1);
   double m5_close = iClose(_Symbol, PERIOD_M5, 1);
   double m5_range = m5_high - m5_low;
   if(m5_range <= 0)
   {
      g_blockReason = "M5 range nul";
      return false;
   }

   double body      = MathAbs(m5_close - m5_open);
   double bodyRatio = body / m5_range;
   double atrM5     = iATR(_Symbol, PERIOD_M5, ATR_Period, 1);

   if(m5_close > g_oprHigh)
   {
      if(bodyRatio < MinBodyRatio)
      {
         g_blockReason = "Body M5 " + DoubleToStr(bodyRatio*100, 0) +
                         "% < " + DoubleToStr(MinBodyRatio*100, 0) + "%";
         return false;
      }
      direction      = +1;
      slPrice        = g_oprLow - atrM5 * 0.5;
      g_atrM5AtEntry = atrM5;
      return true;
   }
   if(m5_close < g_oprLow)
   {
      if(bodyRatio < MinBodyRatio)
      {
         g_blockReason = "Body M5 " + DoubleToStr(bodyRatio*100, 0) +
                         "% < " + DoubleToStr(MinBodyRatio*100, 0) + "%";
         return false;
      }
      direction      = -1;
      slPrice        = g_oprHigh + atrM5 * 0.5;
      g_atrM5AtEntry = atrM5;
      return true;
   }

   g_blockReason = "Pas de cassure";
   return false;
}

//============================================================
//  CALCUL DU LOT BASE SUR LE RISQUE
//============================================================
double CalculateLotSize(double slDistPrice)
{
   if(slDistPrice <= 0) return 0.0;
   double tickValue = MarketInfo(_Symbol, MODE_TICKVALUE);
   double tickSize  = MarketInfo(_Symbol, MODE_TICKSIZE);
   if(tickValue <= 0 || tickSize <= 0) return 0.0;
   double moneyPerPricePerLot = tickValue / tickSize;
   double moneyAtRisk         = AccountBalance() * RiskPercent / 100.0;
   double rawLot              = moneyAtRisk / (slDistPrice * moneyPerPricePerLot);
   return rawLot;
}

double NormalizeLotDown(double lot, double step, double minL, double maxL)
{
   if(step <= 0) step = 0.01;
   double n = MathFloor(lot / step + 1e-9) * step;
   if(n < minL) return 0.0;
   if(n > maxL) n = maxL;
   int decimals = 2;
   if(step >= 0.099) decimals = 1;
   if(step >= 0.99)  decimals = 0;
   return NormalizeDouble(n, decimals);
}

//============================================================
//  OUVERTURE DES TRADES (scale-out en 2 ordres)
//============================================================
bool OpenTrade(int dir, double slPrice)
{
   RefreshRates();
   double entry  = (dir > 0) ? Ask : Bid;
   double slDist = MathAbs(entry - slPrice);
   if(slDist <= 0)
   {
      LogBlocked("SL distance nulle");
      return false;
   }
   double tp1Price = (dir > 0) ? (entry + slDist * RR_TP1)
                               : (entry - slDist * RR_TP1);

   double totalLot = CalculateLotSize(slDist);
   if(totalLot <= 0)
   {
      LogBlocked("Lot calcule <= 0");
      return false;
   }

   double minLot  = MarketInfo(_Symbol, MODE_MINLOT);
   double maxLot  = MarketInfo(_Symbol, MODE_MAXLOT);
   double lotStep = MarketInfo(_Symbol, MODE_LOTSTEP);

   double lot1 = NormalizeLotDown(totalLot * ScaleOut_TP1_Pct / 100.0, lotStep, minLot, maxLot);
   double rem  = totalLot - lot1;
   double lot2 = NormalizeLotDown(rem, lotStep, minLot, maxLot);
   bool scaleOut = (lot2 >= minLot && lot1 >= minLot);

   if(!scaleOut)
   {
      lot1 = NormalizeLotDown(totalLot, lotStep, minLot, maxLot);
      lot2 = 0.0;
      Print(EA_NAME, " Volume insuffisant pour scale-out, ordre unique");
   }
   if(lot1 < minLot)
   {
      LogBlocked("Lot < MinLot broker (" + DoubleToStr(minLot, 2) + ")");
      return false;
   }

   int    op   = (dir > 0) ? OP_BUY : OP_SELL;
   double slN  = NormalizeDouble(slPrice, _Digits);
   double tp1N = NormalizeDouble(tp1Price, _Digits);

   int t1 = SendWithRetry(op, lot1, entry, slN, tp1N, COMMENT_TP1);
   if(t1 < 0)
   {
      LogBlocked("OrderSend TP1 echoue");
      return false;
   }
   g_ticketTP1   = t1;
   g_initialLot1 = lot1;

   int t2 = -1;
   if(scaleOut)
   {
      RefreshRates();
      double entry2 = (dir > 0) ? Ask : Bid;
      t2 = SendWithRetry(op, lot2, entry2, slN, 0.0, COMMENT_TRAIL);
      if(t2 < 0)
      {
         Print(EA_NAME, " AVERT : second ordre (trail) echoue, gestion TP1 uniquement");
      }
      else
      {
         g_ticketTrail = t2;
         g_initialLot2 = lot2;
      }
   }

   g_currentDir      = dir;
   g_tradeTakenToday = true;
   g_tradesToday++;
   g_entryPrice      = entry;
   g_slPrice         = slN;
   g_tp1Price        = tp1N;

   LogTrade(op, lot1, lot2, entry, slN, tp1N);
   return true;
}

//============================================================
//  ENVOI ORDRE AVEC RETRY
//============================================================
int SendWithRetry(int op, double lot, double price, double sl, double tp, string cmt)
{
   if(!IsTradeAllowed())
   {
      Print(EA_NAME, " ERR : trading desactive (IsTradeAllowed=false)");
      return -1;
   }
   for(int i = 0; i < MAX_RETRIES; i++)
   {
      RefreshRates();
      double p = (op == OP_BUY) ? Ask : Bid;
      color c = (op == OP_BUY) ? clrBlue : clrRed;
      int ticket = OrderSend(_Symbol, op, lot, p, SLIPPAGE_POINTS, sl, tp,
                             cmt, MagicNumber, 0, c);
      if(ticket > 0) return ticket;

      int err = GetLastError();
      Print(EA_NAME, " OrderSend echec err=", err, " tentative=", (i+1), "/", MAX_RETRIES);

      if(err == ERR_TRADE_DISABLED || err == ERR_MARKET_CLOSED ||
         err == ERR_NOT_ENOUGH_MONEY || err == ERR_INVALID_TRADE_VOLUME)
      {
         return -1;
      }
      if(err == ERR_OFF_QUOTES || err == ERR_REQUOTE || err == ERR_PRICE_CHANGED)
      {
         Sleep(500);
         continue;
      }
      Sleep(500);
   }
   return -1;
}

//============================================================
//  TRAILING STOP DU SECOND ORDRE
//============================================================
void ManageTrailingStop()
{
   if(!g_tp1Filled && g_ticketTP1 > 0)
   {
      bool stillOpen = false;
      if(OrderSelect(g_ticketTP1, SELECT_BY_TICKET))
      {
         if(OrderCloseTime() == 0) stillOpen = true;
      }
      if(!stillOpen)
      {
         g_tp1Filled = true;
         Print(EA_NAME, " TP1 atteint, activation du trailing sur ticket=", g_ticketTrail);
      }
   }

   if(!g_tp1Filled) return;
   if(g_ticketTrail <= 0) return;

   if(!OrderSelect(g_ticketTrail, SELECT_BY_TICKET)) return;
   if(OrderCloseTime() > 0) return;
   if(OrderSymbol() != _Symbol || OrderMagicNumber() != MagicNumber) return;

   double trailDistPrice = (g_oprHigh - g_oprLow) * TrailMultiplier;
   if(trailDistPrice <= 0) return;

   double curSL   = OrderStopLoss();
   double newSL   = curSL;
   int    type    = OrderType();
   bool   improve = false;

   if(type == OP_BUY)
   {
      double target = Bid - trailDistPrice;
      if(target > curSL + _Point)
      {
         newSL   = NormalizeDouble(target, _Digits);
         improve = true;
      }
   }
   else if(type == OP_SELL)
   {
      double target = Ask + trailDistPrice;
      if(curSL == 0.0 || target < curSL - _Point)
      {
         newSL   = NormalizeDouble(target, _Digits);
         improve = true;
      }
   }

   if(improve)
   {
      if(!OrderModify(g_ticketTrail, OrderOpenPrice(), newSL,
                      OrderTakeProfit(), 0, clrYellow))
      {
         Print(EA_NAME, " OrderModify trailing err=", GetLastError());
      }
   }
}

//============================================================
//  FERMETURE EOD
//============================================================
void CheckEODClose()
{
   if(g_eodClosed) return;
   datetime now = TimeCurrent();
   datetime eod = SessionEndTime();
   if(now < eod) return;
   CloseAllPositions("EOD force");
   g_eodClosed = true;
}

void CloseAllPositions(string reason)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != _Symbol) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      RefreshRates();
      double price = (type == OP_BUY) ? Bid : Ask;
      bool ok = OrderClose(OrderTicket(), OrderLots(), price, SLIPPAGE_POINTS, clrYellow);
      if(!ok)
         Print(EA_NAME, " OrderClose err=", GetLastError(), " reason=", reason);
      else
         Print(EA_NAME, " Position fermee (", reason, ") ticket=", OrderTicket());
   }
}

//============================================================
//  P&L ET RECUPERATION DE L'ETAT
//============================================================
double ComputeOpenPnL()
{
   double pnl = 0.0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != _Symbol) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      pnl += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return pnl;
}

void RecoverState()
{
   datetime today = ComputeDayStart();
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != _Symbol) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      string cmt = OrderComment();
      if(StringFind(cmt, COMMENT_TP1) >= 0)
      {
         g_ticketTP1  = OrderTicket();
         g_currentDir = (type == OP_BUY) ? +1 : -1;
         g_entryPrice = OrderOpenPrice();
         g_slPrice    = OrderStopLoss();
         g_tp1Price   = OrderTakeProfit();
         if(OrderOpenTime() >= today) g_tradeTakenToday = true;
      }
      else if(StringFind(cmt, COMMENT_TRAIL) >= 0)
      {
         g_ticketTrail = OrderTicket();
         if(g_currentDir == 0) g_currentDir = (type == OP_BUY) ? +1 : -1;
         if(OrderOpenTime() >= today) g_tradeTakenToday = true;
      }
   }
   if(g_ticketTrail > 0 && g_ticketTP1 < 0)
      g_tp1Filled = true;
   if(g_tradeTakenToday)
      Print(EA_NAME, " Etat recupere : tradeTakenToday=true, TP1=", g_ticketTP1, " Trail=", g_ticketTrail);
}

//============================================================
//  DASHBOARD
//============================================================
void DrawDashboard()
{
   if(!ShowDashboard) { Comment(""); return; }
   string nl = "\n";
   string s = "";
   s += "================ " + EA_NAME + " v" + EA_VERSION + " ================" + nl;
   s += "Instrument : " + EA_INSTRUMENT + "  (" + _Symbol + ")" + nl;
   s += "Heure srv  : " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + nl;
   s += "Etat       : " + g_state + nl;
   s += "-----------------------------------------------" + nl;

   if(g_rangeBuilt || g_oprHigh > 0)
   {
      s += "OPR High   : " + DoubleToStr(g_oprHigh, _Digits) + nl;
      s += "OPR Low    : " + DoubleToStr(g_oprLow,  _Digits) + nl;
      s += "Range      : " + DoubleToStr(g_rangeSizeUnits, 1) + " points" + nl;
      s += "Range OK   : " + ((g_rangeSizeUnits >= MinRangeSize && g_rangeSizeUnits <= MaxRangeSize) ?
                              "YES" : "NO (" + DoubleToStr(MinRangeSize,0) + "-" +
                              DoubleToStr(MaxRangeSize,0) + ")") + nl;
   }
   else
   {
      s += "OPR        : non construit" + nl;
   }
   s += "-----------------------------------------------" + nl;

   if(g_tradeTakenToday)
   {
      string dirStr = (g_currentDir > 0) ? "LONG" : (g_currentDir < 0 ? "SHORT" : "?");
      double pnl    = ComputeOpenPnL();
      s += "Direction  : " + dirStr + nl;
      s += "Entree     : " + DoubleToStr(g_entryPrice, _Digits) + nl;
      s += "SL         : " + DoubleToStr(g_slPrice,    _Digits) + nl;
      s += "TP1        : " + DoubleToStr(g_tp1Price,   _Digits) + nl;
      s += "Lot1/Lot2  : " + DoubleToStr(g_initialLot1, 2) + " / " +
                            DoubleToStr(g_initialLot2, 2) + nl;
      s += "TP1 hit    : " + (g_tp1Filled ? "YES (trailing actif)" : "NO") + nl;
      s += "P&L open   : " + DoubleToStr(pnl, 2) + " " + AccountCurrency() + nl;
   }
   else
   {
      s += "Position   : aucune" + nl;
      if(IsFridayBlocked())  s += "BLOQUE     : Vendredi" + nl;
      if(IsNewsDay())        s += "BLOQUE     : News day (" + NewsDate + ")" + nl;
      if(!IsSpreadOK())      s += "BLOQUE     : Spread " +
                                  DoubleToStr(MarketInfo(_Symbol, MODE_SPREAD), 0) +
                                  " > " + IntegerToString(MaxSpreadPoints) + nl;
   }
   s += "-----------------------------------------------" + nl;
   s += "Trades jour: " + IntegerToString(g_tradesToday) + nl;
   s += "P&L jour   : " + DoubleToStr(g_pnlToday + ComputeOpenPnL(), 2) + " " + AccountCurrency() + nl;
   s += "Risque %   : " + DoubleToStr(RiskPercent, 2) + nl;
   s += "Magic      : " + IntegerToString(MagicNumber) + nl;
   Comment(s);
}

//============================================================
//  JOURNALISATION
//============================================================
void LogTrade(int op, double lot1, double lot2, double entry, double sl, double tp1)
{
   string dirStr = (op == OP_BUY) ? "LONG" : "SHORT";
   string ts     = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string msg    = ts + " | " + _Symbol + " | " + dirStr +
                   " | lot1=" + DoubleToStr(lot1, 2) +
                   " lot2=" + DoubleToStr(lot2, 2) +
                   " | entry=" + DoubleToStr(entry, _Digits) +
                   " | SL=" + DoubleToStr(sl, _Digits) +
                   " | TP1=" + DoubleToStr(tp1, _Digits) +
                   " | range=" + DoubleToStr(g_rangeSizeUnits, 1) + " points" +
                   " | ATR_M5=" + DoubleToStr(g_atrM5AtEntry, _Digits);
   Print(EA_NAME, " TRADE OPENED >>> ", msg);
}

void LogBlocked(string reason)
{
   Print(EA_NAME, " TRADE BLOQUE : ", reason);
   g_blockReason = reason;
}
