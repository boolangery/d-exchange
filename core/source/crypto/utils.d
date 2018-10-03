module crypto.utils;


import vibe.data.json : Json;
import std.conv : to;

/// Take an Json array of object, and return an associative array
/// indexed by an object field.
Json[T] indexBy(T = string)(Json array, string field)
{
    assert(array.type is Json.Type.array);

    Json[T] result;
    foreach(obj; array) {
        auto key = obj[field].get!T;
        result[key] = obj;
    }
    return result;
}

/// Json get extension to do a safe get.
T safeGet(T)(Json json, T defaultValue = T.init)
{
    try {
        return json.get!T;
    }
    catch (Exception e) {
        return defaultValue;
    }
}

T safeTo(T, V)(V valueToConv, T defaultValue)
{
    try {
        return to!T(valueToConv);
    }
    catch (Exception e) {
        return defaultValue;
    }
}
