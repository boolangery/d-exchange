/**
	This module contains the tests for binance exchange.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Eliott Dumeix
*/

import common;
import crypto.exchanges.binance;

private static Credentials _binanceCredentials;

static this()
{
    _binanceCredentials = getTestConfig()["binance"].credentials;
}

@SingleThreaded
@Name("test")
unittest {
    Credentials creds;
    auto binance = new BinanceExchange(creds);
    // auto markets = binance.fetchMarkets();

    binance.fetchBalance();
}
