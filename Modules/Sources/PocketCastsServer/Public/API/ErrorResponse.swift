import Foundation

public enum APIError: String, Error {
    case UNKNOWN = "unknown"
    case INCORRECT_PASSWORD = "login_password_incorrect"
    case PERMISSION_DENIED = "login_permission_denied_not_admin"
    case ACCOUNT_LOCKED = "login_account_locked"
    case BLANK_EMAIL = "login_email_blank"
    case BLANK_PASSWORD = "login_password_blank"
    case EMAIL_NOT_FOUND = "login_email_not_found"
    case THANKS_FOR_SIGNING_UP = "login_thanks_signing_up"
    case UNABLE_TO_CREATE_ACCOUNT = "login_unable_to_create_account"
    case PASSWORD_INVALID = "login_password_invalid"
    case EMAIL_INVALID = "login_email_invalid"
    case EMAIL_TAKEN = "login_email_taken"
    case USER_REGISTER_FAILED = "login_user_register_failed"
    case PROMO_ALREADY_PLUS = "promo_already_plus"
    case PROMO_CODE_EXPIRED_OR_INVALID = "promo_code_expired_or_invalid"
    case PROMO_ALREADY_REDEEMED = "promo_already_redeemed"
    case AUTHORIZATION_PENDING = "authorization_pending"
    case EXPIRED_TOKEN = "expired_token"
    case ACCESS_DENIED = "access_denied"
    case INVALID_GRANT = "invalid_grant"
    // These errors don't map to a code provided by the API but are added locallay for client errors.
    case NO_CONNECTION = "no_connection"
    case TOKEN_DEAUTH = "token_deauth"
}
