/**
 * @description Service class for Payment Plan modification operations.
 *
 * Handles plan modifications including:
 * - Updating Opportunity-only fields (weekly payment, number of weeks, etc.)
 * - Previewing plan modifications (EST_CURRENT_PAYMENT, EST_TOTAL_DEBT)
 * - Saving plan modifications as new Draft versions
 *
 * Delegates shared calculation helpers to PaymentPlanCalculationService and
 * uses PaymentPlanEditorController for wrapper types and plan retrieval.
 *
 * @author DCG Development Team
 * @since 2024-01
 * @see PaymentPlanEditorController
 * @see PaymentPlanCalculationService
 * @see PaymentFeeService
 * @see PaymentCalcConfigSvc
 */
public with sharing class PaymentPlanModificationService {

    // ==================================================================================
    // CONSTANTS - CLASS IDENTIFICATION
    // ==================================================================================
    private static final String CLASS_NAME = 'PaymentPlanModificationService';

    // ==================================================================================
    // CONSTANTS - DEBUG LOGGING PREFIXES
    // ==================================================================================
    private static final String LOG_ENTRY = '▶️ ENTRY';
    private static final String LOG_EXIT = '◀️ EXIT';
    private static final String LOG_PARAM = '📋 PARAM';
    private static final String LOG_QUERY = '🔍 QUERY';
    private static final String LOG_DML = '💾 DML';
    private static final String LOG_ERROR = '❌ ERROR';
    private static final String LOG_WARN = '⚠️ WARN';
    private static final String LOG_INFO = 'ℹ️ INFO';
    private static final String LOG_DEBUG = '🔧 DEBUG';
    private static final String LOG_SUCCESS = '✅ SUCCESS';

    // ==================================================================================
    // CONSTANTS - PAYMENT SCHEDULE ITEM STATUS VALUES
    // ==================================================================================
    private static final String STATUS_SCHEDULED = 'Scheduled';
    private static final String STATUS_CLEARED = 'Cleared';
    private static final String STATUS_NSF = 'NSF';
    private static final String STATUS_CANCELLED = 'Cancelled';

    // ==================================================================================
    // CONSTANTS - PAYMENT PLAN VERSION STATUS VALUES
    // ==================================================================================
    private static final String VERSION_STATUS_DRAFT = 'Draft';
    private static final String VERSION_STATUS_ACTIVE = 'Active';
    private static final String VERSION_STATUS_ARCHIVED = 'Archived';

    // ==================================================================================
    // CONSTANTS - DEFAULT VALUES FOR CALCULATIONS
    // ==================================================================================
    private static final Decimal DEFAULT_BANKING_FEE = 15.00;
    private static final Integer PAYMENT_INTERVAL_DAYS = 7;
    private static final Decimal DEFAULT_RETAINER_FEE = 0.00;
    private static final Decimal DEFAULT_SPLIT_RATIO = 0.50;
    private static final Integer DEFAULT_SETUP_FEE_PAYMENTS = 4;
    private static final Integer DEFAULT_NUMBER_OF_PAYMENTS = 52;

    // ==================================================================================
    // CONSTANTS - QUERY AND VALIDATION LIMITS
    // ==================================================================================
    private static final Integer MAX_QUERY_LIMIT = 1000;

    // ==================================================================================
    // CONSTANTS - ERROR MESSAGE SYMBOLS
    // ==================================================================================
    private static final String ERROR_SYMBOL = '⚠️ ';
    private static final String NOT_FOUND_SYMBOL = '🔍 ';
    private static final String VALIDATION_SYMBOL = '❌ ';
    private static final String CONFIG_SYMBOL = '⚙️ ';

    // ==================================================================================
    // CONSTANTS - SOURCE AND VERSION TYPE VALUES
    // ==================================================================================
    private static final String SOURCE_UI = 'UI';
    private static final String VERSION_TYPE_REVISION = 'Revision';

    // ==================================================================================
    // INNER CLASSES
    // ==================================================================================

    /**
     * @description Internal result holder for plan modification calculations.
     * Used by both preview (no DML) and save (with DML) paths.
     */
    private class PlanModificationResult {
        PaymentPlan__c currentPlan;
        Opportunity opp;
        PaymentPlan__c newPlan;
        List<Payment_Schedule_Item__c> nonScheduledItems;
        List<Payment_Schedule_Item__c> existingItems;
        List<Payment_Schedule_Item__c> newItems;
        PaymentPlanEditorController.PlanModificationPreview preview;
        Decimal weeklyPayment;
        Integer numberOfPayments;
        Decimal settlementAmount;
        Decimal programFeeAmount;
    }

    // ==================================================================================
    // PRIVATE HELPERS
    // ==================================================================================

    /**
     * @description Parses a date string in ISO format (YYYY-MM-DD) to a Salesforce Date object.
     * @param dateString The date string to parse (expected format: YYYY-MM-DD)
     * @return The parsed Date object, or null if parsing fails or input is blank
     */
    private static Date parseOpportunityDate(String dateString) {
        if (String.isBlank(dateString)) {
            return null;
        }
        try {
            // Handle ISO format: YYYY-MM-DD
            if (dateString.contains('-')) {
                List<String> parts = dateString.split('-');
                if (parts.size() == 3) {
                    return Date.newInstance(
                        Integer.valueOf(parts[0]),
                        Integer.valueOf(parts[1]),
                        Integer.valueOf(parts[2])
                    );
                }
            }
            // Fallback to valueOf
            return Date.valueOf(dateString);
        } catch (Exception e) {
            System.debug('[parseOpportunityDate] Error parsing date: ' + e.getMessage());
            return null;
        }
    }

    // ==================================================================================
    // PUBLIC SERVICE METHODS
    // ==================================================================================

    /**
     * @description Updates Opportunity fields only (no Payment Plan changes).
     * Validates number of weeks and weekly payment ranges against calculator config.
     * @param recordId The Opportunity record ID
     * @param numberOfWeeks Number of program weeks
     * @param weeklyPayment Desired weekly payment amount
     * @param firstDraftDate First draft date in ISO format (YYYY-MM-DD)
     * @param bankingFee Banking fee per payment
     * @param setupFeeTerm Number of setup fee payments
     * @param noFeeProgram Whether this is a no-fee program
     * @param programType Program type (e.g., DCG_MOD, DCG_DEBT)
     * @param settlementAmount Settlement amount
     * @param programFee Program fee amount
     */
    public static void updateOpportunityOnly(
        Id recordId,
        Integer numberOfWeeks,
        Decimal weeklyPayment,
        String firstDraftDate,
        Decimal bankingFee,
        Integer setupFeeTerm,
        Boolean noFeeProgram,
        String programType,
        Decimal settlementAmount,
        Decimal programFee
    ) {
        try {
            String sObjectType = recordId.getSObjectType().getDescribe().getName();

            // Only update Opportunity records
            if (sObjectType != 'Opportunity') {
                throw new AuraHandledException('Record must be an Opportunity');
            }

            // ============ VALIDATION: Number of Weeks and Weekly Payment Ranges ============
            // Get config for validation - if config fails, skip validation but allow save
            PaymentCalcConfigSvc.ConfigDTO cfg = null;
            try {
                cfg = PaymentCalcConfigSvc.getRequiredConfig();
            } catch (Exception configEx) {
                System.debug(LoggingLevel.WARN, '[updateOpportunityOnly] Config not available, skipping range validation: ' + configEx.getMessage());
            }

            // Validate Number of Weeks (only if config loaded successfully)
            if (cfg != null && numberOfWeeks != null) {
                Integer minWeeks = cfg.minProgramWeeks != null ? cfg.minProgramWeeks.intValue() : 24;
                Integer maxWeeks = cfg.maxProgramWeeks != null ? cfg.maxProgramWeeks.intValue() : 260;

                if (numberOfWeeks < minWeeks || numberOfWeeks > maxWeeks) {
                    throw new AuraHandledException(
                        VALIDATION_SYMBOL + 'Number of weeks must be between ' + minWeeks + ' and ' + maxWeeks + '.'
                    );
                }
            }

            // Validate Weekly Payment (Desired Payment)
            // Only validate if current payment is set and config loaded (validation bounds depend on current payment)
            if (cfg != null && weeklyPayment != null) {
                // Query Opportunity to get Estimated_Current_Payment__c for range calculation
                List<Opportunity> opps = [
                    SELECT Id, Estimated_Current_Payment__c
                    FROM Opportunity
                    WHERE Id = :recordId
                    LIMIT 1
                ];

                Decimal currentPayment = 0;
                if (!opps.isEmpty() && opps[0].Estimated_Current_Payment__c != null) {
                    currentPayment = opps[0].Estimated_Current_Payment__c;
                }

                // Only apply payment range validation if current payment is set
                // (The UI shows validation bounds based on current payment)
                if (currentPayment > 0) {
                    // Determine program type for validation
                    String normalizedProgramType = programType != null ? programType.replace(' ', '_').toUpperCase() : 'DCG_MOD';
                    Boolean isDcgDebt = normalizedProgramType == 'DCG_DEBT';

                    // Get minimum payment floor based on program type
                    Decimal minPaymentFloor = isDcgDebt
                        ? (cfg.minWeeklyTargetPaymentDcgDebt != null ? cfg.minWeeklyTargetPaymentDcgDebt : 0)
                        : (cfg.minWeeklyTargetPayment != null ? cfg.minWeeklyTargetPayment : 35);

                    // Calculate percentage-based floor
                    Decimal minTargetPercent = isDcgDebt
                        ? (cfg.minTargetPercentDcgDebt != null ? cfg.minTargetPercentDcgDebt : 15)
                        : (cfg.minTargetPercentDcgMod != null ? cfg.minTargetPercentDcgMod : 40);
                    Decimal percentageFloor = currentPayment * (minTargetPercent / 100);

                    // Use the higher of absolute floor or percentage floor
                    Decimal minPayment = Math.max(minPaymentFloor, percentageFloor);

                    // Calculate maximum payment based on maxTargetPercent
                    Decimal maxTargetPercent = cfg.maxTargetPercent != null ? cfg.maxTargetPercent : 100;
                    Decimal maxPayment = currentPayment * (maxTargetPercent / 100);

                    // Validate payment is within range
                    if (weeklyPayment < minPayment) {
                        throw new AuraHandledException(
                            VALIDATION_SYMBOL + 'Desired payment must be at or above $' + minPayment.setScale(2) + '.'
                        );
                    }
                    if (weeklyPayment > maxPayment) {
                        throw new AuraHandledException(
                            VALIDATION_SYMBOL + 'Desired payment must be at or below $' + maxPayment.setScale(2) + '.'
                        );
                    }
                }
            }
            // ============ END VALIDATION ============

            Opportunity opp = new Opportunity(Id = recordId);
            Boolean hasUpdates = false;

            // Number of weeks
            if (numberOfWeeks != null) {
                opp.Number_of_Weeks__c = numberOfWeeks;
                hasUpdates = true;
            }

            // Weekly payment
            if (weeklyPayment != null) {
                opp.Est_weekly_payment__c = weeklyPayment;
                hasUpdates = true;
            }

            // First draft date
            if (String.isNotBlank(firstDraftDate)) {
                opp.First_Draft_Date__c = parseOpportunityDate(firstDraftDate);
                hasUpdates = true;
            }

            // Banking fee
            if (bankingFee != null) {
                opp.Banking_Fee__c = bankingFee;
                hasUpdates = true;
            }

            // Setup fee term
            if (setupFeeTerm != null) {
                opp.Setup_Fee_Term__c = String.valueOf(setupFeeTerm);
                hasUpdates = true;
            }

            // Program Type - convert underscores to spaces and save exactly what user selected
            String normalizedType = '';
            if (String.isNotBlank(programType)) {
                normalizedType = programType.toUpperCase().replace('_', ' ');
                opp.Program_Type__c = normalizedType;
                hasUpdates = true;
            }

            // No-Fee Program - only allowed for DCG MOD per validation rule
            // DCG MOD CA uses no-fee behavior internally for calculations but the
            // Opportunity field must be false for MOD CA and DEBT program types
            if (normalizedType == 'DCG MOD') {
                opp.No_Fee_Program__c = noFeeProgram == true;
            } else {
                opp.No_Fee_Program__c = false;
            }
            hasUpdates = true;

            // Settlement percentage picklist - reuses cfg from validation section above
            if (cfg != null) {
                try {
                    // Est_Settlement__c picklist
                    if (cfg.settlementPercent != null) {
                        Integer settlementInt = cfg.settlementPercent.intValue();
                        Set<Integer> validSettlementValues = new Set<Integer>();
                        if (String.isNotBlank(cfg.validSettlementValues)) {
                            for (String valStr : cfg.validSettlementValues.split(',')) {
                                validSettlementValues.add(Integer.valueOf(valStr.trim()));
                            }
                        }
                        if (validSettlementValues.contains(settlementInt)) {
                            opp.Est_Settlement__c = String.valueOf(settlementInt) + '%';
                            hasUpdates = true;
                        }
                    }

                    // Program_Fee__c picklist
                    Decimal programFeePct = noFeeProgram ? cfg.baselineNoFeeProgramFee : cfg.programFeePercent;
                    if (programFeePct != null) {
                        Decimal minProgramFeePercent = cfg.minProgramFeePercent;
                        Decimal maxProgramFeePercent = cfg.maxProgramFeePercent;
                        if (programFeePct >= minProgramFeePercent && programFeePct <= maxProgramFeePercent) {
                            opp.Program_Fee__c = String.valueOf(programFeePct.intValue()) + '%';
                            hasUpdates = true;
                        }
                    }
                } catch (Exception e) {
                    System.debug('[updateOpportunityOnly] Skipping config-validated fields: ' + e.getMessage());
                }
            }

            if (hasUpdates) {
                Database.update(opp, AccessLevel.SYSTEM_MODE);
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to update Opportunity: ' + e.getMessage());
        }
    }

    // ==================================================================================
    // PLAN MODIFICATION METHODS (Modify Weekly Payment / Modify Est Total Debt)
    // ==================================================================================

    /**
     * @description Preview a plan modification without saving.
     * Calculates the new schedule items based on the modified field value
     * using the same formula as recalculateRemainingBalance.
     * @param planId The current Payment Plan ID
     * @param modificationType 'EST_CURRENT_PAYMENT' or 'EST_TOTAL_DEBT'
     * @param newValue The new value for the modified field
     * @return PlanModificationPreview with summary metrics and projected schedule items
     */
    public static PaymentPlanEditorController.PlanModificationPreview previewPlanModification(Id planId, String modificationType, Decimal newValue) {
        String methodName = 'previewPlanModification';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + planId + ' | type: ' + modificationType + ' | value: ' + newValue);

        try {
            PlanModificationResult result = calculateModifiedPlan(planId, modificationType, newValue);
            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Preview generated with ' + result.preview.scheduleItems.size() + ' items');
            return result.preview;
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error generating preview: ' + e.getMessage());
        }
    }

    /**
     * @description Save a plan modification as a new Draft version.
     * Creates a new plan version with recalculated schedule items and updates the Opportunity field.
     * Uses the same formula as recalculateRemainingBalance but with the user-provided value override.
     * @param planId The current Payment Plan ID
     * @param modificationType 'EST_CURRENT_PAYMENT' or 'EST_TOTAL_DEBT'
     * @param newValue The new value for the modified field
     * @return PaymentPlanWrapper for the newly created plan version
     */
    public static PaymentPlanEditorController.PaymentPlanWrapper savePlanModification(Id planId, String modificationType, Decimal newValue) {
        String methodName = 'savePlanModification';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + planId + ' | type: ' + modificationType + ' | value: ' + newValue);

        Savepoint sp = Database.setSavepoint();
        try {
            PlanModificationResult result = calculateModifiedPlan(planId, modificationType, newValue);

            // Insert new plan
            insert result.newPlan;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted new plan: ' + result.newPlan.Id);

            // Assign plan ID to all items
            for (Payment_Schedule_Item__c item : result.newItems) {
                item.Payment_Plan__c = result.newPlan.Id;
            }

            // Recalculate draft numbers and insert items
            if (!result.newItems.isEmpty()) {
                PaymentPlanCalculationService.recalculateDraftNumbers(result.newItems);
                insert result.newItems;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted ' + result.newItems.size() + ' schedule items');

                // Clone fees for non-scheduled items (preserves EPPS data: Fee_Id__c, Transaction_Id__c, Status_Code__c, Status__c)
                // Create fresh fees for new scheduled items
                Set<Id> oldNonScheduledIds = new Set<Id>();
                Map<Decimal, Id> paymentNumToOldId = new Map<Decimal, Id>();
                for (Payment_Schedule_Item__c oldItem : result.nonScheduledItems) {
                    oldNonScheduledIds.add(oldItem.Id);
                    if (oldItem.Payment_Number__c != null) {
                        paymentNumToOldId.put(oldItem.Payment_Number__c, oldItem.Id);
                    }
                }

                // Query standard fees (Banking, Program, Setup) for old non-scheduled items
                Map<Id, Map<String, Payment_Fee__c>> oldFeeMap = oldNonScheduledIds.isEmpty()
                    ? new Map<Id, Map<String, Payment_Fee__c>>()
                    : PaymentFeeService.getFeesByScheduleItemIds(oldNonScheduledIds);

                List<Payment_Fee__c> clonedFees = new List<Payment_Fee__c>();
                List<Payment_Schedule_Item__c> newScheduledItems = new List<Payment_Schedule_Item__c>();

                for (Payment_Schedule_Item__c newItem : result.newItems) {
                    if (newItem.Status__c != STATUS_SCHEDULED && newItem.Payment_Number__c != null) {
                        // Non-scheduled item: clone fee records from original item
                        Id oldItemId = paymentNumToOldId.get(newItem.Payment_Number__c);
                        if (oldItemId != null && oldFeeMap.containsKey(oldItemId)) {
                            Map<String, Payment_Fee__c> feesByType = oldFeeMap.get(oldItemId);
                            for (Payment_Fee__c oldFee : feesByType.values()) {
                                Payment_Fee__c clonedFee = oldFee.clone(false, true, false, false);
                                clonedFee.Payment_Schedule_Item__c = newItem.Id;
                                clonedFees.add(clonedFee);
                            }
                        }
                    } else {
                        // Scheduled item: collect for fresh fee creation
                        newScheduledItems.add(newItem);
                    }
                }

                // Insert cloned fees for non-scheduled items
                if (!clonedFees.isEmpty()) {
                    insert clonedFees;
                    System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Cloned ' + clonedFees.size() + ' fee record(s) for non-scheduled items');
                }

                // Create fresh fee records for new scheduled items
                if (!newScheduledItems.isEmpty()) {
                    PaymentPlanCalculationService.createFeeRecordsForScheduleItems(newScheduledItems);
                }
            }

            // Carry over wire fees
            PaymentPlanCalculationService.carryOverWireFees(result.existingItems, result.newItems);

            // Update plan item count
            result.newPlan.Schedule_Item_Count__c = result.newItems.size();
            update result.newPlan;

            // Update Opportunity fields
            Opportunity oppUpdate = new Opportunity(Id = result.opp.Id);
            oppUpdate.Number_of_Weeks__c = result.numberOfPayments;
            oppUpdate.Est_weekly_payment__c = result.weeklyPayment;
            if (modificationType == 'EST_CURRENT_PAYMENT') {
                oppUpdate.Estimated_Current_Payment__c = newValue;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Updating Opp Estimated_Current_Payment__c to ' + newValue + ' | Est_weekly_payment__c to ' + result.weeklyPayment);
            } else if (modificationType == 'EST_TOTAL_DEBT') {
                oppUpdate.Estimated_Total_Debt__c = newValue;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Updating Opp Estimated_Total_Debt__c to ' + newValue);
            }
            update oppUpdate;

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Plan modification saved successfully');
            return PaymentPlanEditorController.getPaymentPlanById(result.newPlan.Id);

        } catch (AuraHandledException ae) {
            Database.rollback(sp);
            throw ae;
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error saving plan modification: ' + e.getMessage());
        }
    }

    // ==================================================================================
    // PRIVATE CALCULATION ENGINE
    // ==================================================================================

    /**
     * @description Shared calculation engine for plan modification (preview + save).
     * Follows the same formula as recalculateRemainingBalance but allows overriding
     * either the weekly payment or the estimated total debt.
     * For EST_CURRENT_PAYMENT: user provides new estimated current payment, weekly payment calculated from Target_Payment_Percent__c, number of payments adjusts.
     * For EST_TOTAL_DEBT: user provides new total debt, weekly payment stays the same, number of payments adjusts.
     * @param planId The current Payment Plan ID
     * @param modType 'EST_CURRENT_PAYMENT' or 'EST_TOTAL_DEBT'
     * @param newValue The new value for the modified field
     * @return PlanModificationResult with all calculated data (no DML performed)
     */
    private static PlanModificationResult calculateModifiedPlan(Id planId, String modType, Decimal newValue) {
        String methodName = 'calculateModifiedPlan';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);

        // Validate inputs
        if (planId == null) {
            throw new AuraHandledException(VALIDATION_SYMBOL + 'Plan ID is required.');
        }
        if (String.isBlank(modType) || (modType != 'EST_CURRENT_PAYMENT' && modType != 'EST_TOTAL_DEBT')) {
            throw new AuraHandledException(VALIDATION_SYMBOL + 'Invalid modification type. Must be EST_CURRENT_PAYMENT or EST_TOTAL_DEBT.');
        }
        if (newValue == null || newValue <= 0) {
            throw new AuraHandledException(VALIDATION_SYMBOL + 'Value must be greater than zero.');
        }

        // Query current plan with all fields via describe (ensures clone never misses a field)
        String ppFields = PaymentPlanCalculationService.getPaymentPlanQueryFields();
        List<PaymentPlan__c> currentPlans = Database.query(
            'SELECT ' + ppFields + ' FROM PaymentPlan__c WHERE Id = :planId LIMIT 1'
        );

        if (currentPlans.isEmpty()) {
            throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Payment Plan not found.');
        }

        PaymentPlan__c currentPlan = currentPlans[0];

        if (currentPlan.Opportunity__c == null) {
            throw new AuraHandledException(VALIDATION_SYMBOL + 'Payment Plan is not linked to an Opportunity.');
        }

        // Query Opportunity (for fields not stored on plan and for Opp updates)
        List<Opportunity> opportunities = [
            SELECT Id, Name, Estimated_Total_Debt__c, Number_of_Weeks__c, First_Draft_Date__c,
                   No_Fee_Program__c, Program_Type__c,
                   Setup_Fee__c, Setup_Fee_Term__c,
                   Total_Program__c, Program_Fee__c, Est_Settlement__c,
                   Est_weekly_payment__c, Estimated_Current_Payment__c, Payment_Frequency__c
            FROM Opportunity
            WHERE Id = :currentPlan.Opportunity__c
            LIMIT 1
        ];

        if (opportunities.isEmpty()) {
            throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Related Opportunity not found.');
        }

        Opportunity opp = opportunities[0];

        // Load CMDT config for split ratios
        String programType = currentPlan.Program_Type__c != null ? currentPlan.Program_Type__c : opp.Program_Type__c;
        String normalizedProgramType = programType != null ? programType.replace(' ', '_').toUpperCase() : 'DCG_MOD';

        PaymentCalcConfigSvc.ConfigDTO config;
        try {
            config = PaymentCalcConfigSvc.getRequiredConfigForProgram(normalizedProgramType);
        } catch (Exception configEx) {
            System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Using default config: ' + configEx.getMessage());
            config = PaymentCalcConfigSvc.getRequiredConfig();
        }

        // Get split ratios from CMDT
        Decimal programSplitRatio = config.programSplitRatio != null ? config.programSplitRatio : DEFAULT_SPLIT_RATIO;
        Boolean isNoFeeProgram = currentPlan.No_Fee_Program__c != null && currentPlan.No_Fee_Program__c;
        if (isNoFeeProgram) {
            programSplitRatio = 0;
        }

        // ==================================================================================
        // SOURCE PERCENTAGES: Opportunity first (authoritative), then Plan, then Config
        // Plan percentage fields may be stale — Opportunity is the source of truth
        // ==================================================================================
        Decimal oppSettlementPct = PaymentPlanCalculationService.parsePercentageToDecimal(opp.Est_Settlement__c);
        Decimal oppProgramFeePct = PaymentPlanCalculationService.parsePercentageToDecimal(opp.Program_Fee__c);
        Decimal settlementPercentage = oppSettlementPct != null ? oppSettlementPct
            : (currentPlan.Settlement_Percentage__c != null ? currentPlan.Settlement_Percentage__c
            : (config.settlementPercent != null ? config.settlementPercent : 60));
        Decimal programFeePercentage = oppProgramFeePct != null ? oppProgramFeePct
            : (currentPlan.Program_Fee_Percentage__c != null ? currentPlan.Program_Fee_Percentage__c
            : (config.programFeePercent != null ? config.programFeePercent : 35));
        Decimal bankingFee = currentPlan.Banking_Fee__c != null ? currentPlan.Banking_Fee__c : DEFAULT_BANKING_FEE;
        Decimal bank2Fee = currentPlan.Bank2_Fee__c != null ? currentPlan.Bank2_Fee__c : 0;
        Decimal totalSetupFee = currentPlan.Setup_Fee__c != null ? currentPlan.Setup_Fee__c : 0;
        Decimal setupFeePaymentsTotal = currentPlan.Setup_Fee_Payments__c != null && currentPlan.Setup_Fee_Payments__c > 0
            ? currentPlan.Setup_Fee_Payments__c
            : DEFAULT_SETUP_FEE_PAYMENTS;
        Decimal perPaymentSetupFee = setupFeePaymentsTotal > 0 ? (totalSetupFee / setupFeePaymentsTotal) : 0;

        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Plan config — Settlement%: ' + settlementPercentage + ' | ProgramFee%: ' + programFeePercentage + ' | BankingFee: ' + bankingFee + ' | SetupFee: ' + totalSetupFee + '/' + setupFeePaymentsTotal + ' payments');

        // Determine values based on modification type
        Decimal estimatedTotalDebt;
        Decimal weeklyPayment;
        Decimal estimatedCurrentPayment;

        // Target payment percent: back-calculated for display only (not used for weekly calculation)
        Decimal targetPaymentPercent = currentPlan.Target_Payment_Percent__c != null && currentPlan.Target_Payment_Percent__c > 0
            ? currentPlan.Target_Payment_Percent__c
            : (config.targetPaymentPercentage != null ? config.targetPaymentPercentage : 59);

        if (modType == 'EST_TOTAL_DEBT') {
            estimatedTotalDebt = newValue;
            estimatedCurrentPayment = currentPlan.Current_Payment__c;
            // Keep weekly payment from current plan
            weeklyPayment = currentPlan.Weekly_Payment__c != null && currentPlan.Weekly_Payment__c > 0
                ? currentPlan.Weekly_Payment__c
                : (opp.Est_weekly_payment__c != null && opp.Est_weekly_payment__c > 0
                    ? opp.Est_weekly_payment__c : 0);
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | EST_TOTAL_DEBT: newDebt=' + estimatedTotalDebt + ' | weeklyPayment from plan=' + weeklyPayment);
        } else {
            // EST_CURRENT_PAYMENT: scale weekly proportionally from plan's actual values
            // newWeekly = currentWeekly × (newCurrentPayment / originalCurrentPayment)
            // Same input → same weekly (no changes). Different input → proportional change.
            estimatedCurrentPayment = newValue;
            estimatedTotalDebt = currentPlan.Total_Debt__c != null && currentPlan.Total_Debt__c > 0
                ? currentPlan.Total_Debt__c
                : (opp.Estimated_Total_Debt__c != null ? opp.Estimated_Total_Debt__c : 0);
            Decimal originalCurrentPayment = currentPlan.Current_Payment__c != null && currentPlan.Current_Payment__c > 0
                ? currentPlan.Current_Payment__c
                : (opp.Estimated_Current_Payment__c != null && opp.Estimated_Current_Payment__c > 0
                    ? opp.Estimated_Current_Payment__c : 1);
            Decimal originalWeekly = currentPlan.Weekly_Payment__c != null && currentPlan.Weekly_Payment__c > 0
                ? currentPlan.Weekly_Payment__c
                : (opp.Est_weekly_payment__c != null && opp.Est_weekly_payment__c > 0
                    ? opp.Est_weekly_payment__c : 0);
            weeklyPayment = (originalWeekly * (estimatedCurrentPayment / originalCurrentPayment)).setScale(2, RoundingMode.HALF_UP);
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | EST_CURRENT_PAYMENT: newCurrentPayment=' + estimatedCurrentPayment + ' | originalCurrentPayment=' + originalCurrentPayment + ' | originalWeekly=' + originalWeekly + ' | newWeekly=' + weeklyPayment);
        }

        if (estimatedTotalDebt <= 0) {
            throw new AuraHandledException(VALIDATION_SYMBOL + 'Estimated Total Debt must be greater than zero.');
        }

        // ==================================================================================
        // CALCULATE SETTLEMENT & PROGRAM FEE
        // Always calculate from Opportunity percentages (authoritative source)
        // Both modes use the same formula — only the debt value differs
        // ==================================================================================
        Decimal settlementAmount = (estimatedTotalDebt * (settlementPercentage / 100)).setScale(2, RoundingMode.HALF_UP);
        Decimal programFeeAmount = isNoFeeProgram ? 0 : (estimatedTotalDebt * (programFeePercentage / 100)).setScale(2, RoundingMode.HALF_UP);
        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Settlement: ' + settlementAmount + ' (' + settlementPercentage + '%) | ProgramFee: ' + programFeeAmount + ' (' + programFeePercentage + '%) | Debt: ' + estimatedTotalDebt);

        Decimal totalProgramCost = settlementAmount + programFeeAmount + totalSetupFee;
        Decimal totalProgramFee = programFeeAmount;

        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Settlement: ' + settlementAmount + ' | ProgramFee: ' + programFeeAmount + ' | SetupFee: ' + totalSetupFee + ' | TotalProgramCost: ' + totalProgramCost);

        // Validate weekly payment exceeds banking fee
        Decimal baseProgramCostPerPayment = weeklyPayment - bankingFee;
        if (baseProgramCostPerPayment <= 0) {
            throw new AuraHandledException(VALIDATION_SYMBOL + 'Weekly payment ($' + weeklyPayment.setScale(2) + ') must exceed the banking fee ($' + bankingFee.setScale(2) + ').');
        }

        // Query existing schedule items
        String fields = PaymentPlanCalculationService.getScheduleItemQueryFields();
        String query = 'SELECT ' + fields +
            ' FROM Payment_Schedule_Item__c WHERE Payment_Plan__c = :planId ORDER BY Payment_Number__c ASC LIMIT ' + MAX_QUERY_LIMIT;
        List<Payment_Schedule_Item__c> existingItems = Database.query(query);

        // Separate items by status and calculate paid amounts (same as recalculateRemainingBalance)
        List<Payment_Schedule_Item__c> nonScheduledItems = new List<Payment_Schedule_Item__c>();
        List<Payment_Schedule_Item__c> scheduledItems = new List<Payment_Schedule_Item__c>();
        Decimal paidProgramCostSum = 0;
        Decimal paidProgramFeeSum = 0;
        Integer paidSetupFeeCount = 0;

        Decimal paidSetupFeeAmount = 0;
        for (Payment_Schedule_Item__c item : existingItems) {
            if (item.Status__c == STATUS_SCHEDULED) {
                scheduledItems.add(item);
            } else {
                nonScheduledItems.add(item);
                // All non-scheduled items are preserved/cloned in the new plan with their amounts.
                // Subtract their program cost from the remaining total to avoid double-counting.
                // Only scheduled items are rebuilt — remaining cost covers only what scheduled items need.
                Decimal programFee = item.Program_Fee_Amount__c != null ? item.Program_Fee_Amount__c : 0;
                Decimal toEscrow = item.To_Escrow_Amount__c != null ? item.To_Escrow_Amount__c : 0;
                paidProgramCostSum += (programFee + toEscrow);
                paidProgramFeeSum += programFee;
                // Count and sum setup fees from ALL non-scheduled items (Cleared, NSF, Processing, Cancelled)
                // These items already had setup fees allocated — do not re-add them in new schedule
                if (item.Setup_Fee_Amount__c != null && item.Setup_Fee_Amount__c > 0) {
                    paidSetupFeeCount++;
                    paidSetupFeeAmount += item.Setup_Fee_Amount__c;
                }
            }
        }
        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Non-Scheduled: ' + nonScheduledItems.size() + ' | Scheduled: ' + scheduledItems.size());
        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Paid Program Cost: ' + paidProgramCostSum + ' | Paid Program Fee: ' + paidProgramFeeSum);

        // Remaining amounts — remainingProgramCost uses settlement + programFee (not setup fee, which is tracked separately)
        Decimal remainingProgramCost = Math.max(0, (settlementAmount + programFeeAmount) - paidProgramCostSum);
        Decimal remainingProgramFee = Math.max(0, totalProgramFee - paidProgramFeeSum);
        Integer remainingSetupFeePayments = Math.max(0, setupFeePaymentsTotal.intValue() - paidSetupFeeCount);

        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Remaining Program Cost: ' + remainingProgramCost + ' | Remaining Program Fee: ' + remainingProgramFee + ' | Remaining Setup Fee Payments: ' + remainingSetupFeePayments);

        if (remainingProgramCost <= 0) {
            throw new AuraHandledException(VALIDATION_SYMBOL + 'Debt is already paid off. Remaining program cost: $' + remainingProgramCost.setScale(2));
        }

        // ==================================================================================
        // DYNAMICALLY CALCULATE REMAINING COUNT (both modes use same logic)
        // ==================================================================================
        Integer remainingCount = (Integer) Math.ceil(remainingProgramCost / baseProgramCostPerPayment);

        // Cap at max program weeks
        Integer maxWeeks = config.maxProgramWeeks != null ? config.maxProgramWeeks.intValue() : 260;
        if ((nonScheduledItems.size() + remainingCount) > maxWeeks) {
            remainingCount = maxWeeks - nonScheduledItems.size();
        }

        if (remainingCount <= 0) {
            throw new AuraHandledException(VALIDATION_SYMBOL + 'No remaining payments can be scheduled.');
        }

        // Calculate last payment using ACTUAL per-payment net (weeklyPayment - bankingFee)
        // This ensures total net = exactly remainingProgramCost, so savings = exactly settlement amount
        Decimal actualNetPerPayment = weeklyPayment - bankingFee;
        Decimal lastPaymentProgramCost = remainingProgramCost - (actualNetPerPayment * (remainingCount - 1));
        lastPaymentProgramCost = Math.max(0, lastPaymentProgramCost).setScale(2, RoundingMode.HALF_UP);
        Decimal lastWeeklyPayment = lastPaymentProgramCost + bankingFee;

        Integer numberOfPayments = nonScheduledItems.size() + remainingCount;
        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | ' + modType + ': remainingCount=' + remainingCount + ' | Total Payments: ' + numberOfPayments + ' | Weekly: ' + weeklyPayment + ' | LastWeekly: ' + lastWeeklyPayment);

        // ==================================================================================
        // BUILD NEW PLAN VERSION
        // ==================================================================================
        Decimal newVersionNumber = currentPlan.Version_Number__c != null ? currentPlan.Version_Number__c + 1 : 2;
        PaymentPlan__c newPlan = currentPlan.clone(false, true, false, false);
        newPlan.Version_Number__c = newVersionNumber;
        newPlan.Status__c = VERSION_STATUS_DRAFT;
        newPlan.Is_Active__c = false;
        newPlan.Previous_Version__c = currentPlan.Id;
        newPlan.Version_Type__c = VERSION_TYPE_REVISION;
        newPlan.Source__c = SOURCE_UI;
        newPlan.Calculation_Timestamp__c = DateTime.now();

        // Core calculated fields
        newPlan.Weekly_Payment__c = weeklyPayment;
        newPlan.Number_of_Payments__c = numberOfPayments;
        newPlan.Total_Debt__c = estimatedTotalDebt;
        newPlan.Settlement_Amount__c = settlementAmount;
        newPlan.Program_Fee_Amount__c = programFeeAmount;
        newPlan.Total_Program_Cost__c = totalProgramCost;
        newPlan.Settlement_Percentage__c = settlementPercentage;
        newPlan.Program_Fee_Percentage__c = programFeePercentage;
        newPlan.Setup_Fee__c = totalSetupFee;
        newPlan.Setup_Fee_Payments__c = setupFeePaymentsTotal;
        newPlan.Program_Type__c = currentPlan.Program_Type__c;
        newPlan.No_Fee_Program__c = currentPlan.No_Fee_Program__c;

        // Carry forward calculator settings from plan
        newPlan.Target_Payment_Percent__c = currentPlan.Target_Payment_Percent__c;
        newPlan.Calculation_Mode__c = currentPlan.Calculation_Mode__c;
        newPlan.Payment_Frequency__c = opp.Payment_Frequency__c != null ? opp.Payment_Frequency__c : currentPlan.Payment_Frequency__c;
        // Update current payment on the new plan
        if (estimatedCurrentPayment != null) {
            newPlan.Current_Payment__c = estimatedCurrentPayment;
        }

        // Per-payment fee fields
        newPlan.Banking_Fee__c = bankingFee;
        newPlan.Bank2_Fee__c = bank2Fee;
        newPlan.Monthly_Payment__c = (weeklyPayment * 4.33).setScale(2, RoundingMode.HALF_UP);

        // Calculated summary fields — include banking in Total Program Cost (matches recalculatePaymentPlan)
        Decimal totalBankingFeeCalc = bankingFee * numberOfPayments;
        newPlan.Total_Banking_Fee__c = totalBankingFeeCalc;
        totalProgramCost = settlementAmount + programFeeAmount + totalSetupFee + totalBankingFeeCalc;
        newPlan.Total_Program_Cost__c = totalProgramCost;
        newPlan.Total_Savings__c = estimatedTotalDebt - totalProgramCost;

        String modLabel = modType == 'EST_CURRENT_PAYMENT' ? 'Estimated Current Payment' : 'Estimated Total Debt';
        newPlan.Version_Notes__c = modLabel + ' modified to $' + newValue.setScale(2) + ' on ' + DateTime.now().format() +
            '. Payments: ' + numberOfPayments + ', Weekly: $' + weeklyPayment.setScale(2) +
            ' (Settlement ' + settlementPercentage + '%, ProgramFee ' + programFeePercentage + '%).';

        // ==================================================================================
        // BUILD SCHEDULE ITEMS
        // ==================================================================================
        List<Payment_Schedule_Item__c> newItems = new List<Payment_Schedule_Item__c>();

        // Clone non-scheduled items (preserve Cleared/NSF/Cancelled)
        for (Payment_Schedule_Item__c item : nonScheduledItems) {
            newItems.add(PaymentPlanCalculationService.cloneItemForNewPlan(item, null)); // Plan ID set later in save
        }

        // Determine start date for new scheduled items
        Date lastNonScheduledDate = null;
        for (Payment_Schedule_Item__c item : nonScheduledItems) {
            if (item.Payment_Date__c != null) {
                if (lastNonScheduledDate == null || item.Payment_Date__c > lastNonScheduledDate) {
                    lastNonScheduledDate = item.Payment_Date__c;
                }
            }
        }
        Date firstDraftDate = opp.First_Draft_Date__c != null ? opp.First_Draft_Date__c : Date.today();
        Date scheduledStartDate = lastNonScheduledDate != null ?
            lastNonScheduledDate.addDays(PAYMENT_INTERVAL_DAYS) : firstDraftDate;

        // Get running escrow balance from non-scheduled items
        Decimal runningEscrowBalance = 0;
        for (Payment_Schedule_Item__c item : nonScheduledItems) {
            if (item.Savings_Balance__c != null && item.Savings_Balance__c > runningEscrowBalance) {
                runningEscrowBalance = item.Savings_Balance__c;
            }
        }

        // Create new scheduled items with fee split (same logic as recalculateRemainingBalance)
        Integer setupFeePaymentsMade = 0;
        Decimal trackingRemainingProgramFee = remainingProgramFee;

        // Setup fee: use FLOOR rounding with last-payment-remainder to ensure exact total
        Decimal remainingSetupFeeAmount = Math.max(0, totalSetupFee - paidSetupFeeAmount);
        Decimal baseSetupFeePerPayment = remainingSetupFeePayments > 0
            ? (remainingSetupFeeAmount / remainingSetupFeePayments).setScale(2, RoundingMode.FLOOR)
            : 0;
        Decimal lastSetupFeePayment = remainingSetupFeePayments > 0
            ? (remainingSetupFeeAmount - (baseSetupFeePerPayment * (remainingSetupFeePayments - 1))).setScale(2, RoundingMode.HALF_UP)
            : 0;
        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Setup fee distribution: base=' + baseSetupFeePerPayment + ' × ' + (remainingSetupFeePayments - 1) + ' + last=' + lastSetupFeePayment + ' = ' + remainingSetupFeeAmount);

        for (Integer i = 1; i <= remainingCount; i++) {
            Integer paymentNumber = nonScheduledItems.size() + i;

            Payment_Schedule_Item__c newItem = new Payment_Schedule_Item__c();
            newItem.Payment_Number__c = paymentNumber;
            newItem.Draft_Number__c = String.valueOf(paymentNumber);
            newItem.Payment_Date__c = scheduledStartDate.addDays((i - 1) * PAYMENT_INTERVAL_DAYS);

            // Last payment uses remainder amount (will be <= base weekly payment)
            Decimal thisWeeklyPayment = (i == remainingCount) ? lastWeeklyPayment : weeklyPayment;

            // Setup fee: last setup fee payment absorbs remainder to keep total exact
            Decimal thisSetupFee = 0;
            if (setupFeePaymentsMade < remainingSetupFeePayments) {
                Boolean isLastSetupPayment = (setupFeePaymentsMade == remainingSetupFeePayments - 1);
                thisSetupFee = isLastSetupPayment ? lastSetupFeePayment : baseSetupFeePerPayment;
                setupFeePaymentsMade++;
            }

            // Banking fees: flat rate from plan config
            Decimal thisBankingFee = bankingFee;
            Decimal thisBank2Fee = bank2Fee;

            // Net amount for program/escrow split
            Decimal netAmount = thisWeeklyPayment - bankingFee;

            // Program fee and escrow split (same as recalculateRemainingBalance)
            Decimal thisProgramFee = 0;
            Decimal toEscrow = 0;

            // For DCG Debt: skip program fee on first payment — all goes to escrow
            Boolean skipFeeThisPayment = (paymentNumber == 1 && normalizedProgramType == 'DCG_DEBT');

            if (trackingRemainingProgramFee > 0 && !skipFeeThisPayment) {
                Decimal desiredProgramFee = netAmount * programSplitRatio;
                thisProgramFee = Math.min(desiredProgramFee, trackingRemainingProgramFee);
                toEscrow = netAmount - thisProgramFee;
                trackingRemainingProgramFee -= thisProgramFee;
            } else {
                // All program fees collected, no-fee program, or first payment DCG Debt
                toEscrow = netAmount;
            }

            runningEscrowBalance += toEscrow;

            Decimal totalPayment = thisWeeklyPayment + thisSetupFee;

            newItem.Total_Payment__c = totalPayment;
            newItem.Setup_Fee_Amount__c = thisSetupFee;
            newItem.Program_Fee_Amount__c = thisProgramFee;
            newItem.Banking_Fee_Amount__c = thisBankingFee;
            newItem.Bank2_Fee_Amount__c = thisBank2Fee;
            newItem.Retainer_Fee_Amount__c = DEFAULT_RETAINER_FEE;
            newItem.To_Escrow_Amount__c = toEscrow;
            newItem.Savings_Balance__c = runningEscrowBalance;
            newItem.Status__c = STATUS_SCHEDULED;

            newItems.add(newItem);
        }

        // ==================================================================================
        // BUILD PREVIEW AND RESULT
        // ==================================================================================
        PaymentPlanEditorController.PlanModificationPreview preview = new PaymentPlanEditorController.PlanModificationPreview();
        preview.numberOfPayments = numberOfPayments;
        preview.totalProgramCost = totalProgramCost;
        preview.weeklyPayment = weeklyPayment;
        preview.totalProgramFee = totalProgramFee;
        preview.estimatedTotalDebt = estimatedTotalDebt;
        preview.settlementAmount = settlementAmount;
        preview.programFeeAmount = programFeeAmount;
        preview.totalSavings = newPlan.Total_Savings__c;
        preview.totalBankingFee = totalBankingFeeCalc;
        preview.targetPaymentPercent = targetPaymentPercent;
        preview.paymentFrequency = newPlan.Payment_Frequency__c;

        // Convert all items to ScheduleItemWrapper for preview
        for (Payment_Schedule_Item__c item : newItems) {
            PaymentPlanEditorController.ScheduleItemWrapper wrapper = new PaymentPlanEditorController.ScheduleItemWrapper();
            wrapper.rowNumber = item.Payment_Number__c != null ? item.Payment_Number__c.intValue() : 0;
            wrapper.draftNumber = item.Draft_Number__c;
            wrapper.paymentDate = item.Payment_Date__c;
            wrapper.draftAmount = item.Total_Payment__c;
            wrapper.retainerFee = item.Retainer_Fee_Amount__c;
            wrapper.setupFee = item.Setup_Fee_Amount__c;
            wrapper.programFee = item.Program_Fee_Amount__c;
            wrapper.bankingFee = item.Banking_Fee_Amount__c;
            wrapper.banking2Fee = item.Bank2_Fee_Amount__c;
            wrapper.savingsBalance = item.Savings_Balance__c;
            wrapper.toEscrowAmount = item.To_Escrow_Amount__c;
            wrapper.status = item.Status__c;
            wrapper.isModified = false;
            wrapper.isNew = false;
            wrapper.isDeleted = false;
            preview.scheduleItems.add(wrapper);
        }

        // Build result
        PlanModificationResult result = new PlanModificationResult();
        result.currentPlan = currentPlan;
        result.opp = opp;
        result.newPlan = newPlan;
        result.nonScheduledItems = nonScheduledItems;
        result.existingItems = existingItems;
        result.newItems = newItems;
        result.preview = preview;
        result.weeklyPayment = weeklyPayment;
        result.numberOfPayments = numberOfPayments;
        result.settlementAmount = settlementAmount;
        result.programFeeAmount = programFeeAmount;

        System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | Items: ' + newItems.size());
        return result;
    }
}
