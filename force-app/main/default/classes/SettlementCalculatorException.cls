/**
 * @description Custom exception class for Settlement Calculator errors.
 *              Provides specific error types for different failure scenarios.
 * @author Settlement Calculator Team
 * @date December 2025
 */
public class SettlementCalculatorException extends Exception {

    public enum ErrorType {
        NO_SEGMENTS,
        INVALID_SEGMENT_TYPE,
        INVALID_SETTLEMENT_AMOUNT,
        INVALID_SEGMENT_CONFIG,
        MAX_ITERATIONS_EXCEEDED,
        INVALID_CREDITOR_OPPORTUNITY,
        CALCULATION_ERROR,
        DATE_CALCULATION_ERROR,
        FEE_CALCULATION_ERROR
    }

    private ErrorType errorType;
    private String fieldName;
    private Object invalidValue;

    /**
     * @description Constructor with error type
     * @param errorType The type of error that occurred
     * @param message Detailed error message
     */
    public SettlementCalculatorException(ErrorType errorType, String message) {
        this(message);
        this.errorType = errorType;
    }

    /**
     * @description Constructor with error type and field context
     * @param errorType The type of error that occurred
     * @param message Detailed error message
     * @param fieldName The field that caused the error
     * @param invalidValue The invalid value
     */
    public SettlementCalculatorException(ErrorType errorType, String message, String fieldName, Object invalidValue) {
        this(message);
        this.errorType = errorType;
        this.fieldName = fieldName;
        this.invalidValue = invalidValue;
    }

    public ErrorType getErrorType() {
        return this.errorType;
    }

    public String getFieldName() {
        return this.fieldName;
    }

    public Object getInvalidValue() {
        return this.invalidValue;
    }
}