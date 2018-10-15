/**
    Relative Strength Index.

    http://stockcharts.com/school/doku.php?id=chart_school:technical_indicators:relative_strength_index_rsi
*/
module crypto.exchanges.indicators.rsi;


import crypto.exchanges.indicators.base;
import crypto.exchanges.indicators.smma;

/// Relative Strength Index Indicator.
class RSI : Indicator
{
    bool _init = false;
    float _lastClose;
    int _age;
    float _u, _d;
    SMMA _avgU, _avgD;
    float _rs;

    this(int weight)
    {
        _avgU = new SMMA(weight);
        _avgD = new SMMA(weight);
    }

    override float update(in float price) pure nothrow @safe @nogc
    {
        auto currentClose = price;

        if (!_init) {
            _lastClose = currentClose;
            _init = true;
            return 0;
        }

        if (currentClose > _lastClose) {
            _u = currentClose - _lastClose;
            _d = 0;
        }
        else {
            _u = 0;
            _d = _lastClose - currentClose;
        }

        _lastClose = currentClose;

        auto _avgUResult = _avgU.update(_u);
        auto _avgDResult = _avgD.update(_d);

        if (_avgDResult is 0 && _avgUResult !is 0)
            return 100;
        else if (_avgDResult is 0)
            return 0;
        else {
            float rs = _avgUResult / _avgDResult;
            return 100 - (100 / (1 + rs));
        }
    }
}

///
unittest
{
    import std.algorithm.comparison : equal;
    import std.math : approxEqual;

    float[] prices = [81, 24, 75, 21, 34, 25, 72, 92, 99, 2, 86, 80, 76, 8, 87, 75, 32, 65, 41, 9, 13, 26, 56, 28, 65, 58, 17, 90, 87, 86, 99, 3, 70, 1, 27, 9, 92, 68, 9];
    float[] exp_12 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 49.44320712694878, 42.432667245873155, 51.2017782300719, 49.94116787991835, 45.55663590860508, 49.284333951746184, 46.74501674557244, 43.4860123510052, 44.01823674189631, 45.82704797004994, 49.90209564896179, 46.351969981868436, 51.34208640997234, 50.37501845071388, 44.96351306736635, 54.464714123844956, 54.04642006918241, 53.895901697369816, 55.6476477612053, 42.60631369413207, 51.2964732419777, 43.83906729252931, 47.00600661743475, 45.08586375053323, 54.44633399991266, 51.6681674437389, 45.44886082103851];
    assert(equal!approxEqual(exp_12, new RSI(12).compute(prices)));
}
