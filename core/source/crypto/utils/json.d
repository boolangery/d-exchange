/**
    This module contains json utils.
*/
module crypto.utils.json;


public import vibe.data.json : Json;
public import std.conv : to;

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

/// Json get extension to get a string field and convert it to a type safely.
T safeGetStr(T)(Json json, T defaultValue = T.init)
{
    scope(failure) return defaultValue;
    return json.get!string.to!T;
}
