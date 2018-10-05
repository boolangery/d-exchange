module crypto.api;

import vibe.http.client;
import vibe.stream.operations;
import vibe.core.log;
import std.typecons;
import std.container;

public import url : URLD = URL;
public import crypto.utils;
public import std.algorithm: canFind;
public import std.datetime : DateTime;

public enum RateType {PerMilis, PerSecond, PerMinute, PerHour}

class ExchangeException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}

/**
    A class to manage api rate limit.
*/
class RateLimitManager {
    import std.datetime;

    private RateType _type;
    private MonoTime _lastRequest;
    private Duration _rate;

    this(RateType type, int rateLimit) {
        _type = type;
        final switch (type)
        {
            case RateType.PerMilis:
                _rate = dur!"msecs"(1) / rateLimit;
                break;

            case RateType.PerSecond:
                _rate = dur!"seconds"(1) / rateLimit;
                break;

            case RateType.PerMinute:
                _rate = dur!"minutes"(1) / rateLimit;
                break;

            case RateType.PerHour:
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

        auto rmm = new RateLimitManager(RateType.PerMilis, 4);
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

/**
    A class to manage api cache.
*/
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

/** Represent a min/max range.*/
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

/** Enumaration of known exchanges. */
static enum Exchanges
{
    Bittrex = "bittrex"
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

/** Api configuration. */
struct Configuration
{
    string id;      // exchange unique id
    string name;    // display name
    string ver;     // api version
    int rateLimit = 36000;  // number or request per rateLimitType
    RateType rateLimitType; // rate limit type, limit per second, minute, hour..
    bool substituteCommonCurrencyCodes = true;
}

/** Base class for implementing a new exchange.
*/
abstract class Exchange
{
    import vibe.data.json;

protected:
    Credentials _credentials;

private:
    CacheManager _cache;
    Configuration _configuration;
    RateLimitManager _rateManager;

    Market[string] _markets; /// Markets by unified symbols
    Market[string] _marketsById; /// Markets by exchange id
    string[] _symbols;
    string[] _exchangeIds;

public /*properties*/:
    @property auto markets()
    {
        loadMarkets();
        return _markets;
    }

    @property auto marketsById() { return _marketsById; }
    @property auto symbols() { return _symbols; }
    @property auto exchangeIds() { return _exchangeIds; }

    immutable bool hasFetchMarkets;
    immutable bool hasFetchOrderBook;
    immutable bool hasFetchTicker;

public:
    /// Constructor.
    this(this T)(Credentials credential)
    {
        hasFetchMarkets = __traits(isOverrideFunction, T.fetchMarkets);
        hasFetchOrderBook = __traits(isOverrideFunction, T.fetchOrderBook);
        hasFetchTicker = __traits(isOverrideFunction, T.fetchTicker);

        _credentials = credential;
        this.configure(this._configuration);
        _rateManager = new RateLimitManager(_configuration.rateLimitType, _configuration.rateLimit);
        _cache = new CacheManager(_rateManager);
    }

    abstract Market[] fetchMarkets();
    OrderBook fetchOrderBook(string symbol, int limit) { return null; }
    PriceTicker fetchTicker(string symbol) { return null; }

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

protected:
    /// Configure the api.
    abstract void configure(ref Configuration config);

    /// Return an unix timestamp.
    pragma(inline) const long getUnixTimestamp() {
        import std.datetime;
        return Clock.currTime().toUnixTime();
    }

    /** Called before making the http request to sign the request
    if needed. Return the new url. */
    const void signRequest(URLD currentUrl, out string[string] headers)
    {

    }

    /** Performs a synchronous HTTP request on the specified URL,
    using the specified method. */
    const Json jsonHttpRequest(URLD url, HTTPMethod method, string[string] headers=null)
    {
        Json data;
        this.signRequest(url, headers);
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
        this.signRequest(url, headers);
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
