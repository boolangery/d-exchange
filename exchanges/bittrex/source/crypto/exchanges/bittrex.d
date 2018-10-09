module crypto.exchanges.bittrex;


public import crypto.exchanges.core.api;


class BittrexExchange: Exchange
{
private:
    URLD BaseUrl = parseURL("https://bittrex.com/api/");

protected:
    override void _signRequest(ref URLD url, out string[string] headers) const @safe
    {
        if (!indexOf(url.path, "public")) {
            import std.digest.hmac;
            import std.digest : toHexString;
            import std.digest.sha : SHA512;

            long nonce = this._getUnixTimestamp();
            url.queryParams.overwrite("apikey", _credentials.apiKey);
            url.queryParams.overwrite("nonce", to!string(nonce));
            string sign = url.toString()
                .representation
                .hmac!SHA512(_credentials.secretApiKey.representation)
                .toHexString!(LetterCase.lower);
            headers["apisign"] = sign;
        }
    }

    /** Ensure no error in a bittrex json response.
    It throw exception depending of the error code. */
    override void _enforceNoError(in Json response) @safe const
    {
        // if json field "code" exists, then it is an error
        if (!response["success"].get!bool) {
            auto msg = response["message"].enforceGetStr;

            throw new ExchangeException(msg);
        }
    }

public:
    this(Credentials credential, ExchangeConfiguration config = null)
    {
        super(credential, config);
    }

    override Market[] fetchMarkets()
    {
        URLD endpoint = BaseUrl;
        endpoint.path = "v1.1/public/getmarkets";

        Json response = _jsonHttpRequest(endpoint, HTTPMethod.GET);

        throw new ExchangeException("TODO");
    }
}
