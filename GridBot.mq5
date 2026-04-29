//+------------------------------------------------------------------+
//| GridBot.mq5                                                      |
//| Bot de Grid Geometrico Dinamico para Forex (MT5)                 |
//| v3.6.0 — UI REDISENADA (paleta profesional fintech)              |
//+------------------------------------------------------------------+
#property copyright "Oscar Alvarado"
#property version   "3.60"
#property description "Grid Bot Geometrico Dinamico — LONG/SHORT"
#property description "v3.6.0 — UI rediseno: paleta financiera, sin solapamientos"
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
enum DireccionGrid { GRID_LONG, GRID_SHORT };

input group "==== DIRECCION ===="
input DireccionGrid Direccion_Inp = GRID_LONG;

input group "==== RANGO ===="
input double Techo_Inp   = 1.1800;
input double Piso_Inp    = 1.1600;
input double Trigger_Inp = 1.1720;
input double GPct_Inp    = 0.0025;

input group "==== CAPITAL Y RIESGO ===="
input double Capital_Inp   = 3000;
input double Volumen_Inp   = 0.01;
input double RiskPct_Inp   = 1.0;
input int    MaxOrders_Inp = 10;
input bool   ModoLibre_Inp = false;

input group "==== SALIDAS ===="
input double TP_Inp = 1.1850;
input double SL_Inp = 1.1550;

input group "==== AVANZADO ===="
input int    Magic_Number = 20250424;

//+------------------------------------------------------------------+
//| RUNTIME PARAMS                                                   |
//+------------------------------------------------------------------+
double p_Techo, p_Piso, p_Trigger, p_G;
double p_Capital, p_Vol, p_Risk;
int    p_MaxOrd;
bool   p_Libre;
double p_TP, p_SL;
DireccionGrid p_Direccion;

//+------------------------------------------------------------------+
//| HELPER: Pips reales segun digitos del simbolo                    |
//+------------------------------------------------------------------+
double PipsDivisor()
{
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return (dg == 3 || dg == 5) ? 10.0 : 1.0;
}

double ToPips(double distanciaPrice)
{
   return distanciaPrice / _Point / PipsDivisor();
}

//+------------------------------------------------------------------+
//| ESTADO Y GLOBALES                                                |
//+------------------------------------------------------------------+
enum EstadoBot { PENDING, ACTIVE, PAUSED, STOPPED, PRECHECK };
EstadoBot estado = PRECHECK;

enum AlertType { ALERT_INFO, ALERT_WARN, ALERT_ERROR, ALERT_SUCCESS };
bool      AlertaVisible    = false;
bool      PanelMinimized   = false;
bool      ConfigMinimized  = false;

bool DragPanel = false, DragConfig = false;
int  DragOffX  = 0, DragOffY = 0;
int  PanelPosX = 12, PanelPosY = 12;
int  ConfigPosX = -1, ConfigPosY = -1;

int  LastChartW = 0, LastChartH = 0;

string PrevTecho="", PrevPiso="", PrevTrigger="", PrevG="", PrevVol="";
string PrevCap="", PrevRisk="", PrevMaxo="";
string PrevTP="", PrevSL="";
string    AlertaTitle  = "";
string    AlertaMsg    = "";
string    AlertaSubMsg = "";
AlertType AlertaTipo   = ALERT_INFO;

double GridLevels[];
double GananciaAcumulada   = 0.0;
ulong  UltimoDealProcesado = 0;
int    RejillasActivas     = 0;
int    MaxOrdersSafe       = 0;
double RiesgoRealUSD       = 0.0;
double RiesgoRealPct       = 0.0;
double GananciaPorRejilla  = 0.0;
const string PFX = "GB36_";

double GUIScale      = 1.0;
datetime BotStartTime = 0;
int  PanelW = 244, PanelH = 360;

bool ConfigVisible = false;
int  ConfigTab     = 0;
int  CfgX, CfgY;
int  CfgW = 540, CfgH = 600;
bool CfgCompact = false;

//+------------------------------------------------------------------+
//| PALETA — FINTECH OSCURA PROFESIONAL                              |
//+------------------------------------------------------------------+
#define CLR_BG_DEEP     C'7,9,18'        // 070912
#define CLR_BG_BASE     C'15,19,32'      // 0F1320
#define CLR_PANEL       C'22,27,41'      // 161B29
#define CLR_PANEL_2     C'28,34,53'      // 1C2235
#define CLR_ELEV        C'35,43,66'      // 232B42
#define CLR_INPUT       C'12,15,26'      // 0C0F1A
#define CLR_BORDER      C'42,50,71'      // 2A3247
#define CLR_BORDER_LT   C'58,67,97'      // 3A4361
#define CLR_BORDER_STR  C'74,84,120'     // 4A5478

#define CLR_TEXT        C'232,235,242'   // E8EBF2
#define CLR_TEXT_DIM    C'151,160,184'   // 97A0B8
#define CLR_TEXT_FAINT  C'94,104,133'    // 5E6885
#define CLR_TEXT_MUTE   C'74,83,112'     // 4A5370

#define CLR_ACCENT      C'91,140,255'    // 5B8CFF
#define CLR_ACCENT_2    C'122,164,255'   // 7AA4FF
#define CLR_ACCENT_DIM  C'45,74,153'     // 2D4A99
#define CLR_ACCENT_DEEP C'26,44,94'      // 1A2C5E

#define CLR_GREEN       C'34,197,94'     // 22C55E
#define CLR_GREEN_DIM   C'21,128,61'     // 15803D
#define CLR_GREEN_DEEP  C'10,61,31'      // 0A3D1F

#define CLR_RED         C'239,68,68'     // EF4444
#define CLR_RED_DIM     C'153,27,27'     // 991B1B
#define CLR_RED_DEEP    C'61,10,10'      // 3D0A0A

#define CLR_AMBER       C'245,158,11'    // F59E0B
#define CLR_AMBER_DIM   C'180,83,9'      // B45309
#define CLR_AMBER_DEEP  C'61,41,6'       // 3D2906

// Compatibilidad con codigo previo
#define CLR_BG          CLR_BG_BASE
#define CLR_PANEL_HOV   CLR_PANEL_2
#define CLR_TAB_ACTIVE  CLR_PANEL_2
#define CLR_MINT        CLR_GREEN
#define CLR_MINT_ACT    C'52,220,123'
#define CLR_MINT_DIM    CLR_GREEN_DEEP
#define CLR_TP          CLR_GREEN
#define CLR_SL          CLR_RED
#define CLR_RANGO       CLR_AMBER
#define CLR_TRIGGER     CLR_ACCENT

//+------------------------------------------------------------------+
//| HELPERS UI                                                       |
//+------------------------------------------------------------------+
double GetUIScale()
{
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   if(cw <= 0) return 1.0;
   double scale = (double)cw / 1280.0;
   if(scale < 0.75) scale = 0.75;
   if(scale > 1.50) scale = 1.50;
   GUIScale = scale;
   return scale;
}

void RefreshScale() { GetUIScale(); }
int Sc(int v) { return (int)MathRound(v * GUIScale); }

int IndiceDesdeComment(const string c)
{
   int p = StringFind(c, "_", StringFind(c, "_") + 1);
   if(p < 0) return -1;
   return (int)StringToInteger(StringSubstr(c, p + 1));
}

void CargarParametros()
{
   p_Direccion = Direccion_Inp;
   p_Techo   = Techo_Inp;   p_Piso    = Piso_Inp;
   p_Trigger = Trigger_Inp; p_G       = GPct_Inp;
   p_Capital = Capital_Inp; p_Vol     = Volumen_Inp;
   p_Risk    = RiskPct_Inp; p_MaxOrd  = MaxOrders_Inp;
   p_Libre   = ModoLibre_Inp;
   p_TP      = TP_Inp;      p_SL      = SL_Inp;
}

void BorrarTodo()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, PFX) == 0) ObjectDelete(0, n);
   }
   ChartRedraw(0);
}

void BorrarLineasGrid()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, PFX + "L_TP") == 0    || StringFind(n, PFX + "L_SL") == 0    ||
         StringFind(n, PFX + "L_TECHO") == 0 || StringFind(n, PFX + "L_PISO") == 0  ||
         StringFind(n, PFX + "L_TRIGGER") == 0 || StringFind(n, PFX + "L_GRID_") == 0 ||
         StringFind(n, PFX + "L_TPACT_") == 0 ||
         StringFind(n, PFX + "T_") == 0)
         ObjectDelete(0, n);
   }
}

//+------------------------------------------------------------------+
//| RISK ENGINE                                                      |
//+------------------------------------------------------------------+
void CalcularRiesgo()
{
   double presupuesto = p_Capital * (p_Risk / 100.0);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSz <= 0) tickSz = _Point;

   double acum = 0;
   MaxOrdersSafe = 0;
   int total = ArraySize(GridLevels);
   for(int i = 0; i < total; i++)
   {
      double d = MathAbs(GridLevels[i] - p_SL);
      acum += d / tickSz * tickVal * p_Vol;
      if(acum <= presupuesto) MaxOrdersSafe = i + 1;
      else break;
   }

   double rt = 0;
   int nc = MathMin(p_MaxOrd, total);
   for(int i = 0; i < nc; i++)
   {
      double d = MathAbs(GridLevels[i] - p_SL);
      rt += d / tickSz * tickVal * p_Vol;
   }
   RiesgoRealUSD = rt;
   RiesgoRealPct = (p_Capital > 0) ? rt / p_Capital * 100 : 0;
   if(total > 0) GananciaPorRejilla = (GridLevels[0] * p_G) / tickSz * tickVal * p_Vol;
}

//+------------------------------------------------------------------+
//| LINEAS EN GRAFICO                                                |
//+------------------------------------------------------------------+
void CrearLinea(string id, double pr, color clr, ENUM_LINE_STYLE st, int w)
{
   string n = PFX + "L_" + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_HLINE, 0, 0, pr);
   ObjectSetDouble(0, n, OBJPROP_PRICE, pr);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_STYLE, st);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, w);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
}

void CrearLabelGraf(string id, double pr, color clr, string txt, int bOff, ENUM_ANCHOR_POINT anc)
{
   string n = PFX + "T_" + id;
   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, bOff);
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_TEXT, 0, t0, pr);
   ObjectSetInteger(0, n, OBJPROP_TIME, t0);
   ObjectSetDouble(0, n, OBJPROP_PRICE, pr);
   ObjectSetString(0, n, OBJPROP_TEXT, "<- " + txt + " " + DoubleToString(pr, _Digits));
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, anc);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
}

void DibujarTPsActivos()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, PFX + "L_TPACT_") == 0 || StringFind(n, PFX + "T_TPACT_") == 0)
         ObjectDelete(0, n);
   }
   if(estado != ACTIVE && estado != PAUSED) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double tpPrice;
      if(p_Direccion == GRID_LONG)
         tpPrice = NormalizeDouble(openPrice * (1.0 + p_G), _Digits);
      else
         tpPrice = NormalizeDouble(openPrice / (1.0 + p_G), _Digits);

      string sid = IntegerToString(ticket);
      string nL  = PFX + "L_TPACT_" + sid;
      string nT  = PFX + "T_TPACT_" + sid;
      if(ObjectFind(0, nL) < 0) ObjectCreate(0, nL, OBJ_HLINE, 0, 0, tpPrice);
      ObjectSetDouble(0, nL,  OBJPROP_PRICE, tpPrice);
      ObjectSetInteger(0, nL, OBJPROP_COLOR, CLR_MINT_ACT);
      ObjectSetInteger(0, nL, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, nL, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nL, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nL, OBJPROP_BACK, true);

      datetime t0 = iTime(_Symbol, PERIOD_CURRENT, 2);
      if(ObjectFind(0, nT) < 0) ObjectCreate(0, nT, OBJ_TEXT, 0, t0, tpPrice);
      ObjectSetInteger(0, nT, OBJPROP_TIME, t0);
      ObjectSetDouble(0, nT,  OBJPROP_PRICE, tpPrice);
      ObjectSetString(0, nT,  OBJPROP_TEXT, "<- TP #" + sid);
      ObjectSetInteger(0, nT, OBJPROP_COLOR, CLR_MINT_ACT);
      ObjectSetInteger(0, nT, OBJPROP_FONTSIZE, 7);
      ObjectSetString(0, nT,  OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, nT, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
      ObjectSetInteger(0, nT, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nT, OBJPROP_BACK, false);
   }
}

void DibujarLineasGrid()
{
   BorrarLineasGrid();
   CrearLinea("TP",      p_TP,      CLR_TP,      STYLE_DASH,    2);
   CrearLinea("SL",      p_SL,      CLR_SL,      STYLE_DASH,    2);
   CrearLinea("TECHO",   p_Techo,   CLR_RANGO,   STYLE_SOLID,   2);
   CrearLinea("PISO",    p_Piso,    CLR_RANGO,   STYLE_SOLID,   2);
   CrearLinea("TRIGGER", p_Trigger, CLR_TRIGGER, STYLE_DASHDOT, 2);

   CrearLabelGraf("TP",      p_TP,      CLR_TP,      "TP Global", 0,  ANCHOR_RIGHT_LOWER);
   CrearLabelGraf("SL",      p_SL,      CLR_SL,      "SL Global", 0,  ANCHOR_RIGHT_LOWER);
   CrearLabelGraf("TECHO",   p_Techo,   CLR_RANGO,   "Techo",     0,  ANCHOR_RIGHT_LOWER);
   CrearLabelGraf("PISO",    p_Piso,    CLR_RANGO,   "Piso",      16, ANCHOR_RIGHT_UPPER);
   CrearLabelGraf("TRIGGER", p_Trigger, CLR_TRIGGER, "Trigger",   16, ANCHOR_RIGHT_LOWER);

   int total = ArraySize(GridLevels);
   int offs[3] = {0, 4, 8};
   string lbl_prefix = (p_Direccion == GRID_LONG) ? "Buy" : "Sell";
   for(int i = 0; i < total; i++)
   {
      bool ok    = (i < MaxOrdersSafe);
      color clrR = (estado == ACTIVE && ok) ? CLR_MINT_ACT : ok ? CLR_MINT : CLR_MINT_DIM;
      string lbl = (ok ? lbl_prefix : lbl_prefix + "*") + " [" + IntegerToString(i) + "]";
      CrearLinea("GRID_" + IntegerToString(i), GridLevels[i], clrR, STYLE_DOT, 1);
      CrearLabelGraf("GRID_" + IntegerToString(i), GridLevels[i], clrR, lbl, offs[i % 3],
                     (i == total - 1) ? ANCHOR_RIGHT_UPPER : ANCHOR_RIGHT_LOWER);
   }
   DibujarTPsActivos();
   ChartRedraw(0);
}

void MarcarRejillaActiva(int idx, bool act)
{
   string nL = PFX + "L_GRID_" + IntegerToString(idx);
   string nT = PFX + "T_GRID_" + IntegerToString(idx);
   color clr = act ? CLR_MINT_ACT : CLR_MINT;
   int   ww  = act ? 2 : 1;
   if(ObjectFind(0, nL) >= 0) { ObjectSetInteger(0, nL, OBJPROP_COLOR, clr); ObjectSetInteger(0, nL, OBJPROP_WIDTH, ww); }
   if(ObjectFind(0, nT) >= 0)   ObjectSetInteger(0, nT, OBJPROP_COLOR, clr);
   DibujarTPsActivos();
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| PRIMITIVOS UI                                                    |
//+------------------------------------------------------------------+
void PR(string id, int x, int y, int w, int h, color bg, color brd, int bw = 1)
{
   string n = PFX + "R_" + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,     h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,   bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR,     brd);
   ObjectSetInteger(0, n, OBJPROP_WIDTH,     bw);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK,      false);
}

void PL(string id, int x, int y, string txt, color clr, int sz, string font = "Consolas")
{
   string n = PFX + "L_" + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  n, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, n, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,  sz);
   ObjectSetString(0,  n, OBJPROP_FONT,      font);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK,      false);
}

// Label con anchor — para alinear texto a la derecha o centro
void PLA(string id, int x, int y, string txt, color clr, int sz, ENUM_ANCHOR_POINT anc, string font = "Consolas")
{
   string n = PFX + "L_" + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  n, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, n, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,  sz);
   ObjectSetString(0,  n, OBJPROP_FONT,      font);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR,    anc);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK,      false);
}

void PB(string id, int x, int y, int w, int h, string txt, color bg, color clr, int sz = 9, string font = "Consolas")
{
   string n = PFX + "B_" + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,        h);
   ObjectSetString(0,  n, OBJPROP_TEXT,         txt);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR,        clr);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,     sz);
   ObjectSetString(0,  n, OBJPROP_FONT,         font);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, n, OBJPROP_STATE,        false);
}

void PE(string id, int x, int y, int w, int h, string val)
{
   string n = PFX + "E_" + id;
   bool existed = (ObjectFind(0, n) >= 0);
   if(!existed) ObjectCreate(0, n, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,        h);
   if(!existed) ObjectSetString(0, n, OBJPROP_TEXT, val);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      CLR_INPUT);
   ObjectSetInteger(0, n, OBJPROP_COLOR,        CLR_TEXT);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, CLR_BORDER);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,     10);
   ObjectSetString(0,  n, OBJPROP_FONT,         "Consolas");
   ObjectSetInteger(0, n, OBJPROP_ALIGN,        ALIGN_LEFT);
   ObjectSetInteger(0, n, OBJPROP_READONLY,     false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, n, OBJPROP_BACK,         false);
}

void PE_Force(string id, string val)
{
   string n = PFX + "E_" + id;
   if(ObjectFind(0, n) >= 0) ObjectSetString(0, n, OBJPROP_TEXT, val);
}

void PHR(string id, int x, int y, int w, color clr) { PR(id, x, y, w, 1, clr, clr, 0); }
void PVR(string id, int x, int y, int h, color clr) { PR(id, x, y, 1, h, clr, clr, 0); }

string GetEdit(string id) { return ObjectGetString(0, PFX + "E_" + id, OBJPROP_TEXT); }
void   DelObj(string full){ ObjectDelete(0, PFX + full); }

// BADGE: pildora con dot indicador + texto — para estados
void PBadge(string id, int x, int y, int w, int h, string txt, color textC, color bgC, color brdC)
{
   PR(id + "_BG", x, y, w, h, bgC, brdC, 1);
   // Dot indicador a la izquierda
   int dotSz = MathMax(Sc(5), 4);
   int dotY  = y + (h - dotSz) / 2;
   PR(id + "_DOT", x + Sc(7), dotY, dotSz, dotSz, textC, textC, 0);
   // Texto a la derecha del dot
   PL(id + "_TX", x + Sc(7) + dotSz + Sc(6), y + (h - Sc(11)) / 2, txt, textC, Sc(8), "Arial");
}

//+------------------------------------------------------------------+
//| ALERTAS POPUP                                                    |
//+------------------------------------------------------------------+
void MostrarAlerta(string title, string msg, string subMsg, AlertType tipo)
{
   AlertaTitle = title; AlertaMsg = msg; AlertaSubMsg = subMsg; AlertaTipo = tipo;
   AlertaVisible = true; DibujarAlerta();
}

void BorrarAlerta()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, PFX + "R_ALR") == 0 || StringFind(n, PFX + "L_ALR") == 0 || StringFind(n, PFX + "B_ALR") == 0)
         ObjectDelete(0, n);
   }
   ChartRedraw(0);
}

void DibujarTextoLargo(string id, int x, int y, int wPx, string texto, color clr, int sz, int lineGap = 20)
{
   int charW    = (sz <= 9) ? 10 : (sz <= 10) ? 12 : (sz <= 11) ? 13 : 14;
   int maxChars = wPx / charW;
   if(maxChars < 10) maxChars = 10;
   string lineas[20]; int totalLineas = 0; string linea = ""; string textoRest = texto;
   while(StringLen(textoRest) > 0 && totalLineas < 20)
   {
      int spacePos = StringFind(textoRest, " "); string palabra;
      if(spacePos < 0) { palabra = textoRest; textoRest = ""; }
      else { palabra = StringSubstr(textoRest, 0, spacePos); textoRest = StringSubstr(textoRest, spacePos + 1); }
      if(palabra == "") continue;
      string nueva = (linea == "") ? palabra : linea + " " + palabra;
      if(StringLen(nueva) <= maxChars) linea = nueva;
      else { if(linea != "") { lineas[totalLineas++] = linea; linea = palabra; } else { lineas[totalLineas++] = palabra; linea = ""; } }
   }
   if(linea != "" && totalLineas < 20) lineas[totalLineas++] = linea;
   for(int i = 0; i < totalLineas; i++) PL(id + "_" + IntegerToString(i), x, y + i * lineGap, lineas[i], clr, sz, "Arial");
}

void DibujarAlerta()
{
   if(!AlertaVisible) { BorrarAlerta(); return; }
   double sc = GetUIScale();
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int W = MathMin((int)(680*sc), cw - 40); if(W < 360) W = 360;
   int H = MathMin((int)(330*sc), ch - 40); if(H < 240) H = 240;
   int x = (cw - W) / 2; if(x < 10) x = 10;
   int y = (ch - H) / 2; if(y < 10) y = 10;
   color iconC; string iconText;
   switch(AlertaTipo)
   {
      case ALERT_ERROR:   iconC = CLR_RED;    iconText = "!";  break;
      case ALERT_WARN:    iconC = CLR_AMBER;  iconText = "!";  break;
      case ALERT_SUCCESS: iconC = CLR_GREEN;  iconText = "OK"; break;
      default:            iconC = CLR_ACCENT; iconText = "i";  break;
   }
   bool compact = (H < 320);
   int PAD = compact ? Sc(18) : Sc(24);
   int hdrH = compact ? Sc(52) : Sc(64);
   int footerSpace = compact ? Sc(50) : Sc(58);
   int okBtnH = compact ? Sc(34) : Sc(40);
   PR("ALR_BG",  x, y, W, H,    CLR_PANEL,   CLR_ACCENT, 2);
   PR("ALR_HDR", x, y, W, hdrH, CLR_BG_DEEP, CLR_BG_DEEP, 0);
   PHR("ALR_HDR_LN", x, y + hdrH - 1, W, CLR_BORDER);
   int icnY = y + (hdrH - Sc(28)) / 2;
   PB("ALR_ICN", x + PAD, icnY, Sc(28), Sc(28), iconText, iconC, CLR_TEXT, Sc(14));
   ObjectSetInteger(0, PFX + "B_ALR_ICN", OBJPROP_BORDER_COLOR, iconC);
   int titX = x + PAD + Sc(40); int titW = W - PAD * 2 - Sc(80);
   PB("ALR_TIT", titX, icnY, titW, Sc(28), AlertaTitle, CLR_BG_DEEP, CLR_TEXT, Sc(12));
   ObjectSetInteger(0, PFX + "B_ALR_TIT", OBJPROP_BORDER_COLOR, CLR_BG_DEEP);
   PB("ALR_X", x + W - PAD - Sc(30), icnY, Sc(30), Sc(28), "X", CLR_RED_DIM, CLR_TEXT, Sc(12));
   int by = y + hdrH + (compact ? Sc(16) : Sc(24)); int textW = W - PAD * 2;
   DibujarTextoLargo("ALR_MSG", x + PAD, by, textW - 12, AlertaMsg, CLR_TEXT, Sc(11), Sc(22));
   if(StringLen(AlertaSubMsg) > 0)
   {
      int subY = by + (compact ? Sc(50) : Sc(60)); int subH = compact ? Sc(52) : Sc(64);
      int maxSubBottom = y + H - footerSpace - Sc(8);
      if(subY + subH > maxSubBottom) subH = maxSubBottom - subY;
      if(subH > Sc(24))
      {
         PR("ALR_SBOX", x + PAD, subY, textW, subH, CLR_BG_DEEP, CLR_BORDER, 1);
         PR("ALR_SIND", x + PAD, subY, 4, subH, iconC, iconC, 0);
         DibujarTextoLargo("ALR_SMSG", x + PAD + Sc(16), subY + Sc(12), textW - Sc(44), AlertaSubMsg, CLR_TEXT_DIM, Sc(10), Sc(18));
      }
   }
   int btnY = y + H - footerSpace;
   PHR("ALR_BTN_LN", x, btnY - 1, W, CLR_BORDER);
   int okW = MathMin(Sc(220), W - PAD * 2);
   PB("ALR_OK", x + (W - okW) / 2, btnY + (footerSpace - okBtnH) / 2, okW, okBtnH, "ENTENDIDO", CLR_ACCENT, CLR_TEXT, Sc(13));
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| BOTONES ESQUINA                                                  |
//+------------------------------------------------------------------+
void DibujarBotonesEsquina()
{
   int btnW = Sc(92); int btnH = Sc(28); int badgeW = Sc(72); int gap = Sc(6); int margin = Sc(10);

   PB("CFGBTN", btnW + margin, margin, btnW, btnH, "CONFIG", CLR_ACCENT_DIM, CLR_TEXT, Sc(9), "Arial");
   ObjectSetInteger(0, PFX + "B_CFGBTN", OBJPROP_CORNER,       CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, PFX + "B_CFGBTN", OBJPROP_XDISTANCE,    btnW + margin);
   ObjectSetInteger(0, PFX + "B_CFGBTN", OBJPROP_YDISTANCE,    margin);
   ObjectSetInteger(0, PFX + "B_CFGBTN", OBJPROP_BORDER_COLOR, CLR_ACCENT);

   color  dirC = (p_Direccion == GRID_LONG) ? CLR_GREEN : CLR_RED;
   color  dirBg = (p_Direccion == GRID_LONG) ? CLR_GREEN_DEEP : CLR_RED_DEEP;
   string dirT = (p_Direccion == GRID_LONG) ? "▲ LONG" : "▼ SHORT";
   int badgeXDist = btnW + margin + gap + badgeW;
   PB("DIRBADGE", badgeXDist, margin, badgeW, btnH, dirT, dirBg, dirC, Sc(9), "Arial");
   ObjectSetInteger(0, PFX + "B_DIRBADGE", OBJPROP_CORNER,       CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, PFX + "B_DIRBADGE", OBJPROP_XDISTANCE,    badgeXDist);
   ObjectSetInteger(0, PFX + "B_DIRBADGE", OBJPROP_YDISTANCE,    margin);
   ObjectSetInteger(0, PFX + "B_DIRBADGE", OBJPROP_BORDER_COLOR, dirC);
}

//+------------------------------------------------------------------+
//| PANEL PRINCIPAL — REDISENADO                                     |
//+------------------------------------------------------------------+
void BorrarPanelTodo()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, PFX) != 0) continue;
      if(StringFind(n, PFX + "L_TP") == 0)       continue;
      if(StringFind(n, PFX + "L_SL") == 0)       continue;
      if(StringFind(n, PFX + "L_TECHO") == 0)    continue;
      if(StringFind(n, PFX + "L_PISO") == 0)     continue;
      if(StringFind(n, PFX + "L_TRIGGER") == 0)  continue;
      if(StringFind(n, PFX + "L_GRID_") == 0)    continue;
      if(StringFind(n, PFX + "L_TPACT_") == 0)   continue;
      if(StringFind(n, PFX + "T_") == 0)         continue;
      if(StringFind(n, PFX + "R_CFG_") == 0)     continue;
      if(StringFind(n, PFX + "L_CFG_") == 0)     continue;
      if(StringFind(n, PFX + "B_CFG_") == 0)     continue;
      if(StringFind(n, PFX + "E_CFG_") == 0)     continue;
      if(StringFind(n, PFX + "R_ALR") == 0)      continue;
      if(StringFind(n, PFX + "L_ALR") == 0)      continue;
      if(StringFind(n, PFX + "B_ALR") == 0)      continue;
      if(StringFind(n, PFX + "B_CFGBTN") == 0)   continue;
      if(StringFind(n, PFX + "B_DIRBADGE") == 0) continue;
      ObjectDelete(0, n);
   }
}

void DibujarPanel()
{
   RefreshScale();
   BorrarPanelTodo();

   // Panel ancho 256px (escalado) — etiquetas + valores con espacio garantizado
   int W   = Sc(256); int PAD = Sc(14); int HDR = Sc(36);
   int x   = PanelPosX; int y = PanelPosY;
   int sz8 = Sc(8); int sz9 = Sc(9); int sz10 = Sc(10); int sz11 = Sc(11); int sz12 = Sc(12);

   // Layout: etiqueta a la izquierda, valor anclado a la derecha
   int LBL_X    = x + PAD;
   int VAL_X    = x + W - PAD;     // alineado a la derecha
   int LH       = Sc(22);          // altura uniforme de fila
   int GAP      = Sc(10);
   int SEC_GAP  = Sc(6);

   string minIcon = PanelMinimized ? "+" : "−";
   int minSz  = Sc(22); int minY  = y + (HDR - minSz) / 2;
   int logoSz = Sc(24); int logoY = y + (HDR - logoSz) / 2;

   // Calculamos la altura total dinamicamente
   int totalH = PanelMinimized ? HDR : Sc(382);
   PR("BG",     x, y, W, totalH, CLR_PANEL,   CLR_BORDER_LT, 1);
   PR("BG_HDR", x, y, W, HDR,    CLR_BG_DEEP, CLR_BG_DEEP,   0);
   if(!PanelMinimized) PHR("HDR_LN", x, y + HDR - 1, W, CLR_BORDER);

   // Logo + titulo
   PB("LOGO", x + PAD, logoY, logoSz, logoSz, "G", CLR_ACCENT, CLR_TEXT, Sc(11), "Arial Black");
   ObjectSetInteger(0, PFX + "B_LOGO", OBJPROP_BORDER_COLOR, CLR_ACCENT);
   PL("HTIT", x + PAD + logoSz + Sc(9), y + (HDR - Sc(13))/2 + Sc(1), "GRIDBOT", CLR_TEXT, sz10, "Arial");
   PL("HVER", x + PAD + logoSz + Sc(9) + Sc(58), y + (HDR - Sc(13))/2 + Sc(2), "v3.6", CLR_TEXT_FAINT, sz8, "Arial");
   PB("MINBTN", x + W - PAD - minSz, minY, minSz, minSz, minIcon, CLR_ELEV, CLR_TEXT_DIM, Sc(11), "Arial");
   ObjectSetInteger(0, PFX + "B_MINBTN", OBJPROP_BORDER_COLOR, CLR_BORDER);
   DibujarBotonesEsquina();

   if(PanelMinimized) { ChartRedraw(0); return; }

   // Estado y direccion como BADGES
   string eStr; color eClr;
   switch(estado)
   {
      case PRECHECK: eStr = "PRE-CHECK"; eClr = CLR_AMBER;  break;
      case PENDING:  eStr = "PENDING";   eClr = CLR_ACCENT; break;
      case ACTIVE:   eStr = "ACTIVE";    eClr = CLR_GREEN;  break;
      case PAUSED:   eStr = "PAUSED";    eClr = CLR_AMBER;  break;
      case STOPPED:  eStr = "STOPPED";   eClr = CLR_RED;    break;
      default:       eStr = "???";       eClr = CLR_TEXT;
   }
   color eBg = (estado==PRECHECK || estado==PAUSED) ? CLR_AMBER_DEEP :
               (estado==ACTIVE) ? CLR_GREEN_DEEP :
               (estado==STOPPED) ? CLR_RED_DEEP : CLR_ACCENT_DEEP;
   color eBrd = (estado==PRECHECK || estado==PAUSED) ? CLR_AMBER_DIM :
                (estado==ACTIVE) ? CLR_GREEN_DIM :
                (estado==STOPPED) ? CLR_RED_DIM : CLR_ACCENT_DIM;

   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string ganS = (GananciaAcumulada >= 0 ? "+$" : "-$") + DoubleToString(MathAbs(GananciaAcumulada), 2);
   color  ganC = (GananciaAcumulada > 0) ? CLR_GREEN : (GananciaAcumulada < 0 ? CLR_RED : CLR_TEXT);
   color  rskC = (RiesgoRealPct > p_Risk) ? CLR_RED : CLR_GREEN;

   int cy = y + HDR + GAP;

   // ── ESTADO (badge) ──────────────────────────────────────────
   PL("ELAB", LBL_X, cy + Sc(4), "ESTADO", CLR_TEXT_FAINT, sz8, "Arial");
   int badW = Sc(94); int badH = Sc(20);
   PBadge("EBADGE", VAL_X - badW, cy + Sc(2), badW, badH, eStr, eClr, eBg, eBrd);
   cy += LH + Sc(2);

   // ── DIRECCION (badge) ───────────────────────────────────────
   PL("DLAB", LBL_X, cy + Sc(4), "DIRECCION", CLR_TEXT_FAINT, sz8, "Arial");
   color dC  = (p_Direccion == GRID_LONG) ? CLR_GREEN : CLR_RED;
   color dBg = (p_Direccion == GRID_LONG) ? CLR_GREEN_DEEP : CLR_RED_DEEP;
   color dBr = (p_Direccion == GRID_LONG) ? CLR_GREEN_DIM : CLR_RED_DIM;
   string dT = (p_Direccion == GRID_LONG) ? "LONG" : "SHORT";
   PBadge("DBADGE", VAL_X - badW, cy + Sc(2), badW, badH, dT, dC, dBg, dBr);
   cy += LH + SEC_GAP;

   PHR("S1", LBL_X, cy, W - PAD*2, CLR_BORDER); cy += SEC_GAP;

   // ── PRECIO ──────────────────────────────────────────────────
   PL("BLAB", LBL_X, cy + Sc(4), "PRECIO", CLR_TEXT_FAINT, sz8, "Arial");
   PLA("BVAL", VAL_X, cy + Sc(4), DoubleToString(bid, _Digits), CLR_TEXT, sz10, ANCHOR_RIGHT_UPPER, "Arial");
   cy += LH;

   // ── TRIGGER ─────────────────────────────────────────────────
   PL("TLAB", LBL_X, cy + Sc(4), "TRIGGER", CLR_TEXT_FAINT, sz8, "Arial");
   PLA("TVAL", VAL_X, cy + Sc(4), DoubleToString(p_Trigger, _Digits), CLR_ACCENT_2, sz10, ANCHOR_RIGHT_UPPER, "Arial");
   cy += LH + SEC_GAP;

   PHR("S2", LBL_X, cy, W - PAD*2, CLR_BORDER); cy += SEC_GAP;

   // ── RIESGO (header de seccion) ──────────────────────────────
   PL("RHTL", LBL_X, cy + Sc(2), "RIESGO", CLR_TEXT_MUTE, sz8, "Arial");
   PHR("S2B", LBL_X + Sc(46), cy + Sc(8), W - PAD*2 - Sc(46), CLR_BORDER);
   cy += Sc(18);

   // Objetivo
   PL("RCLA", LBL_X, cy + Sc(3), "Objetivo", CLR_TEXT_DIM, sz8, "Arial");
   PLA("RCVA", VAL_X, cy + Sc(3),
       DoubleToString(p_Risk,1)+"% · $"+DoubleToString(p_Capital*p_Risk/100,0),
       CLR_GREEN, sz9, ANCHOR_RIGHT_UPPER, "Arial");
   cy += LH;

   // Real
   PL("RRLA", LBL_X, cy + Sc(3), "Real", CLR_TEXT_DIM, sz8, "Arial");
   PLA("RRVA", VAL_X, cy + Sc(3),
       DoubleToString(RiesgoRealPct,1)+"% · $"+DoubleToString(RiesgoRealUSD,1),
       rskC, sz9, ANCHOR_RIGHT_UPPER, "Arial");
   cy += LH;

   // Uso/Cap — 2 líneas compactas para evitar solapamiento con etiqueta
   PL("GRLA", LBL_X, cy + Sc(2), "Uso / Cap", CLR_TEXT_DIM, sz8, "Arial");
   // Valor en 2 partes: rejillas/max derecha, max-seguro debajo-derecha
   PLA("GRVA",  VAL_X, cy + Sc(2),
       IntegerToString(RejillasActivas) + " / " + IntegerToString(p_MaxOrd),
       CLR_TEXT, sz9, ANCHOR_RIGHT_UPPER, "Arial");
   PLA("GRVA2", VAL_X, cy + Sc(14),
       "máx " + IntegerToString(MaxOrdersSafe),
       CLR_TEXT_DIM, sz8, ANCHOR_RIGHT_UPPER, "Arial");
   cy += LH + Sc(4);

   // Gan/rej
   PL("GPLA", LBL_X, cy + Sc(3), "Gan / rej", CLR_TEXT_DIM, sz8, "Arial");
   PLA("GPVA", VAL_X, cy + Sc(3),
       "$"+DoubleToString(GananciaPorRejilla,2),
       CLR_GREEN, sz9, ANCHOR_RIGHT_UPPER, "Arial");
   cy += LH + SEC_GAP;

   // ── GANANCIA (card destacada) ───────────────────────────────
   int gnH = Sc(44);
   PR("GNCARD", LBL_X, cy, W - PAD*2, gnH, CLR_INPUT, CLR_BORDER, 1);
   PL("GNLA",  LBL_X + Sc(10), cy + Sc(7),  "GANANCIA ACUMULADA", CLR_TEXT_FAINT, sz8, "Arial");
   PLA("GNVA", VAL_X - Sc(10), cy + Sc(22), ganS, ganC, sz12, ANCHOR_RIGHT_UPPER, "Arial");
   cy += gnH + GAP;

   // ── BOTONES ─────────────────────────────────────────────────
   int btnH = Sc(30);
   if(estado == PRECHECK || estado == STOPPED)
   {
      PB("START", LBL_X, cy, W - PAD*2, btnH, "▶ INICIAR BOT", CLR_GREEN_DIM, CLR_TEXT, sz9, "Arial");
      ObjectSetInteger(0, PFX + "B_START", OBJPROP_BORDER_COLOR, CLR_GREEN);
   }
   else if(estado == PENDING)
   {
      PB("CANCEL", LBL_X, cy, W - PAD*2, btnH, "✕ CANCELAR", CLR_RED_DIM, CLR_TEXT, sz9, "Arial");
      ObjectSetInteger(0, PFX + "B_CANCEL", OBJPROP_BORDER_COLOR, CLR_RED);
   }
   else if(estado == ACTIVE || estado == PAUSED)
   {
      int bw = (W - PAD*2 - Sc(6)) / 2;
      PB("PAUSE", LBL_X, cy, bw, btnH,
         (estado==ACTIVE)?"⏸ PAUSAR":"▶ REANUDAR", CLR_ACCENT_DIM, CLR_TEXT, sz8, "Arial");
      ObjectSetInteger(0, PFX + "B_PAUSE", OBJPROP_BORDER_COLOR, CLR_ACCENT);
      PB("STOP",  LBL_X + bw + Sc(6), cy, bw, btnH, "⏹ PARAR", CLR_RED_DIM, CLR_TEXT, sz8, "Arial");
      ObjectSetInteger(0, PFX + "B_STOP", OBJPROP_BORDER_COLOR, CLR_RED);
   }

   PanelH = (cy + btnH + GAP) - y;
   ObjectSetInteger(0, PFX + "R_BG", OBJPROP_YSIZE, PanelH);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| CONFIG DIALOG                                                    |
//+------------------------------------------------------------------+
int CFG_HDR_H=64, CFG_TABS_H=38, CFG_FOOT_H=58, CFG_BODY_PAD_TOP=18;
int CFG_ROW_GAP=58, CFG_PAD=20;

void BorrarConfigDialog()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, PFX + "R_CFG_") == 0 || StringFind(n, PFX + "L_CFG_") == 0 ||
         StringFind(n, PFX + "B_CFG_") == 0 || StringFind(n, PFX + "E_CFG_") == 0 ||
         n == PFX + "E_E_LIBRE")
         ObjectDelete(0, n);
   }
   ChartRedraw(0);
}

void CalcularLayoutConfig()
{
   double sc = GetUIScale();
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   CfgW = MathMin((int)(560*sc), cw - 40); if(CfgW < 460) CfgW = 460;
   CfgH = MathMin((int)(620*sc), ch - 40); if(CfgH < 460) CfgH = 460;
   CFG_HDR_H        = Sc(64);  CFG_TABS_H       = Sc(38);
   CFG_FOOT_H       = Sc(58);  CFG_BODY_PAD_TOP = Sc(18);
   CFG_ROW_GAP      = Sc(58);  CFG_PAD          = Sc(20);
}

void CfgField(string id, int x, int y, int w, string label, string val, string suffix = "")
{
   int inputH = Sc(28); int gap = Sc(18); int sufW = Sc(42); int lblSz = Sc(8);
   PL("CFG_" + id + "_L", x, y, label, CLR_TEXT_FAINT, lblSz, "Arial");
   if(suffix != "")
   {
      PE("CFG_" + id,         x,            y + gap, w - sufW - 2, inputH, val);
      PR("CFG_" + id + "_SB", x + w - sufW, y + gap, sufW, inputH, CLR_BG_DEEP, CLR_BORDER, 1);
      PL("CFG_" + id + "_S",  x + w - sufW + Sc(10), y + gap + (inputH - Sc(11))/2, suffix, CLR_TEXT_FAINT, lblSz, "Arial");
   }
   else
      PE("CFG_" + id, x, y + gap, w, inputH, val);
}

void DibujarBodyRango(int x, int y, int w, int hAvail);
void DibujarBodyRiesgo(int x, int y, int w, int hAvail);
void DibujarBodySalidas(int x, int y, int w, int hAvail);

void DibujarConfigDialog()
{
   if(!ConfigVisible) { BorrarConfigDialog(); return; }
   RefreshScale();
   if(ConfigMinimized)
   {
      BorrarConfigDialog();
      int bw = Sc(260); int bh = Sc(40);
      int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int bx = (cw - bw) / 2; int by = Sc(60);
      PR("CFG_BG",  bx, by, bw, bh, CLR_BG_DEEP, CLR_ACCENT, 2);
      PL("CFG_TIT", bx + Sc(14), by + (bh - Sc(13))/2 + Sc(1), "CONFIG (minimizada)", CLR_TEXT, Sc(10), "Arial");
      int rsz = bh - Sc(10);
      PB("CFG_MIN", bx + bw - rsz - rsz - Sc(12), by + Sc(5), rsz, rsz, "+", CLR_ELEV,    CLR_TEXT, Sc(11), "Arial");
      PB("CFG_X",   bx + bw - rsz - Sc(6),         by + Sc(5), rsz, rsz, "✕", CLR_RED_DIM, CLR_TEXT, Sc(11), "Arial");
      ChartRedraw(0); return;
   }

   CalcularLayoutConfig();
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(ConfigPosX < 0 || ConfigPosY < 0)
   {
      CfgX = (cw - CfgW) / 2; if(CfgX < 10) CfgX = 10;
      CfgY = (ch - CfgH) / 2; if(CfgY < 10) CfgY = 10;
      ConfigPosX = CfgX; ConfigPosY = CfgY;
   }
   else
   {
      CfgX = ConfigPosX; CfgY = ConfigPosY;
      if(CfgX + CfgW > cw) CfgX = cw - CfgW - 10;
      if(CfgY + CfgH > ch) CfgY = ch - CfgH - 10;
      if(CfgX < 10) CfgX = 10; if(CfgY < 10) CfgY = 10;
   }

   int x = CfgX, y = CfgY, W = CfgW, H = CfgH;
   int PAD = CFG_PAD; int FOOTER_H = CFG_FOOT_H; int HDR_H = CFG_HDR_H; int TABS_H = CFG_TABS_H;

   PR("CFG_BG",      x, y, W, H,     CLR_PANEL,   CLR_BORDER_LT, 1);
   PR("CFG_HDR",     x, y, W, HDR_H, CLR_BG_DEEP, CLR_BG_DEEP,   0);
   PHR("CFG_HDR_LN", x, y + HDR_H - 1, W, CLR_BORDER);

   int logoSize = Sc(30); int logoY = y + (HDR_H - logoSize) / 2;
   PB("CFG_LOGO", x + PAD, logoY, logoSize, logoSize, "G", CLR_ACCENT, CLR_TEXT, Sc(13), "Arial Black");
   ObjectSetInteger(0, PFX + "B_CFG_LOGO", OBJPROP_BORDER_COLOR, CLR_ACCENT);

   int titX  = x + PAD + logoSize + Sc(12);
   PL("CFG_TIT", titX, y + HDR_H/2 - Sc(12), "GridBot Configuration", CLR_TEXT, Sc(11), "Arial");
   PL("CFG_SUB", titX, y + HDR_H/2 + Sc(4),  "v3.6 · " + _Symbol, CLR_TEXT_FAINT, Sc(8), "Arial");

   string stBadge; color stBadgeC; color stBg; color stBrd;
   switch(estado)
   {
      case ACTIVE:   stBadge = "ACTIVE";   stBadgeC = CLR_GREEN;  stBg = CLR_GREEN_DEEP;  stBrd = CLR_GREEN_DIM;  break;
      case PAUSED:   stBadge = "PAUSED";   stBadgeC = CLR_AMBER;  stBg = CLR_AMBER_DEEP;  stBrd = CLR_AMBER_DIM;  break;
      case PENDING:  stBadge = "PENDING";  stBadgeC = CLR_ACCENT; stBg = CLR_ACCENT_DEEP; stBrd = CLR_ACCENT_DIM; break;
      case STOPPED:  stBadge = "STOPPED";  stBadgeC = CLR_RED;    stBg = CLR_RED_DEEP;    stBrd = CLR_RED_DIM;    break;
      case PRECHECK: stBadge = "PRE-CHK";  stBadgeC = CLR_AMBER;  stBg = CLR_AMBER_DEEP;  stBrd = CLR_AMBER_DIM;  break;
      default:       stBadge = "READY";   stBadgeC = CLR_AMBER;  stBg = CLR_AMBER_DEEP;  stBrd = CLR_AMBER_DIM;
   }
   int badgeW = Sc(88); int badgeH = Sc(24); int badgeY = y + (HDR_H - badgeH) / 2;
   int closeW = Sc(26); int closeH = badgeH; int minW = closeW; int gap = Sc(6);

   PBadge("CFG_ST", x + W - PAD - closeW - gap - minW - gap - badgeW, badgeY, badgeW, badgeH, stBadge, stBadgeC, stBg, stBrd);
   PB("CFG_MIN", x + W - PAD - closeW - gap - minW, badgeY, minW,   closeH, "−", CLR_ELEV,    CLR_TEXT_DIM, Sc(11), "Arial");
   ObjectSetInteger(0, PFX + "B_CFG_MIN", OBJPROP_BORDER_COLOR, CLR_BORDER);
   PB("CFG_X",   x + W - PAD - closeW,              badgeY, closeW, closeH, "✕", CLR_RED_DIM, CLR_TEXT,     Sc(10), "Arial");
   ObjectSetInteger(0, PFX + "B_CFG_X", OBJPROP_BORDER_COLOR, CLR_RED_DIM);

   // Tabs
   int tabsY = y + HDR_H;
   PR("CFG_TBG",     x, tabsY, W, TABS_H, CLR_BG_DEEP, CLR_BG_DEEP, 0);
   PHR("CFG_TBG_LN", x, tabsY + TABS_H - 1, W, CLR_BORDER);
   string tabLabels[3] = {"RANGO", "RIESGO", "SALIDAS"};
   int tw  = W / 3;
   int tw2 = W - 2 * tw;
   for(int i = 0; i < 3; i++)
   {
      int tabW = (i < 2) ? tw : tw2;
      bool act = (i == ConfigTab);
      PB("CFG_T" + IntegerToString(i), x + i*tw, tabsY, tabW, TABS_H - 2, tabLabels[i],
         CLR_BG_DEEP, act ? CLR_TEXT : CLR_TEXT_FAINT, Sc(9), "Arial");
      if(act)
      {
         // Underline azul
         PR("CFG_T" + IntegerToString(i) + "_IND", x + i*tw, tabsY + TABS_H - Sc(2), tabW, Sc(2), CLR_ACCENT, CLR_ACCENT, 0);
      }
      else DelObj("R_CFG_T" + IntegerToString(i) + "_IND");
   }

   int by = tabsY + TABS_H + CFG_BODY_PAD_TOP;
   int bodyW = W - PAD * 2;
   int bodyMaxH = (y + H - FOOTER_H) - by - Sc(8);
   if(ConfigTab == 0)      DibujarBodyRango(x + PAD,  by, bodyW, bodyMaxH);
   else if(ConfigTab == 1) DibujarBodyRiesgo(x + PAD, by, bodyW, bodyMaxH);
   else                    DibujarBodySalidas(x + PAD, by, bodyW, bodyMaxH);

   int fy = y + H - FOOTER_H;
   PHR("CFG_FT_LN", x, fy, W, CLR_BORDER);
   PR("CFG_FT",     x, fy + 1, W, FOOTER_H - 1, CLR_BG_DEEP, CLR_BG_DEEP, 0);
   int btnGap = Sc(12); int btnTotalW = W - PAD*2;
   int cancelW = (btnTotalW - btnGap) / 2; int applyW = btnTotalW - cancelW - btnGap;
   int btnH = Sc(32); int btnY = fy + (FOOTER_H - btnH) / 2;
   PB("CFG_CANCEL", x + PAD,                    btnY, cancelW, btnH, "CANCELAR", CLR_ELEV, CLR_TEXT_DIM, Sc(9), "Arial");
   ObjectSetInteger(0, PFX + "B_CFG_CANCEL", OBJPROP_BORDER_COLOR, CLR_BORDER_LT);
   PB("CFG_APPLY",  x + PAD + cancelW + btnGap, btnY, applyW,  btnH, "APLICAR",  CLR_ACCENT, CLR_TEXT, Sc(10), "Arial");
   ObjectSetInteger(0, PFX + "B_CFG_APPLY", OBJPROP_BORDER_COLOR, CLR_ACCENT_2);
   ChartRedraw(0);
   ResetCacheEdits();
}

//+------------------------------------------------------------------+
//| BODY RANGO                                                       |
//+------------------------------------------------------------------+
void DibujarBodyRango(int x, int y, int w, int hAvail)
{
   int colW   = (w - Sc(14)) / 2;
   int rowGap = CFG_ROW_GAP;
   int dirH   = Sc(32);
   int padIn  = Sc(14);

   // --- Bloque DIRECCION (toggle estilo segmented) ---
   PL("CFG_DIR_L", x, y, "DIRECCION DEL GRID", CLR_TEXT_FAINT, Sc(8), "Arial");
   int togBgY = y + Sc(16);
   PR("CFG_DIR_BG", x, togBgY, w, dirH + Sc(6), CLR_INPUT, CLR_BORDER, 1);
   int dirBtnW = (w - Sc(10)) / 2 - Sc(3);
   bool isLong = (p_Direccion == GRID_LONG);
   PB("CFG_DIR_LONG",  x + Sc(3),                    togBgY + Sc(3), dirBtnW, dirH, "▲ LONG",
      isLong ? CLR_GREEN_DIM : CLR_INPUT, isLong ? CLR_TEXT : CLR_TEXT_FAINT, Sc(10), "Arial");
   if(isLong) ObjectSetInteger(0, PFX + "B_CFG_DIR_LONG", OBJPROP_BORDER_COLOR, CLR_GREEN);
   PB("CFG_DIR_SHORT", x + Sc(7) + dirBtnW, togBgY + Sc(3), dirBtnW, dirH, "▼ SHORT",
      isLong ? CLR_INPUT : CLR_RED_DIM, isLong ? CLR_TEXT_FAINT : CLR_TEXT, Sc(10), "Arial");
   if(!isLong) ObjectSetInteger(0, PFX + "B_CFG_DIR_SHORT", OBJPROP_BORDER_COLOR, CLR_RED);

   int yStart = y;
   y += Sc(64);

   // --- Fila 1: TECHO / PISO ---
   CfgField("E_TECHO",   x,                 y, colW, "TECHO", DoubleToString(p_Techo, _Digits));
   CfgField("E_PISO",    x + colW + Sc(14), y, colW, "PISO",  DoubleToString(p_Piso,  _Digits));

   // --- Fila 2: TRIGGER ---
   CfgField("E_TRIGGER", x, y + rowGap, w, "TRIGGER — PRECIO DE ACTIVACION", DoubleToString(p_Trigger, _Digits));

   // --- Fila 3: G% / VOLUMEN ---
   CfgField("E_G",   x,                 y + rowGap*2, colW, "PASO GEOMETRICO", DoubleToString(p_G, 4),   "%");
   CfgField("E_VOL", x + colW + Sc(14), y + rowGap*2, colW, "VOLUMEN",         DoubleToString(p_Vol, 2), "LOT");

   // --- Card RANGO ACTIVO ---
   int cyTop     = y + rowGap * 2 + Sc(64);
   int yFinDispo = yStart + hAvail;
   int cardH     = MathMin(Sc(150), yFinDispo - cyTop - Sc(4));
   if(cardH < Sc(80)) return;

   PR("CFG_RANGE_CARD", x, cyTop, w, cardH, CLR_INPUT, CLR_BORDER, 1);

   double distOp = (p_Direccion == GRID_LONG)
                   ? MathAbs(p_Trigger - p_Piso)
                   : MathAbs(p_Techo   - p_Trigger);
   string strNiveles = IntegerToString(MathMax(1, ArraySize(GridLevels))) + " niveles";
   string strPips    = DoubleToString(ToPips(distOp), 1) + " pips";
   string strRef     = (p_Direccion == GRID_LONG)
                       ? DoubleToString(p_Piso, _Digits) + "  →  " + DoubleToString(p_Trigger, _Digits)
                       : DoubleToString(p_Trigger, _Digits) + "  →  " + DoubleToString(p_Techo, _Digits);

   int ty1 = cyTop + Sc(12);
   int ty2 = ty1   + Sc(20);
   int ty3 = ty2   + Sc(22);

   PL("CFG_RC_HD",   x + padIn, ty1, "RANGO ACTIVO · PROYECCION", CLR_TEXT_FAINT, Sc(8), "Arial");
   PL("CFG_RC_NUM",  x + padIn, ty2, strNiveles + "  |  " + strPips, CLR_ACCENT_2, Sc(13), "Arial");
   PL("CFG_RC_SUB",  x + padIn, ty3, strRef, CLR_TEXT_DIM, Sc(9), "Consolas");

   // Mini-grafico
   int minAxisY = ty3 + Sc(24);
   int axisY    = MathMax(minAxisY, cyTop + cardH - Sc(22));
   int axisX    = x + padIn;
   int axisW    = w - padIn * 2;

   if(axisY <= cyTop + cardH - Sc(6))
   {
      // Track
      PR("CFG_RC_TRACK", axisX, axisY, axisW, Sc(4), CLR_BG_DEEP, CLR_BORDER, 1);

      // Zone (zona LONG/SHORT)
      double rangeTot = MathMax(p_Techo - p_Piso, 0.00001);
      double trgPct   = MathMax(0.0, MathMin(1.0, (p_Trigger - p_Piso) / rangeTot));
      int    trgX     = axisX + (int)(axisW * trgPct);

      int zoneX  = (p_Direccion == GRID_LONG) ? axisX : trgX;
      int zoneW2 = (p_Direccion == GRID_LONG) ? MathMax(0, trgX - axisX) : MathMax(0, axisX + axisW - trgX);
      if(zoneW2 > 2)
         PR("CFG_RC_ZONE", zoneX, axisY, zoneW2, Sc(4), CLR_ACCENT_DIM, CLR_ACCENT_DIM, 0);

      // Marks PISO/TECHO (ambar)
      PVR("CFG_RC_PISO",  axisX,             axisY - Sc(6), Sc(16), CLR_AMBER);
      PVR("CFG_RC_TECHO", axisX + axisW - 1, axisY - Sc(6), Sc(16), CLR_AMBER);

      // Trigger dot
      int dotSz = Sc(10);
      PR("CFG_RC_TRG", trgX - dotSz/2, axisY - dotSz/2 + Sc(2), dotSz, dotSz, CLR_ACCENT, CLR_ACCENT_2, 1);

      // Labels
      PL("CFG_RC_PISO_L",  axisX,                  axisY + Sc(8), "PISO",  CLR_AMBER, Sc(7), "Arial");
      PLA("CFG_RC_TECHO_L", axisX + axisW,         axisY + Sc(8), "TECHO", CLR_AMBER, Sc(7), ANCHOR_RIGHT_UPPER, "Arial");
      PLA("CFG_RC_TRG_L", trgX,                    axisY - Sc(20), "TRG", CLR_ACCENT_2, Sc(7), ANCHOR_LOWER, "Arial");
   }
}

//+------------------------------------------------------------------+
//| BODY RIESGO                                                      |
//+------------------------------------------------------------------+
void DibujarBodyRiesgo(int x, int y, int w, int hAvail)
{
   int colW = (w - Sc(12)) / 2;
   int rowGap = CFG_ROW_GAP;
   int togH = Sc(28);
   int togGap = Sc(18);

   CfgField("E_CAP",  x,                 y,          colW, "CAPITAL",         DoubleToString(p_Capital, 2), "USD");
   CfgField("E_RISK", x + colW + Sc(12), y,          colW, "RIESGO OBJETIVO", DoubleToString(p_Risk, 2),    "%");
   CfgField("E_MAXO", x,                 y + rowGap, colW, "MAX ORDENES",     IntegerToString(p_MaxOrd));

   PL("CFG_ML_L", x + colW + Sc(12), y + rowGap, "MODO LIBRE", CLR_TEXT_FAINT, Sc(8), "Arial");
   bool freeOff = !p_Libre;
   int togBgX = x + colW + Sc(12);
   int togBgY = y + rowGap + togGap;
   PR("CFG_ML_BG", togBgX, togBgY, colW, togH + Sc(4), CLR_INPUT, CLR_BORDER, 1);
   int togBtnW = (colW - Sc(8)) / 2;
   PB("CFG_ML_OFF", togBgX + Sc(2),                togBgY + Sc(2), togBtnW, togH, "OFF",
      freeOff  ? CLR_ELEV : CLR_INPUT,
      freeOff  ? CLR_TEXT : CLR_TEXT_FAINT, Sc(9), "Arial");
   if(freeOff) ObjectSetInteger(0, PFX + "B_CFG_ML_OFF", OBJPROP_BORDER_COLOR, CLR_BORDER_LT);
   PB("CFG_ML_ON",  togBgX + Sc(6) + togBtnW, togBgY + Sc(2), togBtnW, togH, "ON",
      !freeOff ? CLR_ACCENT_DEEP : CLR_INPUT,
      !freeOff ? CLR_TEXT       : CLR_TEXT_FAINT, Sc(9), "Arial");
   if(!freeOff) ObjectSetInteger(0, PFX + "B_CFG_ML_ON", OBJPROP_BORDER_COLOR, CLR_ACCENT_DIM);
   PE("E_LIBRE", togBgX, togBgY, 1, 1, p_Libre ? "true" : "false");
   ObjectSetInteger(0, PFX + "E_E_LIBRE", OBJPROP_HIDDEN, true);

   int cardH = Sc(176);
   int cyTop = y + rowGap * 2 + Sc(8);
   int yFinDispo = y + hAvail;
   if(cyTop + cardH > yFinDispo) cardH = MathMax(Sc(150), yFinDispo - cyTop);

   bool  excedido    = (RiesgoRealPct > p_Risk);
   bool  maxExcedido = (p_MaxOrd > ArraySize(GridLevels));
   color cardBorder  = excedido ? CLR_RED_DIM : CLR_GREEN_DIM;
   PR("CFG_RSK_CARD", x, cyTop, w, cardH, CLR_INPUT, cardBorder, 1);

   int padIn = Sc(14);

   // Status row: dot + texto (izq) + pill (der)
   int dotSz = Sc(10);
   PR("CFG_RSK_DOT", x + padIn, cyTop + Sc(15), dotSz, dotSz,
      excedido ? CLR_RED : CLR_GREEN, excedido ? CLR_RED : CLR_GREEN, 0);
   PL("CFG_RSK_HD", x + padIn + dotSz + Sc(8), cyTop + Sc(13),
      excedido ? "RIESGO EXCEDIDO" : "RIESGO OK", excedido ? CLR_RED : CLR_GREEN, Sc(10), "Arial");

   if(excedido)
   {
      double over = (RiesgoRealPct / MathMax(p_Risk, 0.01) - 1.0) * 100.0;
      string overTxt = "+" + DoubleToString(over, 0) + "% sobre objetivo";
      int pillW = Sc(146); int pillH = Sc(20);
      PR("CFG_RSK_BG", x + w - padIn - pillW, cyTop + Sc(11), pillW, pillH, CLR_RED_DEEP, CLR_RED_DIM, 1);
      PL("CFG_RSK_BT", x + w - padIn - pillW + Sc(8), cyTop + Sc(13), overTxt, CLR_RED, Sc(8), "Arial");
   }
   else if(maxExcedido)
   {
      int totalNiv = ArraySize(GridLevels);
      string overTxt = "tope " + IntegerToString(totalNiv);
      int pillW = Sc(74); int pillH = Sc(20);
      PR("CFG_RSK_BG", x + w - padIn - pillW, cyTop + Sc(11), pillW, pillH, CLR_AMBER_DEEP, CLR_AMBER_DIM, 1);
      PL("CFG_RSK_BT", x + w - padIn - pillW + Sc(8), cyTop + Sc(13), overTxt, CLR_AMBER, Sc(8), "Arial");
   }

   // Info row
   int totalNiveles = ArraySize(GridLevels);
   string infoNiv = "Capacidad: " + IntegerToString(totalNiveles) + " rej   ·   Uso: " + IntegerToString(p_MaxOrd) + "   ·   Seguro: " + IntegerToString(MaxOrdersSafe);
   PL("CFG_RSK_NIV", x + padIn, cyTop + Sc(38), infoNiv, CLR_TEXT_DIM, Sc(8), "Consolas");

   // Stats: 3 columnas
   int statW  = (w - padIn*2 - Sc(20)) / 3;
   int statsY = cyTop + Sc(60);
   PL("CFG_RSK_S1L", x + padIn,                    statsY,          "REAL %",      CLR_TEXT_FAINT, Sc(8), "Arial");
   PL("CFG_RSK_S1V", x + padIn,                    statsY + Sc(15), DoubleToString(RiesgoRealPct, 2), excedido ? CLR_RED : CLR_GREEN, Sc(14), "Arial");

   PL("CFG_RSK_S2L", x + padIn + statW + Sc(10),   statsY,          "PERDIDA POT.", CLR_TEXT_FAINT, Sc(8), "Arial");
   PL("CFG_RSK_S2V", x + padIn + statW + Sc(10),   statsY + Sc(15), "$" + DoubleToString(RiesgoRealUSD, 2), excedido ? CLR_RED : CLR_GREEN, Sc(14), "Arial");

   PL("CFG_RSK_S3L", x + padIn + (statW+Sc(10))*2, statsY,          "SEGURO",       CLR_TEXT_FAINT, Sc(8), "Arial");
   PL("CFG_RSK_S3V", x + padIn + (statW+Sc(10))*2, statsY + Sc(15), IntegerToString(MaxOrdersSafe) + " rej", CLR_AMBER, Sc(14), "Arial");

   // Barra de progreso
   int barY = cyTop + Sc(118);
   if(barY + Sc(28) <= cyTop + cardH - Sc(8))
   {
      PL("CFG_RSK_BL1",  x + padIn,                   barY, "0%",  CLR_TEXT_FAINT, Sc(7), "Arial");
      PLA("CFG_RSK_BL2", x + padIn + (w-padIn*2)/2,  barY, "OBJ " + DoubleToString(p_Risk,1) + "%", CLR_AMBER, Sc(7), ANCHOR_UPPER, "Arial");
      PLA("CFG_RSK_BL3", x + w - padIn,              barY, "2x",  CLR_TEXT_FAINT, Sc(7), ANCHOR_RIGHT_UPPER, "Arial");

      PR("CFG_RSK_BAR_BG", x + padIn, barY + Sc(14), w - padIn*2, Sc(8), CLR_BORDER, CLR_BORDER, 0);
      double fillPct = MathMin(RiesgoRealPct / (p_Risk * 2.0), 1.0);
      int    fillW   = (int)((w - padIn*2) * fillPct);
      if(fillW > 0)
         PR("CFG_RSK_BAR_FL", x + padIn, barY + Sc(14), fillW, Sc(8),
            excedido ? CLR_RED : CLR_GREEN, excedido ? CLR_RED : CLR_GREEN, 0);
      // Marker objetivo (50% = OBJ)
      PVR("CFG_RSK_BAR_MK", x + padIn + (w - padIn*2)/2, barY + Sc(11), Sc(14), CLR_AMBER);
   }
}

//+------------------------------------------------------------------+
//| BODY SALIDAS                                                     |
//+------------------------------------------------------------------+
void DibujarBodySalidas(int x, int y, int w, int hAvail)
{
   int colW = (w - Sc(12)) / 2;
   CfgField("E_TP", x,                 y, colW, "TAKE PROFIT GLOBAL", DoubleToString(p_TP, _Digits));
   CfgField("E_SL", x + colW + Sc(12), y, colW, "STOP LOSS GLOBAL",   DoubleToString(p_SL, _Digits));

   int cyTop = y + Sc(64);
   int cardH = Sc(270);   // aumentado: acomoda sepH=40 + rrCard sin recortar
   int yFinDispo = y + hAvail;
   if(cyTop + cardH > yFinDispo) cardH = MathMax(Sc(220), yFinDispo - cyTop);

   PR("CFG_EXT_CARD", x, cyTop, w, cardH, CLR_INPUT, CLR_BORDER, 1);

   int padIn = Sc(14);
   PL("CFG_EXT_HD", x + padIn, cyTop + Sc(12), "DISTANCIAS DESDE TRIGGER", CLR_TEXT_FAINT, Sc(8), "Arial");

   double dist_tp   = MathAbs(p_TP      - p_Trigger);
   double dist_sl   = MathAbs(p_Trigger - p_SL);
   double pips_tp   = ToPips(dist_tp);
   double pips_sl   = ToPips(dist_sl);
   double maxD      = MathMax(dist_tp, dist_sl);

   int tagW   = Sc(34);
   int pctW   = Sc(72);
   int barX   = x + padIn + tagW + Sc(8);
   int barW   = w - padIn*2 - tagW - pctW - Sc(16);
   int rowH   = Sc(30);
   // sepH ampliado: TRG label (sz11 ≈ 14px) + línea + margen antes del SL bar
   // Distribución interna: [4px top] [14px text] [10px gap] [1px line] [11px bottom] = 40px
   int sepH   = Sc(40);

   int rowY = cyTop + Sc(34);
   int sepY = rowY + rowH + Sc(8);   // +8 en lugar de +6 para más aire entre TP bar y TRG
   int slY  = sepY + sepH;

   // --- Fila TP ---
   PL("CFG_EXT_TPL",  x + padIn, rowY + (rowH-Sc(11))/2, "TP", CLR_GREEN, Sc(11), "Arial");
   PR("CFG_EXT_TPBG", barX,      rowY, barW, rowH, CLR_BG_DEEP, CLR_BORDER, 1);
   int tpBarW = MathMax(0, (int)(barW * (dist_tp / MathMax(maxD, 0.0001))));
   if(tpBarW > Sc(3))
      PR("CFG_EXT_TPFL", barX + Sc(3), rowY + 1, tpBarW - Sc(3), rowH - 2, CLR_GREEN_DEEP, CLR_GREEN_DEEP, 0);
   PR("CFG_EXT_TPLN", barX, rowY, Sc(3), rowH, CLR_GREEN, CLR_GREEN, 0);
   PL("CFG_EXT_TPV", barX + Sc(12), rowY + (rowH-Sc(11))/2,
      "+" + DoubleToString(pips_tp, 1) + " pips", CLR_GREEN, Sc(10), "Arial");
   PLA("CFG_EXT_TPP", x + w - padIn, rowY + (rowH-Sc(11))/2,
      "+" + DoubleToString(dist_tp / MathMax(p_Trigger, 0.0001) * 100, 2) + "%",
      CLR_GREEN, Sc(10), ANCHOR_RIGHT_UPPER, "Arial");

   // --- Separador TRG: texto arriba + línea debajo bien separados ---
   int trgTextY = sepY + Sc(4);           // texto "TRG" y valor: zona superior
   int trgLineY = sepY + Sc(24);          // línea horizontal: zona inferior (separada del texto)
   PL("CFG_EXT_TGL",  x + padIn, trgTextY, "TRG", CLR_ACCENT_2, Sc(11), "Arial");
   PHR("CFG_EXT_TGLN", barX, trgLineY, barW, CLR_ACCENT);
   PLA("CFG_EXT_TGV", x + w - padIn, trgTextY, DoubleToString(p_Trigger, _Digits),
       CLR_ACCENT_2, Sc(10), ANCHOR_RIGHT_UPPER, "Consolas");

   // --- Fila SL ---
   PL("CFG_EXT_SLL", x + padIn, slY + (rowH-Sc(11))/2, "SL", CLR_RED, Sc(11), "Arial");
   PR("CFG_EXT_SLBG", barX, slY, barW, rowH, CLR_BG_DEEP, CLR_BORDER, 1);
   int slBarW = MathMax(0, (int)(barW * (dist_sl / MathMax(maxD, 0.0001))));
   if(slBarW > Sc(3))
      PR("CFG_EXT_SLFL", barX + Sc(3), slY + 1, slBarW - Sc(3), rowH - 2, CLR_RED_DEEP, CLR_RED_DEEP, 0);
   PR("CFG_EXT_SLLN", barX, slY, Sc(3), rowH, CLR_RED, CLR_RED, 0);
   PL("CFG_EXT_SLV", barX + Sc(12), slY + (rowH-Sc(11))/2,
      "−" + DoubleToString(pips_sl, 1) + " pips", CLR_RED, Sc(10), "Arial");
   PLA("CFG_EXT_SLP", x + w - padIn, slY + (rowH-Sc(11))/2,
      "−" + DoubleToString(dist_sl / MathMax(p_Trigger, 0.0001) * 100, 2) + "%",
      CLR_RED, Sc(10), ANCHOR_RIGHT_UPPER, "Arial");

   // --- Risk/Reward card ---
   double rr     = pips_tp / MathMax(pips_sl, 0.00001);
   bool   rrGood = (rr >= 1.5);
   color  rrColor = rrGood ? CLR_GREEN : (rr >= 1.0 ? CLR_AMBER : CLR_RED);
   color  rrBg    = rrGood ? CLR_GREEN_DEEP : (rr >= 1.0 ? CLR_AMBER_DEEP : CLR_RED_DEEP);
   color  rrBrd   = rrGood ? CLR_GREEN_DIM : (rr >= 1.0 ? CLR_AMBER_DIM : CLR_RED_DIM);
   int rrY = slY + rowH + Sc(14); int rrH = Sc(56);
   if(rrY + rrH <= cyTop + cardH - Sc(6))
   {
      PR("CFG_EXT_RR_BG", x + padIn, rrY, w - padIn*2, rrH, CLR_BG_DEEP, rrBrd, 1);
      PL("CFG_EXT_RR_L",  x + padIn + Sc(14), rrY + Sc(10), "RISK / REWARD", CLR_TEXT_FAINT, Sc(8), "Arial");
      PL("CFG_EXT_RR_V",  x + padIn + Sc(14), rrY + Sc(28), "1 : " + DoubleToString(rr, 2), rrColor, Sc(15), "Arial");
      string rrLabel = rrGood ? "OPTIMO" : (rr >= 1.0 ? "ACEPTABLE" : "SUBOPTIMO");
      int badgeW = Sc(100); int badgeH = Sc(28);  // badge más ancho para texto largo
      int badgeX = x + w - padIn - badgeW;        // alineado al borde derecho interno
      int badgeY = rrY + (rrH - badgeH) / 2;
      PR("CFG_EXT_RR_PT", badgeX, badgeY, badgeW, badgeH, rrBg, rrBrd, 1);
      // PL left-aligned (no PLA ANCHOR_UPPER) para que el texto nunca desborde a la derecha
      PL("CFG_EXT_RR_PL", badgeX + Sc(12), badgeY + (badgeH - Sc(11))/2, rrLabel, rrColor, Sc(9), "Arial");
   }
}

//+------------------------------------------------------------------+
//| APLICAR CONFIG                                                   |
//+------------------------------------------------------------------+
void CalcularRejillas();

void AplicarConfiguracionAuto()
{
   ChartRedraw(0);
   if(ObjectFind(0, PFX + "E_CFG_E_TECHO") >= 0)
   {
      double vt = StringToDouble(GetEdit("CFG_E_TECHO")); double vp = StringToDouble(GetEdit("CFG_E_PISO"));
      double vtr = StringToDouble(GetEdit("CFG_E_TRIGGER")); double vg = StringToDouble(GetEdit("CFG_E_G"));
      double vv = StringToDouble(GetEdit("CFG_E_VOL"));
      if(vt > vp && vtr >= vp && vtr <= vt && vg > 0 && vv > 0)
         { p_Techo = vt; p_Piso = vp; p_Trigger = vtr; p_G = vg; p_Vol = vv; }
   }
   if(ObjectFind(0, PFX + "E_CFG_E_CAP") >= 0)
   {
      double vc = StringToDouble(GetEdit("CFG_E_CAP")); double vr = StringToDouble(GetEdit("CFG_E_RISK"));
      int vm = (int)StringToInteger(GetEdit("CFG_E_MAXO"));
      if(vc > 0 && vr > 0 && vr <= 100 && vm > 0) { p_Capital = vc; p_Risk = vr; p_MaxOrd = vm; }
   }
   if(ObjectFind(0, PFX + "E_CFG_E_TP") >= 0)
   {
      double vtp = StringToDouble(GetEdit("CFG_E_TP")); double vsl = StringToDouble(GetEdit("CFG_E_SL"));
      bool ok = (p_Direccion == GRID_LONG) ? (vtp > p_Trigger && vsl < p_Trigger) : (vtp < p_Trigger && vsl > p_Trigger);
      if(ok) { p_TP = vtp; p_SL = vsl; }
   }
   CalcularRejillas(); CalcularRiesgo(); DibujarLineasGrid(); DibujarPanel(); RedibujarSoloVisualesBody();
}

void AplicarConfiguracion()
{
   bool aplicado = false;
   if(ConfigTab == 0)
   {
      double vt = StringToDouble(GetEdit("CFG_E_TECHO")); double vp = StringToDouble(GetEdit("CFG_E_PISO"));
      double vtr = StringToDouble(GetEdit("CFG_E_TRIGGER")); double vg = StringToDouble(GetEdit("CFG_E_G"));
      double vv = StringToDouble(GetEdit("CFG_E_VOL"));
      if(vt > vp && vtr >= vp && vtr <= vt && vg > 0 && vv > 0)
         { p_Techo = vt; p_Piso = vp; p_Trigger = vtr; p_G = vg; p_Vol = vv; aplicado = true; }
      else MostrarAlerta("DATOS INVALIDOS", "Rango invalido. Techo > Piso, Trigger entre ambos, G% > 0, Vol > 0.", "", ALERT_ERROR);
   }
   else if(ConfigTab == 1)
   {
      double vc = StringToDouble(GetEdit("CFG_E_CAP")); double vr = StringToDouble(GetEdit("CFG_E_RISK"));
      int vm = (int)StringToInteger(GetEdit("CFG_E_MAXO")); string vl = GetEdit("E_LIBRE");
      if(vc > 0 && vr > 0 && vr <= 100 && vm > 0)
         { p_Capital = vc; p_Risk = vr; p_MaxOrd = vm; p_Libre = (vl == "true" || vl == "1"); aplicado = true; }
      else MostrarAlerta("DATOS INVALIDOS", "Capital > 0, Riesgo 0-100, Max Ordenes > 0.", "", ALERT_ERROR);
   }
   else
   {
      double vtp = StringToDouble(GetEdit("CFG_E_TP")); double vsl = StringToDouble(GetEdit("CFG_E_SL"));
      bool ok = (p_Direccion == GRID_LONG) ? (vtp > p_Trigger && vsl < p_Trigger) : (vtp < p_Trigger && vsl > p_Trigger);
      if(ok) { p_TP = vtp; p_SL = vsl; aplicado = true; }
      else
      {
         string msg = (p_Direccion == GRID_LONG) ? "LONG: TP > Trigger y SL < Trigger." : "SHORT: TP < Trigger y SL > Trigger.";
         MostrarAlerta("DATOS INVALIDOS", "TP/SL no respetan la direccion.", msg, ALERT_ERROR);
      }
   }
   if(aplicado)
   {
      CalcularRejillas(); CalcularRiesgo(); DibujarLineasGrid(); DibujarPanel();
      PE_Force("CFG_E_TECHO",   DoubleToString(p_Techo,   _Digits));
      PE_Force("CFG_E_PISO",    DoubleToString(p_Piso,    _Digits));
      PE_Force("CFG_E_TRIGGER", DoubleToString(p_Trigger, _Digits));
      PE_Force("CFG_E_G",       DoubleToString(p_G, 4));
      PE_Force("CFG_E_VOL",     DoubleToString(p_Vol, 2));
      PE_Force("CFG_E_CAP",     DoubleToString(p_Capital, 2));
      PE_Force("CFG_E_RISK",    DoubleToString(p_Risk, 2));
      PE_Force("CFG_E_MAXO",    IntegerToString(p_MaxOrd));
      PE_Force("CFG_E_TP",      DoubleToString(p_TP, _Digits));
      PE_Force("CFG_E_SL",      DoubleToString(p_SL, _Digits));
      ResetCacheEdits(); RedibujarSoloVisualesBody();
   }
}

//+------------------------------------------------------------------+
//| LOGICA DE TRADING (igual que v3.5 — sin cambios)                 |
//+------------------------------------------------------------------+
void CalcularRejillas()
{
   ArrayResize(GridLevels, 0);
   const int MAX_NIVELES = 500;
   int count = 0;
   double nivel = p_Trigger;

   if(p_Direccion == GRID_LONG)
      while(nivel >= p_Piso && count < MAX_NIVELES)  { count++; nivel /= (1.0 + p_G); }
   else
      while(nivel <= p_Techo && count < MAX_NIVELES) { count++; nivel *= (1.0 + p_G); }

   if(count == MAX_NIVELES)
      PrintFormat("ADVERTENCIA: Grid limitado a %d niveles. Considera aumentar G%% o reducir el rango.", MAX_NIVELES);

   ArrayResize(GridLevels, count);

   nivel = p_Trigger;
   if(p_Direccion == GRID_LONG)
      for(int i = 0; i < count; i++) { GridLevels[i] = NormalizeDouble(nivel, _Digits); nivel /= (1.0 + p_G); }
   else
      for(int i = 0; i < count; i++) { GridLevels[i] = NormalizeDouble(nivel, _Digits); nivel *= (1.0 + p_G); }

   PrintFormat("Rejillas calculadas (%s): %d niveles", p_Direccion == GRID_LONG ? "LONG" : "SHORT", count);
}

bool ValidarInputs()
{
   if(Magic_Number == 0)                          { Print("ERROR: Magic=0");            return false; }
   if(p_Piso <= 0)                                { Print("ERROR: Piso debe ser > 0");  return false; }
   if(p_Piso >= p_Techo)                          { Print("ERROR: Piso >= Techo");       return false; }
   if(p_G <= 0)                                   { Print("ERROR: G% <= 0");                    return false; }
   if(p_G > 0.20)                                 { Print("ERROR: G% > 20% — paso irrazonable"); return false; }
   if(p_MaxOrd <= 0)                              { Print("ERROR: MaxOrdenes <= 0");     return false; }
   if(p_Trigger < p_Piso || p_Trigger > p_Techo) { Print("ERROR: Trigger fuera rango"); return false; }
   if(p_Capital <= 0)                             { Print("ERROR: Capital <= 0");        return false; }

   double volMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(p_Vol < volMin)
   {
      PrintFormat("ERROR: Volumen %.2f < minimo del broker %.2f", p_Vol, volMin);
      return false;
   }
   if(volStep > 0) p_Vol = MathRound(p_Vol / volStep) * volStep;
   if(p_Vol <= 0) { Print("ERROR: Volumen normalizado es 0"); return false; }

   if(p_Direccion == GRID_LONG)
   {
      if(p_TP <= p_Trigger) { Print("ERROR LONG: TP debe ser > Trigger"); return false; }
      if(p_SL >= p_Piso)    { Print("ERROR LONG: SL debe ser < Piso");    return false; }
   }
   else
   {
      if(p_TP >= p_Trigger) { Print("ERROR SHORT: TP debe ser < Trigger"); return false; }
      if(p_SL <= p_Techo)   { Print("ERROR SHORT: SL debe ser > Techo");   return false; }
   }
   return true;
}

bool OrdenExisteEnNivel(double pr)
{
   double tol = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i); if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != Magic_Number) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - pr) <= tol) return true;
   }
   return false;
}

bool PosicionExisteEnNivel(double pr)
{
   double tol = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i); if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - pr) <= tol) return true;
   }
   return false;
}

int ContarPosicionesAbiertas()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i); if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == Magic_Number && PositionGetString(POSITION_SYMBOL) == _Symbol) c++;
   }
   return c;
}

int ContarOrdenesPendientes()
{
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i); if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) == Magic_Number && OrderGetString(ORDER_SYMBOL) == _Symbol) c++;
   }
   return c;
}

int EscanearOrdenesExistentes() { return ContarOrdenesPendientes() + ContarPosicionesAbiertas(); }

void ActivarGrid()
{
   trade.SetExpertMagicNumber(Magic_Number);
   trade.SetTypeFillingBySymbol(_Symbol);
   long stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minD = stops * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int col = 0, fl = 0, total = MathMin(ArraySize(GridLevels), p_MaxOrd);

   bool marketOk = false;
   if(p_Direccion == GRID_LONG)
   {
      if(!PosicionExisteEnNivel(GridLevels[0]))
      {
         marketOk = trade.Buy(p_Vol, _Symbol, 0, 0, 0, "GRID_BUY_0");
         if(!marketOk) PrintFormat("FALLO Buy[0] rc=%u msg=%s", trade.ResultRetcode(), trade.ResultComment());
         else Print("Buy[0] mercado OK");
      }
      else { marketOk = true; Print("Nivel 0 ya tiene posicion — omitiendo market Buy[0]"); }

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      for(int i = 1; i < total; i++)
      {
         double nv = GridLevels[i]; if(OrdenExisteEnNivel(nv)) continue; if(nv >= ask - minD) continue;
         if(trade.BuyLimit(p_Vol, nv, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "GRID_BUY_" + IntegerToString(i))) col++;
         else { fl++; PrintFormat("FALLO BuyLimit[%d] rc=%u", i, trade.ResultRetcode()); }
      }
   }
   else
   {
      if(!PosicionExisteEnNivel(GridLevels[0]))
      {
         marketOk = trade.Sell(p_Vol, _Symbol, 0, 0, 0, "GRID_SELL_0");
         if(!marketOk) PrintFormat("FALLO Sell[0] rc=%u msg=%s", trade.ResultRetcode(), trade.ResultComment());
         else Print("Sell[0] mercado OK");
      }
      else { marketOk = true; Print("Nivel 0 ya tiene posicion — omitiendo market Sell[0]"); }

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      for(int i = 1; i < total; i++)
      {
         double nv = GridLevels[i]; if(OrdenExisteEnNivel(nv)) continue; if(nv <= bid + minD) continue;
         if(trade.SellLimit(p_Vol, nv, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "GRID_SELL_" + IntegerToString(i))) col++;
         else { fl++; PrintFormat("FALLO SellLimit[%d] rc=%u", i, trade.ResultRetcode()); }
      }
   }
   RejillasActivas = col + (marketOk ? 1 : 0);
   PrintFormat("Grid activado: %d ordenes colocadas (%d fallaron), market=%s",
               col, fl, marketOk ? "OK" : "FALLO");
   DibujarLineasGrid();
}

void CerrarTodo()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i); if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!trade.PositionClose(t)) PrintFormat("FALLO cerrar %I64u rc=%u", t, trade.ResultRetcode());
   }
}

void CancelarPendientes()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i); if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != Magic_Number || OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(!trade.OrderDelete(t)) PrintFormat("FALLO cancel %I64u rc=%u", t, trade.ResultRetcode());
   }
}

bool CheckKillSwitch()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool hTP = (p_Direccion == GRID_LONG) ? (bid >= p_TP) : (bid <= p_TP);
   bool hSL = (p_Direccion == GRID_LONG) ? (bid <= p_SL) : (bid >= p_SL);
   if(hTP || hSL)
   {
      PrintFormat("KILL SWITCH: %s", hTP ? "TP" : "SL");
      CancelarPendientes(); CerrarTodo();
      estado = hTP ? PENDING : STOPPED; RejillasActivas = 0;
      DibujarLineasGrid(); DibujarPanel(); return true;
   }
   return false;
}

void CheckTrigger()
{
   if(estado != PENDING) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool triggered = (p_Direccion == GRID_LONG) ? (bid <= p_Trigger) : (bid >= p_Trigger);
   if(!triggered) return;
   ActivarGrid(); estado = ACTIVE;
}

void CheckRange()
{
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool   fuera = (bid > p_Techo || bid < p_Piso);
   if     (estado == ACTIVE && fuera)  { estado = PAUSED; Print("PAUSED"); }
   else if(estado == PAUSED && !fuera) { estado = ACTIVE;  Print("ACTIVE"); }
}

void LogOperacion(string tipo, double salida, double lotes, double ganancia)
{
   GananciaAcumulada += ganancia;
   string fn = "GridBot_Log_" + _Symbol + ".csv";
   int h = FileOpen(fn, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE) return;
   if(FileSize(h) == 0) FileWrite(h, "Timestamp","Par","Tipo","Salida","Lotes","Ganancia","Acumulada");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), _Symbol, tipo,
             DoubleToString(salida, _Digits), DoubleToString(lotes, 2),
             DoubleToString(ganancia, 2), DoubleToString(GananciaAcumulada, 2));
   FileClose(h);
}

void ColocarContraparte(int idx, ENUM_DEAL_TYPE dt, double pe)
{
   if(idx < 0 || idx >= ArraySize(GridLevels)) return;
   if(ContarPosicionesAbiertas() >= p_MaxOrd) { Print("FRENO Max_Orders en ColocarContraparte"); return; }
   trade.SetExpertMagicNumber(Magic_Number);

   bool ok = false;
   if(dt == DEAL_TYPE_BUY)
   {
      double obj = NormalizeDouble(pe * (1.0 + p_G), _Digits);
      if(OrdenExisteEnNivel(obj)) { Print("Contraparte ya existe en ", DoubleToString(obj, _Digits)); return; }
      ok = trade.SellLimit(p_Vol, obj, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "GRID_TP_" + IntegerToString(idx));
      if(!ok) PrintFormat("FALLO TP-sell idx=%d obj=%.5f rc=%u", idx, obj, trade.ResultRetcode());
   }
   else if(dt == DEAL_TYPE_SELL)
   {
      double obj = NormalizeDouble(pe / (1.0 + p_G), _Digits);
      if(OrdenExisteEnNivel(obj)) { Print("Contraparte ya existe en ", DoubleToString(obj, _Digits)); return; }
      ok = trade.BuyLimit(p_Vol, obj, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "GRID_TP_" + IntegerToString(idx));
      if(!ok) PrintFormat("FALLO TP-buy idx=%d obj=%.5f rc=%u", idx, obj, trade.ResultRetcode());
   }

   if(ok) { MarcarRejillaActiva(idx, true); RejillasActivas++; }
}

void ReponerEntrada(int idx)
{
   if(idx < 0 || idx >= ArraySize(GridLevels)) return;
   if(estado == PAUSED || estado == STOPPED) return;
   if(ContarPosicionesAbiertas() >= p_MaxOrd) return;
   double nv = GridLevels[idx]; if(OrdenExisteEnNivel(nv)) return;
   MarcarRejillaActiva(idx, false); if(RejillasActivas > 0) RejillasActivas--;
   trade.SetExpertMagicNumber(Magic_Number);
   bool ok = (p_Direccion == GRID_LONG)
      ? trade.BuyLimit(p_Vol,  nv, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "GRID_BUY_"  + IntegerToString(idx))
      : trade.SellLimit(p_Vol, nv, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "GRID_SELL_" + IntegerToString(idx));
   if(!ok) PrintFormat("FALLO repos idx=%d rc=%u", idx, trade.ResultRetcode());
}

void ProcesarDeals()
{
   if(!HistorySelect(BotStartTime, TimeCurrent() + 1)) return;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket <= UltimoDealProcesado) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != Magic_Number) continue;
      if(HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol) continue;

      ENUM_DEAL_ENTRY entry  = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      ENUM_DEAL_TYPE  dtype  = (ENUM_DEAL_TYPE) HistoryDealGetInteger(ticket, DEAL_TYPE);
      double precio  = HistoryDealGetDouble(ticket, DEAL_PRICE);
      double vol     = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double profit  = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                     + HistoryDealGetDouble(ticket, DEAL_SWAP)
                     + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
      int idx = IndiceDesdeComment(comment);

      if(entry == DEAL_ENTRY_IN)         ColocarContraparte(idx, dtype, precio);
      else if(entry == DEAL_ENTRY_OUT)   { LogOperacion("CLOSE_" + IntegerToString(idx), precio, vol, profit); ReponerEntrada(idx); }
      else if(entry == DEAL_ENTRY_INOUT) { LogOperacion("INOUT_" + IntegerToString(idx), precio, vol, profit); ColocarContraparte(idx, dtype, precio); }

      UltimoDealProcesado = ticket;
   }
}

void InicializarCursorDeals()
{
   if(!HistorySelect(BotStartTime, TimeCurrent() + 1)) return;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != Magic_Number) continue;
      if(HistoryDealGetString(t,  DEAL_SYMBOL) != _Symbol) continue;
      if(t > UltimoDealProcesado) UltimoDealProcesado = t;
   }
   PrintFormat("Cursor deals inicializado: ultimo ticket = %I64u", UltimoDealProcesado);
}

//+------------------------------------------------------------------+
//| OnChartEvent                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(StringFind(sparam, PFX + "E_CFG_") != 0) return;
      AplicarConfiguracionAuto(); return;
   }
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS); int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      if(cw != LastChartW || ch != LastChartH)
      {
         LastChartW = cw; LastChartH = ch;
         DibujarPanel(); if(ConfigVisible) DibujarConfigDialog(); if(AlertaVisible) DibujarAlerta();
      }
      return;
   }
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int mx = (int)lparam; int my = (int)dparam; bool md = ((int)StringToInteger(sparam) & 1) != 0;
      int pW = Sc(256); int pHDR = Sc(36); int cHDR_h = CFG_HDR_H;
      if(md && !DragPanel && !DragConfig && mx >= PanelPosX && mx <= PanelPosX+pW && my >= PanelPosY && my <= PanelPosY+pHDR)
         { DragPanel = true; DragOffX = mx - PanelPosX; DragOffY = my - PanelPosY; ChartSetInteger(0, CHART_MOUSE_SCROLL, false); }
      if(md && !DragConfig && !DragPanel && ConfigVisible && !ConfigMinimized &&
         mx >= ConfigPosX && mx <= ConfigPosX+CfgW && my >= ConfigPosY && my <= ConfigPosY+cHDR_h)
         { DragConfig = true; DragOffX = mx - ConfigPosX; DragOffY = my - ConfigPosY; ChartSetInteger(0, CHART_MOUSE_SCROLL, false); }
      if(md && DragPanel)
      {
         PanelPosX = MathMax(0, MathMin(mx - DragOffX, (int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)  - pW));
         PanelPosY = MathMax(0, MathMin(my - DragOffY, (int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS) - pHDR));
         DibujarPanel();
      }
      else if(md && DragConfig)
      {
         ConfigPosX = MathMax(0, MathMin(mx - DragOffX, (int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)  - CfgW));
         ConfigPosY = MathMax(0, MathMin(my - DragOffY, (int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS) - CfgH));
         DibujarConfigDialog();
      }
      if(!md && (DragPanel || DragConfig)) { DragPanel = false; DragConfig = false; ChartSetInteger(0, CHART_MOUSE_SCROLL, true); }
      return;
   }
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == PFX + "B_MINBTN")   { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); PanelMinimized = !PanelMinimized; DibujarPanel(); return; }
   if(sparam == PFX + "B_CFGBTN")   { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); ConfigVisible = !ConfigVisible; ConfigMinimized=false; if(!ConfigVisible) BorrarConfigDialog(); else DibujarConfigDialog(); return; }
   if(sparam == PFX + "B_CFG_X")    { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); ConfigVisible=false; ConfigMinimized=false; BorrarConfigDialog(); return; }
   if(sparam == PFX + "B_CFG_MIN")  { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); ConfigMinimized=!ConfigMinimized; BorrarConfigDialog(); DibujarConfigDialog(); return; }
   if(sparam == PFX + "B_CFG_CANCEL") { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); ConfigVisible=false; BorrarConfigDialog(); return; }
   if(sparam == PFX + "B_ALR_X" || sparam == PFX + "B_ALR_OK") { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); AlertaVisible=false; BorrarAlerta(); return; }

   for(int t = 0; t < 3; t++)
      if(sparam == PFX + "B_CFG_T" + IntegerToString(t))
         { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); ConfigTab=t; BorrarConfigDialog(); DibujarConfigDialog(); return; }

   if(sparam == PFX + "B_CFG_DIR_LONG")  { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); p_Direccion=GRID_LONG;  CalcularRejillas(); CalcularRiesgo(); BorrarConfigDialog(); DibujarConfigDialog(); DibujarLineasGrid(); DibujarPanel(); return; }
   if(sparam == PFX + "B_CFG_DIR_SHORT") { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); p_Direccion=GRID_SHORT; CalcularRejillas(); CalcularRiesgo(); BorrarConfigDialog(); DibujarConfigDialog(); DibujarLineasGrid(); DibujarPanel(); return; }
   if(sparam == PFX + "B_CFG_ML_OFF")    { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); p_Libre=false; ObjectSetString(0,PFX+"E_E_LIBRE",OBJPROP_TEXT,"false"); BorrarConfigDialog(); DibujarConfigDialog(); return; }
   if(sparam == PFX + "B_CFG_ML_ON")     { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); p_Libre=true;  ObjectSetString(0,PFX+"E_E_LIBRE",OBJPROP_TEXT,"true");  BorrarConfigDialog(); DibujarConfigDialog(); return; }
   if(sparam == PFX + "B_CFG_APPLY")     { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); ChartRedraw(0); AplicarConfiguracion(); return; }

   if(sparam == PFX + "B_START")
   {
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      if(!(RiesgoRealPct <= p_Risk || p_Libre))
         { MostrarAlerta("RIESGO EXCEDIDO", "Riesgo real supera el objetivo. Activa Modo Libre para forzar.", "Max seguro: " + IntegerToString(MaxOrdersSafe) + " rejillas.", ALERT_WARN); return; }

      int posAbiertas  = ContarPosicionesAbiertas();
      int ordPendientes = ContarOrdenesPendientes();

      if(posAbiertas > 0)
      {
         RejillasActivas = posAbiertas + ordPendientes;
         estado = ACTIVE;
         Print("START: Retomando con ", posAbiertas, " pos abiertas + ", ordPendientes, " pendientes — ACTIVE");
      }
      else if(ordPendientes > 0)
      {
         RejillasActivas = ordPendientes;
         estado = ACTIVE;
         Print("START: Retomando con ", ordPendientes, " ordenes pendientes — ACTIVE (esperando ejecucion)");
      }
      else
      {
         estado = PENDING;
         Print("START: Sin ordenes — PENDING, esperando trigger en ", DoubleToString(p_Trigger, _Digits));
      }
      DibujarLineasGrid(); DibujarPanel(); return;
   }
   if(sparam == PFX + "B_PAUSE") { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); if(estado==ACTIVE) estado=PAUSED; else if(estado==PAUSED) estado=ACTIVE; DibujarPanel(); return; }
   if(sparam == PFX + "B_STOP")  { ObjectSetInteger(0,sparam,OBJPROP_STATE,false); CancelarPendientes(); CerrarTodo(); estado=STOPPED; RejillasActivas=0; DibujarLineasGrid(); DibujarPanel(); return; }
   if(sparam == PFX + "B_CANCEL"){ ObjectSetInteger(0,sparam,OBJPROP_STATE,false); CancelarPendientes(); estado=STOPPED; RejillasActivas=0; DibujarLineasGrid(); DibujarPanel(); MostrarAlerta("CANCELADO","Orden pendiente cancelada.","",ALERT_INFO); return; }
}

//+------------------------------------------------------------------+
//| OnTimer                                                          |
//+------------------------------------------------------------------+
ulong LastEditTick  = 0;
bool  PendingRecalc = false;

void OnTimer()
{
   if(!ConfigVisible || ConfigMinimized) return;
   bool changed = false; string cur;
   if(ObjectFind(0, PFX + "E_CFG_E_TECHO") >= 0)
   {
      cur=GetEdit("CFG_E_TECHO");   if(cur!=PrevTecho)   { PrevTecho=cur;   double v=StringToDouble(cur); if(v>0) p_Techo=v;   changed=true; }
      cur=GetEdit("CFG_E_PISO");    if(cur!=PrevPiso)    { PrevPiso=cur;    double v=StringToDouble(cur); if(v>0) p_Piso=v;    changed=true; }
      cur=GetEdit("CFG_E_TRIGGER"); if(cur!=PrevTrigger) { PrevTrigger=cur; double v=StringToDouble(cur); if(v>0) p_Trigger=v; changed=true; }
      cur=GetEdit("CFG_E_G");       if(cur!=PrevG)       { PrevG=cur;       double v=StringToDouble(cur); if(v>0) p_G=v;       changed=true; }
      cur=GetEdit("CFG_E_VOL");     if(cur!=PrevVol)     { PrevVol=cur;     double v=StringToDouble(cur); if(v>0) p_Vol=v;     changed=true; }
   }
   if(ObjectFind(0, PFX + "E_CFG_E_CAP") >= 0)
   {
      cur=GetEdit("CFG_E_CAP");  if(cur!=PrevCap)  { PrevCap=cur;  double v=StringToDouble(cur);       if(v>0)           p_Capital=v; changed=true; }
      cur=GetEdit("CFG_E_RISK"); if(cur!=PrevRisk) { PrevRisk=cur; double v=StringToDouble(cur);       if(v>0&&v<=100)   p_Risk=v;    changed=true; }
      cur=GetEdit("CFG_E_MAXO"); if(cur!=PrevMaxo) { PrevMaxo=cur; int    v=(int)StringToInteger(cur); if(v>0)           p_MaxOrd=v;  changed=true; }
   }
   if(ObjectFind(0, PFX + "E_CFG_E_TP") >= 0)
   {
      cur=GetEdit("CFG_E_TP"); if(cur!=PrevTP) { PrevTP=cur; double v=StringToDouble(cur); if(v>0) p_TP=v; changed=true; }
      cur=GetEdit("CFG_E_SL"); if(cur!=PrevSL) { PrevSL=cur; double v=StringToDouble(cur); if(v>0) p_SL=v; changed=true; }
   }
   if(changed) { LastEditTick = GetTickCount(); PendingRecalc = true; }
   if(PendingRecalc && (GetTickCount() - LastEditTick) > 400)
   {
      PendingRecalc = false;
      CalcularRejillas(); CalcularRiesgo(); DibujarLineasGrid(); DibujarPanel(); RedibujarSoloVisualesBody();
   }
}

void RedibujarSoloVisualesBody()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, PFX) != 0) continue;
      if(StringFind(n, PFX + "E_") == 0) continue;
      if(StringFind(n, PFX + "R_CFG_RANGE_") == 0 || StringFind(n, PFX + "L_CFG_RC_") == 0    ||
         StringFind(n, PFX + "R_CFG_RC_") == 0    || StringFind(n, PFX + "R_CFG_RSK_") == 0   ||
         StringFind(n, PFX + "L_CFG_RSK_") == 0   || StringFind(n, PFX + "R_CFG_EXT_") == 0   ||
         StringFind(n, PFX + "L_CFG_EXT_") == 0   || StringFind(n, PFX + "B_CFG_EXT_") == 0   ||
         StringFind(n, PFX + "L_CFG_E_") == 0     || StringFind(n, PFX + "R_CFG_E_") == 0     ||
         StringFind(n, PFX + "B_CFG_DIR_") == 0   || StringFind(n, PFX + "B_CFG_ML_") == 0    ||
         StringFind(n, PFX + "L_CFG_DIR_") == 0   || StringFind(n, PFX + "L_CFG_ML_") == 0    ||
         StringFind(n, PFX + "R_CFG_DIR_") == 0   || StringFind(n, PFX + "R_CFG_ML_") == 0)
         ObjectDelete(0, n);
   }
   int by = ConfigPosY + CFG_HDR_H + CFG_TABS_H + CFG_BODY_PAD_TOP;
   int bodyW = CfgW - CFG_PAD * 2;
   int bodyMaxH = (ConfigPosY + CfgH - CFG_FOOT_H) - by - Sc(8);
   if(ConfigTab == 0)      DibujarBodyRango(ConfigPosX + CFG_PAD,  by, bodyW, bodyMaxH);
   else if(ConfigTab == 1) DibujarBodyRiesgo(ConfigPosX + CFG_PAD, by, bodyW, bodyMaxH);
   else                    DibujarBodySalidas(ConfigPosX + CFG_PAD, by, bodyW, bodyMaxH);
   ChartRedraw(0);
}

void ResetCacheEdits()
{
   PrevTecho   = DoubleToString(p_Techo,   _Digits); PrevPiso    = DoubleToString(p_Piso,    _Digits);
   PrevTrigger = DoubleToString(p_Trigger, _Digits); PrevG       = DoubleToString(p_G,       4);
   PrevVol     = DoubleToString(p_Vol,     2);        PrevCap     = DoubleToString(p_Capital, 2);
   PrevRisk    = DoubleToString(p_Risk,    2);        PrevMaxo    = IntegerToString(p_MaxOrd);
   PrevTP      = DoubleToString(p_TP,      _Digits); PrevSL      = DoubleToString(p_SL,      _Digits);
}

//+------------------------------------------------------------------+
//| PERSISTENCIA                                                     |
//+------------------------------------------------------------------+
string GVarPrefix() { return "GridBot_" + _Symbol + "_" + IntegerToString(Magic_Number) + "_"; }

void GuardarEstado()
{
   string p = GVarPrefix();
   GlobalVariableSet(p+"estado",        (double)estado);    GlobalVariableSet(p+"p_Direccion", (double)p_Direccion);
   GlobalVariableSet(p+"p_Techo",       p_Techo);           GlobalVariableSet(p+"p_Piso",      p_Piso);
   GlobalVariableSet(p+"p_Trigger",     p_Trigger);         GlobalVariableSet(p+"p_G",         p_G);
   GlobalVariableSet(p+"p_Capital",     p_Capital);         GlobalVariableSet(p+"p_Vol",       p_Vol);
   GlobalVariableSet(p+"p_Risk",        p_Risk);            GlobalVariableSet(p+"p_MaxOrd",    (double)p_MaxOrd);
   GlobalVariableSet(p+"p_Libre",       p_Libre?1.0:0.0);   GlobalVariableSet(p+"p_TP",        p_TP);
   GlobalVariableSet(p+"p_SL",          p_SL);              GlobalVariableSet(p+"GananciaAcum",GananciaAcumulada);
   GlobalVariableSet(p+"PanelMinimized",PanelMinimized?1.0:0.0);
   GlobalVariableSet(p+"PanelPosX",     (double)PanelPosX); GlobalVariableSet(p+"PanelPosY",(double)PanelPosY);
   GlobalVariableSet(p+"Saved",         1.0);
}

bool CargarEstado()
{
   string p = GVarPrefix();
   if(!GlobalVariableCheck(p+"Saved")) return false;
   estado          = (EstadoBot)(int)GlobalVariableGet(p+"estado");
   p_Direccion     = (DireccionGrid)(int)GlobalVariableGet(p+"p_Direccion");
   p_Techo         = GlobalVariableGet(p+"p_Techo");    p_Piso    = GlobalVariableGet(p+"p_Piso");
   p_Trigger       = GlobalVariableGet(p+"p_Trigger");  p_G       = GlobalVariableGet(p+"p_G");
   p_Capital       = GlobalVariableGet(p+"p_Capital");  p_Vol     = GlobalVariableGet(p+"p_Vol");
   p_Risk          = GlobalVariableGet(p+"p_Risk");     p_MaxOrd  = (int)GlobalVariableGet(p+"p_MaxOrd");
   p_Libre         = GlobalVariableGet(p+"p_Libre") > 0.5;
   p_TP            = GlobalVariableGet(p+"p_TP");       p_SL      = GlobalVariableGet(p+"p_SL");
   GananciaAcumulada = GlobalVariableGet(p+"GananciaAcum");
   PanelMinimized  = GlobalVariableGet(p+"PanelMinimized") > 0.5;
   PanelPosX       = (int)GlobalVariableGet(p+"PanelPosX");
   PanelPosY       = (int)GlobalVariableGet(p+"PanelPosY");
   return true;
}

void BorrarEstadoGuardado()
{
   string p = GVarPrefix();
   string keys[18] = {"estado","p_Direccion","p_Techo","p_Piso","p_Trigger","p_G","p_Capital",
                       "p_Vol","p_Risk","p_MaxOrd","p_Libre","p_TP","p_SL","GananciaAcum",
                       "PanelMinimized","PanelPosX","PanelPosY","Saved"};
   for(int i = 0; i < 18; i++) GlobalVariableDel(p + keys[i]);
}

//+------------------------------------------------------------------+
//| OnInit / OnTick / OnTradeTransaction / OnDeinit                  |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("==============================================");
   Print("GridBot v3.6.0 | UI redisenada | ", _Symbol);
   Print("==============================================");

   BotStartTime = TimeCurrent() - 86400;
   GUIScale     = 1.0;

   CargarParametros();
   bool restaurado = CargarEstado();
   if(!restaurado) estado = PRECHECK;
   if(!ValidarInputs()) return INIT_PARAMETERS_INCORRECT;
   CalcularRejillas(); CalcularRiesgo();
   trade.SetExpertMagicNumber(Magic_Number);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(30);
   InicializarCursorDeals();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   RefreshScale();
   LastChartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   LastChartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   EventSetMillisecondTimer(200);
   if(restaurado && (estado==ACTIVE || estado==PAUSED || estado==PENDING))
   {
      int posAbiertas   = ContarPosicionesAbiertas();
      int ordPendientes = ContarOrdenesPendientes();
      if(posAbiertas > 0 || ordPendientes > 0)
      {
         RejillasActivas = posAbiertas + ordPendientes;
         if(estado == PENDING && ordPendientes > 0) estado = ACTIVE;
         PrintFormat("Retomando: %d pos abiertas + %d pendientes → %s",
                     posAbiertas, ordPendientes,
                     estado==ACTIVE?"ACTIVE":estado==PAUSED?"PAUSED":"PENDING");
      }
      else if(estado == ACTIVE || estado == PAUSED)
      {
         estado = PRECHECK;
         Print("Sin ordenes en broker — volviendo a PRECHECK");
      }
   }
   DibujarLineasGrid(); DibujarPanel();
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(estado == PRECHECK || estado == STOPPED) return;

   if(estado == PENDING)
   {
      CheckTrigger();
      DibujarPanel();
      return;
   }

   if(CheckKillSwitch()) return;

   if(estado == ACTIVE)
   {
      CheckRange();
      ProcesarDeals();
   }
   else if(estado == PAUSED)
   {
      CheckRange();
   }

   DibujarPanel();
}

void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && estado == ACTIVE)
      ProcesarDeals();
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
   ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
   if(reason==REASON_CHARTCHANGE || reason==REASON_PARAMETERS || reason==REASON_RECOMPILE ||
      reason==REASON_TEMPLATE    || reason==REASON_ACCOUNT)
      GuardarEstado();
   else
      BorrarEstadoGuardado();
   BorrarTodo();
   PrintFormat("GridBot v3.6.0 fin. Estado=%d | Acumulado=%.2f USD", estado, GananciaAcumulada);
}
//+------------------------------------------------------------------+
