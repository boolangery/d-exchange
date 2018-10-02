/**
    This module contains some utilities to properly run unittest.

    unittest requires exchange api keys to be runned. So you need to
    provide them in a unittest.conf file.
*/
module crypto.test;

import api : Credentials;
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
    import api : Exchanges;
    import vibe.data.json;

    // if the file doesn't exists, create a stub:
    if (!exists("./unittest.conf")) {
        File file = File("./unittest.conf", "w");

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
    File file = File("./unittest.conf", "r");

    string json = "";
    while (!file.eof()) {
        string line = file.readln();
        json ~= line;
    }
    return deserializeJson!(TestConfiguration[string])(json);
}
