module exceptions;


/**
    Base class for all exceptions.
*/
class BaseError: Exception {
    this() {
        super("");
    }

    this(const string message) {
        super(message);
    }
}

/**
    Raised when an exchange server replies with an error in JSON.
*/
class ExchangeError: BaseError {}

/**
    Raised if the endpoint is not offered/not yet supported by the exchange API.
*/
class NotSupported: ExchangeError {}

/**
    Raised when API credentials are required but missing or wrong.
*/
class AuthenticationError: ExchangeError {}

/**
    Raised in case of a wrong or conflicting nonce number in private requests.
*/
class InvalidNonce: ExchangeError {}

/**
    Raised when you don't have enough currency on your account balance to place an order.
*/
class InsufficientFunds: ExchangeError {}

/**
    "Base class for all exceptions related to the unified order API.
*/
class InvalidOrder: ExchangeError {}

/**
    Raised when you are trying to fetch or cancel a non-existent order.
*/
class OrderNotFound: InvalidOrder {}

/**
    Raised when the order is not found in local cache (where applicable).
*/
class OrderNotCached: InvalidOrder {}

/**
    Raised when an order that is already pending cancel is being canceled again.
*/
class CancelPending: InvalidOrder {}

/**
    Base class for all errors related to networking.
*/
class NetworkError: BaseError {}

/**
    Raised whenever DDoS protection restrictions are enforced per user or region/location.
*/
class DDoSProtection: NetworkError {}

/**
    Raised when the exchange fails to reply in .timeout time.
*/
class RequestTimeout: NetworkError {}

/**
    Raised if a reply from an exchange contains keywords related to maintenance or downtime.
*/
class ExchangeNotAvailable: NetworkError {}
