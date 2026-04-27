//+------------------------------------------------------------------+
//| GridBot.mq5                                                      |
//| Bot de Grid Geometrico Dinamico para Forex (MT5)                 |
//| v3.4.3 — UI Responsive + Minimizar + LONG/SHORT                  |
//+------------------------------------------------------------------+
#property copyright "Oscar Alvarado"
#property version   "3.43"
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
//| ESTADO Y GLOBALES                                                |
//+------------------------------------------------------------------+
enum EstadoBot { PENDING, ACTIVE, PAUSED, STOPPED, PRECHECK };
EstadoBot estado = PRECHECK;

enum AlertType { ALERT_INFO, ALERT_WARN, ALERT_ERROR, ALERT_SUCCESS };
bool      AlertaVisible    = false;
bool      PanelMinimized   = false;
bool      ConfigMinimized  = false;

// Drag de paneles
bool DragPanel = false, DragConfig = false;
int  DragOffX  = 0, DragOffY = 0;
int  PanelPosX = 8, PanelPosY = 8;     // posicion runtime del panel principal
int  ConfigPosX = -1, ConfigPosY = -1; // posicion runtime del config (-1 = centrar)

// Cache para evitar parpadeo en CHART_CHANGE
int  LastChartW = 0, LastChartH = 0;

// Cache de valores de OBJ_EDIT — para detectar cambios y auto-aplicar
string PrevTecho="", PrevPiso="", PrevTrigger="", PrevG="", PrevVol="";
string PrevCap="", PrevRisk="", PrevMaxo="";
string PrevTP="", PrevSL="";
string    AlertaTitle      = "";
string    AlertaMsg        = "";
string    AlertaSubMsg     = "";
AlertType AlertaTipo       = ALERT_INFO;

double GridLevels[];
double GananciaAcumulada   = 0.0;
ulong  UltimoDealProcesado = 0;
int    RejillasActivas     = 0;
int    MaxOrdersSafe       = 0;
double RiesgoRealUSD       = 0.0;
double RiesgoRealPct       = 0.0;
double GananciaPorRejilla  = 0.0;
string PFX = "GB34_";

int  PanelW = 220, PanelH = 320;

bool ConfigVisible = false;
int  ConfigTab     = 0;
int  CfgX, CfgY;
int  CfgW = 700, CfgH = 960;
bool CfgCompact = false;

//+------------------------------------------------------------------+
//| PALETA                                                           |
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

#define CLR_MINT        CLR_GREEN
#define CLR_MINT_ACT    C'34,220,110'
#define CLR_MINT_DIM    C'21,90,40'
#define CLR_TP          CLR_GREEN
#define CLR_SL          CLR_RED
#define CLR_RANGO       CLR_AMBER
#define CLR_TRIGGER     CLR_ACCENT

//+------------------------------------------------------------------+
//| HELPERS                                                          |
//+------------------------------------------------------------------+
// Factor de escala UI — compensa diferencias de DPI Win/Mac
double GetUIScale()
{
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   if(cw <= 0) return 1.0;
   double scale = (double)cw / 1280.0;
   if(scale < 0.85) scale = 0.85;
   if(scale > 1.25) scale = 1.25;
   return scale;
}

int Sc(int v) { return (int)MathRound(v * GetUIScale()); }

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
      if(StringFind(n, PFX + "L_TP") == 0 || StringFind(n, PFX + "L_SL") == 0 ||
         StringFind(n, PFX + "L_TECHO") == 0 || StringFind(n, PFX + "L_PISO") == 0 ||
         StringFind(n, PFX + "L_TRIGGER") == 0 || StringFind(n, PFX + "L_GRID_") == 0 ||
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
      string lbl = (ok ? lbl_prefix : lbl_prefix+"*") + " [" + IntegerToString(i) + "]";
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
   bool existed = (ObjectFind(0, n) >= 0);
   if(!existed) ObjectCreate(0, n, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,        h);
   // CRITICAL: solo setear texto si el objeto es NUEVO
   // Si ya existía (el usuario lo está editando), respetar su valor actual
   if(!existed) ObjectSetString(0, n, OBJPROP_TEXT, val);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      CLR_BG_DEEP);
   ObjectSetInteger(0, n, OBJPROP_COLOR,        CLR_TEXT);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, CLR_BORDER);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,     10);
   ObjectSetString(0,  n, OBJPROP_FONT,         "Consolas");
   ObjectSetInteger(0, n, OBJPROP_ALIGN,        ALIGN_LEFT);
   ObjectSetInteger(0, n, OBJPROP_READONLY,     false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, n, OBJPROP_BACK,         false);
}

// Forzar setear texto en un OBJ_EDIT (usado cuando hace falta resetear el valor)
void PE_Force(string id, string val)
{
   string n = PFX + "E_" + id;
   if(ObjectFind(0, n) >= 0)
      ObjectSetString(0, n, OBJPROP_TEXT, val);
}

void PHR(string id, int x, int y, int w, color clr)  { PR(id, x, y, w, 1, clr, clr, 0); }
void PVR(string id, int x, int y, int h, color clr)  { PR(id, x, y, 1, h, clr, clr, 0); }

string GetEdit(string id)  { return ObjectGetString(0, PFX + "E_" + id, OBJPROP_TEXT); }
void   DelObj(string full) { ObjectDelete(0, PFX + full); }

//+------------------------------------------------------------------+
//| ALERTAS POPUP                                                    |
//+------------------------------------------------------------------+
void MostrarAlerta(string title, string msg, string subMsg, AlertType tipo)
{
   AlertaTitle  = title; AlertaMsg = msg; AlertaSubMsg = subMsg; AlertaTipo = tipo;
   AlertaVisible = true; DibujarAlerta();
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
   int charW    = (sz <= 9) ? 10 : (sz <= 10) ? 12 : (sz <= 11) ? 13 : 14;
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
      if(StringLen(nueva) <= maxChars) linea = nueva;
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

   double sc = GetUIScale();
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   int W = MathMin((int)(680*sc), cw - 40);  if(W < 360) W = 360;
   int H = MathMin((int)(330*sc), ch - 40);  if(H < 240) H = 240;
   int x = (cw - W) / 2; if(x < 10) x = 10;
   int y = (ch - H) / 2; if(y < 10) y = 10;

   color  iconC; string iconText;
   switch(AlertaTipo)
   {
      case ALERT_ERROR:   iconC = CLR_RED;    iconText = "!";  break;
      case ALERT_WARN:    iconC = CLR_AMBER;  iconText = "!";  break;
      case ALERT_SUCCESS: iconC = CLR_GREEN;  iconText = "OK"; break;
      default:            iconC = CLR_ACCENT; iconText = "i";  break;
   }

   bool compact = (H < 320);
   int  PAD     = compact ? Sc(18) : Sc(24);
   int  hdrH    = compact ? Sc(52) : Sc(64);
   int  footerSpace = compact ? Sc(50) : Sc(58);
   int  okBtnH  = compact ? Sc(34) : Sc(40);

   PR("ALR_BG",     x, y, W, H,    CLR_PANEL,    CLR_ACCENT,  2);
   PR("ALR_HDR",    x, y, W, hdrH, CLR_BG_DEEP,  CLR_BG_DEEP, 0);
   PHR("ALR_HDR_LN", x, y + hdrH - 1, W, CLR_ACCENT);

   int icnY = y + (hdrH - Sc(28)) / 2;
   PB("ALR_ICN", x + PAD, icnY, Sc(28), Sc(28), iconText, iconC, CLR_TEXT, Sc(14));
   ObjectSetInteger(0, PFX + "B_ALR_ICN", OBJPROP_BORDER_COLOR, iconC);

   int titX = x + PAD + Sc(40);
   int titW = W - PAD * 2 - Sc(80);
   PB("ALR_TIT", titX, icnY, titW, Sc(28), AlertaTitle, CLR_BG_DEEP, CLR_TEXT, Sc(12));
   ObjectSetInteger(0, PFX + "B_ALR_TIT", OBJPROP_BORDER_COLOR, CLR_BG_DEEP);

   PB("ALR_X", x + W - PAD - Sc(30), icnY, Sc(30), Sc(28), "X", CLR_RED_DIM, CLR_TEXT, Sc(12));

   int by    = y + hdrH + (compact ? Sc(16) : Sc(24));
   int textW = W - PAD * 2;
   DibujarTextoLargo("ALR_MSG", x + PAD, by, textW - 12, AlertaMsg, CLR_TEXT, Sc(11), Sc(22));

   if(StringLen(AlertaSubMsg) > 0)
   {
      int subY = by + (compact ? Sc(50) : Sc(60));
      int subH = compact ? Sc(52) : Sc(64);
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
//| BOTONES ESQUINA SUPERIOR DERECHA (CONFIG + DIRBADGE)              |
//+------------------------------------------------------------------+
void DibujarBotonesEsquina()
{
   double sc = GetUIScale();
   int btnW   = Sc(86);
   int btnH   = Sc(26);
   int badgeW = Sc(64);
   int gap    = Sc(6);
   int margin = Sc(10);

   PB("CFGBTN", btnW + margin, margin, btnW, btnH, "CONFIG", CLR_ACCENT, CLR_TEXT, Sc(9));
   ObjectSetInteger(0, PFX + "B_CFGBTN", OBJPROP_CORNER,       CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, PFX + "B_CFGBTN", OBJPROP_XDISTANCE,    btnW + margin);
   ObjectSetInteger(0, PFX + "B_CFGBTN", OBJPROP_YDISTANCE,    margin);
   ObjectSetInteger(0, PFX + "B_CFGBTN", OBJPROP_BORDER_COLOR, CLR_ACCENT);

   color  dirC = (p_Direccion == GRID_LONG) ? CLR_GREEN : CLR_RED;
   string dirT = (p_Direccion == GRID_LONG) ? "LONG" : "SHORT";
   int badgeXDist = btnW + margin + gap + badgeW;
   PB("DIRBADGE", badgeXDist, margin, badgeW, btnH, dirT, CLR_BG_DEEP, dirC, Sc(9));
   ObjectSetInteger(0, PFX + "B_DIRBADGE", OBJPROP_CORNER,       CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, PFX + "B_DIRBADGE", OBJPROP_XDISTANCE,    badgeXDist);
   ObjectSetInteger(0, PFX + "B_DIRBADGE", OBJPROP_YDISTANCE,    margin);
   ObjectSetInteger(0, PFX + "B_DIRBADGE", OBJPROP_BORDER_COLOR, dirC);
}

//+------------------------------------------------------------------+
//| PANEL DE ESTADO — fijo izquierda, escalado, minimizable          |
//+------------------------------------------------------------------+
void BorrarPanelTodo()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, PFX) != 0) continue;
      // Conservar lineas del grafico, dialog config, y alertas
      if(StringFind(n, PFX + "L_TP") == 0)      continue;
      if(StringFind(n, PFX + "L_SL") == 0)      continue;
      if(StringFind(n, PFX + "L_TECHO") == 0)   continue;
      if(StringFind(n, PFX + "L_PISO") == 0)    continue;
      if(StringFind(n, PFX + "L_TRIGGER") == 0) continue;
      if(StringFind(n, PFX + "L_GRID_") == 0)   continue;
      if(StringFind(n, PFX + "T_") == 0)        continue;
      if(StringFind(n, PFX + "R_CFG_") == 0)    continue;
      if(StringFind(n, PFX + "L_CFG_") == 0)    continue;
      if(StringFind(n, PFX + "B_CFG_") == 0)    continue;
      if(StringFind(n, PFX + "E_CFG_") == 0)    continue;
      if(StringFind(n, PFX + "R_ALR") == 0)     continue;
      if(StringFind(n, PFX + "L_ALR") == 0)     continue;
      if(StringFind(n, PFX + "B_ALR") == 0)     continue;
      if(StringFind(n, PFX + "B_CFGBTN") == 0)  continue;
      if(StringFind(n, PFX + "B_DIRBADGE") == 0)continue;
      ObjectDelete(0, n);
   }
}

void DibujarPanel()
{
   BorrarPanelTodo();

   double sc  = GetUIScale();
   int    W   = Sc(180);
   int    PAD = Sc(10);
   int    HDR = Sc(28);
   int    x   = PanelPosX;
   int    y   = PanelPosY;

   int rowH = Sc(15);
   int gapS = Sc(5);
   int sz7  = Sc(7);
   int sz8  = Sc(8);
   int sz9  = Sc(9);
   int sz10 = Sc(10);
   int COL  = Sc(78);

   string minIcon = PanelMinimized ? "+" : "_";
   int    minSz   = Sc(18);
   int    minY    = y + (HDR - minSz) / 2;
   int    logoSz  = Sc(18);
   int    logoY   = y + (HDR - logoSz) / 2;

   // BG primero
   int totalH = PanelMinimized ? HDR : Sc(260);
   PR("BG", x, y, W, totalH, CLR_PANEL, CLR_BORDER_LT, 1);

   // Header
   PR("BG_HDR", x, y, W, HDR, CLR_BG_DEEP, CLR_BG_DEEP, 0);
   if(!PanelMinimized) PHR("HDR_LN", x, y + HDR - 1, W, CLR_BORDER);

   // Elementos del header
   PB("LOGO", x + PAD, logoY, logoSz, logoSz, "G", CLR_ACCENT, CLR_TEXT, Sc(9));
   ObjectSetInteger(0, PFX + "B_LOGO", OBJPROP_BORDER_COLOR, CLR_ACCENT);
   PL("HTIT", x + PAD + logoSz + Sc(6), y + (HDR - Sc(12))/2, "GRIDBOT", CLR_TEXT, sz9);

   // Minimizar
   PB("MINBTN", x + W - PAD - minSz, minY, minSz, minSz, minIcon, CLR_PANEL_HOV, CLR_TEXT, Sc(10));

   // Botones esquina derecha del chart
   DibujarBotonesEsquina();

   if(PanelMinimized)
   {
      ChartRedraw(0);
      return;
   }

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

   int cy = y + HDR + gapS + Sc(2);

   PL("ELAB", x + PAD, cy + 1, "ESTADO", CLR_TEXT_FAINT, sz7);
   PL("EVAL", x + COL, cy,     eStr,     eClr,           sz10);
   cy += rowH + Sc(2);
   PHR("S1", x + PAD, cy, W - PAD * 2, CLR_BORDER); cy += gapS;

   PL("BLAB", x + PAD, cy + 1, "PRECIO", CLR_TEXT_FAINT, sz7);
   PL("BVAL", x + COL, cy,     DoubleToString(bid, _Digits), CLR_TEXT, sz9);
   cy += rowH - Sc(1);
   PL("TLAB", x + PAD, cy + 1, "TRIGGER", CLR_TEXT_FAINT, sz7);
   PL("TVAL", x + COL, cy,     DoubleToString(p_Trigger, _Digits), CLR_ACCENT, sz9);
   cy += rowH + Sc(2);
   PHR("S2", x + PAD, cy, W - PAD * 2, CLR_BORDER); cy += gapS;

   PL("RHTL", x + PAD, cy, "RIESGO", CLR_TEXT_FAINT, sz7); cy += rowH - Sc(3);
   PL("RCLA", x + PAD, cy + 1, "Config", CLR_TEXT_DIM, sz7);
   PL("RCVA", x + COL, cy, DoubleToString(p_Risk, 1) + "% / $" + DoubleToString(p_Capital * p_Risk / 100, 0), CLR_GREEN, sz8);
   cy += rowH - Sc(3);
   PL("RRLA", x + PAD, cy + 1, "Real", CLR_TEXT_DIM, sz7);
   PL("RRVA", x + COL, cy, DoubleToString(RiesgoRealPct, 1) + "% / $" + DoubleToString(RiesgoRealUSD, 1), rskC, sz8);
   cy += rowH - Sc(3);
   PL("GRLA", x + PAD, cy + 1, "Rejillas", CLR_TEXT_DIM, sz7);
   PL("GRVA", x + COL, cy, IntegerToString(RejillasActivas) + "/" + IntegerToString(p_MaxOrd) + " (" + IntegerToString(MaxOrdersSafe) + " ok)", CLR_TEXT, sz8);
   cy += rowH - Sc(3);
   PL("GPLA", x + PAD, cy + 1, "Gan/rej", CLR_TEXT_DIM, sz7);
   PL("GPVA", x + COL, cy, "$" + DoubleToString(GananciaPorRejilla, 2), CLR_GREEN, sz8);
   cy += rowH - Sc(1);
   PHR("S3", x + PAD, cy, W - PAD * 2, CLR_BORDER); cy += gapS;

   PL("GNLA", x + PAD, cy + 1, "GANANCIA", CLR_TEXT_FAINT, sz7);
   PL("GNVA", x + COL, cy,     ganS,       ganC,           sz10);
   cy += rowH + Sc(2);
   PHR("S4", x + PAD, cy, W - PAD * 2, CLR_BORDER); cy += gapS;

   int btnH = Sc(24);
   if(estado == PRECHECK || estado == STOPPED)
   {
      PB("START", x + PAD, cy, W - PAD * 2, btnH, "INICIAR BOT", CLR_GREEN_DIM, CLR_TEXT, sz9);
   }
   else if(estado == PENDING)
   {
      PB("CANCEL", x + PAD, cy, W - PAD * 2, btnH, "CANCELAR", CLR_RED_DIM, CLR_TEXT, sz9);
   }
   else if(estado == ACTIVE || estado == PAUSED)
   {
      int    bw   = (W - PAD * 2 - Sc(4)) / 2;
      string ptxt = (estado == ACTIVE) ? "PAUSAR" : "REANUDAR";
      PB("PAUSE", x + PAD,             cy, bw, btnH, ptxt,    CLR_ACCENT,  CLR_TEXT, sz8);
      PB("STOP",  x + PAD + bw + Sc(4), cy, bw, btnH, "PARAR", CLR_RED_DIM, CLR_TEXT, sz8);
   }

   PanelH = (cy + btnH + gapS) - y;
   ObjectSetInteger(0, PFX + "R_BG", OBJPROP_YSIZE, PanelH);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| VENTANA CONFIG (responsive + minimizable)                        |
//+------------------------------------------------------------------+
int  CFG_HDR_H=110, CFG_TABS_H=54, CFG_FOOT_H=88, CFG_BODY_PAD_TOP=40;
int  CFG_ROW_GAP=110, CFG_CARD_H_RANGE=200, CFG_CARD_H_RISK=280, CFG_CARD_H_EXIT=480;
int  CFG_PAD=32;

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

void CalcularLayoutConfig()
{
   double sc = GetUIScale();
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

   int maxW = cw - 40;
   int maxH = ch - 40;

   // Tamaño profesional compacto
   CfgW = MathMin((int)(460*sc), maxW); if(CfgW < 400) CfgW = 400;
   CfgH = MathMin((int)(580*sc), maxH); if(CfgH < 420) CfgH = 420;

   CfgCompact = true;  // siempre compacto para look profesional consistente

   CFG_HDR_H        = Sc(56);
   CFG_TABS_H       = Sc(34);
   CFG_FOOT_H       = Sc(52);
   CFG_BODY_PAD_TOP = Sc(14);
   CFG_ROW_GAP      = Sc(56);
   CFG_CARD_H_RANGE = Sc(96);
   CFG_CARD_H_RISK  = Sc(168);
   CFG_CARD_H_EXIT  = Sc(220);
   CFG_PAD          = Sc(16);
}

void CfgField(string id, int x, int y, int w, string label, string val, string suffix = "")
{
   int inputH = Sc(22);
   int gap    = Sc(14);
   int sufW   = Sc(34);
   int lblSz  = Sc(8);
   PL("CFG_" + id + "_L", x, y, label, CLR_TEXT_DIM, lblSz);
   if(suffix != "")
   {
      PE("CFG_" + id,         x,             y + gap, w - sufW - 2, inputH, val);
      PR("CFG_" + id + "_SB", x + w - sufW,  y + gap, sufW, inputH, CLR_BG_DEEP, CLR_BORDER, 1);
      PL("CFG_" + id + "_S",  x + w - sufW + Sc(10), y + gap + (inputH - Sc(13))/2, suffix, CLR_TEXT_FAINT, lblSz);
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

   // Si esta minimizado, mostrar solo barra flotante
   if(ConfigMinimized)
   {
      BorrarConfigDialog();
      double sc = GetUIScale();
      int    bw = Sc(240);
      int    bh = Sc(36);
      int    cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int    bx = (cw - bw) / 2;
      int    by = Sc(60);
      PR("CFG_BG",  bx, by, bw, bh, CLR_BG_DEEP, CLR_ACCENT, 2);
      PL("CFG_TIT", bx + Sc(14), by + (bh - Sc(13))/2, "CONFIG (minimizada)", CLR_TEXT, Sc(10));
      int rsz = bh - Sc(8);
      PB("CFG_MIN", bx + bw - rsz - rsz - Sc(10), by + Sc(4), rsz, rsz, "+", CLR_PANEL_HOV, CLR_TEXT, Sc(11));
      PB("CFG_X",   bx + bw - rsz - Sc(6),         by + Sc(4), rsz, rsz, "X", CLR_RED_DIM, CLR_TEXT, Sc(11));
      ChartRedraw(0);
      return;
   }

   CalcularLayoutConfig();

   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(ConfigPosX < 0 || ConfigPosY < 0)
   {
      // Primera vez — centrar
      CfgX = (cw - CfgW) / 2; if(CfgX < 10) CfgX = 10;
      CfgY = (ch - CfgH) / 2; if(CfgY < 10) CfgY = 10;
      ConfigPosX = CfgX; ConfigPosY = CfgY;
   }
   else
   {
      CfgX = ConfigPosX; CfgY = ConfigPosY;
      // Asegurar que no se salga del chart
      if(CfgX + CfgW > cw) CfgX = cw - CfgW - 10;
      if(CfgY + CfgH > ch) CfgY = ch - CfgH - 10;
      if(CfgX < 10) CfgX = 10;
      if(CfgY < 10) CfgY = 10;
   }

   int x = CfgX, y = CfgY, W = CfgW, H = CfgH;
   int PAD      = CFG_PAD;
   int FOOTER_H = CFG_FOOT_H;
   int HDR_H    = CFG_HDR_H;
   int TABS_H   = CFG_TABS_H;

   PR("CFG_BG",     x, y, W, H,        CLR_PANEL,   CLR_BORDER_LT, 1);
   PR("CFG_HDR",    x, y, W, HDR_H,    CLR_BG_DEEP, CLR_BG_DEEP,   0);
   PHR("CFG_HDR_LN", x, y + HDR_H - 1, W, CLR_BORDER);

   int logoSize = Sc(26);
   int logoY    = y + (HDR_H - logoSize) / 2;
   PB("CFG_LOGO", x + PAD, logoY, logoSize, logoSize, "G", CLR_ACCENT, CLR_TEXT, Sc(12));
   ObjectSetInteger(0, PFX + "B_CFG_LOGO", OBJPROP_BORDER_COLOR, CLR_ACCENT);

   int titX  = x + PAD + logoSize + Sc(10);
   int titSz = Sc(11);
   int subSz = Sc(8);
   int titY  = y + HDR_H/2 - Sc(12);
   int subY  = y + HDR_H/2 + Sc(2);
   PL("CFG_TIT", titX, titY, "GRIDBOT CONFIG",  CLR_TEXT,     titSz, "Arial");
   PL("CFG_SUB", titX, subY, "v3.4.3 " + _Symbol, CLR_TEXT_DIM, subSz);

   string stBadge; color stBadgeC;
   switch(estado)
   {
      case ACTIVE:  stBadge = "ACTIVE";  stBadgeC = CLR_GREEN;  break;
      case PAUSED:  stBadge = "PAUSED";  stBadgeC = CLR_AMBER;  break;
      case PENDING: stBadge = "PENDING"; stBadgeC = CLR_ACCENT; break;
      case STOPPED: stBadge = "STOPPED"; stBadgeC = CLR_RED;    break;
      default:      stBadge = "READY";   stBadgeC = CLR_AMBER;  break;
   }
   int badgeW = Sc(76);
   int badgeH = Sc(24);
   int badgeY = y + (HDR_H - badgeH) / 2;
   int closeW = Sc(24);
   int closeH = badgeH;
   int minW   = closeW;
   int gap    = Sc(5);

   PB("CFG_ST_T", x + W - PAD - closeW - gap - minW - gap - badgeW, badgeY, badgeW, badgeH, stBadge, CLR_BG_DEEP, stBadgeC, Sc(8));
   ObjectSetInteger(0, PFX + "B_CFG_ST_T", OBJPROP_BORDER_COLOR, stBadgeC);
   PB("CFG_MIN",  x + W - PAD - closeW - gap - minW, badgeY, minW, closeH, "_", CLR_PANEL_HOV, CLR_TEXT, Sc(10));
   PB("CFG_X",    x + W - PAD - closeW,              badgeY, closeW, closeH, "X", CLR_RED_DIM, CLR_TEXT, Sc(10));

   int tabsY = y + HDR_H;
   PR("CFG_TBG",    x, tabsY, W, TABS_H,  CLR_BG, CLR_BG, 0);
   PHR("CFG_TBG_LN", x, tabsY + TABS_H - 1, W, CLR_BORDER);

   string tabLabels[3] = {"RANGO", "RIESGO", "SALIDAS"};
   int tw = W / 3;
   for(int i = 0; i < 3; i++)
   {
      bool  act = (i == ConfigTab);
      color tbg = act ? CLR_TAB_ACTIVE : CLR_BG;
      color tcl = act ? CLR_TEXT       : CLR_TEXT_DIM;
      PB("CFG_T" + IntegerToString(i), x + i * tw, tabsY, tw, TABS_H - 2, tabLabels[i], tbg, tcl, Sc(9));
      if(act) PR("CFG_T" + IntegerToString(i) + "_IND", x + i * tw + tw / 3, tabsY + TABS_H - Sc(3), tw / 3, Sc(2), CLR_ACCENT, CLR_ACCENT, 0);
      else    DelObj("R_CFG_T" + IntegerToString(i) + "_IND");
   }

   int by    = tabsY + TABS_H + CFG_BODY_PAD_TOP;
   int bodyW = W - PAD * 2;
   int bodyMaxH = (y + H - FOOTER_H) - by - Sc(8);

   if     (ConfigTab == 0) DibujarBodyRango(x + PAD,  by, bodyW, bodyMaxH);
   else if(ConfigTab == 1) DibujarBodyRiesgo(x + PAD, by, bodyW, bodyMaxH);
   else                    DibujarBodySalidas(x + PAD, by, bodyW, bodyMaxH);

   int fy = y + H - FOOTER_H;
   PHR("CFG_FT_LN", x, fy, W, CLR_BORDER);
   PR("CFG_FT",     x, fy + 1, W, FOOTER_H - 1, CLR_BG_DEEP, CLR_BG_DEEP, 0);

   int btnGap    = Sc(10);
   int btnTotalW = W - PAD * 2;
   int cancelW   = (btnTotalW - btnGap) / 2;
   int applyW    = btnTotalW - cancelW - btnGap;
   int btnH      = Sc(26);
   int btnY      = fy + (FOOTER_H - btnH) / 2;
   PB("CFG_CANCEL", x + PAD,                    btnY, cancelW, btnH, "CANCELAR", CLR_PANEL_HOV, CLR_TEXT, Sc(9));
   PB("CFG_APPLY",  x + PAD + cancelW + btnGap, btnY, applyW,  btnH, "APLICAR",  CLR_ACCENT,    CLR_TEXT, Sc(10));
   ChartRedraw(0);
   ResetCacheEdits();   // sincronizar cache con valores actuales mostrados
}

//+------------------------------------------------------------------+
//| BODY RANGO                                                       |
//+------------------------------------------------------------------+
void DibujarBodyRango(int x, int y, int w, int hAvail)
{
   int colW    = (w - Sc(10)) / 2;
   int rowGap  = CFG_ROW_GAP;
   int dirH    = Sc(24);
   int dirYofs = Sc(46);

   PL("CFG_DIR_L", x, y, "DIRECCION", CLR_TEXT_DIM, Sc(8));
   int  dirBtnW = (w - Sc(8)) / 2;
   bool isLong  = (p_Direccion == GRID_LONG);
   PB("CFG_DIR_LONG",  x,                     y + Sc(16), dirBtnW, dirH, "LONG",  isLong ? CLR_GREEN_DIM  : CLR_PANEL_HOV, CLR_TEXT, Sc(9));
   PB("CFG_DIR_SHORT", x + dirBtnW + Sc(8),   y + Sc(16), dirBtnW, dirH, "SHORT", isLong ? CLR_PANEL_HOV : CLR_RED_DIM,    CLR_TEXT, Sc(9));
   int yStart = y;
   y += dirYofs;

   CfgField("E_TECHO",   x,                 y,            colW, "TECHO",          DoubleToString(p_Techo,   _Digits));
   CfgField("E_PISO",    x + colW + Sc(10), y,            colW, "PISO",           DoubleToString(p_Piso,    _Digits));
   CfgField("E_TRIGGER", x,                 y + rowGap,   w,    "TRIGGER",        DoubleToString(p_Trigger, _Digits));
   CfgField("E_G",       x,                 y + rowGap*2, colW, "G %",            DoubleToString(p_G, 4), "%");
   CfgField("E_VOL",     x + colW + Sc(10), y + rowGap*2, colW, "VOLUMEN",        DoubleToString(p_Vol, 2), "LOT");

   int cardH = CFG_CARD_H_RANGE;
   int cyTop = y + rowGap * 2 + Sc(50);
   int yFinDispo = yStart + hAvail;
   if(cyTop + cardH > yFinDispo) cardH = MathMax(Sc(110), yFinDispo - cyTop);

   PR("CFG_RANGE_CARD", x, cyTop, w, cardH, CLR_BG_DEEP, CLR_BORDER, 1);

   int padIn = Sc(12);
   PL("CFG_RC_HD",  x + padIn, cyTop + Sc(10), "RANGO ACTIVO", CLR_TEXT_FAINT, Sc(8));
   PL("CFG_RC_NUM", x + padIn, cyTop + Sc(28), IntegerToString(ArraySize(GridLevels)) + " niveles", CLR_TEXT, Sc(12));
   PL("CFG_RC_SUB", x + padIn, cyTop + Sc(50), DoubleToString(MathAbs(p_Techo - p_Piso) * 10000, 0) + " pips " +
                                               DoubleToString(p_Piso, _Digits) + " -> " + DoubleToString(p_Techo, _Digits), CLR_TEXT_DIM, Sc(8));

   if(cardH >= Sc(80))
   {
      int axisX = x + padIn, axisY = cyTop + cardH - Sc(34), axisW = w - padIn * 2;
      PHR("CFG_RC_AXIS",    axisX, axisY, axisW, CLR_BORDER);
      PVR("CFG_RC_PISO",    axisX,             axisY - Sc(12), Sc(24), CLR_AMBER);
      PL ("CFG_RC_PISO_L",  axisX + Sc(4),     axisY - Sc(28), "PISO",  CLR_AMBER, Sc(8));
      PVR("CFG_RC_TECHO",   axisX + axisW - 1, axisY - Sc(12), Sc(24), CLR_AMBER);
      PL ("CFG_RC_TECHO_L", axisX + axisW - Sc(38), axisY - Sc(28), "TECHO", CLR_AMBER, Sc(8));

      double rangePct = (p_Trigger - p_Piso) / MathMax(p_Techo - p_Piso, 0.00001);
      int    trgX     = axisX + (int)(axisW * rangePct);
      PVR("CFG_RC_TRG",   trgX,    axisY - Sc(18), Sc(34), CLR_ACCENT);
      PL ("CFG_RC_TRG_L", trgX + Sc(4), axisY - Sc(28), "TRG", CLR_ACCENT, Sc(8));
   }
}

//+------------------------------------------------------------------+
//| BODY RIESGO                                                      |
//+------------------------------------------------------------------+
void DibujarBodyRiesgo(int x, int y, int w, int hAvail)
{
   int colW   = (w - Sc(10)) / 2;
   int rowGap = CFG_ROW_GAP;
   int togH   = Sc(22);
   int togGap = Sc(16);

   CfgField("E_CAP",  x,                 y,          colW, "CAPITAL",     DoubleToString(p_Capital, 2), "USD");
   CfgField("E_RISK", x + colW + Sc(10), y,          colW, "RIESGO",      DoubleToString(p_Risk, 2),    "%");
   CfgField("E_MAXO", x,                 y + rowGap, colW, "MAX ORDENES", IntegerToString(p_MaxOrd));

   PL("CFG_ML_L", x + colW + Sc(10), y + rowGap, "MODO LIBRE", CLR_TEXT_DIM, Sc(8));
   bool freeOff = !p_Libre;
   PB("CFG_ML_OFF", x + colW + Sc(10),               y + rowGap + togGap, colW / 2, togH, "OFF",
      freeOff  ? CLR_PANEL_HOV : CLR_BG_DEEP, freeOff  ? CLR_TEXT : CLR_TEXT_FAINT, Sc(9));
   PB("CFG_ML_ON",  x + colW + Sc(10) + colW/2,      y + rowGap + togGap, colW / 2, togH, "ON",
      !freeOff ? CLR_PANEL_HOV : CLR_BG_DEEP, !freeOff ? CLR_TEXT : CLR_TEXT_FAINT, Sc(9));
   PE("E_LIBRE", x + colW + Sc(10), y + rowGap + togGap, 1, 1, p_Libre ? "true" : "false");
   ObjectSetInteger(0, PFX + "E_E_LIBRE", OBJPROP_HIDDEN, true);

   int cardH = CFG_CARD_H_RISK;
   int cyTop = y + rowGap * 2 + Sc(8);
   int yFinDispo = y + hAvail;
   if(cyTop + cardH > yFinDispo) cardH = MathMax(Sc(140), yFinDispo - cyTop);

   bool  excedido   = (RiesgoRealPct > p_Risk);
   color cardBorder = excedido ? CLR_RED : CLR_GREEN;
   PR("CFG_RSK_CARD", x, cyTop, w, cardH, CLR_BG_DEEP, cardBorder, 1);

   int padIn = Sc(12);
   PR("CFG_RSK_DOT", x + padIn,          cyTop + Sc(15), Sc(7), Sc(7), excedido ? CLR_RED : CLR_GREEN, excedido ? CLR_RED : CLR_GREEN, 0);
   PL("CFG_RSK_HD",  x + padIn + Sc(14), cyTop + Sc(11), excedido ? "RIESGO EXCEDIDO" : "RIESGO OK", excedido ? CLR_RED : CLR_GREEN, Sc(9));

   // Info de rejillas reales vs configuradas
   int totalNiveles = ArraySize(GridLevels);
   bool maxExcedido = (p_MaxOrd > totalNiveles);
   string infoNiv = IntegerToString(totalNiveles) + " niveles / " + IntegerToString(p_MaxOrd) + " max";
   color  infoCol = maxExcedido ? CLR_AMBER : CLR_TEXT_DIM;
   PL("CFG_RSK_NIV", x + padIn, cyTop + Sc(28), infoNiv, infoCol, Sc(8));

   if(excedido)
   {
      double over = (RiesgoRealPct / MathMax(p_Risk, 0.01) - 1.0) * 100.0;
      PR("CFG_RSK_BG", x + w - Sc(72), cyTop + Sc(11), Sc(60), Sc(18), CLR_RED_DIM, CLR_RED_DIM, 0);
      PL("CFG_RSK_BT", x + w - Sc(66), cyTop + Sc(15), "+" + DoubleToString(over, 0) + "%", CLR_RED, Sc(8));
   }
   else if(maxExcedido)
   {
      // Indicador ambar: max ordenes mayor que niveles disponibles
      PR("CFG_RSK_BG", x + w - Sc(72), cyTop + Sc(11), Sc(60), Sc(18), CLR_AMBER_DIM, CLR_AMBER_DIM, 0);
      PL("CFG_RSK_BT", x + w - Sc(66), cyTop + Sc(15), "tope " + IntegerToString(totalNiveles), CLR_AMBER, Sc(8));
   }

   int statW  = (w - padIn*2 - Sc(20)) / 3;
   int statsY = cyTop + Sc(48);
   PL("CFG_RSK_S1L", x + padIn,                      statsY,         "REAL %",                                  CLR_TEXT_FAINT, Sc(8));
   PL("CFG_RSK_S1V", x + padIn,                      statsY + Sc(16), DoubleToString(RiesgoRealPct, 2),          excedido ? CLR_RED : CLR_GREEN, Sc(12));
   PL("CFG_RSK_S2L", x + padIn + statW + Sc(10),     statsY,         "PERDIDA",                                 CLR_TEXT_FAINT, Sc(8));
   PL("CFG_RSK_S2V", x + padIn + statW + Sc(10),     statsY + Sc(16), "$" + DoubleToString(RiesgoRealUSD, 2),    excedido ? CLR_RED : CLR_GREEN, Sc(12));
   PL("CFG_RSK_S3L", x + padIn + (statW+Sc(10))*2,   statsY,         "SEGURO",                                  CLR_TEXT_FAINT, Sc(8));
   PL("CFG_RSK_S3V", x + padIn + (statW+Sc(10))*2,   statsY + Sc(16), IntegerToString(MaxOrdersSafe) + " rej",   CLR_AMBER, Sc(12));

   int barY = cyTop + Sc(104);
   if(barY + Sc(24) <= cyTop + cardH - Sc(8))
   {
      PL("CFG_RSK_BL1", x + padIn,              barY, "0%", CLR_TEXT_FAINT, Sc(7));
      PL("CFG_RSK_BL2", x + (w/2) - Sc(30),     barY, "OBJ " + DoubleToString(p_Risk,1)+"%", CLR_AMBER, Sc(7));
      PL("CFG_RSK_BL3", x + w - padIn - Sc(16), barY, "2x", CLR_TEXT_FAINT, Sc(7));
      PR("CFG_RSK_BAR_BG", x + padIn, barY + Sc(14), w - padIn*2, Sc(6), CLR_BORDER, CLR_BORDER, 0);
      double fillPct = MathMin(RiesgoRealPct / (p_Risk * 2.0), 1.0);
      int    fillW   = (int)((w - padIn*2) * fillPct);
      PR("CFG_RSK_BAR_FL", x + padIn, barY + Sc(14), fillW, Sc(6), excedido ? CLR_RED : CLR_GREEN, excedido ? CLR_RED : CLR_GREEN, 0);
      PVR("CFG_RSK_BAR_MK", x + padIn + (w - padIn*2) / 2, barY + Sc(11), Sc(12), CLR_AMBER);
   }
}

//+------------------------------------------------------------------+
//| BODY SALIDAS                                                     |
//+------------------------------------------------------------------+
void DibujarBodySalidas(int x, int y, int w, int hAvail)
{
   int colW = (w - Sc(10)) / 2;
   CfgField("E_TP", x,                 y, colW, "TAKE PROFIT", DoubleToString(p_TP, _Digits));
   CfgField("E_SL", x + colW + Sc(10), y, colW, "STOP LOSS",   DoubleToString(p_SL, _Digits));

   int cyTop = y + Sc(60);
   int cardH = CFG_CARD_H_EXIT;
   int yFinDispo = y + hAvail;
   if(cyTop + cardH > yFinDispo) cardH = MathMax(Sc(180), yFinDispo - cyTop);

   PR("CFG_EXT_CARD", x, cyTop, w, cardH, CLR_BG_DEEP, CLR_BORDER, 1);

   int padIn = Sc(12);
   PL("CFG_EXT_HD", x + padIn, cyTop + Sc(10), "DISTANCIAS DESDE TRIGGER", CLR_TEXT_FAINT, Sc(8));

   double dist_tp = MathAbs(p_TP      - p_Trigger);
   double dist_sl = MathAbs(p_Trigger - p_SL);
   double maxD    = MathMax(dist_tp, dist_sl);
   int    barX    = x + Sc(40);
   int    barW    = w - Sc(56);
   int    rowH    = Sc(28);
   int    sepH    = Sc(20);

   int rowY = cyTop + Sc(32);
   int sepY = rowY + rowH + Sc(8);
   int slY  = sepY + sepH;

   int tpBarW  = (int)(barW * (dist_tp / MathMax(maxD, 0.0001)));
   PL("CFG_EXT_TPL",  x + padIn,            rowY + (rowH-Sc(14))/2, "TP", CLR_GREEN, Sc(9));
   PR("CFG_EXT_TPBG", barX,                 rowY, barW, rowH, CLR_BG, CLR_BORDER, 1);
   PR("CFG_EXT_TPLN", barX,                 rowY, Sc(3), rowH, CLR_GREEN, CLR_GREEN, 0);
   PR("CFG_EXT_TPFL", barX + Sc(3),         rowY + 1, tpBarW - Sc(3), rowH - 2, C'18,55,38', C'18,55,38', 0);
   PL("CFG_EXT_TPV",  barX + Sc(10),        rowY + (rowH-Sc(14))/2, "+" + DoubleToString(dist_tp * 10000, 1) + " pips", CLR_GREEN, Sc(10));
   PL("CFG_EXT_TPP",  barX + barW - Sc(60), rowY + (rowH-Sc(14))/2, "+" + DoubleToString(dist_tp / p_Trigger * 100, 2) + "%", CLR_GREEN, Sc(9));

   PL ("CFG_EXT_TGL",  x + padIn,            sepY + Sc(4),       "TRG", CLR_ACCENT, Sc(9));
   PHR("CFG_EXT_TGLN", barX,                 sepY + sepH/2,      barW,  CLR_ACCENT);
   PL ("CFG_EXT_TGV",  barX + barW - Sc(60), sepY + Sc(3),       DoubleToString(p_Trigger, _Digits), CLR_ACCENT, Sc(9));

   int slBarW = (int)(barW * (dist_sl / MathMax(maxD, 0.0001)));
   PL("CFG_EXT_SLL",  x + padIn,            slY + (rowH-Sc(14))/2, "SL", CLR_RED, Sc(9));
   PR("CFG_EXT_SLBG", barX,                 slY, barW, rowH, CLR_BG, CLR_BORDER, 1);
   PR("CFG_EXT_SLLN", barX,                 slY, Sc(3), rowH, CLR_RED, CLR_RED, 0);
   PR("CFG_EXT_SLFL", barX + Sc(3),         slY + 1, slBarW - Sc(3), rowH - 2, C'60,22,22', C'60,22,22', 0);
   PL("CFG_EXT_SLV",  barX + Sc(10),        slY + (rowH-Sc(14))/2, "-" + DoubleToString(dist_sl * 10000, 1) + " pips", CLR_RED, Sc(10));
   PL("CFG_EXT_SLP",  barX + barW - Sc(60), slY + (rowH-Sc(14))/2, "-" + DoubleToString(dist_sl / p_Trigger * 100, 2) + "%", CLR_RED, Sc(9));

   double rr      = dist_tp / MathMax(dist_sl, 0.00001);
   bool   rrGood  = (rr >= 1.5);
   color  rrColor = rrGood ? CLR_GREEN : (rr >= 1.0 ? CLR_AMBER : CLR_RED);

   int rrY = slY + rowH + Sc(10);
   int rrH = Sc(56);
   if(rrY + rrH <= cyTop + cardH - Sc(6))
   {
      PR("CFG_EXT_RR_BG", x + padIn,         rrY,                w - padIn*2, rrH, CLR_BG, rrColor, 1);
      PL("CFG_EXT_RR_L",  x + padIn + Sc(14), rrY + Sc(10),      "RISK / REWARD",                CLR_TEXT_FAINT, Sc(8));
      PL("CFG_EXT_RR_V",  x + padIn + Sc(14), rrY + Sc(28),      "1 : " + DoubleToString(rr, 2), rrColor, Sc(13));

      string rrLabel = rrGood ? "OPTIMO" : (rr >= 1.0 ? "ACEPT." : "SUBOP.");
      int    badgeW  = Sc(86);
      int    badgeH  = Sc(26);
      int    badgeX  = x + w - padIn - Sc(14) - badgeW;
      int    badgeY  = rrY + (rrH - badgeH) / 2;
      PB("CFG_EXT_RR_PT", badgeX, badgeY, badgeW, badgeH, rrLabel, rrColor, CLR_TEXT, Sc(9));
   }
}

//+------------------------------------------------------------------+
//| APLICAR CONFIG                                                   |
//+------------------------------------------------------------------+
void CalcularRejillas();

//+------------------------------------------------------------------+
//| AUTO-APPLY (silencioso) — se ejecuta al salir de un campo OBJ_EDIT
//+------------------------------------------------------------------+
void AplicarConfiguracionAuto()
{
   // Forzar redraw para que MT5 actualice OBJPROP_TEXT de todos los EDITs
   ChartRedraw(0);

   // Leer TODOS los campos de TODAS las pestañas (los inactivos pueden no existir)
   if(ObjectFind(0, PFX + "E_CFG_E_TECHO") >= 0)
   {
      double v_techo   = StringToDouble(GetEdit("CFG_E_TECHO"));
      double v_piso    = StringToDouble(GetEdit("CFG_E_PISO"));
      double v_trigger = StringToDouble(GetEdit("CFG_E_TRIGGER"));
      double v_g       = StringToDouble(GetEdit("CFG_E_G"));
      double v_vol     = StringToDouble(GetEdit("CFG_E_VOL"));
      if(v_techo > v_piso && v_trigger >= v_piso && v_trigger <= v_techo && v_g > 0 && v_vol > 0)
      {
         p_Techo = v_techo; p_Piso = v_piso; p_Trigger = v_trigger; p_G = v_g; p_Vol = v_vol;
      }
   }
   if(ObjectFind(0, PFX + "E_CFG_E_CAP") >= 0)
   {
      double v_cap  = StringToDouble(GetEdit("CFG_E_CAP"));
      double v_risk = StringToDouble(GetEdit("CFG_E_RISK"));
      int    v_maxo = (int)StringToInteger(GetEdit("CFG_E_MAXO"));
      if(v_cap > 0 && v_risk > 0 && v_risk <= 100 && v_maxo > 0)
      {
         p_Capital = v_cap; p_Risk = v_risk; p_MaxOrd = v_maxo;
      }
   }
   if(ObjectFind(0, PFX + "E_CFG_E_TP") >= 0)
   {
      double v_tp = StringToDouble(GetEdit("CFG_E_TP"));
      double v_sl = StringToDouble(GetEdit("CFG_E_SL"));
      bool tpSlOk = (p_Direccion == GRID_LONG)
                    ? (v_tp > p_Trigger && v_sl < p_Trigger)
                    : (v_tp < p_Trigger && v_sl > p_Trigger);
      if(tpSlOk) { p_TP = v_tp; p_SL = v_sl; }
   }

   // Recalcular TODO siempre
   CalcularRejillas();
   CalcularRiesgo();
   DibujarLineasGrid();
   DibujarPanel();
   // CRITICAL: NO redibujar dialog completo (rompe edicion). Solo visuales del body.
   RedibujarSoloVisualesBody();
}

void AplicarConfiguracion()
{
   bool aplicado = false;

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
         aplicado = true;
         Print("Config Rango aplicada OK");
      }
      else
      {
         Print("ERROR: Valores de rango invalidos");
         MostrarAlerta("DATOS INVALIDOS",
            "Los valores de rango ingresados no son validos.",
            "Verifica que Techo > Piso, Trigger entre Piso y Techo, G% > 0 y Volumen > 0.",
            ALERT_ERROR);
      }
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
         aplicado = true;
         Print("Config Riesgo aplicada OK");
      }
      else
      {
         Print("ERROR: Valores de riesgo invalidos");
         MostrarAlerta("DATOS INVALIDOS",
            "Los valores de riesgo ingresados no son validos.",
            "Capital > 0, Riesgo entre 0 y 100, Max Ordenes > 0.",
            ALERT_ERROR);
      }
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
         aplicado = true;
         Print("Config Salidas aplicada OK");
      }
      else
      {
         Print("ERROR: TP/SL no respetan la direccion");
         string msg = (p_Direccion == GRID_LONG)
            ? "Para LONG: TP debe ser MAYOR que Trigger y SL debe ser MENOR que Trigger."
            : "Para SHORT: TP debe ser MENOR que Trigger y SL debe ser MAYOR que Trigger.";
         MostrarAlerta("DATOS INVALIDOS",
            "TP/SL no respetan la direccion del grid.",
            msg,
            ALERT_ERROR);
      }
   }

   // Si se aplicaron valores validos, recalcular TODO siempre
   if(aplicado)
   {
      CalcularRejillas();
      CalcularRiesgo();
      DibujarLineasGrid();
      DibujarPanel();
      // Sincronizar valores de los OBJ_EDIT con los p_* aplicados (en caso de que difieran)
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
      // Refrescar la cache para evitar que el timer detecte falsos cambios
      ResetCacheEdits();
      // Solo redibujar visuales del body, sin tocar OBJ_EDIT
      RedibujarSoloVisualesBody();
      PrintFormat("APPLY MANUAL: Rej=%d Real=%.2f%% ($%.2f) Seguro=%d",
                  ArraySize(GridLevels), RiesgoRealPct, RiesgoRealUSD, MaxOrdersSafe);
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
      { int n = ArraySize(GridLevels); ArrayResize(GridLevels, n + 1); GridLevels[n] = NormalizeDouble(nivel, _Digits); nivel = nivel / (1.0 + p_G); }
   }
   else
   {
      while(nivel <= p_Techo)
      { int n = ArraySize(GridLevels); ArrayResize(GridLevels, n + 1); GridLevels[n] = NormalizeDouble(nivel, _Digits); nivel = nivel * (1.0 + p_G); }
   }
   PrintFormat("Rejillas (%s): %d", p_Direccion == GRID_LONG ? "LONG" : "SHORT", ArraySize(GridLevels));
}

bool ValidarInputs()
{
   if(Magic_Number == 0)                         { Print("ERROR: Magic=0");       return false; }
   if(p_Piso >= p_Techo)                         { Print("ERROR: Piso>=Techo");   return false; }
   if(p_G <= 0)                                  { Print("ERROR: G%<=0");         return false; }
   if(p_Vol <= 0)                                { Print("ERROR: Volumen<=0");    return false; }
   if(p_Trigger < p_Piso || p_Trigger > p_Techo) { Print("ERROR: Trigger fuera"); return false; }
   if(p_Capital <= 0)                            { Print("ERROR: Capital<=0");    return false; }
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
      if(OrderGetInteger(ORDER_MAGIC)  != Magic_Number) continue;
      if(OrderGetString(ORDER_SYMBOL)  != _Symbol)      continue;
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
      if(PositionGetInteger(POSITION_MAGIC) == Magic_Number && PositionGetString(POSITION_SYMBOL) == _Symbol) c++;
   }
   return c;
}

void ActivarGrid()
{
   trade.SetExpertMagicNumber(Magic_Number);
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
      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)      continue;
      if(!trade.PositionClose(t)) PrintFormat("FALLO cerrar %I64u rc=%u", t, trade.ResultRetcode());
   }
}

void CancelarPendientes()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i); if(t == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != Magic_Number) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)      continue;
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
   trade.SetExpertMagicNumber(Magic_Number);
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
   trade.SetExpertMagicNumber(Magic_Number);
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
      if(ticket <= UltimoDealProcesado)                              continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  != Magic_Number) continue;
      if(HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol)      continue;

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
      if(OrderGetInteger(ORDER_MAGIC) == Magic_Number && OrderGetString(ORDER_SYMBOL) == _Symbol) c++;
   }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i); if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == Magic_Number && PositionGetString(POSITION_SYMBOL) == _Symbol) c++;
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
      if(HistoryDealGetInteger(t, DEAL_MAGIC)  != Magic_Number) continue;
      if(HistoryDealGetString(t,  DEAL_SYMBOL) != _Symbol)      continue;
      if(t > UltimoDealProcesado) UltimoDealProcesado = t;
   }
}

//+------------------------------------------------------------------+
//| OnChartEvent                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   // ENDEDIT — el usuario terminó de editar un campo (Enter/Tab/click afuera)
   // Auto-apply en tiempo real
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      // Solo procesar campos del config dialog
      if(StringFind(sparam, PFX + "E_CFG_") != 0) return;
      AplicarConfiguracionAuto();
      return;
   }

   // CHART_CHANGE solo redibuja si el chart cambio de tamaño (anti-parpadeo)
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      if(cw != LastChartW || ch != LastChartH)
      {
         LastChartW = cw; LastChartH = ch;
         DibujarPanel();
         if(ConfigVisible) DibujarConfigDialog();
         if(AlertaVisible) DibujarAlerta();
      }
      return;
   }

   // MOUSE_MOVE para drag de paneles
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int  mx = (int)lparam;
      int  my = (int)dparam;
      bool md = ((int)StringToInteger(sparam) & 1) != 0;

      // Dimensiones panel principal
      int pW = Sc(180);
      int pHDR = Sc(30);

      // Dimensiones header config dialog
      int cHDR_y = ConfigPosY;
      int cHDR_h = CFG_HDR_H;

      // Iniciar drag PANEL principal — solo si click en su header
      if(md && !DragPanel && !DragConfig &&
         mx >= PanelPosX && mx <= PanelPosX + pW &&
         my >= PanelPosY && my <= PanelPosY + pHDR)
      {
         DragPanel = true;
         DragOffX = mx - PanelPosX;
         DragOffY = my - PanelPosY;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
      }

      // Iniciar drag CONFIG — solo si click en su header (y no minimizado)
      if(md && !DragConfig && !DragPanel && ConfigVisible && !ConfigMinimized &&
         mx >= ConfigPosX && mx <= ConfigPosX + CfgW &&
         my >= ConfigPosY && my <= ConfigPosY + cHDR_h)
      {
         DragConfig = true;
         DragOffX = mx - ConfigPosX;
         DragOffY = my - ConfigPosY;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
      }

      // Procesar drag activo
      if(md && DragPanel)
      {
         PanelPosX = mx - DragOffX;
         PanelPosY = my - DragOffY;
         int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
         int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
         if(PanelPosX < 0) PanelPosX = 0;
         if(PanelPosY < 0) PanelPosY = 0;
         if(PanelPosX > cw - pW) PanelPosX = cw - pW;
         if(PanelPosY > ch - pHDR) PanelPosY = ch - pHDR;
         DibujarPanel();
      }
      else if(md && DragConfig)
      {
         ConfigPosX = mx - DragOffX;
         ConfigPosY = my - DragOffY;
         int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
         int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
         if(ConfigPosX < 0) ConfigPosX = 0;
         if(ConfigPosY < 0) ConfigPosY = 0;
         if(ConfigPosX > cw - CfgW) ConfigPosX = cw - CfgW;
         if(ConfigPosY > ch - CfgH) ConfigPosY = ch - CfgH;
         DibujarConfigDialog();
      }

      // Soltar — restaurar scroll del chart
      if(!md && (DragPanel || DragConfig))
      {
         DragPanel = false;
         DragConfig = false;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
      }
      return;
   }

   if(id != CHARTEVENT_OBJECT_CLICK) return;

   // Toggle minimizar PANEL principal
   if(sparam == PFX + "B_MINBTN")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      PanelMinimized = !PanelMinimized;
      DibujarPanel();
      return;
   }

   // CONFIG abrir/cerrar
   if(sparam == PFX + "B_CFGBTN")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ConfigVisible = !ConfigVisible;
      ConfigMinimized = false;
      if(!ConfigVisible) BorrarConfigDialog();
      else DibujarConfigDialog();
      return;
   }
   if(sparam == PFX + "B_CFG_X")
      { ObjectSetInteger(0, sparam, OBJPROP_STATE, false); ConfigVisible = false; ConfigMinimized = false; BorrarConfigDialog(); return; }
   if(sparam == PFX + "B_CFG_MIN")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ConfigMinimized = !ConfigMinimized;
      BorrarConfigDialog();
      DibujarConfigDialog();
      return;
   }
   if(sparam == PFX + "B_CFG_CANCEL")
      { ObjectSetInteger(0, sparam, OBJPROP_STATE, false); ConfigVisible = false; BorrarConfigDialog(); return; }

   if(sparam == PFX + "B_ALR_X" || sparam == PFX + "B_ALR_OK")
      { ObjectSetInteger(0, sparam, OBJPROP_STATE, false); AlertaVisible = false; BorrarAlerta(); return; }

   for(int t = 0; t < 3; t++)
      if(sparam == PFX + "B_CFG_T" + IntegerToString(t))
         { ObjectSetInteger(0, sparam, OBJPROP_STATE, false); ConfigTab = t; BorrarConfigDialog(); DibujarConfigDialog(); return; }

   if(sparam == PFX + "B_CFG_DIR_LONG")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      p_Direccion = GRID_LONG;
      CalcularRejillas(); CalcularRiesgo();
      BorrarConfigDialog(); DibujarConfigDialog();
      DibujarLineasGrid(); DibujarPanel();
      return;
   }
   if(sparam == PFX + "B_CFG_DIR_SHORT")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      p_Direccion = GRID_SHORT;
      CalcularRejillas(); CalcularRiesgo();
      BorrarConfigDialog(); DibujarConfigDialog();
      DibujarLineasGrid(); DibujarPanel();
      return;
   }
   if(sparam == PFX + "B_CFG_ML_OFF")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      p_Libre = false;
      ObjectSetString(0, PFX + "E_E_LIBRE", OBJPROP_TEXT, "false");
      BorrarConfigDialog(); DibujarConfigDialog();
      return;
   }
   if(sparam == PFX + "B_CFG_ML_ON")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      p_Libre = true;
      ObjectSetString(0, PFX + "E_E_LIBRE", OBJPROP_TEXT, "true");
      BorrarConfigDialog(); DibujarConfigDialog();
      return;
   }
   if(sparam == PFX + "B_CFG_APPLY")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ChartRedraw(0);  // forzar actualizacion de OBJ_EDIT antes de leer
      AplicarConfiguracion();
      return;
   }

   // INICIAR
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
      else        {                       estado = PENDING; Print("PENDING — esperando trigger"); }
      DibujarLineasGrid(); DibujarPanel();
      return;
   }
   if(sparam == PFX + "B_PAUSE")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      if     (estado == ACTIVE) { estado = PAUSED; Print("PAUSED"); }
      else if(estado == PAUSED) { estado = ACTIVE; Print("ACTIVE"); }
      DibujarPanel();
      return;
   }
   if(sparam == PFX + "B_STOP")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      CancelarPendientes(); CerrarTodo();
      estado = STOPPED; RejillasActivas = 0;
      DibujarLineasGrid(); DibujarPanel();
      return;
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
      return;
   }
}

//+------------------------------------------------------------------+
//| OnInit / OnTick / OnDeinit / OnTradeTransaction                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| OnTimer — verifica los OBJ_EDIT cada 200ms y aplica si cambian   |
//+------------------------------------------------------------------+
// Debounce: cuando el usuario edita, esperamos 400ms sin cambios antes de aplicar
ulong   LastEditTick     = 0;
bool    PendingRecalc    = false;

void OnTimer()
{
   if(!ConfigVisible || ConfigMinimized) return;

   bool changed = false;
   string cur;

   // ---- DETECTAR cambios en cualquier campo y leerlos ----
   if(ObjectFind(0, PFX + "E_CFG_E_TECHO") >= 0)
   {
      cur = GetEdit("CFG_E_TECHO");
      if(cur != PrevTecho)
      {
         PrevTecho = cur;
         double v = StringToDouble(cur);
         if(v > 0) p_Techo = v;
         changed = true;
      }
      cur = GetEdit("CFG_E_PISO");
      if(cur != PrevPiso)
      {
         PrevPiso = cur;
         double v = StringToDouble(cur);
         if(v > 0) p_Piso = v;
         changed = true;
      }
      cur = GetEdit("CFG_E_TRIGGER");
      if(cur != PrevTrigger)
      {
         PrevTrigger = cur;
         double v = StringToDouble(cur);
         if(v > 0) p_Trigger = v;
         changed = true;
      }
      cur = GetEdit("CFG_E_G");
      if(cur != PrevG)
      {
         PrevG = cur;
         double v = StringToDouble(cur);
         if(v > 0) p_G = v;
         changed = true;
      }
      cur = GetEdit("CFG_E_VOL");
      if(cur != PrevVol)
      {
         PrevVol = cur;
         double v = StringToDouble(cur);
         if(v > 0) p_Vol = v;
         changed = true;
      }
   }

   if(ObjectFind(0, PFX + "E_CFG_E_CAP") >= 0)
   {
      cur = GetEdit("CFG_E_CAP");
      if(cur != PrevCap)
      {
         PrevCap = cur;
         double v = StringToDouble(cur);
         if(v > 0) p_Capital = v;
         changed = true;
      }
      cur = GetEdit("CFG_E_RISK");
      if(cur != PrevRisk)
      {
         PrevRisk = cur;
         double v = StringToDouble(cur);
         if(v > 0 && v <= 100) p_Risk = v;
         changed = true;
      }
      cur = GetEdit("CFG_E_MAXO");
      if(cur != PrevMaxo)
      {
         PrevMaxo = cur;
         int v = (int)StringToInteger(cur);
         if(v > 0) p_MaxOrd = v;
         changed = true;
      }
   }

   if(ObjectFind(0, PFX + "E_CFG_E_TP") >= 0)
   {
      cur = GetEdit("CFG_E_TP");
      if(cur != PrevTP)
      {
         PrevTP = cur;
         double v = StringToDouble(cur);
         if(v > 0) p_TP = v;
         changed = true;
      }
      cur = GetEdit("CFG_E_SL");
      if(cur != PrevSL)
      {
         PrevSL = cur;
         double v = StringToDouble(cur);
         if(v > 0) p_SL = v;
         changed = true;
      }
   }

   // Si hubo cambio, marcar pendiente y reiniciar timer
   if(changed)
   {
      LastEditTick = GetTickCount();
      PendingRecalc = true;
   }

   // Aplicar despues de 400ms sin cambios (debounce)
   if(PendingRecalc && (GetTickCount() - LastEditTick) > 400)
   {
      PendingRecalc = false;
      // Recalcular con los nuevos valores
      CalcularRejillas();
      CalcularRiesgo();
      DibujarLineasGrid();
      DibujarPanel();
      // CRITICAL: solo redibujar elementos visuales (NO los OBJ_EDIT)
      RedibujarSoloVisualesBody();
      PrintFormat("AUTO-APPLY: Rej=%d Real=%.2f%% ($%.2f) Seguro=%d",
                  ArraySize(GridLevels), RiesgoRealPct, RiesgoRealUSD, MaxOrdersSafe);
   }
}

//+------------------------------------------------------------------+
//| Borrar y redibujar SOLO los elementos visuales del body actual   |
//| MANTIENE los OBJ_EDIT (E_*) intactos para no romper la edicion   |
//+------------------------------------------------------------------+
void RedibujarSoloVisualesBody()
{
   // Borrar elementos visuales del body (cards, labels, badges, dots)
   // pero NO los OBJ_EDIT
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, PFX) != 0) continue;
      // Mantener OBJ_EDIT intactos
      if(StringFind(n, PFX + "E_") == 0) continue;
      // Solo borrar elementos del body (cards de range, riesgo, salidas)
      if(StringFind(n, PFX + "R_CFG_RANGE_") == 0 ||
         StringFind(n, PFX + "L_CFG_RC_") == 0    ||
         StringFind(n, PFX + "R_CFG_RSK_") == 0   ||
         StringFind(n, PFX + "L_CFG_RSK_") == 0   ||
         StringFind(n, PFX + "R_CFG_EXT_") == 0   ||
         StringFind(n, PFX + "L_CFG_EXT_") == 0   ||
         StringFind(n, PFX + "B_CFG_EXT_") == 0   ||
         // suffix boxes y direccion buttons
         StringFind(n, PFX + "L_CFG_E_") == 0     ||
         StringFind(n, PFX + "R_CFG_E_") == 0     ||
         StringFind(n, PFX + "B_CFG_DIR_") == 0   ||
         StringFind(n, PFX + "B_CFG_ML_") == 0    ||
         StringFind(n, PFX + "L_CFG_DIR_") == 0   ||
         StringFind(n, PFX + "L_CFG_ML_") == 0)
      {
         ObjectDelete(0, n);
      }
   }

   // Redibujar el body de la pestaña actual (sin tocar OBJ_EDIT que se mantienen)
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int by    = ConfigPosY + CFG_HDR_H + CFG_TABS_H + CFG_BODY_PAD_TOP;
   int bodyW = CfgW - CFG_PAD * 2;
   int bodyMaxH = (ConfigPosY + CfgH - CFG_FOOT_H) - by - Sc(8);

   if     (ConfigTab == 0) DibujarBodyRango(ConfigPosX + CFG_PAD,  by, bodyW, bodyMaxH);
   else if(ConfigTab == 1) DibujarBodyRiesgo(ConfigPosX + CFG_PAD, by, bodyW, bodyMaxH);
   else                    DibujarBodySalidas(ConfigPosX + CFG_PAD, by, bodyW, bodyMaxH);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Reset cache cuando se redibuja el dialog                         |
//+------------------------------------------------------------------+
void ResetCacheEdits()
{
   PrevTecho = DoubleToString(p_Techo, _Digits);
   PrevPiso  = DoubleToString(p_Piso, _Digits);
   PrevTrigger = DoubleToString(p_Trigger, _Digits);
   PrevG = DoubleToString(p_G, 4);
   PrevVol = DoubleToString(p_Vol, 2);
   PrevCap  = DoubleToString(p_Capital, 2);
   PrevRisk = DoubleToString(p_Risk, 2);
   PrevMaxo = IntegerToString(p_MaxOrd);
   PrevTP = DoubleToString(p_TP, _Digits);
   PrevSL = DoubleToString(p_SL, _Digits);
}

int OnInit()
{
   Print("================================================");
   Print("GridBot v3.4.3 | Responsive + Persistente | ", _Symbol);
   Print("================================================");

   // Primero cargar parametros desde inputs (defaults)
   CargarParametros();

   // Intentar restaurar estado guardado de la sesion anterior (mismo simbolo+magic)
   bool restaurado = CargarEstado();
   if(restaurado)
   {
      PrintFormat(">>> Estado restaurado: %s | Tech=%s Piso=%s Trig=%s",
                  estado==ACTIVE?"ACTIVE":estado==PENDING?"PENDING":estado==PAUSED?"PAUSED":estado==STOPPED?"STOPPED":"PRECHECK",
                  DoubleToString(p_Techo,_Digits),
                  DoubleToString(p_Piso,_Digits),
                  DoubleToString(p_Trigger,_Digits));
   }
   else
   {
      Print(">>> Estado nuevo desde inputs");
      estado = PRECHECK;
   }

   if(!ValidarInputs()) return INIT_PARAMETERS_INCORRECT;

   CalcularRejillas(); CalcularRiesgo();
   trade.SetExpertMagicNumber(Magic_Number);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(10);
   InicializarCursorDeals();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   LastChartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   LastChartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   EventSetMillisecondTimer(200);

   // Si se restauro un estado activo, verificar que las ordenes existan en el broker
   if(restaurado && (estado == ACTIVE || estado == PAUSED || estado == PENDING))
   {
      int existentes = EscanearOrdenesExistentes();
      if(existentes > 0)
      {
         RejillasActivas = existentes;
         PrintFormat(">>> Retomando con %d ordenes existentes en el broker", existentes);
      }
      else if(estado == ACTIVE || estado == PAUSED)
      {
         // No hay ordenes — el bot pensaba que estaba activo pero no hay nada
         Print(">>> No se encontraron ordenes — volviendo a PRECHECK");
         estado = PRECHECK;
      }
   }

   PrintFormat("Risk: Real=%.1f%% ($%.2f) | Seguro=%d rejillas", RiesgoRealPct, RiesgoRealUSD, MaxOrdersSafe);
   DibujarLineasGrid(); DibujarPanel();
   Print(">>> Panel a la izquierda | CONFIG arriba derecha | persistencia por symbol+magic");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(estado == PRECHECK || estado == STOPPED) return;
   if(CheckKillSwitch()) return;
   if(estado == PENDING) CheckTrigger();
   else { CheckRange(); ProcesarDeals(); }
   DibujarPanel();
}

void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) ProcesarDeals();
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
   ChartSetInteger(0, CHART_MOUSE_SCROLL, true);

   // Guardar estado SOLO en casos donde el bot va a volver a iniciar
   // REASON_CHARTCHANGE = cambio de timeframe/simbolo
   // REASON_PARAMETERS = cambio de inputs
   // REASON_RECOMPILE  = recompilacion del codigo
   // REASON_TEMPLATE   = aplicar template
   // REASON_ACCOUNT    = cambio de cuenta
   // En estos casos guardamos el estado para restaurar
   if(reason == REASON_CHARTCHANGE ||
      reason == REASON_PARAMETERS  ||
      reason == REASON_RECOMPILE   ||
      reason == REASON_TEMPLATE    ||
      reason == REASON_ACCOUNT)
   {
      GuardarEstado();
      Print(">>> Estado guardado (motivo: ", reason, ") - se restaurara automaticamente");
   }
   else
   {
      // REASON_REMOVE / REASON_CLOSE / REASON_PROGRAM = quitar bot del chart definitivamente
      BorrarEstadoGuardado();
      Print(">>> Estado borrado (motivo: ", reason, ") - bot eliminado");
   }

   BorrarTodo();
   PrintFormat("GridBot v3.4.3 fin. Estado=%d | Acumulado=%.2f USD", estado, GananciaAcumulada);
}
//+------------------------------------------------------------------+
