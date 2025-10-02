//+------------------------------------------------------------------+
//| Expert Advisor: XAUUSD Strategy based on Candle Color & SLTP    |
//| Author: ChatGPT                                                  |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

input double SLTP_USD_Base = 30;      // Origin volume
input double TP_USD_Increase = 10;    // Increase volume
input int BUF_SL_PIP = 200;           // SL/TP by pip (1 pip = 0.01)
input int MAX_SLTP_PIP = 1000;        // SL/TP by pip (1 pip = 0.01)
input string SYMBOL = "XAUUSD";
input double PRICE_BETWEEN_OC = 3;

double pip_value = 0.01;
double sltp_value       = SLTP_USD_Base; // volume cơ bản
double daily_profit     = 0;             // tổng profit trong ngày
int    current_day      = -1;            // theo dõi ngày hiện tại
bool volume_increased = false;

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
   
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int minute = dt.min;

   if(minute < 5 || minute > 35)
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
      tp_price = NormalizeDouble(price + MAX_SLTP_PIP * pip_value, digits);
      double volume = CalculateLotFromUSD(sltp_value);
      trade.SetDeviationInPoints(30);
      trade.Buy(volume, SYMBOL, price, sl_price, tp_price, "AutoBuy");
      
      string msg = FormatTradeMessage("BUY", volume, price, sl_price, tp_price);
      SendTelegramMessage(msg);
   }
   else if(sellCondition){
      sl_price = GetSLPrice(SYMBOL, "sell", price);
      double sl_pip = MathAbs(sl_price - price) / pip_value;
      tp_price = NormalizeDouble(price - MAX_SLTP_PIP * pip_value, digits);
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


void CheckCloseByTime()
{
   if(PositionSelect(SYMBOL))   // Kiểm tra có lệnh đang mở không
   {
      // Lấy thông tin lệnh
      datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
      // Thời gian hiện tại
      datetime now = TimeCurrent();
      MqlDateTime dtNow;
      TimeToStruct(now, dtNow);

      // Xác định cây H1 thứ 3 từ lúc vào lệnh
      datetime entryBarTime = entryTime - (entryTime % 3600); // thời gian bắt đầu cây H1 chứa entry
      datetime thirdBarTime = entryBarTime + 2 * 3600;        // cây thứ 3 (sau 2 giờ kể từ cây entry)

      // Nếu đang trong cây H1 thứ 3 và ở phút 4
      if(now >= thirdBarTime && now < thirdBarTime + 3600) // trong cây H1 thứ 3
      {
         if(dtNow.min >= 4)
         {
            if(trade.PositionClose(SYMBOL))
               Print("⏳ Đóng lệnh ", SYMBOL, " tại phút 04 của cây H1 thứ 3 từ lúc vào lệnh.");
            else
               Print("❌ Không thể đóng lệnh ", SYMBOL, ". Lỗi: ", GetLastError());
         }
      }
   }
}


//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
      if(!HistoryDealSelect(trans.deal)) return;

      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      datetime dealTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
      MqlDateTime dt;
      TimeToStruct(dealTime, dt);
      
      if(profit > 0) {
         string msg = FormatProfitMessage("WIN", profit);
         SendTelegramMessage(msg);
      }
      else if(profit < 0) {
         string msg = FormatProfitMessage("LOST", profit);
         SendTelegramMessage(msg);
      }
      
      // Nếu ngày mới thì reset profit ngày trước đó
      if(current_day != dt.day) {
         if(current_day != -1) { // bỏ qua lần đầu tiên
            if(daily_profit > 0) {
               if(!volume_increased) { // chỉ tăng 1 lần duy nhất
                  sltp_value += TP_USD_Increase;
                  volume_increased = true; // đánh dấu đã tăng rồi
                  Print("📈 Ngày ", current_day, " có lời: ", daily_profit,
                        " USD → tăng volume lên ", sltp_value);
               } else {
                  Print("📈 Ngày ", current_day, " có lời: ", daily_profit,
                        " USD → giữ nguyên volume ", sltp_value);
               }
            } else {
               Print("📉 Ngày ", current_day, " không lời (", daily_profit,
                     " USD) → reset volume về ", SLTP_USD_Base);
               sltp_value = SLTP_USD_Base;
               volume_increased = false; // cho phép tăng lại ở tương lai
            }
         }
      
         // reset cho ngày mới
         current_day  = dt.day;
         daily_profit = 0;
      }

      // cộng profit vào tổng ngày
      daily_profit += profit;

      PrintFormat("Deal #%I64d | %s | Profit=%.2f | Lũy kế ngày=%0.2f",
                  trans.deal, trans.symbol, profit, daily_profit);
   }
}
//+------------------------------------------------------------------+

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
   string baseUrl = "https://script.google.com/macros/s/AKfycbxQdMRbz4ZS8ja_sbGwk6pZRuLocyLuZ4rinLEFk5SMpG6Q4WgfARaXdpYi0ij6SWTT/exec";
   string encodedMessage = message;
   StringReplace(encodedMessage, " ", "%20");
   StringReplace(encodedMessage, "!", "%21");
   StringReplace(encodedMessage, ":", "%3A");
   StringReplace(encodedMessage, "&", "%26");
   StringReplace(encodedMessage, "\n", "%0A");

   string fullUrl = baseUrl + "?msg=" + encodedMessage;

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