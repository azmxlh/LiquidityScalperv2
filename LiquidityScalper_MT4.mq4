//+------------------------------------------------------------------+
//|                                        LiquidityScalper_MT4.mq4 |
//|                                   Professional Trading Solutions |
//|                                        Built for XAUUSD Scalping |
//+------------------------------------------------------------------+
#property copyright "Professional Trading Solutions"
#property link      "https://github.com/yourlink"
#property version   "1.00"
#property strict

//--- Include files
#include "LS_Config.mqh"
#include "LS_Functions.mqh"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

//--- Risk Management
input group "=== RISK MANAGEMENT ==="
input double   RiskPercent = 1.0;              // Risk per trade (%)
input double   DailyLossLimit = 2.0;           // Daily loss limit (%)
input double   DailyProfitTarget = 3.0;        // Daily profit target (%)
input bool     LockProfitsAtTarget = false;    // Stop trading when daily target hit

//--- Trading Models
input group "=== TRADING MODELS ==="
input bool     EnableModelA = true;            // Enable Model A (Retest entries)
input bool     EnableModelB = true;            // Enable Model B (Stop orders)
input int      MaxStopLoss_ModelA = 150;       // Max stop loss Model A (points)
input int      MaxStopLoss_ModelB = 120;       // Max stop loss Model B (points)

//--- Session Settings
input group "=== SESSION SETTINGS ==="
input bool     TradeLondonSession = true;      // Trade London session
input bool     TradeNYSession = true;          // Trade New York session
input int      LondonStartHour = 8;            // London start (UTC)
input int      LondonEndHour = 12;             // London end (UTC)
input int      NYStartHour = 13;               // NY start (UTC)
input int      NYEndHour = 17;                 // NY end (UTC)
input int      MaxTradesPerSession = 3;        // Max trades per session
input int      MaxTradesPerDay = 5;            // Max trades per day

//--- Entry Settings
input group "=== ENTRY SETTINGS ==="
input int      MinDisplacementPoints = 80;     // Minimum displacement candle (points)
input int      MaxRetestCandles = 10;          // Max candles to wait for retest
input int      OrderBlockLookback = 10;        // Candles to search for order block
input int      LiquiditySweepBuffer = 5;       // Buffer beyond sweep level (points)

//--- Trade Management
input group "=== TRADE MANAGEMENT ==="
input double   TP1_RiskReward = 1.5;           // TP1 Risk:Reward ratio
input double   TP2_RiskReward = 3.0;           // TP2 Risk:Reward ratio
input double   TP1_PartialClose = 50;          // Close % at TP1
input int      BreakevenTrigger = 100;         // Move to BE after X points profit
input int      BreakevenBuffer = 2;            // BE buffer (points)
input int      TrailStartPoints = 100;         // Start trailing after X points
input int      TrailStopDistance = 25;         // Trailing stop distance (points)

//--- News Filter
input group "=== NEWS FILTER ==="
input bool     EnableNewsFilter = true;        // Enable news filter
input int      MinutesBeforeNews = 15;         // Minutes before news to stop
input int      MinutesAfterNews = 15;          // Minutes after news to resume
input string   HighImpactNewsTimes = "08:30,13:30,15:00"; // High impact times (UTC)

//--- Visual & Alerts
input group "=== VISUAL & ALERTS ==="
input bool     ShowDashboard = true;           // Show info dashboard
input bool     DrawKeyLevels = true;           // Draw daily levels on chart
input bool     EnableSoundAlerts = true;       // Sound alerts
input bool     EnableEmailAlerts = false;      // Email alerts
input bool     EnablePushAlerts = false;       // Push notifications

//--- Magic Number
input group "=== EXPERT ADVISOR SETTINGS ==="
input int      MagicNumber = 777888;           // Magic number for this EA
input string   TradeComment = "LiqScalp";      // Trade comment

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+

// Daily levels
double g_PDH = 0, g_PDL = 0;           // Previous Day High/Low
double g_ASH = 0, g_ASL = 0;           // Asian Session High/Low
double g_DayOpen = 0;                  // Day opening price

// Session tracking
int g_TradesLondon = 0;
int g_TradesNY = 0;
int g_TradesToday = 0;

// Daily P/L tracking
double g_DailyPL = 0;
double g_StartingBalance = 0;

// Order block zones
double g_BullishOB = 0;
double g_BearishOB = 0;

// Trade state tracking
datetime g_LastBarTime = 0;
datetime g_LastLiquiditySweep = 0;
datetime g_DisplacementTime = 0;
bool g_DisplacementDetected = false;
int g_DisplacementDirection = 0;  // 1=bullish, -1=bearish

// News filter
datetime g_NextNewsTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("===================================");
   Print("Liquidity Scalper EA Initialized");
   Print("Symbol: ", Symbol());
   Print("Account: ", AccountNumber());
   Print("Risk per trade: ", RiskPercent, "%");
   Print("===================================");
   
   // Validate symbol
   if(Symbol() != "XAUUSD" && Symbol() != "GOLD")
   {
      Alert("WARNING: This EA is designed for XAUUSD/GOLD only!");
   }
   
   // Validate timeframe
   if(Period() != PERIOD_M5)
   {
      Alert("WARNING: EA should run on M5 chart for optimal performance");
   }
   
   // Initialize starting balance
   g_StartingBalance = AccountBalance();
   
   // Calculate initial daily levels
   CalculateDailyLevels();
   
   // Draw initial levels if enabled
   if(DrawKeyLevels)
   {
      DrawDailyLevels();
   }
   
   // Create dashboard
   if(ShowDashboard)
   {
      CreateDashboard();
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up chart objects
   ObjectsDeleteAll(0, "LS_");
   
   Print("===================================");
   Print("Liquidity Scalper EA Stopped");
   Print("Total trades today: ", g_TradesToday);
   Print("Daily P/L: ", DoubleToString(g_DailyPL, 2), "%");
   Print("===================================");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new bar
   if(Time[0] == g_LastBarTime)
      return;
   g_LastBarTime = Time[0];
   
   //--- STEP 1: Check if new day (reset counters)
   if(IsNewDay())
   {
      ResetDailyCounters();
      CalculateDailyLevels();
      if(DrawKeyLevels) DrawDailyLevels();
   }
   
   //--- STEP 2: Update daily P/L
   UpdateDailyPL();
   
   //--- STEP 3: Pre-flight checks
   if(!PassPreFlightChecks())
   {
      ManageOpenTrades(); // Still manage existing trades
      if(ShowDashboard) UpdateDashboard();
      return;
   }
   
   //--- STEP 4: Scan for setups
   
   // Model A: Liquidity Sweep + Retest
   if(EnableModelA)
   {
      ScanModelA();
   }
   
   // Model B: Stop Order Continuation
   if(EnableModelB)
   {
      ScanModelB();
   }
   
   //--- STEP 5: Manage open trades
   ManageOpenTrades();
   
   //--- STEP 6: Update dashboard
   if(ShowDashboard)
   {
      UpdateDashboard();
   }
}

//+------------------------------------------------------------------+
//| PRE-FLIGHT CHECKS                                                 |
//+------------------------------------------------------------------+
bool PassPreFlightChecks()
{
   //--- Check if trading time
   if(!IsTradingTime())
   {
      return false;
   }
   
   //--- Check daily loss limit
   if(g_DailyPL <= -DailyLossLimit)
   {
      static datetime lastWarning = 0;
      if(TimeCurrent() - lastWarning > 3600) // Alert once per hour
      {
         Alert("Daily loss limit reached (", g_DailyPL, "%). Trading stopped.");
         lastWarning = TimeCurrent();
      }
      return false;
   }
   
   //--- Check daily profit target
   if(LockProfitsAtTarget && g_DailyPL >= DailyProfitTarget)
   {
      static datetime lastProfit = 0;
      if(TimeCurrent() - lastProfit > 3600)
      {
         Alert("Daily profit target reached (", g_DailyPL, "%). Trading locked.");
         lastProfit = TimeCurrent();
      }
      return false;
   }
   
   //--- Check max trades per day
   if(g_TradesToday >= MaxTradesPerDay)
   {
      return false;
   }
   
   //--- Check news filter
   if(EnableNewsFilter && IsNewsTime())
   {
      return false;
   }
   
   //--- Check if we have enough margin
   if(AccountFreeMarginCheck(Symbol(), OP_BUY, 0.01) < 0)
   {
      Alert("Insufficient margin to open trades!");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| MODEL A: LIQUIDITY SWEEP + RETEST SCANNER                        |
//+------------------------------------------------------------------+
void ScanModelA()
{
   //--- Check session trade limit
   if(GetCurrentSession() == "London" && g_TradesLondon >= MaxTradesPerSession)
      return;
   if(GetCurrentSession() == "NY" && g_TradesNY >= MaxTradesPerSession)
      return;
   
   //--- PHASE 1: Detect liquidity sweep
   if(!g_DisplacementDetected)
   {
      int sweepDirection = DetectLiquiditySweep();
      
      if(sweepDirection != 0)
      {
         g_LastLiquiditySweep = Time[1];
         
         // PHASE 2: Check for displacement
         if(DetectDisplacement(sweepDirection))
         {
            g_DisplacementDetected = true;
            g_DisplacementDirection = sweepDirection;
            g_DisplacementTime = Time[1];
            
            // Identify order block
            if(sweepDirection == 1) // Bullish
            {
               g_BullishOB = FindOrderBlock(true);
            }
            else // Bearish
            {
               g_BearishOB = FindOrderBlock(false);
            }
            
            if(EnableSoundAlerts)
            {
               Alert("Displacement detected! Direction: ", (sweepDirection == 1 ? "BULLISH" : "BEARISH"));
            }
         }
      }
   }
   
   //--- PHASE 3: Wait for retest and execute
   if(g_DisplacementDetected)
   {
      // Check if retest window expired
      int barsSinceDisplacement = iBarShift(Symbol(), PERIOD_M5, g_DisplacementTime);
      
      if(barsSinceDisplacement > MaxRetestCandles)
      {
         // Reset - retest took too long
         g_DisplacementDetected = false;
         g_DisplacementDirection = 0;
         return;
      }
      
      // Check for retest entry
      if(g_DisplacementDirection == 1 && g_BullishOB > 0)
      {
         // Bullish retest
         if(Low[1] <= g_BullishOB && Close[1] >= g_BullishOB)
         {
            ExecuteModelA_Long();
         }
      }
      else if(g_DisplacementDirection == -1 && g_BearishOB > 0)
      {
         // Bearish retest
         if(High[1] >= g_BearishOB && Close[1] <= g_BearishOB)
         {
            ExecuteModelA_Short();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| EXECUTE MODEL A LONG ENTRY                                       |
//+------------------------------------------------------------------+
void ExecuteModelA_Long()
{
   double entryPrice = g_BullishOB;
   double stopLoss = g_ASL - (LiquiditySweepBuffer * Point);
   
   // Calculate stop distance
   double stopPoints = (entryPrice - stopLoss) / Point;
   
   // Validate stop size
   if(stopPoints > MaxStopLoss_ModelA || stopPoints < 20)
   {
      g_DisplacementDetected = false;
      return;
   }
   
   // Calculate lot size
   double lotSize = CalculateLotSize(stopPoints * Point);
   
   // Calculate targets
   double tp1 = entryPrice + (stopPoints * Point * TP1_RiskReward);
   double tp2 = entryPrice + (stopPoints * Point * TP2_RiskReward);
   
   // Open position
   int ticket = OrderSend(
      Symbol(),
      OP_BUY,
      lotSize,
      Ask,
      3,
      stopLoss,
      0, // No TP initially, will manage manually
      TradeComment + " ModelA",
      MagicNumber,
      0,
      clrGreen
   );
   
   if(ticket > 0)
   {
      Print("Model A LONG opened: Ticket=", ticket, " Entry=", Ask, " SL=", stopLoss);
      
      // Increment counters
      IncrementTradeCounters();
      
      // Send alerts
      if(EnableSoundAlerts) Alert("Model A LONG entry executed!");
      if(EnableEmailAlerts) SendMail("Trade Alert", "Model A LONG opened at " + DoubleToString(Ask, Digits));
      
      // Reset displacement flag
      g_DisplacementDetected = false;
   }
   else
   {
      Print("Error opening Model A LONG: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| EXECUTE MODEL A SHORT ENTRY                                      |
//+------------------------------------------------------------------+
void ExecuteModelA_Short()
{
   double entryPrice = g_BearishOB;
   double stopLoss = g_ASH + (LiquiditySweepBuffer * Point);
   
   // Calculate stop distance
   double stopPoints = (stopLoss - entryPrice) / Point;
   
   // Validate stop size
   if(stopPoints > MaxStopLoss_ModelA || stopPoints < 20)
   {
      g_DisplacementDetected = false;
      return;
   }
   
   // Calculate lot size
   double lotSize = CalculateLotSize(stopPoints * Point);
   
   // Calculate targets
   double tp1 = entryPrice - (stopPoints * Point * TP1_RiskReward);
   double tp2 = entryPrice - (stopPoints * Point * TP2_RiskReward);
   
   // Open position
   int ticket = OrderSend(
      Symbol(),
      OP_SELL,
      lotSize,
      Bid,
      3,
      stopLoss,
      0,
      TradeComment + " ModelA",
      MagicNumber,
      0,
      clrRed
   );
   
   if(ticket > 0)
   {
      Print("Model A SHORT opened: Ticket=", ticket, " Entry=", Bid, " SL=", stopLoss);
      
      IncrementTradeCounters();
      
      if(EnableSoundAlerts) Alert("Model A SHORT entry executed!");
      if(EnableEmailAlerts) SendMail("Trade Alert", "Model A SHORT opened at " + DoubleToString(Bid, Digits));
      
      g_DisplacementDetected = false;
   }
   else
   {
      Print("Error opening Model A SHORT: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| MODEL B: STOP ORDER CONTINUATION SCANNER                         |
//+------------------------------------------------------------------+
void ScanModelB()
{
   // Check session trade limit
   if(GetCurrentSession() == "London" && g_TradesLondon >= MaxTradesPerSession)
      return;
   if(GetCurrentSession() == "NY" && g_TradesNY >= MaxTradesPerSession)
      return;
   
   // Check if there are pending orders already
   int pendingCount = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
         {
            if(OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP)
               pendingCount++;
         }
      }
   }
   
   if(pendingCount > 0) return; // Already have pending orders
   
   // Detect break of structure + consolidation
   if(DetectBOS())
   {
      if(DetectConsolidation())
      {
         PlaceStopOrders();
      }
   }
}

//+------------------------------------------------------------------+
//| PLACE STOP ORDERS (Model B)                                      |
//+------------------------------------------------------------------+
void PlaceStopOrders()
{
   // Get consolidation range
   double consHigh = GetConsolidationHigh();
   double consLow = GetConsolidationLow();
   
   if(consHigh == 0 || consLow == 0) return;
   
   // Determine structure direction from H1
   int h1Direction = GetH1StructureDirection();
   
   if(h1Direction == 1) // Bullish structure - place buy stop
   {
      double buyStopPrice = consHigh + (5 * Point);
      double stopLoss = consLow - (5 * Point);
      double stopPoints = (buyStopPrice - stopLoss) / Point;
      
      if(stopPoints > MaxStopLoss_ModelB || stopPoints < 20)
         return;
      
      double lotSize = CalculateLotSize(stopPoints * Point);
      double tp = buyStopPrice + (100 * Point); // Fixed 100 points for Model B
      
      int ticket = OrderSend(
         Symbol(),
         OP_BUYSTOP,
         lotSize,
         buyStopPrice,
         3,
         stopLoss,
         0,
         TradeComment + " ModelB",
         MagicNumber,
         TimeCurrent() + 7200, // 2 hour expiry
         clrBlue
      );
      
      if(ticket > 0)
      {
         Print("Model B BUY STOP placed: ", buyStopPrice);
         if(EnableSoundAlerts) Alert("Model B BUY STOP placed!");
      }
   }
   else if(h1Direction == -1) // Bearish structure - place sell stop
   {
      double sellStopPrice = consLow - (5 * Point);
      double stopLoss = consHigh + (5 * Point);
      double stopPoints = (stopLoss - sellStopPrice) / Point;
      
      if(stopPoints > MaxStopLoss_ModelB || stopPoints < 20)
         return;
      
      double lotSize = CalculateLotSize(stopPoints * Point);
      double tp = sellStopPrice - (100 * Point);
      
      int ticket = OrderSend(
         Symbol(),
         OP_SELLSTOP,
         lotSize,
         sellStopPrice,
         3,
         stopLoss,
         0,
         TradeComment + " ModelB",
         MagicNumber,
         TimeCurrent() + 7200,
         clrOrange
      );
      
      if(ticket > 0)
      {
         Print("Model B SELL STOP placed: ", sellStopPrice);
         if(EnableSoundAlerts) Alert("Model B SELL STOP placed!");
      }
   }
}

//+------------------------------------------------------------------+
//| MANAGE OPEN TRADES                                               |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS))
         continue;
         
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
         continue;
      
      // Close all trades at session end
      if(Hour() >= NYEndHour)
      {
         CloseOrder(OrderTicket());
         continue;
      }
      
      // Delete expired pending orders
      if(OrderType() == OP_BUYSTOP || OrderType() == OP_SELLSTOP)
      {
         if(OrderExpiration() > 0 && TimeCurrent() >= OrderExpiration())
         {
            OrderDelete(OrderTicket());
            continue;
         }
      }
      
      // Manage market orders
      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
      {
         double profit = OrderProfit();
         double openPrice = OrderOpenPrice();
         double currentPrice = (OrderType() == OP_BUY) ? Bid : Ask;
         
         // Calculate profit in points
         double profitPoints = 0;
         if(OrderType() == OP_BUY)
            profitPoints = (Bid - openPrice) / Point;
         else
            profitPoints = (openPrice - Ask) / Point;
         
         // Move to breakeven
         if(profitPoints >= BreakevenTrigger)
         {
            if(OrderStopLoss() < openPrice && OrderType() == OP_BUY)
            {
               double newSL = openPrice + (BreakevenBuffer * Point);
               OrderModify(OrderTicket(), openPrice, newSL, OrderTakeProfit(), 0, clrBlue);
               Print("Trade ", OrderTicket(), " moved to breakeven");
            }
            else if(OrderStopLoss() > openPrice && OrderType() == OP_SELL)
            {
               double newSL = openPrice - (BreakevenBuffer * Point);
               OrderModify(OrderTicket(), openPrice, newSL, OrderTakeProfit(), 0, clrBlue);
               Print("Trade ", OrderTicket(), " moved to breakeven");
            }
         }
         
         // Partial close at TP1
         double stopDist = MathAbs(OrderOpenPrice() - OrderStopLoss()) / Point;
         double tp1Distance = stopDist * TP1_RiskReward;
         
         if(profitPoints >= tp1Distance && OrderLots() > MarketInfo(Symbol(), MODE_MINLOT))
         {
            double closeVolume = OrderLots() * TP1_PartialClose / 100.0;
            closeVolume = NormalizeDouble(closeVolume, 2);
            
            if(closeVolume >= MarketInfo(Symbol(), MODE_MINLOT))
            {
               PartialClose(OrderTicket(), closeVolume);
            }
         }
         
         // Trailing stop
         if(profitPoints >= TrailStartPoints)
         {
            double newSL = 0;
            
            if(OrderType() == OP_BUY)
            {
               newSL = Bid - (TrailStopDistance * Point);
               if(newSL > OrderStopLoss() && newSL < Bid)
               {
                  OrderModify(OrderTicket(), openPrice, newSL, OrderTakeProfit(), 0, clrGreen);
               }
            }
            else // SELL
            {
               newSL = Ask + (TrailStopDistance * Point);
               if(newSL < OrderStopLoss() && newSL > Ask)
               {
                  OrderModify(OrderTicket(), openPrice, newSL, OrderTakeProfit(), 0, clrRed);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| SUPPORT FUNCTIONS - Continue in LS_Functions.mqh                |
//+------------------------------------------------------------------+

// Note: The remaining functions are in the LS_Functions.mqh file
// to keep code organized and maintainable
