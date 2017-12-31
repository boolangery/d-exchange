
module Exchange;

import vibe.http.common;
import vibe.http.client;
import vibe.stream.operations;
import vibe.core.log;

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
    Represent a generic market.
*/
struct Markets {
    string id;
    string base;
    string quote;
    string symbol;
    bool active;
    Limits limits;
}

/**
    An improved url class.
*/
class Url{
    import vibe.inet.url;
    import std.array;

    private URL _url;
    public string[string] params;

    this(string url) {
        _url = URL.fromString(url);
        foreach (keyValue; _url.queryString.split("&")) {
            auto parts = keyValue.split("=");
            params[parts[0]] = parts[1];
        }
    }

    override string toString() {
        string newParams = "";
        foreach (key; params.keys)
            newParams ~= key ~ "=" ~ params[key] ~ "&";
        if (!newParams.empty) // pop back trailing &
            newParams.popBack();
        _url.queryString = newParams;
        return _url.toString();
    }

    unittest {
        Url url = new Url("https://bittrex.com/market/getopenorders?apikey=$apikey&nonce=$nonce");
        assert(url.params["apikey"] == "$apikey");
        assert(url.params["nonce"] == "$nonce");
        url.params["extra"] = "roll";
        assert(url.toString() == "https://bittrex.com/market/getopenorders?nonce=$nonce&apikey=$apikey&extra=roll");
    }
}

/**
    Represent api credentials.
*/
struct Credentials {
    string apiKey;
    string secretApiKey;
}

abstract class Exchange {
    public static enum Exchanges {
        Bittrex = "bittrex"
    }

    // Api properties
    public bool enableRateLimit = false;
    public int rateLimit = 2000;
    public int timeout = 10000;
    public bool verbose = false;
    public bool parseJsonResponse = true;
    public bool twofa = false;
    public bool hasPublicAPI = true;
    public bool hasPrivateAPI = true;
    public bool hasCORS = false;
    public bool hasFetchTicker = true;
    public bool hasFetchOrderBook = true;
    public bool hasFetchTrades = true;
    public bool hasFetchTickers = false;
    public bool hasFetchOHLCV = false;
    public bool hasDeposit = false;
    public bool hasWithdraw = false;
    public bool hasFetchBalance = true;
    public bool hasFetchOrder = false;
    public bool hasFetchOrders = false;
    public bool hasFetchOpenOrders = false;
    public bool hasFetchClosedOrders = false;
    public bool hasFetchMyTrades = false;
    public bool hasFetchCurrencies = false;
    struct RequiredCredentials {
        public bool apiKey;
        public bool secret;
        public bool uid;
        public bool login;
        public bool password;
    }
    RequiredCredentials requiredCredentials = {
        apiKey  : true,
        secret  : true,
        uid     : false,
        login   : false,
        password: false
    };
    // API method metainfo
    public struct Has {
        bool cancelOrder;
        bool createDepositAddress;
        bool createOrder;
        bool deposit;
        bool fetchBalance;
        bool fetchClosedOrders;
        bool etchCurrencies;
        bool fetchDepositAddress;
        bool fetchMarkets;
        bool fetchMyTrades;
        bool fetchOHLCV;
        bool fetchOpenOrders;
        bool fetchOrder;
        bool fetchOrderBook;
        bool fetchOrders;
        bool fetchTicker;
        bool fetchTickers;
        bool fetchTrades;
        bool withdraw;
    }
    public Has has = {
        cancelOrder: true,
        createDepositAddress: false,
        createOrder: true,
        deposit: false,
        fetchBalance: true,
        fetchClosedOrders: false,
        etchCurrencies: false,
        fetchDepositAddress: false,
        fetchMarkets: true,
        fetchMyTrades: false,
        fetchOHLCV: false,
        fetchOpenOrders: false,
        fetchOrder: false,
        fetchOrderBook: true,
        fetchOrders: false,
        fetchTicker: true,
        fetchTickers: false,
        fetchTrades: true,
        withdraw: false
    };
    public bool substituteCommonCurrencyCodes = true;
    public int lastRestRequestTimestamp = 0;
    public int lastRestPollTimestamp = 0;
    public bool restPollerLoopIsRunning = false;
    public int rateLimitTokens = 16;
    public int rateLimitMaxTokens = 16;
    public int rateLimitUpdateTime = 0;

    public Credentials credentials;

    /**
        Return an unix timestamp.
    */
    pragma(inline):
    protected long getUnixTimestamp() {
        import std.datetime;
        return Clock.currTime().toUnixTime();
    }

    /**
        Called before making the http request to sign the request
        if needed. Return the new url.
    */
    protected abstract void signRequest(Url currentUrl, out string[string] headers);

    /**
        Performs a synchronous HTTP request on the specified URL,
        using the specified method.
    */
    template jsonHttpRequest(T) if (is(T == class) | is(T == struct)) {
        protected T jsonHttpRequest(string url, HTTPMethod method, string[string] headers) {
            import vibe.data.serialization;
            import vibe.data.json;

            T data;
            Url eurl = new Url(url);
            this.signRequest(eurl, headers);

            requestHTTP(url,
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
}



