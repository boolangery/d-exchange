module bittrex;

import std.conv;
import std.math;
import api;
import vibe.data.json;
import vibe.data.bson;
import vibe.web.rest;
import vibe.http.common;
import url;



// ////////////////////////////////////////////////////////////////////////////
// REST Api                                                                  //
// ////////////////////////////////////////////////////////////////////////////
// JSON Reponses //////////////////////////////////////////////////////////////
/**
    Generic Bittrex response.
*/
struct BittrexResponse(T) {
    bool success;
    string message;
    @optional T result;
}

/**
    Markets response.
*/
struct BittrexMarket {
    @name("MarketCurrency") string marketCurrency;
    @name("BaseCurrency") string baseCurrency;
    @name("MarketCurrencyLong") string marketCurrencyLong;
    @name("BaseCurrencyLong") string baseCurrencyLong;
    @name("MinTradeSize") double minTradeSize;
    @name("MarketName") string marketName;
    @name("IsActive") bool isActive;
    @name("Created") string created;
    @name("Notice") @optional string notice;
    @name("IsSponsored") @optional bool isSponsored;
    @name("LogoUrl") @optional string logoUrl;
}


class BittrexExchange: Exchange {
    private string _baseUrl = "https://bittrex.com/api/v1.1/public/";
    private const Credentials _credentials;

    this(Credentials credentials) {
        this._credentials = credentials;
    }

    protected override void configure(ref Configuration configuration) {

    }

    /**
        Bittrex signing process.
    */
    protected override const void signRequest(url.URL url, out string[string] headers) {
        import std.digest.hmac;
        import std.digest : toHexString;
        import std.digest.sha : SHA512;
        import std.string : representation;

        long nonce = this.getUnixTimestamp();
        url.queryParams.overwrite("apikey", _credentials.apiKey);
        url.queryParams.overwrite("nonce", to!string(nonce));
        string sign = url.toString()
            .representation
            .hmac!SHA512(_credentials.secretApiKey.representation)
            .toHexString!(LetterCase.lower);
        headers["apisign"] = sign;
    }


    @property bool hasFetchMarkets() { return true; }
    Market[] fetchMarkets() {
        auto resp = this.jsonHttpRequest!(BittrexResponse!(BittrexMarket[]))(parseURL("https://bittrex.com/api/v1.1/public/getmarkets"), HTTPMethod.GET);
        // convert to generic response:
        Market[] markets = new Market[resp.result.length];
        int k = 0;
        foreach (m; resp.result) {
            markets[k].id = m.marketName;
            markets[k].base = this.commonCurrencyCode(m.marketCurrency);
            markets[k].quote = this.commonCurrencyCode(m.baseCurrency);
            markets[k].symbol = markets[k].base ~ "/" ~ markets[k].quote;
            markets[k].active = m.isActive;
            markets[k].precision.amount = 8; // TODO: check
            markets[k].precision.price = 8;
            markets[k].lot = pow(10, -markets[k].precision.amount);
            markets[k].limits.amount.min = m.minTradeSize;
            k++;
        }
        BittrexResponse!BittrexMarket response;
        return null;
    }
    unittest {
        import test;
        auto config = getTestConfig();
        auto bittrex = new BittrexExchange(config[Exchange.Exchanges.Bittrex].credentials);
    }

}