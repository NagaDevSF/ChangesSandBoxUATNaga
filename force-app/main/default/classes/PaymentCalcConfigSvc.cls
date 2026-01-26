/**
 * @description Service class for loading and validating Payment Calculation Configuration
 *              from Custom Metadata Type (Payment_Calc_Config__mdt).
 *
 * CRITICAL CONFIGURATION BEHAVIOR:
 * ================================
 * This service enforces a FAIL-FAST approach. Configuration is REQUIRED for all
 * payment calculations. There are NO DEFAULT VALUES or fallbacks.
 *
 * If configuration cannot be loaded or fails validation:
 * 1. An ERROR-level log is written with full context (System.debug)
 * 2. A PaymentCalcConfigException is thrown, failing the transaction
 *
 * USAGE:
 * ------
 * For required configuration (most use cases):
 *   ConfigDTO cfg = PaymentCalcConfigSvc.getRequiredConfig();
 *   // Code here only runs if config is valid
 *
 * For program-specific configuration:
 *   ConfigDTO cfg = PaymentCalcConfigSvc.getRequiredConfigForProgram('DCG_MOD');
 *
 * CACHING:
 * --------
 * Configuration is cached per-transaction using a static variable.
 * This ensures:
 * - Consistent config values within a single transaction
 * - Minimal CMDT queries (one per config name per transaction)
 * - Validation runs once per load
 *
 * @author DCG Development Team
 * @date 2025-12-19
 */
public with sharing class PaymentCalcConfigSvc {

    /** The default CMDT record name to load */
    @TestVisible
    private static String DEFAULT_PAYMENT_CALC_CONFIG = 'Default';

    /** Per-transaction cache for default config */
    private static ConfigDTO cachedDefaultConfig = null;

    /** Per-transaction cache for program-specific configs */
    private static Map<String, ConfigDTO> cachedProgramConfigs = new Map<String, ConfigDTO>();

    /**
     * @description DTO containing all configuration values.
     *              ALL fields are required and validated - no nulls allowed for critical fields.
     */
    public class ConfigDTO {
        // Core fee configuration
        @AuraEnabled public Decimal settlementPercent;
        @AuraEnabled public Decimal programFeePercent;
        @AuraEnabled public Decimal bankingFee;
        @AuraEnabled public Decimal bank2Fee;
        @AuraEnabled public Decimal programSplitRatio;
        @AuraEnabled public Decimal escrowSplitRatio;

        // Setup fee configuration
        @AuraEnabled public Decimal setupFee;
        @AuraEnabled public Decimal setupFeePayments;
        @AuraEnabled public Decimal noFeeSetupFee;
        @AuraEnabled public Decimal debtProgramSetupFee;  // Setup fee for DCG Debt program
        @AuraEnabled public Decimal setupFeeMinPayments;
        @AuraEnabled public Decimal setupFeeMaxPayments;

        // Weekly payment thresholds
        @AuraEnabled public Decimal minWeeklyTargetPayment;
        @AuraEnabled public Decimal minWeeklyTargetPaymentDcgDebt;

        // Program duration configuration
        @AuraEnabled public Decimal minProgramWeeks;
        @AuraEnabled public Decimal maxProgramWeeks;
        @AuraEnabled public Decimal defaultProgramWeeks;
        @AuraEnabled public Decimal recommendedMinWeeks;

        // Target payment configuration
        @AuraEnabled public Decimal targetPaymentPercentage;
        @AuraEnabled public Decimal minTargetPercentDcgMod;
        @AuraEnabled public Decimal minTargetPercentDcgDebt;
        @AuraEnabled public Decimal maxTargetPercent;

        // Conversion & calculation factors
        @AuraEnabled public Decimal weeklyToMonthlyFactor;
        @AuraEnabled public Decimal paymentFallbackRatio;
        @AuraEnabled public Decimal priorityAdjustmentMultiplier;
        @AuraEnabled public Decimal firstPaymentDaysOffset;

        // Additional product fees
        @AuraEnabled public Decimal legalMonitoringWeeklyFee;

        // Validation range configuration
        @AuraEnabled public String validSettlementValues;
        @AuraEnabled public Decimal minProgramFeePercent;
        @AuraEnabled public Decimal maxProgramFeePercent;
        @AuraEnabled public Decimal baselineNoFeeProgramFee;
    }

    // ==================================================================================
    // PUBLIC METHODS - REQUIRED CONFIG (FAIL-FAST)
    // ==================================================================================

    /**
     * @description Loads and validates the default configuration. REQUIRED - will throw
     *              PaymentCalcConfigException if config is missing or invalid.
     *
     * This is the primary method for obtaining configuration. Use this for all
     * calculation-related code paths.
     *
     * @return Fully validated ConfigDTO
     * @throws PaymentCalcConfigException if config cannot be loaded or fails validation
     */
    @AuraEnabled(cacheable=true)
    public static ConfigDTO getRequiredConfig() {
        // Return cached config if available
        if (cachedDefaultConfig != null) {
            return cachedDefaultConfig;
        }

        String configName = DEFAULT_PAYMENT_CALC_CONFIG;
        String correlationId = generateCorrelationId();

        try {
            Payment_Calc_Config__mdt mdt = Payment_Calc_Config__mdt.getInstance(configName);

            if (mdt == null) {
                handleConfigError(
                    'MISSING_CMDT_RECORD',
                    'Payment_Calc_Config__mdt record \'' + configName + '\' does not exist',
                    configName,
                    null,
                    correlationId,
                    null
                );
                // handleConfigError throws, but compiler needs this
                throw PaymentCalcConfigException.missingConfig(configName);
            }

            ConfigDTO dto = mapMdtToDto(mdt, null);
            validateConfig(dto, configName, correlationId);

            // Cache the validated config
            cachedDefaultConfig = dto;

            return dto;

        } catch (PaymentCalcConfigException configEx) {
            // Re-throw config exceptions (already logged/flagged)
            throw configEx;
        } catch (Exception e) {
            handleConfigError(
                'CMDT_LOAD_FAILURE',
                'Failed to load configuration: ' + e.getMessage(),
                configName,
                null,
                correlationId,
                e.getStackTraceString()
            );
            throw PaymentCalcConfigException.loadFailure(e);
        }
    }

    /** Valid program types - used for validation */
    private static final Set<String> VALID_PROGRAM_TYPES = new Set<String>{
        'DCG_DEBT', 'DCG_MOD', 'DCG_MOD_CA'
    };

    /**
     * @description Loads and validates configuration for a specific program type.
     *              REQUIRED - will throw PaymentCalcConfigException if config is missing or invalid.
     *
     * @param programType The program type (e.g., 'DCG_MOD', 'DCG_DEBT', 'DCG_MOD_CA')
     * @return Fully validated ConfigDTO with program-specific overrides
     * @throws PaymentCalcConfigException if config cannot be loaded, program type is invalid, or fails validation
     */
    @AuraEnabled(cacheable=true)
    public static ConfigDTO getRequiredConfigForProgram(String programType) {
        String normalizedType = programType != null ? programType.toUpperCase() : null;
        String cacheKey = normalizedType != null ? normalizedType : 'DEFAULT';

        // Validate program type - throw if unknown
        if (normalizedType != null && !VALID_PROGRAM_TYPES.contains(normalizedType)) {
            String correlationId = generateCorrelationId();
            handleConfigError(
                'INVALID_PROGRAM_TYPE',
                'Unknown program type: \'' + programType + '\'. Valid types are: ' + String.join(new List<String>(VALID_PROGRAM_TYPES), ', '),
                programType,
                'programType',
                correlationId,
                null
            );
            throw PaymentCalcConfigException.missingConfig('Program type \'' + programType + '\' is not valid. Valid types: ' + String.join(new List<String>(VALID_PROGRAM_TYPES), ', '));
        }

        // Return cached config if available
        if (cachedProgramConfigs.containsKey(cacheKey)) {
            return cachedProgramConfigs.get(cacheKey);
        }

        String configName = DEFAULT_PAYMENT_CALC_CONFIG;
        String correlationId = generateCorrelationId();

        try {
            Payment_Calc_Config__mdt mdt = Payment_Calc_Config__mdt.getInstance(configName);

            if (mdt == null) {
                handleConfigError(
                    'MISSING_CMDT_RECORD',
                    'Payment_Calc_Config__mdt record \'' + configName + '\' does not exist',
                    configName,
                    null,
                    correlationId,
                    null
                );
                throw PaymentCalcConfigException.missingConfig(configName);
            }

            ConfigDTO dto = mapMdtToDto(mdt, programType);
            validateConfig(dto, configName, correlationId);

            // Cache the validated config
            cachedProgramConfigs.put(cacheKey, dto);

            return dto;

        } catch (PaymentCalcConfigException configEx) {
            throw configEx;
        } catch (Exception e) {
            handleConfigError(
                'CMDT_LOAD_FAILURE',
                'Failed to load configuration for program ' + programType + ': ' + e.getMessage(),
                configName,
                null,
                correlationId,
                e.getStackTraceString()
            );
            throw PaymentCalcConfigException.loadFailure(e);
        }
    }

    // ==================================================================================
    // LEGACY METHODS - DEPRECATED (redirect to required methods)
    // ==================================================================================

    /**
     * @description DEPRECATED: Use getRequiredConfig() instead.
     *              This method now delegates to getRequiredConfig() and will throw
     *              on missing/invalid config rather than returning defaults.
     *
     * @return ConfigDTO from getRequiredConfig()
     * @throws PaymentCalcConfigException if config is missing or invalid
     */
    @AuraEnabled(cacheable=true)
    public static ConfigDTO getConfig() {
        return getRequiredConfig();
    }

    /**
     * @description DEPRECATED: Use getRequiredConfigForProgram() instead.
     *              This method now delegates to getRequiredConfigForProgram() and will throw
     *              on missing/invalid config rather than returning defaults.
     *
     * @param programType The program type
     * @return ConfigDTO from getRequiredConfigForProgram()
     * @throws PaymentCalcConfigException if config is missing or invalid
     */
    @AuraEnabled(cacheable=true)
    public static ConfigDTO getConfigForProgram(String programType) {
        return getRequiredConfigForProgram(programType);
    }

    // ==================================================================================
    // TEST SUPPORT
    // ==================================================================================

    /**
     * @description Clears the per-transaction cache. Only for use in tests.
     */
    @TestVisible
    private static void clearCache() {
        cachedDefaultConfig = null;
        cachedProgramConfigs.clear();
    }

    /**
     * @description Exposes validation for testing. Only for use in tests.
     * @param dto The ConfigDTO to validate
     * @param configName The config name for error messages
     * @throws PaymentCalcConfigException if validation fails
     */
    @TestVisible
    private static void validateConfigForTest(ConfigDTO dto, String configName) {
        String correlationId = generateCorrelationId();
        validateConfig(dto, configName, correlationId);
    }

    // ==================================================================================
    // PRIVATE IMPLEMENTATION
    // ==================================================================================

    /**
     * @description Maps CMDT record fields to ConfigDTO with program-specific overrides
     */
    private static ConfigDTO mapMdtToDto(Payment_Calc_Config__mdt mdt, String programType) {
        ConfigDTO dto = new ConfigDTO();

        // Core fee configuration
        dto.settlementPercent = mdt.Settlement_Percentage__c;
        dto.programFeePercent = mdt.Program_Fee_Percentage__c;
        dto.bankingFee = mdt.Banking_Fee__c;
        dto.bank2Fee = mdt.Bank2_Fee__c;

        // Program-specific split ratios
        // DCG_MOD_CA uses the same ratios as DCG_MOD (it's DCG_MOD with no-fee enabled)
        String normalizedType = programType != null ? programType.toUpperCase() : null;
        Boolean isDebt = (normalizedType == 'DCG_DEBT');
        Boolean isMod = (normalizedType == 'DCG_MOD' || normalizedType == 'DCG_MOD_CA');

        if (normalizedType != null) {
            dto.programSplitRatio = isDebt ? mdt.Debt_Program_Split_Ratio__c : mdt.Mod_Program_Split_Ratio__c;
            dto.escrowSplitRatio = isDebt ? mdt.Debt_Escrow_Split_Ratio__c : mdt.Mod_Escrow_Split_Ratio__c;

            // Fall back to generic split ratios if program-specific ones are null
            if (dto.programSplitRatio == null) {
                dto.programSplitRatio = mdt.Program_Split_Ratio__c;
            }
            if (dto.escrowSplitRatio == null) {
                dto.escrowSplitRatio = mdt.Escrow_Split_Ratio__c;
            }
        } else {
            dto.programSplitRatio = mdt.Program_Split_Ratio__c;
            dto.escrowSplitRatio = mdt.Escrow_Split_Ratio__c;
        }

        // Setup fee configuration
        dto.setupFee = mdt.Setup_Fee__c;
        dto.setupFeePayments = mdt.Setup_Fee_Payments__c;
        dto.noFeeSetupFee = mdt.No_Fee_Setup_Fee__c;
        dto.debtProgramSetupFee = mdt.Debt_Program_Setup_Fee__c;  // Setup fee for DCG Debt
        dto.setupFeeMinPayments = mdt.Setup_Fee_Min_Payments__c;
        dto.setupFeeMaxPayments = mdt.Setup_Fee_Max_Payments__c;

        // Weekly payment thresholds
        dto.minWeeklyTargetPayment = mdt.Min_Weekly_Target_Payment__c;
        dto.minWeeklyTargetPaymentDcgDebt = mdt.Min_Weekly_Target_Payment_DCG_Debt__c;

        // Program duration configuration
        dto.minProgramWeeks = mdt.Min_Program_Weeks__c;
        dto.maxProgramWeeks = mdt.Max_Program_Weeks__c;
        dto.defaultProgramWeeks = mdt.Default_Program_Weeks__c;
        dto.recommendedMinWeeks = mdt.Recommended_Min_Weeks__c;

        // Target payment configuration
        dto.targetPaymentPercentage = mdt.Target_Payment_Percentage__c;
        dto.minTargetPercentDcgMod = mdt.Min_Target_Percent_DCG_Mod__c;
        dto.minTargetPercentDcgDebt = mdt.Min_Target_Percent_DCG_Debt__c;
        dto.maxTargetPercent = mdt.Max_Target_Percent__c;

        // Conversion & calculation factors
        dto.weeklyToMonthlyFactor = mdt.Weekly_To_Monthly_Factor__c;
        dto.paymentFallbackRatio = mdt.Payment_Fallback_Ratio__c;
        dto.priorityAdjustmentMultiplier = mdt.Priority_Adjustment_Multiplier__c;
        dto.firstPaymentDaysOffset = mdt.First_Payment_Days_Offset__c;

        // Additional product fees
        dto.legalMonitoringWeeklyFee = mdt.Legal_Monitoring_Weekly_Fee__c;

        // Validation range configuration
        dto.validSettlementValues = mdt.Valid_Settlement_Values__c;
        dto.minProgramFeePercent = mdt.Min_Program_Fee_Percent__c;
        dto.maxProgramFeePercent = mdt.Max_Program_Fee_Percent__c;
        dto.baselineNoFeeProgramFee = mdt.Baseline_No_Fee_Program_Fee__c;

        return dto;
    }

    /**
     * @description Validates all required configuration fields.
     *              Throws PaymentCalcConfigException if any validation fails.
     */
    private static void validateConfig(ConfigDTO dto, String configName, String correlationId) {
        List<String> errors = new List<String>();

        // Core fee validation - REQUIRED, must be non-negative
        validateNonNegative(dto.settlementPercent, 'settlementPercent', errors);
        validateNonNegative(dto.programFeePercent, 'programFeePercent', errors);
        validateNonNegative(dto.bankingFee, 'bankingFee', errors);
        validateNonNegative(dto.bank2Fee, 'bank2Fee', errors);

        // Split ratios - REQUIRED, must be between 0 and 1
        validateRange(dto.programSplitRatio, 'programSplitRatio', 0, 1, errors);
        validateRange(dto.escrowSplitRatio, 'escrowSplitRatio', 0, 1, errors);

        // Setup fee configuration - REQUIRED
        validateNonNegative(dto.setupFee, 'setupFee', errors);
        validateMinimum(dto.setupFeePayments, 'setupFeePayments', 1, errors);
        validateNonNegative(dto.noFeeSetupFee, 'noFeeSetupFee', errors);
        validateMinimum(dto.setupFeeMinPayments, 'setupFeeMinPayments', 1, errors);
        validateMinimum(dto.setupFeeMaxPayments, 'setupFeeMaxPayments', 1, errors);

        // Program duration - REQUIRED, must have valid ranges
        validateMinimum(dto.minProgramWeeks, 'minProgramWeeks', 1, errors);
        validateMinimum(dto.maxProgramWeeks, 'maxProgramWeeks', 1, errors);
        validateMinimum(dto.defaultProgramWeeks, 'defaultProgramWeeks', 1, errors);
        validateMinimum(dto.recommendedMinWeeks, 'recommendedMinWeeks', 1, errors);

        // Target payment - REQUIRED
        validatePositive(dto.targetPaymentPercentage, 'targetPaymentPercentage', errors);
        validatePositive(dto.minTargetPercentDcgMod, 'minTargetPercentDcgMod', errors);
        validateNonNegative(dto.minTargetPercentDcgDebt, 'minTargetPercentDcgDebt', errors);
        validatePositive(dto.maxTargetPercent, 'maxTargetPercent', errors);

        // Conversion factors - REQUIRED
        validatePositive(dto.weeklyToMonthlyFactor, 'weeklyToMonthlyFactor', errors);
        validateNonNegative(dto.paymentFallbackRatio, 'paymentFallbackRatio', errors);
        validateNonNegative(dto.firstPaymentDaysOffset, 'firstPaymentDaysOffset', errors);

        // Additional products - REQUIRED
        validateNonNegative(dto.legalMonitoringWeeklyFee, 'legalMonitoringWeeklyFee', errors);

        // Validation ranges - REQUIRED
        validateNotBlank(dto.validSettlementValues, 'validSettlementValues', errors);
        validateNonNegative(dto.minProgramFeePercent, 'minProgramFeePercent', errors);
        validateNonNegative(dto.maxProgramFeePercent, 'maxProgramFeePercent', errors);
        validateNonNegative(dto.baselineNoFeeProgramFee, 'baselineNoFeeProgramFee', errors);

        // Range consistency validations
        if (dto.minProgramWeeks != null && dto.maxProgramWeeks != null && dto.minProgramWeeks > dto.maxProgramWeeks) {
            errors.add('minProgramWeeks (' + dto.minProgramWeeks + ') must be <= maxProgramWeeks (' + dto.maxProgramWeeks + ')');
        }
        if (dto.setupFeeMinPayments != null && dto.setupFeeMaxPayments != null && dto.setupFeeMinPayments > dto.setupFeeMaxPayments) {
            errors.add('setupFeeMinPayments (' + dto.setupFeeMinPayments + ') must be <= setupFeeMaxPayments (' + dto.setupFeeMaxPayments + ')');
        }
        if (dto.minProgramFeePercent != null && dto.maxProgramFeePercent != null && dto.minProgramFeePercent > dto.maxProgramFeePercent) {
            errors.add('minProgramFeePercent (' + dto.minProgramFeePercent + ') must be <= maxProgramFeePercent (' + dto.maxProgramFeePercent + ')');
        }

        // If any validation errors, fail fast
        if (!errors.isEmpty()) {
            String firstError = errors[0];
            String allErrors = String.join(errors, '; ');
            handleConfigError(
                'VALIDATION_FAILED',
                'Configuration validation failed: ' + allErrors,
                configName,
                firstError.substringBefore(' '),
                correlationId,
                null
            );

            PaymentCalcConfigException ex = PaymentCalcConfigException.fieldError(
                'Configuration validation failed: ' + allErrors,
                firstError.substringBefore(' '),
                null,
                'VALIDATION_FAILED'
            );
            throw ex;
        }
    }

    // Validation helper methods
    private static void validateNonNegative(Decimal value, String fieldName, List<String> errors) {
        if (value == null) {
            errors.add(fieldName + ' is required but was null');
        } else if (value < 0) {
            errors.add(fieldName + ' must be non-negative (was ' + value + ')');
        }
    }

    private static void validatePositive(Decimal value, String fieldName, List<String> errors) {
        if (value == null) {
            errors.add(fieldName + ' is required but was null');
        } else if (value <= 0) {
            errors.add(fieldName + ' must be positive (was ' + value + ')');
        }
    }

    private static void validateMinimum(Decimal value, String fieldName, Decimal minimum, List<String> errors) {
        if (value == null) {
            errors.add(fieldName + ' is required but was null');
        } else if (value < minimum) {
            errors.add(fieldName + ' must be >= ' + minimum + ' (was ' + value + ')');
        }
    }

    private static void validateRange(Decimal value, String fieldName, Decimal minVal, Decimal maxVal, List<String> errors) {
        if (value == null) {
            errors.add(fieldName + ' is required but was null');
        } else if (value < minVal || value > maxVal) {
            errors.add(fieldName + ' must be between ' + minVal + ' and ' + maxVal + ' (was ' + value + ')');
        }
    }

    private static void validateNotBlank(String value, String fieldName, List<String> errors) {
        if (String.isBlank(value)) {
            errors.add(fieldName + ' is required but was blank/null');
        }
    }

    /**
     * @description Handles config errors by logging with ERROR severity.
     */
    private static void handleConfigError(
        String errorType,
        String message,
        String configName,
        String failedField,
        String correlationId,
        String stackTrace
    ) {
        // Log with ERROR severity for debugging and monitoring via Debug Logs
        System.debug(LoggingLevel.ERROR, '[PaymentCalcConfigSvc] CONFIG ERROR');
        System.debug(LoggingLevel.ERROR, '[PaymentCalcConfigSvc] Error Type: ' + errorType);
        System.debug(LoggingLevel.ERROR, '[PaymentCalcConfigSvc] Message: ' + message);
        System.debug(LoggingLevel.ERROR, '[PaymentCalcConfigSvc] Config Name: ' + configName);
        System.debug(LoggingLevel.ERROR, '[PaymentCalcConfigSvc] Failed Field: ' + failedField);
        System.debug(LoggingLevel.ERROR, '[PaymentCalcConfigSvc] Correlation ID: ' + correlationId);
        System.debug(LoggingLevel.ERROR, '[PaymentCalcConfigSvc] User ID: ' + UserInfo.getUserId());
        if (String.isNotBlank(stackTrace)) {
            System.debug(LoggingLevel.ERROR, '[PaymentCalcConfigSvc] Stack Trace: ' + stackTrace);
        }
    }

    /**
     * @description Generates a unique correlation ID for tracing
     */
    private static String generateCorrelationId() {
        Blob b = Crypto.generateAesKey(128);
        String hex = EncodingUtil.convertToHex(b);
        return hex.substring(0, 8) + '-' + hex.substring(8, 12) + '-' +
               hex.substring(12, 16) + '-' + hex.substring(16, 20) + '-' +
               hex.substring(20, 32);
    }
}