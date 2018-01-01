module api;

import vibe.http.client;
import vibe.stream.operations;
import vibe.core.log;
import std.typecons;
import url;

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
    Represent a generic market.
*/
struct Market {
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

/**
    Represent api credentials.
*/
struct Credentials {
    string apiKey;
    string secretApiKey;
}

/**
    Define available endpoint in the api.
*/
interface Endpoints {
    @property bool hasFetchMarkets();
    Market[] fetchMarkets();
}

/**
    Api configuration.
*/
struct Configuration {
    bool substituteCommonCurrencyCodes = true;
}

abstract class Exchange: Endpoints {
    public static enum Exchanges {
        Bittrex = "bittrex"
    }

    public Credentials credentials;

    private Configuration _configuration;

    /**
        Constructor.
    */
    this () {
        this.configure(this._configuration);
    }

    /**
        Configure the api.
    */
    protected abstract void configure(ref Configuration configuration);

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

    /**
        Performs a synchronous HTTP request on the specified URL,
        using the specified method.
    */
    template jsonHttpRequest(T) if (is(T == class) | is(T == struct)) {
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

    /**
        Used to convert a currency code to a common currency code.
    */
    protected const string commonCurrencyCode(string currency) {
        enum COMMON = [
            "XBT": "BTC",
            "BCC": "BCH",
            "DRK": "DASH"];
        if (this._configuration.substituteCommonCurrencyCodes) {
            if (currency in COMMON)
                return COMMON[currency];
        }
        return currency;
    }
}



