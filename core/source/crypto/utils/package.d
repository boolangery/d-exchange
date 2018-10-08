module crypto.utils;


public import crypto.utils.json;


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
