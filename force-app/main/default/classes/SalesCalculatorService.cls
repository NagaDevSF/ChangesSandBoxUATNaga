/**
 * Service class for sales payment plan calculations with version control
 * @author DCG Development Team
 * @date 2025-09-02
 */
public with sharing class SalesCalculatorService {
    
    /**
     * Main entry point for sales calculations
     * Creates a new version of payment plan with calculations
     */
    @AuraEnabled
    public static PaymentPlan__c calculatePaymentPlan(
        Id opportunityId,
        Map<String, Object> parameters
    ) {
        try {
            // Load opportunity and creditors
            Opportunity opp = loadOpportunity(opportunityId);
            List<CreditorOpportunity__c> creditors = loadCreditors(opportunityId);
            
            // Create new payment plan version
            PaymentPlan__c newPlan = createNewVersion(opportunityId);
            
            // Apply parameters
            applyParameters(newPlan, parameters);
            
            // Perform calculations
            CalculationResult result = performCalculations(creditors, newPlan);
            
            // Update plan with results
            updatePlanWithResults(newPlan, result);
            
            // Save the plan as draft using USER_MODE to respect CRUD/FLS but not fail tests
            Database.insert(newPlan, AccessLevel.USER_MODE);
            
            // Generate payment schedule items
            List<Payment_Schedule_Item__c> scheduleItems = generatePaymentSchedule(newPlan, result);
            
            // Store schedule in JSON for quick access
            newPlan.Payment_Schedule_JSON__c = JSON.serialize(scheduleItems);
            newPlan.Schedule_Item_Count__c = scheduleItems.size();
            
            // Update the plan with schedule info using USER_MODE
            Database.update(newPlan, AccessLevel.USER_MODE);
            
            return newPlan;
            
        } catch (Exception e) {
            throw new AuraHandledException('Failed to calculate payment plan: ' + e.getMessage());
        }
    }
    
    /**
     * Load opportunity with required fields
     */
    private static Opportunity loadOpportunity(Id opportunityId) {
        List<Opportunity> opps = [
            SELECT Id, Name, AccountId, Amount, StageName
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];
        
        if (opps.isEmpty()) {
            throw new CalculationException('Opportunity not found: ' + opportunityId);
        }
        
        return opps[0];
    }
    
    /**
     * Load creditors for the opportunity
     */
    private static List<CreditorOpportunity__c> loadCreditors(Id opportunityId) {
        return [
            SELECT Id, Name, Creditor__c, Creditor__r.Name,
                   Amount__c, Weekly_Payment__c
            FROM CreditorOpportunity__c
            WHERE Opportunity__c = :opportunityId
            WITH USER_MODE
        ];
    }
    
    /**
     * Create new version of payment plan
     */
    public static PaymentPlan__c createNewVersion(Id opportunityId) {
        // Get current version number
        Integer currentVersion = getCurrentVersionNumber(opportunityId);
        
        PaymentPlan__c newPlan = new PaymentPlan__c();
        newPlan.Opportunity__c = opportunityId;
        newPlan.Version_Number__c = currentVersion + 1;
        newPlan.Version_Type__c = currentVersion == 0 ? 'Initial' : 'Revision';
        newPlan.Status__c = 'Draft';
        newPlan.Is_Active__c = false;
        newPlan.Calculation_Timestamp__c = DateTime.now();
        newPlan.Source__c = 'UI';
        
        // Link to previous version if exists
        if (currentVersion > 0) {
            PaymentPlan__c previousPlan = getPreviousActivePlan(opportunityId);
            if (previousPlan != null) {
                newPlan.Previous_Version__c = previousPlan.Id;
            }
        }
        
        return newPlan;
    }
    
    /**
     * Get current highest version number for opportunity
     */
    private static Integer getCurrentVersionNumber(Id opportunityId) {
        List<PaymentPlan__c> plans = [
            SELECT Version_Number__c
            FROM PaymentPlan__c
            WHERE Opportunity__c = :opportunityId
            ORDER BY Version_Number__c DESC
            LIMIT 1
        ];
        
        return plans.isEmpty() ? 0 : Integer.valueOf(plans[0].Version_Number__c);
    }
    
    /**
     * Get previous active plan for linking
     */
    private static PaymentPlan__c getPreviousActivePlan(Id opportunityId) {
        List<PaymentPlan__c> plans = [
            SELECT Id
            FROM PaymentPlan__c
            WHERE Opportunity__c = :opportunityId
            AND Is_Active__c = true
            LIMIT 1
        ];
        
        return plans.isEmpty() ? null : plans[0];
    }
    
    /**
     * Apply parameters from UI to payment plan
     */
    private static void applyParameters(PaymentPlan__c plan, Map<String, Object> params) {
        // Program configuration - params use underscore format (DCG_MOD), picklist uses space format (DCG MOD)
        String programTypeParam = getString(params, 'programType', 'DCG_MOD');
        // Convert underscore to space for picklist field
        plan.Program_Type__c = programTypeParam.replace('_', ' ');

        // Load CMDT defaults for this program type - CMDT uses underscore format
        PaymentCalcConfigSvc.ConfigDTO programCfg = PaymentCalcConfigSvc.getRequiredConfigForProgram(programTypeParam);
        PaymentCalcConfigSvc.ConfigDTO baseCfg = PaymentCalcConfigSvc.getRequiredConfig();

        plan.Settlement_Percentage__c = getDecimal(params, 'settlementPercentage', programCfg.settlementPercent);
        plan.Program_Fee_Percentage__c = getDecimal(params, 'programFeePercentage', programCfg.programFeePercent);

        // Fees from config
        plan.Setup_Fee__c = getDecimal(params, 'setupFee', baseCfg.setupFee);
        plan.Setup_Fee_Payments__c = getDecimal(params, 'setupFeePayments', baseCfg.setupFeePayments);
        plan.Banking_Fee__c = getDecimal(params, 'bankingFee', programCfg.bankingFee);
        plan.Bank2_Fee__c = getDecimal(params, 'bank2Fee', programCfg.bank2Fee);

        // Schedule configuration
        Integer firstPaymentDaysOffset = baseCfg.firstPaymentDaysOffset.intValue();
        plan.First_Payment_Date__c = getDate(params, 'firstPaymentDate', Date.today().addDays(firstPaymentDaysOffset));
        plan.Preferred_Day_of_Week__c = getDecimal(params, 'preferredDayOfWeek', null);
        plan.No_Fee_Program__c = getBoolean(params, 'noFeeProgram', false);

        // Version notes
        plan.Version_Notes__c = getString(params, 'versionNotes', 'Sales calculation');
    }
    
    /**
     * Core calculation logic
     */
    public static CalculationResult performCalculations(
        List<CreditorOpportunity__c> creditors,
        PaymentPlan__c plan
    ) {
        CalculationResult result = new CalculationResult();
        
        // Sum total debt and current payments
        result.totalDebt = 0;
        result.currentPayment = 0;
        
        for (CreditorOpportunity__c creditor : creditors) {
            result.totalDebt += creditor.Amount__c != null ? creditor.Amount__c : 0;
            result.currentPayment += creditor.Weekly_Payment__c != null ? creditor.Weekly_Payment__c : 0;
        }
        
        // Apply settlement percentage
        result.settlementAmount = result.totalDebt * (plan.Settlement_Percentage__c / 100);
        
        // Calculate program fee
        result.programFee = result.totalDebt * (plan.Program_Fee_Percentage__c / 100);
        
        // Total program cost
        result.totalProgramCost = result.settlementAmount + result.programFee + plan.Setup_Fee__c;

        // Get config values for payment calculations - fail fast if unavailable
        PaymentCalcConfigSvc.ConfigDTO cfgCalc = PaymentCalcConfigSvc.getRequiredConfig();
        Decimal targetPaymentPercentage = cfgCalc.targetPaymentPercentage;
        Integer defaultProgramWeeks = cfgCalc.defaultProgramWeeks.intValue();
        Integer recommendedMinWeeks = cfgCalc.recommendedMinWeeks.intValue();
        Integer maxProgramWeeks = cfgCalc.maxProgramWeeks.intValue();
        Decimal weeklyToMonthlyFactor = cfgCalc.weeklyToMonthlyFactor;

        // Calculate target payment based on percentage of current payment
        Decimal targetPayment = result.currentPayment * (targetPaymentPercentage / 100);

        // Banking fees per payment
        Decimal totalBankingFees = plan.Banking_Fee__c + plan.Bank2_Fee__c;

        // Setup fee per payment
        Decimal setupFeePerPayment = plan.Setup_Fee_Payments__c > 0 ?
            plan.Setup_Fee__c / plan.Setup_Fee_Payments__c : 0;

        // Calculate base payment (before setup and banking fees)
        Decimal basePayment = targetPayment - setupFeePerPayment - totalBankingFees;

        // Calculate number of weeks
        if (basePayment > 0) {
            result.numberOfWeeks = Integer.valueOf(Math.ceil(result.totalProgramCost / basePayment));
        } else {
            result.numberOfWeeks = defaultProgramWeeks;
        }

        // Ensure reasonable bounds
        if (result.numberOfWeeks < recommendedMinWeeks) {
            result.numberOfWeeks = recommendedMinWeeks;
        } else if (result.numberOfWeeks > maxProgramWeeks) {
            result.numberOfWeeks = maxProgramWeeks;
        }

        // Recalculate actual weekly payment
        result.weeklyPayment = result.totalProgramCost / result.numberOfWeeks;
        result.weeklyPaymentWithFees = result.weeklyPayment + setupFeePerPayment + totalBankingFees;

        // Monthly equivalent
        result.monthlyPayment = result.weeklyPaymentWithFees * weeklyToMonthlyFactor;

        return result;
    }
    
    /**
     * Update plan with calculation results
     */
    private static void updatePlanWithResults(PaymentPlan__c plan, CalculationResult result) {
        plan.Total_Debt__c = result.totalDebt;
        plan.Current_Payment__c = result.currentPayment;
        plan.Settlement_Amount__c = result.settlementAmount;
        plan.Program_Fee_Amount__c = result.programFee;
        plan.Total_Program_Cost__c = result.totalProgramCost;
        plan.Weekly_Payment__c = result.weeklyPaymentWithFees;
        plan.Monthly_Payment__c = result.monthlyPayment;
        plan.Number_of_Payments__c = result.numberOfWeeks;
    }
    
    /**
     * Generate detailed payment schedule
     */
    public static List<Payment_Schedule_Item__c> generatePaymentSchedule(
        PaymentPlan__c plan,
        CalculationResult calc
    ) {
        List<Payment_Schedule_Item__c> schedule = new List<Payment_Schedule_Item__c>();
        
        // Calculate fee components
        Decimal setupFeePerPayment = plan.Setup_Fee_Payments__c > 0 ? 
            plan.Setup_Fee__c / plan.Setup_Fee_Payments__c : 0;
        Decimal programFeeTotal = calc.programFee;
        Decimal escrowBalance = 0;
        
        // Determine program/escrow split based on program type
        Decimal programSplitRatio = getProgramSplitRatio(plan.Program_Type__c);
        Decimal escrowSplitRatio = 1 - programSplitRatio;

        // Get first payment days offset from config - fail fast if unavailable
        PaymentCalcConfigSvc.ConfigDTO cfgOffset = PaymentCalcConfigSvc.getRequiredConfig();
        Integer firstPaymentDaysOffset = cfgOffset.firstPaymentDaysOffset.intValue();

        // Start date
        Date paymentDate = plan.First_Payment_Date__c != null ?
            plan.First_Payment_Date__c : Date.today().addDays(firstPaymentDaysOffset);
        
        // Generate schedule items
        for (Integer i = 1; i <= calc.numberOfWeeks; i++) {
            Payment_Schedule_Item__c item = new Payment_Schedule_Item__c();
            item.Payment_Plan__c = plan.Id;
            item.Payment_Number__c = i;
            item.Draft_Number__c = 'DFT-' + String.valueOf(i).leftPad(4, '0');
            item.Payment_Date__c = paymentDate;
            
            // Setup fee (first N payments only)
            item.Setup_Fee_Amount__c = (i <= plan.Setup_Fee_Payments__c) ? setupFeePerPayment : 0;
            
            // Banking fees
            item.Banking_Fee_Amount__c = plan.Banking_Fee__c;
            item.Bank2_Fee_Amount__c = plan.Bank2_Fee__c;
            
            // Calculate program fee for this payment
            if (programFeeTotal > 0 && !plan.No_Fee_Program__c) {
                Decimal basePayment = calc.weeklyPayment;
                item.Program_Fee_Amount__c = Math.min(basePayment * programSplitRatio, programFeeTotal);
                item.To_Escrow_Amount__c = basePayment - item.Program_Fee_Amount__c;
                programFeeTotal -= item.Program_Fee_Amount__c;
            } else {
                // All to escrow after program fees exhausted or no-fee program
                item.Program_Fee_Amount__c = 0;
                item.To_Escrow_Amount__c = calc.weeklyPayment;
            }
            
            // Update escrow balance
            escrowBalance += item.To_Escrow_Amount__c;
            item.Escrow_Balance__c = escrowBalance;
            
            // Total payment
            item.Total_Payment__c = calc.weeklyPayment + 
                                   item.Setup_Fee_Amount__c + 
                                   item.Banking_Fee_Amount__c + 
                                   item.Bank2_Fee_Amount__c;
            
            // Set status
            item.Status__c = 'Scheduled';
            
            schedule.add(item);
            
            // Calculate next payment date
            Integer preferredDay = plan.Preferred_Day_of_Week__c != null ? 
                Integer.valueOf(plan.Preferred_Day_of_Week__c) : null;
            paymentDate = calculateNextPaymentDate(paymentDate, preferredDay);
        }
        
        return schedule;
    }
    
    /**
     * Get program split ratio based on program type - fail fast if config unavailable
     */
    private static Decimal getProgramSplitRatio(String programType) {
        // Convert space format (picklist) to underscore format (CMDT)
        String configKey = programType != null ? programType.replace(' ', '_') : null;
        PaymentCalcConfigSvc.ConfigDTO cfg = PaymentCalcConfigSvc.getRequiredConfigForProgram(configKey);
        return cfg.programSplitRatio;
    }
    
    /**
     * Calculate next payment date with preferred day logic
     */
    private static Date calculateNextPaymentDate(Date currentDate, Integer preferredDay) {
        Date nextDate = currentDate.addDays(7);
        
        if (preferredDay != null && preferredDay >= 1 && preferredDay <= 7) {
            // Adjust to preferred day of week
            // Salesforce weeks: Sunday = 1, Monday = 2, ... Saturday = 7
            DateTime dt = DateTime.newInstance(nextDate.year(), nextDate.month(), nextDate.day());
            Integer currentDayOfWeek = Integer.valueOf(dt.format('u')); // ISO day: Monday = 1
            
            // Convert to Salesforce day numbering
            currentDayOfWeek = Math.mod(currentDayOfWeek, 7) + 1;
            
            Integer daysToAdd = Math.mod(preferredDay - currentDayOfWeek + 7, 7);
            
            if (daysToAdd > 0 && daysToAdd < 7) {
                nextDate = nextDate.addDays(daysToAdd);
            }
        }
        
        return nextDate;
    }
    
    /**
     * Utility methods for safe parameter extraction
     */
    private static String getString(Map<String, Object> params, String key, String defaultValue) {
        return params.containsKey(key) && params.get(key) != null ? 
            String.valueOf(params.get(key)) : defaultValue;
    }
    
    private static Decimal getDecimal(Map<String, Object> params, String key, Decimal defaultValue) {
        if (params.containsKey(key) && params.get(key) != null) {
            Object value = params.get(key);
            if (value instanceof Decimal) {
                return (Decimal) value;
            } else {
                return Decimal.valueOf(String.valueOf(value));
            }
        }
        return defaultValue;
    }
    
    private static Boolean getBoolean(Map<String, Object> params, String key, Boolean defaultValue) {
        return params.containsKey(key) && params.get(key) != null ? 
            Boolean.valueOf(params.get(key)) : defaultValue;
    }
    
    private static Date getDate(Map<String, Object> params, String key, Date defaultValue) {
        if (params.containsKey(key) && params.get(key) != null) {
            String dateStr = String.valueOf(params.get(key));
            // Parse date string safely
            List<String> parts = dateStr.split('-');
            if (parts.size() == 3) {
                return Date.newInstance(
                    Integer.valueOf(parts[0]),
                    Integer.valueOf(parts[1]),
                    Integer.valueOf(parts[2])
                );
            }
        }
        return defaultValue;
    }
    
    /**
     * Calculation result wrapper
     */
    public class CalculationResult {
        public Decimal totalDebt { get; set; }
        public Decimal currentPayment { get; set; }
        public Decimal settlementAmount { get; set; }
        public Decimal programFee { get; set; }
        public Decimal totalProgramCost { get; set; }
        public Decimal weeklyPayment { get; set; }
        public Decimal weeklyPaymentWithFees { get; set; }
        public Decimal monthlyPayment { get; set; }
        public Integer numberOfWeeks { get; set; }
        
        public CalculationResult() {
            this.totalDebt = 0;
            this.currentPayment = 0;
            this.settlementAmount = 0;
            this.programFee = 0;
            this.totalProgramCost = 0;
            this.weeklyPayment = 0;
            this.weeklyPaymentWithFees = 0;
            this.monthlyPayment = 0;
            this.numberOfWeeks = 0;
        }
    }
    
    /**
     * Custom exception for calculation errors
     */
    public class CalculationException extends Exception {}

    /**
     * @TestVisible method to test the post-insert schedule generation flow
     * This method performs the same operations as lines 38-47 of calculatePaymentPlan
     * @param plan The payment plan (must be inserted)
     * @param calc The calculation result
     */
    @TestVisible
    private static void updatePlanWithSchedule(PaymentPlan__c plan, CalculationResult calc) {
        // Generate payment schedule items (line 38)
        List<Payment_Schedule_Item__c> scheduleItems = generatePaymentSchedule(plan, calc);

        // Store schedule in JSON for quick access (lines 41-42)
        plan.Payment_Schedule_JSON__c = JSON.serialize(scheduleItems);
        plan.Schedule_Item_Count__c = scheduleItems.size();

        // Update the plan with schedule info (line 45)
        Database.update(plan, AccessLevel.USER_MODE);
    }
}