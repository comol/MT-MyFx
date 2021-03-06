//+------------------------------------------------------------------+
//|                                                    MyFxTrade.mq5 |
//|                        Copyright 2018, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2018, Oleg Filippov & Petr Gordeev"
#property version     "1.00"
#property description "This Expert Advisor uing external statistics of opened positions"
#property description "internet connection is necessary for this Expert. Optimized for XAUUSD"


#property link      "https://www.mql5.com"
#property version   "1.00"

#property icon "icon_60_60.ico"

#resource "history.csv" as string ExtCode

input int Lots = 1;


#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>
//Библиотека для работы с json
#include <jason.mqh>
#include <Arrays\List.mqh>  

CTrade trade;
int EmptyCounter;
int MagicNumber=192168;
bool testing;
CPositionInfo myposition;

class CTradeLine: CObject
{
   public: 
   datetime ChangeDate;
   string PosType;
}; 

CList* testlist = new CList();
 

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+



int OnInit()
  {
  
  if (MQLInfoInteger(MQL_TESTER) == true)
  {
     testing = true;
     ResourceToList(ExtCode, testlist);    
  }
  
  trade.SetExpertMagicNumber(MagicNumber);
  EmptyCounter = 0;  

  if (testing == false)
  {
   if (GetMyFxData() == "Err")
      {
         Alert("Server connection falue. Please add http://178.238.227.195/cgi-bin/XAUUSD to Whitelist in Metatrader settings");
         return(INIT_FAILED);
      }
   }

   EventSetTimer(60);
   
    
   //--- установим допустимое проскальзывание в пунктах при совершении покупки/продажи
   int deviation=10;
   trade.SetDeviationInPoints(deviation);
   //--- режим заполнения ордера, нужно использовать тот режим, который разрешается сервером
   trade.SetTypeFilling(ORDER_FILLING_RETURN);
   //--- какую функцию использовать для торговли: true - OrderSendAsync(), false - OrderSend()
   trade.SetAsyncMode(true);
   //---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- destroy timer
   EventKillTimer();
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   
  }

// Ищем и вычисляем всё безобразие по массиву
string GetMyFxDataTesting()
{
   datetime curtime = TimeTradeServer();
   CTradeLine *currline = testlist.GetFirstNode();
   
   while (!currline == NULL)
   {
      if (currline.ChangeDate > curtime) //Как только добрались до точки когда дата больше текущей
      {
         return currline.PosType;
      }
      else
      {
         currline = testlist.GetNextNode();
      }
   }

    //будет получено по серверу
   return "Long";
}
  
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   
   //--- количество знаков после запятой
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   //--- значение пункта
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   //--- получим цену покупки
   double price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   //--- заполним комментарий
   
   string myfxaction;
   
   if (testing)
   {
      myfxaction = GetMyFxDataTesting();
   }
   else
   {
      myfxaction = GetMyFxData();
   }
   
   
   if (myfxaction == "Err")
   {
      EmptyCounter++;
      if (EmptyCounter > 100) // Более  100 ошибок - закрываем всё нафиг 
      {
         for(int i=0;i<PositionsTotal();i++) 
         {
            if(PositionGetSymbol(i)==_Symbol)
               {
                  double Volum=PositionGetDouble(POSITION_VOLUME);
                  if (Volum > 0)
                  {               
                     long type=PositionGetInteger(POSITION_TYPE);
                     long ticket=PositionGetInteger(POSITION_TICKET);
                     trade.PositionClose(ticket);                     
                  }
               }
           }
         EmptyCounter = 0;
      }      
      return;
   }
   
   
   if (myfxaction == "Empty")
   {
      return;
   }
   
   EmptyCounter = 0;

   // Закрываем все "неправильные" позиции
   for(int i=0;i<PositionsTotal();i++) 
    {
      if(PositionGetSymbol(i)==_Symbol)
         {
            double Volum=PositionGetDouble(POSITION_VOLUME);
            if (Volum > 0)
            {
               
               long type=PositionGetInteger(POSITION_TYPE);
               long ticket=PositionGetInteger(POSITION_TICKET);
               
               if (type == (long)POSITION_TYPE_BUY && myfxaction == "Short" && MagicNumber == PositionGetInteger(POSITION_MAGIC))
               { 
                  trade.PositionClose(ticket);
               }
               
               else if (type == (long)POSITION_TYPE_SELL && myfxaction == "Long" && MagicNumber == PositionGetInteger(POSITION_MAGIC))
               {
                  trade.PositionClose(ticket);
               }
               
               else if (myfxaction == "Close" && MagicNumber == PositionGetInteger(POSITION_MAGIC))
               {
                  trade.PositionClose(ticket);  
               } 
               
            }
         }
   }
   
   // проверяем что нет открытых позиций. Если есть - не открываем новых
    int poscout = 0;

    for(int i=0;i<PositionsTotal();i++) 
    {
      if(PositionGetSymbol(i)==_Symbol)
         {
            double Volum=PositionGetDouble(POSITION_VOLUME);
            if (Volum > 0)
            {
               poscout++;
            }
        }
    }
    
     
    if (poscout == 0) 
      {
         if (myfxaction == "Long")
         {
            string comment="Buy "+_Symbol+ IntegerToString(Lots) + " at "+DoubleToString(price,digits);
            if (CheckMoneyForTrade(_Symbol, Lots, ORDER_TYPE_BUY) == true)
            {
               if (CheckVolumeValue(Lots) == true)
               {
                  if (IsNewOrderAllowed() == true)
                  {
                     if (NewOrderAllowedVolume(_Symbol) < Lots)
                     {                     
                        trade.Buy(Lots);
                     }
                     else 
                     {
                        Print("Position volume is more then allowed"); 
                     }
                  }
               }
            }
         }
         else
         {
            string comment="Sell "+_Symbol+ IntegerToString(Lots) + " at "+DoubleToString(price,digits);
            if (CheckMoneyForTrade(_Symbol, Lots, ORDER_TYPE_SELL) == true)
            {
               if (CheckVolumeValue(Lots) == true)
               {
                  if (IsNewOrderAllowed() == true)
                  {
                     if (NewOrderAllowedVolume(_Symbol) < Lots)
                     {                     
                        trade.Sell(Lots);
                     }
                     else 
                     {
                        Print("Position volume is more then allowed");
                     }
                  }
               }
            }
         }
      }
      
  }
 
 // Функция получает данные по HTTP - используется в реалтайм торговле 
  string GetMyFxData()
  {
    
   
   string aCookieHOLDER = NULL,
          aHttpHEADERs;

   char   postBYTEs[],
          replBYTEs[];    
   int    aRetCODE;
   datetime now = TimeCurrent();
   string aTargetURL = "http://178.238.227.195/cgi-bin/XAUUSD";
   CJAVal jv;

   int    aTIMEOUT = 30000;              
   aRetCODE = WebRequest( "GET",
                          aTargetURL,
                          aCookieHOLDER,
                          NULL,
                          aTIMEOUT,
                          postBYTEs,
                          0,
                          replBYTEs,
                          aHttpHEADERs
                          );
                          
   if (aRetCODE != 200)   
   {      
      return "Err";
   }   
   
   jv.Deserialize(replBYTEs);
   string Action=jv["Action"].ToStr();     
   return Action;
   
  }

// Функция загружает данные из CSV файла в массив для их дальнейшей проверки на истории
void ResourceToList(string ResTxt,CList & ListOfLines){
   
   ushort u_sep = 13;                    // код символа разделителя 
   string splitresult[];                 // массив для получения строк 
   int k=StringSplit(ResTxt,u_sep,splitresult); 
   if(k>0) 
     { 
      for(int i=0;i<k;i++) 
        { 
          string resultstring = splitresult[i];
          int sepposition = StringFind(resultstring, ";");
          int length = StringLen(resultstring);
          
          string DateString = StringSubstr(resultstring, 0, sepposition);
          StringTrimLeft(DateString);
          StringTrimRight(DateString);
          string PosString = StringSubstr(resultstring, sepposition + 1, length - sepposition - 1);
          StringTrimLeft(PosString);
          StringTrimRight(PosString);
          
          CTradeLine *newline = new CTradeLine;
          newline.ChangeDate = StringToTime(DateString);
          newline.PosType = PosString;
          ListOfLines.Add((CObject*)newline);    
        } 
     }
     
     CTradeLine *newline = ListOfLines.GetFirstNode();
     datetime startdate = newline.ChangeDate;
     string sstartdate = TimeToString(startdate);
     newline = ListOfLines.GetLastNode();
     datetime enddate   =  newline.ChangeDate;
     string senddate = TimeToString(enddate);
     Print("Test data avaliable only from : " + sstartdate + " to: " + senddate);
    
   return;
}

bool CheckMoneyForTrade(string symb,double lots,ENUM_ORDER_TYPE type)
  {
   MqlTick mqltick;
   SymbolInfoTick(symb,mqltick);
   double price=mqltick.ask;
   if(type==ORDER_TYPE_SELL)
      price=mqltick.bid;
   double margin,free_margin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(!OrderCalcMargin(type,symb,lots,price,margin))
     {
      Print("Error in ",__FUNCTION__," code=",GetLastError());
      return(false);
     }
   if(margin>free_margin)
     {
      Print("Not enough money for ",EnumToString(type)," ",lots," ",symb," Error code=",GetLastError());
      return(false);
     }
   return(true);
  }
  
  bool CheckVolumeValue(double volume)
  {

   double min_volume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   if(volume<min_volume)
     {
      Print("Position volume is less then minimum allowed SYMBOL_VOLUME_MIN=%.2f",min_volume);
      return(false);
     }

   double max_volume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   if(volume>max_volume)
     {
      Print("Position volume is more then maximum allowed SYMBOL_VOLUME_MAX=%.2f",max_volume);
      return(false);
     }

   double volume_step=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP);

   int ratio=(int)MathRound(volume/volume_step);
   if(MathAbs(ratio*volume_step-volume)>0.0000001)
     {
      Print("Position volume is not a multiple of position step SYMBOL_VOLUME_STEP=%.2f, nearest multiple volume %.2f",
                               volume_step,ratio*volume_step);
      return(false);
     }
   return(true);
  }
  
  
  bool IsNewOrderAllowed()
  {
   int max_allowed_orders=(int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
   if(max_allowed_orders==0) return(true);
   int orders=OrdersTotal();
   return(orders<max_allowed_orders);
  }
  
  double PositionVolume(string symbol)
  {
   bool selected=PositionSelect(symbol);
   if(selected)
      return(PositionGetDouble(POSITION_VOLUME));
   else
     {
      Print(__FUNCTION__," clouldn't execute PositionSelect() for symbol ",
            symbol," Error ",GetLastError());
      return(-1);
     }
  }
  
  double   PendingsVolume(string symbol)
  {
   double volume_on_symbol=0;
   ulong ticket;
   int all_orders=OrdersTotal();

   for(int i=0;i<all_orders;i++)
     {
      ticket=OrderGetTicket(i);
      if(symbol==OrderGetString(ORDER_SYMBOL))
            volume_on_symbol+=OrderGetDouble(ORDER_VOLUME_INITIAL);
     }
   return(volume_on_symbol);
  }
  
  double NewOrderAllowedVolume(string symbol)
  {
   double allowed_volume=0;
   double symbol_max_volume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   double max_volume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_LIMIT);
   double opened_volume=PositionVolume(symbol);
   if(opened_volume>=0)
     {
      if(max_volume-opened_volume<=0)
         return(0);
      double orders_volume_on_symbol=PendingsVolume(symbol);
      allowed_volume=max_volume-opened_volume-orders_volume_on_symbol;
      if(allowed_volume>symbol_max_volume) allowed_volume=symbol_max_volume;
     }
   return(allowed_volume);
  }