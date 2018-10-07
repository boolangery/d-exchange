module crypto.utils;


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

/** Transform an array to an associative array by indexing the initial array
using the specified field inside the object array. */
auto indexBy(string field, T)(T[] array) if (__traits(hasMember, T, field))
{
    alias KeyType = typeof(__traits(getMember, T, field));

    T[KeyType] aa;

    foreach(obj; array)
        aa[__traits(getMember, obj, field)] = obj;

    return aa;
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

/// Json get extension to get a string field and convert it a type safely.
T safeGetStr(T)(Json json, T defaultValue = T.init)
{
    scope(failure) return defaultValue;
    return json.get!string.to!T;
}


T safeTo(T, V)(V valueToConv, T defaultValue)
{
    scope(failure) return defaultValue;
    return defaultValue;
}

long getMillisTimestamp()
{
    import std.datetime.systime : Clock;

    auto now = Clock.currTime;
    return now.toUnixTime() * 1000 + now.fracSecs.total!"msecs";
}
