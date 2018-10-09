/**
    This module contains json utils.
*/
module crypto.exchanges.core.utils.json;


public import vibe.data.json : Json;
public import std.conv : to;

import crypto.exchanges.core.exceptions;

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



/** A no-throw json get.
Template_Params:
    T = Value type to get.

Params:
    json = The json object to use
    defaultValue = The default value in case of failure
*/
T safeGet(T)(Json json, T defaultValue = T.init) @safe nothrow
{
    try {
        return json.get!T;
    }
    catch (Exception e) {
        return defaultValue;
    }
}


/** A json get extension to enforce an api exception in case of failure.
Template_Params:
    T = The type to get
    TFrom = If set, apply a conversion from TFrom to T before, equivalent to json.get!TFrom.to!T

Throws:
    InvalidResponseException on failure.
*/
T enforceGet(T, TFrom = void)(Json json) @safe
{
    try {
        static if (is(TFrom == void))
            return json.get!T;
        else
            return json.get!TFrom.to!T;
    }
    catch (Exception e) {
        throw new InvalidResponseException(e.msg);
    }
}

alias enforceGetStr = enforceGet!string;
alias enforceGetStrToF = enforceGet!(float, string);