module BittrexExchange;

import Exchange;
import vibe.data.json;
import vibe.data.bson;
import vibe.web.rest;
import vibe.http.common;


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
    T[] result;
}

/**
    Markets response.
*/
struct BittrexTicker {
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

    this() {
    }

    /**
        Bittrex signing process.
    */
    protected override void signRequest(Url url, out string[string] headers) {
        long nonce = this.getUnixTimestamp();
    }

    public BittrexResponse!BittrexTicker getMarkets() {
        // BittrexResponse!BittrexTicker response = _client.getMarkets();
        string[string] headers;
        auto resp = this.jsonHttpRequest!(BittrexResponse!BittrexTicker)("https://bittrex.com/api/v1.1/public/getmarkets", HTTPMethod.GET, headers);
        BittrexResponse!BittrexTicker response;
        return response;
    }
}
