//+------------------------------------------------------------------+
//| PGA_Types.mqh — PremGoldAdvisor V1.4 core types                  |
//+------------------------------------------------------------------+
#property copyright "PremGoldAdvisor"
#property strict

#ifndef PGA_TYPES_MQH
#define PGA_TYPES_MQH

#define PGA_MAX_BASKETS     32
#define PGA_LEGS_PER_BASKET 5
#define PGA_COMMENT_PREFIX  "PGA14"

enum ENUM_PGA_DIRECTION
{
   PGA_DIR_BUY  = 0,
   PGA_DIR_SELL = 1
};

enum ENUM_PGA_BASKET_STATE
{
   PGA_BASKET_INACTIVE = 0,
   PGA_BASKET_ACTIVE   = 1,
   PGA_BASKET_DONE     = 2
};

struct PGA_Leg
{
   ulong  ticket;
   int    slot;          // 1..5
   double takeProfit;
   bool   closed;
};

struct PGA_Basket
{
   ulong               id;
   datetime            candleTime;
   ENUM_PGA_DIRECTION  direction;
   double              entryPrice;
   double              tp[6];          // index 1..5 used
   double              initialSL;
   double              breakEvenPrice;
   double              currentTrailSL;
   int                 highestTPHit;   // 0 = none, 1..5 = highest TP closed
   PGA_Leg             legs[6];        // index 1..5 used
   ENUM_PGA_BASKET_STATE state;
   bool                inUse;
};

struct PGA_CandlePlan
{
   datetime candleTime;
   double   openPrice;
   double   buyEntryLevel;
   double   sellEntryLevel;
   bool     buyTriggered;
   bool     sellTriggered;
   bool     valid;
};

#endif // PGA_TYPES_MQH
