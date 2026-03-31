//+------------------------------------------------------------------+
//|                                          AccountExporter_EA.mq4  |
//|                              Dashboard Trading - Julien Barange  |
//|                              Exporte les données compte en JSON  |
//+------------------------------------------------------------------+
#property copyright "Julien Barange - Trading Dashboard"
#property link      ""
#property version   "1.0"
#property strict

// ============================================================
// PARAMETRES
// ============================================================
extern int    ExportIntervalSeconds = 10;     // Intervalle export (secondes)
extern string AccountAlias         = "";      // Nom du compte (ex: "RoboForex #1")
extern string SharedExportPath     = "C:\\TradingDashboard\\data\\"; // Dossier partagé
extern bool   UseSharedPath        = true;    // Utiliser le dossier partagé
extern bool   DebugMode            = false;   // Logs debug

datetime lastExport = 0;
string exportFilename = "";

//+------------------------------------------------------------------+
int OnInit()
{
   if(AccountAlias == "")
      AccountAlias = "Account_" + IntegerToString(AccountNumber());

   exportFilename = "dashboard_" + IntegerToString(AccountNumber()) + ".json";

   Print("=== AccountExporter EA ===");
   Print("Compte: ", AccountAlias, " (#", AccountNumber(), ")");
   Print("Export: toutes les ", ExportIntervalSeconds, "s");
   Print("Fichier: ", exportFilename);

   // Premier export immédiat
   ExportAccountData();
   EventSetTimer(ExportIntervalSeconds);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("AccountExporter EA arrêté pour ", AccountAlias);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   ExportAccountData();
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(TimeCurrent() - lastExport >= ExportIntervalSeconds)
      ExportAccountData();
}

//+------------------------------------------------------------------+
string EscapeJSON(string s)
{
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\n", "\\n");
   StringReplace(s, "\r", "\\r");
   StringReplace(s, "\t", "\\t");
   return s;
}

//+------------------------------------------------------------------+
void ExportAccountData()
{
   int handle = INVALID_HANDLE;

   if(UseSharedPath && StringLen(SharedExportPath) > 0)
   {
      // Export vers dossier partagé (hors sandbox MT4)
      string fullPath = SharedExportPath + exportFilename;
      handle = FileOpen(fullPath, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(handle == INVALID_HANDLE)
      {
         // Fallback: essayer en mode commun
         handle = FileOpen(exportFilename, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      }
   }
   else
   {
      handle = FileOpen(exportFilename, FILE_WRITE|FILE_TXT|FILE_ANSI);
   }

   if(handle == INVALID_HANDLE)
   {
      Print("ERREUR: Impossible d'ouvrir ", exportFilename, " - Error: ", GetLastError());
      return;
   }

   // ============================================================
   // INFOS COMPTE
   // ============================================================
   double balance    = AccountBalance();
   double equity     = AccountEquity();
   double margin     = AccountMargin();
   double freeMargin = AccountFreeMargin();
   double marginLvl  = margin > 0 ? (equity / margin) * 100.0 : 0;
   double floatingPL = equity - balance;

   double dailyPL    = CalculateDailyPL();
   double monthlyPL  = CalculateMonthlyPL();
   double weeklyPL   = CalculateWeeklyPL();

   double maxBalance = GetMaxHistoricalBalance();
   double drawdown   = maxBalance > 0 ? ((maxBalance - equity) / maxBalance) * 100.0 : 0;
   if(drawdown < 0) drawdown = 0;

   double initialDeposit = GetInitialDeposit();
   double totalProfit    = balance - initialDeposit + floatingPL;
   double profitability  = initialDeposit > 0 ? (totalProfit / initialDeposit) * 100.0 : 0;

   // ============================================================
   // JSON
   // ============================================================
   string json = "{\n";
   json += "  \"accountId\": " + IntegerToString(AccountNumber()) + ",\n";
   json += "  \"alias\": \"" + EscapeJSON(AccountAlias) + "\",\n";
   json += "  \"broker\": \"" + EscapeJSON(AccountCompany()) + "\",\n";
   json += "  \"server\": \"" + EscapeJSON(AccountServer()) + "\",\n";
   json += "  \"currency\": \"" + AccountCurrency() + "\",\n";
   json += "  \"leverage\": " + IntegerToString(AccountLeverage()) + ",\n";
   json += "  \"balance\": " + DoubleToString(balance, 2) + ",\n";
   json += "  \"equity\": " + DoubleToString(equity, 2) + ",\n";
   json += "  \"margin\": " + DoubleToString(margin, 2) + ",\n";
   json += "  \"freeMargin\": " + DoubleToString(freeMargin, 2) + ",\n";
   json += "  \"marginLevel\": " + DoubleToString(marginLvl, 1) + ",\n";
   json += "  \"floatingPL\": " + DoubleToString(floatingPL, 2) + ",\n";
   json += "  \"dailyPL\": " + DoubleToString(dailyPL, 2) + ",\n";
   json += "  \"weeklyPL\": " + DoubleToString(weeklyPL, 2) + ",\n";
   json += "  \"monthlyPL\": " + DoubleToString(monthlyPL, 2) + ",\n";
   json += "  \"drawdown\": " + DoubleToString(drawdown, 2) + ",\n";
   json += "  \"profitability\": " + DoubleToString(profitability, 2) + ",\n";
   json += "  \"initialDeposit\": " + DoubleToString(initialDeposit, 2) + ",\n";
   json += "  \"totalProfit\": " + DoubleToString(totalProfit, 2) + ",\n";
   json += "  \"lastUpdate\": \"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\",\n";
   json += "  \"serverTime\": \"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\",\n";
   json += "  \"localTime\": \"" + TimeToString(TimeLocal(), TIME_DATE|TIME_SECONDS) + "\",\n";

   // ============================================================
   // POSITIONS OUVERTES
   // ============================================================
   json += "  \"positions\": [\n";

   int totalOrders = OrdersTotal();
   bool firstOrder = true;

   for(int i = 0; i < totalOrders; i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderType() > OP_SELL) continue;

      if(!firstOrder) json += ",\n";
      firstOrder = false;

      string type = OrderType() == OP_BUY ? "BUY" : "SELL";
      double currentPrice = OrderType() == OP_BUY
         ? MarketInfo(OrderSymbol(), MODE_BID)
         : MarketInfo(OrderSymbol(), MODE_ASK);

      int digits = (int)MarketInfo(OrderSymbol(), MODE_DIGITS);
      double point = MarketInfo(OrderSymbol(), MODE_POINT);
      double pips = 0;

      if(point > 0)
      {
         double pipSize = (digits == 3 || digits == 5) ? point * 10 : point;
         pips = OrderType() == OP_BUY
            ? (currentPrice - OrderOpenPrice()) / pipSize
            : (OrderOpenPrice() - currentPrice) / pipSize;
      }

      double netProfit = OrderProfit() + OrderSwap() + OrderCommission();

      json += "    {\n";
      json += "      \"ticket\": " + IntegerToString(OrderTicket()) + ",\n";
      json += "      \"symbol\": \"" + OrderSymbol() + "\",\n";
      json += "      \"type\": \"" + type + "\",\n";
      json += "      \"lots\": " + DoubleToString(OrderLots(), 2) + ",\n";
      json += "      \"openPrice\": " + DoubleToString(OrderOpenPrice(), digits) + ",\n";
      json += "      \"currentPrice\": " + DoubleToString(currentPrice, digits) + ",\n";
      json += "      \"pips\": " + DoubleToString(pips, 1) + ",\n";
      json += "      \"profit\": " + DoubleToString(OrderProfit(), 2) + ",\n";
      json += "      \"netProfit\": " + DoubleToString(netProfit, 2) + ",\n";
      json += "      \"swap\": " + DoubleToString(OrderSwap(), 2) + ",\n";
      json += "      \"commission\": " + DoubleToString(OrderCommission(), 2) + ",\n";
      json += "      \"sl\": " + DoubleToString(OrderStopLoss(), digits) + ",\n";
      json += "      \"tp\": " + DoubleToString(OrderTakeProfit(), digits) + ",\n";
      json += "      \"openTime\": \"" + TimeToString(OrderOpenTime(), TIME_DATE|TIME_SECONDS) + "\",\n";
      json += "      \"magicNumber\": " + IntegerToString(OrderMagicNumber()) + ",\n";
      json += "      \"comment\": \"" + EscapeJSON(OrderComment()) + "\"\n";
      json += "    }";
   }

   json += "\n  ],\n";

   // ============================================================
   // ORDRES PENDING
   // ============================================================
   json += "  \"pendingOrders\": [\n";
   bool firstPending = true;

   for(int i = 0; i < totalOrders; i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderType() <= OP_SELL) continue; // Skip market orders

      if(!firstPending) json += ",\n";
      firstPending = false;

      string pendType = "";
      switch(OrderType())
      {
         case OP_BUYLIMIT:  pendType = "BUY_LIMIT"; break;
         case OP_SELLLIMIT: pendType = "SELL_LIMIT"; break;
         case OP_BUYSTOP:   pendType = "BUY_STOP"; break;
         case OP_SELLSTOP:  pendType = "SELL_STOP"; break;
      }

      int d = (int)MarketInfo(OrderSymbol(), MODE_DIGITS);
      json += "    {\"ticket\": " + IntegerToString(OrderTicket());
      json += ", \"symbol\": \"" + OrderSymbol() + "\"";
      json += ", \"type\": \"" + pendType + "\"";
      json += ", \"lots\": " + DoubleToString(OrderLots(), 2);
      json += ", \"price\": " + DoubleToString(OrderOpenPrice(), d);
      json += ", \"sl\": " + DoubleToString(OrderStopLoss(), d);
      json += ", \"tp\": " + DoubleToString(OrderTakeProfit(), d) + "}";
   }

   json += "\n  ]\n";
   json += "}";

   FileWriteString(handle, json);
   FileClose(handle);

   lastExport = TimeCurrent();

   if(DebugMode)
      Print("Export OK: ", AccountAlias, " | Bal: ", DoubleToString(balance, 2),
            " | Eq: ", DoubleToString(equity, 2),
            " | Pos: ", totalOrders, " | DD: ", DoubleToString(drawdown, 1), "%");
}

//+------------------------------------------------------------------+
double CalculatePLFromDate(datetime fromDate)
{
   double pl = 0;

   // Trades fermés depuis fromDate
   int total = OrdersHistoryTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderCloseTime() < fromDate) break;
      if(OrderType() > OP_SELL) continue;
      pl += OrderProfit() + OrderSwap() + OrderCommission();
   }

   // Floating actuel
   int openTotal = OrdersTotal();
   for(int i = 0; i < openTotal; i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderType() > OP_SELL) continue;
      pl += OrderProfit() + OrderSwap() + OrderCommission();
   }

   return pl;
}

//+------------------------------------------------------------------+
double CalculateDailyPL()
{
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   return CalculatePLFromDate(today);
}

//+------------------------------------------------------------------+
double CalculateWeeklyPL()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int dayOfWeek = dt.day_of_week;
   if(dayOfWeek == 0) dayOfWeek = 7; // Dimanche = 7
   datetime weekStart = StringToTime(TimeToString(TimeCurrent() - (dayOfWeek - 1) * 86400, TIME_DATE));
   return CalculatePLFromDate(weekStart);
}

//+------------------------------------------------------------------+
double CalculateMonthlyPL()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.day = 1; dt.hour = 0; dt.min = 0; dt.sec = 0;
   return CalculatePLFromDate(StructToTime(dt));
}

//+------------------------------------------------------------------+
double GetMaxHistoricalBalance()
{
   double maxBal = AccountBalance();
   int total = OrdersHistoryTotal();
   double runningBal = AccountBalance();

   for(int i = total - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderType() > OP_SELL) continue;
      runningBal -= (OrderProfit() + OrderSwap() + OrderCommission());
   }

   double bal = runningBal;
   maxBal = bal;
   for(int i = 0; i < total; i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderType() > OP_SELL) continue;
      bal += OrderProfit() + OrderSwap() + OrderCommission();
      if(bal > maxBal) maxBal = bal;
   }

   return maxBal;
}

//+------------------------------------------------------------------+
double GetInitialDeposit()
{
   int total = OrdersHistoryTotal();
   for(int i = 0; i < total; i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderType() == 6 && OrderProfit() > 0)
         return OrderProfit();
   }
   return AccountBalance();
}
//+------------------------------------------------------------------+
