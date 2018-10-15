/**
    Smoothed Simple Moving Average.
*/
module crypto.exchanges.indicators.smma;


import crypto.exchanges.indicators.base;


/// Smoothed Simple Moving Average.
class SMMA : Indicator
{
    import crypto.exchanges.indicators.sma;

private:
    SMA _sma;
    int _weight;
    float _sum;
    float _last;
    int _age;

public:
    this(int weight)
    {
        import std.algorithm.mutation : fill;

        _sma = new SMA(weight);
        _weight = weight;
    }

    override float update(in float price) pure nothrow @safe @nogc
    {
        _age++;
        // first period
        if (_age < _weight) {
            _last = _sma.update(price);
            return 0;
        }
        else {
            auto prevSum = _last * _weight;
            auto smmai = (prevSum - _last + price) / _weight;
            _last = smmai;
            return smmai;
        }
    }
}

///
unittest
{
    import std.algorithm.comparison : equal;
    import std.math : approxEqual;

    float[] prices = [81, 24, 75, 21, 34, 25, 72, 92, 99, 2, 86, 80, 76, 8, 87, 75, 32, 65, 41, 9, 13, 26, 56, 28, 65, 58, 17, 90, 87, 86, 99, 3, 70, 1, 27, 9, 92, 68, 9];
    float[] exp_12 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 57.583333333333336, 59.118055555555564, 54.8582175925926, 57.53669945987655, 58.991974504886834, 56.74264329614626, 57.43075635480074, 56.061526658567345, 52.1397327703534, 48.878088372823946, 46.97158100842196, 47.72394925772013, 46.08028681957679, 47.656929584612065, 48.518852119227724, 45.89228110929208, 49.5679243501844, 52.687263987669034, 55.46332532202995, 59.09138154519412, 54.41709974976127, 55.7156747706145, 51.15603520639663, 49.14303227253024, 45.797779583152725, 49.64796461788999, 51.177300899732494, 47.66252582475479];

    assert(equal!approxEqual(exp_12, new SMMA(12).compute(prices)));
}
