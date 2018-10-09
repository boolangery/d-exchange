/**
    Binance API.
*/
module crypto.exchanges.binance;

public import crypto.exchanges.core.api;


alias CandleListener = void delegate(scope Candlestick);

class CombinedStreamResponse
{
    string stream;
    Json data;
}

/** Binance exchange. */
class BinanceExchange: Exchange
{
    import vibe.inet.url : URL;
    import vibe.http.websockets;
    import std.math : pow, log10;

private /*constants*/:
    URLD BaseUrl = parseURL("https://api.binance.com");
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
    override void _signRequest(ref URLD url, out string[string] headers) const @safe
    {
        import std.string : split, representation;
        import std.algorithm : canFind;
        import std.ascii : LetterCase;

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

    override long _fetchServerMillisTimestamp() @safe
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
    override void _enforceNoError(in Json binanceResponse) @safe const
    {
        if (binanceResponse.type == Json.Type.object) {
            // if json field "code" exists, then it is an error
            if (binanceResponse["code"].type !is Json.Type.undefined) {
                auto code = binanceResponse["code"].enforceGet!int;
                auto msg = binanceResponse["msg"].enforceGetStr;

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
        import vibe.data.json;


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

    void addCandleListener(string pair, CandleListener listener)
    {
        /*
        string pairString = _tradingPairToString(pair);
        string stream = pairString ~ "@depth"; // <symbol>@kline_<interval>
        info(pairString);
        _candleListeners[pairString] = listener;
        refreshWebSocket([stream]);*/
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

            Json[string] filters = crypto.exchanges.core.utils.json.indexBy(market["filters"], "filterType");

            auto entry = new Market();
            entry.id = market["symbol"].enforceGetStr;
            entry.base = _commonCurrencyCode(market["baseAsset"].enforceGetStr);
            entry.quote = _commonCurrencyCode(market["quoteAsset"].enforceGetStr);
            entry.precision.base = market["baseAssetPrecision"].enforceGet!int;
            entry.precision.quote = market["quotePrecision"].enforceGet!int;
            entry.precision.amount = market["baseAssetPrecision"].enforceGet!int;
            entry.precision.price = market["quotePrecision"].enforceGet!int;
            entry.active = (market["status"].enforceGetStr == "TRADING");

            entry.info = market;
            entry.limits.amount.min = 2;
            entry.limits.amount.min = pow(10.0, -entry.precision.amount);
            entry.limits.price.min = pow(10.0, -entry.precision.price);
            entry.limits.cost.min = -1.0 * log10(entry.precision.amount);

            if ("PRICE_FILTER" in filters) {
                auto filter = filters["PRICE_FILTER"];
                entry.precision.price = _precisionFromString(filter["tickSize"].enforceGetStr);
                entry.limits.price.min = filter["minPrice"].enforceGetStrToF;
                entry.limits.price.max = filter["maxPrice"].enforceGetStrToF;
            }
            if ("LOT_SIZE" in filters) {
                auto filter = filters["LOT_SIZE"];
                entry.precision.amount = _precisionFromString(filter["stepSize"].enforceGetStr);
                entry.limits.amount.min = filter["minQty"].enforceGetStrToF;
                entry.limits.amount.max = filter["minQty"].enforceGetStrToF;
            }
            if ("MIN_NOTIONAL" in filters) {
                auto filter = filters["MIN_NOTIONAL"];
                entry.limits.cost.min = filter["minNotional"].enforceGetStrToF;
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
            result.bids ~= Order(bid[1].enforceGetStrToF, bid[0].enforceGetStrToF);

        foreach(ask; response["asks"])
            result.asks ~= Order(ask[1].enforceGetStrToF, ask[0].enforceGetStrToF);

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
        result.high = response["highPrice"].enforceGetStrToF;
        result.low = response["lowPrice"].enforceGetStrToF;
        result.bid = response["bidPrice"].enforceGetStrToF;
        result.bidVolume = response["bidQty"].enforceGetStrToF;
        result.ask = response["askPrice"].enforceGetStrToF;
        result.askVolume = response["askQty"].enforceGetStrToF;
        result.vwap = response["weightedAvgPrice"].enforceGetStrToF;
        result.open = response["openPrice"].enforceGetStrToF;
        result.close = last;
        result.last = last;
        result.previousClose = response["prevClosePrice"].enforceGetStrToF;
        result.change = response["priceChange"].enforceGetStrToF;
        result.percentage = response["priceChangePercent"].enforceGetStrToF;
        result.average = 0;
        result.baseVolume = response["volume"].enforceGetStrToF;
        result.quoteVolume = response["quoteVolume"].enforceGetStrToF;

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
            entry.open   = candle[1].enforceGetStrToF;
            entry.high   = candle[2].enforceGetStrToF;
            entry.low    = candle[3].enforceGetStrToF;
            entry.close  = candle[4].enforceGetStrToF;
            entry.volume = candle[5].enforceGetStrToF;

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
            entry.price = trade["p"].enforceGetStrToF;
            entry.amount = trade["q"].enforceGetStrToF;
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
            auto free = balance["free"].enforceGetStrToF;
            auto used = balance["locked"].enforceGetStrToF;
            if (hideZero && (free == 0) && (used == 0))
                continue;

            entry.free = free;
            entry.used = used;
            result[balance["asset"].enforceGetStr] = entry;
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
            entry.status = OrderStatusToStd[order["status"].enforceGetStr];
            entry.symbol = _findSymbol(order["symbol"].enforceGetStr);
            entry.type = OrderTypeToStd[order["type"].enforceGetStr];
            entry.side = TradeDirectionToStd[order["side"].enforceGetStr];
            entry.price = order["price"].enforceGetStrToF;
            entry.amount = order["origQty"].enforceGetStrToF;
            entry.filled = order["executedQty"].enforceGetStrToF;
            entry.cost = order["cummulativeQuoteQty"].enforceGetStrToF;
            entry.info = order;
            result ~= entry;
        }
        return result;
    }
}
