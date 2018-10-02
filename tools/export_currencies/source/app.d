import vibe.http.client;
import vibe.stream.operations;
import vibe.data.json;
import std.stdio;
import std.typecons;


/**
{
    "data": [
        {
            "id": 1,
            "name": "Bitcoin",
            "symbol": "BTC",
            "website_slug": "bitcoin"
        }
    ],
    "metadata": {
        "timestamp": 1538472433,
        "num_cryptocurrencies": 2010,
        "error": null

	}
}
*/
class Response
{
	Coin[] data;
	Metadata metadata;
}

class Metadata
{
	double timestamp;
	int num_cryptocurrencies;
	Nullable!string error;
}


class Coin
{
    int id;
    string name;
    string symbol;
    string website_slug;
}

int main(string[] args)
{
    requestHTTP("https://api.coinmarketcap.com/v2/listings/",
		(scope req) {
			req.method = HTTPMethod.GET;
		},
		(scope res) {
			string resp = res.bodyReader.readAllUTF8();
			auto coinList = deserializeJson!Response(resp);

			writeln("module crypto.coins;");
			writeln("");
			writeln("");
			writeln("enum Coins : string");
			writeln("{");
			foreach(coin; coinList.data) {
                writeln("    " ~ coin.symbol ~ " =  \"" ~ coin.name ~ "\",");
            }
			writeln("}");
			writeln("");
		}
	);

    return 0;
}
