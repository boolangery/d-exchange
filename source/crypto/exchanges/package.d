module crypto.exchanges;

public import crypto.exchanges.core.api;

/// exchanges
public import crypto.exchanges.binance;


enum Exchanges
{
    binance
}

static class Factory
{
	static IExchange create(T: ExchangeConfiguration)(Exchanges ex, Credentials creds, T conf = null)
    {
        final switch(ex) {
         	case Exchanges.binance: return new BinanceExchange(creds, conf);
        }
    }
}
