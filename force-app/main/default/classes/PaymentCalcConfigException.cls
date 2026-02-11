/**
 * @description Custom exception thrown when critical Payment Calculation Configuration
 *              cannot be loaded or fails validation. This exception signals a fail-fast
 *              condition - the system cannot proceed without valid configuration.
 *
 * OPERATIONAL BEHAVIOR:
 * - When this exception is thrown, a Critical_Config_Error__e Platform Event is published
 * - All transactions requiring config will fail (no silent fallbacks)
 * - Administrators should monitor Platform Events and system logs for these errors
 *
 * ROOT CAUSES:
 * - Payment_Calc_Config__mdt 'Default' record does not exist
 * - CMDT record exists but has null/invalid values for required fields
 * - Insufficient permissions to read CMDT
 *
 * RESOLUTION:
 * - Ensure Payment_Calc_Config__mdt has a 'Default' record with all required fields populated
 * - Verify field values are within valid ranges (see PaymentCalcConfigSvc.validateConfig)
 * - Check user/profile permissions for CMDT read access
 *
 * @author DCG Development Team
 * @date 2025-12-19
 */
public class PaymentCalcConfigException extends Exception {

    /** The specific config field that failed validation, if applicable */
    public String failedField { get; private set; }

    /** The value that was found (may be null) */
    public Object foundValue { get; private set; }

    /** Additional context about the failure */
    public String context { get; private set; }

    /**
     * @description Create exception with field-level detail
     * @param message Error message
     * @param failedField The config field that failed
     * @param foundValue The value that was found
     * @param context Additional context
     * @return PaymentCalcConfigException with populated details
     */
    public static PaymentCalcConfigException fieldError(
        String message,
        String failedField,
        Object foundValue,
        String context
    ) {
        PaymentCalcConfigException ex = new PaymentCalcConfigException(message);
        ex.failedField = failedField;
        ex.foundValue = foundValue;
        ex.context = context;
        return ex;
    }

    /**
     * @description Create exception for missing config record
     * @param configName The name of the missing config record
     * @return PaymentCalcConfigException for missing config
     */
    public static PaymentCalcConfigException missingConfig(String configName) {
        String message = 'Critical configuration missing: Payment_Calc_Config__mdt record \'' +
            configName + '\' does not exist. System cannot proceed.';
        PaymentCalcConfigException ex = new PaymentCalcConfigException(message);
        ex.context = 'MISSING_CMDT_RECORD';
        return ex;
    }

    /**
     * @description Create exception for config load failure
     * @param originalException The underlying exception that caused the failure
     * @return PaymentCalcConfigException wrapping the original error
     */
    public static PaymentCalcConfigException loadFailure(Exception originalException) {
        String message = 'Failed to load critical configuration: ' + originalException.getMessage();
        PaymentCalcConfigException ex = new PaymentCalcConfigException(message, originalException);
        ex.context = 'CMDT_LOAD_FAILURE';
        return ex;
    }
}