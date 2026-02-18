//+------------------------------------------------------------------+
//|                                             LS_Functions.mqh     |
//|                                   Helper Functions Library       |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                      |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossDistance)
{
   double riskAmount = AccountBalance() * RiskPercent / 100.0;
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   
   // Calculate raw lot size
   double lotSize = riskAmount / (stopLossDistance / Point * tickValue);
   
   // Normalize to lot step
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   lotSize = NormalizeDouble(lotSize, 2);
   
   // Apply limits
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   // Additional safety: max 5% of free margin
   double maxLotByMargin = AccountFreeMargin() * 0.05 / MarketInfo(Symbol(), MODE_MARGINREQUIRED);
   if(lotSize > maxLotByMargin)
      lotSize = maxLotByMargin;
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Detect liquidity sweep                                           |
//| Returns: 1=bullish sweep, -1=bearish sweep, 0=no sweep          |
//+------------------------------------------------------------------+
int DetectLiquiditySweep()
{
   double currentHigh = High[1];
   double currentLow = Low[1];
   double closePrice = Close[1];
   
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
   double candleRange = MathAbs(High[1] - Low[1]) / Point;
   
   // Check if candle meets minimum displacement criteria
   if(candleRange < MinDisplacementPoints)
      return false;
   
   // Check if displacement matches expected direction
   if(expectedDirection == 1) // Bullish displacement expected
   {
      if(Close[1] > Open[1] && Close[1] > High[2])
      {
         // Check if it broke previous structure
         bool brokeStructure = false;
         for(int i = 2; i <= 10; i++)
         {
            if(Close[1] > High[i])
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
      if(Close[1] < Open[1] && Close[1] < Low[2])
      {
         bool brokeStructure = false;
         for(int i = 2; i <= 10; i++)
         {
            if(Close[1] < Low[i])
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
      if(bullish)
      {
         // Find last bearish candle (order block for longs)
         if(Close[i] < Open[i])
         {
            Print("Bullish order block found at candle ", i, " - Level: ", High[i]);
            return High[i]; // Top of bearish candle
         }
      }
      else
      {
         // Find last bullish candle (order block for shorts)
         if(Close[i] > Open[i])
         {
            Print("Bearish order block found at candle ", i, " - Level: ", Low[i]);
            return Low[i]; // Bottom of bullish candle
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
      double recentHigh = iHigh(Symbol(), PERIOD_M5, 1);
      double previousHigh = iHigh(Symbol(), PERIOD_M5, 5); // 5 candles ago
      
      if(recentHigh > previousHigh)
      {
         Print("Bullish BOS detected on M5");
         return true;
      }
   }
   else if(h1Direction == -1) // Bearish
   {
      double recentLow = iLow(Symbol(), PERIOD_M5, 1);
      double previousLow = iLow(Symbol(), PERIOD_M5, 5);
      
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
   // Analyze last 10 H1 candles for structure
   double swingHighs[5];
   double swingLows[5];
   int highCount = 0, lowCount = 0;
   
   // Find swing points
   for(int i = 5; i <= 50; i += 10)
   {
      swingHighs[highCount] = iHigh(Symbol(), PERIOD_H1, i);
      swingLows[lowCount] = iLow(Symbol(), PERIOD_H1, i);
      highCount++;
      lowCount++;
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
   double high = High[1];
   double low = Low[1];
   
   for(int i = 2; i <= 6; i++)
   {
      if(High[i] > high) high = High[i];
      if(Low[i] < low) low = Low[i];
   }
   
   double rangePoints = (high - low) / Point;
   
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
   double high = High[1];
   for(int i = 2; i <= 6; i++)
   {
      if(High[i] > high) high = High[i];
   }
   return high;
}

//+------------------------------------------------------------------+
//| Get consolidation low                                            |
//+------------------------------------------------------------------+
double GetConsolidationLow()
{
   double low = Low[1];
   for(int i = 2; i <= 6; i++)
   {
      if(Low[i] < low) low = Low[i];
   }
   return low;
}

//+------------------------------------------------------------------+
//| Calculate daily levels                                           |
//+------------------------------------------------------------------+
void CalculateDailyLevels()
{
   // Previous Day High/Low
   g_PDH = iHigh(Symbol(), PERIOD_D1, 1);
   g_PDL = iLow(Symbol(), PERIOD_D1, 1);
   
   // Day opening price (midnight UTC)
   g_DayOpen = iOpen(Symbol(), PERIOD_D1, 0);
   
   // Asian Session High/Low (00:00 - 08:00 UTC)
   g_ASH = 0;
   g_ASL = 999999;
   
   datetime asianStart = iTime(Symbol(), PERIOD_H1, 0);
   asianStart = asianStart - (asianStart % 86400); // Today midnight
   
   for(int i = 0; i < 8; i++) // 8 hours = Asian session
   {
      int shift = iBarShift(Symbol(), PERIOD_H1, asianStart + (i * 3600));
      
      if(shift >= 0)
      {
         double high = iHigh(Symbol(), PERIOD_H1, shift);
         double low = iLow(Symbol(), PERIOD_H1, shift);
         
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
   int currentDay = Day();
   
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
   g_StartingBalance = AccountBalance();
   
   Print("=== NEW DAY - Counters Reset ===");
}

//+------------------------------------------------------------------+
//| Check if trading time                                            |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
   int hour = Hour();
   
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
   int hour = Hour();
   
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
   int count = StringSplit(HighImpactNewsTimes, ',', times);
   
   datetime currentTime = TimeCurrent();
   int currentHour = TimeHour(currentTime);
   int currentMinute = TimeMinute(currentTime);
   
   for(int i = 0; i < count; i++)
   {
      string parts[];
      StringSplit(times[i], ':', parts);
      
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
   double currentBalance = AccountBalance();
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
//| Close order                                                      |
//+------------------------------------------------------------------+
void CloseOrder(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return;
   
   double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
   
   bool result = OrderClose(ticket, OrderLots(), closePrice, 3, clrYellow);
   
   if(result)
   {
      Print("Order ", ticket, " closed at ", closePrice);
   }
   else
   {
      Print("Error closing order ", ticket, ": ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Partial close                                                    |
//+------------------------------------------------------------------+
void PartialClose(int ticket, double volume)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return;
   
   double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
   
   bool result = OrderClose(ticket, volume, closePrice, 3, clrOrange);
   
   if(result)
   {
      Print("Partial close executed: ", volume, " lots closed from ticket ", ticket);
   }
   else
   {
      Print("Error partial closing: ", GetLastError());
   }
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
   
   // PDL
   ObjectCreate(0, "LS_PDL", OBJ_HLINE, 0, 0, g_PDL);
   ObjectSetInteger(0, "LS_PDL", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "LS_PDL", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "LS_PDL", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetString(0, "LS_PDL", OBJPROP_TEXT, "PDL");
   
   // ASH
   ObjectCreate(0, "LS_ASH", OBJ_HLINE, 0, 0, g_ASH);
   ObjectSetInteger(0, "LS_ASH", OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, "LS_ASH", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "LS_ASH", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetString(0, "LS_ASH", OBJPROP_TEXT, "ASH");
   
   // ASL
   ObjectCreate(0, "LS_ASL", OBJ_HLINE, 0, 0, g_ASL);
   ObjectSetInteger(0, "LS_ASL", OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, "LS_ASL", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "LS_ASL", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetString(0, "LS_ASL", OBJPROP_TEXT, "ASL");
   
   // Day Open
   ObjectCreate(0, "LS_DayOpen", OBJ_HLINE, 0, 0, g_DayOpen);
   ObjectSetInteger(0, "LS_DayOpen", OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0, "LS_DayOpen", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, "LS_DayOpen", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetString(0, "LS_DayOpen", OBJPROP_TEXT, "Day Open");
   
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
   int height = 20;
   
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
   
   // Title
   CreateLabel("LS_Title", "LIQUIDITY SCALPER", x, y, clrYellow, 12, "Arial Bold");
   
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
   ObjectSetString(0, "LS_PDHLabel", OBJPROP_TEXT, "PDH: " + DoubleToString(g_PDH, Digits));
   ObjectSetString(0, "LS_PDLLabel", OBJPROP_TEXT, "PDL: " + DoubleToString(g_PDL, Digits));
   ObjectSetString(0, "LS_ASHLabel", OBJPROP_TEXT, "ASH: " + DoubleToString(g_ASH, Digits));
   ObjectSetString(0, "LS_ASLLabel", OBJPROP_TEXT, "ASL: " + DoubleToString(g_ASL, Digits));
   
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
