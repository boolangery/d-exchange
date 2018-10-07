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
public import crypto.api : CandlestickInterval;

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

alias CandleListener = void delegate(scope Candlestick);

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

private /*constants*/:
    immutable string BaseEndpoint = "https://api.binance.com";
    immutable string WsEndpoint = "wss://stream.binance.com:9443";
    static immutable int[int] DepthValidLimitByWeight;

    static this()
    {

        DepthValidLimitByWeight = [
            5: 1,
            10: 1,
            20: 1,
            50: 1,
            100: 1,
            500: 5,
            1000: 10
        ];
    }

private:
    URLD BaseUrl = parseURL("https://api.binance.com");
    CandleListener[string] _candleListeners;
    WebSocket _currentWebSocket;

protected:
    DateTime _timestampToDateTime(long ts)
    {
        import std.datetime.systime : unixTimeToStdTime;
        import std.datetime : SysTime;

        return cast(DateTime) SysTime(unixTimeToStdTime(ts / 1000));
    }

    /// Sign a binance secure route.
    override const void _signRequest(URLD url, out string[string] headers)
    {
        import std.string : split;
        import std.algorithm : canFind;

        static immutable SignedEndpoints = ["order"];

        // endpoint require signing ?
        if (canFind(SignedEndpoints, url.toString().split('/')[$-1])) {

        }
    }

    override DateTime _fetchTime()
    {
        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v1/time";
        Json response = jsonHttpRequest(endpoint, HTTPMethod.GET);

        return _timestampToDateTime(response["serverTime"].get!long);
    }

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
                        _candleListeners[pair](new Candlestick());

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

    override OrderBook fetchOrderBook(string symbol, int limit=100)
    {
        enforceSymbol(symbol);
        enforce!ExchangeException(limit in DepthValidLimitByWeight, "Not a valid exchange limit " ~ limit.to!string);

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v1/depth";
        endpoint.queryParams.add("symbol", markets[symbol].id);
        endpoint.queryParams.add("limit", limit.to!string);
        Json response = jsonHttpRequest(endpoint, HTTPMethod.GET);

        OrderBook result = new OrderBook();
        foreach(bid; response["bids"])
            result.bids ~= Order(bid[1].get!string().to!double(), bid[0].get!string().to!double());

        foreach(ask; response["asks"])
            result.asks ~= Order(ask[1].get!string().to!double(), ask[0].get!string().to!double());

        return result;
    }

    override PriceTicker fetchTicker(string symbol)
    {
        enforceSymbol(symbol);

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v1/ticker/24hr";
        endpoint.queryParams.add("symbol", markets[symbol].id);
        Json response = jsonHttpRequest(endpoint, HTTPMethod.GET);

        PriceTicker result = new PriceTicker();
        auto last = response["lastPrice"].safeGetStr!float();

        result.symbol = symbol;
        result.info = response;
        result.timestamp = response["closeTime"].safeGet!long;
        result.datetime = _timestampToDateTime(result.timestamp);
        result.high = response["highPrice"].safeGetStr!float();
        result.low = response["lowPrice"].safeGetStr!float();
        result.bid = response["bidPrice"].safeGetStr!float();
        result.bidVolume = response["bidQty"].safeGetStr!float();
        result.ask = response["askPrice"].safeGetStr!float();
        result.askVolume = response["askQty"].safeGetStr!float();
        result.vwap = response["weightedAvgPrice"].safeGetStr!float();
        result.open = response["openPrice"].safeGetStr!float();
        result.close = last;
        result.last = last;
        result.previousClose = response["prevClosePrice"].safeGetStr!float();
        result.change = response["priceChange"].safeGetStr!float();
        result.percentage = response["priceChangePercent"].safeGetStr!float();
        result.average = 0;
        result.baseVolume = response["volume"].safeGetStr!float();
        result.quoteVolume = response["quoteVolume"].safeGetStr!float();

        return result;
    }

    override Candlestick[] fetchOhlcv(string symbol, CandlestickInterval interval, int limit=500)
    {
        enforceSymbol(symbol);
        loadMarkets();

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v1/klines";
        endpoint.queryParams.add("symbol", markets[symbol].id);
        endpoint.queryParams.add("interval", _candlestickIntervalToStr(interval));
        endpoint.queryParams.add("limit", limit.to!string);
        Json response = jsonHttpRequest(endpoint, HTTPMethod.GET);
        Candlestick[] result;

        foreach(candle; response) {
            Candlestick entry = new Candlestick();
            entry.timestamp = candle[0].get!long;
            entry.open   = candle[1].safeGetStr!float();
            entry.high   = candle[2].safeGetStr!float();
            entry.low    = candle[3].safeGetStr!float();
            entry.close  = candle[4].safeGetStr!float();
            entry.volume = candle[5].safeGetStr!float();

            result ~= entry;
        }
        return result;
    }

    override Trade[] fetchTrades(string symbol, int limit=500)
    {
        enforceSymbol(symbol);

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v1/aggTrades";
        // TODO: add startTime, endTime, fromId
        endpoint.queryParams.add("symbol", markets[symbol].id);
        endpoint.queryParams.add("limit", limit.to!string);
        Json response = jsonHttpRequest(endpoint, HTTPMethod.GET);

        Trade[] result;
        foreach(trade; response) {
            Trade entry = new Trade();
            entry.info = trade;
            entry.id = trade["a"].get!long.to!string;
            entry.timestamp = trade["T"].get!long;
            entry.datetime = _timestampToDateTime(entry.timestamp);
            entry.symbol = symbol;
            entry.order = null;
            entry.type = OrderType.undefined;
            if (trade["m"].get!bool)
                entry.side = TradeDirection.sell;
            else
                entry.side = TradeDirection.buy;
            entry.price = trade["p"].safeGetStr!float();
            entry.amount = trade["q"].safeGetStr!float();
            result ~= entry;
        }

        return result;
    }
}
