module crypto.exchanges.binance;

import std.conv;
import std.math;
import std.string;
import std.container;
import vibe.data.json;
import vibe.data.bson;
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

class CombinedStreamResponse
{
    string stream;
    Json data;
}

/** Binance json base response */
class BinanceResponse
{
    @optional BinanceError error;
}

/** Binance json error response */
class BinanceError
{
    int code;
    string msg;
}


class BinanceExchange: Exchange
{
    import vibe.inet.url : URL;
    import vibe.http.websockets;
    import std.math : pow, log10;

private:
    immutable string BaseEndpoint = "https://api.binance.com";
    immutable string WsEndpoint = "wss://stream.binance.com:9443";

    URLD BaseUrl = parseURL("https://api.binance.com");

    CandleListener[string] _candleListeners;
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
		    while(ws.connected) {
		        auto str = ws.receiveText();
		        auto resp = deserializeJson!CombinedStreamResponse(str);

                import std.format : formattedRead;

                string pair;
                string stream;
                resp.stream.formattedRead!"%s@%s"(pair, stream);

                if (stream == "depth")
                    if (pair in _candleListeners)
                        _candleListeners[pair](new Candle());

		        info(str);
            }

			_currentWebSocket = null;
        });
    }

    private string _tradingPairToString(TradingPair pair)
    {
        return pair.first.symbol ~ pair.second.symbol;
    }

    void addCandleListener(TradingPair pair, CandleListener listener)
    {
        string pairString = _tradingPairToString(pair);
        string stream = pairString ~ "@depth"; // <symbol>@kline_<interval>
        info(pairString);
        _candleListeners[pairString] = listener;
        refreshWebSocket([stream]);
    }

    override Market[] fetchMarkets()
    {
        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v1/exchangeInfo";

        Json response = jsonHttpRequest(endpoint, HTTPMethod.GET);
        // if self.options['adjustForTimeDifference']:
        //    self.load_time_difference()

        Market[] result;
        auto markets = response["symbols"];
        foreach(market; markets) {
            // "123456" is a "test symbol/market"
            if (market["symbol"] == "123456")
                continue;

            Json[string] filters = indexBy(market["filters"], "filterType");

            auto entry = new Market();
            entry.id = market["symbol"].get!string;
            entry.base = commonCurrencyCode(market["baseAsset"].get!string);
            entry.quote = commonCurrencyCode(market["quoteAsset"].get!string);
            entry.precision.base = market["baseAssetPrecision"].get!int;
            entry.precision.quote = market["quotePrecision"].get!int;
            entry.precision.amount = market["baseAssetPrecision"].get!int;
            entry.precision.price = market["quotePrecision"].get!int;
            entry.active = (market["status"].get!string == "TRADING");

            entry.info = market;
            entry.limits.amount.min = 2;
            entry.limits.amount.min = pow(10.0, -entry.precision.amount);
            entry.limits.price.min = pow(10.0, -entry.precision.price);
            entry.limits.cost.min = -1.0 * log10(entry.precision.amount);

            if ("PRICE_FILTER" in filters) {
                auto filter = filters["PRICE_FILTER"];
                entry.precision.price = precisionFromString(filter["tickSize"].get!string);
                entry.limits.price.min = filter["minPrice"].get!string.safeTo!double(0);
                entry.limits.price.max = filter["maxPrice"].get!string.safeTo!double(0);
            }
            if ("LOT_SIZE" in filters) {
                auto filter = filters["LOT_SIZE"];
                entry.precision.amount = precisionFromString(filter["stepSize"].get!string);
                entry.limits.amount.min = filter["minQty"].get!string.safeTo!double(0);
                entry.limits.amount.max = filter["minQty"].get!string.safeTo!double(0);
            }
            if ("MIN_NOTIONAL" in filters) {
                auto filter = filters["MIN_NOTIONAL"];
                entry.limits.cost.min = filter["minNotional"].get!string.safeTo!double(0);
            }
            result ~= entry;
        }
        return result;
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
