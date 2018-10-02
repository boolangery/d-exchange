/**
	This module contains the tests for binance exchange.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Eliott Dumeix
*/

import common;
import crypto.exchanges.binance;



@SingleThreaded
@Name("test")
unittest {
    Credentials creds;
    auto binance = new BinanceExchange(creds);


    binance.addCandleListener(TradingPair("bnb", "btc"), (scope candle) {


    });
}
