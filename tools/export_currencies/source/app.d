import vibe.http.client;
import vibe.stream.operations;
import vibe.data.json;
import std.stdio;
import std.typecons;
import std.array;
import std.ascii : isAlpha, toUpper, isDigit;
import std.uni : toLower;
import std.string : capitalize;
import std.range.primitives;

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

struct SanitizedCoin
{
    string name;
    string symbol;
    string identifier;
}

string sanitizeSymbol(string symbol)
{
    // forbidden chars
    symbol = symbol.replace("$", " Dol ");
    symbol = symbol.replace("@", " At ");

    if (symbol.front.isDigit)
        symbol.insertInPlace(0, '_');

    string[] words = symbol.split(" ");
    symbol = words.join("_");

    if (symbol.back is '_')
        symbol.popBack();

    if (symbol.front is '_' && symbol.length > 1 && !symbol[1].isDigit)
        symbol.popFront();

    return symbol;
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

            SanitizedCoin[] sanitized;
            bool[string] coinNames;

            foreach(coin; coinList.data) {
                string identifier = coin.name;

                // if duplicated coin identifier, try to use website_slug
                if (capitalize(identifier) in coinNames)
                    identifier = coin.website_slug;

                coinNames[capitalize(identifier)] = true;

                // act as a space char
                identifier = identifier.replace("_", " ");
                identifier = identifier.replace("/", " ");

                // forbidden char
                identifier = identifier.replace("'", "");

                // replaced by word char
                identifier = identifier.replace("+", " Plus ");
                identifier = identifier.replace("-", " Minus ");
                identifier = identifier.replace(".", " Dot ");
                identifier = identifier.replace("$", " Dol ");
                identifier = identifier.replace("@", " At ");

                string[] words = identifier.split(" ");
                string sanitizedId;

                foreach(word; words)
                    sanitizedId ~= capitalize(word);

                // replaced by '_' char
                sanitizedId = sanitizedId.replace("(", "_");
                sanitizedId = sanitizedId.replace(")", "_");
                sanitizedId = sanitizedId.replace("[", "_");
                sanitizedId = sanitizedId.replace("]", "_");

                if (sanitizedId.back is '_')
                    sanitizedId.popBack();

                if (sanitizedId.front.isDigit)
                    sanitizedId.insertInPlace(0, '_');

                sanitized ~= SanitizedCoin(coin.name,
                    coin.symbol.toLower(),
                    sanitizedId);

            }

            writeln("module crypto.coins;");
            writeln("");
            writeln("");
            writeln("struct Coin");
            writeln("{");
            writeln("private:");
            writeln("    static immutable Coin[string] _reverse;");
            writeln("");
            writeln("public:");
            writeln("    string name;");
            writeln("    string symbol;");
            writeln("");
            foreach(coin; sanitized)
                writeln("    static immutable Coin %s = Coin(\"%s\", \"%s\");"
                    .format(coin.identifier, coin.name, coin.symbol));
            writeln("");
            writeln("    static this()");
            writeln("    {");
            foreach(coin; sanitized)
                writeln("        _reverse[%s.symbol] = %s;".format(coin.identifier, coin.identifier));
            writeln("    }");

            writeln("static Coin opIndex(string symbol) { return _reverse[symbol]; }");
            writeln("}");
        }
    );

    return 0;
}
