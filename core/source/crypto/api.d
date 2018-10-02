module crypto.api;

import vibe.http.client;
import vibe.stream.operations;
import vibe.core.log;
import std.typecons;
import std.container;
import url;

public enum RateType {PerMilis, PerSecond, PerMinute, PerHour}

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

interface IGenericResponse(T) {
    T toGeneric();
}

/**
    Represent a min/max amount.
*/
struct Amount {
    double min;
    double max;
}

/**
    Represent a min/max price.
*/
struct Price {
    double min;
    double max;
}

/**
    Represent market limits.
*/
struct Limits {
    Amount amount;
    Price price;
}

/**
    Represent a market precision.
*/
struct Precision {
    double amount;
    double price;
}

/**
    Represent api credentials.
*/
struct Credentials {
    string apiKey;
    string secretApiKey;
}

/**
    Generic api endpoint.
*/
interface IEndpoint {}

/**
    Represent a generic market.
*/
class Market {
    string id;
    string base;
    string quote;
    string symbol;
    bool active;
    double lot;
    Precision precision;
    Limits limits = {
        amount: {
            min: 0,
            max: double.max},
        price: {
            min: 0,
            max: double.max}
    };
}

interface IMarketEndpoint: IEndpoint {
    Array!Market fetchMarkets();
}

enum OrderBookType {Buy, Sell, Both}

/**
    Represent an order.
*/
class Order {
    double quantity;
    double rate;
}

/**
    Represent a generic order book.
*/
class OrderBook {
    OrderBookType type;
    Array!Order buyOrders;
    Array!Order sellOrders;
}

interface IOrderBookEndpoint: IEndpoint {
    OrderBook fetchOrderBook(string symbol, OrderBookType type);
}

/**
    Enumaration of known exchanges.
*/
public static enum Exchanges {
    Bittrex = "bittrex"
}

/**
    Api configuration.
*/
struct Configuration {
    string id;      // exchange unique id
    string name;    // display name
    string ver;     // api version
    int rateLimit = 36000;  // number or request per rateLimitType
    RateType rateLimitType; // rate limit type, limit per second, minute, hour..
    bool substituteCommonCurrencyCodes = true;
}

abstract class Exchange {
    protected Credentials _credentials;

    private CacheManager _cache;
    private Configuration _configuration;
    private RateLimitManager _rateManager;


    /**
        Constructor.
    */
    this(Credentials credential) {
        _credentials = credential;
        this.configure(this._configuration);
        _rateManager = new RateLimitManager(_configuration.rateLimitType, _configuration.rateLimit);
        _cache = new CacheManager(_rateManager);
    }

    /**
        Check if the api implements the endpoint.
        Exemple: bittrex.hasEndpoint!IFetchMarket()
    */
    public T hasEndpoint(T: IEndpoint)() {
        return (cast(T) this != null);
    }

    /**
        Cast the api in the type of the requested endpoint.
    */
    public T asEndpoint(T: IEndpoint)() {
        return (cast(T) this);
    }

    /**
        Configure the api.
    */
    protected abstract void configure(ref Configuration config);

    /**
        Return an unix timestamp.
    */
    pragma(inline):
    protected const long getUnixTimestamp() {
        import std.datetime;
        return Clock.currTime().toUnixTime();
    }

    /**
        Called before making the http request to sign the request
        if needed. Return the new url.
    */
    protected abstract const void signRequest(url.URL currentUrl, out string[string] headers);

    template jsonHttpRequest(T) if (is(T == class) | is(T == struct)) {
        /**
            Performs a synchronous HTTP request on the specified URL,
            using the specified method.
        */
        protected const T jsonHttpRequest(url.URL url, HTTPMethod method, string[string] headers=null) {
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
    }

    template jsonHttpRequestCached(T) if (is(T == class) | is(T == struct)) {
        /**
            Performs a synchronous HTTP request on the specified URL,
            using the specified method, if api limit rate not exceeded.
            If api limit rate is exceeded, it try to return cached data.
        */
        protected T jsonHttpRequestCached(url.URL url, HTTPMethod method, string[string] headers=null) {
            string cacheId = url.toString();
            if (_cache.isFresh(cacheId))
                return _cache.get!T(cacheId);
            else {
                T data = jsonHttpRequest!T(url, method, headers);
                _cache.set(cacheId, data);
                return data;
            }
        }
    }

    /**
        Used to convert a currency code to a common currency code.
    */
    protected const string commonCurrencyCode(string currency) {
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

    /**
        Load markets in cache.
    */
    protected const void loadMarkets(bool reload=false) {

    }
}



