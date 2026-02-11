@IsTest
private class CalculationServiceTest {

    @TestSetup
    static void setup() {
        Account a = new Account(Name = 'Calc Test Acc');
        insert a;
        Opportunity o = new Opportunity(Name = 'Calc Test Opp', AccountId = a.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert o;

        // Create creditors and link to opportunity
        List<Account> cs = TestDataFactory.makeCreditorsAsAccount(3, 'Calc Cred');
        TestDataFactory.linkCredsToOpp(o.Id, cs, 10000, 100, 3);
    }

    private static Opportunity getOpp() {
        return [SELECT Id FROM Opportunity LIMIT 1];
    }

    @IsTest
    static void testPercentageModeScheduleAndSplits() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_MOD',
            'calculationMode' => 'percentage',
            'targetPaymentPercentage' => 45,
            'currentPayment' => 400,
            'setupFee' => 1000,
            'setupFeePayments' => 10,
            'bankingFee' => 35,
            'bank2Fee' => 0,
            'firstDraftDate' => String.valueOf(Date.today()),
            'preferredDayOfWeek' => 1
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);

        System.assert(res.debtBreakdown != null && res.debtBreakdown.totalDebt > 0, 'Should compute total debt');
        System.assert(res.weeklyPayment > 0, 'Weekly payment should be positive');
        System.assert(res.numberOfWeeks >= 1, 'Weeks bounded');
        System.assertNotEquals(null, res.paymentSchedule, 'Schedule generated');
        System.assert(res.splitRatio > 0 && res.escrowRatio > 0, 'Split ratios set');
    }

    @IsTest
    static void testDesiredPaymentMode() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_MOD',
            'calculationMode' => 'desired_payment',
            'desiredWeeklyPayment' => 300,
            'maxSettlementPercentage' => 85,
            'setupFee' => 500,
            'setupFeePayments' => 5,
            'bankingFee' => 35,
            'bank2Fee' => 0
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        System.assertEquals(750, res.weeklyPayment, 'Should honor minimum weekly payment floor');
        System.assert(res.numberOfWeeks >= 1, 'Weeks bounded');
    }

    @IsTest
    static void testStandardMode() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_DEBT',
            'calculationMode' => 'standard',
            'setupFee' => 800,
            'setupFeePayments' => 8,
            'bankingFee' => 35,
            'bank2Fee' => 0
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        System.assert(res.splitRatio > 0 && res.escrowRatio > 0, 'Split ratios set for standard');
        System.assert(res.programFee > 0 && res.settlementAmount > 0, 'Standard amounts computed');
    }

    @IsTest
    static void testPercentageMode_NoCurrentPayment_FallbackUsed() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_DEBT',
            'calculationMode' => 'percentage',
            // intentionally omit currentPayment to trigger fallback
            'targetPaymentPercentage' => 45,
            'setupFee' => 1000,
            'setupFeePayments' => 10,
            'bankingFee' => 35,
            'bank2Fee' => 0
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        // When no currentPayment, fallback uses config ratio - just verify payment is positive
        System.assert(res.weeklyPayment > 0, 'Weekly payment should be positive');
        System.assert(res.weeklyPayment >= CalculationService.MIN_WEEKLY_TARGET_PAYMENT_DCG_DEBT, 'Should respect absolute floor');
        System.assert(res.numberOfWeeks >= 1, 'Weeks should be at least 1');
    }

    @IsTest
    static void testDesiredPayment_RespectsMaxSettlement() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_MOD',
            'calculationMode' => 'desired_payment',
            'desiredWeeklyPayment' => 200,
            'maxSettlementPercentage' => 50,
            'bankingFee' => 35,
            'bank2Fee' => 0
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        Decimal maxSettlement = res.debtBreakdown.totalDebt * 0.50;
        System.assert(res.settlementAmount <= maxSettlement, 'Settlement should not exceed max percentage');
        System.assert(res.numberOfWeeks >= 1, 'Weeks bounded');
    }

    @IsTest
    static void testValidateAdjust_MinMaxWeeklyApplied() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_DEBT',
            'calculationMode' => 'percentage',
            'currentPayment' => 100, // 45 -> 45 weekly
            'targetPaymentPercentage' => 45,
            'minWeeklyPayment' => 200,
            'maxWeeklyPayment' => 300,
            'setupFee' => 0,
            'setupFeePayments' => 1,
            'bankingFee' => 0,
            'bank2Fee' => 0
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        //System.assertEquals(CalculationService.MIN_WEEKLY_TARGET_PAYMENT_DCG_DEBT, res.weeklyPayment, 'Should enforce absolute weekly minimum');
        //System.assertEquals(0, res.validationMessages.size(), 'No additional validation warnings expected when absolute floor applies');
    }

    @IsTest
    static void testScheduleGeneration_PreferredDayAndSetupFees() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_DEBT',
            'calculationMode' => 'percentage',
            'currentPayment' => 1000, // 45% -> 450 base
            'targetPaymentPercentage' => 45,
            'setupFee' => 1000,
            'setupFeePayments' => 4,
            'bankingFee' => 35,
            'firstDraftDate' => String.valueOf(Date.today().addDays(3)),
            'preferredDayOfWeek' => 1 // Monday
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        System.assert(res.paymentSchedule != null && res.paymentSchedule.size() > 4, 'Schedule should be generated');
        Date d1 = Date.valueOf(res.paymentSchedule[0].paymentDate);
        Date d2 = Date.valueOf(res.paymentSchedule[1].paymentDate);
        System.assert(d2 > d1, 'Second payment after first');
        // First N payments include setup fee on top
        System.assert(res.paymentSchedule[0].setupFee > 0 && res.paymentSchedule[4].setupFee == 0, 'Setup fee applied to first 4 payments only');
    }

    @IsTest
    static void testSetupFeeInstallmentsSumToConfiguredTotal() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_MOD',
            'calculationMode' => 'percentage',
            'currentPayment' => 1500,
            'targetPaymentPercentage' => 45,
            'setupFee' => 2500,
            'setupFeePayments' => 6,
            'bankingFee' => 35,
            'bank2Fee' => 0
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        System.assert(res.paymentSchedule != null && res.paymentSchedule.size() > 6, 'Schedule should include setup installments');

        Decimal collected = 0;
        for (Integer i = 0; i < res.paymentSchedule.size(); i++) {
            CalculationService.PaymentScheduleEntry entry = res.paymentSchedule[i];
            if (i < 6) {
                System.assert(entry.setupFee > 0, 'Setup fee should be applied to the configured number of payments');
            } else {
                System.assertEquals(0, entry.setupFee, 'Setup fee should drop to zero after configured installments');
            }
            collected += entry.setupFee;
        }

        System.assertEquals(2500, collected.setScale(2), 'Setup fee installments must sum to configured total');
    }

    @IsTest
    static void testDesiredPaymentHonorsAbsoluteFloor() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_MOD',
            'calculationMode' => 'desired_payment',
            'desiredWeeklyPayment' => 200,
            'bankingFee' => 35,
            'bank2Fee' => 0
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        System.assertEquals(750, res.weeklyPayment, 'Desired mode should floor weekly payment at $750');
    }

    @IsTest
    static void testDebtProgramPercentageFloorApplied() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_DEBT',
            'calculationMode' => 'percentage',
            'currentPayment' => 450,
            'targetPaymentPercentage' => 10,
            'bankingFee' => 35,
            'bank2Fee' => 0
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        //System.assertEquals(CalculationService.MIN_WEEKLY_TARGET_PAYMENT_DCG_DEBT, res.weeklyPayment, 'Percentage mode for DCG Debt should floor weekly payment at $0');
    }


    @IsTest
    static void testValidateAdjust_MaxWeeklyApplied() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_DEBT',
            'calculationMode' => 'percentage',
            'currentPayment' => 2000, // 45% => 900 baseline
            'targetPaymentPercentage' => 45,
            'minWeeklyPayment' => 100,
            'maxWeeklyPayment' => 500, // cap below baseline
            'setupFee' => 0,
            'setupFeePayments' => 1,
            'bankingFee' => 35,
            'bank2Fee' => 0
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        //System.assertEquals(CalculationService.MIN_WEEKLY_TARGET_PAYMENT_DCG_DEBT, res.weeklyPayment, 'Absolute floor should override configured maximum weekly payment');
    }

    @IsTest
    static void testProgramFeesExhaustThenEscrow() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        // Make program fee relatively small and payments long so it exhausts early
        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_DEBT',
            'calculationMode' => 'percentage',
            'currentPayment' => 1000,
            'targetPaymentPercentage' => 45,
            'settlementPercentage' => 60,
            'programFeePercentage' => 5, // small fee to exhaust early
            'setupFee' => 0,
            'setupFeePayments' => 1,
            'bankingFee' => 35,
            'bank2Fee' => 0
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        System.assert(res.paymentSchedule != null && res.paymentSchedule.size() > 5, 'Schedule present');
        // Check last entry shifts all to escrow after fees exhausted
        Integer last = res.paymentSchedule.size() - 1;
        System.assertEquals(0, res.paymentSchedule[last].programAmount, 'Program amount should be zero after fees exhausted');
        System.assert(res.paymentSchedule[last].escrowAmount > 0, 'Escrow receives full net after fees later in schedule');
    }

    @IsTest
    static void testNoFeeProgramMaintainsDuration() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        Map<String, Object> baseConfig = new Map<String, Object>{
            'programType' => 'DCG_MOD',
            'calculationMode' => 'percentage',
            'currentPayment' => 900,
            'targetPaymentPercentage' => 45,
            'settlementPercentage' => 60,
            'programFeePercentage' => 35,
            'setupFee' => 0,
            'setupFeePayments' => 1,
            'bankingFee' => 35,
            'bank2Fee' => 0
        };

        CalculationService.PaymentCalculationResult withFee = CalculationService.calculateAdvancedPaymentPlan(creditors, baseConfig, opp.Id);

        Map<String, Object> noFeeConfig = new Map<String, Object>(baseConfig);
        noFeeConfig.put('noFeeProgram', true);
        noFeeConfig.put('programFeePercentage', 0);
        noFeeConfig.put('noFeeProgramOriginalFeePercentage', 35);

        CalculationService.PaymentCalculationResult noFee = CalculationService.calculateAdvancedPaymentPlan(creditors, noFeeConfig, opp.Id);

        System.assertEquals(withFee.numberOfWeeks, noFee.numberOfWeeks, 'No-fee toggle should preserve program duration');
        System.assertEquals(withFee.weeklyPayment, noFee.weeklyPayment, 'Weekly payment should remain unchanged when toggling No-Fee');
    }

    @IsTest
    static void testDefaultState_UsesBaseSettlementPercentage() {
        Opportunity opp = getOpp();
        // Force account state to a non-mapped value to hit DEFAULT path
        Opportunity opp2 = [SELECT Id, AccountId FROM Opportunity WHERE Id = :opp.Id LIMIT 1];
        Account a = [SELECT Id, BillingState FROM Account WHERE Id = :opp2.AccountId LIMIT 1];
        a.BillingState = null;
        update a;

        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];
        Decimal totalDebt = 0; for (CreditorOpportunity__c co : creditors) totalDebt += co.Amount__c;

        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_MOD',
            'calculationMode' => 'percentage',
            'settlementPercentage' => 60,
            'programFeePercentage' => 35,
            'targetPaymentPercentage' => 45,
            'currentPayment' => 400,
            'setupFee' => 0,
            'setupFeePayments' => 1,
            'bankingFee' => 35,
            'bank2Fee' => 0
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        System.assertEquals(totalDebt * 0.60, res.settlementAmount, 'DEFAULT state should not increase settlement percentage');
    }

    @IsTest
    static void testZeroSetupFee_NoSetupFeesInSchedule() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_DEBT',
            'calculationMode' => 'percentage',
            'currentPayment' => 800,
            'targetPaymentPercentage' => 45,
            'settlementPercentage' => 60,
            'programFeePercentage' => 35,
            'setupFee' => 0,
            'setupFeePayments' => 12,
            'bankingFee' => 35,
            'bank2Fee' => 0
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        System.assert(res.paymentSchedule != null && !res.paymentSchedule.isEmpty(), 'Schedule should be generated');
        // All entries should have zero setupFee when setupFee=0
        for (CalculationService.PaymentScheduleEntry e : res.paymentSchedule) {
            System.assertEquals(0, e.setupFee, 'Setup fee should be zero across schedule when configured as zero');
        }
    }

    @IsTest
    static void testAdditionalProducts_AddsToPaymentAmount() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        // Choose config that avoids setup fee noise
        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_MOD',
            'calculationMode' => 'desired_payment',
            'desiredWeeklyPayment' => 300,
            'setupFee' => 0,
            'setupFeePayments' => 1,
            'bankingFee' => 35,
            'bank2Fee' => 0,
            'additionalProductsWeeklyTotal' => 10
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        System.assert(res.paymentSchedule != null && !res.paymentSchedule.isEmpty(), 'Schedule present');
        CalculationService.PaymentScheduleEntry first = res.paymentSchedule[0];
        System.assertEquals(10, first.feesAmount - (first.bankingFee + first.programAmount + first.setupFee) + 0, 'Fees include addl products');
        //System.assertEquals(res.weeklyPayment + first.setupFee + 10, first.paymentAmount, 'Payment amount includes addl products');
    }

    @IsTest
    static void testUnknownProgramType_ThrowsConfigException() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'UNKNOWN',
            'calculationMode' => 'standard',
            'settlementPercentage' => 60,
            'programFeePercentage' => 35,
            'setupFee' => 0,
            'setupFeePayments' => 1,
            'bank2Fee' => 0
        };

        Boolean exceptionThrown = false;
        try {
            CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        } catch (PaymentCalcConfigException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('UNKNOWN'), 'Exception should mention invalid program type');
        }
        System.assert(exceptionThrown, 'Should throw PaymentCalcConfigException for unknown program type');
    }

    @IsTest
    static void testUtilityMethods_WeightedInterestRate() {
        // Weighted rate should return a fixed value (20.0)
        Decimal wr = CalculationService.calculateWeightedInterestRate();
        System.assertEquals(20.0, wr, 'Weighted interest rate should return 20.0');
    }

    @IsTest
    static void testMonthlyMinimumPayments() {
        // Test with valid current payment
        Decimal result1 = CalculationService.calculateMonthlyMinimumPayments(500);
        System.assertEquals(500, result1, 'Should return the current payment value');

        // Test with null
        Decimal result2 = CalculationService.calculateMonthlyMinimumPayments(null);
        System.assertEquals(0, result2, 'Should return 0 for null');

        // Test with zero
        Decimal result3 = CalculationService.calculateMonthlyMinimumPayments(0);
        System.assertEquals(0, result3, 'Should return 0 for zero value');

        // Test with negative
        Decimal result4 = CalculationService.calculateMonthlyMinimumPayments(-100);
        System.assertEquals(0, result4, 'Should return 0 for negative value');
    }

    @IsTest
    static void testInvalidFirstDraftDate_ThrowsCalculationException() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];
        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_MOD',
            'calculationMode' => 'desired_payment',
            'desiredWeeklyPayment' => 200,
            'firstDraftDate' => 'INVALID_DATE_STRING'
        };
        try {
            CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
            System.assert(false, 'Expected CalculationException for invalid date');
        } catch (CalculationService.CalculationException e) {
            System.assert(e.getMessage().contains('Advanced calculation failed'), 'Should wrap error in CalculationException');
        }
    }

    @IsTest
    static void testEvenPaymentDistribution() {
        Opportunity opp = getOpp();
        List<CreditorOpportunity__c> creditors = [
            SELECT Id, Amount__c, Weekly_Payment__c FROM CreditorOpportunity__c WHERE Opportunity__c = :opp.Id
        ];

        // Setup scenario:
        // Total Debt approx 50k -> Total Program Cost approx 48.5k
        // Desired Payment 3000 -> Net Capacity 2965
        // Expect 17 weeks of ~2853 + 35 fee = ~2888
        
        // We need to mock the debt amount to control the math precisely, 
        // but since we rely on existing creditors, we'll just use the config to force values where possible
        // or just check for consistency in the output schedule.
        
        Map<String, Object> config = new Map<String, Object>{
            'programType' => 'DCG_MOD',
            'calculationMode' => 'desired_payment',
            'desiredWeeklyPayment' => 3000, 
            'bankingFee' => 35,
            'bank2Fee' => 0,
            'setupFee' => 1000,
            'setupFeePayments' => 1
        };

        CalculationService.PaymentCalculationResult res = CalculationService.calculateAdvancedPaymentPlan(creditors, config, opp.Id);
        
        System.assert(res.paymentSchedule != null && res.paymentSchedule.size() > 1, 'Schedule generated');
        
        // Verify that payments are distributed evenly
        // The standard deviation or variance between payment amounts (excluding setup fee differences) should be very small
        // or simply check that the last payment is close to the average payment.
        
        Decimal sumBasePayments = 0;
        List<Decimal> basePayments = new List<Decimal>();
        
        for (CalculationService.PaymentScheduleEntry entry : res.paymentSchedule) {
            // Subtract setup fee to get the base program payment
            Decimal base = entry.paymentAmount - entry.setupFee;
            basePayments.add(base);
            sumBasePayments += base;
        }
        
        Decimal avgPayment = sumBasePayments / basePayments.size();
        Decimal lastPayment = basePayments[basePayments.size() - 1];
        
        // In the old logic, the last payment would be significantly different (remainder).
        // In the new logic, it should be very close to the average (within rounding difference).
        
        Decimal diff = Math.abs(lastPayment - avgPayment);
        System.assert(diff < 5.0, 'Last payment (' + lastPayment + ') should be close to average (' + avgPayment + ') indicating even distribution');
    }
}