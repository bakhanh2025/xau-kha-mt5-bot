//+------------------------------------------------------------------+
//| Expert Advisor: XAUUSD Strategy based on Candle Color & SLTP    |
//| Author: ChatGPT                                                  |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

input double SLTP_USD_Base    = 30;      // Origin volume
input double TP_USD_Increase  = 10;    // Increase volume
input int BUF_SL_PIP          = 200;           // SL/TP by pip (1 pip = 0.01)
input int MAX_SLTP_PIP        = 1000;        // SL/TP by pip (1 pip = 0.01)
input string SYMBOL           = "XAUUSDm";
input double PRICE_BETWEEN_OC = 3;
input bool IS_SEND_TELEGRAM   = false;

double pip_value              = 0.01;
double sltp_value             = SLTP_USD_Base; // volume cơ bản
string telegramUrl            = "https://script.google.com/macros/s/AKfycbxQdMRbz4ZS8ja_sbGwk6pZRuLocyLuZ4rinLEFk5SMpG6Q4WgfARaXdpYi0ij6SWTT/exec";
   
//+------------------------------------------------------------------+
int OnInit()
  {
   EventSetTimer(30);  // Check per sec
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   CheckCloseByTime();
   
   if(PositionSelect(SYMBOL)) return; // Already has a position
   
   if(!IsEntryAllowed()) 
      return;

   // --- Điều kiện mới đa khung thời gian ---
   double openPrevH1 = iOpen(SYMBOL, PERIOD_H1, 1);
   double closePrevH1 = iClose(SYMBOL, PERIOD_H1, 1);
   
   // Giá mở/đóng nến hiện tại các khung
   double openM1 = iOpen(SYMBOL, PERIOD_M1, 0);
   double closeM1 = iClose(SYMBOL, PERIOD_M1, 0);
   
   double openM5 = iOpen(SYMBOL, PERIOD_M5, 0);
   double closeM5 = iClose(SYMBOL, PERIOD_M5, 0);
   
   double openM15 = iOpen(SYMBOL, PERIOD_M15, 0);
   double closeM15 = iClose(SYMBOL, PERIOD_M15, 0);
   
   double openM30 = iOpen(SYMBOL, PERIOD_M30, 0);
   double closeM30 = iClose(SYMBOL, PERIOD_M30, 0);
   
   double openH1 = iOpen(SYMBOL, PERIOD_H1, 0);
   double closeH1 = iClose(SYMBOL, PERIOD_H1, 0);
   
   // Xác định điều kiện BUY
   bool buyCondition = ((closePrevH1 - openPrevH1) >= PRICE_BETWEEN_OC &&
       (closeM1 > openM1) &&    // M1 xanh
       (closeM5 > openM5) &&    // M5 xanh
       (closeM15 < openM15) &&  // M15 đỏ
       (closeM30 < openM30) &&  // M30 đỏ
       (closeH1 < openH1));     // H1 hiện tại đỏ
   
   // Xác định điều kiện SELL
   bool sellCondition = ((openPrevH1 - closePrevH1) >= PRICE_BETWEEN_OC &&
       (closeM1 < openM1) &&    // M1 đỏ
       (closeM5 < openM5) &&    // M5 đỏ
       (closeM15 > openM15) &&  // M15 xanh
       (closeM30 > openM30) &&  // M30 xanh
       (closeH1 > openH1));     // H1 hiện tại xanh
   
   if(!(buyCondition || sellCondition)) return;

   double price;
   if(!SymbolInfoDouble(SYMBOL, buyCondition ? SYMBOL_ASK : SYMBOL_BID, price)) {
      Print("Could not get market price");
      return;
   }
   
   double sl_price, tp_price;
   int digits = (int)SymbolInfoInteger(SYMBOL, SYMBOL_DIGITS);

   if(buyCondition) {
      sl_price = GetSLPrice(SYMBOL, "buy", price);
      tp_price = GetTPPrice(SYMBOL, "buy", price, sl_price);
      double volume = CalculateLotFromUSD(sltp_value);
      trade.SetDeviationInPoints(30);
      trade.Buy(volume, SYMBOL, price, sl_price, tp_price, "AutoBuy");
      
      string msg = FormatTradeMessage("BUY", volume, price, sl_price, tp_price);
      SendTelegramMessage(msg);
   }
   else if(sellCondition){
      sl_price = GetSLPrice(SYMBOL, "sell", price);
      tp_price = GetTPPrice(SYMBOL, "sell", price, sl_price);
      double volume = CalculateLotFromUSD(sltp_value);
      trade.SetDeviationInPoints(30);
      trade.Sell(volume, SYMBOL, price, sl_price, tp_price, "AutoSell");
      
      string msg = FormatTradeMessage("SELL", volume, price, sl_price, tp_price);
      SendTelegramMessage(msg);
   }
  }

double CalculateLotFromUSD(double riskUsd)
{
   return NormalizeDouble(riskUsd / 1000, 2);
}

double GetSLPrice(string symbol, string direction, double entry_price)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   double prev_high = iHigh(symbol, PERIOD_H1, 1);
   double prev_low  = iLow(symbol, PERIOD_H1, 1);

   double sl_price;
   int sl_pip;

   if(direction == "buy")
   {
      double raw_sl = prev_low - BUF_SL_PIP * pip_value;
      sl_pip = int((entry_price - raw_sl) / pip_value);
      if(sl_pip > MAX_SLTP_PIP) sl_pip = MAX_SLTP_PIP;
      sl_price = NormalizeDouble(entry_price - sl_pip * pip_value, digits);
   }
   else
   {
      double raw_sl = prev_high + BUF_SL_PIP * pip_value;
      sl_pip = int((raw_sl - entry_price) / pip_value);
      if(sl_pip > MAX_SLTP_PIP) sl_pip = MAX_SLTP_PIP;
      sl_price = NormalizeDouble(entry_price + sl_pip * pip_value, digits);
   }

   return sl_price;
}

double GetTPPrice(string symbol, string direction, double entry_price, double sl_price)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double distance = MathAbs(entry_price - sl_price);
   double tp_distance = distance * 1.5; // TP = SL * 1.5
   double tp_price;

   if(direction == "buy")
   {
      tp_price = NormalizeDouble(entry_price + tp_distance, digits);
   }
   else
   {
      tp_price = NormalizeDouble(entry_price - tp_distance, digits);
   }
   return tp_price;
}

int GetSessionFromTime(int hour, int minute)
{
   // Returns: 1=Asia,2=Europe,3=US,0=none
   // Entry windows:
   // Asia: 07:05 - 09:05
   // Europe: 13:05 - 15:05
   // US: 19:05 - 21:05
   // No trading: 01:00 - 07:00

   // No trading period
   if(hour >= 1 && hour < 7)
      return 0;

   // Asia session 07:05 - 09:05
   if((hour == 7 && minute >= 5) || (hour > 7 && hour < 9) || (hour == 9 && minute <= 5))
      return 1;

   // Europe session 13:05 - 15:05
   if((hour == 13 && minute >= 5) || (hour > 13 && hour < 15) || (hour == 15 && minute <= 5))
      return 2;

   // US session 19:05 - 21:05
   if((hour == 19 && minute >= 5) || (hour > 19 && hour < 21) || (hour == 21 && minute <= 5))
      return 3;

   return 0;
}

void CheckCloseByTime()
{
   // Close open positions if they passed their session forced close time
   if(PositionSelect(SYMBOL))
   {
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      MqlDateTime dtOpen; TimeToStruct(open_time, dtOpen);
      MqlDateTime dtNow; TimeToStruct(TimeVietNamAuto(), dtNow);
      
      int session = GetSessionFromTime(dtOpen.hour, dtOpen.min);
      if(session == 0) return; // unknown session

      // compute forced close datetime
      datetime forcedClose = 0;
      datetime now = TimeVietNamAuto();
      MqlDateTime fc; TimeToStruct(now, fc); // base on today, adjust if needed

      if(session == 1) { // Asian: forced close 12:45 same day
         fc.hour = 12; fc.min = 45; fc.sec = 0;
         forcedClose = StructToTime(fc);
      } else if(session == 2) { // Europe: 18:45 same day
         fc.hour = 18; fc.min = 45; fc.sec = 0;
         forcedClose = StructToTime(fc);
      } else if(session == 3) { // US: forced close 00:45 next day
         // build next day 00:45
         datetime base = now - (dtNow.hour*3600 + dtNow.min*60 + dtNow.sec);
         forcedClose = base + 24*3600 + 45*60; // next day 00:45
      }

      if(TimeVietNamAuto() >= forcedClose)
      {
         double vol = PositionGetDouble(POSITION_VOLUME);
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         // attempt close by market opposite
         bool closed = false;
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            closed = trade.PositionClose(ticket);
         else
            closed = trade.PositionClose(ticket);

         if(closed) Print("Position closed by forced session close at ", TimeToString(TimeVietNamAuto()));
      }
   }
}

bool IsEntryAllowed()
{
   MqlDateTime dt; TimeToStruct(TimeVietNamAuto(), dt);
   if(dt.hour >=1 && dt.hour <7) return false;
   if(GetSessionFromTime(dt.hour, dt.min) != 0) return true;
   return false;
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
      if(!HistoryDealSelect(trans.deal)) return;
      
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      string symbol = trans.symbol;
      
      if(profit > 0) {
         sltp_value += TP_USD_Increase;
         
         string msg = FormatProfitMessage("WIN", profit);
         Print("Send profit message: " + msg);
         SendTelegramMessage(msg);
      }
      else if(profit < 0) {
         sltp_value = SLTP_USD_Base;
         string msg = FormatProfitMessage("LOST", profit);
         Print("Send profit message: " + msg);
         SendTelegramMessage(msg);
      }
   }
}

string FormatTradeMessage(string type, double vol, double price, double sl, double tp)
{
   string account = GetFormattedAccountInfo();
   string emoji = (type == "BUY") ? "🟢" : "🔴";
   string msg = emoji + " " + account + " " + type + " XAUUSD\n";
   msg += "Lot: " + DoubleToString(vol, 2) + "\n";
   msg += "Giá: " + DoubleToString(price, 2) + "\n";
   msg += "TP: " + DoubleToString(tp, 2) + "\n";
   msg += "SL: " + DoubleToString(sl, 2);
   return msg;
}

string FormatProfitMessage(string type, double profit)
{
   string account = GetFormattedAccountInfo();
   string emoji = (type == "WIN") ? "✅" : "❌";
   string msg = emoji + " " + account + " " + type + " " + DoubleToString(profit, 2) + " USD";
   return msg;
}

void SendTelegramMessage(string message)
{
   if(!IS_SEND_TELEGRAM) return;
   
   string encodedMessage = message;
   StringReplace(encodedMessage, " ", "%20");
   StringReplace(encodedMessage, "!", "%21");
   StringReplace(encodedMessage, ":", "%3A");
   StringReplace(encodedMessage, "&", "%26");
   StringReplace(encodedMessage, "\n", "%0A");

   string fullUrl = telegramUrl + "?msg=" + encodedMessage;

   uchar postData[]; // rỗng vì là GET
   uchar result[];
   string headers = "";
   string cookies = "";
   string resultHeaders = "";
   int timeout = 5000;

   ResetLastError();
   int res = WebRequest("GET", fullUrl, headers, cookies, timeout, postData, 0, result, resultHeaders);
   if (res == -1)
   {
      Print("❌ Gửi Telegram thất bại. Lỗi: ", GetLastError());
   }
   else
   {
      string response = CharArrayToString(result);
      Print("✅ Telegram phản hồi: ", response);
   }
}

string GetFormattedAccountInfo()
{
   long id = AccountInfoInteger(ACCOUNT_LOGIN);
   return "Account " + IntegerToString(id) + ": ";
}

int GetServerGMTOffset()
{
   datetime utc = TimeGMT();
   datetime server = TimeTradeServer();
   return (int)((server - utc) / 3600);
}

datetime TimeVietNamAuto()
{
   int diff = 7 - GetServerGMTOffset();
   return TimeTradeServer() + diff * 3600;
}