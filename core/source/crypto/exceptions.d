module crypto.exceptions;


/// Base class for all exception.
class ExchangeException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}

/// Indicate an expired request (for example a request outside of the recvWindow).
class ExpiredRequestException : ExchangeException
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}

class InvalidResponseException : ExchangeException
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}
