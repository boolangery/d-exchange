/**
    Simple Moving Average.
*/
module crypto.exchanges.indicators.sma;


import crypto.exchanges.indicators;


/// Simple Moving Average.
class SMA : Indicator
{
    import std.algorithm : min;

private:
    int _windowLength;
    float[] data;
    float sum = 0f;
    int index, nFilled;

public:
    this(int windowLength)
    {
        import std.algorithm.mutation : fill;

        _windowLength = windowLength;
        data.length = _windowLength;
        data.fill(0);
    }

    override float update(in float v) pure nothrow @safe @nogc
    {
        sum += -data[index] + v;
        data[index] = v;
        index = (index + 1) % _windowLength;
        nFilled = min(_windowLength, nFilled + 1);
        return sum / nFilled;
    }
}

///
unittest
{
    import std.algorithm.comparison : equal;
    import std.math : approxEqual;

    auto prices = [81f, 24, 75, 21, 34, 25, 72, 92, 99, 2, 86, 80];
    auto exp = [81, 52.5, 60, 40, 43.3333, 26.6667, 43.6667, 63, 87.6667, 64.3333, 62.3333, 56];

    auto res = new SMA(3).compute(prices);
    assert(equal!approxEqual(res, exp));
}

// SMA 10
unittest
{
    import std.algorithm.comparison : equal;
    import std.math : approxEqual;

    float[] prices = [81, 24, 75, 21, 34, 25, 72, 92, 99, 2, 86, 80, 76, 8, 87, 75, 32, 65, 41, 9, 13, 26, 56, 28, 65, 58, 17, 90, 87, 86, 99, 3, 70, 1, 27, 9, 92, 68, 9];
    float[] exp_10 = [81, 52.5, 60, 50.25, 47, 43.3333, 47.4286, 53, 58.1111, 52.5, 53, 58.6, 58.7, 57.4, 62.7, 67.7, 63.7, 61, 55.2, 55.9, 48.6, 43.2, 41.2, 43.2, 41, 39.3, 37.8, 40.3, 44.9, 52.6, 61.2, 58.9, 60.3, 57.6, 53.8, 48.9, 56.4, 54.2, 46.4];
    float[] exp_12 = [81, 52.5, 60, 50.25, 47, 43.3333, 47.4286, 53, 58.1111, 52.5, 55.5455, 57.5833, 57.1667, 55.8333, 56.8333, 61.3333, 61.1667, 64.5, 61.9167, 55, 47.8333, 49.8333, 47.3333, 43, 42.0833, 46.25, 40.4167, 41.6667, 46.25, 48, 52.8333, 52.3333, 57.0833, 55, 52.5833, 51, 53.25, 54.0833, 53.4167];
    float[] exp_26 = [81, 52.5, 60, 50.25, 47, 43.3333, 47.4286, 53, 58.1111, 52.5, 55.5455, 57.5833, 59, 55.3571, 57.4667, 58.5625, 57, 57.4444, 56.5789, 54.2, 52.2381, 51.0455, 51.2609, 50.2917, 50.88, 51.1538, 48.6923, 51.2308, 51.6923, 54.1923, 56.6923, 55.8462, 55.7692, 52.2692, 49.5, 49.7692, 50, 49.5385, 46.9615];

    assert(equal!approxEqual(exp_10, new SMA(10).compute(prices)));
    assert(equal!approxEqual(exp_12, new SMA(12).compute(prices)));
    assert(equal!approxEqual(exp_26, new SMA(26).compute(prices)));
}
