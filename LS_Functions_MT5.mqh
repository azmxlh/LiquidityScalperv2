//+------------------------------------------------------------------+
//|                                          LS_Functions_MT5.mqh    |
//|                                   Helper Functions Library       |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                      |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossDistance)
{
   double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
   
   // Get contract specifications
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   // Calculate point value
   double pointValue = tickValue * (g_Point / tickSize);
   
   // Calculate raw lot size
   double lotSize = riskAmount / (stopLossDistance / g_Point * pointValue);
   
   // Normalize to lot step
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = NormalizeDouble(lotSize, 2);
   
   // Apply limits
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   // Additional safety: max 5% of free margin
   double marginRequired = 0;
   if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lotSize, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginRequired))
   {
      double maxLotByMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.05 / marginRequired;
      if(lotSize > maxLotByMargin)
         lotSize = maxLotByMargin;
   }
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Detect liquidity sweep                                           |
//| Returns: 1=bullish sweep, -1=bearish sweep, 0=no sweep          |
//+------------------------------------------------------------------+
int DetectLiquiditySweep()
{
   double currentHigh = iHigh(_Symbol, PERIOD_M5, 1);
   double currentLow = iLow(_Symbol, PERIOD_M5, 1);
   double closePrice = iClose(_Symbol, PERIOD_M5, 1);
   
   // Check for bearish sweep (swept highs then reversed)
   if(currentHigh > g_ASH || currentHigh > g_PDH)
   {
      if(closePrice < MathMin(g_ASH, g_PDH))
      {
         Print("Bearish liquidity sweep detected at ", currentHigh);
         return -1;
      }
   }
   
   // Check for bullish sweep (swept lows then reversed)
   if(currentLow < g_ASL || currentLow < g_PDL)
   {
      if(closePrice > MathMax(g_ASL, g_PDL))
      {
         Print("Bullish liquidity sweep detected at ", currentLow);
         return 1;
      }
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Detect displacement candle                                       |
//+------------------------------------------------------------------+
bool DetectDisplacement(int expectedDirection)
{
   double high = iHigh(_Symbol, PERIOD_M5, 1);
   double low = iLow(_Symbol, PERIOD_M5, 1);
   double close = iClose(_Symbol, PERIOD_M5, 1);
   double open = iOpen(_Symbol, PERIOD_M5, 1);
   
   double candleRange = MathAbs(high - low) / g_Point;
   
   // Check if candle meets minimum displacement criteria
   if(candleRange < MinDisplacementPoints)
      return false;
   
   // Check if displacement matches expected direction
   if(expectedDirection == 1) // Bullish displacement expected
   {
      if(close > open)
      {
         // Check if it broke previous structure
         bool brokeStructure = false;
         for(int i = 2; i <= 10; i++)
         {
            if(close > iHigh(_Symbol, PERIOD_M5, i))
            {
               brokeStructure = true;
               break;
            }
         }
         
         if(brokeStructure)
         {
            Print("Bullish displacement confirmed: ", candleRange, " points");
            return true;
         }
      }
   }
   else if(expectedDirection == -1) // Bearish displacement expected
   {
      if(close < open)
      {
         bool brokeStructure = false;
         for(int i = 2; i <= 10; i++)
         {
            if(close < iLow(_Symbol, PERIOD_M5, i))
            {
               brokeStructure = true;
               break;
            }
         }
         
         if(brokeStructure)
         {
            Print("Bearish displacement confirmed: ", candleRange, " points");
            return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Find order block zone                                            |
//+------------------------------------------------------------------+
double FindOrderBlock(bool bullish)
{
   // Look for last opposite candle before displacement
   for(int i = 2; i < OrderBlockLookback; i++)
   {
      double close = iClose(_Symbol, PERIOD_M5, i);
      double open = iOpen(_Symbol, PERIOD_M5, i);
      double high = iHigh(_Symbol, PERIOD_M5, i);
      double low = iLow(_Symbol, PERIOD_M5, i);
      
      if(bullish)
      {
         // Find last bearish candle (order block for longs)
         if(close < open)
         {
            Print("Bullish order block found at candle ", i, " - Level: ", high);
            return high; // Top of bearish candle
         }
      }
      else
      {
         // Find last bullish candle (order block for shorts)
         if(close > open)
         {
            Print("Bearish order block found at candle ", i, " - Level: ", low);
            return low; // Bottom of bullish candle
         }
      }
   }
   
   return 0; // No valid order block found
}

//+------------------------------------------------------------------+
//| Detect Break of Structure                                        |
//+------------------------------------------------------------------+
bool DetectBOS()
{
   // Check H1 timeframe for clear trend
   int h1Direction = GetH1StructureDirection();
   
   if(h1Direction == 0) return false;
   
   // Check if recent M5 candle broke structure
   if(h1Direction == 1) // Bullish
   {
      double recentHigh = iHigh(_Symbol, PERIOD_M5, 1);
      double previousHigh = iHigh(_Symbol, PERIOD_M5, 5); // 5 candles ago
      
      if(recentHigh > previousHigh)
      {
         Print("Bullish BOS detected on M5");
         return true;
      }
   }
   else if(h1Direction == -1) // Bearish
   {
      double recentLow = iLow(_Symbol, PERIOD_M5, 1);
      double previousLow = iLow(_Symbol, PERIOD_M5, 5);
      
      if(recentLow < previousLow)
      {
         Print("Bearish BOS detected on M5");
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Get H1 structure direction                                       |
//+------------------------------------------------------------------+
int GetH1StructureDirection()
{
   // Analyze last H1 candles for structure
   double swingHighs[5];
   double swingLows[5];
   int highCount = 0, lowCount = 0;
   
   // Find swing points
   for(int i = 5; i <= 50; i += 10)
   {
      swingHighs[highCount] = iHigh(_Symbol, PERIOD_H1, i);
      swingLows[lowCount] = iLow(_Symbol, PERIOD_H1, i);
      highCount++;
      lowCount++;
      if(highCount >= 5) break;
   }
   
   // Check for higher highs and higher lows (bullish)
   bool higherHighs = true;
   bool higherLows = true;
   
   for(int i = 1; i < 4; i++)
   {
      if(swingHighs[i] <= swingHighs[i-1]) higherHighs = false;
      if(swingLows[i] <= swingLows[i-1]) higherLows = false;
   }
   
   if(higherHighs && higherLows)
      return 1; // Bullish
   
   // Check for lower highs and lower lows (bearish)
   bool lowerHighs = true;
   bool lowerLows = true;
   
   for(int i = 1; i < 4; i++)
   {
      if(swingHighs[i] >= swingHighs[i-1]) lowerHighs = false;
      if(swingLows[i] >= swingLows[i-1]) lowerLows = false;
   }
   
   if(lowerHighs && lowerLows)
      return -1; // Bearish
   
   return 0; // Ranging/unclear
}

//+------------------------------------------------------------------+
//| Detect consolidation                                             |
//+------------------------------------------------------------------+
bool DetectConsolidation()
{
   // Check last 5 candles for tight range
   double high = iHigh(_Symbol, PERIOD_M5, 1);
   double low = iLow(_Symbol, PERIOD_M5, 1);
   
   for(int i = 2; i <= 6; i++)
   {
      double h = iHigh(_Symbol, PERIOD_M5, i);
      double l = iLow(_Symbol, PERIOD_M5, i);
      if(h > high) high = h;
      if(l < low) low = l;
   }
   
   double rangePoints = (high - low) / g_Point;
   
   // Consolidation if range < 200 points
   if(rangePoints < 200 && rangePoints > 30)
   {
      Print("Consolidation detected: ", rangePoints, " points range");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Get consolidation high                                           |
//+------------------------------------------------------------------+
double GetConsolidationHigh()
{
   double high = iHigh(_Symbol, PERIOD_M5, 1);
   for(int i = 2; i <= 6; i++)
   {
      double h = iHigh(_Symbol, PERIOD_M5, i);
      if(h > high) high = h;
   }
   return high;
}

//+------------------------------------------------------------------+
//| Get consolidation low                                            |
//+------------------------------------------------------------------+
double GetConsolidationLow()
{
   double low = iLow(_Symbol, PERIOD_M5, 1);
   for(int i = 2; i <= 6; i++)
   {
      double l = iLow(_Symbol, PERIOD_M5, i);
      if(l < low) low = l;
   }
   return low;
}

//+------------------------------------------------------------------+
//| Calculate daily levels                                           |
//+------------------------------------------------------------------+
void CalculateDailyLevels()
{
   // Previous Day High/Low
   g_PDH = iHigh(_Symbol, PERIOD_D1, 1);
   g_PDL = iLow(_Symbol, PERIOD_D1, 1);
   
   // Day opening price (midnight UTC)
   g_DayOpen = iOpen(_Symbol, PERIOD_D1, 0);
   
   // Asian Session High/Low (00:00 - 08:00 UTC)
   g_ASH = 0;
   g_ASL = 999999;
   
   datetime todayMidnight = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(todayMidnight, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   todayMidnight = StructToTime(dt);
   
   for(int i = 0; i < 8; i++) // 8 hours = Asian session
   {
      int shift = iBarShift(_Symbol, PERIOD_H1, todayMidnight + (i * 3600));
      
      if(shift >= 0)
      {
         double high = iHigh(_Symbol, PERIOD_H1, shift);
         double low = iLow(_Symbol, PERIOD_H1, shift);
         
         if(high > g_ASH) g_ASH = high;
         if(low < g_ASL) g_ASL = low;
      }
   }
   
   Print("Daily Levels Updated:");
   Print("PDH: ", g_PDH, " | PDL: ", g_PDL);
   Print("ASH: ", g_ASH, " | ASL: ", g_ASL);
   Print("Day Open: ", g_DayOpen);
}

//+------------------------------------------------------------------+
//| Check if new day                                                 |
//+------------------------------------------------------------------+
bool IsNewDay()
{
   static int lastDay = -1;
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentDay = dt.day;
   
   if(currentDay != lastDay)
   {
      lastDay = currentDay;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Reset daily counters                                             |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
   g_TradesLondon = 0;
   g_TradesNY = 0;
   g_TradesToday = 0;
   g_DailyPL = 0;
   g_StartingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   Print("=== NEW DAY - Counters Reset ===");
}

//+------------------------------------------------------------------+
//| Check if trading time                                            |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   // London session
   if(TradeLondonSession && hour >= LondonStartHour && hour < LondonEndHour)
      return true;
   
   // NY session
   if(TradeNYSession && hour >= NYStartHour && hour < NYEndHour)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Get current session name                                         |
//+------------------------------------------------------------------+
string GetCurrentSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   
   if(hour >= LondonStartHour && hour < LondonEndHour)
      return "London";
   
   if(hour >= NYStartHour && hour < NYEndHour)
      return "NY";
   
   return "Closed";
}

//+------------------------------------------------------------------+
//| Check if news time                                               |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
   // Parse high impact news times
   string times[];
   int count = StringSplit(HighImpactNewsTimes, StringGetCharacter(",", 0), times);
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentHour = dt.hour;
   int currentMinute = dt.min;
   
   for(int i = 0; i < count; i++)
   {
      string parts[];
      StringSplit(times[i], StringGetCharacter(":", 0), parts);
      
      if(ArraySize(parts) == 2)
      {
         int newsHour = (int)StringToInteger(parts[0]);
         int newsMinute = (int)StringToInteger(parts[1]);
         
         // Calculate time difference in minutes
         int timeDiff = (currentHour * 60 + currentMinute) - (newsHour * 60 + newsMinute);
         
         if(timeDiff >= -MinutesBeforeNews && timeDiff <= MinutesAfterNews)
         {
            return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Update daily P/L                                                 |
//+------------------------------------------------------------------+
void UpdateDailyPL()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_DailyPL = ((currentBalance - g_StartingBalance) / g_StartingBalance) * 100.0;
}

//+------------------------------------------------------------------+
//| Increment trade counters                                         |
//+------------------------------------------------------------------+
void IncrementTradeCounters()
{
   g_TradesToday++;
   
   string session = GetCurrentSession();
   if(session == "London")
      g_TradesLondon++;
   else if(session == "NY")
      g_TradesNY++;
}

//+------------------------------------------------------------------+
//| Draw daily levels on chart                                       |
//+------------------------------------------------------------------+
void DrawDailyLevels()
{
   // Delete old levels
   ObjectDelete(0, "LS_PDH");
   ObjectDelete(0, "LS_PDL");
   ObjectDelete(0, "LS_ASH");
   ObjectDelete(0, "LS_ASL");
   ObjectDelete(0, "LS_DayOpen");
   
   // PDH
   ObjectCreate(0, "LS_PDH", OBJ_HLINE, 0, 0, g_PDH);
   ObjectSetInteger(0, "LS_PDH", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "LS_PDH", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "LS_PDH", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetString(0, "LS_PDH", OBJPROP_TEXT, "PDH");
   ObjectSetInteger(0, "LS_PDH", OBJPROP_SELECTABLE, false);
   
   // PDL
   ObjectCreate(0, "LS_PDL", OBJ_HLINE, 0, 0, g_PDL);
   ObjectSetInteger(0, "LS_PDL", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "LS_PDL", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "LS_PDL", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetString(0, "LS_PDL", OBJPROP_TEXT, "PDL");
   ObjectSetInteger(0, "LS_PDL", OBJPROP_SELECTABLE, false);
   
   // ASH
   ObjectCreate(0, "LS_ASH", OBJ_HLINE, 0, 0, g_ASH);
   ObjectSetInteger(0, "LS_ASH", OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, "LS_ASH", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "LS_ASH", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetString(0, "LS_ASH", OBJPROP_TEXT, "ASH");
   ObjectSetInteger(0, "LS_ASH", OBJPROP_SELECTABLE, false);
   
   // ASL
   ObjectCreate(0, "LS_ASL", OBJ_HLINE, 0, 0, g_ASL);
   ObjectSetInteger(0, "LS_ASL", OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, "LS_ASL", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "LS_ASL", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetString(0, "LS_ASL", OBJPROP_TEXT, "ASL");
   ObjectSetInteger(0, "LS_ASL", OBJPROP_SELECTABLE, false);
   
   // Day Open
   ObjectCreate(0, "LS_DayOpen", OBJ_HLINE, 0, 0, g_DayOpen);
   ObjectSetInteger(0, "LS_DayOpen", OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0, "LS_DayOpen", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "LS_DayOpen", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetString(0, "LS_DayOpen", OBJPROP_TEXT, "Day Open");
   ObjectSetInteger(0, "LS_DayOpen", OBJPROP_SELECTABLE, false);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Create dashboard                                                 |
//+------------------------------------------------------------------+
void CreateDashboard()
{
   int x = 20;
   int y = 50;
   int width = 250;
   
   // Background panel
   ObjectCreate(0, "LS_Panel", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LS_Panel", OBJPROP_XDISTANCE, x - 10);
   ObjectSetInteger(0, "LS_Panel", OBJPROP_YDISTANCE, y - 10);
   ObjectSetInteger(0, "LS_Panel", OBJPROP_XSIZE, width + 20);
   ObjectSetInteger(0, "LS_Panel", OBJPROP_YSIZE, 200);
   ObjectSetInteger(0, "LS_Panel", OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, "LS_Panel", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "LS_Panel", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "LS_Panel", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, "LS_Panel", OBJPROP_BACK, true);
   ObjectSetInteger(0, "LS_Panel", OBJPROP_SELECTABLE, false);
   
   // Title
   CreateLabel("LS_Title", "LIQUIDITY SCALPER MT5", x, y, clrYellow, 12, "Arial Bold");
   
   // Info labels
   CreateLabel("LS_Session", "Session: --", x, y + 30, clrWhite, 9, "Arial");
   CreateLabel("LS_Trades", "Trades: 0/5", x, y + 50, clrWhite, 9, "Arial");
   CreateLabel("LS_DailyPL", "Daily P/L: 0.00%", x, y + 70, clrWhite, 9, "Arial");
   CreateLabel("LS_PDHLabel", "PDH: --", x, y + 90, clrRed, 9, "Arial");
   CreateLabel("LS_PDLLabel", "PDL: --", x, y + 110, clrRed, 9, "Arial");
   CreateLabel("LS_ASHLabel", "ASH: --", x, y + 130, clrOrange, 9, "Arial");
   CreateLabel("LS_ASLLabel", "ASL: --", x, y + 150, clrOrange, 9, "Arial");
   CreateLabel("LS_Status", "Status: Active", x, y + 170, clrLime, 9, "Arial");
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Create label helper                                              |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int size, string font)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Update dashboard                                                 |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   string session = GetCurrentSession();
   
   ObjectSetString(0, "LS_Session", OBJPROP_TEXT, "Session: " + session);
   ObjectSetString(0, "LS_Trades", OBJPROP_TEXT, "Trades: " + IntegerToString(g_TradesToday) + "/" + IntegerToString(MaxTradesPerDay));
   
   // Daily P/L color coding
   color plColor = (g_DailyPL >= 0) ? clrLime : clrRed;
   ObjectSetString(0, "LS_DailyPL", OBJPROP_TEXT, "Daily P/L: " + DoubleToString(g_DailyPL, 2) + "%");
   ObjectSetInteger(0, "LS_DailyPL", OBJPROP_COLOR, plColor);
   
   // Levels
   ObjectSetString(0, "LS_PDHLabel", OBJPROP_TEXT, "PDH: " + DoubleToString(g_PDH, g_Digits));
   ObjectSetString(0, "LS_PDLLabel", OBJPROP_TEXT, "PDL: " + DoubleToString(g_PDL, g_Digits));
   ObjectSetString(0, "LS_ASHLabel", OBJPROP_TEXT, "ASH: " + DoubleToString(g_ASH, g_Digits));
   ObjectSetString(0, "LS_ASLLabel", OBJPROP_TEXT, "ASL: " + DoubleToString(g_ASL, g_Digits));
   
   // Status
   string status = "Active";
   color statusColor = clrLime;
   
   if(g_DailyPL <= -DailyLossLimit)
   {
      status = "Daily Loss Limit";
      statusColor = clrRed;
   }
   else if(LockProfitsAtTarget && g_DailyPL >= DailyProfitTarget)
   {
      status = "Target Reached";
      statusColor = clrGold;
   }
   else if(!IsTradingTime())
   {
      status = "Outside Hours";
      statusColor = clrGray;
   }
   
   ObjectSetString(0, "LS_Status", OBJPROP_TEXT, "Status: " + status);
   ObjectSetInteger(0, "LS_Status", OBJPROP_COLOR, statusColor);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Get bar shift (MT5 compatible)                                   |
//+------------------------------------------------------------------+
int iBarShift(string symbol, ENUM_TIMEFRAMES timeframe, datetime time)
{
   datetime barTime[];
   ArraySetAsSeries(barTime, true);
   
   int copied = CopyTime(symbol, timeframe, 0, 500, barTime);
   if(copied <= 0) return -1;
   
   for(int i = 0; i < copied; i++)
   {
      if(barTime[i] <= time)
         return i;
   }
   
   return -1;
}
