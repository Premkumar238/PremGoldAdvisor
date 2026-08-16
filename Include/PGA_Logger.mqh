#ifndef PGA_LOGGER_MQH
#define PGA_LOGGER_MQH

#include "PGA_Inputs.mqh"

const string PGA_LOG_FILE = "PremGoldAdvisor.log";

void PgaLog(const string message)
  {
   if(InpLogToJournal)
      Print("[PremGoldAdvisor] ", message);

   if(!InpLogToFile)
      return;

   int handle = FileOpen(PGA_LOG_FILE, FILE_READ | FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
      return;

   FileSeek(handle, 0, SEEK_END);
   FileWriteString(handle, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "  " + message + "\r\n");
   FileClose(handle);
  }

void PgaLogTrade(const string action, const string side, const ulong ticket,
                 const double volume, const double price, const double sl, const double tp,
                 const string reason)
  {
   PgaLog(StringFormat("%s %s ticket=%I64u vol=%.2f price=%s sl=%s tp=%s | %s",
                       action, side, ticket, volume,
                       DoubleToString(price, _Digits),
                       DoubleToString(sl, _Digits),
                       DoubleToString(tp, _Digits),
                       reason));
  }

#endif
