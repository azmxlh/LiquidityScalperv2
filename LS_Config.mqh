//+------------------------------------------------------------------+
//|                                                LS_Config.mqh     |
//|                                   Configuration Constants        |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| SYSTEM CONSTANTS                                                 |
//+------------------------------------------------------------------+

#define EA_NAME "Liquidity Scalper Pro"
#define EA_VERSION "1.0.0"
#define EA_BUILD_DATE "2026-02-10"

//+------------------------------------------------------------------+
//| TIMEFRAME CONSTANTS                                              |
//+------------------------------------------------------------------+

#define BIAS_TIMEFRAME PERIOD_H1    // Structure analysis
#define EXEC_TIMEFRAME PERIOD_M5    // Entry execution

//+------------------------------------------------------------------+
//| TRADING CONSTANTS                                                |
//+------------------------------------------------------------------+

// Session times (UTC)
#define ASIAN_START 0
#define ASIAN_END 8
#define LONDON_START 8
#define LONDON_END 12
#define NY_START 13
#define NY_END 17

// Default risk parameters
#define DEFAULT_RISK 1.0
#define MAX_RISK 5.0
#define MIN_RISK 0.1

// Point values (for XAUUSD)
#define MIN_STOP_POINTS 20
#define MAX_STOP_POINTS_A 150
#define MAX_STOP_POINTS_B 120

// Trade management
#define MIN_DISPLACEMENT 80
#define MAX_RETEST_WAIT 10
#define OB_LOOKBACK 10

//+------------------------------------------------------------------+
//| COLOR SCHEME                                                     |
//+------------------------------------------------------------------+

#define COLOR_PDH clrCrimson
#define COLOR_PDL clrCrimson
#define COLOR_ASH clrOrange
#define COLOR_ASL clrOrange
#define COLOR_DAYOPEN clrGray
#define COLOR_BULLISH_OB clrDodgerBlue
#define COLOR_BEARISH_OB clrMagenta

//+------------------------------------------------------------------+
//| DASHBOARD LAYOUT                                                 |
//+------------------------------------------------------------------+

#define PANEL_X 20
#define PANEL_Y 50
#define PANEL_WIDTH 250
#define PANEL_HEIGHT 200
#define LINE_HEIGHT 20
#define FONT_SIZE_TITLE 12
#define FONT_SIZE_NORMAL 9

//+------------------------------------------------------------------+
//| VALIDATION MACROS                                                |
//+------------------------------------------------------------------+

// Validate symbol is Gold
#define IS_GOLD (Symbol() == "XAUUSD" || Symbol() == "GOLD" || StringFind(Symbol(), "XAU") >= 0)

// Validate timeframe
#define IS_M5 (Period() == PERIOD_M5)

// Validate account type
#define IS_DEMO (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO)

//+------------------------------------------------------------------+
//| ERROR MESSAGES                                                   |
//+------------------------------------------------------------------+

#define ERR_WRONG_SYMBOL "This EA is designed for XAUUSD/GOLD only"
#define ERR_WRONG_TIMEFRAME "EA should run on M5 chart"
#define ERR_NO_MARGIN "Insufficient margin"
#define ERR_INVALID_STOPS "Invalid stop loss size"
#define ERR_MAX_TRADES "Maximum trades reached"
#define ERR_DAILY_LOSS "Daily loss limit hit"
#define ERR_NEWS_TIME "Trading halted due to news"

//+------------------------------------------------------------------+
//| PROP FIRM PRESETS                                                |
//+------------------------------------------------------------------+

// Common prop firm challenge parameters
struct PropFirmProfile
{
   string name;
   double profitTarget;      // % to pass
   double maxDailyLoss;      // % max daily loss
   double maxTotalLoss;      // % max total loss
   int tradingDays;          // Days to achieve target
   bool holdOvernight;       // Allow overnight positions
};

// Predefined profiles
PropFirmProfile FTMO_STANDARD = {"FTMO Standard", 10.0, 5.0, 10.0, 30, false};
PropFirmProfile FTMO_AGGRESSIVE = {"FTMO Aggressive", 20.0, 5.0, 10.0, 60, false};
PropFirmProfile THE5ERS = {"The5ers", 6.0, 4.0, 6.0, 30, false};
PropFirmProfile FUNDED_NEXT = {"Funded Next", 10.0, 5.0, 10.0, 30, true};

//+------------------------------------------------------------------+
//| NEWS EVENT STRUCTURE                                             |
//+------------------------------------------------------------------+

struct NewsEvent
{
   datetime time;
   string currency;
   string description;
   int impact;  // 1=low, 2=medium, 3=high
};

// High impact events to avoid (manual list - update weekly)
string HighImpactEvents[] = 
{
   "NFP",
   "FOMC",
   "CPI",
   "GDP",
   "Interest Rate Decision",
   "Unemployment Rate",
   "Retail Sales"
};

//+------------------------------------------------------------------+
//| UTILITY FUNCTIONS                                                |
//+------------------------------------------------------------------+

// Convert points to price for current symbol
double PointsToPrice(double points)
{
   return points * Point;
}

// Convert price to points for current symbol
double PriceToPoints(double price)
{
   return price / Point;
}

// Get symbol point value
double GetPointValue()
{
   return MarketInfo(Symbol(), MODE_TICKVALUE);
}

// Calculate pip value
double GetPipValue()
{
   return Point * 10; // For XAUUSD, 1 pip = 10 points
}

//+------------------------------------------------------------------+
//| LOGGING HELPERS                                                  |
//+------------------------------------------------------------------+

// Log levels
#define LOG_INFO 0
#define LOG_WARNING 1
#define LOG_ERROR 2
#define LOG_TRADE 3

// Enhanced logging function
void LogMessage(int level, string message)
{
   string prefix = "";
   
   switch(level)
   {
      case LOG_INFO: prefix = "[INFO] "; break;
      case LOG_WARNING: prefix = "[WARNING] "; break;
      case LOG_ERROR: prefix = "[ERROR] "; break;
      case LOG_TRADE: prefix = "[TRADE] "; break;
   }
   
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   Print(timestamp, " ", prefix, message);
}

//+------------------------------------------------------------------+
//| PERFORMANCE TRACKING                                             |
//+------------------------------------------------------------------+

// Trade statistics structure
struct TradeStats
{
   int totalTrades;
   int winningTrades;
   int losingTrades;
   double totalProfit;
   double totalLoss;
   double largestWin;
   double largestLoss;
   double winRate;
   double avgRR;
   double profitFactor;
};

// Initialize statistics
TradeStats g_Stats;

void ResetStats()
{
   g_Stats.totalTrades = 0;
   g_Stats.winningTrades = 0;
   g_Stats.losingTrades = 0;
   g_Stats.totalProfit = 0;
   g_Stats.totalLoss = 0;
   g_Stats.largestWin = 0;
   g_Stats.largestLoss = 0;
   g_Stats.winRate = 0;
   g_Stats.avgRR = 0;
   g_Stats.profitFactor = 0;
}

//+------------------------------------------------------------------+
//| RISK CALCULATOR                                                  |
//+------------------------------------------------------------------+

// Calculate position size for prop firm compliance
double CalculatePropFirmLotSize(double stopPoints, PropFirmProfile &profile)
{
   double accountSize = AccountBalance();
   double maxRiskAmount = accountSize * (profile.maxDailyLoss / 100.0) * 0.33; // Use 1/3 of daily limit per trade
   
   double tickValue = GetPointValue();
   double lotSize = maxRiskAmount / (stopPoints * tickValue);
   
   // Normalize and validate
   lotSize = NormalizeDouble(lotSize, 2);
   lotSize = MathMax(lotSize, MarketInfo(Symbol(), MODE_MINLOT));
   lotSize = MathMin(lotSize, MarketInfo(Symbol(), MODE_MAXLOT));
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| SESSION HELPERS                                                  |
//+------------------------------------------------------------------+

// Get session name from current time
string GetSessionName(datetime time = 0)
{
   if(time == 0) time = TimeCurrent();
   
   int hour = TimeHour(time);
   
   if(hour >= ASIAN_START && hour < ASIAN_END)
      return "Asian";
   else if(hour >= LONDON_START && hour < LONDON_END)
      return "London";
   else if(hour >= NY_START && hour < NY_END)
      return "New York";
   else
      return "Closed";
}

// Check if market is open
bool IsMarketOpen()
{
   int dayOfWeek = DayOfWeek();
   
   // Closed on weekends
   if(dayOfWeek == 0 || dayOfWeek == 6)
      return false;
   
   // Check if within trading hours
   string session = GetSessionName();
   return (session != "Closed");
}

//+------------------------------------------------------------------+
//| ALERT HELPERS                                                    |
//+------------------------------------------------------------------+

// Send comprehensive alert
void SendTradeAlert(string type, string message)
{
   string fullMessage = EA_NAME + " - " + type + ": " + message;
   
   // Sound alert
   if(EnableSoundAlerts)
      Alert(fullMessage);
   
   // Email alert
   if(EnableEmailAlerts)
      SendMail(EA_NAME + " Alert", fullMessage);
   
   // Push notification
   if(EnablePushAlerts)
      SendNotification(fullMessage);
   
   // Log
   LogMessage(LOG_TRADE, fullMessage);
}
