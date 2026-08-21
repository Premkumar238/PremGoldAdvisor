//+------------------------------------------------------------------+
//| PGA_Errors.mqh — logging and trade error helpers                 |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor"
#property strict

#ifndef PGA_ERRORS_MQH
#define PGA_ERRORS_MQH

void PGA_LogInfo(const string msg)
{
   Print("[PGA V1.4][INFO] ", msg);
}

void PGA_LogWarn(const string msg)
{
   Print("[PGA V1.4][WARN] ", msg);
}

void PGA_LogError(const string msg)
{
   Print("[PGA V1.4][ERROR] ", msg, " | GetLastError=", IntegerToString(GetLastError()));
}

string PGA_TradeRetcodeDescription(const uint retcode)
{
   switch(retcode)
   {
      case TRADE_RETCODE_DONE:               return "Done";
      case TRADE_RETCODE_DONE_PARTIAL:       return "Done partial";
      case TRADE_RETCODE_REQUOTE:            return "Requote";
      case TRADE_RETCODE_REJECT:             return "Request rejected";
      case TRADE_RETCODE_CANCEL:             return "Request canceled";
      case TRADE_RETCODE_PLACED:             return "Order placed";
      case TRADE_RETCODE_ERROR:              return "Common error";
      case TRADE_RETCODE_TIMEOUT:            return "Timeout";
      case TRADE_RETCODE_INVALID:            return "Invalid request";
      case TRADE_RETCODE_INVALID_VOLUME:     return "Invalid volume";
      case TRADE_RETCODE_INVALID_PRICE:      return "Invalid price";
      case TRADE_RETCODE_INVALID_STOPS:      return "Invalid stops";
      case TRADE_RETCODE_TRADE_DISABLED:     return "Trade disabled";
      case TRADE_RETCODE_MARKET_CLOSED:      return "Market closed";
      case TRADE_RETCODE_NO_MONEY:           return "Insufficient margin";
      case TRADE_RETCODE_PRICE_CHANGED:      return "Price changed";
      case TRADE_RETCODE_PRICE_OFF:          return "No quotes";
      case TRADE_RETCODE_INVALID_EXPIRATION: return "Invalid expiration";
      case TRADE_RETCODE_ORDER_CHANGED:      return "Order state changed";
      case TRADE_RETCODE_TOO_MANY_REQUESTS:  return "Too many requests";
      case TRADE_RETCODE_NO_CHANGES:         return "No changes";
      case TRADE_RETCODE_SERVER_DISABLES_AT: return "Autotrading disabled by server";
      case TRADE_RETCODE_CLIENT_DISABLES_AT: return "Autotrading disabled by client";
      case TRADE_RETCODE_LOCKED:             return "Request locked";
      case TRADE_RETCODE_FROZEN:             return "Order/position frozen";
      case TRADE_RETCODE_INVALID_FILL:       return "Invalid fill type";
      case TRADE_RETCODE_CONNECTION:         return "No connection";
      case TRADE_RETCODE_ONLY_REAL:          return "Only real accounts allowed";
      case TRADE_RETCODE_LIMIT_ORDERS:       return "Order limit reached";
      case TRADE_RETCODE_LIMIT_VOLUME:       return "Volume limit reached";
      case TRADE_RETCODE_POSITION_CLOSED:    return "Position already closed";
      case TRADE_RETCODE_INVALID_ORDER:      return "Invalid order";
      case TRADE_RETCODE_CLOSE_ORDER_EXIST:  return "Close order already exists";
      case TRADE_RETCODE_LIMIT_POSITIONS:    return "Position limit reached";
      default:                               return "Retcode " + IntegerToString((int)retcode);
   }
}

void PGA_LogTradeResult(const string context, const MqlTradeResult &result)
{
   if(result.retcode == TRADE_RETCODE_DONE ||
      result.retcode == TRADE_RETCODE_DONE_PARTIAL ||
      result.retcode == TRADE_RETCODE_PLACED)
   {
      PGA_LogInfo(context + " OK | retcode=" + IntegerToString(result.retcode) +
                  " (" + PGA_TradeRetcodeDescription(result.retcode) + ")" +
                  " deal=" + IntegerToString(result.deal) +
                  " order=" + IntegerToString(result.order) +
                  " volume=" + DoubleToString(result.volume, 2) +
                  " price=" + DoubleToString(result.price, _Digits));
      return;
   }

   PGA_LogError(context + " FAILED | retcode=" + IntegerToString(result.retcode) +
                " (" + PGA_TradeRetcodeDescription(result.retcode) + ")" +
                " comment=" + result.comment);
}

#endif // PGA_ERRORS_MQH
