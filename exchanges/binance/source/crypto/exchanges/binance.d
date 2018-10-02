module crypto.exchanges.binance;

import std.conv;
import std.math;
import std.string;
import std.container;
import vibe.data.json;
import vibe.data.bson;
import vibe.web.rest;
import vibe.http.common;
import url;
import crypto.api;
import std.experimental.logger;

public import crypto.coins;

struct TradingPair
{
    Coin first;
    Coin second;

    this(Coin f, Coin s)
    {
        first = f;
        second = s;
    }

    this(string f, string s)
    {
        first = Coin[f];
        second = Coin[s];
    }
}

class Candle
{
public:
    double high;
    double low;
    double open;
    double close;

    bool isIncreasing()
    {
        return close > open;
    }

    bool isDecreasing()
    {
        return close < open;
    }
}

alias CandleListener = void delegate(scope Candle);

class BinanceExchange: Exchange
{
    import vibe.inet.url : URL;
    import vibe.http.websockets;

private:
    immutable string WsEndpoint = "wss://stream.binance.com:9443";

    CandleListener[] _candleListeners;
    WebSocket _currentWebSocket;

public:
    this(Credentials credential)
    {
        super(credential);
    }

    void connect()
    {

    }

    override void configure(ref Configuration config)
    {

    }

    /// Refresh websocket connection with stream list.
    void refreshWebSocket(string[] streams)
    {
        import std.array : join;


        try {
        if (_currentWebSocket !is null)
            _currentWebSocket.close();
        }
        catch (Exception e) {
            error(e.msg);
        }

        // /stream?streams=<streamName1>/<streamName2>/<streamName3>
        string url = WsEndpoint ~ "/stream?streams=" ~ streams.join("/");

        connectWebSocket(URL(url), (scope WebSocket ws) {
            _currentWebSocket = ws;

			// assert(ws.connected);
		    while(ws.connected)
		        info(ws.receiveText());
			_currentWebSocket = null;
        });
    }

    private string _tradingPairToString(TradingPair pair)
    {
        return pair.first.symbol ~ pair.second.symbol;
    }


    void addCandleListener(TradingPair pair, CandleListener listener)
    {
        _candleListeners ~= listener;



        //  <symbol>@kline_<interval>
        refreshWebSocket([_tradingPairToString(pair) ~ "@depth"]);
    }
}









/*

    mixin generateTradingPairs!([Coin.Bitcoin, Coin.Monero]);

    private mixin template generateTradingPairs(Coin[] coins)
    {
        import std.traits;
        import std.uni : toUpper;
        import std.format;
        import std.conv : to;
        import std.array;

        enum sanitizeChars = [
            "$": "D",
            "@": "At",
        ];

        static foreach(first; coins) {
            static foreach(second; [EnumMembers!Coin]) {
				mixin(q{
					static immutable TradingPair %s_%s = TradingPair(Coin.%s, Coin.%s);
 				}.format(sanitizeIdentifier(first.toUpper, sanitizeChars), sanitizeIdentifier(second.toUpper, sanitizeChars), to!string(first), to!string(second)));
            }
        }
    }

    private static string sanitizeIdentifier(string id, string[string] delimiters)
    {
        import std.array : replace;

        foreach(to, from; delimiters)
            id = id.replace(to, from);

        return id;
    }
    */
