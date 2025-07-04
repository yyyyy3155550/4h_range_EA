//+------------------------------------------------------------------+
//|                                                         4-5J.mq5 |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   ""

//#define JST_OFFSET_HOURS 9 // 日本標準時 (JST) は UTC+9　//タイムセッション関数

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/AccountInfo.mqh> // 口座情報取得用
#include <Trade/SymbolInfo.mqh>  // 銘柄情報取得用

CTrade trade;
CPositionInfo posinfo;


//trade time setting
input int START_HOUR          = 15;    //START_HOUR
input int START_MINUTE        = 30; //START_MINUTE
input int END_HOUR            = 0;     //END_HOUR
input int END_MINUTE          = 30;   //END_MINUTE

//時間になったらキャンセルpendingOrder
input int cancelPendingHour = 0; //cancelPendingHour
input int cancelPendingMin = 30; //cancelPendingMin

//trade position setting
input double loss_parcent = 1; //％　許容損失
input double SL = 15; //SL
input double TP = 30; //TP
input int MagicNum =012345; //MagicNumber

input double MaxSpread = 3; //MaxSpread

input bool ChartOBJ = false; //チャートオブジェクト描写

//タイムセッション関数
//input int BrokerGmtOffsetForBacktest = 2;

//--- 垂直線オブジェクト----------
int      LineTargHour   = START_HOUR;     // 目標時間 (時) 統合
int      LineTargMin = START_MINUTE;     // 目標時間 (分)　統合
input int      InpDaysToDraw   = 5;      // 描画する日数
input color    InpLineColor    = clrRed; // 線の色
input ENUM_LINE_STYLE InpLineStyle = STYLE_DASH; // 線のスタイル
input int      InpLineWidth    = 1;      // 線の幅
string   InpLinePrefix   = "VLine_1500_"; // オブジェクト名の接頭辞
datetime g_last_draw_time = 0; // 最後に描画を実行した時間（秒単位のチェック用）
int      InpLineTargetHour ;     // 目標時間 (時)
int      InpLineTargetMinute ;     // 目標時間 (分)


//Dailyポジションリミット、カウント
int DailyLimitFlag = 0;
// グローバル変数：最後に更新した4Hバーの開始時刻
datetime lastH4ConfirmedTime = 0;
datetime lastM15ConfirmedTime = 0;
//確定4h最高安値 格納
double prevH4High ;
double prevH4Low ;
double Pip;
ulong orderTicket = 0; //オーダーID
int Akeeper = 0; //キーパーロック
datetime flagCandle = 0; //signalをonにした5mの始まりの時間を格納
//flagCandleの高値と安値
double m5H = 0;
double m5L = 0;

//+--------------------------+
//| Time to ServerTime
//--
int START_HOUR_ServerTime;
int START_MINUTE_ServerTime;
int END_HOUR_ServerTime;
int END_MINUTE_ServerTime;


//+--------------------------------------+
//| シグナルフラグの定義   |
//+---------------------------+
enum SignalFlag
   {
    SIGNAL_NONE = 0,  // 何もしない
    SIGNAL_BUY,        // 買いシグナル
    SIGNAL_SELL,       // 売りシグナル
    SIGNAL_OK_TRADE,   //閾値超え 売買可能

    SIGNAL_NOTTIME //時間外
   };

// 各インジケーターのシグナルフラグ       /////--- グローバル ---/////
SignalFlag maSignal = SIGNAL_NONE;
SignalFlag rsiSignal = SIGNAL_NONE;
SignalFlag atrSignal = SIGNAL_NONE;
SignalFlag timeSignal = SIGNAL_NONE;
SignalFlag B4HighSig = SIGNAL_NONE; //break 4h high signal
SignalFlag B4LowSig = SIGNAL_NONE; //break 4h low signal


//+------------------------------------------------------------------+
//| [TIME SECTION]   DSTルール定義   (ヘッダーに置く)             |
//+------------------------------------------------------------------+
enum ENUM_DST_RULE
   {
    DST_NONE,     // DSTなし
    DST_EUROPE,   // 欧州ルール (デフォルト)
    DST_USA       // 米国ルール
   };


//+-----------------------------------------------------------------+
//|[AdjustPriceToStopLevel] TYPE定義  (ヘッダーに置く)     |
//+---------------------------------------------------------+
enum ENUM_ADJUST_TYPE
   {
    ADJUST_BUY_LIMIT,   // 買い指値
    ADJUST_SELL_LIMIT,  // 売り指値
    ADJUST_BUY_STOP,    // 買い逆指値
    ADJUST_SELL_STOP,   // 売り逆指値
    ADJUST_TP_BUY,      // 買い注文のテイクプロフィット
    ADJUST_TP_SELL,     // 売り注文のテイクプロフィット
    ADJUST_SL_BUY,      // 買い注文のストップロス
    ADJUST_SL_SELL      // 売り注文のストップロス
   };


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
   {
    trade.SetExpertMagicNumber(MagicNum);

    Print("jsttoser ",JSTtoServerTime(10,0));
    Print(TimeGMT());

//chart
    BJTshowChart();

    EventSetTimer(60); // 60秒ごとにOnTimer()を呼び出す

//---
//DrawVerticalLines();

    return(INIT_SUCCEEDED);
   }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
   {

    ObjectsDeleteAll(0,"H4HighLine_");
    ObjectsDeleteAll(0,"H4LowLine_");

//--- タイマーを停止
    EventKillTimer();

//--- 描画した垂直線を削除
    DeleteVerticalLines();

   }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
   {
    DayliyFlagReset();

    EntryCheck();

    ExecuteScheduledTasksAtJST(cancelPendingHour,cancelPendingMin);

//４時間/起動
    datetime currentH4Time = iTime(_Symbol, PERIOD_H4, 1);
    if(currentH4Time != lastH4ConfirmedTime)
       {
        lastH4ConfirmedTime = currentH4Time;
        Print("New4HBar 確定/更新: ", TimeToString(currentH4Time, TIME_DATE|TIME_MINUTES));


        if(ChartOBJ)
           {
            DrawH4Lines(); // 4HL描写
           }

        //確定4h最高安値取得
        prevH4High = iHigh(_Symbol, PERIOD_H4, 1);
        prevH4Low  = iLow(_Symbol, PERIOD_H4, 1);

        //更新のタイミングで ブレイク フラグ の初期化
        B4HighSig = SIGNAL_NONE; //break 4h high signal
        B4LowSig  = SIGNAL_NONE; //break 4h low signal

        Pip = GetPipSize();  // 1pipの価格単位を取得


        //--垂直線オブジェクト-----------------------------
        if(ChartOBJ)
           {
            DrawVerticalLines();

            MqlDateTime tdt;
            //inputされたhour,minutes,(日本時間)からサーバータイムに変換(dateTime型)
            datetime TargetTime = JSTtoServerTime(LineTargHour,LineTargMin); //LineTargetには、StartH,Mが代入されてる
            TimeToStruct(TargetTime,tdt);
            //サーバー時間に変換された、hour,minutesをInpLineTarget に格納して、グローバルで宣言してるのでそれを垂直線描写関数で呼び出して使う。
            InpLineTargetHour   = tdt.hour;     // 目標時間 (時)
            InpLineTargetMinute = tdt.min;     // 目標時間 (分)
           }
        //------------------------------------------


        //--セッションタイム jst to sever tiem--------------
        datetime StartDateTime = JSTtoServerTime(START_HOUR,START_MINUTE);
        datetime EndDateTime   = JSTtoServerTime(END_HOUR,END_MINUTE);

        MqlDateTime startDT;
        MqlDateTime endDT;
        TimeToStruct(StartDateTime,startDT);
        TimeToStruct(EndDateTime,endDT);

        START_HOUR_ServerTime   = startDT.hour;
        START_MINUTE_ServerTime = startDT.min;
        END_HOUR_ServerTime     = endDT.hour;
        END_MINUTE_ServerTime   = endDT.min;
        //------------------------------------------------

       }

//15M/起動
    datetime currentM15Time = iTime(_Symbol,PERIOD_M15,1);
    if(currentM15Time != lastM15ConfirmedTime)
       {
        lastM15ConfirmedTime = currentM15Time;

        //--垂直線オブジェクト--
        //DrawVerticalLines(); //m15だと重すぎて、やっぱ4hでいいかも。
        //--------------------------

       }


   }
/*
//+------------------------------------------------------------------+
//| エキスパートタイマー関数                                                 |
//+------------------------------------------------------------------+
void OnTimer()
   {
//--- 現在時刻を取得し、前回の描画から十分時間が経過したか確認
// (より厳密にするなら、日付や時間が変わったかチェック)
    datetime now = TimeCurrent();
// 簡単なチェック：毎分実行（OnInitでも実行されるのでこれで十分な場合が多い）
    DrawVerticalLines();
// 必要なら g_last_draw_time を使って頻度を制御
// g_last_draw_time = now;

   }
*/

//+------------------------------------------------------------------+
//|Entry check                               |
//+------------------------------------------------------------------+
void EntryCheck()
   {
    /* v1 -> v2を採用のため コメントあうと
      //------------
     //-- TIME ----
    //-----------
         datetime currentTime = TimeCurrent();
         MqlDateTime dt;

         TimeToStruct(currentTime,dt);

         int currentTotalMinutes = dt.hour * 60 + dt.min;
         int startTotalMinutes = START_HOUR * 60 + START_MINUTE;
         int endTotalMinutes   = END_HOUR * 60 + END_MINUTE;

         if(
              (startTotalMinutes <= endTotalMinutes && currentTotalMinutes >= startTotalMinutes && currentTotalMinutes <= endTotalMinutes) ||
              (startTotalMinutes > endTotalMinutes && (currentTotalMinutes >= startTotalMinutes || currentTotalMinutes <= endTotalMinutes))
         )
             {
              timeSignal = SIGNAL_OK_TRADE;
             }
    */

//トレードセッションタイム V2
// bool TradeSession = IsTradeTimeJST(START_HOUR,START_MINUTE,END_HOUR,END_MINUTE);
//トレードセッションタイム V3
    bool TradeSession = IsTradeTimeJST_Unified(/*TimeCurrent(),*/START_HOUR,START_MINUTE,END_HOUR,END_MINUTE);

    double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    /*----発注の瞬間にAsk,BidからTP,SLを計算するよりPriceから直接計算したほうがいいと判断したため、移転。---
        double bSL  = Ask - SL *Pip;
        double bTP  = Ask + TP *Pip;
        double sSL = Bid + SL *Pip;
        double sTP = Bid - TP *Pip;
    //正規化
        double buySL  = NormalizeDouble(bSL,_Digits);
        double buyTP  = NormalizeDouble(bTP,_Digits);
        double sellSL = NormalizeDouble(sSL,_Digits);
        double sellTP = NormalizeDouble(sTP,_Digits);
    *///-------------------------------------------------------------------------------

//高値ブレイク
    if((B4LowSig == SIGNAL_NONE || B4LowSig == SIGNAL_NOTTIME) && B4HighSig != SIGNAL_NOTTIME && prevH4High < Bid)
       {
        if(timeSignal == SIGNAL_OK_TRADE)
           {
            B4HighSig = SIGNAL_SELL;
            //Print("B4HighSig = SIGNAL_SELL");
           }
        else
            if(timeSignal == SIGNAL_NONE)
               {
                B4HighSig = SIGNAL_NOTTIME;
               }
       }
//安値ブレイク
    if((B4HighSig == SIGNAL_NONE || B4HighSig == SIGNAL_NOTTIME) && B4LowSig != SIGNAL_NOTTIME && prevH4Low > Bid) //あえてのBid、スプレッドでカウントされたくない
       {
        if(timeSignal == SIGNAL_OK_TRADE)
           {
            B4LowSig = SIGNAL_BUY;
            //Print("B4LowSig = SIGNAL_BUY;");
           }
        else
            if(timeSignal == SIGNAL_NONE)
               {
                B4LowSig = SIGNAL_NOTTIME;
               }
       }

//Print("timeSignal =(",EnumToString(timeSignal),") ", "B4HighSig =(",EnumToString(B4HighSig),") "," 　B4LowSig =(",EnumToString(B4LowSig),") ");
//Print("DailyLimitFlag ",DailyLimitFlag);

    if(DailyLimitFlag == 0)
       {
        if(TradeSession && timeSignal==SIGNAL_OK_TRADE)
           {
            //// 売りの場合
            if(B4HighSig == SIGNAL_SELL)
               {
                //Print("H-1");
                datetime currentM5BarTime = iTime(Symbol(), PERIOD_M5, 0);
                //Akeeper = 0; //キーパーロック

                //orderTicket = 0; // 注文番号格納用

                //現在足のスタート時間を保存
                if(flagCandle != currentM5BarTime && Akeeper == 0)
                   {
                    //Print("H-2");
                    Print("Akeeper= ",Akeeper);
                    flagCandle = currentM5BarTime;
                    Akeeper = 1;

                    Print("flagCandle =(",flagCandle,")");
                   }
                //保存した足がCloseしたら起動
                if(currentM5BarTime != flagCandle && Akeeper == 1)
                   {
                    //Print("H-3");
                    //5m HLを取得
                    m5H = iHigh(Symbol(), PERIOD_M5, 1);
                    m5L  = iLow(Symbol(), PERIOD_M5, 1);
                    double price = m5L - 0.1 * Pip; //大文字のPriceに最終価格をいれる
                    // AdjustPriceToStopLevelでStopLevel対策 正規化込み
                    double Price = AdjustPriceToStopLevel(_Symbol,price,ADJUST_SELL_STOP); //NormalizeDouble(price,_Digits);

                    //---PriceからSL,TPを計算------
                    double sSL = m5L + SL *Pip;
                    double sTP = m5L - TP *Pip;
                    // AdjustPriceToStopLevelでStopLevel対策 正規化込み
                    double sellSL = AdjustPriceToStopLevel(_Symbol,sSL,ADJUST_SL_SELL); //NormalizeDouble(sSL,_Digits);
                    double sellTP = AdjustPriceToStopLevel(_Symbol,sTP,ADJUST_TP_SELL); //NormalizeDouble(sTP,_Digits);

                    //---Lot----
                    double Lot = CalculateLotSize(_Symbol,SL,loss_parcent);
                    if(IsSpreadAcceptable(_Symbol,MaxSpread))
                       {
                        //pending order
                        if(!trade.SellStop(Lot,Price,_Symbol,sellSL,sellTP))
                           {
                            Print("売り注文発注失敗。エラーコード: ", trade.ResultRetcode());
                            Akeeper = 0;
                           }
                        else
                           {
                            //Print("H-4");
                            // 成功した場合、注文番号を取得
                            orderTicket = trade.ResultOrder();
                            Print("売り注文成功。チケット番号: ", orderTicket);
                            Akeeper = 2;
                           }
                       }

                   }
                //高値を超えたらオーダーキャンセル
                if(Bid > m5H && Akeeper == 2 && orderTicket > 0)
                   {
                    Print("bb");
                    if(trade.OrderDelete(orderTicket))
                       {
                        PrintFormat("注文 #%d の削除成功。", orderTicket);
                        orderTicket = 0; // 削除に成功したらチケット番号をリセット
                        Akeeper = 0;
                       }
                    else
                       {
                        PrintFormat("注文 #%d の削除失敗。エラーコード: %d",
                                    orderTicket,
                                    trade.ResultRetcode());
                        Akeeper = 0;
                       }
                   }

                /*
                if(Akeeper == 2 && orderTicket > 0) // 有効なチケット番号を持っているか
                  {
                   // 1. 注文情報を取得試行
                   if(OrderSelect(orderTicket))
                     {
                      // 2. 注文状態を取得
                      long orderState = OrderGetInteger(ORDER_STATE);

                      // 3. 約定したかチェック (ORDER_STATE_FILLED)
                      if(orderState == ORDER_STATE_FILLED)
                        {Print("h1");
                         PrintFormat("注文 #%d が約定しました！", orderTicket);
                         // --- 約定時の処理 ---
                         DailyLimitFlag++; // フラグを更新
                         PrintFormat("DailyLimitFlag を %d に更新。", DailyLimitFlag);
                         orderTicket = 0;  // チケット番号をリセット
                         Akeeper = 0;      // 状態をリセット
                         flagCandle = 0;   // 次のシグナルに備える
                         // --------------------
                        }
                      // else if (orderState == ORDER_STATE_PLACED etc...) { /* まだ約定していない場合の処理 * }

                     }
                   else // OrderSelect失敗 = 注文がアクティブリストにない
                     {
                      // 約定、キャンセル、期限切れの可能性
                      long lastError = GetLastError();
                      if(lastError == ERR_TRADE_ORDER_NOT_FOUND)  // 注文が見つからないエラー
                        {
                         PrintFormat("注文 #%d がアクティブリストにないため、処理完了とみなしリセットします。(約定/削除済み)", orderTicket);
                         // 約定したとみなす場合：
                         // DailyLimitFlag++;
                         orderTicket = 0;
                         Akeeper = 0;
                         flagCandle = 0;
                        }
                     }
                }*/
               }


            //// 買いの場合
            else
                if(B4LowSig == SIGNAL_BUY)
                   {
                    //Print("L-1");
                    datetime currentM5BarTime = iTime(Symbol(), PERIOD_M5, 0);
                    //Akeeper = 0; //キーパーロック
                    //static datetime flagCandle = 0; //signalをonにした5mの始まりの時間を格納
                    //flagCandleの高値と安値
                    //static double m5H = 0;
                    //static double m5L = 0;
                    //orderTicket = 0; // 注文番号格納用

                    //現在足のスタート時間を保存
                    if(flagCandle != currentM5BarTime && Akeeper == 0)
                       {
                        //Print("L-2");
                        Print("Akeeper= ",Akeeper);
                        flagCandle = currentM5BarTime;
                        Akeeper = 1;

                        Print("flagCandle =(",flagCandle,")");
                       }

                    //保存した足がCloseしたら起動
                    if(currentM5BarTime != flagCandle && Akeeper == 1)
                       {
                        //Print("L-3");
                        //5m HLを取得
                        m5H = iHigh(Symbol(), PERIOD_M5, 1);
                        m5L  = iLow(Symbol(), PERIOD_M5, 1);
                        double price = m5H + 0.1 * Pip; //大文字のPriceに最終価格をいれる
                        // AdjustPriceToStopLevelでStopLevel対策 正規化込み
                        double Price = AdjustPriceToStopLevel(_Symbol,price,ADJUST_BUY_STOP); //NormalizeDouble(price,_Digits); //正規化

                        //---PriceからSL,TPを計算---
                        double bSL  = m5H - SL *Pip;
                        double bTP  = m5H + TP *Pip;
                        // AdjustPriceToStopLevelでStopLevel対策 正規化込み
                        double buySL  = AdjustPriceToStopLevel(_Symbol,bSL,ADJUST_SL_BUY); //NormalizeDouble(bSL,_Digits);
                        double buyTP  = AdjustPriceToStopLevel(_Symbol,bTP,ADJUST_TP_BUY); //NormalizeDouble(bTP,_Digits);
                        double Lot = CalculateLotSize(_Symbol,SL,loss_parcent);

                        if(IsSpreadAcceptable(_Symbol,MaxSpread))
                           {
                            //pending order
                            if(!trade.BuyStop(Lot,Price,_Symbol,buySL,buyTP))
                               {
                                Print("売り注文発注失敗。エラーコード: ", trade.ResultRetcode());
                                Akeeper = 0;
                               }
                            else
                               {
                                //Print("L-4");
                                // 成功した場合、注文番号を取得
                                orderTicket = trade.ResultOrder();
                                Print("売り注文成功。チケット番号: ", orderTicket);
                                Akeeper = 2;
                               }
                           }
                       }
                    //安値を割ったらオーダーキャンセル
                    if(m5L > Bid && Akeeper == 2 && orderTicket > 0)
                       {
                        Print("bb2");
                        if(trade.OrderDelete(orderTicket))
                           {
                            PrintFormat("注文 #%d の削除成功。", orderTicket);
                            orderTicket = 0; // 削除に成功したらチケット番号をリセット
                            Akeeper = 0;
                           }
                        else
                           {
                            PrintFormat("注文 #%d の削除失敗。エラーコード: %d",
                                        orderTicket,
                                        trade.ResultRetcode());
                            Akeeper = 0;
                           }
                       }
                   }
           }
       }
   }

//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction //定義済み関数　イベントハンドラ　オーダーや、ポジションに関するイベント時に呼び出される。（自動）
(
    const MqlTradeTransaction& trans, // 取引トランザクション情報
    const MqlTradeRequest& request,   // 元の取引リクエスト
    const MqlTradeResult& result     // 取引結果
)
   {
// --- トランザクションタイプが「約定追加」かチェック ---
//     約定はポジションのオープン/クローズ両方を含む
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD) //タイプが、「約定がでたならば」
       {
        ulong deal_ticket = trans.deal; // 約定チケット番号を取得

        // --- 約定(Deal)の詳細情報を取得 ---
        if(deal_ticket > 0 && HistoryDealSelect(deal_ticket))
           {
            ulong deal_magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);

            if(deal_magic == MagicNum)
               {
                //entryの種類を取得 in,out,inout
                ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
                ulong order_ticket = HistoryDealGetInteger(deal_ticket, DEAL_ORDER); // 関連する注文チケットを取得

                // --- 新規エントリー (IN) または決済 (OUT, INOUT, OUT_BY) の約定かチェック ---
                //     ここでは新規エントリーのみカウントする
                if(entry == DEAL_ENTRY_IN)  // ★新規エントリーの約定のみをカウントする場合
                   {
                    if(DailyLimitFlag <= 0)
                       {
                        DailyLimitFlag++; // ★DailyLimitFlag をカウント
                        PrintFormat("OnTradeTransaction: 新規エントリー Deal #%d (Order: #%d) により DailyLimitFlag を %d に更新",
                                    deal_ticket,
                                    order_ticket,
                                    DailyLimitFlag);

                        Akeeper = 0; //キーパーフラグ　初期化
                       }
                   }
                // --- (オプション) 決済約定時のログ ---
                else
                    if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
                       {
                        PrintFormat("OnTradeTransaction: 決済 Deal #%d (%s) 発生 (Order: #%d)",
                                    deal_ticket, EnumToString(entry), order_ticket);
                       }
               }
            else // HistoryDealSelect 失敗
               {
                PrintFormat("OnTradeTransaction: Deal #%d の情報取得失敗。Error: %d", deal_ticket, GetLastError());
               }
           }
       }
   }

//+------------------------------------------------------------------+
//|DayliyFlagReset 関数                              |
//+------------------------------------------------------------------+
//1日の約定上限を設定する関数
void DayliyFlagReset()
   {

////約定が成功したら DailyLimitFlag に インクリメント ++ する

    if(DailyLimitFlag > 0)
       {
        datetime DailyStart = iTime(_Symbol, PERIOD_D1, 0);
        string DailyStartTimeStr = TimeToString(DailyStart, TIME_MINUTES); // 時間と分まで取り出す

        // 現在時刻の取得
        datetime CurrentTime = TimeCurrent();
        string CurrentTimeStr = TimeToString(CurrentTime, TIME_MINUTES); // 時間と分まで取り出す

        // 時刻だけを比較する
        if(DailyStartTimeStr == CurrentTimeStr)
           {
            // フラグリセット
            DailyLimitFlag = 0;
            Akeeper = 0;


            Print("フラグリセット実行");
           }
       }
   }


//+------------------------------------------------------------------+
//| 過去30本分の4Hローソク足の高値・安値ラインを、延長終点を2本先に描画  |
//+------------------------------------------------------------------+
void DrawH4Lines()
   {
    int bars = 30;

    MqlRates h4Rates[];

    if(CopyRates(_Symbol, PERIOD_H4, 0, bars, h4Rates) < bars)
       {
        Print("十分な4Hデータが取得できませんでした。");
        return;
       }
//ArraySetAsSeries(h4Rates,true); //copyratesはデフォルトで0が最新になってるみたい。

//関数が呼び出されるたびに、ループで0 to bar(30?)を一本ずつ処理
    for(int i = 0; i < bars; i++)
       {
        //オブジェクトの設定で使う、アンカー設定
        datetime startTime = h4Rates[i].time;
        datetime endTime   = h4Rates[i].time + 28800;  // 2本先の4Hバーの開始時刻を終点に使用
        double h4High      = h4Rates[i].high;
        double h4Low       = h4Rates[i].low;

        // オブジェクト名をユニーク、固有にする
        string highLineName = "H4HighLine_" + IntegerToString(i); //highLineNameっていう文字列変数に、H4HighLine_Xっていうユニークな名前を付ける
        string lowLineName  = "H4LowLine_" + IntegerToString(i);


        // 既存オブジェクトの削除
        if(ObjectFind(0, highLineName) != -1) //obj,highLineNameをチャート0から探す。-1(存在しない)でなければ
            ObjectDelete(0, highLineName);     // ↓オブジェクトを削除
        if(ObjectFind(0, lowLineName) != -1)
            ObjectDelete(0, lowLineName);


        // ObjectsDeleteAll(0, "H4HighLine_");
        //  ObjectsDeleteAll(0, "H4LowLine_");

        // 高値ラインの作成
        if(!ObjectCreate(0, highLineName, OBJ_TREND, 0, startTime, h4High, endTime, h4High))//0はchartID,つける名前,種,subWin,アンカー,この順番で並んでる。
           {
            Print("高値ラインの作成に失敗しました。");
           }
        else
           {
            //オブジェクト作成後、Objetsetで詳細設定
            ObjectSetInteger(0, highLineName, OBJPROP_COLOR, clrRed); // 色を赤にする
            ObjectSetInteger(0, highLineName, OBJPROP_RAY_RIGHT, false);// 終点は右側に延長しない
           }

        // 安値ラインの作成
        if(!ObjectCreate(0, lowLineName, OBJ_TREND, 0, startTime, h4Low, endTime, h4Low))
           {
            Print("安値ラインの作成に失敗しました。");
           }
        else
           {
            ObjectSetInteger(0, lowLineName, OBJPROP_COLOR, clrBlue);
            ObjectSetInteger(0, lowLineName, OBJPROP_RAY_RIGHT, false);
           }
       }
   }

//---vertical_Line_Draw-----------------------------------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|指定時間垂直オブジェクト vertical_Line_Draw 関数             |
//+------------------------------------------------------------------+
void DrawVerticalLines()
   {
//--- まず既存の線を削除
    DeleteVerticalLines();

//--- 目標時刻の MqlDateTime 構造体を作成 (日付は仮)
    MqlDateTime target_dt;
//InpLineTargetは、ontickでjsttoservertimeでサーバータイムに変換した。そしてmqldatetimeでH,m,を抜き出して格納してある。
    target_dt.hour = InpLineTargetHour;
    target_dt.min  = InpLineTargetMinute;
    target_dt.sec  = 0;

//--- 描画した日数をカウント
    int days_drawn = 0;

//--- 過去のバーを遡って目標時刻を探す
    datetime found_times[]; // 見つかった目標時刻を格納する配列
    datetime processed_days[]; // 処理済みの日の開始時刻(00:00:00)を格納

    int bars_total = Bars(_Symbol, PERIOD_M5);
    int limit_bars = MathMin(bars_total, 10000); // MathMiniは、インプットのうち小さいほうを返す。念のため探索上限を設定 (10000バー)

    for(int i = 0; i < limit_bars && days_drawn < InpDaysToDraw; i++)//10000回を上限&&描写days5以下ならループ //InpDaysToDrawは、inputで5を設定。
       {
        datetime bar_time = iTime(_Symbol,PERIOD_M5,i); //i本目のバーの始まり時刻を取得
        MqlDateTime bar_dt;                             //MqlDateTime型のbar_dtを宣言
        TimeToStruct(bar_time, bar_dt);                 //bar_time　を　bar_dt　に、ぶちこみ

        //--- day_start_timeには、そのバーの日付の開始時刻 (00:00:00) を格納。1日一本なので、その日は処理した日なのかをチェックするため。
        bar_dt.hour = 0; //日付以降の時分秒を0にそぎ落とし、1日の始まりの時間にする。
        bar_dt.min = 0;
        bar_dt.sec = 0;
        datetime day_start_time = StructToTime(bar_dt); //日付けと0:00:00のデータを格納

        //----------ここで、日ごとにフィルターしていく----------
        //--- この日付が既に処理済みかチェック
        bool day_processed = false; //ループのフラグ初期値
        for(int k = 0; k < ArraySize(processed_days); k++)//processed_daysのインデックスmaxまでループ
           {
            if(processed_days[k] == day_start_time) //IF配列[K]とday_start_timeが一致したら,day_processed = true;で、break;する
               {
                day_processed = true; //既に処理済みの検索で、一致すればtrueを返し、breakでループをでる
                break;
               }
           } //ArraySize(processed_days)までループして一致がなければ、終了し次の処理へ

        //------日ごとのフィルターを突破＝未処理だったら、そこからその日のターゲット時間を検索しにかかる---------
        //--- まだ処理していない日付の場合
        if(!day_processed)
           {
            //--- その日の目標時刻以降の最初のバーを探す
            // (iから遡り、同じ日で目標時刻より前のバーが見つかったら、その次のバーが目標)
            datetime target_bar_time = 0;
            datetime earliest_time_found_for_day = 0; // その日に見つかった目標時刻以降の最も早い時刻

            // バーiから過去に遡り、同じ日付の範囲で目標時刻を探す
            for(int j = i; j < limit_bars; j++)//iと連動して10000回を上限にループ
               {
                datetime current_bar_time = iTime(_Symbol, PERIOD_M5, j);
                MqlDateTime current_bar_dt;
                TimeToStruct(current_bar_time, current_bar_dt);

                current_bar_dt.hour = 0;
                current_bar_dt.min = 0;
                current_bar_dt.sec = 0;
                // 日付が変わったら、この日の探索は終了
                if(StructToTime(current_bar_dt) != day_start_time)
                   {
                    break; // 前の日になったのでループを抜ける
                   }

                // TimeToStructで再上書きして、0をリセット。current_bar_time現在バーのOpen時間にセット。
                TimeToStruct(current_bar_time, current_bar_dt);

                //1本ずつ検索と保存を繰り返して、目標時刻に一番近いとこまで繰り返す
                if(current_bar_dt.hour > InpLineTargetHour || (current_bar_dt.hour == InpLineTargetHour && current_bar_dt.min >= InpLineTargetMinute))//currentがinpより大きい OR （currentが15時 && currentMinがinpMin以上）
                   {
                    // 目標時刻以降のバーが見つかったら、その時刻を候補として保持
                    earliest_time_found_for_day = current_bar_time;
                    // このループでは同じ日のバーを遡っているので、
                    // earliest_time_found_for_day は自動的にその日の15:30以降で最も早い時刻に更新されていく
                   }
                else
                   {
                    // 目標時刻より前のバーが見つかったら、その日の探索はここまで
                    // （earliest_time_found_for_day には直前の目標時刻以降のバーが入っているはず）
                    break;
                   }

                //
               }


            //--- earliest_time_found_for_day に有効な時刻が入っていれば採用
            if(earliest_time_found_for_day > 0)
               {
                target_bar_time = earliest_time_found_for_day;

                // 見つかった時刻を配列に追加
                int current_size = ArraySize(found_times);//一周目は0から
                ArrayResize(found_times, current_size + 1);//一周するごとに+1していく
                found_times[current_size] = target_bar_time;//最初は、0に格納。そこから1ずつ増える。

                // 処理済み日付としてマーク
                int processed_size = ArraySize(processed_days);
                ArrayResize(processed_days, processed_size + 1);
                processed_days[processed_size] = day_start_time;//その日の0:00:0を処理済みに格納して、日ごとのフィルターで再処理しないようにする

                days_drawn++; // 描画カウントを増やす

                // 最適化: この日に属するバーはチェック済みなので、次のバーの探索位置を調整できるが、
                //          安全のため、単純に i をインクリメントさせる (forループの i++)
               }
            else
               {
                // その日には目標時刻以降のバーが見つからなかった
                // (例: 週末や、データが15:30前に終わっている場合など)
                // この場合でも、日付自体はチェック対象とする（無限ループ防止のため）
                int processed_size = ArraySize(processed_days);
                ArrayResize(processed_days, processed_size + 1);
                processed_days[processed_size] = day_start_time;
                // days_drawn は増やさない
               }
           }
       }

//--- 見つかった時刻に垂直線を描画
    for(int i = 0; i < ArraySize(found_times); i++)
       {
        datetime line_time = found_times[i];
        string obj_name = InpLinePrefix + TimeToString(line_time, TIME_DATE | TIME_MINUTES); // よりユニークな名前
        // 既存チェックはDeleteで実施済みなので不要
        // if(ObjectFind(0, obj_name) == -1)
        // {
        if(!ObjectCreate(0, obj_name, OBJ_VLINE, 0, line_time, 0))
           {
            Print("垂直線の作成に失敗: ", obj_name, ", Error: ", GetLastError());
           }
        else
           {
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, InpLineColor);
            ObjectSetInteger(0, obj_name, OBJPROP_STYLE, InpLineStyle);
            ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, InpLineWidth);
            ObjectSetInteger(0, obj_name, OBJPROP_BACK, true); // 背景に描画
            ObjectSetString(0, obj_name, OBJPROP_TOOLTIP, TimeToString(line_time, TIME_DATE | TIME_MINUTES) + " Line"); // ツールチップ
           }
        // }
       }
    ChartRedraw(); // チャートを再描画
   }
//+------------------------------------------------------------------+
//| 描画した垂直線を削除する関数                               |
//+------------------------------------------------------------------+
void DeleteVerticalLines()
   {
// チャート上の全オブジェクトをチェック
    for(int i = ObjectsTotal(0, -1, OBJ_VLINE) - 1; i >= 0; i--)//OBJ_VLINEタイプのオブジェクトの総数を取得。-1でインデックスに。
       {
        //一つずつVLINEタイプのオブジェクトの名前を取得　
        string obj_name = ObjectName(0, i, -1, OBJ_VLINE);
        //名前の接頭辞が一致するかチェック StringStartsWithは(obj_name)が特定の文字列(InpLinePrefix)で始まっているかどうかをチェックする
        if(StringStartsWith(obj_name, InpLinePrefix))
           {
            ObjectDelete(0, obj_name);
           }
       }
    ChartRedraw();
   }
//+------------------------------------------------------------------+
//| 文字列が指定した接頭辞で始まるかチェックするヘルパー関数             |
//+------------------------------------------------------------------+
bool StringStartsWith(const string text, const string prefix)
   {
    return(StringLen(text) >= StringLen(prefix) && StringSubstr(text, 0, StringLen(prefix)) == prefix);
   }

//---vertical_Line_Draw-----------------------------------------------------------------------------------------------+


//+--------------------------------------------------------------------------------+
//|時間になったら未約定オーダー全キャンセルする 関数  & 週末金曜　00:30　全ポジ決済  |
//+--------------------------------------------------------------------------------+
void ExecuteScheduledTasksAtJST(
    int targetHourJST,
    int targetMinuteJST
)
   {
// --- 入力値の検証 ---
    if(targetHourJST < 0 || targetHourJST > 23 || targetMinuteJST < 0 || targetMinuteJST > 59) {/*...*/return;}

//入力を換算関数でserverTimeにする
    datetime targetTime = JSTtoServerTime(targetHourJST,targetMinuteJST);

    static datetime lastExecutionMinute = 0;
//----------------------------


//-----------------------------
// 1. 現在のJST時刻と曜日を取得
    datetime serverTime = TimeCurrent();

    MqlDateTime now;
    TimeToStruct(serverTime,now);
    int currentHour = now.hour;
    int currentMinute = now.min;
    int currentDayOfWeek = now.day_of_week;

    MqlDateTime targetT;
    TimeToStruct(targetTime,targetT);
    int targetHour_severTime = targetT.hour;
    int targetMin_serverTime = targetT.min;


// 曜日を示す文字列を取得
    string currentDayStr = "不明な曜日"; // デフォルト値
    switch(currentDayOfWeek)
       {
        case SUNDAY:
            currentDayStr = "日曜日";
            break;
        case MONDAY:
            currentDayStr = "月曜日";
            break;
        case TUESDAY:
            currentDayStr = "火曜日";
            break;
        case WEDNESDAY:
            currentDayStr = "水曜日";
            break;
        case THURSDAY:
            currentDayStr = "木曜日";
            break;
        case FRIDAY:
            currentDayStr = "金曜日";
            break;
        case SATURDAY:
            currentDayStr = "土曜日";
            break;
       }

// 2. 指定時刻になったかチェック
    if(currentHour == targetHour_severTime && currentMinute == targetMin_serverTime)
       {
        datetime currentMinuteStart = serverTime - (serverTime % 60);
        if(currentMinuteStart != lastExecutionMinute)
           {
            // --- タスク実行 ---
            // ★ 取得した曜日文字列 (currentDayStr) を使用 ★
            PrintFormat("指定時刻 %02d:%02d JST (%s) になりました。スケジュールされたタスクを実行します。",
                        targetHourJST, targetMinuteJST, currentDayStr);
            lastExecutionMinute = currentMinuteStart;

            // --- タスク1: 未約定の保留注文を全て削除 ---
            Print("---  未約定の保留注文を削除します ---");
            // (削除ロジックは変更なし)
            int totalOrders = OrdersTotal();
            int deletedOrdersCount=0, failedOrdersCount=0;
            for(int i=totalOrders-1; i>=0; i--)
               {
                ulong t=OrderGetTicket(i);
                if(t>0 && OrderSelect(t))
                   {
                    long type=OrderGetInteger(ORDER_TYPE);
                    if(type == ORDER_TYPE_BUY_LIMIT ||
                       type == ORDER_TYPE_SELL_LIMIT ||
                       type == ORDER_TYPE_BUY_STOP ||
                       type == ORDER_TYPE_SELL_STOP ||
                       type == ORDER_TYPE_BUY_STOP_LIMIT ||
                       type == ORDER_TYPE_SELL_STOP_LIMIT)
                       {
                        string s=OrderGetString(ORDER_SYMBOL);
                        PrintFormat("  注文削除試行: #%d",t);
                        if(trade.OrderDelete(t))
                           {
                            Print("    -> 成功");
                            deletedOrdersCount++;
                           }
                        else
                           {
                            PrintFormat("    -> 失敗: %d",trade.ResultRetcode());
                            failedOrdersCount++;
                           }
                       }
                   }
               }
            //PrintFormat("---  結果 - 成功:%d, 失敗:%d ---", deletedOrdersCount, failedOrdersCount);


            // --- タスク2: 金曜日の場合、全ポジションを決済 ---
            if(currentDayOfWeek == FRIDAY)  // 金曜日かチェック
               {
                Print("---  週末のため、全オープンポジションを決済します ---");
                // (決済ロジックは変更なし)
                int totalPositions = PositionsTotal();
                int closedPositionsCount=0, failedPositionsCount=0;
                if(totalPositions > 0)
                   {
                    for(int i = totalPositions - 1; i >= 0; i--)
                       {
                        ulong ticket = PositionGetTicket(i);
                        if(PositionSelectByTicket(ticket))
                           {
                            //string symbol=PositionGetString(POSITION_SYMBOL);
                            //long type=PositionGetInteger(POSITION_TYPE);
                            //double vol=PositionGetDouble(POSITION_VOLUME);
                            PrintFormat("  ポジ決済試行: #%d",ticket);
                            if(trade.PositionClose(ticket))
                               {
                                Print("    -> 成功");
                                closedPositionsCount++;
                               }
                            else
                               {
                                PrintFormat("    -> 失敗: %d",trade.ResultRetcode());
                                failedPositionsCount++;
                               }
                           }
                        else
                           {
                            PrintFormat("  ポジ選択失敗(idx %d)",i);
                           }
                       }
                   }
                else
                   {
                    Print("  決済対象なし。");
                   }
                //PrintFormat("---  結果 - 成功:%d, 失敗:%d ---", closedPositionsCount, failedPositionsCount);
               }
            else
               {
                Print("---  NOT FRIDAY  ---");
               }
           }
       }
   }

//+------------------------------------------------------------------+
//セッションタイム関数   日本時間                                        |
//+------------------------------------------------------------------+
bool IsTradeTimeJST_Unified(
    //datetime currentBrokerTime,    // チェックする時刻 (バックテスト: time[i] or TimeCurrent(), ライブ: TimeCurrent())
    int      startHourJST,          // 取引開始 時 (日本時間)
    int      startMinuteJST,        // 取引開始 分 (日本時間)
    int      endHourJST,            // 取引終了 時 (日本時間)
    int      endMinuteJST,          // 取引終了 分 (日本時間)
    int BrokerGmtOffsetForBacktest = 2 // バックテスト用のタイムゾーン設定
)
   {
    datetime currentBrokerTime = TimeCurrent();
    const int JST_OFFSET_HOURS = 9;

// --- 入力値の検証 ---
    if(startHourJST < 0 || startHourJST > 23 || startMinuteJST < 0 || startMinuteJST > 59 ||
       endHourJST < 0 || endHourJST > 23 || endMinuteJST < 0 || endMinuteJST > 59)
       {
        PrintFormat("IsTradeTimeJST_Unified エラー: 無効なJST時刻 [%02d:%02d - %02d:%02d JST].",
                    startHourJST, startMinuteJST, endHourJST, endMinuteJST);
        timeSignal = SIGNAL_NONE; // エラー時はシグナルをNONEに設定
        return false;
       }

    bool isInRange = false;
    bool isTester = (bool)MQLInfoInteger(MQL_TESTER); // バックテスト環境か判定

// --- バックテスト環境での処理 ---
    if(isTester)
       {
        /*-----old---------------------------------------------------
                // バックテストでは input 変数 BrokerGmtOffsetForBacktest を使用
                int brokerGmtOffsetHours = BrokerGmtOffsetForBacktest;


                // GMTオフセットの簡単な検証 (必要に応じて範囲を調整)
                if(brokerGmtOffsetHours < -12 || brokerGmtOffsetHours > 14)
                   {
                    // PrintFormat("IsTradeTimeJST_Unified (Backtest) 警告: brokerGmtOffsetHours (%d) が一般的範囲外。", brokerGmtOffsetHours);
                    // 警告を出すだけで続行するなどの処理も可能
                   }

                // 1. ブローカー(サーバー)時刻からUTC時刻を計算 (バックテスト用)
                datetime simulatedUtcTime = currentBrokerTime - ((datetime)brokerGmtOffsetHours * 3600);

                // 2. 計算したUTC時刻から日本時間(JST)を計算 (バックテスト用)
                datetime simulatedJstTime = simulatedUtcTime + ((datetime)JST_OFFSET_HOURS * 3600);

                // 3. 計算した日本時間を MqlDateTime 構造体に変換して時・分を取得 (バックテスト用)
                MqlDateTime currentJstStruct;
                if(!TimeToStruct(simulatedJstTime, currentJstStruct))
                   {
                    PrintFormat("IsTradeTimeJST_Unified (Backtest) エラー: JST時刻の構造体変換失敗 (%s)", TimeToString(simulatedJstTime));
                    timeSignal = SIGNAL_NONE;
                    return false;
                   }

                int currentHourJST = currentJstStruct.hour;
                int currentMinuteJST = currentJstStruct.min;

                // 4. 全ての時刻を深夜0時からの合計分数(JST基準)に変換 (バックテスト用)
                int currentTotalMinutesJST = currentHourJST * 60 + currentMinuteJST;
                int startTotalMinutesJST = startHourJST * 60 + startMinuteJST;
                int endTotalMinutesJST = endHourJST * 60 + endMinuteJST;

                // 5. JST分数を使用して時間範囲をチェック (バックテスト用ロジック)
                // ケース1: 24時間
                if(startTotalMinutesJST == endTotalMinutesJST)
                   {
                    isInRange = true;
                   }
                // ケース2: 日付をまたがない (例: 09:00-17:00)
                else
                    if(startTotalMinutesJST < endTotalMinutesJST)
                       {
                        if(currentTotalMinutesJST >= startTotalMinutesJST && currentTotalMinutesJST < endTotalMinutesJST)
                           {
                            isInRange = true;
                           }
                       }
                    // ケース3: 日付をまたぐ (例: 22:00-05:00)
                    else // startTotalMinutesJST > endTotalMinutesJST
                       {
                        if(currentTotalMinutesJST >= startTotalMinutesJST || currentTotalMinutesJST < endTotalMinutesJST)
                           {
                            isInRange = true;
                           }
                       }
                /*
                // --- デバッグ用出力 (バックテスト) ---
                if(!IsOptimization()) // 最適化中は出力を抑制
                {
                    PrintFormat("Mode: Backtest, Broker Time: %s (Offset: %+d) -> Sim UTC: %s -> Sim JST: %s (%02d:%02d)",
                                TimeToString(currentBrokerTime), brokerGmtOffsetHours, TimeToString(simulatedUtcTime),
                                TimeToString(simulatedJstTime), currentHourJST, currentMinuteJST);
                    PrintFormat("JST Range: [%02d:%02d-%02d:%02d] (Total Mins: %d-%d), Current JST Total Mins: %d -> In Range: %s",
                                startHourJST, startMinuteJST, endHourJST, endMinuteJST, startTotalMinutesJST, endTotalMinutesJST,
                                currentTotalMinutesJST, (isInRange ? "Yes" : "No"));
                }
                */
        //--------- ↓　New ----
        MqlDateTime currentTimeStruct;
        if(!TimeToStruct(currentBrokerTime, currentTimeStruct))
           {
            PrintFormat("IsTradeTimeJST_Unified (Backtest) エラー: JST時刻の構造体変換失敗 (%s)", TimeToString(currentBrokerTime));
            timeSignal = SIGNAL_NONE;
            return false;
           }


        int currentHour = currentTimeStruct.hour;
        int currentMinute = currentTimeStruct.min;

        int currentTotalMinutes = currentHour * 60 + currentMinute;
        int startTotalMinutes   = START_HOUR_ServerTime * 60 + START_MINUTE_ServerTime;
        int endTotalMinutes     = END_HOUR_ServerTime * 60 + END_MINUTE_ServerTime;

        // ケース1: 24時間
        if(startTotalMinutes == endTotalMinutes)
           {
            isInRange = true;
           }
        // ケース2: 日付をまたがない (例: 09:00-17:00)
        else
            if(startTotalMinutes < endTotalMinutes)
               {
                if(currentTotalMinutes >= startTotalMinutes && currentTotalMinutes < endTotalMinutes)
                   {
                    isInRange = true;
                   }
               }
            // ケース3: 日付をまたぐ (例: 22:00-05:00)
            else // startTotalMinutes > endTotalMinutes
               {
                if(currentTotalMinutes >= startTotalMinutes || currentTotalMinutes < endTotalMinutes)
                   {
                    isInRange = true;
                   }
               }
       }
// --- ライブ環境での処理 ---
    else
       {
        // ライブでは TimeGMT() を使用 (引数 currentBrokerTime は使わない)
        datetime utcTime = TimeGMT(); // 現在のUTC時刻を取得 (DST自動考慮)

        // 1. UTC時刻を MqlDateTime に変換 (ライブ用)
        MqlDateTime utcDt;
        if(!TimeToStruct(utcTime, utcDt))
           {
            Print("IsTradeTimeJST_Unified (Live) エラー: UTC時刻の分解に失敗しました。");
            timeSignal = SIGNAL_NONE;
            return false;
           }
        int currentHourUTC = utcDt.hour;
        int currentMinuteUTC = utcDt.min;

        // 2. JSTの開始/終了時刻をUTCに変換 (ライブ用)
        int startHourUTC = (startHourJST - JST_OFFSET_HOURS + 24) % 24;
        int startMinuteUTC = startMinuteJST;
        int endHourUTC = (endHourJST - JST_OFFSET_HOURS + 24) % 24;
        int endMinuteUTC = endMinuteJST;

        // 3. 全ての時刻を深夜0時からの合計分数(UTC基準)に変換 (ライブ用)
        int currentTotalMinutesUTC = currentHourUTC * 60 + currentMinuteUTC;
        int startTotalMinutesUTC = startHourUTC * 60 + startMinuteUTC;
        int endTotalMinutesUTC = endHourUTC * 60 + endMinuteUTC;

        // 4. UTC分数を使用して時間範囲をチェック (ライブ用ロジック - 元のコードと同じ)
        // ケース1: 24時間
        if(startTotalMinutesUTC == endTotalMinutesUTC)
           {
            isInRange = true;
           }
        // ケース2: UTCで日付をまたがない
        else
            if(startTotalMinutesUTC < endTotalMinutesUTC)
               {
                if(currentTotalMinutesUTC >= startTotalMinutesUTC && currentTotalMinutesUTC < endTotalMinutesUTC)
                   {
                    isInRange = true;
                   }
               }
            // ケース3: UTCで日付をまたぐ
            else // startTotalMinutesUTC > endTotalMinutesUTC
               {
                if(currentTotalMinutesUTC >= startTotalMinutesUTC || currentTotalMinutesUTC < endTotalMinutesUTC)
                   {
                    isInRange = true;
                   }
               }
        /*
        // --- デバッグ用出力 (ライブ) ---
        datetime serverTimeLive = TimeCurrent(); // デバッグ表示用に取得
        PrintFormat("Mode: Live/Demo, JST Range: [%02d:%02d-%02d:%02d] -> UTC Range: [%02d:%02d-%02d:%02d]",
                    startHourJST, startMinuteJST, endHourJST, endMinuteJST,
                    startHourUTC, startMinuteUTC, endHourUTC, endMinuteUTC);
        PrintFormat("Server: %s (Offset:%d, DST:%d) -> UTC: %s (%02d:%02d) -> Total UTC Mins: %d -> In Range: %s",
                    TimeToString(serverTimeLive), TimeGMTOffset(), TimeDaylightSavings(),
                    TimeToString(utcTime), currentHourUTC, currentMinuteUTC,
                    currentTotalMinutesUTC, (isInRange ? "Yes" : "No"));
        */
       }

// --- 最終的なシグナル設定と戻り値 ---
    if(isInRange)
       {
        timeSignal = SIGNAL_OK_TRADE; // 時間内シグナル
       }
    else
       {
        timeSignal = SIGNAL_NONE;     // 時間外シグナル
       }

    return isInRange; // チェック結果を返す (true:範囲内, false:範囲外)
   }


//+------------------------------------------------------------------+
//| Pip size取得関数                                            |
//+------------------------------------------------------------------+
/* ------------ これはV1　　V2を導入したためコメントアウト -----------------
double GetPipSize()
   {
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

// もし tickSize が pointSize と同じなら、1 pip = 10 ticks と考え、10倍する
    double pipSize = (tickSize == pointSize) ? tickSize * 10 : tickSize;
    return NormalizeDouble(pipSize, _Digits);
   }
*/
//-------- V2 ----------------------------------------------------------
double GetPipSize()
   {
// シンボル情報を取得
    int calc_mode = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_CALC_MODE);
    double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

// Pointサイズが無効な場合は基本的なチェック
    if(pointSize <= 0)
       {
        PrintFormat("Warning: Invalid SYMBOL_POINT (%.*f) for %s. Returning 0.", digits, pointSize, _Symbol);
        return 0.0;
       }

    double pipSize = 0.0;

    if(calc_mode == SYMBOL_CALC_MODE_FOREX || calc_mode == SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE)
       {
        // --- FX系の処理 ---
        if(digits == 3 || digits == 5)  // JPY系3桁 (123.456) または 非JPY系5桁 (1.23456)
           {
            pipSize = pointSize * 10.0;
           }
        else
            if(digits == 2 || digits == 4)  // JPY系2桁 (123.45) または 非JPY系4桁 (1.2345)
               {
                pipSize = pointSize;
               }
            else // FXカテゴリだが標準外の桁数の場合 (念のためPointを返す)
               {
                pipSize = pointSize;
                // 必要なら警告メッセージを表示
                // PrintFormat("Warning: Unusual digits (%d) for Forex symbol %s. Using PointSize as PipSize.", digits, _Symbol);
               }
       }
// --- それ以外の計算モード (CFD, Futures, Stock, etc.) ---
    else
       {
        // TickSizeが有効であればそれを採用
        if(tickSize > 0)
           {
            pipSize = tickSize;
           }
        // TickSizeが無効ならPointをフォールバック(第一候補の値が使えないとき、代わりに使う値) (安全策)
        else
           {
            pipSize = pointSize;
            // 必要なら警告メッセージを表示
            // PrintFormat("Warning: Invalid SYMBOL_TRADE_TICK_SIZE (%.*f) for non-Forex symbol %s. Using PointSize as fallback.", digits, tickSize, _Symbol);
           }
       }

// 念のため、計算されたPipSizeがPointSizeより小さくならないようにする
// (TickSize が PointSize より小さい特殊ケースへの対応)
    if(pipSize < pointSize)
       {
        // TickSize が有効で PointSize より小さい場合は、TickSize を優先すべきか検討
        // ここでは安全策として、PointSize を下回らないように調整する
        // PrintFormat("Warning: Calculated PipSize (%.*f) was smaller than PointSize (%.*f) for %s. Adjusted to PointSize.", digits, pipSize, digits, pointSize, _Symbol);
        pipSize = pointSize;
       }

    return NormalizeDouble(pipSize, digits);
   }


//+------------------------------------------------------------------+
//|ロットサイズ計算関数 許容損失％と損切幅から計算                        |
//+------------------------------------------------------------------+
double CalculateLotSize(
    const string symbol,
    const double stopLossPips,
    const double riskPercent,
    const bool useBalance = true,
    const ENUM_ORDER_TYPE orderType = NULL
)

   {
// --- 0. 入力値検証 ---
    if(symbol == "" || !SymbolSelect(symbol, true))
       {
        PrintFormat("%s: Error - Symbol '%s' is invalid, not found, or not selected in Market Watch.", __FUNCTION__, symbol);
        return (0.0);
       }
    if(stopLossPips <= 0)
       {
        PrintFormat("%s: Error - Stop Loss (%.2f pips/points) must be positive.", __FUNCTION__, stopLossPips);
        return (0.0);
       }
    if(riskPercent <= 0)
       {
        PrintFormat("%s: Error - Risk percentage (%.2f%%) must be positive.", __FUNCTION__, riskPercent);
        return (0.0);
       }
// orderType は現在計算に不要だが、将来的に使う可能性を考慮し形式チェックのみ
    /*if(orderType != ORDER_TYPE_BUY && orderType != ORDER_TYPE_SELL)
       {
        PrintFormat("%s: Warning - Invalid order type specified (%d). Calculation proceeds but ensure correct usage.", __FUNCTION__, orderType);
        // return(0.0); // エラーにする場合はコメント解除
       }
    */

// --- 1. 必要な口座情報を取得 ---
    double accountFund = useBalance ? AccountInfoDouble(ACCOUNT_BALANCE) : AccountInfoDouble(ACCOUNT_EQUITY);
    string accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);

    if(accountFund <= 0)
       {
        PrintFormat("%s: Error - Account %s (%.2f %s) is zero or negative.", __FUNCTION__,
                    useBalance ? "Balance" : "Equity", accountFund, accountCurrency);
        return (0.0);
       }

// --- 2. 必要な銘柄情報を取得 ---
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);             // 最小価格変動単位
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE); // 1ティックの価値(口座通貨) - 1 Lot あたり
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);   // 1ティックの価格変動幅
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);      // ロットステップ
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);        // 最小ロット
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);        // 最大ロット
    int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);      // 価格の小数点以下桁数
    int    lotDigits = 0; // ロットの小数点以下桁数

// ロットステップから小数点以下桁数を決定
    if(lotStep > 0)
       {
        //-mathlog10が0を下回れば、0.0が採用される。mathlog10は10の何乗で()になるかの計算-にしてるのは+に反転させるため +0.00001は誤計算対策(例:-1.9999999998)
        lotDigits = (int)MathMax(0.0, -MathLog10(lotStep) + 0.00001);
       }
    else
       {
        PrintFormat("%s: Warning - Lot step for '%s' is zero or invalid. Assuming 2 digits for lot normalization.", __FUNCTION__, symbol);
        lotDigits = 2;
       }

    if(point <= 0 || tickValue <= 0 || tickSize <= 0 || lotStep <= 0 || minLot <= 0)
       {
        PrintFormat("%s: Error - Failed to retrieve critical symbol info for '%s'. Point=%.10f, TickValue=%.5f, TickSize=%.10f, LotStep=%.*f, MinLot=%.*f",
                    __FUNCTION__, symbol, point, tickValue, tickSize, lotDigits, lotStep, lotDigits, minLot);
        // TickValueが0または負は計算不能
        return (0.0);
       }

// --- 3. 1ロットあたりの損失額を計算 (口座通貨建て) ---
//    OrderCalcProfit を使わずに計算する

    double valuePerPoint = 0;
// TickValue は 1 Lot あたりの TickSize 変動による価値
// Point あたりの価値を計算 (TickSize が Point の N 倍の場合があるため)
    if(tickSize > 1e-10)  //1e-10=1 × 10⁻¹⁰=0.0000000001 誤差によって、理論上ゼロでも "0.00000000000001" のような超微小な値が残っていた場合に true になってしまう。それの対策
       {
        valuePerPoint = tickValue * (point / tickSize);
       }
    else
       {
        PrintFormat("%s: Error - Tick size for '%s' is zero or too small (%.10f). Cannot calculate value per point.", __FUNCTION__, symbol, tickSize);
        return (0.0);
       }


// 1 Pip は Point の何倍か？ (FXペアでは通常10倍、CFD等では1倍の場合が多い)
// 一般的なルール: 桁数が 3 または 5 -> 1 Pip = 10 Points, 桁数が 2 または 4 -> 1 Pip = 1 Point
    double pointsPerPip = 1.0;
    if(digits == 3 || digits == 5)
       {
        pointsPerPip = 10.0;
       }
// 例外的な銘柄 (例: XAUUSD=2桁だがPointがPipを表さない場合) は別途考慮が必要になる場合がある
// ここでは一般的なルールを適用

// 1 Pip あたりの価値 (1ロットあたり、口座通貨建て)
    double valuePerPip = valuePerPoint * pointsPerPip;

// 1ロットあたりの損失額 (SL幅 Pips * 1 Pip あたりの価値)
    double lossPerLot = stopLossPips * valuePerPip;

    if(lossPerLot <= 1e-10)  // 損失が計算できない、またはゼロの場合
       {
        PrintFormat("%s: Warning/Error - Calculated loss per lot for '%s' is zero or negative (%.10f %s). Check symbol info (TickValue=%.5f, TickSize=%.10f, Point=%.10f) and Stop Loss (%.2f pips).",
                    __FUNCTION__, symbol, lossPerLot, accountCurrency, tickValue, tickSize, point, stopLossPips);
        return(0.0);
       }

// --- 4. リスク許容額から最適ロットを計算 ---
    double riskAmount = accountFund * (riskPercent / 100.0);
    double calculatedLot = riskAmount / lossPerLot;

// --- 5. ロットサイズを正規化し、制約内に収める ---
    double adjustedLot = MathFloor(calculatedLot / lotStep) * lotStep;

    if(adjustedLot < minLot)
       {
        PrintFormat("%s: Info - Calculated lot (%.*f -> adjusted %.*f) for '%s' is below minimum (%.*f). Returning 0.0.",
                    __FUNCTION__,
                    lotDigits + 2, calculatedLot,
                    lotDigits, adjustedLot,
                    symbol,
                    lotDigits, minLot);
        return (0.0);
       }

    if(adjustedLot > maxLot)
       {
        PrintFormat("%s: Info - Calculated lot (%.*f -> adjusted %.*f) for '%s' exceeds maximum (%.*f). Capping at maximum.",
                    __FUNCTION__,
                    lotDigits + 2, calculatedLot,
                    lotDigits, adjustedLot,
                    symbol,
                    lotDigits, maxLot);
        adjustedLot = maxLot;
       }

    double finalLotSize = NormalizeDouble(adjustedLot, lotDigits);

// --- 6. 結果表示 (デバッグ用) ---
    PrintFormat("%s: Symbol=%s, SL Pips=%.1f, Risk=%.2f%%, Fund=%.2f %s => Risk Amount=%.2f %s, Value/Pip=%.5f %s, Loss/Lot=%.2f %s => Calc Lot=%.*f => Final Lot=%.*f",
                __FUNCTION__,
                symbol, stopLossPips, riskPercent,
                accountFund, accountCurrency,
                riskAmount, accountCurrency,
                valuePerPip, accountCurrency, // 1 Pipあたりの価値も表示
                lossPerLot, accountCurrency,
                lotDigits + 2, calculatedLot,
                lotDigits, finalLotSize);


// --- 7. 計算結果を返す ---
    return (finalLotSize);
   }



//+========================================================================+
//|| ---------------- TIME SECTION ------------------                    ||
//+========================================================================+

//+----------------------------------------------------------------------------------------------------------+
//| JST to ServerTIME 関数                                                                                   |
//| 指定されたJST時刻(時・分)に相当をサーバー時刻に変換し返す                                                    |
//| テスターモードでは standardServerOffsetHours と dstRule に基づいて手動DST判定を行う                         |
//| ライブ環境では TimeCurrent() と TimeGMT() の差からDST込みのオフセットを自動計算するため、dstRule は無視される  |
//+----------------------------------------------------------------------------------------------------------+
datetime JSTtoServerTime(
    int jHour,                            // 目標のJST時 (0-23)
    int jMinute,                         // 目標のJST分 (0-59)
    int standardServerOffsetHours = 2,  // サーバーの*標準時*のGMTオフセット(時間単位, 例: GMT+2なら2)
    ENUM_DST_RULE dstRule = DST_USA    // テスターモードで使用するDSTルール (ライブでは無視)
)
   {
// --- 入力値検証 ---
    if(jHour < 0 || jHour > 23 || jMinute < 0 || jMinute > 59)
       {
        PrintFormat("time_con エラー: 無効な時刻が指定されました (時=%d, 分=%d)", jHour, jMinute);
        return 0;
       }
// OffSetの検証 (例: GMT-12からGMT+14の範囲)
    if(standardServerOffsetHours < -12 || standardServerOffsetHours > 14)
       {
        PrintFormat("time_con エラー: 無効な標準オフセットが指定されました (OffSet=%d)", standardServerOffsetHours);
        return 0;
       }

// --- JSTのGMTからのオフセット(秒) (JST = GMT+9) ---
    const long jst_offset_seconds = 9 * 3600; //1h=3600sec

// --- 現在のサーバー時刻を取得 ---
// (テスター/ライブ共通: TimeCurrent()はどちらでも動作する)
    datetime now_server = TimeCurrent();
    if(now_server == 0) // TimeCurrent()がまだ有効でない場合(起動直後など)
       {
        PrintFormat("time_con エラー: 現在のサーバー時刻を取得できません。");
        return 0;
       }

    long server_offset_seconds = 0; // サーバーの現在のGMTオフセット(秒)

// --- モードに応じてサーバーのGMTオフセット(秒)を計算 ---
    bool isTester = (bool)MQLInfoInteger(MQL_TESTER);
    if(isTester)
       {
        // --- テスターモード ---
        // PrintFormat("time_con: テスターモード (標準オフセット = %+d, DSTルール = %s)",
        //             standardServerOffsetHours, EnumToString(dstRule));

        // 1. 標準時のオフセットを秒に変換
        long base_offset_seconds = (long)standardServerOffsetHours * 3600;

        // 2. 指定されたルールに基づいて現在のシミュレーション時刻のDSTを判定
        bool is_dst = false;
        switch(dstRule)
           {
            case DST_EUROPE:
                is_dst = IsSummerTime_Europe(now_server, (int)base_offset_seconds);
                //if(is_dst) Print("time_con: DST期間中と判定 (欧州ルール)");
                break;
            case DST_USA:
                is_dst = IsSummerTime_USA(now_server, (int)base_offset_seconds);
                //if(is_dst) Print("time_con: DST期間中と判定 (米国ルール)");
                break;
            case DST_NONE:
            default:
                is_dst = false; // DSTなし、または不明なルール
                //if(dstRule != DST_NONE) PrintFormat("time_con 警告: 不明なDSTルール %d が指定されました。DSTなしとして扱います。", (int)dstRule);
                break;
           }

        // 3. 夏時間ならオフセットを+1時間調整
        long dst_offset_seconds_adjustment = (is_dst ? 3600 : 0);
        server_offset_seconds = base_offset_seconds + dst_offset_seconds_adjustment;

        // PrintFormat("time_con: 計算されたサーバーオフセット = %d 秒 (GMT %+f)", server_offset_seconds, (double)server_offset_seconds / 3600.0);
       }
    else
       {
        // --- ライブ環境 ---
        // Print("time_con: ライブモード");
        // 1. 現在のサーバー時刻とGMTを取得
        datetime now_gmt = TimeGMT();
        if(now_gmt == 0) // TimeGMT()がまだ有効でない場合
           {
            PrintFormat("time_con エラー: GMT時刻を取得できません。ライブ環境では処理を中断します。");
            // ライブでGMTが取れないのは致命的。テスターのように標準オフセットを使うのは不正確すぎる可能性がある。
            return 0;
           }

        // 2. サーバーの現在のGMTからのオフセット(秒)を計算 (DST自動反映)
        server_offset_seconds = (long)now_server - (long)now_gmt;
        // PrintFormat("time_con: ライブ オフセット = %d 秒 (GMT %+f)", server_offset_seconds, (double)server_offset_seconds / 3600.0);
       }

// --- 共通計算部分 ---

// 4. JSTとサーバー時間のオフセットの差を計算 (JSTがサーバー時間より何秒進んでいるか)
    long diff_jst_vs_server = jst_offset_seconds - server_offset_seconds;

// 5. 今日のサーバー日付で、指定された JST 時・分を持つ仮の時刻を作成
//    (これはまだ正しいサーバー時間ではない。あくまで計算の基準点)
    MqlDateTime dt;
    TimeToStruct(now_server, dt); // 現在のサーバー日付を取得
    dt.hour = jHour;              // 指定されたJSTの「時」を設定 (まだ仮)
    dt.min = jMinute;             // 指定されたJSTの「分」を設定 (まだ仮)
    dt.sec = 0;
    datetime target_time_on_server_date = StructToTime(dt);
    if(target_time_on_server_date == 0) // StructToTime失敗チェック
       {
        PrintFormat("time_con エラー: 仮の目標時刻を作成できませんでした (日付:%s, 時:%d, 分:%d)",
                    TimeToString(now_server, TIME_DATE), jHour, jMinute);
        return 0;
       }

// 6. 仮の時刻からオフセット差を引いて、目標のJST時刻に対するサーバー時刻を計算
//    例: JST=GMT+9, Server=GMT+3(DST) の場合、差は +6時間。
//        JST 10:00 は Server 04:00。
//        ステップ5で仮に作った Server日付の10:00 から 6時間引くと Server日付の04:00 になる。
    datetime target_server_time = (datetime)target_time_on_server_date - (datetime)diff_jst_vs_server;

// 7. 日付ロールオーバー処理: 計算結果が現在時刻より過去なら翌日の時刻とする
//    これにより、常に「次の」指定JST時刻に対応するサーバー時刻を返す
    if(target_server_time <= now_server)
       {
        target_server_time += 24 * 3600; // 1日(秒)を加算

        // --- DST境界チェック (テスターモードのみ、翌日にDST状態が変わる可能性がある場合) ---
        // 翌日にした結果、DST状態が変わる場合、オフセットが1時間ずれる可能性がある。
        // このずれを補正するために、翌日のオフセットを再計算し、target_server_time を微調整する。
        if(isTester && dstRule != DST_NONE) // ライブでは不要、DSTなしルールでも不要
           {
            long next_day_base_offset_seconds = (long)standardServerOffsetHours * 3600;
            bool next_day_is_dst = false;
            switch(dstRule)
               {
                case DST_EUROPE:
                    next_day_is_dst = IsSummerTime_Europe(target_server_time, (int)next_day_base_offset_seconds);
                    break;
                case DST_USA:
                    next_day_is_dst = IsSummerTime_USA(target_server_time, (int)next_day_base_offset_seconds);
                    break;
               }
            long next_day_dst_offset_adjustment = (next_day_is_dst ? 3600 : 0);
            long next_day_server_offset_seconds = next_day_base_offset_seconds + next_day_dst_offset_adjustment;

            // オフセットが変化した場合、その差分だけ時刻を調整
            long offset_difference = next_day_server_offset_seconds - server_offset_seconds;
            if(offset_difference != 0)
               {
                // PrintFormat("time_con: DST境界を跨ぎました。オフセット変化: %d秒。時刻を調整します。", offset_difference);
                // JSTとサーバーの差が変化するので、その分 target_server_time を調整する。
                // diff_jst_vs_server = jst_offset_seconds - server_offset_seconds;
                // next_diff_jst_vs_server = jst_offset_seconds - next_day_server_offset_seconds;
                // 調整量 = target_server_time(旧オフセット基準) - target_server_time(新オフセット基準)
                //       = (target_jst_utc + server_offset_seconds) - (target_jst_utc + next_day_server_offset_seconds)
                //       = server_offset_seconds - next_day_server_offset_seconds = -offset_difference
                target_server_time -= (datetime)offset_difference;

                // 再度、調整後の時刻が過去になっていないかチェック（通常は不要だが念のため）
                if(target_server_time <= now_server)
                   {
                    target_server_time += 24 * 3600;
                   }
               }
           }
       }

// PrintFormat("time_con: 指定JST %02d:%02d -> 次のサーバー時間 %s (オフセット: %+f)",
//             jHour, jMinute, TimeToString(target_server_time, TIME_DATE|TIME_SECONDS), (double)server_offset_seconds / 3600.0); // デバッグ用

    return target_server_time;
   }
//+------------------------------------------------------------------+
//| 欧州夏時間ルールに基づき、指定時刻が夏時間中か判定                   |
//| (テスター用ヘルパー関数)                                        |
//| serverTime: 判定対象のサーバー時間                             |
//| standardOffsetSeconds: サーバーの*標準時*のGMTオフセット(秒)       |
//+------------------------------------------------------------------+
bool IsSummerTime_Europe(datetime serverTime, int standardOffsetSeconds)
   {
// サーバー時間からUTC時間を計算 (DST考慮前の標準時オフセットを使用)
    datetime utcTime = (datetime)serverTime - (datetime)standardOffsetSeconds;
    MqlDateTime dtUTC;
    if(!TimeToStruct(utcTime, dtUTC)) // 失敗チェック追加
       {
        PrintFormat("IsSummerTime_Europe Error: TimeToStruct failed for UTC time calculation (serverTime=%s, offset=%d)",
                    TimeToString(serverTime), standardOffsetSeconds);
        return false; // 失敗時は判定不可として標準時扱い
       }

// 4月～9月は確定で夏時間
    if(dtUTC.mon > 3 && dtUTC.mon < 10)
       {
        return true;
       }
// 1月, 2月, 11月, 12月は確定で標準時間
    if(dtUTC.mon < 3 || dtUTC.mon > 10)
       {
        return false;
       }

// 3月の場合: 最終日曜日の AM 1:00 UTC 以降か判定
    if(dtUTC.mon == 3)
       {
        datetime dstStartTime = GetLastSunday1amUTC(dtUTC.year, 3);
        if(dstStartTime == 0)
           {
            PrintFormat("IsSummerTime_Europe Warning: Failed to get DST start time for %d-03. Assuming standard time.", dtUTC.year);
            return false; // 最終日曜日の取得失敗時は標準時扱い
           }
        return (utcTime >= dstStartTime);
       }

// 10月の場合: 最終日曜日の AM 1:00 UTC より前か判定
    if(dtUTC.mon == 10)
       {
        datetime dstEndTime = GetLastSunday1amUTC(dtUTC.year, 10);
        if(dstEndTime == 0)
           {
            PrintFormat("IsSummerTime_Europe Warning: Failed to get DST end time for %d-10. Assuming standard time.", dtUTC.year);
            return false; // 最終日曜日の取得失敗時は標準時扱い
           }
        return (utcTime < dstEndTime);
       }

// ここには到達しないはず
    PrintFormat("IsSummerTime_Europe Error: Unexpected month %d", dtUTC.mon);
    return false;
   }
//+------------------------------------------------------------------+
//| 米国夏時間ルールに基づき、指定時刻が夏時間中か判定              |
//| (テスター用ヘルパー関数)                                        |
//| serverTime: 判定対象のサーバー時間                             |
//| standardOffsetSeconds: サーバーの*標準時*のGMTオフセット(秒)     |
//+------------------------------------------------------------------+
bool IsSummerTime_USA(datetime serverTime, int standardOffsetSeconds)
   {
// サーバー時間からUTC時間を計算 (DST考慮前の標準時オフセットを使用)
    datetime utcTime = (datetime)serverTime - (datetime)standardOffsetSeconds;
    MqlDateTime dtUTC;
    if(!TimeToStruct(utcTime, dtUTC))
       {
        PrintFormat("IsSummerTime_USA Error: TimeToStruct failed for UTC time calculation (serverTime=%s, offset=%d)",
                    TimeToString(serverTime), standardOffsetSeconds);
        return false; // 失敗時は判定不可として標準時扱い
       }


// 月による絞り込み
    if(dtUTC.mon < 3 || dtUTC.mon > 11)
        return false; // 1, 2, 12月は標準時
    if(dtUTC.mon > 3 && dtUTC.mon < 11)
        return true;  // 4月～10月は夏時間

// --- DST開始判定 (3月) ---
    if(dtUTC.mon == 3)
       {
        // DSTは3月第2日曜日の現地標準時AM 2:00に開始
        // その瞬間のUTC時刻を計算する
        datetime secondSundayStartUTC = GetNthWeekdayOfMonthUTC(dtUTC.year, 3, 2, SUNDAY, 0, 0); // 第2日曜日のUTC 00:00
        if(secondSundayStartUTC == 0)
           {
            PrintFormat("IsSummerTime_USA Warning: Failed to get 2nd Sunday of March %d. Assuming standard time.", dtUTC.year);
            return false;
           }
        // 現地標準時 AM 2:00に対応するUTC時刻 = 日曜UTC 00:00 + (2時間 - 標準オフセット秒)
        datetime dstStartTimeUTC = secondSundayStartUTC + (2 * 3600 - standardOffsetSeconds);

        // PrintFormat("Debug USA Start: Year=%d, 2ndSunUTC0=%s, StartUTC=%s, CurrentUTC=%s",
        //             dtUTC.year, TimeToString(secondSundayStartUTC, TIME_DATE|TIME_SECONDS),
        //             TimeToString(dstStartTimeUTC, TIME_DATE|TIME_SECONDS),
        //             TimeToString(utcTime, TIME_DATE|TIME_SECONDS));

        return (utcTime >= dstStartTimeUTC);
       }

// --- DST終了判定 (11月) ---
    if(dtUTC.mon == 11)
       {
        // DSTは11月第1日曜日の現地夏時間AM 2:00に終了 (現地標準時AM 1:00に戻る)
        // その瞬間のUTC時刻を計算する (標準時に戻る瞬間 = 現地標準時AM 1:00)
        datetime firstSundayStartUTC = GetNthWeekdayOfMonthUTC(dtUTC.year, 11, 1, SUNDAY, 0, 0); // 第1日曜日のUTC 00:00
        if(firstSundayStartUTC == 0)
           {
            PrintFormat("IsSummerTime_USA Warning: Failed to get 1st Sunday of November %d. Assuming standard time.", dtUTC.year);
            return false;
           }
        // 現地標準時 AM 1:00に対応するUTC時刻 = 日曜UTC 00:00 + (1時間 - 標準オフセット秒)
        datetime dstEndTimeUTC = firstSundayStartUTC + (1 * 3600 - standardOffsetSeconds);

        // PrintFormat("Debug USA End: Year=%d, 1stSunUTC0=%s, EndUTC=%s, CurrentUTC=%s",
        //             dtUTC.year, TimeToString(firstSundayStartUTC, TIME_DATE|TIME_SECONDS),
        //             TimeToString(dstEndTimeUTC, TIME_DATE|TIME_SECONDS),
        //             TimeToString(utcTime, TIME_DATE|TIME_SECONDS));

        // DST終了時刻(UTC)より前であれば、まだDST期間中
        return (utcTime < dstEndTimeUTC);
       }

// ここには到達しないはず
    PrintFormat("IsSummerTime_USA Error: Unexpected month %d", dtUTC.mon);
    return false;
   }
//+------------------------------------------------------------------+
//| 指定した年月の最終日曜日 AM 1:00 UTC の datetime を返す        |
//| (欧州 DST 計算用ヘルパー関数)                                   |
//+------------------------------------------------------------------+
datetime GetLastSunday1amUTC(int year, int month)
   {
    MqlDateTime dt;
    dt.year = year;
    dt.mon = month;
    dt.hour = 1; // UTC 1時
    dt.min = 0;
    dt.sec = 0;

// その月の最終日を取得 (簡便法)
    int daysInMonth = 31;
    if(month == 4 || month == 6 || month == 9 || month == 11)
        daysInMonth = 30;
    else
        if(month == 2)
           {
            // うるう年判定
            bool isLeap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
            daysInMonth = isLeap ? 29 : 28;
           }
// dt.day は設定せず、月末から探す

// 月末日から遡って日曜日を探す
    for(int d = daysInMonth; d >= 1; d--)
       {
        dt.day = d; // 日付を設定
        // MqlDateTimeからdatetimeを生成し、曜日を確認
        datetime tempTime = StructToTime(dt);
        if(tempTime > 0) // 有効な日時か確認
           {
            MqlDateTime checkDt;
            if(TimeToStruct(tempTime, checkDt)) // 再度構造体を取得して曜日を確認
               {
                // StructToTime/TimeToStructで日付が変わらないか念のため確認
                if(checkDt.year == year && checkDt.mon == month && checkDt.day == d)
                   {
                    if(checkDt.day_of_week == SUNDAY) // 0 = Sunday
                       {
                        // 見つかった日曜日の 1:00 UTC を正確に作る
                        // 既に dt.hour = 1 になっているので tempTime をそのまま返せば良い
                        return tempTime;
                       }
                   }
                else
                   {
                    // 日付が変わってしまった場合（通常ありえない）
                    PrintFormat("GetLastSunday1amUTC Warning: Date mismatch after StructToTime/TimeToStruct for %d-%02d-%02d", year, month, d);
                   }
               }
            else
               {
                PrintFormat("GetLastSunday1amUTC Warning: TimeToStruct failed for tempTime %s", TimeToString(tempTime));
               }
           }
        else
           {
            // StructToTimeが失敗した場合 (月の最終週などで稀に発生しうる)
            // PrintFormat("GetLastSunday1amUTC Debug: StructToTime failed for %d-%02d-%02d 01:00", year, month, d);
           }

       }
// 見つからなかった場合 (通常ありえない)
    PrintFormat("GetLastSunday1amUTC Error: Could not find last Sunday for %d-%02d", year, month);
    return 0;
   }
//+------------------------------------------------------------------+
//| 指定した年月の第N週・指定曜日の指定UTC時刻のdatetimeを返す      　　 |
//| (米国 DST 計算用ヘルパー関数)                                 　  |
//| nth: 週番号 (1=第1, 2=第2, ...) 第何週か                     　   |
//| day_of_week: 曜日 (0=日, 1=月, ..., 6=土)                        |
//| hourUTC, minuteUTC: 目標のUTC時刻                            　  |
//+------------------------------------------------------------------+
datetime GetNthWeekdayOfMonthUTC(int year, int month, int nth, int day_of_week, int hourUTC = 0, int minuteUTC = 0)
   {
    if(nth <= 0 || nth > 5)
       {
        PrintFormat("GetNthWeekdayOfMonthUTC Error: Invalid nth value %d", nth);
        return 0; // 無効な週番号
       }
    if(day_of_week < 0 || day_of_week > 6)
       {
        PrintFormat("GetNthWeekdayOfMonthUTC Error: Invalid day_of_week value %d", day_of_week);
        return 0; // 無効な曜日
       }


    MqlDateTime dt;
    dt.year = year;
    dt.mon = month;
    dt.day = 1; // 月の初日から開始
    dt.hour = hourUTC; // 指定されたUTC時
    dt.min = minuteUTC; // 指定されたUTC分
    dt.sec = 0;

    datetime firstDayTime = StructToTime(dt);
    if(firstDayTime == 0)
       {
        PrintFormat("GetNthWeekdayOfMonthUTC Error: Failed to create time for the 1st day of %d-%02d", year, month);
        return 0; // 月初日時作成失敗
       }

    MqlDateTime firstDayStruct;
    if(!TimeToStruct(firstDayTime, firstDayStruct))
       {
        PrintFormat("GetNthWeekdayOfMonthUTC Error: TimeToStruct failed for the 1st day of %d-%02d", year, month);
        return 0; // 構造体取得失敗
       }

// 月の初日の曜日 (0=Sun, 6=Sat)
    int firstDayOfWeek = firstDayStruct.day_of_week;

// 最初の目標曜日が何日になるか計算
// 例: 月初が水曜(3)で、目標が日曜(0)の場合: (0 - 3 + 7) % 7 = 4日後 -> 1 + 4 = 5日
// 例: 月初が日曜(0)で、目標が日曜(0)の場合: (0 - 0 + 7) % 7 = 0日後 -> 1 + 0 = 1日
    int daysToAddForFirstOccurrence = (day_of_week - firstDayOfWeek + 7) % 7;
    int firstOccurrenceDayOfMonth = 1 + daysToAddForFirstOccurrence;

// 第N週の目標曜日の日付を計算
    int targetDayOfMonth = firstOccurrenceDayOfMonth + (nth - 1) * 7;

// 計算結果の日付を dt 構造体に設定
    dt.day = targetDayOfMonth;

// 最終的な datetime を生成
    datetime targetTime = StructToTime(dt);
    if(targetTime == 0)
       {
        // PrintFormat("GetNthWeekdayOfMonthUTC Info: Calculated day %d for %d-%02d might be invalid (e.g., 5th Sunday).", targetDayOfMonth, year, month);
        return 0; // 無効な日付 (例: 存在しない第5日曜日など)
       }

// 生成された datetime が本当に正しい月か確認
    MqlDateTime verifyDt;
    if(!TimeToStruct(targetTime, verifyDt))
       {
        PrintFormat("GetNthWeekdayOfMonthUTC Error: TimeToStruct failed for targetTime %s", TimeToString(targetTime));
        return 0;
       }

    if(verifyDt.mon != month)
       {
        // PrintFormat("GetNthWeekdayOfMonthUTC Info: Target day %d for %d-%02d resulted in month %d. Not found.", targetDayOfMonth, year, month, verifyDt.mon);
        return 0; // 計算した日が翌月になってしまった場合 = その月のN番目の曜日は存在しない
       }

// 時刻が指定通りになっているか最終確認 (StructToTimeの挙動による影響を排除)
    if(verifyDt.hour != hourUTC || verifyDt.min != minuteUTC)
       {
        // PrintFormat("GetNthWeekdayOfMonthUTC Debug: Time components mismatch. Re-adjusting. Expected %02d:%02d, Got %02d:%02d for %s",
        //             hourUTC, minuteUTC, verifyDt.hour, verifyDt.min, TimeToString(targetTime));
        verifyDt.hour = hourUTC;
        verifyDt.min = minuteUTC;
        verifyDt.sec = 0;
        targetTime = StructToTime(verifyDt);
        if(targetTime == 0)
           {
            PrintFormat("GetNthWeekdayOfMonthUTC Error: Failed to re-adjust time components for %d-%02d-%02d %02d:%02d",
                        verifyDt.year, verifyDt.mon, verifyDt.day, hourUTC, minuteUTC);
            return 0;
           }
       }

    return targetTime;
   }
//==TIME SECTION=========================================================================================================================++


//+------------------------------------------------------------------+
//|　AdjustPriceToStopLevel関数 Price,SL,TPをStoplevelに対応させる関数  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| StopLevelの要件に準拠するように価格を調整する                  |
//| symbol        : シンボル名                                     |
//| requested_price: 要求された価格                              |
//| adjust_type   : 調整する価格のタイプ (ENUM_ADJUST_TYPE)      |
//| return          : 調整後の価格、またはエラー時は元の価格       |
//+------------------------------------------------------------------+
double AdjustPriceToStopLevel(string symbol, double requested_price, ENUM_ADJUST_TYPE adjust_type)
   {
// --- シンボル情報を取得 ---
    MqlTick latest_tick;
    if(!SymbolInfoTick(symbol, latest_tick))
       {
        Print("Error getting tick for ", symbol, ", Error ", GetLastError());
        // エラー時は元の価格を正規化して返す（あるいはエラーを示す特別な値、例：0や-1）
        return NormalizeDouble(requested_price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
       }
    double ask = latest_tick.ask;
    double bid = latest_tick.bid;

    long stop_level_points = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

// StopLevelが0または取得できない場合は調整不要
    if(stop_level_points <= 0 || point <= 0)
       {
        // PrintFormat("%s: StopLevel (= %d) or Point (= %G) is invalid. No adjustment.", symbol, stop_level_points, point);
        return NormalizeDouble(requested_price, digits); // 元の価格を正規化して返す
       }

// StopLevelを価格単位に変換
    double stop_level_price_delta = stop_level_points * point;

    double adjusted_price = requested_price; // 初期値は要求された価格
    bool adjusted = false; // 調整が行われたかどうかのフラグ

// --- タイプに基づいて調整ロジックを決定 ---
    switch(adjust_type)
       {
        // --- Ask + StopLevelDelta 以上である必要がある価格 ---
        case ADJUST_SELL_LIMIT: // 売り指値価格
        case ADJUST_BUY_STOP:   // 買い逆指値価格
        case ADJUST_TP_BUY:     // 買い注文のTPレベル
        case ADJUST_SL_SELL:    // 売り注文のSLレベル
           {
            double min_level_ask = NormalizeDouble(ask + stop_level_price_delta, digits);
            if(requested_price < min_level_ask)//stoplevelを下回ったら、レベルラインをpriceとして採用
               {
                adjusted_price = min_level_ask;
                adjusted = true;
               }
            break;
           }
        // --- Bid - StopLevelDelta 以下である必要がある価格 ---
        case ADJUST_BUY_LIMIT:  // 買い指値価格
        case ADJUST_SELL_STOP:  // 売り逆指値価格
        case ADJUST_TP_SELL:    // 売り注文のTPレベル
        case ADJUST_SL_BUY:     // 買い注文のSLレベル
           {
            double max_level_bid = NormalizeDouble(bid - stop_level_price_delta, digits);
            // 0より大きいことを確認 (価格がマイナスになるのを防ぐ)
            if(max_level_bid < 0)
                max_level_bid = 0;

            if(requested_price > max_level_bid && requested_price > 0) // 要求価格が0より大きい場合のみ比較
               {
                adjusted_price = max_level_bid;
                adjusted = true;
               }
            else
                if(requested_price <= 0 && (adjust_type == ADJUST_SL_BUY || adjust_type == ADJUST_TP_SELL))
                   {
                    // SL/TPを0に設定しようとしている場合は調整しない（削除とみなす）
                    adjusted_price = 0;
                   }
            break;
           }
        default:
            Print("AdjustPriceToStopLevel: Unknown adjustment type!");
            // 不明なタイプの場合は元の価格を正規化して返す
            return NormalizeDouble(requested_price, digits);
       }

// 調整が行われた場合にログ出力（デバッグ用）
    if(adjusted && requested_price != adjusted_price) // adjusted_priceが0でない場合のみログ出力強化
       {
        PrintFormat("Price Adjusted for %s: Requested=%.*f -> Adjusted=%.*f (Ask=%.*f, Bid=%.*f, StopLevelPoints=%d)",
                    EnumToString(adjust_type),
                    digits, requested_price,
                    digits, adjusted_price,
                    digits, ask,
                    digits, bid,
                    stop_level_points);
       }

// 最終的な価格を正規化して返す
    return NormalizeDouble(adjusted_price, digits);
   }


//+------------------------------------------------------------------+
//|  スプレッドチェッカー関数 　spread checker                         |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable(const string symbol, const double maxSpreadPips)
   {
    string errorDesc = "SpreadCheckerFunction error";
//errorDesc = ""; // エラーメッセージを初期化

// --- 1. シンボルの基本情報取得と検証 ---
    if(symbol == "" || symbol == NULL)
       {
        errorDesc = "シンボル名が指定されていません。";
        PrintFormat("IsSpreadAcceptable Error: %s", errorDesc);
        return false;
       }

// SYMBOL_DIGITS を取得してシンボルの有効性を最初に確認する方が堅牢
    long digits_long = SymbolInfoInteger(symbol, SYMBOL_DIGITS);
// GetLastError() のチェックも重要 (シンボルが存在しない場合 digits_long が 0 になることがあるため)
    if(digits_long <= 0 && GetLastError() != ERR_SUCCESS) // ERR_SUCCESS == 0と同じ
       {
        errorDesc = StringFormat("シンボル '%s' が見つからないか、マーケットウォッチで利用できません。Error: %d", symbol, GetLastError());
        PrintFormat("IsSpreadAcceptable Error: %s", errorDesc);
        // ResetLastError(); // 必要に応じてエラーコードをリセット
        return false;
       }
    int digits = (int)digits_long; // 整数型にキャスト

// SYMBOL_POINT (ポイントサイズ) を取得
    double pointSize = SymbolInfoDouble(symbol, SYMBOL_POINT);
    if(pointSize <= 0)
       {
        // ポイントサイズが取得できないのは致命的
        errorDesc = StringFormat("シンボル '%s' のポイントサイズが無効です (%.*f)。", symbol, digits, pointSize);
        PrintFormat("IsSpreadAcceptable Error: %s", errorDesc);
        return false;
       }

// --- 2. ピップサイズ (ポイント単位) を計算 ---
// 一般的なFXの定義: 3桁/5桁表示ブローカーでは 1 Pip = 10 Points, 2桁/4桁表示ブローカーでは 1 Pip = 1 Point
// 指数や商品など、他のアセットクラスでは 1 Pip = 1 Point と定義されることが多い
// ここではFXの慣例に従うが、必要に応じて調整が必要な場合がある
    double pointsPerPip = (digits == 3 || digits == 5) ? 10.0 : 1.0;
// より厳密には: 1 Pip = 10 * PointSize (5桁/3桁), 1 Pip = PointSize (4桁/2桁)
// double pipValue = pointsPerPip * pointSize; // これはpipsの価格単位での値

// --- 3. 最大許容スプレッドをポイント単位に変換 ---
    double maxSpreadPoints = maxSpreadPips * pointsPerPip;
    if(maxSpreadPoints < 0)  // 念のためマイナス入力チェック
       {
        maxSpreadPoints = 0;
       }

// --- 4. 現在のスプレッド (ポイント単位) を取得 ---
// SYMBOL_SPREAD は整数 (long) でポイント単位のスプレッドを返す
    long currentSpreadPoints = SymbolInfoInteger(symbol, SYMBOL_SPREAD);

// スプレッド取得失敗のチェック (0 は有効な値の場合もあるので注意)
// ゼロスプレッド自体は許可する (<= で比較するため問題ない)
// MarketInfoがまだ利用可能でない場合など、-1が返る可能性は低いがあるかもしれない
    if(currentSpreadPoints < 0)
       {
        // SYMBOL_SPREAD が負数を返すことは通常ないはずだが、念のため
        errorDesc = StringFormat("シンボル '%s' のスプレッド情報の取得に失敗しました (取得値: %d)。", symbol, currentSpreadPoints);
        PrintFormat("IsSpreadAcceptable Error: %s", errorDesc);
        return false;
       }

// --- 5. スプレッド比較 ---
// 現在のスプレッド (ポイント) が最大許容スプレッド (ポイント) 以下かチェック
    bool isAcceptable = (double)currentSpreadPoints <= maxSpreadPoints;

// --- 6. 結果のログ (任意、デバッグ用) ---
    /*
    if(isAcceptable) {
       PrintFormat("IsSpreadAcceptable Info: [%s] 現在のスプレッド %d points (<= 最大許容 %.1f pips / %.1f points) -> OK",
                   symbol, currentSpreadPoints, maxSpreadPips, maxSpreadPoints);
    } else {
       PrintFormat("IsSpreadAcceptable Alert: [%s] 現在のスプレッド %d points (> 最大許容 %.1f pips / %.1f points) -> NG",
                   symbol, currentSpreadPoints, maxSpreadPips, maxSpreadPoints);
    }
    */

    return isAcceptable;
   }


//+------------------------------------------------------------------+
//| ビジュアルテストで時間別チャートを複数だす関数        |
//+------------------------------------------------------------------+
void BJTshowChart()
   {
//double showChart_M1 = iClose(Symbol(), PERIOD_M1, 0);
    double showChart_M5 = iClose(Symbol(), PERIOD_M5, 0);
//double showChart_M15 = iClose(Symbol(), PERIOD_M15, 0);
//double showChart_M30 = iClose(Symbol(), PERIOD_M30, 0);
//double showChart_H1 = iClose(Symbol(), PERIOD_H1, 0);      // H1の終値を取得
//double showChart_H4 = iClose(Symbol(), PERIOD_H4, 0);
//double showChart_D1 = iClose(Symbol(), PERIOD_D1, 0);
   }



//+------------------------------------------------------------------+
