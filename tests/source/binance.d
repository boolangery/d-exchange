/**
	This module contains the tests for binance exchange.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Eliott Dumeix
*/

import common;
import crypto.exchanges.binance;
import vibe.core.core;

private static Credentials _binanceCredentials;

static this()
{
    _binanceCredentials = getTestConfig()["binance"].credentials;
}

@Name("test")
unittest {
    auto binance = new BinanceExchange(_binanceCredentials);

    binance.addCandleListener("ETH/BTC", CandlestickInterval._1m, (scope candle) {
        writelnUt("new candle");
    });

    binance.addCandleListener("ETH/BTC", CandlestickInterval._1m, (scope candle) {
        writelnUt("new candle");
    });

    runApplication();
    // auto markets = binance.fetchMarkets();

    // writelnUt(binance.hasCreateOrder(OrderType.market));
    // writelnUt(binance.hasCreateOrder(OrderType.limit));
    // writelnUt(binance.hasCreateOrder(OrderType.stopLoss));
    //binance.fetchBalance();
}
