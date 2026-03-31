//+------------------------------------------------------------------+
//|                                          AccountExporter_EA.mq4  |
//|                              Dashboard Trading - Julien Barange  |
//|                              Exporte les données compte en JSON  |
//+------------------------------------------------------------------+
#property copyright "Julien Barange - Trading Dashboard"
#property link      ""
#property version   "2.1"
#property strict

// ============================================================
// PARAMETRES
// ============================================================
extern int    ExportIntervalSeconds = 10;
extern string AccountAlias         = "";
extern string SharedExportPath     = "C:\\TradingDashboard\\data\\";
extern bool   UseSharedPath        = true;
extern bool   DebugMode            = false;

datetime lastExport = 0;
string exportFilename = "";

//+------------------------------------------------------------------+
int OnInit()
{
   if(AccountAlias == "")
      AccountAlias = "Account_" + IntegerToString(AccountNumber());

   exportFilename = "dashboard_" + IntegerToString(AccountNumber()) + ".json";

   Print("=== AccountExporter EA v2.1 ===");
   Print("Compte: ", AccountAlias, " (#", AccountNumber(), ")");
   Print("Export: toutes les ", ExportIntervalSeconds, "s");

   ExportAccountData();
   EventSetTimer(ExportIntervalSeconds);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
void OnTimer() { ExportAccountData(); }
void OnTick()  { if(TimeCurrent() - lastExport >= ExportIntervalSeconds) ExportAccountData(); }

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
      string fullPath = SharedExportPath + exportFilename;
      handle = FileOpen(fullPath, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(handle == INVALID_HANDLE)
         handle = FileOpen(exportFilename, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   }
   else
      handle = FileOpen(exportFilename, FILE_WRITE|FILE_TXT|FILE_ANSI);

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

   // ============================================================
   // PROFITS ENCAISSES (trades fermés uniquement)
   // ============================================================
   double dailyProfit   = CalculateRealizedPL(GetStartOfDay());
   double monthlyProfit = CalculateRealizedPL(GetStartOfMonth());
   double yearlyProfit  = CalculateRealizedPL(GetStartOfYear2026());

   // ============================================================
   // FLOATING = encours des positions ouvertes (positif ou négatif)
   // floatingPct = floating / balance * 100
   // ============================================================
   double floatingPct = balance > 0 ? (floatingPL / balance) * 100.0 : 0;

   // ============================================================
   // RENDEMENTS EN %
   // ============================================================
   double balStartDay   = balance - dailyProfit;
   double balStartMonth = balance - monthlyProfit;
   double balStartYear  = balance - yearlyProfit;

   double dailyReturnPct   = balStartDay > 0   ? (dailyProfit / balStartDay) * 100.0 : 0;
   double monthlyReturnPct = balStartMonth > 0  ? (monthlyProfit / balStartMonth) * 100.0 : 0;
   double yearlyReturnPct  = balStartYear > 0   ? (yearlyProfit / balStartYear) * 100.0 : 0;

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
   json += "  \"dailyProfit\": " + DoubleToString(dailyProfit, 2) + ",\n";
   json += "  \"monthlyProfit\": " + DoubleToString(monthlyProfit, 2) + ",\n";
   json += "  \"yearlyProfit\": " + DoubleToString(yearlyProfit, 2) + ",\n";
   json += "  \"dailyReturnPct\": " + DoubleToString(dailyReturnPct, 2) + ",\n";
   json += "  \"monthlyReturnPct\": " + DoubleToString(monthlyReturnPct, 2) + ",\n";
   json += "  \"yearlyReturnPct\": " + DoubleToString(yearlyReturnPct, 2) + ",\n";
   json += "  \"floatingPct\": " + DoubleToString(floatingPct, 2) + ",\n";
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
      if(OrderType() <= OP_SELL) continue;

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
      Print("Export OK: ", AccountAlias,
            " | Bal: ", DoubleToString(balance, 2),
            " | Float: ", DoubleToString(floatingPL, 2),
            " | Float: ", DoubleToString(floatingPct, 1), "%",
            " | Jour: ", DoubleToString(dailyProfit, 2),
            " | Mois: ", DoubleToString(monthlyProfit, 2),
            " | An: ", DoubleToString(yearlyProfit, 2));
}

//+------------------------------------------------------------------+
// PROFIT ENCAISSE (trades fermés uniquement, SANS floating)
// Parcourt TOUT l'historique sans break pour ne rien rater
//+------------------------------------------------------------------+
double CalculateRealizedPL(datetime fromDate)
{
   double pl = 0;
   int total = OrdersHistoryTotal();

   for(int i = 0; i < total; i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderType() > OP_SELL) continue;
      if(OrderCloseTime() >= fromDate)
         pl += OrderProfit() + OrderSwap() + OrderCommission();
   }

   return pl;
}

//+------------------------------------------------------------------+
datetime GetStartOfDay()
{
   return StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
}

//+------------------------------------------------------------------+
datetime GetStartOfMonth()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.day = 1; dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
// Toujours depuis le 1er Janvier 2026
//+------------------------------------------------------------------+
datetime GetStartOfYear2026()
{
   return StringToTime("2026.01.01 00:00:00");
}
//+------------------------------------------------------------------+
