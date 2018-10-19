/**
    Exchange api core.

    It contains unified exchange objects and allow to implement new
    exchanges based on this model.
*/
module crypto.exchanges.core.api;

import vibe.http.client;
import vibe.stream.operations;
import vibe.core.log;
import std.typecons;
import std.container;

public import crypto.exchanges.core.exceptions;
public import crypto.exchanges.core.utils;
public import std.experimental.logger;
public import url : URLD = URL, parseURL;
public import std.algorithm: canFind;
public import std.datetime : DateTime;
public import std.range.primitives : empty;
public import std.exception : enforce;
public import std.typecons : Nullable;
public import std.string : format;
/// Concurrency
public import vibe.core.core : Task, runTask;


enum RateType {perMilis, perSecond, perMinute, perHour}


/** A class to manage api rate limit. */
private class RateLimitManager
{
    import std.datetime;

    private RateType _type;
    private MonoTime _lastRequest;
    private Duration _rate;

    this(RateType type, int rateLimit) {
        _type = type;
        final switch (type)
        {
            case RateType.perMilis:
                _rate = dur!"msecs"(1) / rateLimit;
                break;

            case RateType.perSecond:
                _rate = dur!"seconds"(1) / rateLimit;
                break;

            case RateType.perMinute:
                _rate = dur!"minutes"(1) / rateLimit;
                break;

            case RateType.perHour:
                _rate = dur!"hours"(1) / rateLimit;
                break;
        }
    }

    /**
        Add a request to this rate limit manager.
    */
    void addRequest() {
        _lastRequest = MonoTime.currTime;
    }

    /**
        Check if the theoretically rate limit is excedded.
    */
    const bool isLimitExceeded() {
        return ((MonoTime.currTime - _lastRequest) < _rate);
    }

    unittest {
        import core.thread: Thread;

        auto rmm = new RateLimitManager(RateType.perMilis, 4);
        rmm.addRequest();
        Thread.sleep(dur!("usecs")(250));
        assert(!rmm.isLimitExceeded());
        rmm.addRequest();
        Thread.sleep(dur!("usecs")(250));
        assert(!rmm.isLimitExceeded());
        rmm.addRequest();
        Thread.sleep(dur!("usecs")(250));
        assert(!rmm.isLimitExceeded());
        rmm.addRequest();
        Thread.sleep(dur!("usecs")(250));
        assert(!rmm.isLimitExceeded());

        rmm.addRequest();
        rmm.addRequest();
        assert(rmm.isLimitExceeded());
    }
}

/** A class to manage api cache. */
private class CacheManager
{
    private Object[string] _cache;
    private RateLimitManager _manager;

    this(RateLimitManager manager) {
        _manager = manager;
    }

    bool isFresh(string key) {
        return (key in _cache) && !_manager.isLimitExceeded();
    }

    T get(T)(string key) {
        return cast(T) _cache[key];
    }

    void set(string key, Object data) {
        _cache[key] = data;
        _manager.addRequest();
    }
}

/** Represent a price range. */
struct Range
{
    float min;  /// The minimum value
    float max; /// The maximum value
}

/** Market limits. */
struct Limits
{
    Range amount;
    Range price;
    Range cost;
}

/** Define a market precision in digits. */
struct Precision
{
    int base; /// Precision of base currency
    int quote; /// Precision of quote currency
    int amount; /// Amount precision
    int price; /// Price precision
}

/** Exchange configuration. */
class ExchangeConfiguration
{
    /// specify the number of milliseconds after timestamp the request is valid for.
    long recvWindow;
}

/** API credentials. */
struct Credentials
{
    string apiKey; /// Public API key
    string secretApiKey; /// Secret API key
}

/** Represent a generic market. */
class Market
{
    /** The string or numeric ID of the market or trade instrument within the exchange.
    Market ids are used inside exchanges internally to identify trading pairs during the
    request/response process. */
    string id;

    /** An uppercase string code representation of a particular trading pair or instrument.
    This is usually written as BaseCurrency/QuoteCurrency with a slash as in BTC/USD, LTC/CNY or ETH/EUR, etc. */
    @property string symbol()
    {
        return base ~ '/' ~ quote;
    }

    /// uppercase string, base currency, 3 or more letters
    string base;

    /// uppercase string, quote currency, 3 or more letters
    string quote;

    /// A boolean indicating whether or not trading this market is currently possible.
    bool active;

    /** The amounts of decimal digits accepted in order values by exchanges upon order placement for price,
    amount and cost. */
    Precision precision;

    /// The minimums and maximums for prices, amounts (volumes) and costs (where cost = price * amount).
    Limits limits = {
        amount: {
            min: 0,
            max: float.max},
        price: {
            min: 0,
            max: float.max},
        cost: {
            min: 0,
            max: float.max}
    };

    /// Raw json response as returned by the API
    Json info;
}

/** Represent an order. */
struct Order
{
    float amount;
    float price;
}

/** Represent a generic order book. */
class OrderBook
{
    Order[] bids;
    Order[] asks;
    long timestamp;
    DateTime datetime;
}

/** A price ticker contains statistics for a particular market/symbol for
some period of time in recent past, usually last 24 hours. */
class PriceTicker
{
    string symbol;      /// symbol of the market ('BTC/USD', 'ETH/BTC', ...)
    Json info;          /// raw exchange json
    long timestamp;     /// (64-bit Unix Timestamp in milliseconds since Epoch 1 Jan 1970)
    DateTime datetime;  /// ISO8601 datetime string with milliseconds
    float high;         /// highest price
    float low;          /// lowest price
    float bid;          /// current best bid (buy) price
    float bidVolume;    /// current best bid (buy) amount (may be missing or undefined)
    float ask;          /// current best ask (sell) price
    float askVolume;    /// current best ask (sell) amount (may be missing or undefined)
    float vwap;         /// volume weighed average price
    float open;         /// opening price
    float close;        /// price of last trade (closing price for current period)
    float last;         /// same as `close`, duplicated for convenience
    float previousClose;/// closing price for the previous period
    float change;       /// absolute change, `last - open`
    float percentage;   /// relative change, `(change/open) * 100`
    float average;      /// average price, `(last + open) / 2`
    float baseVolume;   /// volume of base currency traded for last 24 hours
    float quoteVolume;  /// volume of quote currency traded for last 24 hours
}

/// OHLCV data.
class Candlestick
{
public:
    long timestamp; /// UTC timestamp in milliseconds, integer
    float open;     /// (O)pen price, float
    float high;     /// (H)ighest price, float
    float low;      /// (L)owest price, float
    float close;    /// (C)losing price, float
    float volume;   /// (V)olume (in terms of the base currency), float

    bool isIncreasing()
    {
        return close > open;
    }

    bool isDecreasing()
    {
        return close < open;
    }
}

alias CandleListener = void delegate(scope Candlestick) @safe;

/// Candlestick time interval.
enum CandlestickInterval
{
    _1m,    _3m,    _5m,    _15m,
    _30m,   _1h,    _2h,    _4h,
    _6h,    _8h,    _12h,   _1d,
    _3d,    _1w,    _1M
}

/// Define an order type.
enum OrderType
{
    undefined, /// Order type if undefined
    /// A market order is a buy or sell order to be executed immediately at current market prices.
    market,
    /** A limit order is an order to buy a security at no more than a specific price,
    or to sell a security at no less than a specific price (called "or better" for either
    direction). */
    limit,
    /** A stop order, also referred to as a stop-loss order, is an order to buy or sell
    a stock once the price of the stock reaches a specified price, known as the stop price.
    When the stop price is reached, a stop order becomes a market order. */
    stopLoss,
    /** A stop–limit order is an order to buy or sell a stock that combines the features of
    a stop order and a limit order.  */
    stopLossLimit,
    /** A take-profit order (T/P) is a type of limit order that specifies the exact price
    at which to close out an open position for a profit. */
    takeProfit,
    /** Triggers a limit order (buy or sell) when the last price hits the profit price. */
    takeProfitLimit,
    /** If you place a buy order at a price below all of the pending sell orders, it will
     be pending. */
    limitMaker
}


enum TradeDirection { buy, sell }

/// Trade infos.
class Trade
{
     Json info;           /// the original decoded JSON as is
     string id;           /// string trade id
     long timestamp;      /// Unix timestamp in milliseconds
     DateTime datetime;   /// ISO8601 datetime with milliseconds
     string symbol;       /// symbol
     string order;        /// string order id or undefined/None/null
     OrderType type;      /// order type, 'market', 'limit' or undefined/None/null
     TradeDirection side; /// direction of the trade, 'buy' or 'sell'
     float price;         /// float price in quote currency
     float amount;        /// amount of base currency
}

/** Represents a currency balance. */
class CurrencyBalance
{
    float free; /// Available balance
    float used; /// Used or locked balance.
    /// Total balance.
    @property float total() { return free + used; }
}

class FullOrder
{
    string id; /// order unique id
    DateTime datetime; /// ISO8601 datetime of 'timestamp' with milliseconds
    long timestamp; /// order placing/opening Unix timestamp in milliseconds
    long lastTradeTimestamp; /// Unix timestamp of the most recent trade on this order
    OrderStatus status;
    string symbol;
    OrderType type;
    TradeDirection side;
    float price; /// float price in quote currency
    float amount; /// ordered amount of base currency
    float filled; /// filled amount of base currency
    @property float remaining() { return amount - filled; } /// remaining amount to fill
    float cost; /// 'filled' * 'price' (filling price used where available)
    Trade[] trades; /// a list of order trades/executions
    OrderFee fee; /// fee info, if available
    Json info; /// the original unparsed order structure as is
}

/// Define an order status.
enum OrderStatus { open, closed, canceled };

/// Order fee.
class OrderFee
{
    string currency; /// which currency the fee is (usually quote)
    float cost; /// the fee amount in that currency
    float rate; /// the fee rate (if available)
}

/** Api configuration. */
struct Configuration
{
    string id;      /// exchange unique id
    string name;    /// display name
    string ver;     /// api version
    int rateLimit = 36000;  /// number or request per rateLimitType
    RateType rateLimitType; /// rate limit type, limit per second, minute, hour..
    bool substituteCommonCurrencyCodes = true;
}

enum TimeInForce
{
    goodTillCancelled,
    gtc = goodTillCancelled,
}


/** Represents the unified exchange API.

Symbols And Market Ids:
    Market ids are used during the REST request-response process to reference trading pairs
    within exchanges. The set of market ids is unique per exchange and cannot be used across
    exchanges. For example, the BTC/USD pair/market may have different ids on various popular
    exchanges, like btcusd, BTCUSD, XBTUSD, btc/usd, 42 (numeric id), BTC/USD, Btc/Usd,
    tBTCUSD, XXBTZUSD. You don't need to remember or use market ids, they are there for
    internal HTTP request-response purposes inside exchange implementations.

    The library abstracts uncommon market ids to symbols, standardized to a common format.
    Symbols aren't the same as market ids. Every market is referenced by a corresponding symbol.
    Symbols are common across exchanges which makes them suitable for arbitrage and many other
    things.

    A symbol is usually an uppercase string literal name for a pair of traded currencies
    with a slash in between. A currency is a code of three or four uppercase letters,
    like BTC, ETH, USD, GBP, CNY, LTC, JPY, DOGE, RUB, ZEC, XRP, XMR, etc. Some exchanges
    have exotic currencies with longer names. The first currency before the slash is usually
    called base currency, and the one after the slash is called quote currency. Examples of
    a symbol are: BTC/USD, DOGE/LTC, ETH/EUR, DASH/XRP, BTC/CNY, ZEC/XMR, ETH/JPY.
*/
interface IExchange
{
    import std.traits : EnumMembers;

    /** Is the exhange inititialized ?
    You can call initialize() to force exchange initialization or it will be initialized
    automaticaly when needed. */
    @property bool initialized();
    /// Markets indexed by unified symbol.
    @property Market[string] markets();
    /// Markets indexed by exchange id.
    @property Market[string] marketsById();
    /// Available exchange symbols.
    @property string[] symbols();
    /// Exchange ids.
    @property string[] exchangeIds();
    @property bool hasFetchOrderBook();  /// Is `fetchOrderBook` supported ?
    @property bool hasFetchTicker();     /// Is `fetchTicker` supported ?
    @property bool hasFetchOhlcv();      /// Is `fetchOhlcv` supported ?
    @property bool hasFetchTrades();     /// Is `fetchTrades` supported ?
    @property bool hasFetchBalance();    /// Is `fetchBalance` supported ?
    @property bool hasFetchOpenOrders(); /// Is `fetchOpenOrders` supported ?
    @property bool hasCreateOrder(OrderType type)(); /// Is this order type supported ?
    @property bool hasAddCandleListener();

    alias hasCreateLimitOrder = hasCreateOrder!(OrderType.limit);
    alias hasCreateMarketOrder = hasCreateOrder!(OrderType.market);
    alias hasCreateStopLossOrder = hasCreateOrder!(OrderType.stopLoss);
    alias hasCreateStopLossLimitOrder = hasCreateOrder!(OrderType.stopLossLimit);
    alias hasCreateTakeProfitOrder = hasCreateOrder!(OrderType.takeProfit);
    alias hasCreateTakeProfitLimitOrder = hasCreateOrder!(OrderType.takeProfitLimit);
    alias hasCreateLimitMakerOrder = hasCreateOrder!(OrderType.limitMaker);

    void initialize();

    /** Fetches a list of all available markets from an exchange and returns an array of
    markets (objects with properties such as symbol, base, quote etc.).
    Some exchanges do not have means for obtaining a list of markets via their online API. */
    Market[] fetchMarkets();

    /** Exchanges expose information on open orders with bid (buy) and ask (sell) prices,
    volumes and other data. Usually there is a separate endpoint for querying current state
    (stack frame) of the order book for a particular market. An order book is also often
    called market depth. The order book information is used in the trading decision making
    process.
    Supported if `hasFetchOrderBook` is true. */
    OrderBook fetchOrderBook(string symbol, int limit);

    /** Fetch latest ticker data by trading symbol.
    Supported if `hasFetchTicker` is true. */
    PriceTicker fetchTicker(string symbol);

    /** Fetch OHLCV data.
    Supported if `hasFetchOhlcv` is true. */
    Candlestick[] fetchOhlcv(string symbol, CandlestickInterval interval, DateTime from, DateTime to, int limit);

    /** Returns the list of markets as an object indexed by symbol and caches it with the
    exchange instance. Returns cached markets if loaded already, unless the reload = true f
    lag is forced. */
    Market[string] loadMarkets(bool reload=false);

    /** Fetch trade informations.
    Supported if `hasFetchTrades` is true. */
    Trade[] fetchTrades(string symbol, int limit);

    /** Fetch account Balance.
    Supported if `hasFetchBalance` is true. */
    CurrencyBalance[string] fetchBalance(bool hideZero = true);

    /** Fetch account open orders
    Supported if `hasFetchOpenOrders` is true. */
    FullOrder[] fetchOpenOrders(string symbol);

    /// Create a limit order.
    void createLimitOrder(string symbol, TradeDirection side, TimeInForce timeInForce, float amount, float price);

    /// Create a market order.
    void createMarketOrder(string symbol, TradeDirection side, float amount);

    /// Create a stop loss order.
    void createStopLossOrder(string symbol, TradeDirection side, float amount, float stopLoss);

    /// Create a stop loss limit order.
    void createStopLossLimitOrder(string symbol, TradeDirection side, TimeInForce timeInForce,
        float amount, float price, float stopLoss);

    /// Create take profit order.
    void createTakeProfitOrder(string symbol, TradeDirection side, float amount, float stopLoss);

    /// Create take profit limit order.
    void createTakeProfitLimitOrder(string symbol, TradeDirection side, TimeInForce timeInForce, float amount,
        float price, float stopLoss);

    /// Create limit market order.
    void createLimitMakerOrder(string symbol, TradeDirection side, float amount, float price);

    /// A a candlestick listener.
    void addCandleListener(string symbol, CandlestickInterval interval, CandleListener listener);
}

/** Base class for implementing a new exchange.
*/
abstract class Exchange : IExchange
{
    public import vibe.http.client : HTTPMethod;
    import vibe.data.json;

protected:
    Credentials _credentials;
    Nullable!ExchangeConfiguration _userConfig;
    long _serverTime; /// Server unix timestamp
    long _timeDiffMs; /// Time difference in millis

    alias enforceExchange = enforce!ExchangeException;

private:
    CacheManager _cache;
    Configuration _configuration;
    RateLimitManager _rateManager;

    bool _initialized;
    Market[string] _markets; /// Markets by unified symbols
    Market[string] _marketsById; /// Markets by exchange id
    string[] _symbols;
    string[] _exchangeIds;

    immutable bool[string] _has;
    immutable bool[OrderType] _hasOrder;

public /*properties*/:
    @property bool initialized() { return _initialized; }
    @property Market[string] markets() { initialize(); return _markets; }
    @property Market[string] marketsById() { return _marketsById; }
    @property string[] symbols() { return _symbols; }
    @property string[] exchangeIds() { return _exchangeIds; }

    @property bool hasFetchOrderBook()    { return _has["fetchOrderBook"]; }
    @property bool hasFetchTicker()       { return _has["fetchTicker"]; }
    @property bool hasFetchOhlcv()        { return _has["fetchTicker"]; }
    @property bool hasFetchTrades()       { return _has["fetchTrades"]; }
    @property bool hasFetchBalance()      { return _has["fetchBalance"]; }
    @property bool hasFetchOpenOrders()   { return _has["fetchOpenOrders"]; }
    @property bool hasAddCandleListener() { return _has["addCandleListener"]; }
    @property bool hasCreateOrder(OrderType type)() { return _hasOrder[type]; }

    // public constants
    static immutable string[CandlestickInterval] CandlestickIntervalToStr;

public:
    /// Constructor.
    this(this T)(Credentials credential, ExchangeConfiguration config = null)
    {
        // fill features:
        _has = [
            "fetchOrderBook":       __traits(isOverrideFunction, T.fetchOrderBook),
            "fetchTicker":          __traits(isOverrideFunction, T.fetchTicker),
            "fetchOhlcv":           __traits(isOverrideFunction, T.fetchTicker),
            "fetchTrades":          __traits(isOverrideFunction, T.fetchTrades),
            "fetchBalance":         __traits(isOverrideFunction, T.fetchBalance),
            "fetchOpenOrders":      __traits(isOverrideFunction, T.fetchOpenOrders),
            "addCandleListener":    __traits(isOverrideFunction, T.addCandleListener),
        ];
        _hasOrder = [
            OrderType.market:          __traits(isOverrideFunction, T.createMarketOrder),
            OrderType.limit:           __traits(isOverrideFunction, T.createLimitOrder),
            OrderType.stopLoss:        __traits(isOverrideFunction, T.createStopLossOrder),
            OrderType.stopLossLimit:   __traits(isOverrideFunction, T.createStopLossLimitOrder),
            OrderType.takeProfit:      __traits(isOverrideFunction, T.createTakeProfitOrder),
            OrderType.takeProfitLimit: __traits(isOverrideFunction, T.createTakeProfitLimitOrder),
            OrderType.limitMaker:      __traits(isOverrideFunction, T.createLimitMakerOrder),
        ];

        _credentials = credential;

        if (config is null)
            _userConfig = Nullable!ExchangeConfiguration.init;
        else
            _userConfig = config;

        this._configure(this._configuration);
        _rateManager = new RateLimitManager(_configuration.rateLimitType, _configuration.rateLimit);
        _cache = new CacheManager(_rateManager);
    }

    void initialize()
    {
        if (_initialized) return;

        _serverTime = _fetchServerMillisTimestamp();
        _timeDiffMs = getMillisTimestamp() - _serverTime;

        loadMarkets();

        _initialized = true;
    }

    /// Retrieve market informations.
    abstract Market[] fetchMarkets();

    /// Fetch order book. Supported if hasFetchMarkets is true.
    OrderBook fetchOrderBook(string symbol, int limit) { throw new ExchangeException("not supported"); }

    /// Fetch 24h ticker. Supported if hasFetchTicker is true.
    PriceTicker fetchTicker(string symbol) { throw new ExchangeException("not supported"); }

    // Fetch OHLCV data.
    Candlestick[] fetchOhlcv(string symbol, CandlestickInterval interval, DateTime from, DateTime to, int limit) { throw new ExchangeException("not supported"); }

    Trade[] fetchTrades(string symbol, int limit) { throw new ExchangeException("not supported"); }

    Market[string] loadMarkets(bool reload=false)
    {
        if (!reload) {
            if (!_markets.empty) {
                return _markets;
            }
        }

        auto markets = fetchMarkets();
        // _currencies.clear();
        // if self.has['fetchCurrencies']:
        //     currencies = self.fetch_currencies()
        return _setMarkets(markets);
    }

    CurrencyBalance[string] fetchBalance(bool hideZero = true) { throw new ExchangeException("not supported"); }

    FullOrder[] fetchOpenOrders(string symbol) { throw new ExchangeException("not supported"); }

    void createLimitOrder(string symbol, TradeDirection side, TimeInForce timeInForce, float amount, float price)  { throw new ExchangeException("not supported"); }
    void createMarketOrder(string symbol, TradeDirection side, float amount)  { throw new ExchangeException("not supported"); }
    void createStopLossOrder(string symbol, TradeDirection side, float amount, float stopLoss)  { throw new ExchangeException("not supported"); }
    void createStopLossLimitOrder(string symbol, TradeDirection side, TimeInForce timeInForce,float amount, float price, float stopLoss)  { throw new ExchangeException("not supported"); }
    void createTakeProfitOrder(string symbol, TradeDirection side, float amount, float stopLoss)  { throw new ExchangeException("not supported"); }
    void createTakeProfitLimitOrder(string symbol, TradeDirection side, TimeInForce timeInForce, float amount, float price, float stopLoss)  { throw new ExchangeException("not supported"); }
    void createLimitMakerOrder(string symbol, TradeDirection side, float amount, float price) { throw new ExchangeException("not supported"); }

    void addCandleListener(string symbol, CandlestickInterval interval, CandleListener listener) { throw new ExchangeException("not supported"); }

protected:
    /// Static constructor.
    static this()
    {
        CandlestickIntervalToStr = [
            CandlestickInterval._1m:  "1m",
            CandlestickInterval._3m:  "3m",
            CandlestickInterval._5m:  "5m",
            CandlestickInterval._15m: "15m",
            CandlestickInterval._30m: "30m",
            CandlestickInterval._1h:  "1h",
            CandlestickInterval._2h:  "2h",
            CandlestickInterval._4h:  "4h",
            CandlestickInterval._6h:  "6h",
            CandlestickInterval._8h:  "8h",
            CandlestickInterval._12h: "12h",
            CandlestickInterval._1d:  "1d",
            CandlestickInterval._3d:  "3d",
            CandlestickInterval._1w:  "1w",
            CandlestickInterval._1M:  "1M"
        ];
    }

    /// Configure the api.
    abstract void _configure(ref Configuration config);

    /// Return an unix timestamp.
    pragma(inline) long _getUnixTimestamp() const
    {
        import std.datetime;
        return Clock.currTime().toUnixTime();
    }

    /** Called before making the http request to sign the request.
    Request can be signed with header or by modifying the url */
    void _signRequest(ref URLD url, out string[string] headers) const @safe
    {
        // do nothing
    }

    /** Performs a synchronous HTTP request on the specified URL,
    using the specified method. */
    Json _jsonHttpRequest(URLD url, HTTPMethod method, string[string] headers=null) const @safe
    {
        Json data;

        try {
            info(url.toString);
            this._signRequest(url, headers);
            logDebug(url.toString());

            requestHTTP(url.toString(),
                (scope HTTPClientRequest req) {
                    req.method = method;
                    foreach (header; headers.keys)
                        req.headers[header] = headers[header];
                },
                (scope HTTPClientResponse res) {
                    string jsonString = res.bodyReader.readAllUTF8();
                    data = parseJson(jsonString);
                }
            );
        }
        catch (JSONException e) {
            throw new InvalidResponseException(e.msg);
        }
        catch (Exception e) {
            throw new ExchangeException(e.msg);
        }

        _enforceNoError(data);
        return data;
    }

    /** Performs a synchronous HTTP request on the specified URL,
    using the specified method. */
    T _jsonHttpRequest(T)(URLD url, HTTPMethod method, string[string] headers=null) const @safe
    if (is(T == class) | is(T == struct)) {
        import vibe.data.serialization;

        return deserializeJson!T(_jsonHttpRequest(url, method, headers));
    }

    /** Performs a synchronous HTTP request on the specified URL,
    using the specified method, if api limit rate not exceeded.
    If api limit rate is exceeded, it try to return cached data. */
    protected T _jsonHttpRequestCached(T)(URLD url, HTTPMethod method, string[string] headers=null) @safe
    if (is(T == class) | is(T == struct)) {
        string cacheId = url.toString();
        if (_cache.isFresh(cacheId))
            return _cache.get!T(cacheId);
        else {
            T data = _jsonHttpRequest!T(url, method, headers);
            _cache.set(cacheId, data);
            return data;
        }
    }

    /// Used to convert a currency code to a common currency code.
    string _commonCurrencyCode(string currency) const
    {
        enum COMMON = [
            "XBT": "BTC",
            "BCC": "BCH",
            "DRK": "DASH"
        ];
        if (this._configuration.substituteCommonCurrencyCodes) {
            if (currency in COMMON)
                return COMMON[currency];
        }
        return currency;
    }

    /** Return a precision from a string.
    Exemple: with an input of "0.01000", it return 2. */
    int _precisionFromString(string s) const
    {
        import std.string : strip, split;

        auto parts = strip(s, "", "0").split('.');

        if (parts.length > 1)
            return cast(int) parts[1].length;
        else
            return 0;
    }

    /// Ensure symbol existance is a generic cay.
    void _enforceSymbol(string symbol)
    {
        enforceExchange(symbol in markets, "No market symbol " ~ symbol);
    }

    string _candlestickIntervalToStr(CandlestickInterval interval) const
    {
        return CandlestickIntervalToStr[interval];
    }

    long _fetchServerMillisTimestamp() @safe { return getMillisTimestamp(); }

    /** Ensure no error in a json response.
    It throw exception depending of the error code. */
    void _enforceNoError(in Json response) @safe const
    {
        // do nothing
    }

    final Market _findMarket(string marketId)
    {
        initialize();

        if (marketId in _markets)
            return _markets[marketId];
        if (marketId in _marketsById)
            return _marketsById[marketId];
        return null;
    }

    final string _findSymbol(string echangeSymbol, Market market = null)
    {
        if (market is null)
            market = _findMarket(echangeSymbol);
        return market.symbol;
    }

private:
    /// Load markets in cache.
    Market[string] _setMarkets(Market[] markets)
    {
        _markets = markets.indexBy!"symbol";
        _marketsById = markets.indexBy!"id";
        _symbols = _markets.keys();
        _exchangeIds = _marketsById.keys();
        return _markets;
    }
}

///
unittest
{
    class MyExchange : Exchange
    {
        this(Credentials credential, ExchangeConfiguration config = null)
        {
            super(credential, config);
        }
        override Market[] fetchMarkets() { return null; }
        override void _configure(ref Configuration config) {}
        override Trade[] fetchTrades(string symbol, int limit) { return null; }
    }

    Credentials credential;
    IExchange exchange = new MyExchange(credential);

    assert(!exchange.hasFetchOhlcv);
    assert(exchange.hasFetchTrades);
}