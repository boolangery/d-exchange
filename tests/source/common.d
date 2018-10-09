/**
    This module contains some utilities to properly run unittest.

    unittest requires exchange api keys to be runned. So you need to
    provide them in a unittest.conf file.
*/
module common;

import crypto.exchanges.core.api : Credentials;
import std.experimental.logger;

public import unit_threaded;


/// A custom logger to log messages to unit_threaded system.
class UnitThreadedLogger : Logger
{
    this(LogLevel lv) @safe
    {
        super(lv);
    }

    override void writeLogMsg(ref LogEntry payload)
    {
        writelnUt(payload.msg);
    }
}

static this()
{
    // setup logger
    sharedLog = new UnitThreadedLogger(LogLevel.all);
}


/**
    Contains test configuration about an exchange api.
*/
struct TestConfiguration {
    bool runTest = false;
    Credentials credentials;
}

TestConfiguration[string] getTestConfig() {
    import std.array;
    import std.file;
    import std.stdio;
    import std.traits;
    import vibe.data.json;

    import crypto.exchanges.core.api : Exchanges;

    immutable FileName = "./apiConfigs.json";

    // if the file doesn't exists, create a stub:
    if (!exists(FileName)) {
        File file = File(FileName, "w");

        TestConfiguration[string] config;
        // iterate over exchange ids:
        foreach (immutable api; [EnumMembers!(Exchanges)]) {
            auto c = TestConfiguration();
            c.credentials.apiKey = "my_" ~ api ~ "api_key";
            c.credentials.secretApiKey = "my_" ~ api ~ "secret_api_key";
            config[api] = c;
        }
        auto appender = appender!string();
        serialize!(JsonStringSerializer!(Appender!string, true))(config, appender);
        file.writeln(appender.data);
    }

    // Read configuration from file:
    File file = File(FileName, "r");

    string json = "";
    while (!file.eof()) {
        string line = file.readln();
        json ~= line;
    }
    return deserializeJson!(TestConfiguration[string])(json);
}
