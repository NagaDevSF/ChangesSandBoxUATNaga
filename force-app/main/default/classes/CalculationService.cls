/**
 * @description Service class for handling complex payment plan calculations
 *
 * CRITICAL CONFIGURATION BEHAVIOR:
 * ================================
 * This service requires valid configuration from PaymentCalcConfigSvc.
 * There are NO DEFAULT VALUES or fallbacks. If configuration cannot be
 * loaded, a PaymentCalcConfigException is thrown.
 *
 * @author System
 * @date 2025-08-29
 */
public with sharing class CalculationService {

    // ==================================================================================
    // PUBLIC ACCESSORS - Config values are REQUIRED, no fallbacks
    // ==================================================================================

    /**
     * @description Minimum weekly target payment for standard programs.
     *              REQUIRED - throws PaymentCalcConfigException if config unavailable.
     */
    public static Decimal MIN_WEEKLY_TARGET_PAYMENT {
        get {
            PaymentCalcConfigSvc.ConfigDTO cfg = PaymentCalcConfigSvc.getRequiredConfig();
            return cfg.minWeeklyTargetPayment;
        }
    }

    /**
     * @description Minimum weekly target payment for DCG_DEBT programs.
     *              REQUIRED - throws PaymentCalcConfigException if config unavailable.
     */
    public static Decimal MIN_WEEKLY_TARGET_PAYMENT_DCG_DEBT {
        get {
            PaymentCalcConfigSvc.ConfigDTO cfg = PaymentCalcConfigSvc.getRequiredConfig();
            return cfg.minWeeklyTargetPaymentDcgDebt;
        }
    }

    /**
     * @description Minimum program duration in weeks.
     *              REQUIRED - throws PaymentCalcConfigException if config unavailable.
     */
    public static Integer MIN_WEEKS {
        get {
            PaymentCalcConfigSvc.ConfigDTO cfg = PaymentCalcConfigSvc.getRequiredConfig();
            return cfg.minProgramWeeks.intValue();
        }
    }

    /**
     * @description Maximum program duration in weeks.
     *              REQUIRED - throws PaymentCalcConfigException if config unavailable.
     */
    public static Integer MAX_WEEKS {
        get {
            PaymentCalcConfigSvc.ConfigDTO cfg = PaymentCalcConfigSvc.getRequiredConfig();
            return cfg.maxProgramWeeks.intValue();
        }
    }

    /**
     * @description Legacy overload that accepts creditor opportunities but delegates to rollup-based calculation.
     * @param creditorOpps CreditorOpportunity__c records (used to total debt when rollups aren't provided)
     * @param config Configuration parameters
     * @param recordId Opportunity ID for state-specific rules
     * @return PaymentCalculationResult with detailed breakdown
     */
    public static PaymentCalculationResult calculateAdvancedPaymentPlan(
        List<CreditorOpportunity__c> creditorOpps,
        Map<String, Object> config,
        Id recordId
    ) {
        // Legacy callers may still pass creditorOpps; intentionally ignored in favor of Opportunity rollups.
        Decimal totalDebt;
        Decimal currentPayment;
        try {
            if (recordId != null && recordId.getSObjectType() == Opportunity.SObjectType) {
                Opportunity opp = [
                    SELECT Estimated_Total_Debt__c, Estimated_Current_Payment__c
                    FROM Opportunity
                    WHERE Id = :recordId
                    LIMIT 1
                ];
                totalDebt = opp.Estimated_Total_Debt__c;
                currentPayment = opp.Estimated_Current_Payment__c;
            }
        } catch (QueryException qe) {
            // Opportunity query failed - this is a data issue, not config issue
            totalDebt = null;
            currentPayment = null;
        }

        Map<String, Object> safeConfig = (config == null) ? new Map<String, Object>() : config;
        return calculateAdvancedPaymentPlan(totalDebt, currentPayment, safeConfig, recordId);
    }

    /**
     * @description Calculates payment plan with complex business logic using Opportunity rollup totals
     * @param totalDebt Total debt amount from Opportunity.Estimated_Total_Debt__c
     * @param currentPayment Current payment from Opportunity.Estimated_Current_Payment__c
     * @param config Configuration parameters
     * @param recordId Opportunity ID for state-specific rules
     * @return PaymentCalculationResult with detailed breakdown
     */
    public static PaymentCalculationResult calculateAdvancedPaymentPlan(
        Decimal totalDebt,
        Decimal currentPayment,
        Map<String, Object> config,
        Id recordId
    ) {
        // Load required config upfront - will throw if unavailable
        PaymentCalcConfigSvc.ConfigDTO systemConfig = PaymentCalcConfigSvc.getRequiredConfig();

        PaymentCalculationResult result = new PaymentCalculationResult();

        // Ensure split ratios are set consistently across all calculation modes
        // Prefer CMDT-backed values placed into config; fallback to CMDT lookup
        String programType = (String)config.get('programType');
        if (programType == null) programType = 'DCG_MOD';

        Decimal initSplitRatio = (config.containsKey('programSplitRatio') && config.get('programSplitRatio') != null)
            ? (Decimal)config.get('programSplitRatio') : null;
        Decimal initEscrowRatio = (config.containsKey('escrowSplitRatio') && config.get('escrowSplitRatio') != null)
            ? (Decimal)config.get('escrowSplitRatio') : null;

        if (initSplitRatio == null || initEscrowRatio == null) {
            // Load program-specific config - will throw if unavailable
            PaymentCalcConfigSvc.ConfigDTO programConfig = PaymentCalcConfigSvc.getRequiredConfigForProgram(programType);
            if (initSplitRatio == null) initSplitRatio = programConfig.programSplitRatio;
            if (initEscrowRatio == null) initEscrowRatio = programConfig.escrowSplitRatio;

            // Hydrate commonly used values into config when missing
            if (!config.containsKey('settlementPercentage'))
                config.put('settlementPercentage', programConfig.settlementPercent);
            if (!config.containsKey('programFeePercentage'))
                config.put('programFeePercentage', programConfig.programFeePercent);
            if (!config.containsKey('bankingFee'))
                config.put('bankingFee', programConfig.bankingFee);
            if (!config.containsKey('bank2Fee'))
                config.put('bank2Fee', programConfig.bank2Fee);
        }

        result.splitRatio = initSplitRatio;
        result.escrowRatio = initEscrowRatio;

        // Store currentPayment in config for downstream calculations
        if (currentPayment != null) {
            config.put('currentPayment', currentPayment);
        }

        // Create debt breakdown from totals (no longer iterating creditors)
        DebtBreakdown debtBreakdown = createDebtBreakdown(totalDebt);
        result.debtBreakdown = debtBreakdown;

        // Apply calculation mode
        String calculationMode = (String)config.get('calculationMode');
        if (calculationMode == 'percentage') {
            result = calculatePercentageBasedPlan(result, config, systemConfig);
        } else if (calculationMode == 'desired_payment') {
            result = calculateDesiredPaymentPlan(result, config, systemConfig);
        } else {
            result = calculateStandardPlan(result, config, systemConfig);
        }

        // Re-apply split ratios after calculation in case inner methods did not set them
        if (result.splitRatio == null || result.escrowRatio == null) {
            result.splitRatio = initSplitRatio;
            result.escrowRatio = 1 - initSplitRatio;
        }

        // Ensure no-fee programs retain original amortization length
        result = applyNoFeeProgramAdjustments(result, config, systemConfig);

        // Apply validation rules
        result = validateAndAdjustPlan(result, config, systemConfig);

        // Calculate payment schedule
        try {
            result.paymentSchedule = generatePaymentSchedule(result, config, systemConfig);
        } catch (Exception e) {
            throw new CalculationException('Advanced calculation failed: ' + e.getMessage());
        }

        return result;
    }

    /**
     * @description Creates debt breakdown from total debt amount (using Opportunity rollup fields)
     * @param totalDebt Total debt from Opportunity.Estimated_Total_Debt__c
     * @return DebtBreakdown object with total debt
     */
    private static DebtBreakdown createDebtBreakdown(Decimal totalDebt) {
        DebtBreakdown breakdown = new DebtBreakdown();

        if (totalDebt == null || totalDebt <= 0) {
            return breakdown;
        }

        breakdown.totalDebt = totalDebt;
        breakdown.otherDebt = totalDebt;
        breakdown.hasPriorityCreditors = false;
        breakdown.priorityDebt = 0;

        return breakdown;
    }

    /**
     * @description Calculates plan based on percentage parameters
     */
    private static PaymentCalculationResult calculatePercentageBasedPlan(
        PaymentCalculationResult result,
        Map<String, Object> config,
        PaymentCalcConfigSvc.ConfigDTO systemConfig
    ) {
        // Get configuration values - use config map first, then system config
        Decimal settlementPercentage = config.get('settlementPercentage') != null ?
            (Decimal)config.get('settlementPercentage') : systemConfig.settlementPercent;
        Decimal programFeePercentage = config.get('programFeePercentage') != null ?
            (Decimal)config.get('programFeePercentage') : systemConfig.programFeePercent;
        Decimal targetPaymentPercentage = config.get('targetPaymentPercentage') != null ?
            (Decimal)config.get('targetPaymentPercentage') : systemConfig.targetPaymentPercentage;
        Decimal currentPayment = config.get('currentPayment') != null ?
            (Decimal)config.get('currentPayment') : 0;
        String programType = config.get('programType') != null ? (String)config.get('programType') : 'Unknown';

        // Calculate settlement and program fees
        result.settlementAmount = result.debtBreakdown.totalDebt * (settlementPercentage / 100);
        result.programFee = result.debtBreakdown.totalDebt * (programFeePercentage / 100);

        // Calculate target weekly payment based on percentage of current payment
        Decimal targetWeeklyPayment = 0;
        if (currentPayment != null && currentPayment > 0) {
            targetWeeklyPayment = currentPayment * (targetPaymentPercentage / 100);
        } else {
            // Fallback: estimate from total debt using config ratio
            targetWeeklyPayment = result.debtBreakdown.totalDebt * (systemConfig.paymentFallbackRatio / 100);
        }

        // Calculate effective minimum using both percentage-based and absolute floors
        Decimal effectiveMinPayment = calculateEffectiveMinWeeklyPayment(
            currentPayment, programType, systemConfig);
        targetWeeklyPayment = Math.max(effectiveMinPayment, targetWeeklyPayment);

        // Get fees from configuration
        result.setupFee = config.get('setupFee') != null ? (Decimal)config.get('setupFee') : systemConfig.setupFee;
        result.setupFeePayments = config.get('setupFeePayments') != null ?
            (Integer)config.get('setupFeePayments') : systemConfig.setupFeePayments.intValue();
        result.bankingFee = config.get('bankingFee') != null ? (Decimal)config.get('bankingFee') : systemConfig.bankingFee;
        result.bank2Fee = config.get('bank2Fee') != null ? (Decimal)config.get('bank2Fee') : systemConfig.bank2Fee;

        // Calculate setup fee per payment
        Decimal setupFeePerPayment = result.setupFee / result.setupFeePayments;

        // Setup fee is ON TOP of base payment for first N payments
        Decimal weeklyFeesPerPayment = result.bankingFee;
        Decimal availableForProgram = targetWeeklyPayment - weeklyFeesPerPayment;

        // Calculate total program cost
        Decimal totalProgramCost = result.settlementAmount + result.programFee + result.setupFee;

        // Calculate number of weeks needed
        if (availableForProgram > 0) {
            Decimal baselineProgramFee = result.programFee;
            Boolean isNoFeeProgram = getNoFeeFlag(config);

            if (isNoFeeProgram) {
                Decimal baselinePct = getNoFeeBaselinePercentage(config, systemConfig);
                if (baselinePct != null) {
                    Decimal debt = (result.debtBreakdown != null && result.debtBreakdown.totalDebt != null)
                        ? result.debtBreakdown.totalDebt : 0;
                    baselineProgramFee = debt * (baselinePct / 100);
                }
            }

            Decimal totalWithoutSetup = result.settlementAmount + baselineProgramFee;
            result.numberOfWeeks = Math.ceil(totalWithoutSetup / availableForProgram).intValue();
        } else {
            result.numberOfWeeks = systemConfig.maxProgramWeeks.intValue();
        }

        // Apply min/max constraints from config
        result.numberOfWeeks = Math.max(systemConfig.minProgramWeeks.intValue(),
            Math.min(systemConfig.maxProgramWeeks.intValue(), result.numberOfWeeks));

        result.weeklyPayment = targetWeeklyPayment;

        // Priority debt adjustment
        if (result.debtBreakdown.hasPriorityCreditors) {
            result.priorityAdjustment = result.debtBreakdown.priorityDebt *
                (systemConfig.priorityAdjustmentMultiplier / 100);
            result.settlementAmount += result.priorityAdjustment;
        }

        return result;
    }

    /**
     * @description Calculates plan based on desired payment amount
     */
    private static PaymentCalculationResult calculateDesiredPaymentPlan(
        PaymentCalculationResult result,
        Map<String, Object> config,
        PaymentCalcConfigSvc.ConfigDTO systemConfig
    ) {
        // Inputs
        Decimal desiredPayment = (Decimal)config.get('desiredWeeklyPayment');
        String programType = (String)config.get('programType');
        if (desiredPayment == null) desiredPayment = 0;

        // Calculate effective minimum using both percentage-based and absolute floors
        Decimal currentPayment = config.get('currentPayment') != null
            ? (Decimal)config.get('currentPayment') : null;
        Decimal effectiveMinPayment = calculateEffectiveMinWeeklyPayment(
            currentPayment, programType, systemConfig);
        desiredPayment = Math.max(effectiveMinPayment, desiredPayment);

        Decimal maxSettlementPercentage = (Decimal)config.get('maxSettlementPercentage');
        if (maxSettlementPercentage == null) maxSettlementPercentage = systemConfig.settlementPercent;

        // Fees from config or system config
        result.bankingFee = config.get('bankingFee') != null ? (Decimal)config.get('bankingFee') : systemConfig.bankingFee;
        result.bank2Fee = config.get('bank2Fee') != null ? (Decimal)config.get('bank2Fee') : systemConfig.bank2Fee;
        result.setupFee = config.get('setupFee') != null ? (Decimal)config.get('setupFee') : systemConfig.setupFee;
        result.setupFeePayments = config.get('setupFeePayments') != null ?
            (Integer)config.get('setupFeePayments') : systemConfig.setupFeePayments.intValue();

        // Program fee from percentage of total debt
        Decimal programFeePct = config.get('programFeePercentage') != null ?
            (Decimal)config.get('programFeePercentage') : systemConfig.programFeePercent;
        result.programFee = (result.debtBreakdown.totalDebt != null ? result.debtBreakdown.totalDebt : 0) * (programFeePct / 100);

        // Work backwards from desired payment
        Decimal weeklyFees = calculateWeeklyFees(config, systemConfig);
        Decimal netPerWeek = desiredPayment - weeklyFees;
        if (netPerWeek < 0) netPerWeek = 0;

        // Calculate settlement amount
        Decimal settlementPercentage = config.get('settlementPercentage') != null ?
            (Decimal)config.get('settlementPercentage') : systemConfig.settlementPercent;
        result.settlementAmount = result.debtBreakdown.totalDebt * (settlementPercentage / 100);

        // Duration preservation for No-Fee programs
        Decimal baselineProgramFee = result.programFee;
        Boolean isNoFeeProgram = getNoFeeFlag(config);

        if (isNoFeeProgram) {
            Decimal baselinePct = getNoFeeBaselinePercentage(config, systemConfig);
            if (baselinePct != null) {
                Decimal debt = (result.debtBreakdown != null && result.debtBreakdown.totalDebt != null)
                    ? result.debtBreakdown.totalDebt : 0;
                baselineProgramFee = debt * (baselinePct / 100);
            }
        }

        // Calculate weeks based on TOTAL program cost
        Decimal totalProgramCost = result.settlementAmount + baselineProgramFee;
        Decimal estimatedWeeks = 0;
        if (netPerWeek > 0) {
            estimatedWeeks = totalProgramCost / netPerWeek;
        }
        estimatedWeeks = Math.max(systemConfig.minProgramWeeks, Math.min(systemConfig.maxProgramWeeks, estimatedWeeks));

        result.numberOfWeeks = Math.ceil(estimatedWeeks).intValue();
        result.weeklyPayment = desiredPayment;

        // Apply max settlement cap if specified
        Decimal maxSettlement = (result.debtBreakdown.totalDebt != null ? result.debtBreakdown.totalDebt : 0) *
            (maxSettlementPercentage / 100);
        if (result.settlementAmount > maxSettlement) {
            result.settlementAmount = maxSettlement;
            Decimal adjustedTotalCost = result.settlementAmount + baselineProgramFee;
            if (netPerWeek > 0) {
                result.numberOfWeeks = Math.ceil(adjustedTotalCost / netPerWeek).intValue();
                result.numberOfWeeks = Math.max(systemConfig.minProgramWeeks.intValue(),
                    Math.min(systemConfig.maxProgramWeeks.intValue(), result.numberOfWeeks));
            }
        }
        return result;
    }

    /**
     * @description Calculates standard payment plan
     */
    private static PaymentCalculationResult calculateStandardPlan(
        PaymentCalculationResult result,
        Map<String, Object> config,
        PaymentCalcConfigSvc.ConfigDTO systemConfig
    ) {
        // Prefer values from config; use system config as source of truth
        Decimal settlementPercentage = config.get('settlementPercentage') != null ?
            (Decimal)config.get('settlementPercentage') : systemConfig.settlementPercent;
        Decimal programFeePercentage = config.get('programFeePercentage') != null ?
            (Decimal)config.get('programFeePercentage') : systemConfig.programFeePercent;

        // Get program type for split ratio determination
        String programType = (String)config.get('programType');
        if (programType == null) programType = 'DCG_MOD';

        // Apply split ratio from config or system config
        Decimal splitRatio = config.get('programSplitRatio') != null ?
            (Decimal)config.get('programSplitRatio') : systemConfig.programSplitRatio;

        // Calculate settlement and program fees
        result.settlementAmount = result.debtBreakdown.totalDebt * (settlementPercentage / 100);
        result.programFee = result.debtBreakdown.totalDebt * (programFeePercentage / 100);
        result.splitRatio = splitRatio;
        result.escrowRatio = config.get('escrowSplitRatio') != null ?
            (Decimal)config.get('escrowSplitRatio') : (1 - splitRatio);

        // Add setup fee and banking fees
        result.setupFee = config.get('setupFee') != null ? (Decimal)config.get('setupFee') : systemConfig.setupFee;
        result.setupFeePayments = config.get('setupFeePayments') != null ?
            (Integer)config.get('setupFeePayments') : systemConfig.setupFeePayments.intValue();
        result.bankingFee = config.get('bankingFee') != null ? (Decimal)config.get('bankingFee') : systemConfig.bankingFee;
        result.bank2Fee = config.get('bank2Fee') != null ? (Decimal)config.get('bank2Fee') : systemConfig.bank2Fee;

        return result;
    }

    /**
     * @description Reallocate the calculated program fee back into the settlement bucket
     *              for no-fee programs so the repayment term remains unchanged.
     */
    private static PaymentCalculationResult applyNoFeeProgramAdjustments(
        PaymentCalculationResult result,
        Map<String, Object> config,
        PaymentCalcConfigSvc.ConfigDTO systemConfig
    ) {
        if (result == null || config == null) {
            return result;
        }

        Boolean noFeeProgram = getNoFeeFlag(config);
        if (!noFeeProgram) {
            return result;
        }

        Boolean alreadyAdjusted = false;
        if (config.containsKey('noFeeProgramAdjustmentComplete') && config.get('noFeeProgramAdjustmentComplete') != null) {
            alreadyAdjusted = (Boolean)config.get('noFeeProgramAdjustmentComplete');
        }
        if (alreadyAdjusted) {
            return result;
        }

        Decimal baselineProgramFeePct = getNoFeeBaselinePercentage(config, systemConfig);

        Decimal totalDebt = 0;
        if (result.debtBreakdown != null && result.debtBreakdown.totalDebt != null) {
            totalDebt = result.debtBreakdown.totalDebt;
        }

        Decimal programFeeToReallocate = result.programFee;
        if (programFeeToReallocate == null || programFeeToReallocate <= 0) {
            programFeeToReallocate = totalDebt * (baselineProgramFeePct / 100);
        }
        if (programFeeToReallocate == null || programFeeToReallocate <= 0) {
            result.programFee = 0;
            config.put('noFeeProgramAdjustmentComplete', true);
            return result;
        }

        Decimal currentSettlement = (result.settlementAmount != null) ? result.settlementAmount : 0;
        result.settlementAmount = currentSettlement + programFeeToReallocate;
        result.programFee = 0;

        config.put('noFeeProgramAdjustmentComplete', true);
        return result;
    }

    /**
     * @description Validates and adjusts payment plan to meet business rules
     */
    private static PaymentCalculationResult validateAndAdjustPlan(
        PaymentCalculationResult result,
        Map<String, Object> config,
        PaymentCalcConfigSvc.ConfigDTO systemConfig
    ) {
        // Minimum and maximum constraints from config
        Decimal rawMinWeekly = (Decimal)config.get('minWeeklyPayment');
        String programType = (String)config.get('programType');
        if (programType == null) programType = 'DCG_MOD';

        // Calculate effective minimum using both percentage-based and absolute floors
        Decimal currentPayment = config.get('currentPayment') != null
            ? (Decimal)config.get('currentPayment') : null;
        Decimal effectiveMinPayment = calculateEffectiveMinWeeklyPayment(
            currentPayment, programType, systemConfig);

        Boolean minProvided = rawMinWeekly != null && rawMinWeekly >= effectiveMinPayment;
        Decimal minWeeklyPayment = (rawMinWeekly == null || rawMinWeekly < effectiveMinPayment)
            ? effectiveMinPayment : rawMinWeekly;

        Decimal rawMaxWeekly = (Decimal)config.get('maxWeeklyPayment');
        Boolean maxProvided = rawMaxWeekly != null && rawMaxWeekly >= minWeeklyPayment;
        Decimal maxWeeklyPayment = rawMaxWeekly;
        if (maxWeeklyPayment != null && maxWeeklyPayment < minWeeklyPayment) {
            maxWeeklyPayment = minWeeklyPayment;
        }

        // Debug: Log values for troubleshooting minimum payment enforcement
        System.debug('[CalculationService] validateAndAdjust - currentPayment: ' + currentPayment);
        System.debug('[CalculationService] validateAndAdjust - effectiveMinPayment: ' + effectiveMinPayment);
        System.debug('[CalculationService] validateAndAdjust - minWeeklyPayment: ' + minWeeklyPayment);
        System.debug('[CalculationService] validateAndAdjust - result.weeklyPayment BEFORE: ' + result.weeklyPayment);

        if (result.weeklyPayment == null || result.weeklyPayment < minWeeklyPayment) {
            result.weeklyPayment = minWeeklyPayment;
            System.debug('[CalculationService] validateAndAdjust - ENFORCED minimum, result.weeklyPayment NOW: ' + result.weeklyPayment);
            if (minProvided) {
                result.validationMessages.add('Weekly payment adjusted to minimum: $' + minWeeklyPayment);
            }
        }

        if (maxWeeklyPayment != null && result.weeklyPayment > maxWeeklyPayment) {
            result.weeklyPayment = maxWeeklyPayment;
            if (maxProvided) {
                result.validationMessages.add('Weekly payment adjusted to maximum: $' + maxWeeklyPayment);
            }
        }

        // Duration constraints from config
        Integer minWeeks = systemConfig.minProgramWeeks.intValue();
        Integer maxWeeks = systemConfig.maxProgramWeeks.intValue();

        if (result.numberOfWeeks < minWeeks) {
            result.numberOfWeeks = minWeeks;
            result.validationMessages.add('Program duration adjusted to minimum: ' + minWeeks + ' weeks');
        }

        if (result.numberOfWeeks > maxWeeks) {
            result.numberOfWeeks = maxWeeks;
            result.validationMessages.add('Program duration adjusted to maximum: ' + maxWeeks + ' weeks');
        }

        return result;
    }

    /**
     * @description Builds a precise schedule of setup fee installments
     */
    private static List<Decimal> calculateSetupFeeInstallments(Decimal totalSetupFee, Integer installmentCount) {
        List<Decimal> installments = new List<Decimal>();

        if (totalSetupFee == null || totalSetupFee <= 0 || installmentCount == null || installmentCount <= 0) {
            return installments;
        }

        // Front-load distribution: extra cents go to FIRST payments, ensuring last payment never exceeds others
        // Work in cents to avoid floating point issues
        Long totalCents = (totalSetupFee * 100).round(System.RoundingMode.HALF_UP);
        Long baseCents = totalCents / installmentCount;  // Integer division floors
        Long remainderCents = totalCents - (baseCents * installmentCount);

        for (Integer i = 0; i < installmentCount; i++) {
            Decimal installment;
            if (i < remainderCents) {
                // First 'remainder' payments get an extra cent
                installment = (baseCents + 1) / 100.0;
            } else {
                installment = baseCents / 100.0;
            }
            installments.add(installment.setScale(2, System.RoundingMode.HALF_UP));
        }

        return installments;
    }

    /**
     * @description Generates detailed payment schedule with dynamic fee allocation
     */
    private static List<PaymentScheduleEntry> generatePaymentSchedule(
        PaymentCalculationResult result,
        Map<String, Object> config,
        PaymentCalcConfigSvc.ConfigDTO systemConfig
    ) {
        List<PaymentScheduleEntry> schedule = new List<PaymentScheduleEntry>();

        // Get configuration values
        String firstDraftDateStr = (String)config.get('firstDraftDate');
        Integer preferredDayOfWeek = (Integer)config.get('preferredDayOfWeek');

        // Weekly total for additional products
        Decimal additionalProductsWeeklyTotal = 0;
        if (config.containsKey('additionalProductsWeeklyTotal') && config.get('additionalProductsWeeklyTotal') != null) {
            additionalProductsWeeklyTotal = (Decimal)config.get('additionalProductsWeeklyTotal');
        }

        // Parse first draft date or use next business day
        Date startDate;
        if (String.isNotBlank(firstDraftDateStr)) {
            startDate = Date.valueOf(firstDraftDateStr);
        } else {
            startDate = getNextBusinessDay();
        }

        // Get split ratios
        Decimal programSplitRatio = result.splitRatio != null ? result.splitRatio : systemConfig.programSplitRatio;
        Decimal escrowSplitRatio = result.escrowRatio != null ? result.escrowRatio : systemConfig.escrowSplitRatio;

        // Pre-calculate setup fee installments
        List<Decimal> setupFeeInstallments = calculateSetupFeeInstallments(result.setupFee, result.setupFeePayments);

        // Calculate exact payment distribution
        Decimal settlementAmount = result.settlementAmount != null ? result.settlementAmount : 0;
        Decimal programFee = result.programFee != null ? result.programFee : 0;
        Decimal weeklyPayment = result.weeklyPayment != null ? result.weeklyPayment : 0;
        Decimal bankingFee = result.bankingFee != null ? result.bankingFee : systemConfig.bankingFee;

        Decimal totalProgramCost = settlementAmount + programFee;
        Decimal netWeeklyCapacity = weeklyPayment - bankingFee;

        // Calculate precise payment distribution using front-loading
        // Weeks 1..N-1 are equal; last payment absorbs the rounding remainder
        List<Decimal> netPaymentAmounts = new List<Decimal>();
        if (netWeeklyCapacity > 0 && totalProgramCost > 0) {
            // Use FLOOR to keep the average at/above minimum; last payment may be lower
            Integer totalWeeks = Math.floor(totalProgramCost / netWeeklyCapacity).intValue();
            totalWeeks = Math.max(1, totalWeeks); // Ensure at least 1 week

            // Apply min/max week constraints
            totalWeeks = Math.max(totalWeeks, systemConfig.minProgramWeeks.intValue());
            totalWeeks = Math.min(totalWeeks, systemConfig.maxProgramWeeks.intValue());

            // Work in cents to avoid floating point issues
            Long totalCents = (totalProgramCost * 100).round(System.RoundingMode.HALF_UP);
            Long minNetCents = (netWeeklyCapacity * 100).round(System.RoundingMode.HALF_UP);
            Long baseCents = Math.ceil((Decimal)totalCents / totalWeeks).longValue();

            // VALIDATION: If week constraints forced payments below minimum for the first payments, reduce weeks
            if (baseCents < minNetCents) {
                totalWeeks = Math.floor(totalProgramCost / netWeeklyCapacity).intValue();
                totalWeeks = Math.max(1, totalWeeks);
                baseCents = Math.ceil((Decimal)totalCents / totalWeeks).longValue();
            }
            Long lastCents = totalCents - (baseCents * (totalWeeks - 1));

            for (Integer i = 0; i < totalWeeks; i++) {
                Long cents = (i < totalWeeks - 1) ? baseCents : lastCents;
                Decimal payment = cents / 100.0;
                if (payment > 0) {
                    netPaymentAmounts.add(payment.setScale(2, System.RoundingMode.HALF_UP));
                }
            }
        }

        // Adjust weeks if needed
        Integer actualWeeks = netPaymentAmounts.size();
        if (actualWeeks != result.numberOfWeeks) {
            result.numberOfWeeks = actualWeeks;
        }

        // Pre-calculate program/escrow allocation
        List<Decimal> programAmounts = new List<Decimal>();
        List<Decimal> escrowAmounts = new List<Decimal>();
        Decimal remainingProgramFees = programFee;

        for (Integer i = 0; i < netPaymentAmounts.size(); i++) {
            Decimal netAmount = netPaymentAmounts[i];
            Decimal programPayment = 0;
            Decimal escrowPayment = 0;

            if (remainingProgramFees > 0) {
                Decimal desiredProgram = netAmount * programSplitRatio;
                programPayment = Math.min(desiredProgram, remainingProgramFees);
                escrowPayment = netAmount - programPayment;
                remainingProgramFees -= programPayment;
            } else {
                escrowPayment = netAmount;
            }

            programAmounts.add(programPayment);
            escrowAmounts.add(escrowPayment);
        }

        // Track remaining settlement for display
        Decimal remainingSettlement = settlementAmount;
        Decimal remainingSetupFee = (result.setupFee != null) ? result.setupFee.setScale(2, System.RoundingMode.HALF_UP) : 0;

        for (Integer week = 1; week <= result.numberOfWeeks; week++) {
            PaymentScheduleEntry entry = new PaymentScheduleEntry();
            entry.weekNumber = week;

            // Calculate payment date
            if (week == 1) {
                entry.paymentDate = startDate;
            } else if (week == 2 && preferredDayOfWeek != null) {
                entry.paymentDate = getNextPreferredDay(startDate, preferredDayOfWeek);
            } else {
                Date previousDate = schedule.get(week - 2).paymentDate;
                entry.paymentDate = previousDate.addDays(7);
            }

            // Get pre-calculated precise amounts
            Integer weekIndex = week - 1;
            Decimal netPaymentAmount = weekIndex < netPaymentAmounts.size() ? netPaymentAmounts[weekIndex] : 0;
            Decimal programPayment = weekIndex < programAmounts.size() ? programAmounts[weekIndex] : 0;
            Decimal escrowPayment = weekIndex < escrowAmounts.size() ? escrowAmounts[weekIndex] : 0;

            // Base payment amount
            entry.paymentAmount = netPaymentAmount + bankingFee;

            // Setup fee is ON TOP of base payment
            Decimal currentSetupFee = 0;
            if (week <= setupFeeInstallments.size() && remainingSetupFee > 0) {
                currentSetupFee = setupFeeInstallments[week - 1];
                remainingSetupFee = (remainingSetupFee - currentSetupFee).setScale(2, System.RoundingMode.HALF_UP);
                if (remainingSetupFee < 0) remainingSetupFee = 0;
                entry.setupFee = currentSetupFee;
                entry.paymentAmount += currentSetupFee;
            } else {
                entry.setupFee = 0;
            }

            entry.bankingFee = bankingFee;
            entry.programAmount = programPayment;
            entry.escrowAmount = escrowPayment;

            // Update remaining settlement
            remainingSettlement -= escrowPayment;
            entry.remainingBalance = Math.max(0, remainingSettlement);

            entry.principalAmount = escrowPayment;
            entry.feesAmount = programPayment + bankingFee + currentSetupFee;

            entry.bank2Fee = 0;
            entry.retainerFee = 0;
            entry.additionalProducts = additionalProductsWeeklyTotal;

            if (entry.additionalProducts != null && entry.additionalProducts > 0) {
                entry.paymentAmount += entry.additionalProducts;
                entry.feesAmount += entry.additionalProducts;
            }

            entry.runningBalance = 0;

            schedule.add(entry);
        }

        return schedule;
    }

    /**
     * @description Gets next occurrence of preferred day of week
     */
    private static Date getNextPreferredDay(Date fromDate, Integer preferredDay) {
        Date nextDate = fromDate.addDays(1);
        Integer currentDayOfWeek = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(nextDate), 7);
        Integer daysToAdd = preferredDay - currentDayOfWeek;
        if (daysToAdd <= 0) {
            daysToAdd += 7;
        }
        return nextDate.addDays(daysToAdd);
    }

    /**
     * @description Calculates weekly fees from configuration
     */
    private static Decimal calculateWeeklyFees(Map<String, Object> config, PaymentCalcConfigSvc.ConfigDTO systemConfig) {
        Decimal bankingFee = config.get('bankingFee') != null ?
            (Decimal)config.get('bankingFee') : systemConfig.bankingFee;
        Decimal bank2Fee = config.get('bank2Fee') != null ?
            (Decimal)config.get('bank2Fee') : systemConfig.bank2Fee;

        return bankingFee + bank2Fee;
    }

    /**
     * @description Calculates settlement amount based on total debt and settlement percentage
     */
    public static Decimal calculateSettlement(Decimal totalDebt, Map<String, Object> config) {
        if (totalDebt == null || totalDebt <= 0) {
            return 0;
        }

        // Get settlement percentage from config
        PaymentCalcConfigSvc.ConfigDTO systemConfig = PaymentCalcConfigSvc.getRequiredConfig();
        Decimal settlementRate = systemConfig.settlementPercent / 100;

        if (config != null && config.containsKey('settlementPercentage')) {
            settlementRate = (Decimal)config.get('settlementPercentage') / 100;
        }

        return totalDebt * settlementRate;
    }

    /**
     * @description Gets settlement rate based on debt type and legal status
     */
    private static Decimal getSettlementRateByDebtType(String debtType, String legalStatus) {
        if (legalStatus == 'COJ' || legalStatus == 'UCC') {
            return 0.85;
        }
        if (legalStatus == 'Lawsuit') {
            return 0.75;
        }

        if (debtType == 'MCA') {
            return 0.65;
        } else if (debtType == 'Business Loan') {
            return 0.55;
        } else if (debtType == 'Credit Card') {
            return 0.40;
        } else if (debtType == 'Line of Credit') {
            return 0.50;
        }

        return 0;
    }

    /**
     * @description Returns estimated average interest rate for debt portfolio
     */
    public static Decimal calculateWeightedInterestRate() {
        return 20.0;
    }

    /**
     * @description Calculates principal amount for a specific week
     */
    private static Decimal calculatePrincipalAmount(PaymentCalculationResult result, Integer weekNumber) {
        return result.settlementAmount / result.numberOfWeeks;
    }

    /**
     * @description Gets next business day (Monday-Friday)
     */
    private static Date getNextBusinessDay() {
        Date today = Date.today();
        Integer dayOfWeek = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(today), 7);

        if (dayOfWeek == 0) {
            return today.addDays(1);
        } else if (dayOfWeek == 6) {
            return today.addDays(2);
        }

        return today.addDays(1);
    }

    /**
     * @description Returns monthly minimum payments from Opportunity rollup
     */
    public static Decimal calculateMonthlyMinimumPayments(Decimal currentPayment) {
        if (currentPayment == null || currentPayment <= 0) {
            return 0;
        }
        return currentPayment;
    }

    // ==================================================================================
    // HELPER METHODS
    // ==================================================================================

    /**
     * @description Safely extracts noFeeProgram flag from config
     */
    private static Boolean getNoFeeFlag(Map<String, Object> config) {
        Boolean noFeeProgram = false;
        if (config.containsKey('noFeeProgram') && config.get('noFeeProgram') != null) {
            noFeeProgram = (Boolean)config.get('noFeeProgram');
        }
        if (!noFeeProgram && config.containsKey('isCaliforniaNoFee') && config.get('isCaliforniaNoFee') != null) {
            noFeeProgram = (Boolean)config.get('isCaliforniaNoFee');
        }
        return noFeeProgram;
    }

    /**
     * @description Gets baseline program fee percentage for no-fee programs
     */
    private static Decimal getNoFeeBaselinePercentage(Map<String, Object> config, PaymentCalcConfigSvc.ConfigDTO systemConfig) {
        if (config.containsKey('noFeeProgramOriginalFeePercentage') &&
            config.get('noFeeProgramOriginalFeePercentage') != null) {
            return (Decimal)config.get('noFeeProgramOriginalFeePercentage');
        }
        if (config.containsKey('programFeePercentage') && config.get('programFeePercentage') != null) {
            return (Decimal)config.get('programFeePercentage');
        }
        return systemConfig.baselineNoFeeProgramFee;
    }

    /**
     * @description Calculates effective minimum weekly payment considering both
     *              percentage-based floor (% of current payment) and absolute minimum.
     *              Mirrors frontend _minimumWeeklyTarget() logic for consistency.
     * @param currentPayment The client's current payment amount (may be null)
     * @param programType The program type (DCG_MOD, DCG_DEBT, DCG_MOD_CA)
     * @param systemConfig Configuration DTO with min payment thresholds
     * @return The effective minimum weekly payment (max of percentage floor and absolute floor)
     */
    private static Decimal calculateEffectiveMinWeeklyPayment(
        Decimal currentPayment,
        String programType,
        PaymentCalcConfigSvc.ConfigDTO systemConfig
    ) {
        Decimal absoluteFloor = (programType == 'DCG_DEBT')
            ? systemConfig.minWeeklyTargetPaymentDcgDebt
            : systemConfig.minWeeklyTargetPayment;

        Decimal percentageFloor = 0;
        if (currentPayment != null && currentPayment > 0) {
            Decimal minTargetPercent = (programType == 'DCG_DEBT')
                ? systemConfig.minTargetPercentDcgDebt
                : systemConfig.minTargetPercentDcgMod;
            percentageFloor = currentPayment * (minTargetPercent / 100);
        }

        return Math.max(absoluteFloor, percentageFloor);
    }

    // ==================================================================================
    // INNER CLASSES
    // ==================================================================================

    public class PaymentCalculationResult {
        @AuraEnabled public DebtBreakdown debtBreakdown { get; set; }
        @AuraEnabled public Decimal settlementAmount { get; set; }
        @AuraEnabled public Decimal programFee { get; set; }
        @AuraEnabled public Decimal priorityAdjustment { get; set; }
        @AuraEnabled public Decimal weeklyPayment { get; set; }
        @AuraEnabled public Integer numberOfWeeks { get; set; }
        @AuraEnabled public List<PaymentScheduleEntry> paymentSchedule { get; set; }
        @AuraEnabled public List<String> validationMessages { get; set; }
        @AuraEnabled public Decimal splitRatio { get; set; }
        @AuraEnabled public Decimal escrowRatio { get; set; }
        @AuraEnabled public Decimal setupFee { get; set; }
        @AuraEnabled public Integer setupFeePayments { get; set; }
        @AuraEnabled public Decimal bankingFee { get; set; }
        @AuraEnabled public Decimal bank2Fee { get; set; }

        public PaymentCalculationResult() {
            this.debtBreakdown = new DebtBreakdown();
            this.priorityAdjustment = 0;
            this.validationMessages = new List<String>();

            // Initialize from required config - will throw if unavailable
            PaymentCalcConfigSvc.ConfigDTO cfg = PaymentCalcConfigSvc.getRequiredConfig();
            this.splitRatio = cfg.programSplitRatio;
            this.escrowRatio = cfg.escrowSplitRatio;
            this.setupFee = cfg.setupFee;
            this.setupFeePayments = cfg.setupFeePayments.intValue();
            this.bankingFee = cfg.bankingFee;
            this.bank2Fee = cfg.bank2Fee;
        }
    }

    public class DebtBreakdown {
        @AuraEnabled public Decimal totalDebt { get; set; }
        @AuraEnabled public Decimal creditCardDebt { get; set; }
        @AuraEnabled public Decimal mcaDebt { get; set; }
        @AuraEnabled public Decimal businessLoanDebt { get; set; }
        @AuraEnabled public Decimal lineOfCreditDebt { get; set; }
        @AuraEnabled public Decimal otherDebt { get; set; }
        @AuraEnabled public Decimal priorityDebt { get; set; }
        @AuraEnabled public Boolean hasPriorityCreditors { get; set; }
        @AuraEnabled public Decimal weightedInterestRate { get; set; }
        @AuraEnabled public Integer totalCreditors { get; set; }
        @AuraEnabled public Integer includedCreditors { get; set; }

        public DebtBreakdown() {
            this.totalDebt = 0;
            this.creditCardDebt = 0;
            this.mcaDebt = 0;
            this.businessLoanDebt = 0;
            this.lineOfCreditDebt = 0;
            this.otherDebt = 0;
            this.priorityDebt = 0;
            this.hasPriorityCreditors = false;
            this.weightedInterestRate = 0;
            this.totalCreditors = 0;
            this.includedCreditors = 0;
        }
    }

    public class PaymentScheduleEntry {
        @AuraEnabled public Integer weekNumber { get; set; }
        @AuraEnabled public Date paymentDate { get; set; }
        @AuraEnabled public Decimal paymentAmount { get; set; }
        @AuraEnabled public Decimal principalAmount { get; set; }
        @AuraEnabled public Decimal feesAmount { get; set; }
        @AuraEnabled public Decimal remainingBalance { get; set; }
        @AuraEnabled public Decimal setupFee { get; set; }
        @AuraEnabled public Decimal bankingFee { get; set; }
        @AuraEnabled public Decimal programAmount { get; set; }
        @AuraEnabled public Decimal escrowAmount { get; set; }
        @AuraEnabled public Decimal bank2Fee { get; set; }
        @AuraEnabled public Decimal retainerFee { get; set; }
        @AuraEnabled public Decimal additionalProducts { get; set; }
        @AuraEnabled public Decimal runningBalance { get; set; }
    }

    public class CalculationException extends Exception {}
}