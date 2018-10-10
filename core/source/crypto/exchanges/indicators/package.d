/**
	Import all indicators.
*/
module crypto.exchanges.indicators;


abstract class Indicator
{
public:
    abstract float update(in float v) pure nothrow @safe;

    float[] compute(float[] prices) pure nothrow @safe
    {
        float[] result;

        foreach(price; prices)
            result ~= update(price);;

        return result;
    }
}
