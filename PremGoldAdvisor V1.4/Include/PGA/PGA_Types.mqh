//+------------------------------------------------------------------+
//| PGA_Types.mqh — PremGoldAdvisor V1.4 core types                  |
//| Sequential stage system: only ONE active order per direction.    |
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

// Sequential stages: STAGE_1 .. STAGE_5, then COMPLETE
enum ENUM_PGA_STAGE
{
   PGA_STAGE_NONE     = 0,
   PGA_STAGE_1        = 1,
   PGA_STAGE_2        = 2,
   PGA_STAGE_3        = 3,
   PGA_STAGE_4        = 4,
   PGA_STAGE_5        = 5,
   PGA_STAGE_COMPLETE = 6
};

struct PGA_Leg
{
   ulong  ticket;
   int    slot;          // 1..5
   double entryPrice;
   double takeProfit;
   double stopLoss;
   bool   closed;
   bool   opened;        // true once this stage was opened
};

struct PGA_Basket
{
   ulong                 id;
   datetime              candleTime;
   ENUM_PGA_DIRECTION    direction;
   double                triggerEntryLevel; // original level that started the sequence
   double                tpDistance[6];     // configured TP distances 1..5
   double                initialSLDistance;
   double                breakEvenBuffer;
   ENUM_PGA_STAGE        stage;             // current stage (1..5) or COMPLETE
   ulong                 activeTicket;      // the ONE open order ticket (0 if none)
   double                activeEntry;
   double                activeTP;
   double                activeSL;
   double                activeBreakEven;
   bool                  breakEvenApplied;
   bool                  waitingNextOpen;   // true after TP close confirmed, before next open done
   PGA_Leg               legs[6];           // history per stage 1..5
   ENUM_PGA_BASKET_STATE state;
   bool                  inUse;
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
