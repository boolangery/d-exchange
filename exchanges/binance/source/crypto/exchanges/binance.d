module crypto.exchanges.binance;

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



class BittrexExchange: Exchange, IMarketEndpoint, IOrderBookEndpoint
{
private:
    immutable string WsEndpoint = "wss://stream.binance.com:9443";

public:
    this(Credentials credential)
    {
        super(credential);
    }

}


















