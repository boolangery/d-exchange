module crypto.api;

import vibe.http.client;
import vibe.stream.operations;
import vibe.core.log;
import std.typecons;
import std.container;
import std.experimental.logger;

public import url : URLD = URL;
public import crypto.utils;
public import std.algorithm: canFind;
public import std.datetime : DateTime;
public import std.range.primitives : empty;
public import std.exception : enforce;

enum Exchanges
{
    bittrex = "bittrex"
}

public enum RateType {perMilis, perSecond, perMinute, perHour}

class ExchangeException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}

/** A class to manage api rate limit. */
class RateLimitManager
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
class CacheManager {
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

interface IGenericResponse(T)
{
    T toGeneric();
}

/** Represent a min/max range. */
struct Range
{
    double min;
    double max;
}

/** Market limits. */
struct Limits
{
    Range amount;
    Range price;
    Range cost;
}

/** Market precision. */
struct Precision
{
    int base;
    int quote;
    int amount;
    int price;
}

/** API credentials. */
struct Credentials
{
    string apiKey;
    string secretApiKey;
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
            max: double.max},
        price: {
            min: 0,
            max: double.max},
        cost: {
            min: 0,
            max: double.max}
    };

    /// Raw json response as returned by the API
    Json info;
}

/** Represent an order. */
struct Order
{
    double amount;
    double price;
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

/// Candlestick time interval.
enum CandlestickInterval
{
    _1m,    _3m,    _5m,    _15m,
    _30m,   _1h,    _2h,    _4h,
    _6h,    _8h,    _12h,   _1d,
    _3d,    _1w,    _1M
}

enum OrderType { undefined, market, limit }

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

class CurrencyBalance
{
    float free;
    float used;
    @property float total() { return free + used; }
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

interface IExchange
{
    @property bool initialized();
    @property Market[string] markets();
    @property Market[string] marketsById();
    @property string[] symbols();
    @property string[] exchangeIds();
    @property bool hasFetchOrderBook();
    @property bool hasFetchTicker();
    @property bool hasFetchOhlcv();
    @property bool hasFetchTrades();
    @property bool hasFetchBalance();

    void initialize();

    /// Fetch market informations.
    Market[] fetchMarkets();

    /// Fetch order book. Supported if hasFetchMarkets is true.
    OrderBook fetchOrderBook(string symbol, int limit);

    /// Fetch 24h ticker. Supported if hasFetchTicker is true.
    PriceTicker fetchTicker(string symbol);

    /// Fetch OHLCV data.
    Candlestick[] fetchOhlcv(string symbol, CandlestickInterval interval, int limit);

    Market[string] loadMarkets(bool reload=false);

    /// Fetch trade informations.
    Trade[] fetchTrades(string symbol, int limit);

    CurrencyBalance[string] fetchBalance(bool hideZero = true);
}

/** Base class for implementing a new exchange.
*/
abstract class Exchange : IExchange
{
    import vibe.data.json;

protected:
    Credentials _credentials;
    long _serverTime; /// Server unix timestamp
    long _timeDiffMs; /// Time difference in millis

private:
    CacheManager _cache;
    Configuration _configuration;
    RateLimitManager _rateManager;

    bool _initialized;
    Market[string] _markets; /// Markets by unified symbols
    Market[string] _marketsById; /// Markets by exchange id
    string[] _symbols;
    string[] _exchangeIds;
    immutable bool _hasFetchOrderBook;
    immutable bool _hasFetchTicker;
    immutable bool _hasFetchOhlcv;
    immutable bool _hasFetchTrades;
    immutable bool _hasFetchBalance;

public /*properties*/:
    @property bool initialized() { return _initialized; }
    @property Market[string] markets() { initialize(); return _markets; }
    @property Market[string] marketsById() { return _marketsById; }
    @property string[] symbols() { return _symbols; }
    @property string[] exchangeIds() { return _exchangeIds; }
    @property bool hasFetchOrderBook() { return _hasFetchOrderBook; }
    @property bool hasFetchTicker() { return _hasFetchTicker; }
    @property bool hasFetchOhlcv() { return _hasFetchOhlcv; }
    @property bool hasFetchTrades() { return _hasFetchTrades; }
    @property bool hasFetchBalance() { return _hasFetchBalance; }

public:
    /// Constructor.
    this(this T)(Credentials credential)
    {
        _hasFetchOrderBook = __traits(isOverrideFunction, T.fetchOrderBook);
        _hasFetchTicker = __traits(isOverrideFunction, T.fetchTicker);
        _hasFetchOhlcv = __traits(isOverrideFunction, T.fetchTicker);
        _hasFetchTrades = __traits(isOverrideFunction, T.fetchTrades);
        _hasFetchBalance = __traits(isOverrideFunction, T.fetchBalance);

        _credentials = credential;
        this.configure(this._configuration);
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
    Candlestick[] fetchOhlcv(string symbol, CandlestickInterval interval, int limit) { throw new ExchangeException("not supported"); }

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

protected:
    /// Configure the api.
    abstract void configure(ref Configuration config);

    /// Return an unix timestamp.
    pragma(inline) const long getUnixTimestamp() {
        import std.datetime;
        return Clock.currTime().toUnixTime();
    }

    /** Called before making the http request to sign the request.
    Request can be signed with header or by modifying the url */
    const void _signRequest(ref URLD url, out string[string] headers)
    {

    }

    /** Performs a synchronous HTTP request on the specified URL,
    using the specified method. */
    const Json jsonHttpRequest(URLD url, HTTPMethod method, string[string] headers=null)
    {
        Json data;
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
        return data;
    }

    /** Performs a synchronous HTTP request on the specified URL,
    using the specified method. */
    const T jsonHttpRequest(T)(URLD url, HTTPMethod method, string[string] headers=null)
    if (is(T == class) | is(T == struct)) {
        import vibe.data.serialization;
        import vibe.data.json;

        T data;
        this._signRequest(url, headers);
        logDebug(url.toString());

        requestHTTP(url.toString(),
            (scope HTTPClientRequest req) {
                req.method = method;
                foreach (header; headers.keys)
                    req.headers[header] = headers[header];
                // req.writeJsonBody(["name": "My Name"]);
            },
            (scope HTTPClientResponse res) {
                string json = res.bodyReader.readAllUTF8();
                data = deserializeJson!T(json);
            }
        );
        return data;
    }

    /** Performs a synchronous HTTP request on the specified URL,
    using the specified method, if api limit rate not exceeded.
    If api limit rate is exceeded, it try to return cached data. */
    protected T jsonHttpRequestCached(T)(URLD url, HTTPMethod method, string[string] headers=null)
    if (is(T == class) | is(T == struct)) {
        string cacheId = url.toString();
        if (_cache.isFresh(cacheId))
            return _cache.get!T(cacheId);
        else {
            T data = jsonHttpRequest!T(url, method, headers);
            _cache.set(cacheId, data);
            return data;
        }
    }

    /// Used to convert a currency code to a common currency code.
    const string commonCurrencyCode(string currency) {
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
    const int precisionFromString(string s)
    {
        import std.string : strip, split;

        auto parts = strip(s, "", "0").split('.');

        if (parts.length > 1)
            return cast(int) parts[1].length;
        else
            return 0;
    }

    /// Ensure symbol existance is a generic cay.
    void enforceSymbol(string symbol)
    {
        enforce!ExchangeException(symbol in markets, "No market symbol " ~ symbol);
    }

    string _candlestickIntervalToStr(CandlestickInterval interval)
    {
        final switch (interval) {
            case CandlestickInterval._1m:   return "1m";
            case CandlestickInterval._3m:   return "3m";
            case CandlestickInterval._5m:   return "5m";
            case CandlestickInterval._15m:  return "15m";
            case CandlestickInterval._30m:  return "30m";
            case CandlestickInterval._1h:   return "1h";
            case CandlestickInterval._2h:   return "2h";
            case CandlestickInterval._4h:   return "4h";
            case CandlestickInterval._6h:   return "6h";
            case CandlestickInterval._8h:   return "8h";
            case CandlestickInterval._12h:  return "12h";
            case CandlestickInterval._1d:   return "1d";
            case CandlestickInterval._3d:   return "3d";
            case CandlestickInterval._1w:   return "1w";
            case CandlestickInterval._1M:   return "1M";
        }
    }

    abstract long _fetchServerMillisTimestamp();

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
