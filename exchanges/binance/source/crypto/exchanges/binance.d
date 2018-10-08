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
public import crypto.api;

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
    /// last part of signed enpoints
    static immutable SignedEndpoints = ["order", "account", "openOrders"];
    static immutable int[int] DepthValidLimitByWeight;
    static immutable OrderStatus[string] OrderStatusToStd;
    static immutable OrderType[string] OrderTypeToStd;
    static immutable TradeDirection[string] TradeDirectionToStd;

    static this()
    {

        DepthValidLimitByWeight = [
            5: 1,
            10: 1,
            20: 1,
            50: 1,
            100: 1,
            500: 5,
            1000: 10];

        OrderStatusToStd = [
            "NEW":              OrderStatus.open,
            "PARTIALLY_FILLED": OrderStatus.open,
            "FILLED":           OrderStatus.closed,
            "CANCELED":         OrderStatus.canceled,];

        OrderTypeToStd = [
            "LIMIT":             OrderType.market,
            "MARKET":            OrderType.limit,
            "STOP_LOSS":         OrderType.stopLoss,
            "STOP_LOSS_LIMIT":   OrderType.stopLossLimit,
            "TAKE_PROFIT":       OrderType.takeProfit,
            "TAKE_PROFIT_LIMIT": OrderType.takeProfitLimit,
            "LIMIT_MAKER":       OrderType.limitMaker];

        TradeDirectionToStd = [
            "BUY":  TradeDirection.buy,
            "SELL": TradeDirection.sell];
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
    override const void _signRequest(ref URLD url, out string[string] headers)
    {
        import std.string : split;
        import std.algorithm : canFind;

        // endpoint require signing ?
        if (canFind(SignedEndpoints, url.path.split('/')[$-1])) {
            import std.digest.hmac;
            import std.digest : toHexString;
            import std.digest.sha : SHA256;

            // add recvWindow to query params
            if (!_userConfig.isNull)
                url.queryParams.add("recvWindow", _userConfig.recvWindow.to!string);

            // add timestamp to query params
            long nonce = getMillisTimestamp() - _timeDiffMs;
            url.queryParams.add("timestamp", nonce.to!string);

            string totalParams = url.queryParams.toString();
            string signature = totalParams
                .representation
                .hmac!SHA256(_credentials.secretApiKey.representation)
                .toHexString!(LetterCase.lower).dup;
            url.queryParams.add("signature", signature);

            headers["X-MBX-APIKEY"] = _credentials.apiKey;

            // TODO: add recWindow
        }
    }

    override long _fetchServerMillisTimestamp()
    {
        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v1/time";
        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);

        return response["serverTime"].enforceGet!long;
    }

    /** Ensure no error in a binance json response.
    It throw exception depending of the error code.
    Json payload is:
    {"msg":"Timestamp for this request is outside of the recvWindow.","code":-1021} */
    override void _enforceNoError(in Json binanceResponse) const
    {
        if (binanceResponse.type == Json.Type.object) {
            // if json field "code" exists, then it is an error
            if (binanceResponse["code"].type !is Json.Type.undefined) {
                auto code = binanceResponse["code"].enforceGet!int;
                auto msg = binanceResponse["msg"].enforceGet!string;

                switch(code) {
                    case -1021: throw new ExpiredRequestException(msg);
                    default: throw new ExchangeException(msg);
                }
            }
        }
    }

public:
    this(Credentials credential, ExchangeConfiguration config = null)
    {
        super(credential, config);
    }

    void connect()
    {

    }

    override void _configure(ref Configuration config)
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

        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);
        // if self.options['adjustForTimeDifference']:
        //    self.load_time_difference()
        Market[] result;
        auto markets = response["symbols"];

        foreach(market; markets) {
            // "123456" is a "test symbol/market"
            if (market["symbol"] == "123456")
                continue;

            Json[string] filters = crypto.utils.json.indexBy(market["filters"], "filterType");

            auto entry = new Market();
            entry.id = market["symbol"].enforceGet!string;
            entry.base = _commonCurrencyCode(market["baseAsset"].enforceGet!string);
            entry.quote = _commonCurrencyCode(market["quoteAsset"].enforceGet!string);
            entry.precision.base = market["baseAssetPrecision"].enforceGet!int;
            entry.precision.quote = market["quotePrecision"].enforceGet!int;
            entry.precision.amount = market["baseAssetPrecision"].enforceGet!int;
            entry.precision.price = market["quotePrecision"].enforceGet!int;
            entry.active = (market["status"].enforceGet!string == "TRADING");

            entry.info = market;
            entry.limits.amount.min = 2;
            entry.limits.amount.min = pow(10.0, -entry.precision.amount);
            entry.limits.price.min = pow(10.0, -entry.precision.price);
            entry.limits.cost.min = -1.0 * log10(entry.precision.amount);

            if ("PRICE_FILTER" in filters) {
                auto filter = filters["PRICE_FILTER"];
                entry.precision.price = _precisionFromString(filter["tickSize"].enforceGet!string);
                entry.limits.price.min = filter["minPrice"].enforceGet!(float, string);
                entry.limits.price.max = filter["maxPrice"].enforceGet!(float, string);
            }
            if ("LOT_SIZE" in filters) {
                auto filter = filters["LOT_SIZE"];
                entry.precision.amount = _precisionFromString(filter["stepSize"].enforceGet!string);
                entry.limits.amount.min = filter["minQty"].enforceGet!(float, string);
                entry.limits.amount.max = filter["minQty"].enforceGet!(float, string);
            }
            if ("MIN_NOTIONAL" in filters) {
                auto filter = filters["MIN_NOTIONAL"];
                entry.limits.cost.min = filter["minNotional"].enforceGet!(float, string);
            }
            result ~= entry;
        }
        return result;
    }

    override OrderBook fetchOrderBook(string symbol, int limit=100)
    {
        _enforceSymbol(symbol);
        enforce!ExchangeException(limit in DepthValidLimitByWeight, "Not a valid exchange limit " ~ limit.to!string);

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v1/depth";
        endpoint.queryParams.add("symbol", markets[symbol].id);
        endpoint.queryParams.add("limit", limit.to!string);
        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);

        OrderBook result = new OrderBook();
        foreach(bid; response["bids"])
            result.bids ~= Order(bid[1].enforceGet!(float, string), bid[0].enforceGet!(float, string));

        foreach(ask; response["asks"])
            result.asks ~= Order(ask[1].enforceGet!(float, string), ask[0].enforceGet!(float, string));

        return result;
    }

    override PriceTicker fetchTicker(string symbol)
    {
        _enforceSymbol(symbol);

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v1/ticker/24hr";
        endpoint.queryParams.add("symbol", markets[symbol].id);
        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);

        PriceTicker result = new PriceTicker();
        auto last = response["lastPrice"].enforceGet!float();

        result.symbol = symbol;
        result.info = response;
        result.timestamp = response["closeTime"].enforceGet!long;
        result.datetime = _timestampToDateTime(result.timestamp);
        result.high = response["highPrice"].enforceGet!(float, string);
        result.low = response["lowPrice"].enforceGet!(float, string);
        result.bid = response["bidPrice"].enforceGet!(float, string);
        result.bidVolume = response["bidQty"].enforceGet!(float, string);
        result.ask = response["askPrice"].enforceGet!(float, string);
        result.askVolume = response["askQty"].enforceGet!(float, string);
        result.vwap = response["weightedAvgPrice"].enforceGet!(float, string);
        result.open = response["openPrice"].enforceGet!(float, string);
        result.close = last;
        result.last = last;
        result.previousClose = response["prevClosePrice"].enforceGet!(float, string);
        result.change = response["priceChange"].enforceGet!(float, string);
        result.percentage = response["priceChangePercent"].enforceGet!(float, string);
        result.average = 0;
        result.baseVolume = response["volume"].enforceGet!(float, string);
        result.quoteVolume = response["quoteVolume"].enforceGet!(float, string);

        return result;
    }

    override Candlestick[] fetchOhlcv(string symbol, CandlestickInterval interval, int limit=500)
    {
        _enforceSymbol(symbol);
        initialize();

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v1/klines";
        endpoint.queryParams.add("symbol", markets[symbol].id);
        endpoint.queryParams.add("interval", _candlestickIntervalToStr(interval));
        endpoint.queryParams.add("limit", limit.to!string);
        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);
        Candlestick[] result;

        foreach(candle; response) {
            Candlestick entry = new Candlestick();
            entry.timestamp = candle[0].enforceGet!long;
            entry.open   = candle[1].enforceGet!(float, string);
            entry.high   = candle[2].enforceGet!(float, string);
            entry.low    = candle[3].enforceGet!(float, string);
            entry.close  = candle[4].enforceGet!(float, string);
            entry.volume = candle[5].enforceGet!(float, string);

            result ~= entry;
        }
        return result;
    }

    override Trade[] fetchTrades(string symbol, int limit=500)
    {
        _enforceSymbol(symbol);

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v1/aggTrades";
        // TODO: add startTime, endTime, fromId
        endpoint.queryParams.add("symbol", markets[symbol].id);
        endpoint.queryParams.add("limit", limit.to!string);
        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);

        Trade[] result;
        foreach(trade; response) {
            Trade entry = new Trade();
            entry.info = trade;
            entry.id = trade["a"].enforceGet!(string, long);
            entry.timestamp = trade["T"].enforceGet!long;
            entry.datetime = _timestampToDateTime(entry.timestamp);
            entry.symbol = symbol;
            entry.order = null;
            entry.type = OrderType.undefined;
            if (trade["m"].enforceGet!bool)
                entry.side = TradeDirection.sell;
            else
                entry.side = TradeDirection.buy;
            entry.price = trade["p"].enforceGet!(float, string);
            entry.amount = trade["q"].enforceGet!(float, string);
            result ~= entry;
        }

        return result;
    }

    override CurrencyBalance[string] fetchBalance(bool hideZero = true)
    {
        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v3/account";
        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);

        CurrencyBalance[string] result;

        foreach(balance; response["balances"]) {
            CurrencyBalance entry = new CurrencyBalance();
            auto free = balance["free"].enforceGet!(float, string);
            auto used = balance["locked"].enforceGet!(float, string);
            if (hideZero && (free == 0) && (used == 0))
                continue;

            entry.free = free;
            entry.used = used;
            result[balance["asset"].enforceGet!string] = entry;
        }

        return result;
    }

    override FullOrder[] fetchOpenOrders(string symbol)
    {
        _enforceSymbol(symbol);

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v3/openOrders";
        endpoint.queryParams.add("symbol", markets[symbol].id);
        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);

        FullOrder[] result;
        foreach(order; response) {
            FullOrder entry = new FullOrder();
            entry.id = order["orderId"].enforceGet!(string, long);
            entry.timestamp = order["time"].enforceGet!long;
            entry.datetime = _timestampToDateTime(entry.timestamp);
            entry.status = OrderStatusToStd[order["status"].enforceGet!string];
            entry.symbol = _findSymbol(order["symbol"].enforceGet!string);
            entry.type = OrderTypeToStd[order["type"].enforceGet!string];
            entry.side = TradeDirectionToStd[order["side"].enforceGet!string];
            entry.price = order["price"].enforceGet!(float, string);
            entry.amount = order["origQty"].enforceGet!(float, string);
            entry.filled = order["executedQty"].enforceGet!(float, string);
            entry.cost = order["cummulativeQuoteQty"].enforceGet!(float, string);
            entry.info = order;
            result ~= entry;
        }
        return result;
    }
}
