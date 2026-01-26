public with sharing class PaymentCalculatorController {
    // Use CalculationService config-backed properties instead of local constants
    public static Decimal WEEKLY_TARGET_PAYMENT_FLOOR {
        get { return CalculationService.MIN_WEEKLY_TARGET_PAYMENT; }
    }
    public static Decimal WEEKLY_TARGET_PAYMENT_FLOOR_DCG_DEBT {
        get { return CalculationService.MIN_WEEKLY_TARGET_PAYMENT_DCG_DEBT; }
    }

    /**
     * @description Inner class to hold debt totals from Opportunity rollup fields
     */
    public class DebtTotals {
        public Decimal totalDebt { get; set; }
        public Decimal currentPayment { get; set; }

        public DebtTotals() {
            this.totalDebt = 0;
            this.currentPayment = 0;
        }
    }

    /**
     * @description Gets debt totals from Opportunity rollup fields
     * @param recordId Opportunity ID (Leads must be converted first)
     * @return DebtTotals object with totalDebt and currentPayment
     */
    public static DebtTotals getDebtTotals(Id recordId) {
        try {
            String sObjectType = recordId.getSObjectType().getDescribe().getName();
            DebtTotals totals = new DebtTotals();

            if (sObjectType == 'Lead') {
                throw new AuraHandledException('Leads must be converted to Opportunity before calculating. Please convert the Lead first.');
            } else if (sObjectType == 'Opportunity') {
                Opportunity opp = [
                    SELECT Estimated_Total_Debt__c, Estimated_Current_Payment__c
                    FROM Opportunity
                    WHERE Id = :recordId
                    LIMIT 1
                ];
                totals.totalDebt = opp.Estimated_Total_Debt__c != null ? opp.Estimated_Total_Debt__c : 0;
                totals.currentPayment = opp.Estimated_Current_Payment__c != null ? opp.Estimated_Current_Payment__c : 0;
            }

            return totals;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching debt totals: ' + e.getMessage());
        }
    }
    
    /**
     * NEW: Calculate payment plan using version-controlled SalesCalculatorService
     */
    @AuraEnabled
    public static PaymentPlan__c calculatePaymentPlanWithVersion(
        Id recordId,
        Map<String, Object> parameters
    ) {
        try {
            // Convert Lead to Opportunity if needed
            Id opportunityId = getOrCreateOpportunityId(recordId);
            
            // Use the new SalesCalculatorService
            PaymentPlan__c paymentPlan = SalesCalculatorService.calculatePaymentPlan(opportunityId, parameters);
            
            return paymentPlan;
        } catch (Exception e) {
            throw new AuraHandledException('Error calculating payment plan: ' + e.getMessage());
        }
    }
    
    /**
     * Get version history for an opportunity
     */
    @AuraEnabled(cacheable=true)
    public static List<PaymentPlan__c> getPaymentPlanVersions(Id recordId) {
        try {
            Id opportunityId = recordId.getSObjectType().getDescribe().getName() == 'Opportunity' 
                ? recordId 
                : null;
                
            if (opportunityId == null) {
                return new List<PaymentPlan__c>();
            }
            
            return PaymentPlanVersionService.getVersionHistory(opportunityId);
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching payment plan versions: ' + e.getMessage());
        }
    }
    
    /**
     * Activate a specific payment plan version
     */
    @AuraEnabled
    public static PaymentPlan__c activatePaymentPlanVersion(Id paymentPlanId) {
        try {
            return PaymentPlanVersionService.activateVersion(paymentPlanId);
        } catch (Exception e) {
            throw new AuraHandledException('Error activating payment plan version: ' + e.getMessage());
        }
    }
    
    /**
     * Create new version from existing payment plan
     */
    @AuraEnabled
    public static PaymentPlan__c createNewPaymentPlanVersion(Id existingPlanId, String versionNotes) {
        try {
            return PaymentPlanVersionService.createNewVersion(existingPlanId, versionNotes);
        } catch (Exception e) {
            throw new AuraHandledException('Error creating new payment plan version: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static CalculationResult calculatePaymentPlan(
        Id recordId,
        String programType,
        String paymentFrequency,
        String calculationMode,
        Decimal targetPaymentPercentage,
        Decimal targetPaymentAmount,
        Decimal setupFee,
        Integer setupFeeTerm,
        Decimal servicingFee,
        Decimal bank2Fee,
        String firstDraftDate,
        Integer preferredDayOfWeek,
        Boolean noFeeProgram,
        Decimal additionalProductsWeeklyTotal
    ) {
        try {
            // Get debt totals from Opportunity rollup fields
            DebtTotals debtTotals = getDebtTotals(recordId);
            Decimal totalDebt = debtTotals.totalDebt;
            Decimal currentPayment = debtTotals.currentPayment;

            // Build config map from individual parameters
            Map<String, Object> config = new Map<String, Object>();
            config.put('programType', programType);
            config.put('paymentFrequency', paymentFrequency);
            config.put('calculationMode', calculationMode);
            String normalizedProgramType = (programType != null) ? programType.toUpperCase() : 'DCG_MOD';

            // Get min target percentages from config - fail fast if config unavailable
            PaymentCalcConfigSvc.ConfigDTO cfg = PaymentCalcConfigSvc.getRequiredConfig();
            Decimal minTargetPercentDcgDebt = cfg.minTargetPercentDcgDebt;
            Decimal minTargetPercentDcgMod = cfg.minTargetPercentDcgMod;
            Decimal minTargetPercent = (normalizedProgramType == 'DCG_DEBT') ? minTargetPercentDcgDebt : minTargetPercentDcgMod;
            if (targetPaymentPercentage != null && targetPaymentPercentage < minTargetPercent) {
                targetPaymentPercentage = minTargetPercent;
            }

            Decimal workingTargetPaymentFloor = programType == 'DCG_DEBT' ? WEEKLY_TARGET_PAYMENT_FLOOR_DCG_DEBT : WEEKLY_TARGET_PAYMENT_FLOOR;

            // Get weekly to monthly conversion factor from config (already loaded above)
            Decimal weeklyToMonthlyFactor = cfg.weeklyToMonthlyFactor;

            Decimal normalizedWeeklyTarget = null;
            if (targetPaymentAmount != null) {
                normalizedWeeklyTarget = targetPaymentAmount;
                if (paymentFrequency == 'Monthly') {
                    normalizedWeeklyTarget = normalizedWeeklyTarget / weeklyToMonthlyFactor;
                }
                if (normalizedWeeklyTarget < workingTargetPaymentFloor) {
                    normalizedWeeklyTarget = workingTargetPaymentFloor;
                    Decimal adjustedAmount = (paymentFrequency == 'Monthly')
                        ? normalizedWeeklyTarget * weeklyToMonthlyFactor
                        : normalizedWeeklyTarget;
                    targetPaymentAmount = adjustedAmount.setScale(2);
                } else {
                    targetPaymentAmount = targetPaymentAmount.setScale(2);
                }
            }

            config.put('targetPaymentPercentage', targetPaymentPercentage);
            config.put('targetPaymentAmount', targetPaymentAmount);
            config.put('setupFee', setupFee);
            config.put('setupFeePayments', setupFeeTerm);
            // Maintain legacy key and add canonical key expected by CalculationService
            config.put('servicingFee', servicingFee);
            config.put('bankingFee', servicingFee);
            config.put('bank2Fee', bank2Fee);
            config.put('firstDraftDate', firstDraftDate);
            config.put('preferredDayOfWeek', preferredDayOfWeek);
            config.put('noFeeProgram', noFeeProgram);

            // Additional Products (optional; additive weekly amount)
            if (additionalProductsWeeklyTotal != null) {
                config.put('additionalProductsWeeklyTotal', additionalProductsWeeklyTotal);
            }
            // Load CMDT-backed configuration for this program type - fail fast if unavailable
            PaymentCalcConfigSvc.ConfigDTO programCfg = PaymentCalcConfigSvc.getRequiredConfigForProgram(programType);

            // Percentages (override with No-Fee rule)
            Decimal settlementPct = programCfg.settlementPercent;
            Decimal programFeePct = programCfg.programFeePercent;
            Decimal baselineProgramFeePct = programFeePct;
            if (noFeeProgram == true) {
                config.put('noFeeProgramOriginalFeePercentage', baselineProgramFeePct);
                programFeePct = 0;
            } else {
                config.put('noFeeProgramOriginalFeePercentage', baselineProgramFeePct);
            }
            config.put('settlementPercentage', settlementPct);
            config.put('programFeePercentage', programFeePct);

            // Fees (prefer values passed from UI if present, else CMDT)
            if (config.get('bankingFee') == null) {
                config.put('bankingFee', programCfg.bankingFee);
                config.put('servicingFee', programCfg.bankingFee);
            }
            if (config.get('bank2Fee') == null) {
                config.put('bank2Fee', programCfg.bank2Fee);
            }

            // Split ratios
            config.put('programSplitRatio', programCfg.programSplitRatio);
            config.put('escrowSplitRatio', programCfg.escrowSplitRatio);

            // Add current payment to config for downstream calculations
            config.put('currentPayment', currentPayment);

            // If using desired payment mode, normalize and supply required config keys
            if (calculationMode == 'desired_payment') {
                // Normalize target amount to weekly for CalculationService
                Decimal desiredWeekly = (normalizedWeeklyTarget != null)
                    ? normalizedWeeklyTarget
                    : (targetPaymentAmount != null ? targetPaymentAmount : 0);
                if (desiredWeekly == null) desiredWeekly = 0;
                if (desiredWeekly < workingTargetPaymentFloor) {
                    desiredWeekly = workingTargetPaymentFloor;
                }
                config.put('desiredWeeklyPayment', desiredWeekly);
                // Provide a sane cap for settlement percentage if not already present
                if (config.get('maxSettlementPercentage') == null) {
                    Decimal cap = (config.get('settlementPercentage') != null)
                        ? (Decimal)config.get('settlementPercentage') : 60;
                    config.put('maxSettlementPercentage', cap);
                }
            }

            // Use the advanced CalculationService for sophisticated calculations (using totals, not creditor list)
            CalculationService.PaymentCalculationResult advancedResult =
                CalculationService.calculateAdvancedPaymentPlan(totalDebt, currentPayment, config, recordId);
            
            // Convert to controller result format
            CalculationResult result = new CalculationResult();
            
            // Map advanced result to simple result
            result.totalDebt = advancedResult.debtBreakdown != null ? advancedResult.debtBreakdown.totalDebt : 0;
            result.currentPayment = currentPayment;
            result.settlementAmount = advancedResult.settlementAmount != null ? advancedResult.settlementAmount : 0;
            result.programFee = advancedResult.programFee != null ? advancedResult.programFee : 0;
            result.setupFeeTotal = advancedResult.setupFee != null ? advancedResult.setupFee : 0;
            result.bankingFeeTotal = (advancedResult.bankingFee != null && advancedResult.numberOfWeeks != null) 
                ? advancedResult.bankingFee * advancedResult.numberOfWeeks : 0;
            // Total Program = Settlement + Program Fee + Setup Fee + Banking Fees
            result.totalProgram = result.settlementAmount + result.programFee + result.setupFeeTotal + result.bankingFeeTotal;
            result.totalSavings = result.totalDebt - result.totalProgram;
            result.numberOfWeeks = advancedResult.numberOfWeeks != null ? advancedResult.numberOfWeeks : 0;
            result.weeklyPayment = advancedResult.weeklyPayment != null ? advancedResult.weeklyPayment : 0;
            result.monthlyPayment = result.weeklyPayment * weeklyToMonthlyFactor;
            result.savingsPercentage = result.totalDebt > 0 ? (result.totalSavings / result.totalDebt * 100) : 0;

            // Handle first draft date
            if (String.isNotBlank(firstDraftDate)) {
                result.firstDraftDate = firstDraftDate;
            } else {
                result.firstDraftDate = String.valueOf(getNextMonday());
            }
            
            // Set split ratios - use calculated values from CalculationService (no fallbacks - config is required)
            System.debug('[PaymentCalculatorController] Program Type: ' + programType);
            System.debug('[PaymentCalculatorController] Advanced Result splitRatio: ' + advancedResult.splitRatio);
            System.debug('[PaymentCalculatorController] Advanced Result escrowRatio: ' + advancedResult.escrowRatio);
            result.programSplitRatio = advancedResult.splitRatio;
            result.escrowSplitRatio = advancedResult.escrowRatio;
            System.debug('[PaymentCalculatorController] Final programSplitRatio: ' + result.programSplitRatio);
            System.debug('[PaymentCalculatorController] Final escrowSplitRatio: ' + result.escrowSplitRatio);
            
            // Generate detailed payment schedule
            if (advancedResult.paymentSchedule != null && !advancedResult.paymentSchedule.isEmpty()) {
                result.paymentSchedule = new List<PaymentScheduleItem>();
                for (CalculationService.PaymentScheduleEntry entry : advancedResult.paymentSchedule) {
                    PaymentScheduleItem item = new PaymentScheduleItem();
                    item.paymentNumber = entry.weekNumber;
                    item.paymentDate = String.valueOf(entry.paymentDate);
                    item.totalPayment = entry.paymentAmount;
                    item.setupFee = entry.setupFee != null ? entry.setupFee : 0;
                    item.bankingFee = entry.bankingFee != null ? entry.bankingFee : 0;
                    item.programPayment = entry.programAmount != null ? entry.programAmount : 0;
                    item.escrowPayment = entry.escrowAmount != null ? entry.escrowAmount : 0;
                    item.additionalProducts = entry.additionalProducts != null ? entry.additionalProducts : 0;
                    item.remainingBalance = entry.remainingBalance;
                    result.paymentSchedule.add(item);
                }
            }
            
            // Update Lead/Opportunity with calculated debt totals
            updateRecordDebtTotals(recordId, result.totalDebt, currentPayment);
            
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error calculating payment plan: ' + e.getMessage() + ' - ' + e.getStackTraceString());
        }
    }
    
    @AuraEnabled
    public static Id createContract(Id recordId, CalculationResult calculations, Map<String, Object> config) {
        try {
            // Create Contract record
            Contract contract = new Contract();
            contract.AccountId = getAccountId(recordId);
            contract.Status = 'Draft';
            contract.StartDate = Date.today();
            contract.ContractTerm = calculations.numberOfWeeks / 4; // Convert weeks to months
            contract.Description = 'Debt Settlement Agreement\n' +
                                  'Total Debt: $' + calculations.totalDebt + '\n' +
                                  'Settlement Amount: $' + calculations.settlementAmount + '\n' +
                                  'Weekly Payment: $' + calculations.weeklyPayment + '\n' +
                                  'Program Length: ' + calculations.numberOfWeeks + ' weeks';
            // Insert contract
            try {
                Database.insert(contract, AccessLevel.USER_MODE);
            } catch (Exception ex1) {
                throw new AuraHandledException('Contract insert failed: ' + ex1.getMessage() + ' - ' + ex1.getStackTraceString());
            }
            
            // Create PaymentPlan__c record linked to the contract
            Id paymentPlanId;
            try {
                paymentPlanId = createPaymentPlanRecord(recordId, contract.Id, calculations, config);
            } catch (Exception ex2) {
                throw new AuraHandledException('Payment plan creation failed: ' + ex2.getMessage() + ' - ' + ex2.getStackTraceString());
            }
            
            // Update Lead/Opportunity status
            try {
                updateRecordStatus(recordId, 'Contract Generated');
            } catch (Exception ex3) {
                // Non-fatal; log only
                System.debug('Status update failed: ' + ex3.getMessage());
            }
            
            return contract.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating contract: ' + e.getMessage() + ' - ' + e.getStackTraceString());
        }
    }


    /**
     * Helper method to create Payment_Draft_Item__c records from paymentSchedule.
     * Uses strongly-typed CalculationResult for type safety and performance.
     *
     * DESIGN DECISION: Soft Delete (Activate/Deactivate) Strategy
     * -----------------------------------------------------------
     * We intentionally DEACTIVATE existing Payment_Draft_Item__c records (soft delete)
     * rather than physically deleting them before inserting new ones. Here's why:
     *
     * 1. AUDIT TRAIL: Preserves complete history of all payment schedule calculations.
     *    Every calculation version remains queryable for compliance and debugging.
     *
     * 2. COMPLIANCE: Supports regulatory requirements for data retention. Financial
     *    calculations may need to be retained for audit purposes regardless of whether
     *    they were superseded by newer calculations.
     *
     * 3. COMPARISON: Enables future comparison between calculation versions. Users
     *    and auditors can review how payment schedules evolved over time for a draft.
     *
     * 4. RECOVERY: Allows potential reactivation of previous calculation versions
     *    from stored data. Useful if a user wants to revert to a prior
     *    calculation state.
     *
     * 5. TRADE-OFFS:
     *    - Storage accumulation: Mitigated by scheduled cleanup batch job that can
     *      purge old inactive records based on retention policy
     *    - Query filtering requirement: All queries must filter by Is_Active__c = true
     *      to get current records (helper methods provided below)
     *
     * The parent PaymentDraft__c record is the authoritative source; these child
     * records are a denormalized view for reporting and UI convenience, now with
     * full version history via Calculation_Version__c field.
     */
    private static void createPaymentDraftItems(Id draftId, CalculationResult calculations) {
        // Soft delete: Deactivate existing ACTIVE items for this draft before creating new ones.
        // See method-level comment above for detailed rationale on soft-delete strategy.
        List<Payment_Draft_Item__c> existingActiveItems = [
            SELECT Id, Is_Active__c, Deactivated_Date__c
            FROM Payment_Draft_Item__c
            WHERE Payment_Draft__c = :draftId AND Is_Active__c = true
        ];

        // Deactivate existing active items instead of deleting
        if (!existingActiveItems.isEmpty()) {
            for (Payment_Draft_Item__c item : existingActiveItems) {
                item.Is_Active__c = false;
                item.Deactivated_Date__c = DateTime.now();
            }
            Database.update(existingActiveItems, AccessLevel.SYSTEM_MODE);
        }

        // Early exit if no schedule
        if (calculations == null || calculations.paymentSchedule == null || calculations.paymentSchedule.isEmpty()) {
            return;
        }

        // Determine the next version number by finding the max existing version
        Integer nextVersion = 1;
        List<AggregateResult> versionResults = [
            SELECT MAX(Calculation_Version__c) maxVersion
            FROM Payment_Draft_Item__c
            WHERE Payment_Draft__c = :draftId
        ];
        if (!versionResults.isEmpty() && versionResults[0].get('maxVersion') != null) {
            nextVersion = ((Decimal)versionResults[0].get('maxVersion')).intValue() + 1;
        }

        List<Payment_Draft_Item__c> items = new List<Payment_Draft_Item__c>();
        Integer draftNumber = 1;

        for (PaymentScheduleItem scheduleItem : calculations.paymentSchedule) {
            Payment_Draft_Item__c draftItem = new Payment_Draft_Item__c();
            draftItem.Payment_Draft__c = draftId;

            // Use paymentNumber if available, otherwise use sequential draft number
            draftItem.Draft_Number__c = scheduleItem.paymentNumber != null
                ? scheduleItem.paymentNumber
                : draftNumber;

            // Direct field mapping - no more guessing field names
            draftItem.Total_Draft__c = scheduleItem.totalPayment;
            draftItem.Banking_Fee__c = scheduleItem.bankingFee;
            draftItem.Setup_Fee__c = scheduleItem.setupFee;
            draftItem.Savings__c = scheduleItem.escrowPayment;
            draftItem.Program_Fee__c = scheduleItem.programPayment;

            // Parse date string
            if (String.isNotBlank(scheduleItem.paymentDate)) {
                draftItem.Draft_Due_Date__c = parsePaymentDate(scheduleItem.paymentDate);
            }

            // Set active status and version for new items
            draftItem.Is_Active__c = true;
            draftItem.Calculation_Version__c = nextVersion;

            items.add(draftItem);
            draftNumber++;
        }

        if (!items.isEmpty()) {
            // Use SYSTEM_MODE to bypass FLS checks for system-generated child records
            Database.insert(items, AccessLevel.SYSTEM_MODE);
        }
    }

    /**
     * Parses a payment date string supporting both ISO (YYYY-MM-DD) and locale formats.
     */
    private static Date parsePaymentDate(String dateStr) {
        if (String.isBlank(dateStr)) {
            return null;
        }
        try {
            // Try standard ISO format (YYYY-MM-DD)
            return Date.valueOf(dateStr);
        } catch (Exception e) {
            try {
                // Try locale-specific format (e.g. MM/DD/YYYY)
                return Date.parse(dateStr);
            } catch (Exception e2) {
                System.debug(LoggingLevel.ERROR, 'Invalid date format for payment item: ' + dateStr);
                return null;
            }
        }
    }

    /**
     * Returns only ACTIVE Payment_Draft_Item__c records for a given draft.
     * Use this method for displaying current payment schedule to users.
     * Items are ordered by Draft_Number__c for proper sequence display.
     *
     * @param draftId The Id of the PaymentDraft__c record
     * @return List of active Payment_Draft_Item__c records ordered by Draft_Number__c
     */
    @AuraEnabled(cacheable=true)
    public static List<Payment_Draft_Item__c> getActivePaymentDraftItems(Id draftId) {
        try {
            return [
                SELECT Id, Payment_Draft__c, Draft_Number__c, Draft_Due_Date__c,
                       Total_Draft__c, Banking_Fee__c, Setup_Fee__c, Savings__c,
                       Program_Fee__c, Is_Active__c, Calculation_Version__c,
                       CreatedDate, LastModifiedDate
                FROM Payment_Draft_Item__c
                WHERE Payment_Draft__c = :draftId AND Is_Active__c = true
                ORDER BY Draft_Number__c ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching active payment draft items: ' + e.getMessage());
        }
    }

    /**
     * Returns ALL Payment_Draft_Item__c records (both active and inactive) for audit purposes.
     * Use this method for audit trails and comparing calculation versions.
     * Items are ordered by Calculation_Version__c DESC (newest first), then Draft_Number__c ASC.
     *
     * @param draftId The Id of the PaymentDraft__c record
     * @return List of all Payment_Draft_Item__c records with version and status info
     */
    @AuraEnabled(cacheable=true)
    public static List<Payment_Draft_Item__c> getPaymentDraftItemHistory(Id draftId) {
        try {
            return [
                SELECT Id, Payment_Draft__c, Draft_Number__c, Draft_Due_Date__c,
                       Total_Draft__c, Banking_Fee__c, Setup_Fee__c, Savings__c,
                       Program_Fee__c, Is_Active__c, Calculation_Version__c,
                       Deactivated_Date__c, CreatedDate, LastModifiedDate
                FROM Payment_Draft_Item__c
                WHERE Payment_Draft__c = :draftId
                ORDER BY Calculation_Version__c DESC, Draft_Number__c ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching payment draft item history: ' + e.getMessage());
        }
    }

    /**
     * Deserializes a Map<String, Object> to CalculationResult with proper type handling.
     * Handles the LWC-to-Apex serialization where paymentSchedule items may be generic Maps.
     */
    private static CalculationResult deserializeCalculations(Map<String, Object> calculationsMap) {
        if (calculationsMap == null) {
            return null;
        }

        CalculationResult result = new CalculationResult();

        // Map scalar fields - support both LWC key names and Apex key names
        result.totalDebt = getDecimalValue(calculationsMap, 'totalDebt');
        result.currentPayment = getDecimalValue(calculationsMap, 'currentPayment');
        result.settlementAmount = getDecimalValue(calculationsMap, 'settlementAmount');
        // LWC sends 'programFeeAmount', Apex uses 'programFee'
        result.programFee = getDecimalValue(calculationsMap, 'programFee', 'programFeeAmount');
        result.setupFeeTotal = getDecimalValue(calculationsMap, 'setupFeeTotal', 'setupFeePerPayment');
        result.bankingFeeTotal = getDecimalValue(calculationsMap, 'bankingFeeTotal');
        // LWC sends 'totalProgramCost', Apex uses 'totalProgram'
        result.totalProgram = getDecimalValue(calculationsMap, 'totalProgram', 'totalProgramCost');
        // LWC sends 'savingsAmount', Apex uses 'totalSavings'
        result.totalSavings = getDecimalValue(calculationsMap, 'totalSavings', 'savingsAmount');
        // LWC sends 'programLength', Apex uses 'numberOfWeeks'
        result.numberOfWeeks = getIntegerValue(calculationsMap, 'numberOfWeeks', 'programLength', 'numberOfPayments');
        result.weeklyPayment = getDecimalValue(calculationsMap, 'weeklyPayment', 'newWeeklyPayment');
        result.monthlyPayment = getDecimalValue(calculationsMap, 'monthlyPayment');
        result.savingsPercentage = getDecimalValue(calculationsMap, 'savingsPercentage', 'savingsPercent', 'percentSavings');
        result.firstDraftDate = getStringValue(calculationsMap, 'firstDraftDate');
        result.programSplitRatio = getDecimalValue(calculationsMap, 'programSplitRatio');
        result.escrowSplitRatio = getDecimalValue(calculationsMap, 'escrowSplitRatio');

        // Deserialize payment schedule with proper type conversion
        Object scheduleObj = calculationsMap.get('paymentSchedule');
        if (scheduleObj != null) {
            result.paymentSchedule = deserializePaymentSchedule(scheduleObj);
        }

        return result;
    }

    /**
     * Deserializes the payment schedule list, handling both typed and untyped inputs.
     */
    private static List<PaymentScheduleItem> deserializePaymentSchedule(Object scheduleObj) {
        List<PaymentScheduleItem> schedule = new List<PaymentScheduleItem>();

        if (scheduleObj == null) {
            return schedule;
        }

        List<Object> scheduleList;
        try {
            scheduleList = (List<Object>) scheduleObj;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to cast paymentSchedule to List: ' + e.getMessage());
            return schedule;
        }

        for (Object itemObj : scheduleList) {
            PaymentScheduleItem item = deserializeScheduleItem(itemObj);
            if (item != null) {
                schedule.add(item);
            }
        }

        return schedule;
    }

    /**
     * Deserializes a single payment schedule item from various input formats.
     * Supports both LWC Map format and typed PaymentScheduleItem.
     */
    private static PaymentScheduleItem deserializeScheduleItem(Object itemObj) {
        if (itemObj == null) {
            return null;
        }

        // If already a PaymentScheduleItem, return as-is
        if (itemObj instanceof PaymentScheduleItem) {
            return (PaymentScheduleItem) itemObj;
        }

        // Convert to Map for field extraction
        Map<String, Object> itemMap;
        // Direct cast - LWC JavaScript objects deserialize as Map<String, Object> in Apex
        if (itemObj instanceof Map<String, Object>) {
            itemMap = (Map<String, Object>) itemObj;
        } else {
            System.debug(LoggingLevel.ERROR, 'Unexpected type for schedule item: ' + String.valueOf(itemObj));
            return null;
        }

        PaymentScheduleItem item = new PaymentScheduleItem();

        // Map with fallbacks for field name variations (LWC may use different names)
        item.paymentNumber = getIntegerValue(itemMap, 'paymentNumber', 'draftNumber', 'weekNumber');
        item.paymentDate = getStringValue(itemMap, 'paymentDate');
        item.totalPayment = getDecimalValue(itemMap, 'totalPayment', 'paymentAmount', 'draftAmount');
        item.setupFee = getDecimalValue(itemMap, 'setupFee');
        item.bankingFee = getDecimalValue(itemMap, 'bankingFee');
        item.programPayment = getDecimalValue(itemMap, 'programPayment', 'programFee', 'programPortion', 'programAmount');
        item.escrowPayment = getDecimalValue(itemMap, 'escrowPayment', 'escrowAmount', 'savingsBalance');
        item.additionalProducts = getDecimalValue(itemMap, 'additionalProducts');
        item.remainingBalance = getDecimalValue(itemMap, 'remainingBalance');

        return item;
    }

    // Type-safe value extraction helpers
    private static Decimal getDecimalValue(Map<String, Object> m, String key) {
        Object val = m.get(key);
        if (val == null) return null;
        return Decimal.valueOf(String.valueOf(val));
    }

    private static Decimal getDecimalValue(Map<String, Object> m, String key1, String key2) {
        Object val = m.get(key1);
        if (val == null) val = m.get(key2);
        if (val == null) return null;
        return Decimal.valueOf(String.valueOf(val));
    }

    private static Decimal getDecimalValue(Map<String, Object> m, String key1, String key2, String key3) {
        Object val = m.get(key1);
        if (val == null) val = m.get(key2);
        if (val == null) val = m.get(key3);
        if (val == null) return null;
        return Decimal.valueOf(String.valueOf(val));
    }

    private static Decimal getDecimalValue(Map<String, Object> m, String key1, String key2, String key3, String key4) {
        Object val = m.get(key1);
        if (val == null) val = m.get(key2);
        if (val == null) val = m.get(key3);
        if (val == null) val = m.get(key4);
        if (val == null) return null;
        return Decimal.valueOf(String.valueOf(val));
    }

    private static Integer getIntegerValue(Map<String, Object> m, String key) {
        Object val = m.get(key);
        if (val == null) return null;
        return Integer.valueOf(String.valueOf(val));
    }

    private static Integer getIntegerValue(Map<String, Object> m, String key1, String key2, String key3) {
        Object val = m.get(key1);
        if (val == null) val = m.get(key2);
        if (val == null) val = m.get(key3);
        if (val == null) return null;
        return Integer.valueOf(String.valueOf(val));
    }

    private static String getStringValue(Map<String, Object> m, String key) {
        Object val = m.get(key);
        if (val == null) return null;
        return String.valueOf(val);
    }

    /**
     * Builds a ConfigWrapper from native PaymentDraft__c fields.
     * Following Salesforce best practice: Use strongly-typed wrapper classes instead of Maps.
     *
     * @param draft The PaymentDraft__c record with native fields
     * @return ConfigWrapper with configuration values for LWC consumption
     */
    private static ConfigWrapper buildConfigFromDraft(PaymentDraft__c draft) {
        ConfigWrapper config = new ConfigWrapper();

        // Map native fields to wrapper properties
        config.programType = draft.Program_Type__c;
        config.paymentFrequency = draft.Payment_Frequency__c;
        config.noFeeProgram = draft.No_Fee_Program__c;
        config.settlementPercent = draft.Settlement_Percentage__c;
        config.programFeePercent = draft.Program_Fee_Percentage__c;
        config.setupFeeTotal = draft.Setup_Fee__c;
        config.setupFeePayments = draft.Setup_Fee_Term__c != null ? draft.Setup_Fee_Term__c.intValue() : null;
        config.bankingFee = draft.Banking_Fee__c;
        config.firstDraftDate = draft.First_Draft_Date__c != null ? String.valueOf(draft.First_Draft_Date__c) : null;
        config.targetPaymentPercent = draft.Target_Payment_Percent__c;
        config.calculateBy = draft.Calculation_Mode__c;
        config.preferredDayOfWeek = draft.Preferred_Day_of_Week__c != null ? draft.Preferred_Day_of_Week__c.intValue() : null;

        return config;
    }

    /**
     * Builds a CalculationResult from native PaymentDraft__c fields.
     * Following Salesforce best practice: Use strongly-typed wrapper classes instead of Maps.
     *
     * @param draft The PaymentDraft__c record with native fields
     * @return CalculationResult with calculation values for LWC consumption
     */
    private static CalculationResult buildCalcFromDraft(PaymentDraft__c draft) {
        CalculationResult calc = new CalculationResult();

        // Map native fields to wrapper properties
        calc.weeklyPayment = draft.Weekly_Payment__c;
        calc.monthlyPayment = draft.Monthly_Payment__c;
        calc.numberOfWeeks = draft.Number_of_Weeks__c != null ? draft.Number_of_Weeks__c.intValue() : null;
        calc.settlementAmount = draft.Settlement_Amount__c;
        calc.programFee = draft.Program_Fee_Amount__c;
        calc.bankingFeeTotal = draft.Total_Banking_Fee__c;
        calc.totalProgram = draft.Total_Program__c;
        calc.totalSavings = draft.Total_Savings__c;
        calc.totalDebt = draft.Estimated_Total_Debt__c;
        calc.currentPayment = draft.Estimated_Current_Payment__c;
        calc.firstDraftDate = draft.First_Draft_Date__c != null ? String.valueOf(draft.First_Draft_Date__c) : null;

        return calc;
    }

    /**
     * Overloaded: Advanced saveDraft supporting overwrite, optional calculations, and retention cap.
     * Uses strongly-typed deserialization for payment schedule items.
     */
    @AuraEnabled
    public static Id saveDraftV2(
        Id recordId,
        String draftName,
        Map<String, Object> config,
        Id draftIdToOverwrite,
        Map<String, Object> calculationsOptional
    ) {
        System.debug(LoggingLevel.DEBUG, '=== saveDraftV2 START ===');
        System.debug(LoggingLevel.DEBUG, 'recordId: ' + recordId);
        System.debug(LoggingLevel.DEBUG, 'draftName: ' + draftName);
        System.debug(LoggingLevel.DEBUG, 'draftIdToOverwrite: ' + draftIdToOverwrite);
        System.debug(LoggingLevel.DEBUG, 'config keys: ' + (config != null ? String.valueOf(config.keySet()) : 'null'));

        try {
            String sObjectType = recordId.getSObjectType().getDescribe().getName();
            System.debug(LoggingLevel.DEBUG, 'sObjectType: ' + sObjectType);

            // Deserialize calculations to strongly-typed object (for use with createPaymentDraftItems and populateDraftFields)
            CalculationResult typedCalculations = deserializeCalculations(calculationsOptional);

            PaymentDraft__c draft;
            Boolean isUpdate = draftIdToOverwrite != null;

            if (isUpdate) {
                System.debug(LoggingLevel.DEBUG, 'UPDATING existing draft: ' + draftIdToOverwrite);
                draft = [
                    SELECT Id, Draft_Name__c, Is_Active__c
                    FROM PaymentDraft__c
                    WHERE Id = :draftIdToOverwrite
                    LIMIT 1
                ];
                System.debug(LoggingLevel.DEBUG, 'Found draft, Is_Active__c: ' + draft.Is_Active__c);
                draft.Draft_Name__c = draftName != null ? draftName : draft.Draft_Name__c;

                // Populate config and calculation fields on the draft (native fields only, no JSON)
                populateDraftFields(draft, config, typedCalculations);

                System.debug(LoggingLevel.DEBUG, 'About to update draft');
                Database.update(draft, AccessLevel.USER_MODE);
                System.debug(LoggingLevel.DEBUG, 'Draft updated successfully');

                // Create/update Payment Draft Items from payment schedule using strongly-typed data
                if (typedCalculations != null) {
                    createPaymentDraftItems(draft.Id, typedCalculations);
                }
                
                // Update Opportunity base fields from draft (only for Opportunity records)
                updateOpportunityFromDraft(recordId, config, typedCalculations);

                return draft.Id;
            } else {
                // Clear Primary_Key__c from ALL drafts (active and inactive) to avoid unique constraint violation
                // This handles legacy data that may have Primary_Key__c set on inactive drafts
                List<PaymentDraft__c> existingWithPrimaryKey;
                if (sObjectType == 'Lead') {
                    existingWithPrimaryKey = [
                        SELECT Id, Is_Primary__c, Primary_Key__c
                        FROM PaymentDraft__c
                        WHERE Lead__c = :recordId AND Primary_Key__c != null
                    ];
                } else {
                    existingWithPrimaryKey = [
                        SELECT Id, Is_Primary__c, Primary_Key__c
                        FROM PaymentDraft__c
                        WHERE Opportunity__c = :recordId AND Primary_Key__c != null
                    ];
                }
                System.debug(LoggingLevel.DEBUG, 'Found ' + existingWithPrimaryKey.size() + ' drafts with Primary_Key__c to clear');
                for (PaymentDraft__c existing : existingWithPrimaryKey) {
                    existing.Is_Primary__c = false;
                    existing.Primary_Key__c = null;
                }
                if (!existingWithPrimaryKey.isEmpty()) {
                    Database.update(existingWithPrimaryKey, AccessLevel.SYSTEM_MODE);
                    System.debug(LoggingLevel.DEBUG, 'Cleared Primary_Key__c from existing drafts');
                }
                
                System.debug(LoggingLevel.DEBUG, 'Creating NEW draft');
                draft = new PaymentDraft__c();
                draft.Draft_Name__c = String.isNotBlank(draftName) ? draftName : 'Draft ' + String.valueOf(Datetime.now());
                draft.Created_By_Calculator__c = true;

                // Auto-set new draft as primary and active
                draft.Is_Primary__c = true;
                draft.Primary_Key__c = String.valueOf(recordId);
                draft.Is_Active__c = true;  // Explicitly set active for new drafts

                // Populate config and calculation fields on the draft (native fields only, no JSON)
                populateDraftFields(draft, config, typedCalculations);

                if (sObjectType == 'Lead') {
                    draft.Lead__c = recordId;
                } else if (sObjectType == 'Opportunity') {
                    draft.Opportunity__c = recordId;
                }

                System.debug(LoggingLevel.DEBUG, 'About to insert new draft');
                Database.insert(draft, AccessLevel.USER_MODE);
                System.debug(LoggingLevel.DEBUG, 'Draft inserted with Id: ' + draft.Id);

                // Create Payment Draft Items from payment schedule using strongly-typed data
                if (typedCalculations != null) {
                    System.debug(LoggingLevel.DEBUG, 'Creating payment draft items');
                    createPaymentDraftItems(draft.Id, typedCalculations);
                }

                // Update Opportunity base fields from draft (only for Opportunity records)
                System.debug(LoggingLevel.DEBUG, 'Updating opportunity from draft');
                updateOpportunityFromDraft(recordId, config, typedCalculations);

                System.debug(LoggingLevel.DEBUG, '=== saveDraftV2 END (success) ===');
                return draft.Id;
            }
        } catch (DmlException dmx) {
            System.debug(LoggingLevel.ERROR, '=== saveDraftV2 DML EXCEPTION ===');
            System.debug(LoggingLevel.ERROR, 'Message: ' + dmx.getMessage());
            System.debug(LoggingLevel.ERROR, 'DML Index: ' + dmx.getDmlIndex(0));
            System.debug(LoggingLevel.ERROR, 'DML Fields: ' + dmx.getDmlFieldNames(0));
            System.debug(LoggingLevel.ERROR, 'Stack: ' + dmx.getStackTraceString());
            throw new AuraHandledException('Error saving draft: ' + dmx.getMessage());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '=== saveDraftV2 GENERAL EXCEPTION ===');
            System.debug(LoggingLevel.ERROR, 'Type: ' + e.getTypeName());
            System.debug(LoggingLevel.ERROR, 'Message: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('Error saving draft: ' + e.getMessage());
        }
    }
    
    /**
     * Loads all drafts for a given record.
     * Following Salesforce best practice: Returns strongly-typed wrapper class instead of Map<String, Object>.
     *
     * @param recordId The Lead or Opportunity ID
     * @return List of DraftWrapper objects for LWC consumption
     */
    @AuraEnabled
    public static List<DraftWrapper> loadDrafts(Id recordId) {
        try {
            String sObjectType = recordId.getSObjectType().getDescribe().getName();
            List<DraftWrapper> drafts = new List<DraftWrapper>();
            List<PaymentDraft__c> draftRecords = new List<PaymentDraft__c>();

            if (sObjectType == 'Lead') {
                draftRecords = [
                    SELECT Id, Draft_Name__c, CreatedDate, CreatedBy.Name, Is_Primary__c,
                           Weekly_Payment__c, Monthly_Payment__c, Number_of_Weeks__c,
                           Total_Savings__c, Estimated_Total_Debt__c, Estimated_Current_Payment__c,
                           Sync_Status__c, Invalidated_Date__c,
                           Settlement_Amount__c, Program_Fee_Amount__c, Total_Banking_Fee__c, Total_Program__c,
                           Program_Type__c, Payment_Frequency__c, No_Fee_Program__c,
                           Settlement_Percentage__c, Program_Fee_Percentage__c,
                           Setup_Fee__c, Setup_Fee_Term__c, Banking_Fee__c, First_Draft_Date__c,
                           Target_Payment_Percent__c, Calculation_Mode__c, Preferred_Day_of_Week__c
                    FROM PaymentDraft__c
                    WHERE Lead__c = :recordId
                    ORDER BY Is_Primary__c DESC, CreatedDate DESC
                    LIMIT 1999
                ];
            } else if (sObjectType == 'Opportunity') {
                draftRecords = [
                    SELECT Id, Draft_Name__c, CreatedDate, CreatedBy.Name, Is_Primary__c,
                           Weekly_Payment__c, Monthly_Payment__c, Number_of_Weeks__c,
                           Total_Savings__c, Estimated_Total_Debt__c, Estimated_Current_Payment__c,
                           Sync_Status__c, Invalidated_Date__c,
                           Settlement_Amount__c, Program_Fee_Amount__c, Total_Banking_Fee__c, Total_Program__c,
                           Program_Type__c, Payment_Frequency__c, No_Fee_Program__c,
                           Settlement_Percentage__c, Program_Fee_Percentage__c,
                           Setup_Fee__c, Setup_Fee_Term__c, Banking_Fee__c, First_Draft_Date__c,
                           Target_Payment_Percent__c, Calculation_Mode__c, Preferred_Day_of_Week__c
                    FROM PaymentDraft__c
                    WHERE Opportunity__c = :recordId
                    ORDER BY Is_Primary__c DESC, CreatedDate DESC
                    LIMIT 1999
                ];
            }

            // Convert to DraftWrapper for LWC consumption
            for (PaymentDraft__c draft : draftRecords) {
                DraftWrapper wrapper = new DraftWrapper();

                // Basic draft info
                wrapper.id = draft.Id;
                wrapper.name = draft.Draft_Name__c;
                wrapper.createdDate = draft.CreatedDate;
                wrapper.createdBy = draft.CreatedBy?.Name;
                wrapper.isPrimary = draft.Is_Primary__c == true;
                wrapper.syncStatus = draft.Sync_Status__c;
                wrapper.invalidatedDate = draft.Invalidated_Date__c;

                // Use helper methods to build config and calculations
                wrapper.config = buildConfigFromDraft(draft);
                wrapper.calculations = buildCalcFromDraft(draft);

                // Set summary fields from calculations
                wrapper.weeklyPayment = wrapper.calculations.weeklyPayment;
                wrapper.numberOfWeeks = wrapper.calculations.numberOfWeeks;

                // Calculate percent savings: (currentPayment - weeklyPayment) / currentPayment * 100
                Decimal currentPayment = wrapper.calculations.currentPayment;
                Decimal weeklyPayment = wrapper.calculations.weeklyPayment;
                if (currentPayment != null && currentPayment > 0 && weeklyPayment != null) {
                    Decimal weeklySavings = currentPayment - weeklyPayment;
                    wrapper.savingsPercent = (weeklySavings / currentPayment * 100).setScale(1, System.RoundingMode.HALF_UP);
                }

                drafts.add(wrapper);
            }

            return drafts;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading drafts: ' + e.getMessage());
        }
    }

    /**
     * Returns the primary draft for a given parent record, if any.
     * Following Salesforce best practice: Returns strongly-typed wrapper class instead of Map<String, Object>.
     *
     * @param recordId The Lead or Opportunity ID
     * @return DraftWrapper object or null if no primary draft exists
     */
    @AuraEnabled
    public static DraftWrapper getPrimaryDraft(Id recordId) {
        try {
            String sObjectType = recordId.getSObjectType().getDescribe().getName();
            PaymentDraft__c draft = null;

            if (sObjectType == 'Lead') {
                List<PaymentDraft__c> rows = [
                    SELECT Id, Draft_Name__c, CreatedDate, CreatedBy.Name, Is_Primary__c,
                           Weekly_Payment__c, Monthly_Payment__c, Number_of_Weeks__c,
                           Total_Savings__c, Estimated_Total_Debt__c, Estimated_Current_Payment__c,
                           Sync_Status__c, Invalidated_Date__c,
                           Settlement_Amount__c, Program_Fee_Amount__c, Total_Banking_Fee__c, Total_Program__c,
                           Program_Type__c, Payment_Frequency__c, No_Fee_Program__c,
                           Settlement_Percentage__c, Program_Fee_Percentage__c,
                           Setup_Fee__c, Setup_Fee_Term__c, Banking_Fee__c, First_Draft_Date__c,
                           Target_Payment_Percent__c, Calculation_Mode__c, Preferred_Day_of_Week__c
                    FROM PaymentDraft__c
                    WHERE Lead__c = :recordId AND Is_Primary__c = true AND Is_Active__c = true
                    LIMIT 1
                ];
                draft = rows.isEmpty() ? null : rows[0];
            } else if (sObjectType == 'Opportunity') {
                List<PaymentDraft__c> rows = [
                    SELECT Id, Draft_Name__c, CreatedDate, CreatedBy.Name, Is_Primary__c,
                           Weekly_Payment__c, Monthly_Payment__c, Number_of_Weeks__c,
                           Total_Savings__c, Estimated_Total_Debt__c, Estimated_Current_Payment__c,
                           Sync_Status__c, Invalidated_Date__c,
                           Settlement_Amount__c, Program_Fee_Amount__c, Total_Banking_Fee__c, Total_Program__c,
                           Program_Type__c, Payment_Frequency__c, No_Fee_Program__c,
                           Settlement_Percentage__c, Program_Fee_Percentage__c,
                           Setup_Fee__c, Setup_Fee_Term__c, Banking_Fee__c, First_Draft_Date__c,
                           Target_Payment_Percent__c, Calculation_Mode__c, Preferred_Day_of_Week__c
                    FROM PaymentDraft__c
                    WHERE Opportunity__c = :recordId AND Is_Primary__c = true AND Is_Active__c = true
                    LIMIT 1
                ];
                draft = rows.isEmpty() ? null : rows[0];
            }

            if (draft == null) {
                return null;
            }

            // Build DraftWrapper from draft record
            DraftWrapper wrapper = new DraftWrapper();
            wrapper.id = draft.Id;
            wrapper.name = draft.Draft_Name__c;
            wrapper.createdDate = draft.CreatedDate;
            wrapper.createdBy = draft.CreatedBy?.Name;
            wrapper.isPrimary = draft.Is_Primary__c == true;
            wrapper.syncStatus = draft.Sync_Status__c;
            wrapper.invalidatedDate = draft.Invalidated_Date__c;
            wrapper.config = buildConfigFromDraft(draft);
            wrapper.calculations = buildCalcFromDraft(draft);

            // Set summary fields
            wrapper.weeklyPayment = wrapper.calculations.weeklyPayment;
            wrapper.numberOfWeeks = wrapper.calculations.numberOfWeeks;

            return wrapper;
        } catch (Exception e) {
            throw new AuraHandledException('Error getting primary draft: ' + e.getMessage());
        }
    }

    /**
     * Sets the provided draft as primary and unsets siblings. Enforces uniqueness via Primary_Key__c.
     * Also syncs draft field values to the parent Opportunity.
     */
    @AuraEnabled
    public static void setPrimaryDraft(Id draftId) {
        System.debug(LoggingLevel.DEBUG, '=== setPrimaryDraft START ===');
        System.debug(LoggingLevel.DEBUG, 'draftId: ' + draftId);
        try {
            PaymentDraft__c target = [
                SELECT Id, Lead__c, Opportunity__c,
                       Weekly_Payment__c, Number_of_Weeks__c, First_Draft_Date__c,
                       Estimated_Total_Debt__c, Estimated_Current_Payment__c, Payment_Frequency__c,
                       Settlement_Percentage__c, Program_Fee_Percentage__c,
                       Setup_Fee__c, Setup_Fee_Term__c, Banking_Fee__c, Program_Type__c, No_Fee_Program__c
                FROM PaymentDraft__c
                WHERE Id = :draftId
                LIMIT 1
            ];
            System.debug(LoggingLevel.DEBUG, 'Draft found: ' + target.Id);

            Id parentId = target.Lead__c != null ? target.Lead__c : target.Opportunity__c;
            System.debug(LoggingLevel.DEBUG, 'parentId: ' + parentId);
            if (parentId == null) {
                throw new AuraHandledException('Draft is not associated with a parent record.');
            }

            // Unset other primaries for the same parent (only consider active drafts)
            List<PaymentDraft__c> siblings = [
                SELECT Id, Is_Primary__c, Primary_Key__c
                FROM PaymentDraft__c
                WHERE (Lead__c = :parentId OR Opportunity__c = :parentId)
                  AND Id != :draftId
                  AND Is_Primary__c = true
                  AND Is_Active__c = true
            ];
            System.debug(LoggingLevel.DEBUG, 'Found ' + siblings.size() + ' sibling drafts to demote');
            for (PaymentDraft__c s : siblings) {
                s.Is_Primary__c = false;
                s.Primary_Key__c = null;
            }
            if (!siblings.isEmpty()) {
                Database.update(siblings, AccessLevel.USER_MODE);
                System.debug(LoggingLevel.DEBUG, 'Sibling drafts demoted');
            }

            // Now set target as primary
            PaymentDraft__c updateTarget = new PaymentDraft__c(
                Id = draftId,
                Is_Primary__c = true,
                Primary_Key__c = String.valueOf(parentId)
            );
            Database.update(updateTarget, AccessLevel.USER_MODE);
            System.debug(LoggingLevel.DEBUG, 'Draft set as primary');

            // Update Opportunity fields directly from draft fields (no JSON parsing needed)
            System.debug(LoggingLevel.DEBUG, 'Syncing draft fields to Opportunity...');
            updateOpportunityFromPrimaryDraft(parentId, target);
            System.debug(LoggingLevel.DEBUG, '=== setPrimaryDraft END (success) ===');

        } catch (DmlException dmx) {
            System.debug(LoggingLevel.ERROR, '=== setPrimaryDraft DML EXCEPTION ===');
            System.debug(LoggingLevel.ERROR, 'Message: ' + dmx.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + dmx.getStackTraceString());
            // Handle unique constraint gracefully
            throw new AuraHandledException('Could not set primary draft due to a uniqueness conflict. Please retry. Details: ' + dmx.getMessage());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '=== setPrimaryDraft GENERAL EXCEPTION ===');
            System.debug(LoggingLevel.ERROR, 'Type: ' + e.getTypeName());
            System.debug(LoggingLevel.ERROR, 'Message: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('Error setting primary draft: ' + e.getMessage());
        }
    }

    /**
     * Updates Opportunity fields directly from PaymentDraft__c fields.
     * More efficient than parsing JSON - uses direct field mapping.
     *
     * IMPORTANT: This method will throw exceptions if the Opportunity update fails.
     * When setting a primary draft, syncing to Opportunity is the main purpose,
     * so failures should be visible to the user.
     */
    private static void updateOpportunityFromPrimaryDraft(Id recordId, PaymentDraft__c draft) {
        String sObjectType = recordId.getSObjectType().getDescribe().getName();

        // Only update Opportunity records
        if (sObjectType != 'Opportunity') {
            System.debug(LoggingLevel.DEBUG, '[updateOpportunityFromPrimaryDraft] Skipping - not an Opportunity: ' + sObjectType);
            return;
        }

        System.debug(LoggingLevel.DEBUG, '[updateOpportunityFromPrimaryDraft] Starting sync for Opportunity: ' + recordId);

        // Log draft field values for debugging
        System.debug(LoggingLevel.DEBUG, '[updateOpportunityFromPrimaryDraft] Draft field values:');
        System.debug(LoggingLevel.DEBUG, '  - Number_of_Weeks__c: ' + draft.Number_of_Weeks__c);
        System.debug(LoggingLevel.DEBUG, '  - Weekly_Payment__c: ' + draft.Weekly_Payment__c);
        System.debug(LoggingLevel.DEBUG, '  - Estimated_Total_Debt__c: ' + draft.Estimated_Total_Debt__c);
        System.debug(LoggingLevel.DEBUG, '  - Estimated_Current_Payment__c: ' + draft.Estimated_Current_Payment__c);
        System.debug(LoggingLevel.DEBUG, '  - Payment_Frequency__c: ' + draft.Payment_Frequency__c);
        System.debug(LoggingLevel.DEBUG, '  - First_Draft_Date__c: ' + draft.First_Draft_Date__c);
        System.debug(LoggingLevel.DEBUG, '  - Banking_Fee__c: ' + draft.Banking_Fee__c);
        System.debug(LoggingLevel.DEBUG, '  - Setup_Fee_Term__c: ' + draft.Setup_Fee_Term__c);
        System.debug(LoggingLevel.DEBUG, '  - No_Fee_Program__c: ' + draft.No_Fee_Program__c);
        System.debug(LoggingLevel.DEBUG, '  - Program_Type__c: ' + draft.Program_Type__c);
        System.debug(LoggingLevel.DEBUG, '  - Settlement_Percentage__c: ' + draft.Settlement_Percentage__c);
        System.debug(LoggingLevel.DEBUG, '  - Program_Fee_Percentage__c: ' + draft.Program_Fee_Percentage__c);

        Opportunity opp = new Opportunity(Id = recordId);
        Boolean hasUpdates = false;
        List<String> updatedFields = new List<String>();

        // Map draft fields to Opportunity fields
        if (draft.Number_of_Weeks__c != null) {
            opp.Number_of_Weeks__c = draft.Number_of_Weeks__c;
            hasUpdates = true;
            updatedFields.add('Number_of_Weeks__c');
        }
        if (draft.Weekly_Payment__c != null) {
            opp.Est_weekly_payment__c = draft.Weekly_Payment__c;
            hasUpdates = true;
            updatedFields.add('Est_weekly_payment__c');
        }
        // NOTE: Estimated_Total_Debt__c and Estimated_Current_Payment__c are SOURCE fields on Opportunity.
        // Drafts READ from these fields but should NEVER write back to them.
        // The Opportunity is the source of truth for debt data.

        if (draft.First_Draft_Date__c != null) {
            opp.First_Draft_Date__c = draft.First_Draft_Date__c;
            hasUpdates = true;
            updatedFields.add('First_Draft_Date__c');
        }
        if (draft.Banking_Fee__c != null) {
            opp.Banking_Fee__c = draft.Banking_Fee__c;
            hasUpdates = true;
            updatedFields.add('Banking_Fee__c');
        }
        if (draft.Setup_Fee_Term__c != null) {
            opp.Setup_Fee_Term__c = String.valueOf(draft.Setup_Fee_Term__c);
            hasUpdates = true;
            updatedFields.add('Setup_Fee_Term__c');
        }
        if (draft.No_Fee_Program__c != null) {
            opp.No_Fee_Program__c = draft.No_Fee_Program__c;
            hasUpdates = true;
            updatedFields.add('No_Fee_Program__c');
        }
        if (String.isNotBlank(draft.Program_Type__c)) {
            // Convert underscores to spaces for picklist value (DCG_MOD -> DCG MOD)
            opp.Program_Type__c = draft.Program_Type__c.replace('_', ' ');
            hasUpdates = true;
            updatedFields.add('Program_Type__c');
        }
        if (draft.Settlement_Percentage__c != null) {
            opp.Est_Settlement__c = String.valueOf(draft.Settlement_Percentage__c.intValue()) + '%';
            hasUpdates = true;
            updatedFields.add('Est_Settlement__c');
        }
        if (draft.Program_Fee_Percentage__c != null) {
            Decimal programFeePct = draft.Program_Fee_Percentage__c;
            // For No Fee Programs (0%), use baseline fee from config - fee is still calculated, just diverted to escrow
            if (programFeePct == 0) {
                try {
                    PaymentCalcConfigSvc.ConfigDTO cfg = PaymentCalcConfigSvc.getRequiredConfig();
                    programFeePct = cfg.baselineNoFeeProgramFee;
                    System.debug(LoggingLevel.DEBUG, '[updateOpportunityFromPrimaryDraft] No Fee Program - using config baseline fee: ' + programFeePct + '%');
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR, '[updateOpportunityFromPrimaryDraft] Cannot set Program_Fee__c - config unavailable: ' + e.getMessage());
                    programFeePct = null;
                }
            }
            if (programFeePct != null) {
                opp.Program_Fee__c = String.valueOf(programFeePct.intValue()) + '%';
                hasUpdates = true;
                updatedFields.add('Program_Fee__c');
            }
        }

        if (hasUpdates) {
            System.debug(LoggingLevel.DEBUG, '[updateOpportunityFromPrimaryDraft] Updating fields: ' + String.join(updatedFields, ', '));
            // Let exceptions propagate - when setting primary draft, the sync to Opportunity
            // is the main purpose, so failures should be visible to the user
            Database.update(opp, AccessLevel.SYSTEM_MODE);
            System.debug(LoggingLevel.DEBUG, '[updateOpportunityFromPrimaryDraft] Opportunity updated successfully');
        } else {
            // This is a problem - the draft has no field values to sync
            System.debug(LoggingLevel.WARN, '[updateOpportunityFromPrimaryDraft] WARNING: No draft fields have values - nothing to sync to Opportunity. ' +
                'This draft may have been created before field population was implemented, or the fields were never saved.');
        }
    }

    /**
     * Deactivates a draft (soft delete). If it was primary, auto-promote the most recent remaining active draft.
     *
     * DESIGN DECISION: Soft Delete (Activate/Deactivate) Strategy
     * -----------------------------------------------------------
     * We intentionally DEACTIVATE PaymentDraft__c records (soft delete) rather than physically
     * deleting them. This matches the existing pattern used for Payment_Draft_Item__c records.
     *
     * Benefits:
     * 1. AUDIT TRAIL: Preserves complete history of all drafts for compliance and debugging.
     * 2. COMPLIANCE: Supports regulatory requirements for data retention.
     * 3. RECOVERY: Allows potential reactivation of previous drafts.
     * 4. CONSISTENCY: Aligns with Payment_Draft_Item__c soft-delete pattern.
     */
    @AuraEnabled
    public static void deactivateDraft(Id draftId) {
        System.debug(LoggingLevel.DEBUG, '=== deactivateDraft START ===');
        System.debug(LoggingLevel.DEBUG, 'draftId: ' + draftId);
        try {
            PaymentDraft__c target = [
                SELECT Id, Lead__c, Opportunity__c, Is_Primary__c, Is_Active__c
                FROM PaymentDraft__c
                WHERE Id = :draftId
                LIMIT 1
            ];
            System.debug(LoggingLevel.DEBUG, 'Found draft - Is_Active__c: ' + target.Is_Active__c + ', Is_Primary__c: ' + target.Is_Primary__c);

            Id parentId = target.Lead__c != null ? target.Lead__c : target.Opportunity__c;
            Boolean wasPrimary = target.Is_Primary__c == true;
            System.debug(LoggingLevel.DEBUG, 'parentId: ' + parentId + ', wasPrimary: ' + wasPrimary);

            // Soft delete: Set Is_Active__c = false and record deactivation timestamp
            target.Is_Active__c = false;
            target.Deactivated_Date__c = DateTime.now();
            // Clear primary status if it was primary
            if (wasPrimary) {
                target.Is_Primary__c = false;
                target.Primary_Key__c = null;
            }
            System.debug(LoggingLevel.DEBUG, 'About to deactivate draft');
            Database.update(target, AccessLevel.USER_MODE);
            System.debug(LoggingLevel.DEBUG, 'Draft deactivated successfully');

            if (wasPrimary && parentId != null) {
                System.debug(LoggingLevel.DEBUG, 'Looking for draft to auto-promote');
                // Promote most recent remaining ACTIVE draft as primary (if any)
                List<PaymentDraft__c> remaining = [
                    SELECT Id
                    FROM PaymentDraft__c
                    WHERE (Lead__c = :parentId OR Opportunity__c = :parentId)
                      AND Is_Active__c = true
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                System.debug(LoggingLevel.DEBUG, 'Found ' + remaining.size() + ' candidates for promotion');
                if (!remaining.isEmpty()) {
                    PaymentDraft__c promote = new PaymentDraft__c(
                        Id = remaining[0].Id,
                        Is_Primary__c = true,
                        Primary_Key__c = String.valueOf(parentId)
                    );
                    Database.update(promote, AccessLevel.USER_MODE);
                    System.debug(LoggingLevel.DEBUG, 'Promoted draft: ' + remaining[0].Id);
                }
            }
            System.debug(LoggingLevel.DEBUG, '=== deactivateDraft END (success) ===');
        } catch (DmlException dmx) {
            System.debug(LoggingLevel.ERROR, '=== deactivateDraft DML EXCEPTION ===');
            System.debug(LoggingLevel.ERROR, 'Message: ' + dmx.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + dmx.getStackTraceString());
            throw new AuraHandledException('Error deactivating draft: ' + dmx.getMessage());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '=== deactivateDraft GENERAL EXCEPTION ===');
            System.debug(LoggingLevel.ERROR, 'Type: ' + e.getTypeName());
            System.debug(LoggingLevel.ERROR, 'Message: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('Error deactivating draft: ' + e.getMessage());
        }
    }

    /**
     * Reactivates a previously deactivated draft.
     * Note: Does not automatically set as primary - use setPrimaryDraft() separately if needed.
     */
    @AuraEnabled
    public static void activateDraft(Id draftId) {
        System.debug(LoggingLevel.DEBUG, '=== activateDraft START ===');
        System.debug(LoggingLevel.DEBUG, 'draftId: ' + draftId);
        try {
            PaymentDraft__c target = [
                SELECT Id, Is_Active__c, Deactivated_Date__c
                FROM PaymentDraft__c
                WHERE Id = :draftId
                LIMIT 1
            ];
            System.debug(LoggingLevel.DEBUG, 'Found draft - Is_Active__c: ' + target.Is_Active__c + ', Deactivated_Date__c: ' + target.Deactivated_Date__c);

            target.Is_Active__c = true;
            target.Deactivated_Date__c = null;
            System.debug(LoggingLevel.DEBUG, 'About to reactivate draft');
            Database.update(target, AccessLevel.USER_MODE);
            System.debug(LoggingLevel.DEBUG, '=== activateDraft END (success) ===');
        } catch (DmlException dmx) {
            System.debug(LoggingLevel.ERROR, '=== activateDraft DML EXCEPTION ===');
            System.debug(LoggingLevel.ERROR, 'Message: ' + dmx.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + dmx.getStackTraceString());
            throw new AuraHandledException('Error activating draft: ' + dmx.getMessage());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '=== activateDraft GENERAL EXCEPTION ===');
            System.debug(LoggingLevel.ERROR, 'Type: ' + e.getTypeName());
            System.debug(LoggingLevel.ERROR, 'Message: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('Error activating draft: ' + e.getMessage());
        }
    }

    // Helper Methods
    
    /**
     * Get or create Opportunity ID from Lead or Opportunity
     */
    @TestVisible()
    private static Id getOrCreateOpportunityId(Id recordId) {
        String sObjectType = recordId.getSObjectType().getDescribe().getName();
        
        if (sObjectType == 'Opportunity') {
            return recordId;
        } else if (sObjectType == 'Lead') {
            // For now, throw an error - Lead conversion would need to be implemented
            throw new AuraHandledException('Payment Plan versions currently only support Opportunities. Please convert the Lead to an Opportunity first.');
        } else {
            throw new AuraHandledException('Invalid record type. Payment plans can only be created for Leads or Opportunities.');
        }
    }
    
    /**
     * Update Lead/Opportunity fields with calculated debt totals
     */
    private static void updateRecordDebtTotals(Id recordId, Decimal totalDebt, Decimal currentPayment) {
        String sObjectType = recordId.getSObjectType().getDescribe().getName();
        
        try {
            if (sObjectType == 'Lead') {
                Lead lead = [SELECT Id FROM Lead WHERE Id = :recordId LIMIT 1];
                // Assuming custom fields exist - these would need to be created
                // lead.Total_Debt__c = totalDebt;
                // lead.Current_Payment__c = currentPayment;
                // update lead;
            } else if (sObjectType == 'Opportunity') {
                Opportunity opp = [SELECT Id FROM Opportunity WHERE Id = :recordId LIMIT 1];
                // Assuming custom fields exist - these would need to be created
                // opp.Total_Debt__c = totalDebt;
                // opp.Current_Payment__c = currentPayment;
                // update opp;
            }
        } catch (Exception e) {
            System.debug('Could not update record debt totals: ' + e.getMessage());
        }
    }
    
    /**
     * Updates Opportunity base fields from draft configuration and calculations.
     * These base fields drive formula fields that auto-calculate dependent values.
     * Only updates Opportunity records (not Leads).
     *
     * @param recordId The Lead or Opportunity ID
     * @param config Configuration map containing settings like settlement percentage, program fee percentage
     * @param calculations Strongly-typed calculation results
     */
    private static void updateOpportunityFromDraft(Id recordId, Map<String, Object> config, CalculationResult calculations) {
        String sObjectType = recordId.getSObjectType().getDescribe().getName();
        
        // Only update Opportunity records
        if (sObjectType != 'Opportunity') {
            System.debug('[updateOpportunityFromDraft] Skipping - not an Opportunity record: ' + sObjectType);
            return;
        }
        
        System.debug('[updateOpportunityFromDraft] Starting update for Opportunity: ' + recordId);
        System.debug('[updateOpportunityFromDraft] calculations is null: ' + (calculations == null));
        System.debug('[updateOpportunityFromDraft] config is null: ' + (config == null));
        
        Opportunity opp = new Opportunity(Id = recordId);
        Boolean hasUpdates = false;
        
        // Number fields from calculations
        // NOTE: Estimated_Total_Debt__c and Estimated_Current_Payment__c are SOURCE fields on Opportunity.
        // Drafts READ from these fields but should NEVER write back to them.
        // The Opportunity is the source of truth for debt data.
        if (calculations != null) {
            System.debug('[updateOpportunityFromDraft] numberOfWeeks: ' + calculations.numberOfWeeks);
            System.debug('[updateOpportunityFromDraft] firstDraftDate: ' + calculations.firstDraftDate);

            if (calculations.numberOfWeeks != null) {
                opp.Number_of_Weeks__c = calculations.numberOfWeeks;
                hasUpdates = true;
            }

            // Weekly payment - set Estimated weekly payment from calculated weekly payment
            if (calculations.weeklyPayment != null) {
                opp.Est_weekly_payment__c = calculations.weeklyPayment;
                System.debug('[updateOpportunityFromDraft] weeklyPayment: ' + calculations.weeklyPayment);
                hasUpdates = true;
            }
            
            // Date field - parse from string
            if (String.isNotBlank(calculations.firstDraftDate)) {
                opp.First_Draft_Date__c = parsePaymentDate(calculations.firstDraftDate);
                hasUpdates = true;
            }
        }
        
        // Currency fields from config
        // Supports both LWC key names and Apex key names for compatibility
        if (config != null) {
            Object bankingFeeObj = config.get('bankingFee');
            System.debug('[updateOpportunityFromDraft] bankingFee from config: ' + bankingFeeObj);
            if (bankingFeeObj != null) {
                opp.Banking_Fee__c = (bankingFeeObj instanceof Decimal)
                    ? (Decimal)bankingFeeObj
                    : Decimal.valueOf(String.valueOf(bankingFeeObj));
                hasUpdates = true;
            }

            // Setup fee term picklist - convert integer to string
            Object setupFeeTermObj = config.get('setupFeePayments');
            System.debug('[updateOpportunityFromDraft] setupFeePayments from config: ' + setupFeeTermObj);
            if (setupFeeTermObj != null) {
                Integer setupFeeTerm = (setupFeeTermObj instanceof Integer)
                    ? (Integer)setupFeeTermObj
                    : Integer.valueOf(String.valueOf(setupFeeTermObj));
                opp.Setup_Fee_Term__c = String.valueOf(setupFeeTerm);
                hasUpdates = true;
            }

            // No Fee Program checkbox - affects Setup_Fee__c formula ($2500 if true, $1000 if false)
            Object noFeeProgramObj = config.get('noFeeProgram');
            System.debug('[updateOpportunityFromDraft] noFeeProgram from config: ' + noFeeProgramObj);
            Boolean noFeeProgram = false;
            if (noFeeProgramObj != null) {
                noFeeProgram = (noFeeProgramObj instanceof Boolean)
                    ? (Boolean)noFeeProgramObj
                    : Boolean.valueOf(String.valueOf(noFeeProgramObj));
                opp.No_Fee_Program__c = noFeeProgram;
                hasUpdates = true;
            }

            // Program Type picklist - "DCG DEBT", "DCG MOD", or "DCG MOD CA" (spaces, all caps)
            // Config uses underscores (DCG_MOD), picklist uses spaces (DCG MOD)
            // Save exactly what user selected
            Object programTypeObj = config.get('programType');
            System.debug('[updateOpportunityFromDraft] programType from config: ' + programTypeObj);
            if (programTypeObj != null) {
                String programType = String.valueOf(programTypeObj).toUpperCase();
                // Convert underscores to spaces for picklist value (DCG_MOD -> DCG MOD)
                String picklistValue = programType.replace('_', ' ');
                opp.Program_Type__c = picklistValue;
                System.debug('[updateOpportunityFromDraft] Setting Program_Type__c to: ' + picklistValue);
                hasUpdates = true;
            }

            // Config-dependent picklist validation (optional - gracefully degrades if config unavailable)
            try {
                PaymentCalcConfigSvc.ConfigDTO cfgValid = PaymentCalcConfigSvc.getRequiredConfig();

                // Picklist fields - convert numbers to formatted strings with % suffix
                // LWC sends 'settlementPercent', Apex uses 'settlementPercentage'
                // Est_Settlement__c picklist only allows values from config
                Object settlementPctObj = config.get('settlementPercentage');
                if (settlementPctObj == null) settlementPctObj = config.get('settlementPercent');
                System.debug('[updateOpportunityFromDraft] settlementPct from config: ' + settlementPctObj);
                if (settlementPctObj != null) {
                    Decimal settlementPct = (settlementPctObj instanceof Decimal)
                        ? (Decimal)settlementPctObj
                        : Decimal.valueOf(String.valueOf(settlementPctObj));
                    Integer settlementInt = settlementPct.intValue();

                    // Get valid settlement values from config
                    Set<Integer> validSettlementValues = new Set<Integer>();
                    if (String.isNotBlank(cfgValid.validSettlementValues)) {
                        for (String valStr : cfgValid.validSettlementValues.split(',')) {
                            validSettlementValues.add(Integer.valueOf(valStr.trim()));
                        }
                    }

                    // Only update if value matches valid picklist options
                    if (validSettlementValues.contains(settlementInt)) {
                        opp.Est_Settlement__c = String.valueOf(settlementInt) + '%';
                        hasUpdates = true;
                    } else {
                        System.debug('[updateOpportunityFromDraft] Skipping Est_Settlement__c update - value ' + settlementInt + '% is not a valid picklist option');
                    }
                }

                // LWC sends 'programFeePercent', Apex uses 'programFeePercentage'
                // Program_Fee__c picklist only allows values within config-defined range
                // For No Fee Programs (0%), use the baseline fee - fees are diverted to escrow, not waived
                Object programFeePctObj = config.get('programFeePercentage');
                if (programFeePctObj == null) programFeePctObj = config.get('programFeePercent');
                System.debug('[updateOpportunityFromDraft] programFeePct from config: ' + programFeePctObj);
                if (programFeePctObj != null) {
                    Decimal programFeePct = (programFeePctObj instanceof Decimal)
                        ? (Decimal)programFeePctObj
                        : Decimal.valueOf(String.valueOf(programFeePctObj));

                    // Get program fee range from config (already loaded above)
                    Decimal minProgramFeePercent = cfgValid.minProgramFeePercent;
                    Decimal maxProgramFeePercent = cfgValid.maxProgramFeePercent;
                    Decimal baselineNoFeeProgramFee = cfgValid.baselineNoFeeProgramFee;

                    // For No Fee Programs (0%), use baseline fee - the fee is still earned, just diverted to escrow
                    if (programFeePct == 0) {
                        // Check if there's an original fee percentage stored (for No Fee Programs)
                        Object originalFeePctObj = config.get('noFeeProgramOriginalFeePercentage');
                        if (originalFeePctObj != null) {
                            programFeePct = (originalFeePctObj instanceof Decimal)
                                ? (Decimal)originalFeePctObj
                                : Decimal.valueOf(String.valueOf(originalFeePctObj));
                        } else {
                            programFeePct = baselineNoFeeProgramFee;
                        }
                        System.debug('[updateOpportunityFromDraft] No Fee Program detected - using baseline fee: ' + programFeePct + '%');
                    }

                    // Only update if value is within valid picklist range
                    if (programFeePct >= minProgramFeePercent && programFeePct <= maxProgramFeePercent) {
                        opp.Program_Fee__c = String.valueOf(programFeePct.intValue()) + '%';
                        hasUpdates = true;
                    } else {
                        System.debug('[updateOpportunityFromDraft] Skipping Program_Fee__c update - value ' + programFeePct + '% is outside valid picklist range (' + minProgramFeePercent + '-' + maxProgramFeePercent + '%)');
                    }
                }
            } catch (PaymentCalcConfigException e) {
                // Config not available - skip config-validated picklist updates
                System.debug('[updateOpportunityFromDraft] Skipping config-validated fields - CMDT config not available: ' + e.getMessage());
            }
        }
        
        if (hasUpdates) {
            // Use SYSTEM_MODE to bypass FLS restrictions for system-generated updates
            // Following Salesforce best practice: Surface errors to users instead of silent catch
            Database.update(opp, AccessLevel.SYSTEM_MODE);
        }
    }
    
    /**
     * Populates PaymentDraft__c fields from config and calculations.
     * Sets both configuration fields and calculated result fields.
     * 
     * @param draft The PaymentDraft__c record to populate
     * @param config Configuration map containing settings
     * @param calculations Strongly-typed calculation results (can be null for config-only saves)
     */
    private static void populateDraftFields(PaymentDraft__c draft, Map<String, Object> config, CalculationResult calculations) {
        // Populate configuration fields from config map
        // Supports both LWC key names and Apex key names for compatibility
        if (config != null) {
            // Settlement percentage - LWC sends 'settlementPercent', Apex uses 'settlementPercentage'
            Object settlementPctObj = config.get('settlementPercentage');
            if (settlementPctObj == null) settlementPctObj = config.get('settlementPercent');
            if (settlementPctObj != null) {
                draft.Settlement_Percentage__c = (settlementPctObj instanceof Decimal) 
                    ? (Decimal)settlementPctObj 
                    : Decimal.valueOf(String.valueOf(settlementPctObj));
            }
            
            // Program fee percentage - LWC sends 'programFeePercent', Apex uses 'programFeePercentage'
            Object programFeePctObj = config.get('programFeePercentage');
            if (programFeePctObj == null) programFeePctObj = config.get('programFeePercent');
            if (programFeePctObj != null) {
                draft.Program_Fee_Percentage__c = (programFeePctObj instanceof Decimal) 
                    ? (Decimal)programFeePctObj 
                    : Decimal.valueOf(String.valueOf(programFeePctObj));
            }
            
            // Setup fee - LWC sends 'setupFeeTotal', Apex uses 'setupFee'
            Object setupFeeObj = config.get('setupFee');
            if (setupFeeObj == null) setupFeeObj = config.get('setupFeeTotal');
            if (setupFeeObj != null) {
                draft.Setup_Fee__c = (setupFeeObj instanceof Decimal) 
                    ? (Decimal)setupFeeObj 
                    : Decimal.valueOf(String.valueOf(setupFeeObj));
            }
            
            // Setup fee term (number of payments)
            Object setupFeeTermObj = config.get('setupFeePayments');
            if (setupFeeTermObj != null) {
                draft.Setup_Fee_Term__c = (setupFeeTermObj instanceof Integer) 
                    ? (Integer)setupFeeTermObj 
                    : Integer.valueOf(String.valueOf(setupFeeTermObj));
            }
            
            // Banking fee
            Object bankingFeeObj = config.get('bankingFee');
            if (bankingFeeObj != null) {
                draft.Banking_Fee__c = (bankingFeeObj instanceof Decimal)
                    ? (Decimal)bankingFeeObj
                    : Decimal.valueOf(String.valueOf(bankingFeeObj));
            }

            // Program type
            Object programTypeObj = config.get('programType');
            if (programTypeObj != null) {
                draft.Program_Type__c = String.valueOf(programTypeObj);
            }

            // No fee program
            Object noFeeProgramObj = config.get('noFeeProgram');
            if (noFeeProgramObj != null) {
                draft.No_Fee_Program__c = (noFeeProgramObj instanceof Boolean)
                    ? (Boolean)noFeeProgramObj
                    : Boolean.valueOf(String.valueOf(noFeeProgramObj));
            }

            // Payment frequency
            Object paymentFrequencyObj = config.get('paymentFrequency');
            if (paymentFrequencyObj != null) {
                draft.Payment_Frequency__c = String.valueOf(paymentFrequencyObj);
            }

            // NEW: Target payment percent (slider value) - for restoring slider position
            Object targetPctObj = config.get('targetPaymentPercent');
            if (targetPctObj != null) {
                draft.Target_Payment_Percent__c = (targetPctObj instanceof Decimal)
                    ? (Decimal)targetPctObj
                    : Decimal.valueOf(String.valueOf(targetPctObj));
            }

            // NEW: Calculation mode (PERCENT or DESIRED) - for restoring calculator mode
            Object calcModeObj = config.get('calculateBy');
            if (calcModeObj != null) {
                draft.Calculation_Mode__c = String.valueOf(calcModeObj);
            }

            // NEW: Preferred day of week (1-5) - for payment scheduling
            Object dayOfWeekObj = config.get('preferredDayOfWeek');
            if (dayOfWeekObj != null) {
                draft.Preferred_Day_of_Week__c = (dayOfWeekObj instanceof Integer)
                    ? (Integer)dayOfWeekObj
                    : Integer.valueOf(String.valueOf(dayOfWeekObj));
            }
        }

        // Populate calculation result fields from calculations object
        if (calculations != null) {
            draft.Number_of_Weeks__c = calculations.numberOfWeeks;
            draft.Weekly_Payment__c = calculations.weeklyPayment;
            draft.Monthly_Payment__c = calculations.monthlyPayment;
            draft.Settlement_Amount__c = calculations.settlementAmount;
            draft.Program_Fee_Amount__c = calculations.programFee;
            draft.Total_Banking_Fee__c = calculations.bankingFeeTotal;
            draft.Total_Program__c = calculations.totalProgram;
            draft.Total_Savings__c = calculations.totalSavings;
            draft.Estimated_Total_Debt__c = calculations.totalDebt;
            draft.Estimated_Current_Payment__c = calculations.currentPayment;

            // First draft date - parse from string
            if (String.isNotBlank(calculations.firstDraftDate)) {
                draft.First_Draft_Date__c = parsePaymentDate(calculations.firstDraftDate);
            }
        }
    }
    
    /**
     * Create or update PaymentPlan__c record
     */
    private static Id createPaymentPlanRecord(Id recordId, Id contractId, CalculationResult calculations, Map<String, Object> config) {
        String sObjectType = recordId.getSObjectType().getDescribe().getName();
        
        PaymentPlan__c paymentPlan = new PaymentPlan__c();
        paymentPlan.Contract__c = contractId;
        // Set a safe default program type if not provided
        String cfgProgramType = (config != null && config.containsKey('programType')) ? String.valueOf(config.get('programType')) : null;
        paymentPlan.Program_Type__c = String.isNotBlank(cfgProgramType) ? cfgProgramType : 'DCG_MOD';
        paymentPlan.Total_Debt__c = calculations.totalDebt;
        paymentPlan.Settlement_Percentage__c = (Decimal)config.get('settlementPercentage');
        paymentPlan.Program_Fee_Percentage__c = (Decimal)config.get('programFeePercentage');
        paymentPlan.Total_Program_Cost__c = calculations.totalProgram;
        paymentPlan.Weekly_Payment__c = calculations.weeklyPayment;
        paymentPlan.Number_of_Payments__c = calculations.numberOfWeeks;
        paymentPlan.First_Payment_Date__c = Date.valueOf(calculations.firstDraftDate);
        paymentPlan.Status__c = 'Draft';
        // Align with versioning fields if present in org
        paymentPlan.Version_Status__c = 'Draft';
        paymentPlan.Version_Number__c = 1;
        
        if (sObjectType == 'Opportunity') {
            paymentPlan.Opportunity__c = recordId;
        }
        // Note: PaymentPlan__c currently only supports Opportunity. 
        // For Lead support, need to add Lead__c lookup field or convert Lead to Opportunity first
        
        Database.insert(paymentPlan, AccessLevel.USER_MODE);
        return paymentPlan.Id;
    }
    
    /**
     * Get or create PaymentPlan__c record for approval process
     */
    private static Id getOrCreatePaymentPlan(Id recordId, CalculationResult calculations, Map<String, Object> config) {

        String sObjectType = recordId.getSObjectType().getDescribe().getName();
        List<PaymentPlan__c> existingPlans = new List<PaymentPlan__c>();
        
        if (sObjectType == 'Opportunity') {
            existingPlans = [SELECT Id FROM PaymentPlan__c WHERE Opportunity__c = :recordId ORDER BY CreatedDate DESC LIMIT 1];
        }
        // Note: Lead support requires Lead__c field on PaymentPlan__c or Lead conversion to Opportunity
        
        if (!existingPlans.isEmpty()) {
            return existingPlans[0].Id;
        } else {
            // Create new payment plan without contract
            return createPaymentPlanRecord(recordId, null, calculations, config);
        }
    }
    
    
    private static Id getAccountId(Id recordId) {
        String sObjectType = recordId.getSObjectType().getDescribe().getName();
        
        if (sObjectType == 'Lead') {
            Lead lead = [SELECT ConvertedAccountId FROM Lead WHERE Id = :recordId LIMIT 1];
            return lead.ConvertedAccountId;
        } else if (sObjectType == 'Opportunity') {
            Opportunity opp = [SELECT AccountId FROM Opportunity WHERE Id = :recordId LIMIT 1];
            return opp.AccountId;
        }
        
        return null;
    }
    
    private static void updateRecordStatus(Id recordId, String status) {
        String sObjectType = recordId.getSObjectType().getDescribe().getName();
        
        if (sObjectType == 'Lead') {
            Lead lead = [SELECT Id, Status FROM Lead WHERE Id = :recordId LIMIT 1];
            lead.Status = 'Qualified';
            Database.update(lead, AccessLevel.USER_MODE);
        } else if (sObjectType == 'Opportunity') {
            Opportunity opp = [SELECT Id, StageName FROM Opportunity WHERE Id = :recordId LIMIT 1];
            opp.StageName = 'Proposal/Price Quote';
            Database.update(opp, AccessLevel.USER_MODE);
        }
    }
    
    @TestVisible()
    private static Date getNextMonday() {
        Date today = Date.today();
        Integer dayOfWeek = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(today), 7);
        
        if (dayOfWeek == 1) {
            // Today is Monday
            return today.addDays(7);
        } else {
            // Calculate days until next Monday
            Integer daysUntilMonday = Math.mod(8 - dayOfWeek, 7);
            return today.addDays(daysUntilMonday);
        }
    }
    
    // Inner Classes

    /**
     * @description Wrapper class for draft configuration data - replaces Map<String, Object>
     * Following Salesforce best practice: Use strongly-typed wrapper classes instead of generic Maps
     */
    public class ConfigWrapper {
        @AuraEnabled public String programType { get; set; }
        @AuraEnabled public String paymentFrequency { get; set; }
        @AuraEnabled public String calculateBy { get; set; }
        @AuraEnabled public Decimal targetPaymentPercent { get; set; }
        @AuraEnabled public Decimal targetPaymentAmount { get; set; }
        @AuraEnabled public Integer setupFeePayments { get; set; }
        @AuraEnabled public Decimal setupFeeTotal { get; set; }
        @AuraEnabled public Boolean noFeeProgram { get; set; }
        @AuraEnabled public Decimal settlementPercent { get; set; }
        @AuraEnabled public Decimal programFeePercent { get; set; }
        @AuraEnabled public Decimal bankingFee { get; set; }
        @AuraEnabled public String firstDraftDate { get; set; }
        @AuraEnabled public Integer preferredDayOfWeek { get; set; }
        @AuraEnabled public List<String> selectedProductCodes { get; set; }

        public ConfigWrapper() {
            this.selectedProductCodes = new List<String>();
        }
    }

    /**
     * @description Wrapper class for draft data returned to LWC - replaces Map<String, Object>
     * Following Salesforce best practice: Use strongly-typed wrapper classes instead of generic Maps
     */
    public class DraftWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public String createdBy { get; set; }
        @AuraEnabled public Boolean isPrimary { get; set; }
        @AuraEnabled public Decimal weeklyPayment { get; set; }
        @AuraEnabled public Integer numberOfWeeks { get; set; }
        @AuraEnabled public Decimal savingsPercent { get; set; }
        @AuraEnabled public String syncStatus { get; set; }
        @AuraEnabled public Datetime invalidatedDate { get; set; }
        @AuraEnabled public ConfigWrapper config { get; set; }
        @AuraEnabled public CalculationResult calculations { get; set; }

        public DraftWrapper() {
            this.config = new ConfigWrapper();
            this.calculations = new CalculationResult();
        }
    }

    public class CalculationResult {
        @AuraEnabled public Decimal totalDebt { get; set; }
        @AuraEnabled public Decimal currentPayment { get; set; }
        @AuraEnabled public Decimal settlementAmount { get; set; }
        @AuraEnabled public Decimal programFee { get; set; }
        @AuraEnabled public Decimal setupFeeTotal { get; set; }
        @AuraEnabled public Decimal bankingFeeTotal { get; set; }
        @AuraEnabled public Decimal totalProgram { get; set; }
        @AuraEnabled public Decimal totalSavings { get; set; }
        @AuraEnabled public Integer numberOfWeeks { get; set; }
        @AuraEnabled public Decimal weeklyPayment { get; set; }
        @AuraEnabled public Decimal monthlyPayment { get; set; }
        @AuraEnabled public Decimal savingsPercentage { get; set; }
        @AuraEnabled public String firstDraftDate { get; set; }
        @AuraEnabled public Decimal programSplitRatio { get; set; }
        @AuraEnabled public Decimal escrowSplitRatio { get; set; }
        @AuraEnabled public List<PaymentScheduleItem> paymentSchedule { get; set; }
    }
    
    public class PaymentScheduleItem {
        @AuraEnabled public Integer paymentNumber { get; set; }
        @AuraEnabled public String paymentDate { get; set; }
        @AuraEnabled public Decimal totalPayment { get; set; }
        @AuraEnabled public Decimal setupFee { get; set; }
        @AuraEnabled public Decimal bankingFee { get; set; }
        @AuraEnabled public Decimal programPayment { get; set; }
        @AuraEnabled public Decimal escrowPayment { get; set; }
        @AuraEnabled public Decimal additionalProducts { get; set; }
        @AuraEnabled public Decimal remainingBalance { get; set; }
    }
}