module crypto.exchanges.bittrex;

import std.conv;
import std.math;
import std.string;
import std.container;
import vibe.data.json;
import vibe.data.bson;
import vibe.web.rest;
import vibe.http.common;
import url;
import crypto.api;


/**
    Json Generic Bittrex response.
*/
class BittrexResponse(T)
{
    bool success;
    string message;
    @optional T result;
}

/**
    Json Markets response.
*/
class BittrexMarket: IGenericResponse!Market {
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

    Market toGeneric() {
        Market market = new Market();
        market.id = this.marketName;
        market.base = this.marketCurrency;
        market.quote = this.baseCurrency;
        market.symbol = market.base ~ "/" ~ market.quote;
        market.active = this.isActive;
        market.precision.amount = 8; // TODO: check
        market.precision.price = 8;
        market.lot = pow(10, -market.precision.amount);
        market.limits.amount.min = this.minTradeSize;
        return market;
    }
}

/**
    Json Order response.
*/
class BittrexOrder: IGenericResponse!Order {
    @name("Quantity") double quantity;
    @name("Rate") double rate;

    Order toGeneric() {
        Order order = new Order();
        order.quantity = this.quantity;
        order.rate = this.rate;
        return order;
    }
}

/**
    Json Order Book response (type Both).
*/
class BittrexOrderBookBoth: IGenericResponse!OrderBook {
    @optional @name("buy") BittrexOrder[] buyOrders;
    @optional @name("sell") BittrexOrder[] sellOrders;

    OrderBook toGeneric() {
        OrderBook orderBook;
        if (buyOrders.length > 0 && sellOrders.length > 0) {
            orderBook.type = OrderBookType.Both;
        }
        else if (buyOrders.length > 0) {
            orderBook.type = OrderBookType.Buy;
        }
        else {
            orderBook.type = OrderBookType.Sell;
        }

        foreach (order; this.buyOrders) {
            orderBook.buyOrders.insertBack(order.toGeneric());
        }
        foreach (order; this.sellOrders) {
            orderBook.sellOrders.insertBack(order.toGeneric());
        }
        return orderBook;
    }
}


class BittrexExchange: Exchange, IMarketEndpoint, IOrderBookEndpoint {
    private string _baseUrl = "https://bittrex.com/api/v1.1/public/";

    this(Credentials credentials) {
        super(credentials);
    }

    protected override void configure(ref Configuration config) {
        config.id   = "bittrex";
        config.name = "Bittrex";
        config.ver  = "v1.1";
        config.rateLimit = 100;
    }

    /**
        Bittrex signing process.
    */
    protected override const void signRequest(url.URL url, out string[string] headers) {
        if (!indexOf(url.path, "public")) {
            import std.digest.hmac;
            import std.digest : toHexString;
            import std.digest.sha : SHA512;

            long nonce = this.getUnixTimestamp();
            url.queryParams.overwrite("apikey", _credentials.apiKey);
            url.queryParams.overwrite("nonce", to!string(nonce));
            string sign = url.toString()
                .representation
                .hmac!SHA512(_credentials.secretApiKey.representation)
                .toHexString!(LetterCase.lower);
            headers["apisign"] = sign;
        }
    }


    Array!Market fetchMarkets() {
        auto resp = this.jsonHttpRequestCached!(BittrexResponse!(BittrexMarket[]))(parseURL("https://bittrex.com/api/v1.1/public/getmarkets"), HTTPMethod.GET);
        // convert to generic response:
        auto markets = Array!Market();

        foreach (bittrexMarket; resp.result) {
            Market market = bittrexMarket.toGeneric();
            market.base = this.commonCurrencyCode(market.base);
            market.quote = this.commonCurrencyCode(market.quote);
            markets.insertBack(market);
        }
        return markets;
    }
    unittest {
        import test;
        auto config = getTestConfig();

        auto bittrex = new BittrexExchange(config[Exchanges.Bittrex].credentials);
        auto markets = bittrex.fetchMarkets();
        assert(markets.length > 100, "No market fetched");
    }

    OrderBook fetchOrderBook(string symbol, OrderBookType type) {
        enum TYPE_TXT = [
            OrderBookType.Sell : "sell",
            OrderBookType.Buy  : "buy",
            OrderBookType.Both : "both",
        ];
        url.URL url = parseURL("https://bittrex.com/api/v1.1/public/getorderbook");
        url.queryParams.overwrite("market", symbol);
        url.queryParams.overwrite("type", TYPE_TXT[type]);

        // Reponses are different for both and buy/sell
        if (type == OrderBookType.Both) {
            auto resp = this.jsonHttpRequestCached!(BittrexResponse!BittrexOrderBookBoth)(url, HTTPMethod.GET);
            return resp.result.toGeneric();
        }
        else {
            auto resp = this.jsonHttpRequestCached!(BittrexResponse!(BittrexOrder[]))(url, HTTPMethod.GET);
            auto orderBook = new OrderBook();
            orderBook.type = type;
            if (type == OrderBookType.Buy) {
                foreach (bittrexOrder; resp.result) {
                    orderBook.buyOrders.insertBack(bittrexOrder.toGeneric());
                }
            }
            else {
                foreach (bittrexOrder; resp.result) {
                    orderBook.sellOrders.insertBack(bittrexOrder.toGeneric());
                }
            }
            return orderBook;
        }
    }
    unittest {
        import test;
        auto config = getTestConfig();

        auto bittrex = new BittrexExchange(config[Exchanges.Bittrex].credentials);
        auto book = bittrex.fetchOrderBook("BTC-ETH", OrderBookType.Sell);

        assert(book.sellOrders.length > 50, "No orders fetched");
        assert(book.buyOrders.length == 0, "No buy orders must be fetched");
        assert(book.type == OrderBookType.Sell);
    }
}


















