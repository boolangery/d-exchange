/**
    Binance API.
*/
module crypto.exchanges.binance;

public import crypto.exchanges.core.api;


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
    static immutable SignedEndpoints = ["order", "account", "openOrders", "order"];
    static immutable int[int] DepthValidLimitByWeight;
    static immutable OrderStatus[string] OrderStatusToStd;
    static immutable OrderType[string] OrderTypeToStd;
    static immutable string[OrderType] StdToOrderType;
    static immutable TradeDirection[string] TradeDirectionToStd;
    static immutable string[TradeDirection] StdToTradeDirection;

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

        StdToOrderType = OrderTypeToStd.reverse;
        StdToTradeDirection = TradeDirectionToStd.reverse;
    }

public /*properties*/:
    @property bool hasAddCandleListener(this T)() { return true; }

private:
    CombinedStreams _wsStreams;
    CandleListener[string] _candleListeners; /// Candle listeners by binance symbol
    WebSocket _currentWebSocket;
    Task _task;

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

    /// Refresh websocket connection with stream list.
    void _refreshWebSocket()
    {
        import std.array : join;
        import vibe.data.json;
        import std.format : formattedRead;

        // try to close current websocket
        /*
        try {
            if (_currentWebSocket !is null)
                _currentWebSocket.close();
        }
        catch (Exception e) {
            error(e.msg);
        }*/

        //_task = runTask({
            auto wsUrl = URL(WsEndpoint ~ "/" ~ _wsStreams.toString());
            info(wsUrl);
            auto ws = connectWebSocket(wsUrl);

            while (ws.waitForData())
            {
                auto text = ws.receiveText;
                auto response = parseJson(text);
                infof("%s", response);
            }
        //});

        _task.join();
        info("after");
        //_currentWebSocket = connectWebSocket(URL(url));

        /*, (scope WebSocket ws) {
            _currentWebSocket = ws;

            while(ws.connected) {
                string text = ws.receiveText();
                auto response = parseJson(text);


                string pair;
                string stream;
                resp.stream.formattedRead!"%s@%s"(pair, stream);

                if (stream == "depth")
                    if (pair in _candleListeners)
                        _candleListeners[pair](new Candlestick());

                info(text);

            }

            _currentWebSocket = null;
        });
        */
    }

public:
    this(Credentials credential, ExchangeConfiguration config = null)
    {
        super(credential, config);

        _wsStreams = new CombinedStreams();
    }

    void connect()
    {

    }

    override void _configure(ref Configuration config)
    {

    }

    override void addCandleListener(string symbol, CandlestickInterval interval, CandleListener listener)
    {
        _enforceSymbol(symbol);
        auto binanceSymbol = markets[symbol].id;

        _wsStreams.add(new CandlestickStream(binanceSymbol, interval));
        _candleListeners[binanceSymbol] = listener;
        _refreshWebSocket();
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
        enforceExchange(limit in DepthValidLimitByWeight, "Not a valid exchange limit " ~ limit.to!string);

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

    override void createLimitOrder(string symbol, TradeDirection side, TimeInForce timeInForce, float amount, float price)
    {
        _enforceSymbol(symbol);

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v3/order";

        endpoint.queryParams.add("symbol", markets[symbol].id);
        endpoint.queryParams.add("side", StdToTradeDirection[side]);
        endpoint.queryParams.add("type", "LIMIT");
        endpoint.queryParams.add("timeInForce", "GTC"); // Good Till Cancelled
        endpoint.queryParams.add("price", price.to!string);
        endpoint.queryParams.add("quantity", amount.to!string);

        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);
        // TODO: parse response
    }

    override void createMarketOrder(string symbol, TradeDirection side, float amount)
    {
        _enforceSymbol(symbol);

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v3/order";

        endpoint.queryParams.add("symbol", markets[symbol].id);
        endpoint.queryParams.add("side", StdToTradeDirection[side]);
        endpoint.queryParams.add("type", "LIMIT");
        endpoint.queryParams.add("quantity", amount.to!string);

        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);
        // TODO: parse response
    }

    override void createStopLossOrder(string symbol, TradeDirection side, float amount, float stopLoss)
    {
        _enforceSymbol(symbol);

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v3/order";

        endpoint.queryParams.add("symbol", markets[symbol].id);
        endpoint.queryParams.add("side", StdToTradeDirection[side]);
        endpoint.queryParams.add("type", "LIMIT");
        endpoint.queryParams.add("quantity", amount.to!string);
        endpoint.queryParams.add("stopPrice", stopLoss.to!string);

        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);
        // TODO: parse response
    }

    override void createStopLossLimitOrder(string symbol, TradeDirection side, TimeInForce timeInForce,float amount, float price, float stopLoss)
    {
        _enforceSymbol(symbol);

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v3/order";

        endpoint.queryParams.add("symbol", markets[symbol].id);
        endpoint.queryParams.add("side", StdToTradeDirection[side]);
        endpoint.queryParams.add("type", "LIMIT");
        endpoint.queryParams.add("timeInForce", "GTC"); // Good Till Cancelled
        endpoint.queryParams.add("price", price.to!string);
        endpoint.queryParams.add("quantity", amount.to!string);
        endpoint.queryParams.add("stopPrice", stopLoss.to!string);

        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);
        // TODO: parse response
    }

    override void createTakeProfitOrder(string symbol, TradeDirection side, float amount, float stopLoss)
    {
        _enforceSymbol(symbol);

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v3/order";

        endpoint.queryParams.add("symbol", markets[symbol].id);
        endpoint.queryParams.add("side", StdToTradeDirection[side]);
        endpoint.queryParams.add("type", "LIMIT");
        endpoint.queryParams.add("quantity", amount.to!string);
        endpoint.queryParams.add("stopPrice", stopLoss.to!string);

        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);
        // TODO: parse response
    }

    override void createTakeProfitLimitOrder(string symbol, TradeDirection side, TimeInForce timeInForce, float amount, float price, float stopLoss)
    {
        _enforceSymbol(symbol);

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v3/order";

        endpoint.queryParams.add("symbol", markets[symbol].id);
        endpoint.queryParams.add("side", StdToTradeDirection[side]);
        endpoint.queryParams.add("type", "LIMIT");
        endpoint.queryParams.add("timeInForce", "GTC"); // Good Till Cancelled
        endpoint.queryParams.add("price", price.to!string);
        endpoint.queryParams.add("quantity", amount.to!string);
        endpoint.queryParams.add("stopPrice", stopLoss.to!string);

        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);
        // TODO: parse response
    }

    override void createLimitMakerOrder(string symbol, TradeDirection side, float amount, float price)
    {
        _enforceSymbol(symbol);

        URLD endpoint = BaseUrl;
        endpoint.path = "/api/v3/order";

        endpoint.queryParams.add("symbol", markets[symbol].id);
        endpoint.queryParams.add("side", StdToTradeDirection[side]);
        endpoint.queryParams.add("type", "LIMIT");
        endpoint.queryParams.add("timeInForce", "GTC"); // Good Till Cancelled
        endpoint.queryParams.add("price", price.to!string);
        endpoint.queryParams.add("quantity", amount.to!string);

        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);
        // TODO: parse response
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
// Web Sockets Utils                                                                   //
/////////////////////////////////////////////////////////////////////////////////////////
/// Represents a combined stream.
/// Combined streams are accessed at:
///     stream?streams=<streamName1>/<streamName2>/<streamName3>
interface ICombinedStream
{
    string toString() const @safe;
}

/// The Aggregate Trade Streams push trade information that is aggregated
/// for a single taker order.
class AggregateTradeStream : ICombinedStream
{
    string symbol;

    this(string symbol)
    {
        this.symbol = symbol;
    }

    override string toString() const @safe
    {
        return format("%s@aggTrade", symbol);
    }
}

/// The Trade Streams push raw trade information; each trade has a unique
/// buyer and seller.
class TradeStream : AggregateTradeStream
{
    this(string symbol) { super(symbol); }

    override string toString() const @safe
    {
        return format("%s@trade", symbol);
    }
}

/// The Kline/Candlestick Stream push updates to the current klines/candlestick every second.
class CandlestickStream : AggregateTradeStream
{
    CandlestickInterval interval;

    this(string symbol, CandlestickInterval interval)
    {
        super(symbol);
        this.interval = interval;
    }

    override string toString() const @safe
    {
        return format("%s@kline_%s", symbol, Exchange.CandlestickIntervalToStr[interval]);
    }
}

/// 24hr Mini Ticker statistics for a single symbol pushed every second.
class IndividualSymbolMiniTickerStream : AggregateTradeStream
{
    this(string symbol) { super(symbol); }

    override string toString() const @safe
    {
        return format("%s@miniTicker", symbol);
    }
}

/// All Market Mini Tickers Stream.
class AllMarketMiniTickersStream : ICombinedStream
{
    override string toString() const @safe
    {
        return "!miniTicker@arr";
    }
}

/// 24hr Ticker statistics for a single symbol pushed every second.
class IndividualSymbolTickerStream : AggregateTradeStream
{
    this(string symbol) { super(symbol); }

    override string toString() const @safe
    {
        return format("%s@ticker", symbol);
    }
}

/// 24hr Ticker statistics for all symbols that changed in an array pushed every second.
class AllMarketTickersStream : ICombinedStream
{
    override string toString() const @safe
    {
        return "!ticker@arr";
    }
}

enum PartialBookDepth
{
    _5  = 5,
    _10 = 10,
    _20 = 20
}

/// Top <levels> bids and asks, pushed every second. Valid <levels> are 5, 10, or 20.
class PartialBookDepthStream : AggregateTradeStream
{
    PartialBookDepth depth;

    this(string symbol, PartialBookDepth depth)
    {
        super(symbol);
        this.depth = depth;
    }

    override string toString() const @safe
    {
        return format("%s@depth%d", symbol, cast(int) depth);
    }
}

class DiffDepthStream : AggregateTradeStream
{
    this(string symbol) { super(symbol); }

    override string toString() const @safe
    {
        return format("%s@depth", symbol);
    }
}

/// Combined streams are accessed at:
///     stream?streams=<streamName1>/<streamName2>/<streamName3>
final class CombinedStreams
{
private:
    const(ICombinedStream)[] _streams;

public:
    void add(in ICombinedStream stream)
    {
        _streams ~= stream;
    }

    override string toString() @safe
    {
        import std.array : join;

        string[] streamsStr;

        foreach(stream; _streams)
            streamsStr ~= stream.toString();

        return "stream?streams=" ~ streamsStr.join("/");
    }
}
