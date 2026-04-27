//+------------------------------------------------------------------+
//| GridBot.mq5                                                      |
//| Bot de Grid Geometrico Dinamico para Forex (MT5)                 |
//| v3.4 — UI Rediseñada (Modern Dark)                               |
//+------------------------------------------------------------------+
#property copyright "Oscar Alvarado"
#property version   "3.40"
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
enum DireccionGrid { GRID_LONG, GRID_SHORT };

input group "──── DIRECCION ────"
input DireccionGrid Direccion_Inp  = GRID_LONG;  // LONG: compra abajo / SHORT: vende arriba

input group "──── RANGO ────"
input double Techo_Inp   = 1.1800;
input double Piso_Inp    = 1.1600;
input double Trigger_Inp = 1.1720;
input double GPct_Inp    = 0.0025;

input group "──── CAPITAL Y RIESGO ────"
input double Capital_Inp   = 3000;
input double Volumen_Inp   = 0.01;
input double RiskPct_Inp   = 1.0;
input int    MaxOrders_Inp = 10;
input bool   ModoLibre_Inp = false;

input group "──── SALIDAS ────"
input double TP_Inp = 1.1850;
input double SL_Inp = 1.1550;

input group "──── PANEL ────"
input int PanelX      = 20;
input int PanelY      = 50;
input int MagicNumber = 20250424;

//+------------------------------------------------------------------+
//| PARAMETROS EN TIEMPO REAL                                        |
//+------------------------------------------------------------------+
double p_Techo, p_Piso, p_Trigger, p_G;
double p_Capital, p_Vol, p_Risk;
int    p_MaxOrd;
bool   p_Libre;
double p_TP, p_SL;
DireccionGrid p_Direccion;

//+------------------------------------------------------------------+
//| ESTADO Y GLOBALES                                                |
//+------------------------------------------------------------------+
enum EstadoBot { PENDING, ACTIVE, PAUSED, STOPPED, PRECHECK };
EstadoBot estado = PRECHECK;

enum AlertType { ALERT_INFO, ALERT_WARN, ALERT_ERROR, ALERT_SUCCESS };
bool      AlertaVisible = false;
string    AlertaTitle   = "";
string    AlertaMsg     = "";
string    AlertaSubMsg  = "";
AlertType AlertaTipo    = ALERT_INFO;

double GridLevels[];
double GananciaAcumulada   = 0.0;
ulong  UltimoDealProcesado = 0;
int    RejillasActivas     = 0;
int    MaxOrdersSafe       = 0;
double RiesgoRealUSD       = 0.0;
double RiesgoRealPct       = 0.0;
double GananciaPorRejilla  = 0.0;
string PFX = "GB34_";

// Panel
int  PanelX_cur, PanelY_cur, PanelW = 300, PanelH = 320;
bool Dragging = false;
int  DragOffX = 0, DragOffY = 0;

// Config dialog
bool ConfigVisible = false;
int  ConfigTab     = 0;   // 0=Rango, 1=Riesgo, 2=Salidas
int  CfgX, CfgY;
const int CfgW = 700;
const int CfgH = 960;

//+------------------------------------------------------------------+
//| PALETA DE COLORES — MODERN DARK                                  |
//+------------------------------------------------------------------+
#define CLR_BG          C'14,17,25'
#define CLR_BG_DEEP     C'8,10,16'
#define CLR_PANEL       C'22,26,36'
#define CLR_PANEL_HOV   C'28,33,46'
#define CLR_BORDER      C'37,43,59'
#define CLR_BORDER_LT   C'50,58,79'
#define CLR_TAB_ACTIVE  C'30,37,54'
#define CLR_TEXT        C'232,235,242'
#define CLR_TEXT_DIM    C'139,146,165'
#define CLR_TEXT_FAINT  C'91,97,117'
#define CLR_ACCENT      C'91,127,255'
#define CLR_ACCENT_DIM  C'58,86,199'
#define CLR_GREEN       C'34,197,94'
#define CLR_GREEN_DIM   C'21,128,61'
#define CLR_RED         C'239,68,68'
#define CLR_RED_DIM     C'153,27,27'
#define CLR_AMBER       C'245,158,11'
#define CLR_AMBER_DIM   C'180,83,9'

// Alias de compatibilidad
#define CLR_MINT        CLR_GREEN
#define CLR_MINT_ACT    C'34,220,110'
#define CLR_MINT_DIM    C'21,90,40'
#define CLR_TP          CLR_GREEN
#define CLR_SL          CLR_RED
#define CLR_RANGO       CLR_AMBER
#define CLR_TRIGGER     CLR_ACCENT
#define CLR_WARN        CLR_AMBER
#define CLR_HEADER      CLR_BG_DEEP
#define CLR_SEP         CLR_BORDER
#define CLR_WHITE       CLR_TEXT
#define CLR_EDIT_BG     CLR_BG_DEEP
#define CLR_EDIT_BORD   CLR_BORDER
#define CLR_BTN_GREEN   C'21,128,61'
#define CLR_BTN_RED     C'153,27,27'
#define CLR_BTN_BLUE    CLR_ACCENT
#define CLR_BTN_GRAY    CLR_PANEL_HOV
#define CLR_BTN_APPLY   CLR_ACCENT

//+------------------------------------------------------------------+
//| HELPERS                                                          |
//+------------------------------------------------------------------+
int IndiceDesdeComment(const string c)
{
   int p = StringFind(c, "_", StringFind(c, "_") + 1);
   if(p < 0) return -1;
   return (int)StringToInteger(StringSubstr(c, p + 1));
}

void CargarParametros()
{
   p_Direccion = Direccion_Inp;
   p_Techo     = Techo_Inp;    p_Piso    = Piso_Inp;
   p_Trigger   = Trigger_Inp;  p_G       = GPct_Inp;
   p_Capital   = Capital_Inp;  p_Vol     = Volumen_Inp;
   p_Risk      = RiskPct_Inp;  p_MaxOrd  = MaxOrders_Inp;
   p_Libre     = ModoLibre_Inp;
   p_TP        = TP_Inp;       p_SL      = SL_Inp;
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
      if(StringFind(n, PFX + "L_") == 0 || StringFind(n, PFX + "T_") == 0)
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
   ObjectSetString(0, n, OBJPROP_TEXT, "◄ " + txt + " " + DoubleToString(pr, _Digits));
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, anc);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
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
   for(int i = 0; i < total; i++)
   {
      bool ok   = (i < MaxOrdersSafe);
      color clrR = (estado == ACTIVE && ok) ? CLR_MINT_ACT : ok ? CLR_MINT : CLR_MINT_DIM;
      string lbl = (ok ? "Buy" : "Buy*") + " [" + IntegerToString(i) + "]";
      CrearLinea("GRID_" + IntegerToString(i), GridLevels[i], clrR, STYLE_DOT, 1);
      CrearLabelGraf("GRID_" + IntegerToString(i), GridLevels[i], clrR, lbl, offs[i % 3],
                     (i == total - 1) ? ANCHOR_RIGHT_UPPER : ANCHOR_RIGHT_LOWER);
   }
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
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| HELPERS DE PANEL — primitivos UI                                 |
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

void PB(string id, int x, int y, int w, int h, string txt, color bg, color clr, int sz = 9, string font = "Consolas")
{
   string n = PFX + "B_" + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,     h);
   ObjectSetString(0,  n, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,   bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,  sz);
   ObjectSetString(0,  n, OBJPROP_FONT,      font);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_STATE,     false);
}

void PE(string id, int x, int y, int w, int h, string val)
{
   string n = PFX + "E_" + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,        h);
   ObjectSetString(0,  n, OBJPROP_TEXT,         val);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      CLR_BG_DEEP);
   ObjectSetInteger(0, n, OBJPROP_COLOR,        CLR_TEXT);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, CLR_BORDER);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,     10);
   ObjectSetString(0,  n, OBJPROP_FONT,         "Consolas");
   ObjectSetInteger(0, n, OBJPROP_ALIGN,        ALIGN_LEFT);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, n, OBJPROP_BACK,         false);
}

void PHR(string id, int x, int y, int w, color clr)  { PR(id, x, y, w, 1, clr, clr, 0); }
void PVR(string id, int x, int y, int h, color clr)  { PR(id, x, y, 1, h, clr, clr, 0); }

string GetEdit(string id) { return ObjectGetString(0, PFX + "E_" + id, OBJPROP_TEXT); }
void   DelObj(string full) { ObjectDelete(0, PFX + full); }

//+------------------------------------------------------------------+
//| SISTEMA DE ALERTAS POPUP                                         |
//+------------------------------------------------------------------+
void MostrarAlerta(string title, string msg, string subMsg, AlertType tipo)
{
   AlertaTitle  = title;
   AlertaMsg    = msg;
   AlertaSubMsg = subMsg;
   AlertaTipo   = tipo;
   AlertaVisible = true;
   DibujarAlerta();
}

void BorrarAlerta()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, PFX + "R_ALR") == 0 ||
         StringFind(n, PFX + "L_ALR") == 0 ||
         StringFind(n, PFX + "B_ALR") == 0)
         ObjectDelete(0, n);
   }
   ChartRedraw(0);
}

void DibujarTextoLargo(string id, int x, int y, int wPx, string texto, color clr, int sz, int lineGap = 20)
{
   int charW    = (sz <= 9) ? 12 : (sz <= 10) ? 14 : (sz <= 11) ? 15 : 16;
   int maxChars = wPx / charW;
   if(maxChars < 10) maxChars = 10;

   string lineas[20];
   int    totalLineas = 0;
   string linea       = "";
   string textoRest   = texto;

   while(StringLen(textoRest) > 0 && totalLineas < 20)
   {
      int    spacePos = StringFind(textoRest, " ");
      string palabra;
      if(spacePos < 0)  { palabra = textoRest; textoRest = ""; }
      else              { palabra = StringSubstr(textoRest, 0, spacePos); textoRest = StringSubstr(textoRest, spacePos + 1); }
      if(palabra == "") continue;

      string nueva = (linea == "") ? palabra : linea + " " + palabra;
      if(StringLen(nueva) <= maxChars)
         linea = nueva;
      else
      {
         if(linea != "") { lineas[totalLineas++] = linea; linea = palabra; }
         else            { lineas[totalLineas++] = palabra; linea = ""; }
      }
   }
   if(linea != "" && totalLineas < 20) lineas[totalLineas++] = linea;

   for(int i = 0; i < totalLineas; i++)
      PL(id + "_" + IntegerToString(i), x, y + i * lineGap, lineas[i], clr, sz);
}

void DibujarAlerta()
{
   if(!AlertaVisible) { BorrarAlerta(); return; }

   int W = 700, H = 340;
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int x  = (cw - W) / 2;
   int y  = (ch - H) / 2;
   if(x < 0) x = 10;
   if(y < 0) y = 10;

   color  iconC;
   string iconText;
   switch(AlertaTipo)
   {
      case ALERT_ERROR:   iconC = CLR_RED;    iconText = "!";  break;
      case ALERT_WARN:    iconC = CLR_AMBER;  iconText = "!";  break;
      case ALERT_SUCCESS: iconC = CLR_GREEN;  iconText = "OK"; break;
      default:            iconC = CLR_ACCENT; iconText = "i";  break;
   }

   int PAD = 24;
   PR("ALR_BG",     x, y, W, H,  CLR_PANEL,    CLR_ACCENT,  2);
   PR("ALR_HDR",    x, y, W, 64, CLR_BG_DEEP,  CLR_BG_DEEP, 0);
   PHR("ALR_HDR_LN", x, y + 63, W, CLR_ACCENT);

   PB("ALR_ICN", x + PAD, y + 18, 28, 28, iconText, iconC, CLR_TEXT, 14);
   ObjectSetInteger(0, PFX + "B_ALR_ICN", OBJPROP_BORDER_COLOR, iconC);

   int titX = x + PAD + 40;
   int titW = W - PAD * 2 - 40 - 40;
   PB("ALR_TIT", titX, y + 18, titW, 28, AlertaTitle, CLR_BG_DEEP, CLR_TEXT, 12);
   ObjectSetInteger(0, PFX + "B_ALR_TIT", OBJPROP_BORDER_COLOR, CLR_BG_DEEP);

   PB("ALR_X", x + W - PAD - 30, y + 18, 30, 28, "X", CLR_RED_DIM, CLR_TEXT, 12);

   int by    = y + 88;
   int textW = W - PAD * 2;
   DibujarTextoLargo("ALR_MSG", x + PAD, by, textW - 12, AlertaMsg, CLR_TEXT, 11, 22);

   if(StringLen(AlertaSubMsg) > 0)
   {
      int subY = by + 60;
      PR("ALR_SBOX", x + PAD, subY, textW, 64, CLR_BG_DEEP, CLR_BORDER, 1);
      PR("ALR_SIND", x + PAD, subY, 4, 64, iconC, iconC, 0);
      DibujarTextoLargo("ALR_SMSG", x + PAD + 16, subY + 12, textW - 44, AlertaSubMsg, CLR_TEXT_DIM, 10, 18);
   }

   int btnY = y + H - 58;
   PHR("ALR_BTN_LN", x, btnY - 1, W, CLR_BORDER);
   PB("ALR_OK", x + W / 2 - 110, btnY + 10, 220, 40, "ENTENDIDO", CLR_ACCENT, CLR_TEXT, 13);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| PANEL DE ESTADO (movible)                                        |
//+------------------------------------------------------------------+
void DibujarPanel()
{
   int x = PanelX_cur, y = PanelY_cur, W = PanelW;
   int PAD = 18, COL = 140;

   if(ObjectFind(0, PFX + "R_CFG_FIX_BG") >= 0) ObjectDelete(0, PFX + "R_CFG_FIX_BG");

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

   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string ganS = (GananciaAcumulada >= 0 ? "+" : "") + DoubleToString(GananciaAcumulada, 2) + " USD";
   color  ganC = GananciaAcumulada >= 0 ? CLR_GREEN : CLR_RED;
   color  rskC = (RiesgoRealPct > p_Risk) ? CLR_RED : CLR_GREEN;

   PR("BG",     x, y, W, 420, CLR_PANEL,   CLR_BORDER_LT, 1);
   PR("HDR",    x, y, W, 52,  CLR_BG_DEEP, CLR_BG_DEEP,   0);
   PHR("HDR_LN", x, y + 51, W, CLR_BORDER);

   PB("LOGO", x + PAD, y + 13, 28, 28, "G", CLR_ACCENT, CLR_TEXT, 12);
   ObjectSetInteger(0, PFX + "B_LOGO", OBJPROP_BORDER_COLOR, CLR_ACCENT);
   PL("HTIT", x + PAD + 40, y + 15, "GRIDBOT v3.4", CLR_TEXT, 12);

   if(ObjectFind(0, PFX + "B_DIRBADGE") >= 0) ObjectDelete(0, PFX + "B_DIRBADGE");

   PB("CFGBTN", 168, 12, 152, 42, "CONFIG", CLR_ACCENT, CLR_TEXT, 13);
   ObjectSetInteger(0, PFX + "B_CFGBTN", OBJPROP_CORNER,       CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, PFX + "B_CFGBTN", OBJPROP_XDISTANCE,    168);
   ObjectSetInteger(0, PFX + "B_CFGBTN", OBJPROP_YDISTANCE,    12);
   ObjectSetInteger(0, PFX + "B_CFGBTN", OBJPROP_BORDER_COLOR, CLR_ACCENT);

   color  dirC = (p_Direccion == GRID_LONG) ? CLR_GREEN : CLR_RED;
   string dirT = (p_Direccion == GRID_LONG) ? "LONG" : "SHORT";
   PB("DIRBADGE", 292, 12, 108, 42, dirT, CLR_BG_DEEP, dirC, 13);
   ObjectSetInteger(0, PFX + "B_DIRBADGE", OBJPROP_CORNER,       CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, PFX + "B_DIRBADGE", OBJPROP_XDISTANCE,    292);
   ObjectSetInteger(0, PFX + "B_DIRBADGE", OBJPROP_YDISTANCE,    12);
   ObjectSetInteger(0, PFX + "B_DIRBADGE", OBJPROP_BORDER_COLOR, dirC);

   int cy = y + 68;
   PL("ELAB", x + PAD, cy + 3, "ESTADO",  CLR_TEXT_FAINT, 8);
   PL("EVAL", x + COL, cy,     eStr,      eClr,           11);
   cy += 32;
   PHR("S1", x + PAD, cy, W - PAD * 2, CLR_BORDER); cy += 14;

   PL("BLAB", x + PAD, cy + 1, "PRECIO",  CLR_TEXT_FAINT, 8);
   PL("BVAL", x + COL, cy,     DoubleToString(bid, _Digits), CLR_TEXT, 10);
   cy += 26;

   PL("TLAB", x + PAD, cy + 1, "TRIGGER", CLR_TEXT_FAINT, 8);
   PL("TVAL", x + COL, cy,     DoubleToString(p_Trigger, _Digits), CLR_ACCENT, 10);
   cy += 32;
   PHR("S2", x + PAD, cy, W - PAD * 2, CLR_BORDER); cy += 14;

   PL("RHTL", x + PAD, cy, "RIESGO", CLR_TEXT_FAINT, 8); cy += 22;
   PL("RCLA", x + PAD, cy + 1, "Config", CLR_TEXT_DIM, 8);
   PL("RCVA", x + COL, cy, DoubleToString(p_Risk, 1) + "% / $" + DoubleToString(p_Capital * p_Risk / 100, 0), CLR_GREEN, 9);
   cy += 22;
   PL("RRLA", x + PAD, cy + 1, "Real", CLR_TEXT_DIM, 8);
   PL("RRVA", x + COL, cy, DoubleToString(RiesgoRealPct, 1) + "% / $" + DoubleToString(RiesgoRealUSD, 1), rskC, 9);
   cy += 22;
   PL("GRLA", x + PAD, cy + 1, "Rejillas", CLR_TEXT_DIM, 8);
   PL("GRVA", x + COL, cy, IntegerToString(RejillasActivas) + "/" + IntegerToString(p_MaxOrd) + " ok:" + IntegerToString(MaxOrdersSafe), CLR_TEXT, 9);
   cy += 22;
   PL("GPLA", x + PAD, cy + 1, "Gan/rej", CLR_TEXT_DIM, 8);
   PL("GPVA", x + COL, cy, "$" + DoubleToString(GananciaPorRejilla, 2), CLR_GREEN, 9);
   cy += 32;
   PHR("S3", x + PAD, cy, W - PAD * 2, CLR_BORDER); cy += 14;

   PL("GNLA", x + PAD, cy + 3, "GANANCIA", CLR_TEXT_FAINT, 8);
   PL("GNVA", x + COL, cy,     ganS,       ganC,           11);
   cy += 34;
   PHR("S4", x + PAD, cy, W - PAD * 2, CLR_BORDER); cy += 18;

   if(estado == PRECHECK || estado == STOPPED)
   {
      PB("START", x + PAD, cy, W - PAD * 2, 36, "INICIAR BOT", CLR_GREEN_DIM, CLR_TEXT, 11);
      DelObj("B_PAUSE"); DelObj("B_STOP"); DelObj("B_CANCEL");
   }
   else if(estado == PENDING)
   {
      PB("CANCEL", x + PAD, cy, W - PAD * 2, 36, "CANCELAR ORDEN", CLR_RED_DIM, CLR_TEXT, 11);
      DelObj("B_START"); DelObj("B_PAUSE"); DelObj("B_STOP");
   }
   else if(estado == ACTIVE || estado == PAUSED)
   {
      int    bw   = (W - PAD * 2 - 8) / 2;
      string ptxt = (estado == ACTIVE) ? "PAUSAR" : "REANUDAR";
      PB("PAUSE", x + PAD,          cy, bw, 36, ptxt,   CLR_BTN_BLUE, CLR_TEXT, 10);
      PB("STOP",  x + PAD + bw + 8, cy, bw, 36, "PARAR", CLR_RED_DIM,  CLR_TEXT, 10);
      DelObj("B_START"); DelObj("B_CANCEL");
   }

   PanelH = (cy + 36 + 18) - y;
   ObjectSetInteger(0, PFX + "R_BG", OBJPROP_YSIZE, PanelH);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| VENTANA DE CONFIGURACION                                         |
//+------------------------------------------------------------------+
void BorrarConfigDialog()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, PFX + "R_CFG_") == 0 ||
         StringFind(n, PFX + "L_CFG_") == 0 ||
         StringFind(n, PFX + "B_CFG_") == 0 ||
         StringFind(n, PFX + "E_CFG_") == 0)
         ObjectDelete(0, n);
   }
   ChartRedraw(0);
}

void CfgField(string id, int x, int y, int w, string label, string val, string suffix = "")
{
   PL("CFG_" + id + "_L", x, y, label, CLR_TEXT_DIM, 9);
   if(suffix != "")
   {
      int sufW = 52;
      PE("CFG_" + id,         x,             y + 28, w - sufW - 2, 36, val);
      PR("CFG_" + id + "_SB", x + w - sufW,  y + 28, sufW, 36, CLR_BG_DEEP, CLR_BORDER, 1);
      PL("CFG_" + id + "_S",  x + w - sufW + 12, y + 38, suffix, CLR_TEXT_FAINT, 9);
   }
   else
      PE("CFG_" + id, x, y + 28, w, 36, val);
}

void DibujarConfigDialog()
{
   if(!ConfigVisible) { BorrarConfigDialog(); return; }

   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   CfgX = (cw - CfgW) / 2; if(CfgX < 0) CfgX = 10;
   CfgY = (ch - CfgH) / 2; if(CfgY < 0) CfgY = 10;

   int x = CfgX, y = CfgY, W = CfgW, H = CfgH;
   int PAD = 32, FOOTER_H = 88;

   PR("CFG_BG",     x, y, W, H,   CLR_PANEL,   CLR_BORDER_LT, 1);
   PR("CFG_HDR",    x, y, W, 110, CLR_BG_DEEP, CLR_BG_DEEP,   0);
   PHR("CFG_HDR_LN", x, y + 109, W, CLR_BORDER);

   PB("CFG_LOGO", x + PAD, y + 31, 48, 48, "G", CLR_ACCENT, CLR_TEXT, 22);
   ObjectSetInteger(0, PFX + "B_CFG_LOGO", OBJPROP_BORDER_COLOR, CLR_ACCENT);

   PL("CFG_TIT", x + PAD + 82, y + 30, "GRIDBOT CONFIG", CLR_TEXT,     15, "Arial");
   PL("CFG_SUB", x + PAD + 82, y + 68, "v3.4 " + _Symbol, CLR_TEXT_DIM, 11);

   string stBadge;
   color  stBadgeC;
   switch(estado)
   {
      case ACTIVE:  stBadge = "ACTIVE";  stBadgeC = CLR_GREEN;  break;
      case PAUSED:  stBadge = "PAUSED";  stBadgeC = CLR_AMBER;  break;
      case PENDING: stBadge = "PENDING"; stBadgeC = CLR_ACCENT; break;
      case STOPPED: stBadge = "STOPPED"; stBadgeC = CLR_RED;    break;
      default:      stBadge = "READY";   stBadgeC = CLR_AMBER;  break;
   }
   PB("CFG_ST_T", x + W - 220, y + 38, 140, 44, stBadge, CLR_BG_DEEP, stBadgeC, 13);
   ObjectSetInteger(0, PFX + "B_CFG_ST_T", OBJPROP_BORDER_COLOR, stBadgeC);
   PR("CFG_ST_DOT", x + W - 210, y + 55, 10, 10, stBadgeC, stBadgeC, 0);
   PB("CFG_X", x + W - 66, y + 38, 40, 44, "X", CLR_RED_DIM, CLR_TEXT, 14);

   int tabsY = y + 110;
   PR("CFG_TBG",    x, tabsY, W, 54,  CLR_BG, CLR_BG, 0);
   PHR("CFG_TBG_LN", x, tabsY + 53, W, CLR_BORDER);

   string tabLabels[3] = {"RANGO", "RIESGO", "SALIDAS"};
   int tw = W / 3;
   for(int i = 0; i < 3; i++)
   {
      bool  act = (i == ConfigTab);
      color tbg = act ? CLR_TAB_ACTIVE : CLR_BG;
      color tcl = act ? CLR_TEXT       : CLR_TEXT_DIM;
      PB("CFG_T" + IntegerToString(i), x + i * tw, tabsY, tw, 52, tabLabels[i], tbg, tcl, 12);
      if(act) PR("CFG_T" + IntegerToString(i) + "_IND", x + i * tw + tw / 4, tabsY + 49, tw / 2, 4, CLR_ACCENT, CLR_ACCENT, 0);
      else    DelObj("R_CFG_T" + IntegerToString(i) + "_IND");
   }

   int by = tabsY + 54;
   if     (ConfigTab == 0) DibujarBodyRango(x + PAD, by + 40, W - PAD * 2);
   else if(ConfigTab == 1) DibujarBodyRiesgo(x + PAD, by + 40, W - PAD * 2);
   else                    DibujarBodySalidas(x + PAD, by + 40, W - PAD * 2);

   int fy = y + H - FOOTER_H;
   PHR("CFG_FT_LN", x, fy, W, CLR_BORDER);
   PR("CFG_FT",     x, fy + 1, W, FOOTER_H - 1, CLR_BG_DEEP, CLR_BG_DEEP, 0);

   int btnGap    = 20;
   int btnTotalW = W - PAD * 2;
   int cancelW   = (btnTotalW - btnGap) / 2;
   int applyW    = btnTotalW - cancelW - btnGap;
   PB("CFG_CANCEL", x + PAD,                      fy + 24, cancelW, 44, "CANCELAR", CLR_PANEL_HOV, CLR_TEXT, 12);
   PB("CFG_APPLY",  x + PAD + cancelW + btnGap,   fy + 24, applyW,  44, "APLICAR",  CLR_ACCENT,    CLR_TEXT, 13);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| BODY RANGO                                                       |
//+------------------------------------------------------------------+
void DibujarBodyRango(int x, int y, int w)
{
   int colW    = (w - 16) / 2;
   int rowGap  = 110;

   PL("CFG_DIR_L", x, y, "DIRECCION", CLR_TEXT_DIM, 9);
   int  dirBtnW = (w - 12) / 2;
   bool isLong  = (p_Direccion == GRID_LONG);
   PB("CFG_DIR_LONG",  x,              y + 22, dirBtnW, 36, "LONG",  isLong ? CLR_GREEN_DIM  : CLR_PANEL_HOV, CLR_TEXT, 11);
   PB("CFG_DIR_SHORT", x + dirBtnW + 12, y + 22, dirBtnW, 36, "SHORT", isLong ? CLR_PANEL_HOV : CLR_RED_DIM,   CLR_TEXT, 11);
   y += 80;

   CfgField("E_TECHO",   x,          y,           colW, "TECHO",              DoubleToString(p_Techo,   _Digits));
   CfgField("E_PISO",    x + colW + 16, y,         colW, "PISO",               DoubleToString(p_Piso,    _Digits));
   CfgField("E_TRIGGER", x,          y + rowGap,   w,    "TRIGGER DE ENTRADA", DoubleToString(p_Trigger, _Digits));
   CfgField("E_G",       x,          y + rowGap*2, colW, "G % GEOMETRIA",      DoubleToString(p_G, 4), "%");
   CfgField("E_VOL",     x + colW + 16, y + rowGap*2, colW, "VOLUMEN",         DoubleToString(p_Vol, 2), "LOT");

   int cy = y + rowGap * 2 + 100;
   PR("CFG_RANGE_CARD", x, cy, w, 200, CLR_BG_DEEP, CLR_BORDER, 1);
   PL("CFG_RC_HD",  x + 24, cy + 22, "RANGO ACTIVO",                                                    CLR_TEXT_FAINT, 9);
   PL("CFG_RC_NUM", x + 24, cy + 44, IntegerToString(ArraySize(GridLevels)) + " niveles",                CLR_TEXT, 18);
   PL("CFG_RC_SUB", x + 24, cy + 86, DoubleToString(MathAbs(p_Techo - p_Piso) * 10000, 0) + " pips " +
                                      DoubleToString(p_Piso, _Digits) + " -> " + DoubleToString(p_Techo, _Digits), CLR_TEXT_DIM, 9);

   int axisX = x + 24, axisY = cy + 158, axisW = w - 48;
   PHR("CFG_RC_AXIS",    axisX, axisY, axisW, CLR_BORDER);
   PVR("CFG_RC_PISO",    axisX,           cy + 144, 30, CLR_AMBER);
   PL("CFG_RC_PISO_L",   axisX + 6,       cy + 126, "PISO",  CLR_AMBER,  9);
   PVR("CFG_RC_TECHO",   axisX + axisW-1, cy + 144, 30, CLR_AMBER);
   PL("CFG_RC_TECHO_L",  axisX + axisW - 44, cy + 126, "TECHO", CLR_AMBER, 9);

   double rangePct = (p_Trigger - p_Piso) / MathMax(p_Techo - p_Piso, 0.00001);
   int    trgX     = axisX + (int)(axisW * rangePct);
   PVR("CFG_RC_TRG",   trgX,    cy + 138, 40, CLR_ACCENT);
   PL("CFG_RC_TRG_L",  trgX + 5, cy + 126, "TRG", CLR_ACCENT, 9);

   int totalLvl = ArraySize(GridLevels);
   for(int i = 0; i < totalLvl && i < 10; i++)
   {
      double lvlPct = (GridLevels[i] - p_Piso) / MathMax(p_Techo - p_Piso, 0.00001);
      int    lvlX   = axisX + (int)(axisW * lvlPct);
      PR("CFG_RC_L" + IntegerToString(i), lvlX - 2, axisY - 2, 5, 5, CLR_GREEN, CLR_GREEN, 0);
   }
}

//+------------------------------------------------------------------+
//| BODY RIESGO                                                      |
//+------------------------------------------------------------------+
void DibujarBodyRiesgo(int x, int y, int w)
{
   int colW   = (w - 16) / 2;
   int rowGap = 110;

   CfgField("E_CAP",  x,            y,           colW, "CAPITAL",     DoubleToString(p_Capital, 2), "USD");
   CfgField("E_RISK", x + colW + 16, y,           colW, "RIESGO",      DoubleToString(p_Risk, 2),   "%");
   CfgField("E_MAXO", x,            y + rowGap,  colW, "MAX ORDENES", IntegerToString(p_MaxOrd));

   PL("CFG_ML_L", x + colW + 16, y + rowGap, "MODO LIBRE", CLR_TEXT_DIM, 9);
   bool freeOff = !p_Libre;
   PB("CFG_ML_OFF", x + colW + 16,          y + rowGap + 22, colW / 2, 30, "OFF",
      freeOff  ? CLR_PANEL_HOV : CLR_BG_DEEP,
      freeOff  ? CLR_TEXT       : CLR_TEXT_FAINT, 10);
   PB("CFG_ML_ON",  x + colW + 16 + colW/2, y + rowGap + 22, colW / 2, 30, "ON",
      !freeOff ? CLR_PANEL_HOV : CLR_BG_DEEP,
      !freeOff ? CLR_TEXT       : CLR_TEXT_FAINT, 10);
   PE("E_LIBRE", x + colW + 16, y + rowGap + 22, 1, 1, p_Libre ? "true" : "false");
   ObjectSetInteger(0, PFX + "E_E_LIBRE", OBJPROP_HIDDEN, true);

   int   cy       = y + rowGap * 2 + 24;
   bool  excedido = (RiesgoRealPct > p_Risk);
   color cardBorder = excedido ? CLR_RED : CLR_GREEN;
   PR("CFG_RSK_CARD", x, cy, w, 280, CLR_BG_DEEP, cardBorder, 1);

   PR("CFG_RSK_DOT", x + 24, cy + 28, 10, 10, excedido ? CLR_RED : CLR_GREEN, excedido ? CLR_RED : CLR_GREEN, 0);
   PL("CFG_RSK_HD",  x + 44, cy + 24, excedido ? "RIESGO EXCEDIDO" : "RIESGO OK", excedido ? CLR_RED : CLR_GREEN, 11);

   if(excedido)
   {
      double over = (RiesgoRealPct / MathMax(p_Risk, 0.01) - 1.0) * 100.0;
      PR("CFG_RSK_BG", x + w - 100, cy + 24, 80, 24, CLR_RED_DIM, CLR_RED_DIM, 0);
      PL("CFG_RSK_BT", x + w - 92,  cy + 28, "+" + DoubleToString(over, 0) + "%", CLR_RED, 10);
   }

   int statW  = (w - 48 - 40) / 3;
   int statsY = cy + 78;
   PL("CFG_RSK_S1L", x + 24,                  statsY,      "REAL %",    CLR_TEXT_FAINT, 9);
   PL("CFG_RSK_S1V", x + 24,                  statsY + 22, DoubleToString(RiesgoRealPct, 2), excedido ? CLR_RED : CLR_GREEN, 18);
   PL("CFG_RSK_S2L", x + 24 + statW + 20,     statsY,      "PERDIDA",   CLR_TEXT_FAINT, 9);
   PL("CFG_RSK_S2V", x + 24 + statW + 20,     statsY + 22, "$" + DoubleToString(RiesgoRealUSD, 2), excedido ? CLR_RED : CLR_GREEN, 18);
   PL("CFG_RSK_S3L", x + 24 + (statW+20)*2,   statsY,      "SEGURO",    CLR_TEXT_FAINT, 9);
   PL("CFG_RSK_S3V", x + 24 + (statW+20)*2,   statsY + 22, IntegerToString(MaxOrdersSafe) + " rej", CLR_AMBER, 18);

   int barY = cy + 170;
   PL("CFG_RSK_BL1", x + 24,         barY, "0%",                                    CLR_TEXT_FAINT, 9);
   PL("CFG_RSK_BL2", x + (w/2) - 50, barY, "OBJETIVO " + DoubleToString(p_Risk,1)+"%", CLR_AMBER, 9);
   PL("CFG_RSK_BL3", x + w - 50,     barY, "2x",                                    CLR_TEXT_FAINT, 9);
   PR("CFG_RSK_BAR_BG", x + 24, barY + 26, w - 48, 10, CLR_BORDER, CLR_BORDER, 0);
   double fillPct = MathMin(RiesgoRealPct / (p_Risk * 2.0), 1.0);
   int    fillW   = (int)((w - 48) * fillPct);
   PR("CFG_RSK_BAR_FL", x + 24, barY + 26, fillW, 10, excedido ? CLR_RED : CLR_GREEN, excedido ? CLR_RED : CLR_GREEN, 0);
   PVR("CFG_RSK_BAR_MK", x + 24 + (w - 48) / 2, barY + 22, 18, CLR_AMBER);
}

//+------------------------------------------------------------------+
//| BODY SALIDAS                                                     |
//+------------------------------------------------------------------+
void DibujarBodySalidas(int x, int y, int w)
{
   int colW = (w - 16) / 2;
   CfgField("E_TP", x,            y, colW, "TAKE PROFIT", DoubleToString(p_TP, _Digits));
   CfgField("E_SL", x + colW + 16, y, colW, "STOP LOSS",   DoubleToString(p_SL, _Digits));

   int cy = y + 120, cardH = 480;
   PR("CFG_EXT_CARD", x, cy, w, cardH, CLR_BG_DEEP, CLR_BORDER, 1);
   PL("CFG_EXT_HD", x + 24, cy + 22, "DISTANCIAS DESDE TRIGGER", CLR_TEXT_FAINT, 10);

   double dist_tp = MathAbs(p_TP      - p_Trigger);
   double dist_sl = MathAbs(p_Trigger - p_SL);
   double maxD    = MathMax(dist_tp, dist_sl);
   int    barX    = x + 72, barW = w - 96;

   int rowY    = cy + 68;
   int tpBarW  = (int)(barW * (dist_tp / MathMax(maxD, 0.0001)));
   PL("CFG_EXT_TPL",  x + 24,      rowY + 22, "TP", CLR_GREEN, 11);
   PR("CFG_EXT_TPBG", barX,        rowY, barW, 60, CLR_BG, CLR_BORDER, 1);
   PR("CFG_EXT_TPLN", barX,        rowY, 5,    60, CLR_GREEN, CLR_GREEN, 0);
   PR("CFG_EXT_TPFL", barX + 5,    rowY + 1, tpBarW - 5, 58, C'18,55,38', C'18,55,38', 0);
   PL("CFG_EXT_TPV",  barX + 18,   rowY + 22, "+" + DoubleToString(dist_tp * 10000, 1) + " pips", CLR_GREEN, 13);
   PL("CFG_EXT_TPP",  barX + barW - 78, rowY + 22, "+" + DoubleToString(dist_tp / p_Trigger * 100, 2) + "%", CLR_GREEN, 11);

   int sepY = rowY + 86;
   PL("CFG_EXT_TGL",  x + 24,          sepY + 8,  "TRG",                           CLR_ACCENT, 11);
   PHR("CFG_EXT_TGLN", barX,            sepY + 15, barW,                             CLR_ACCENT);
   PL("CFG_EXT_TGV",  barX + barW - 80, sepY + 5,  DoubleToString(p_Trigger, _Digits), CLR_ACCENT, 11);

   int slY    = sepY + 44;
   int slBarW = (int)(barW * (dist_sl / MathMax(maxD, 0.0001)));
   PL("CFG_EXT_SLL",  x + 24,      slY + 22, "SL", CLR_RED, 11);
   PR("CFG_EXT_SLBG", barX,        slY, barW, 60, CLR_BG, CLR_BORDER, 1);
   PR("CFG_EXT_SLLN", barX,        slY, 5,    60, CLR_RED, CLR_RED, 0);
   PR("CFG_EXT_SLFL", barX + 5,    slY + 1, slBarW - 5, 58, C'60,22,22', C'60,22,22', 0);
   PL("CFG_EXT_SLV",  barX + 18,   slY + 22, "-" + DoubleToString(dist_sl * 10000, 1) + " pips", CLR_RED, 13);
   PL("CFG_EXT_SLP",  barX + barW - 78, slY + 22, "-" + DoubleToString(dist_sl / p_Trigger * 100, 2) + "%", CLR_RED, 11);

   double rr      = dist_tp / MathMax(dist_sl, 0.00001);
   bool   rrGood  = (rr >= 1.5);
   color  rrColor = rrGood ? CLR_GREEN : (rr >= 1.0 ? CLR_AMBER : CLR_RED);

   int rrY = slY + 100, rrH = 130;
   PR("CFG_EXT_RR_BG", x + 24,   rrY, w - 48, rrH, CLR_BG, rrColor, 1);
   PL("CFG_EXT_RR_L",  x + 56,   rrY + 28, "RISK / REWARD",          CLR_TEXT_FAINT, 11);
   PL("CFG_EXT_RR_V",  x + 56,   rrY + 62, "1 : " + DoubleToString(rr, 2), rrColor, 22);

   string rrLabel = rrGood ? "OPTIMO" : (rr >= 1.0 ? "ACEPTABLE" : "SUBOPTIMO");
   int    badgeW  = 180, badgeH = 42;
   int    badgeX  = x + w - 56 - badgeW;
   int    badgeY  = rrY + (rrH - badgeH) / 2;
   PB("CFG_EXT_RR_PT", badgeX, badgeY, badgeW, badgeH, rrLabel, rrColor, CLR_TEXT, 12);
}

//+------------------------------------------------------------------+
//| APLICAR CONFIG                                                   |
//+------------------------------------------------------------------+
void AplicarConfiguracion()
{
   if(ConfigTab == 0)
   {
      double v_techo   = StringToDouble(GetEdit("CFG_E_TECHO"));
      double v_piso    = StringToDouble(GetEdit("CFG_E_PISO"));
      double v_trigger = StringToDouble(GetEdit("CFG_E_TRIGGER"));
      double v_g       = StringToDouble(GetEdit("CFG_E_G"));
      double v_vol     = StringToDouble(GetEdit("CFG_E_VOL"));

      if(v_techo > v_piso && v_trigger >= v_piso && v_trigger <= v_techo && v_g > 0 && v_vol > 0)
      {
         p_Techo = v_techo; p_Piso = v_piso; p_Trigger = v_trigger; p_G = v_g; p_Vol = v_vol;
         CalcularRejillas(); CalcularRiesgo();
         DibujarLineasGrid(); DibujarPanel();
         Print("Config Rango aplicada OK");
      }
      else Print("ERROR: Valores de rango invalidos");
   }
   else if(ConfigTab == 1)
   {
      double v_cap  = StringToDouble(GetEdit("CFG_E_CAP"));
      double v_risk = StringToDouble(GetEdit("CFG_E_RISK"));
      int    v_maxo = (int)StringToInteger(GetEdit("CFG_E_MAXO"));
      string v_lib  = GetEdit("E_LIBRE");

      if(v_cap > 0 && v_risk > 0 && v_risk <= 100 && v_maxo > 0)
      {
         p_Capital = v_cap; p_Risk = v_risk; p_MaxOrd = v_maxo;
         p_Libre   = (v_lib == "true" || v_lib == "1" || v_lib == "yes");
         CalcularRiesgo(); DibujarPanel();
         Print("Config Riesgo aplicada OK");
      }
      else Print("ERROR: Valores de riesgo invalidos");
   }
   else
   {
      double v_tp = StringToDouble(GetEdit("CFG_E_TP"));
      double v_sl = StringToDouble(GetEdit("CFG_E_SL"));
      bool tpSlOk = (p_Direccion == GRID_LONG)
                    ? (v_tp > p_Trigger && v_sl < p_Trigger)
                    : (v_tp < p_Trigger && v_sl > p_Trigger);
      if(tpSlOk)
      {
         p_TP = v_tp; p_SL = v_sl;
         CalcularRiesgo(); DibujarLineasGrid(); DibujarPanel();
         Print("Config Salidas aplicada OK");
      }
      else Print("ERROR: TP debe ser > Trigger y SL debe ser < Trigger");
   }
   BorrarConfigDialog();
   DibujarConfigDialog();
}

//+------------------------------------------------------------------+
//| OnChartEvent                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int  mx = (int)lparam, my = (int)dparam;
      bool md = ((int)StringToInteger(sparam) & 1);
      if(md && !Dragging && mx >= PanelX_cur && mx <= PanelX_cur + PanelW && my >= PanelY_cur && my <= PanelY_cur + 52)
         { Dragging = true; DragOffX = mx - PanelX_cur; DragOffY = my - PanelY_cur; }
      if(md && Dragging)
      {
         PanelX_cur = mx - DragOffX; PanelY_cur = my - DragOffY;
         int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
         int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
         if(PanelX_cur < 0) PanelX_cur = 0; if(PanelY_cur < 0) PanelY_cur = 0;
         if(PanelX_cur > cw - PanelW) PanelX_cur = cw - PanelW;
         if(PanelY_cur > ch - PanelH) PanelY_cur = ch - PanelH;
         DibujarPanel();
      }
      if(!md) Dragging = false;
      return;
   }
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == PFX + "B_CFGBTN")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ConfigVisible = !ConfigVisible;
      if(ConfigVisible) BorrarConfigDialog();
      DibujarConfigDialog();
   }
   if(sparam == PFX + "B_CFG_X")
      { ObjectSetInteger(0, sparam, OBJPROP_STATE, false); ConfigVisible = false; BorrarConfigDialog(); }
   if(sparam == PFX + "B_ALR_X" || sparam == PFX + "B_ALR_OK")
      { ObjectSetInteger(0, sparam, OBJPROP_STATE, false); AlertaVisible = false; BorrarAlerta(); }
   if(sparam == PFX + "B_CFG_CANCEL")
      { ObjectSetInteger(0, sparam, OBJPROP_STATE, false); ConfigVisible = false; BorrarConfigDialog(); }

   for(int t = 0; t < 3; t++)
      if(sparam == PFX + "B_CFG_T" + IntegerToString(t))
         { ObjectSetInteger(0, sparam, OBJPROP_STATE, false); ConfigTab = t; BorrarConfigDialog(); DibujarConfigDialog(); }

   if(sparam == PFX + "B_CFG_DIR_LONG")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      p_Direccion = GRID_LONG;
      CalcularRejillas(); CalcularRiesgo();
      BorrarConfigDialog(); DibujarConfigDialog();
   }
   if(sparam == PFX + "B_CFG_DIR_SHORT")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      p_Direccion = GRID_SHORT;
      CalcularRejillas(); CalcularRiesgo();
      BorrarConfigDialog(); DibujarConfigDialog();
   }
   if(sparam == PFX + "B_CFG_ML_OFF")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      p_Libre = false;
      ObjectSetString(0, PFX + "E_E_LIBRE", OBJPROP_TEXT, "false");
      BorrarConfigDialog(); DibujarConfigDialog();
   }
   if(sparam == PFX + "B_CFG_ML_ON")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      p_Libre = true;
      ObjectSetString(0, PFX + "E_E_LIBRE", OBJPROP_TEXT, "true");
      BorrarConfigDialog(); DibujarConfigDialog();
   }
   if(sparam == PFX + "B_CFG_APPLY")
      { ObjectSetInteger(0, sparam, OBJPROP_STATE, false); AplicarConfiguracion(); }

   if(sparam == PFX + "B_START")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      bool ok = (RiesgoRealPct <= p_Risk) || p_Libre;
      if(!ok)
      {
         PrintFormat("ALERTA: Riesgo %.1f%% > %.1f%%. Max seguro=%d", RiesgoRealPct, p_Risk, MaxOrdersSafe);
         MostrarAlerta("RIESGO EXCEDIDO",
            "Tu configuracion tiene un riesgo del " + DoubleToString(RiesgoRealPct, 1) + "% que supera el " + DoubleToString(p_Risk, 1) + "% permitido.",
            "Maximo seguro: " + IntegerToString(MaxOrdersSafe) + " rejilla" + (MaxOrdersSafe == 1 ? "" : "s") + ". Activa Modo Libre para forzar.",
            ALERT_WARN);
         return;
      }
      int ex = EscanearOrdenesExistentes();
      if(ex > 0) { RejillasActivas = ex; estado = ACTIVE;  PrintFormat("Retomando %d ordenes — ACTIVE", ex); }
      else        {                        estado = PENDING; Print("PENDING — esperando trigger"); }
      DibujarLineasGrid(); DibujarPanel();
   }
   if(sparam == PFX + "B_PAUSE")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      if     (estado == ACTIVE) { estado = PAUSED; Print("PAUSED"); }
      else if(estado == PAUSED) { estado = ACTIVE; Print("ACTIVE"); }
      DibujarPanel();
   }
   if(sparam == PFX + "B_STOP")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      CancelarPendientes(); CerrarTodo();
      estado = STOPPED; RejillasActivas = 0;
      DibujarLineasGrid(); DibujarPanel();
   }
   if(sparam == PFX + "B_CANCEL")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      CancelarPendientes();
      estado = STOPPED; RejillasActivas = 0;
      Print("Orden pendiente cancelada — STOPPED");
      DibujarLineasGrid(); DibujarPanel();
      MostrarAlerta("ORDEN CANCELADA",
         "La orden pendiente fue cancelada exitosamente.",
         "Puedes modificar la configuracion o reiniciar el bot cuando lo desees.",
         ALERT_INFO);
   }
}

//+------------------------------------------------------------------+
//| LOGICA DE TRADING                                                |
//+------------------------------------------------------------------+
void CalcularRejillas()
{
   ArrayResize(GridLevels, 0);
   double nivel = p_Trigger;
   if(p_Direccion == GRID_LONG)
   {
      while(nivel >= p_Piso)
      {
         int n = ArraySize(GridLevels); ArrayResize(GridLevels, n + 1);
         GridLevels[n] = NormalizeDouble(nivel, _Digits);
         nivel = nivel / (1.0 + p_G);
      }
   }
   else
   {
      while(nivel <= p_Techo)
      {
         int n = ArraySize(GridLevels); ArrayResize(GridLevels, n + 1);
         GridLevels[n] = NormalizeDouble(nivel, _Digits);
         nivel = nivel * (1.0 + p_G);
      }
   }
   PrintFormat("Rejillas (%s): %d", p_Direccion == GRID_LONG ? "LONG" : "SHORT", ArraySize(GridLevels));
}

bool ValidarInputs()
{
   if(MagicNumber == 0)                          { Print("ERROR: Magic=0");         return false; }
   if(p_Piso >= p_Techo)                         { Print("ERROR: Piso>=Techo");     return false; }
   if(p_G <= 0)                                  { Print("ERROR: G%<=0");           return false; }
   if(p_Vol <= 0)                                { Print("ERROR: Volumen<=0");      return false; }
   if(p_Trigger < p_Piso || p_Trigger > p_Techo){ Print("ERROR: Trigger fuera");   return false; }
   if(p_Capital <= 0)                            { Print("ERROR: Capital<=0");      return false; }
   if(p_Direccion == GRID_LONG)
   {
      if(p_TP <= p_Trigger){ Print("ERROR LONG: TP debe ser > Trigger"); return false; }
      if(p_SL >= p_Trigger){ Print("ERROR LONG: SL debe ser < Trigger"); return false; }
   }
   else
   {
      if(p_TP >= p_Trigger){ Print("ERROR SHORT: TP debe ser < Trigger"); return false; }
      if(p_SL <= p_Trigger){ Print("ERROR SHORT: SL debe ser > Trigger"); return false; }
   }
   return true;
}

bool OrdenExisteEnNivel(double pr)
{
   double tol = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 5;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i); if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC)  != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL)  != _Symbol)     continue;
      if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - pr) <= tol) return true;
   }
   return false;
}

int ContarPosicionesAbiertas()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i); if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol) c++;
   }
   return c;
}

void ActivarGrid()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   long   stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minD  = stops * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    col = 0, fl = 0, total = MathMin(ArraySize(GridLevels), p_MaxOrd);

   if(p_Direccion == GRID_LONG)
   {
      if(!trade.Buy(p_Vol, _Symbol, 0, 0, 0, "GRID_BUY_0"))
         PrintFormat("FALLO Buy[0] rc=%u", trade.ResultRetcode());
      else Print("Buy[0] mercado OK");
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      for(int i = 1; i < total; i++)
      {
         double nv = GridLevels[i]; if(OrdenExisteEnNivel(nv)) continue; if(nv >= ask - minD) continue;
         bool ok = trade.BuyLimit(p_Vol, nv, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "GRID_BUY_" + IntegerToString(i));
         if(ok) col++; else { fl++; PrintFormat("FALLO [%d] rc=%u", i, trade.ResultRetcode()); }
      }
   }
   else
   {
      if(!trade.Sell(p_Vol, _Symbol, 0, 0, 0, "GRID_SELL_0"))
         PrintFormat("FALLO Sell[0] rc=%u", trade.ResultRetcode());
      else Print("Sell[0] mercado OK");
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      for(int i = 1; i < total; i++)
      {
         double nv = GridLevels[i]; if(OrdenExisteEnNivel(nv)) continue; if(nv <= bid + minD) continue;
         bool ok = trade.SellLimit(p_Vol, nv, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "GRID_SELL_" + IntegerToString(i));
         if(ok) col++; else { fl++; PrintFormat("FALLO [%d] rc=%u", i, trade.ResultRetcode()); }
      }
   }
   RejillasActivas = col + 1;
   DibujarLineasGrid();
}

void CerrarTodo()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i); if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;
      if(!trade.PositionClose(t)) PrintFormat("FALLO cerrar %I64u rc=%u", t, trade.ResultRetcode());
   }
}

void CancelarPendientes()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i); if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)     continue;
      if(!trade.OrderDelete(t)) PrintFormat("FALLO cancel %I64u rc=%u", t, trade.ResultRetcode());
   }
}

bool CheckKillSwitch()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool hTP, hSL;
   if(p_Direccion == GRID_LONG) { hTP = (bid >= p_TP); hSL = (bid <= p_SL); }
   else                          { hTP = (bid <= p_TP); hSL = (bid >= p_SL); }
   if(hTP || hSL)
   {
      PrintFormat("KILL SWITCH: %s", hTP ? "TP" : "SL");
      CancelarPendientes(); CerrarTodo();
      estado = hTP ? PENDING : STOPPED;
      RejillasActivas = 0;
      DibujarLineasGrid(); DibujarPanel();
      return true;
   }
   return false;
}

void CheckTrigger()
{
   if(estado != PENDING) return;
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool   triggered = (p_Direccion == GRID_LONG) ? (bid <= p_Trigger) : (bid >= p_Trigger);
   if(!triggered) return;
   PrintFormat("TRIGGER (%s) @ %s", p_Direccion == GRID_LONG ? "LONG" : "SHORT", DoubleToString(bid, _Digits));
   ActivarGrid();
   estado = ACTIVE;
   Print("ACTIVE");
}

void CheckRange()
{
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool   fuera = (bid > p_Techo || bid < p_Piso);
   if     (estado == ACTIVE  &&  fuera) { estado = PAUSED; Print("PAUSED"); }
   else if(estado == PAUSED  && !fuera) { estado = ACTIVE;  Print("ACTIVE"); }
}

void LogOperacion(string tipo, double salida, double lotes, double ganancia)
{
   GananciaAcumulada += ganancia;
   string fn = "GridBot_Log_" + _Symbol + ".csv";
   int    h  = FileOpen(fn, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE) { Print("FALLO log:", GetLastError()); return; }
   if(FileSize(h) == 0)
      FileWrite(h, "Timestamp", "Par", "Tipo", "Salida", "Lotes", "Ganancia", "Acumulada");
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), _Symbol, tipo,
             DoubleToString(salida, _Digits), DoubleToString(lotes, 2),
             DoubleToString(ganancia, 2), DoubleToString(GananciaAcumulada, 2));
   FileClose(h);
}

void ColocarContraparte(int idx, ENUM_DEAL_TYPE dt, double pe)
{
   if(idx < 0 || idx >= ArraySize(GridLevels)) return;
   if(ContarPosicionesAbiertas() >= p_MaxOrd) { Print("FRENO Max_Orders"); return; }
   trade.SetExpertMagicNumber(MagicNumber);
   MarcarRejillaActiva(idx, true);
   RejillasActivas++;
   if(dt == DEAL_TYPE_BUY)
   {
      double obj = NormalizeDouble(pe * (1.0 + p_G), _Digits);
      if(!trade.SellLimit(p_Vol, obj, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "GRID_TP_" + IntegerToString(idx)))
         PrintFormat("FALLO TP-sell idx=%d rc=%u", idx, trade.ResultRetcode());
   }
   else if(dt == DEAL_TYPE_SELL)
   {
      double obj = NormalizeDouble(pe / (1.0 + p_G), _Digits);
      if(!trade.BuyLimit(p_Vol, obj, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "GRID_TP_" + IntegerToString(idx)))
         PrintFormat("FALLO TP-buy idx=%d rc=%u", idx, trade.ResultRetcode());
   }
}

void ReponerEntrada(int idx)
{
   if(idx < 0 || idx >= ArraySize(GridLevels)) return;
   if(estado == PAUSED || estado == STOPPED)   return;
   if(ContarPosicionesAbiertas() >= p_MaxOrd)  return;
   double nv = GridLevels[idx];
   if(OrdenExisteEnNivel(nv)) return;
   MarcarRejillaActiva(idx, false);
   if(RejillasActivas > 0) RejillasActivas--;
   trade.SetExpertMagicNumber(MagicNumber);
   bool ok;
   if(p_Direccion == GRID_LONG)
      ok = trade.BuyLimit(p_Vol,  nv, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "GRID_BUY_"  + IntegerToString(idx));
   else
      ok = trade.SellLimit(p_Vol, nv, _Symbol, 0, 0, ORDER_TIME_GTC, 0, "GRID_SELL_" + IntegerToString(idx));
   if(!ok) PrintFormat("FALLO repos idx=%d rc=%u", idx, trade.ResultRetcode());
}

void ProcesarDeals()
{
   if(!HistorySelect(0, TimeCurrent() + 1)) return;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket <= UltimoDealProcesado)                                 continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  != MagicNumber)    continue;
      if(HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol)        continue;

      ENUM_DEAL_ENTRY entry  = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      ENUM_DEAL_TYPE  dtype  = (ENUM_DEAL_TYPE) HistoryDealGetInteger(ticket, DEAL_TYPE);
      double          precio = HistoryDealGetDouble(ticket, DEAL_PRICE);
      double          vol    = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double          profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                             + HistoryDealGetDouble(ticket, DEAL_SWAP)
                             + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      string          comment = HistoryDealGetString(ticket, DEAL_COMMENT);
      int             idx    = IndiceDesdeComment(comment);

      if     (entry == DEAL_ENTRY_IN)  ColocarContraparte(idx, dtype, precio);
      else if(entry == DEAL_ENTRY_OUT) { LogOperacion("CLOSE_" + IntegerToString(idx), precio, vol, profit); ReponerEntrada(idx); }
      UltimoDealProcesado = ticket;
   }
}

int EscanearOrdenesExistentes()
{
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i); if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) == MagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol) c++;
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i); if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol) c++;
   }
   return c;
}

void InicializarCursorDeals()
{
   if(!HistorySelect(0, TimeCurrent() + 1)) return;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(t, DEAL_MAGIC)  != MagicNumber) continue;
      if(HistoryDealGetString(t,  DEAL_SYMBOL) != _Symbol)     continue;
      if(t > UltimoDealProcesado) UltimoDealProcesado = t;
   }
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("================================================");
   Print("GridBot v3.40 | UI Modern Dark | ", _Symbol);
   Print("================================================");
   CargarParametros();
   if(!ValidarInputs()) return INIT_PARAMETERS_INCORRECT;

   PanelX_cur = PanelX; PanelY_cur = PanelY;
   CalcularRejillas(); CalcularRiesgo();
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(10);
   InicializarCursorDeals();
   estado = PRECHECK;
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   PrintFormat("Risk: Real=%.1f%% ($%.2f) | Seguro=%d rejillas", RiesgoRealPct, RiesgoRealUSD, MaxOrdersSafe);
   DibujarLineasGrid(); DibujarPanel();
   Print(">>> Arrastra panel por el header | CONFIG arriba derecha | Pulsa INICIAR");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   if(estado == PRECHECK || estado == STOPPED) return;
   if(CheckKillSwitch()) return;
   if(estado == PENDING) CheckTrigger();
   else { CheckRange(); ProcesarDeals(); }
   DibujarPanel();
}

//+------------------------------------------------------------------+
//| OnTradeTransaction                                               |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) ProcesarDeals();
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
   BorrarTodo();
   PrintFormat("GridBot v3.40 fin. Estado=%d | Acumulado=%.2f USD", estado, GananciaAcumulada);
}
//+------------------------------------------------------------------+
