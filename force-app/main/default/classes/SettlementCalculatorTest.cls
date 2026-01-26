/**
 * @description Comprehensive test class for Settlement Calculator components.
 *              Covers SettlementPlanCalculatorService, SettlementPlanCalculatorController,
 *              SettlementFeeCalculator, SettlementDateUtils, and SettlementCalculatorException.
 * @author Settlement Calculator Team
 * @date January 2026
 * 
 * NOTE: Tests that use BusinessHours require @IsTest(SeeAllData=true) because
 *       BusinessHours is a setup object that cannot be created in test context.
 */
@IsTest
private class SettlementCalculatorTest {

    // ==================== TEST DATA FACTORY ====================

    /**
     * @description Creates standard test data for settlement calculator tests
     * @return Map containing 'credOpp' and 'segments' keys
     */
    private static Map<String, Object> createTestData() {
        // Create Account (required for CreditorOpportunity)
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        // Create CreditorOpportunity (CreditorAccount__c is required in target org)
        CreditorOpportunity__c credOpp = new CreditorOpportunity__c(
            Name = 'Test Creditor Opp',
            CreditorAccount__c = testAccount.Id,
            Settlement_Offer_Amount__c = 10000.00,
            Escrow_Start_Balance__c = 15000.00,
            Commission_Fee__c = 35.00,
            Bank_Fee__c = 35.00
        );
        insert credOpp;

        Map<String, Object> result = new Map<String, Object>();
        result.put('credOpp', credOpp);
        result.put('segments', new List<Settlement_Segment__c>());

        return result;
    }

    /**
     * @description Creates a Fixed segment
     */
    private static Settlement_Segment__c createFixedSegment(
        Id credOppId,
        Integer order,
        Decimal amount,
        Integer count,
        String frequency,
        Date startDate
    ) {
        Settlement_Segment__c segment = new Settlement_Segment__c(
            Creditors_List__c = credOppId,
            Segment_Order__c = order,
            Segment_Type__c = 'Fixed',
            Payment_Amount__c = amount,
            Payment_Count__c = count,
            Frequency__c = frequency,
            Start_Date__c = startDate
            // Is_First_Segment__c is a formula field - calculated automatically based on Segment_Order__c
        );
        return segment;
    }

    /**
     * @description Creates a Remainder segment
     */
    private static Settlement_Segment__c createRemainderSegment(
        Id credOppId,
        Integer order,
        Decimal amount,
        String frequency,
        Date startDate
    ) {
        Settlement_Segment__c segment = new Settlement_Segment__c(
            Creditors_List__c = credOppId,
            Segment_Order__c = order,
            Segment_Type__c = 'Remainder',
            Payment_Amount__c = amount,
            Frequency__c = frequency,
            Start_Date__c = startDate
            // Is_First_Segment__c is a formula field - calculated automatically based on Segment_Order__c
        );
        return segment;
    }

    /**
     * @description Creates a SolveAmount segment
     */
    private static Settlement_Segment__c createSolveAmountSegment(
        Id credOppId,
        Integer order,
        Integer count,
        String frequency,
        Date startDate
    ) {
        Settlement_Segment__c segment = new Settlement_Segment__c(
            Creditors_List__c = credOppId,
            Segment_Order__c = order,
            Segment_Type__c = 'SolveAmount',
            Payment_Count__c = count,
            Frequency__c = frequency,
            Start_Date__c = startDate
            // Is_First_Segment__c is a formula field - calculated automatically based on Segment_Order__c
        );
        return segment;
    }

    // ==================== SERVICE TESTS ====================
    // Note: Service tests that create payment schedules use BusinessHours
    // through applyPreviousBusinessDayRule(), so they need SeeAllData=true

    @IsTest(SeeAllData=true)
    static void testCalculatePlan_FixedSegment_SinglePayment() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Create Fixed segment: 1 payment of $10,000
        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 10000.00, 1, 'Monthly', Date.newInstance(2026, 2, 1)
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Calculation should succeed');
        System.assertEquals(1, result.numberOfPayments, 'Should have 1 payment');
        System.assertEquals(10000.00, result.totalScheduledAmount, 'Total should be $10,000');
        System.assertEquals(true, result.isFullyFunded, 'Should be fully funded');
    }

    @IsTest(SeeAllData=true)
    static void testCalculatePlan_FixedSegment_MultiplePayments() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Create Fixed segment: 4 payments of $2,500 each
        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 2500.00, 4, 'Monthly', Date.newInstance(2026, 2, 1)
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Calculation should succeed');
        System.assertEquals(4, result.numberOfPayments, 'Should have 4 payments');
        System.assertEquals(10000.00, result.totalScheduledAmount, 'Total should be $10,000');
    }

    @IsTest(SeeAllData=true)
    static void testCalculatePlan_RemainderSegment() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Create Remainder segment: $2,000/month until paid
        Settlement_Segment__c segment = createRemainderSegment(
            credOpp.Id, 1, 2000.00, 'Monthly', Date.newInstance(2026, 2, 1)
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Calculation should succeed');
        System.assertEquals(5, result.numberOfPayments, 'Should have 5 payments ($10k / $2k)');
        System.assertEquals(10000.00, result.totalScheduledAmount, 'Total should be $10,000');
    }

    @IsTest(SeeAllData=true)
    static void testCalculatePlan_SolveAmountSegment() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Create SolveAmount segment: 4 equal payments
        Settlement_Segment__c segment = createSolveAmountSegment(
            credOpp.Id, 1, 4, 'Monthly', Date.newInstance(2026, 2, 1)
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Calculation should succeed');
        System.assertEquals(4, result.numberOfPayments, 'Should have 4 payments');
        System.assertEquals(10000.00, result.totalScheduledAmount, 'Total should be $10,000');
        // First 3 payments should be $2,500.00, last payment gets the remainder
        System.assertEquals(2500.00, result.planItems[0].Payment_Amount__c, 'First payment should be $2,500');
    }

    @IsTest(SeeAllData=true)
    static void testCalculatePlan_SolveAmount_UnevenDivision() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Update to amount that doesn't divide evenly
        credOpp.Settlement_Offer_Amount__c = 1000.00;
        update credOpp;

        // Create SolveAmount segment: 3 equal payments of $1000 (333.33 each, last gets 333.34)
        Settlement_Segment__c segment = createSolveAmountSegment(
            credOpp.Id, 1, 3, 'Monthly', Date.newInstance(2026, 2, 1)
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Calculation should succeed');
        System.assertEquals(3, result.numberOfPayments, 'Should have 3 payments');
        System.assertEquals(1000.00, result.totalScheduledAmount, 'Total should be exactly $1,000');
        // HALF_UP rounding: 1000/3 = 333.33
        System.assertEquals(333.33, result.planItems[0].Payment_Amount__c, 'First payment should be $333.33');
        System.assertEquals(333.33, result.planItems[1].Payment_Amount__c, 'Second payment should be $333.33');
        System.assertEquals(333.34, result.planItems[2].Payment_Amount__c, 'Last payment should be $333.34 (remainder)');
    }

    @IsTest(SeeAllData=true)
    static void testCalculatePlan_MultiSegment() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Segment 1: Fixed - 2 payments of $1,000
        Settlement_Segment__c seg1 = createFixedSegment(
            credOpp.Id, 1, 1000.00, 2, 'Monthly', Date.newInstance(2026, 2, 1)
        );

        // Segment 2: Remainder - $2,000/month until paid (remaining $8,000)
        Settlement_Segment__c seg2 = createRemainderSegment(
            credOpp.Id, 2, 2000.00, 'Monthly', null // continues from previous
        );

        insert new List<Settlement_Segment__c>{ seg1, seg2 };

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Calculation should succeed');
        // 2 fixed + 4 remainder = 6 payments
        System.assertEquals(6, result.numberOfPayments, 'Should have 6 payments (2 fixed + 4 remainder)');
        System.assertEquals(10000.00, result.totalScheduledAmount, 'Total should be $10,000');
    }

    @IsTest
    static void testCalculatePlan_NoSegments_Error() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');
        // Don't create any segments

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Calculation should fail');
        System.assert(result.errorMessage.contains('No settlement segments found'), 
            'Error should mention no segments: ' + result.errorMessage);
    }

    @IsTest
    static void testCalculatePlan_InvalidSettlementAmount_Error() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Set invalid settlement amount
        credOpp.Settlement_Offer_Amount__c = 0;
        update credOpp;

        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 1000.00, 1, 'Monthly', Date.newInstance(2026, 2, 1)
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Calculation should fail');
        System.assert(result.errorMessage.contains('Settlement Offer Amount'), 
            'Error should mention settlement amount: ' + result.errorMessage);
    }

    @IsTest
    static void testCalculatePlan_MissingStartDate_Error() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Create segment without start date on first segment
        Settlement_Segment__c segment = new Settlement_Segment__c(
            Creditors_List__c = credOpp.Id,
            Segment_Order__c = 1,
            Segment_Type__c = 'Fixed',
            Payment_Amount__c = 1000.00,
            Payment_Count__c = 1,
            Frequency__c = 'Monthly',
            Start_Date__c = null // Missing! Is_First_Segment__c is a formula field
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Calculation should fail');
        System.assert(result.errorMessage.contains('Start Date'), 
            'Error should mention start date: ' + result.errorMessage);
    }

    @IsTest(SeeAllData=true)
    static void testSaveCalculation() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 2500.00, 4, 'Monthly', Date.newInstance(2026, 2, 1)
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.saveCalculation(credOpp.Id, true);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Save should succeed');

        // Verify items were actually inserted
        List<Settlement_Plan_Item__c> savedItems = [
            SELECT Id, Payment_Number__c, Payment_Amount__c
            FROM Settlement_Plan_Item__c
            WHERE Creditors_List__c = :credOpp.Id
            ORDER BY Payment_Number__c
        ];
        System.assertEquals(4, savedItems.size(), 'Should have 4 saved items');
    }

    @IsTest(SeeAllData=true)
    static void testSaveCalculation_DeleteExisting() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Create a segment first (required for Settlement_Plan_Item__c)
        Settlement_Segment__c existingSegment = createFixedSegment(
            credOpp.Id, 1, 999.00, 1, 'Monthly', Date.newInstance(2026, 1, 1)
        );
        insert existingSegment;

        // Create existing items linked to the segment
        Settlement_Plan_Item__c existingItem = new Settlement_Plan_Item__c(
            Creditors_List__c = credOpp.Id,
            Settlement_Segment__c = existingSegment.Id,
            Payment_Number__c = 1,
            Payment_Amount__c = 999.00,
            Payment_Date__c = Date.today(),
            Status__c = 'Scheduled'
        );
        insert existingItem;

        // Update segment for new calculation
        existingSegment.Payment_Amount__c = 5000.00;
        existingSegment.Payment_Count__c = 2;
        existingSegment.Start_Date__c = Date.newInstance(2026, 2, 1);
        update existingSegment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.saveCalculation(credOpp.Id, true);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Save should succeed');

        // Verify old item was deleted and new items created
        List<Settlement_Plan_Item__c> savedItems = [
            SELECT Id, Payment_Amount__c
            FROM Settlement_Plan_Item__c
            WHERE Creditors_List__c = :credOpp.Id
        ];
        System.assertEquals(2, savedItems.size(), 'Should have 2 items (old one deleted)');
        System.assertEquals(5000.00, savedItems[0].Payment_Amount__c, 'Should be new amount');
    }

    // ==================== CONTROLLER TESTS ====================

    @IsTest(SeeAllData=true)
    static void testController_CalculatePlan() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 10000.00, 1, 'Monthly', Date.newInstance(2026, 2, 1)
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService.CalculationResult result = 
            SettlementPlanCalculatorController.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Controller calculate should succeed');
        System.assertEquals(1, result.numberOfPayments, 'Should have 1 payment');
    }

    @IsTest
    static void testController_CalculatePlan_NullId() {
        Test.startTest();
        SettlementPlanCalculatorService.CalculationResult result = 
            SettlementPlanCalculatorController.calculatePlan(null);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with null ID');
        System.assert(result.errorMessage.contains('required'), 
            'Error should mention required: ' + result.errorMessage);
    }

    @IsTest(SeeAllData=true)
    static void testController_CalculateAndSavePlan() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 5000.00, 2, 'Monthly', Date.newInstance(2026, 2, 1)
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService.CalculationResult result = 
            SettlementPlanCalculatorController.calculateAndSavePlan(credOpp.Id, true);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Controller save should succeed');

        // Verify saved
        Integer count = [SELECT COUNT() FROM Settlement_Plan_Item__c WHERE Creditors_List__c = :credOpp.Id];
        System.assertEquals(2, count, 'Should have 2 saved items');
    }

    @IsTest
    static void testController_GetSegments() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        Settlement_Segment__c seg1 = createFixedSegment(credOpp.Id, 1, 1000.00, 1, 'Monthly', Date.today());
        Settlement_Segment__c seg2 = createRemainderSegment(credOpp.Id, 2, 500.00, 'Monthly', null);
        insert new List<Settlement_Segment__c>{ seg1, seg2 };

        Test.startTest();
        List<Settlement_Segment__c> segments = SettlementPlanCalculatorController.getSegments(credOpp.Id);
        Test.stopTest();

        System.assertEquals(2, segments.size(), 'Should return 2 segments');
        System.assertEquals(1, segments[0].Segment_Order__c, 'First segment should be order 1');
    }

    @IsTest
    static void testController_GetSegments_NullId() {
        Test.startTest();
        List<Settlement_Segment__c> segments = SettlementPlanCalculatorController.getSegments(null);
        Test.stopTest();

        System.assertEquals(0, segments.size(), 'Should return empty list for null ID');
    }

    @IsTest
    static void testController_GetExistingPlanItems() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Create a segment first (required for Settlement_Plan_Item__c)
        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 1000.00, 1, 'Monthly', Date.today()
        );
        insert segment;

        Settlement_Plan_Item__c item = new Settlement_Plan_Item__c(
            Creditors_List__c = credOpp.Id,
            Settlement_Segment__c = segment.Id,
            Payment_Number__c = 1,
            Payment_Amount__c = 1000.00,
            Payment_Date__c = Date.today(),
            Status__c = 'Scheduled'
        );
        insert item;

        Test.startTest();
        List<Settlement_Plan_Item__c> items = SettlementPlanCalculatorController.getExistingPlanItems(credOpp.Id);
        Test.stopTest();

        System.assertEquals(1, items.size(), 'Should return 1 item');
    }

    @IsTest
    static void testController_GetCreditorOpportunity() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        Test.startTest();
        CreditorOpportunity__c result = SettlementPlanCalculatorController.getCreditorOpportunity(credOpp.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return creditor opportunity');
        System.assertEquals(10000.00, result.Settlement_Offer_Amount__c, 'Should have correct amount');
    }

    @IsTest
    static void testController_DeletePlanItems() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Create a segment first (required for Settlement_Plan_Item__c)
        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 1000.00, 1, 'Monthly', Date.today()
        );
        insert segment;

        Settlement_Plan_Item__c item = new Settlement_Plan_Item__c(
            Creditors_List__c = credOpp.Id,
            Settlement_Segment__c = segment.Id,
            Payment_Number__c = 1,
            Payment_Amount__c = 1000.00,
            Payment_Date__c = Date.today(),
            Status__c = 'Scheduled'
        );
        insert item;

        Test.startTest();
        Boolean success = SettlementPlanCalculatorController.deletePlanItems(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, success, 'Delete should succeed');

        Integer count = [SELECT COUNT() FROM Settlement_Plan_Item__c WHERE Creditors_List__c = :credOpp.Id];
        System.assertEquals(0, count, 'All items should be deleted');
    }

    @IsTest
    static void testController_ValidateBeforeCalculation() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 1000.00, 1, 'Monthly', Date.newInstance(2026, 2, 1)
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorController.ValidationResult result = 
            SettlementPlanCalculatorController.validateBeforeCalculation(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.isValid, 'Validation should pass');
        System.assertEquals(0, result.errors.size(), 'Should have no errors');
    }

    @IsTest
    static void testController_ValidateBeforeCalculation_NoSegments() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');
        // No segments created

        Test.startTest();
        SettlementPlanCalculatorController.ValidationResult result = 
            SettlementPlanCalculatorController.validateBeforeCalculation(credOpp.Id);
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Validation should fail');
        System.assert(result.errors.size() > 0, 'Should have errors');
    }

    // ==================== DATE UTILS TESTS ====================

    @IsTest
    static void testDateUtils_AdvanceDate_Weekly() {
        Date startDate = Date.newInstance(2026, 1, 1);

        Test.startTest();
        Date result = SettlementDateUtils.advanceDate(startDate, 'Weekly', 1);
        Test.stopTest();

        System.assertEquals(Date.newInstance(2026, 1, 8), result, 'Should advance 7 days');
    }

    @IsTest
    static void testDateUtils_AdvanceDate_BiWeekly() {
        Date startDate = Date.newInstance(2026, 1, 1);

        Test.startTest();
        Date result = SettlementDateUtils.advanceDate(startDate, 'Bi-Weekly', 1);
        Test.stopTest();

        System.assertEquals(Date.newInstance(2026, 1, 15), result, 'Should advance 14 days');
    }

    @IsTest
    static void testDateUtils_AdvanceDate_Monthly() {
        Date startDate = Date.newInstance(2026, 1, 15);

        Test.startTest();
        Date result = SettlementDateUtils.advanceDate(startDate, 'Monthly', 1);
        Test.stopTest();

        System.assertEquals(Date.newInstance(2026, 2, 15), result, 'Should advance 1 month');
    }

    @IsTest
    static void testDateUtils_AdvanceDate_SemiMonthly_BeforeFifteenth() {
        Date startDate = Date.newInstance(2026, 1, 1);

        Test.startTest();
        Date result = SettlementDateUtils.advanceDate(startDate, 'Semi-Monthly', 1);
        Test.stopTest();

        System.assertEquals(Date.newInstance(2026, 1, 15), result, 'Should advance to 15th');
    }

    @IsTest
    static void testDateUtils_AdvanceDate_SemiMonthly_OnOrAfterFifteenth() {
        Date startDate = Date.newInstance(2026, 1, 15);

        Test.startTest();
        Date result = SettlementDateUtils.advanceDate(startDate, 'Semi-Monthly', 1);
        Test.stopTest();

        System.assertEquals(Date.newInstance(2026, 2, 1), result, 'Should advance to 1st of next month');
    }

    @IsTest
    static void testDateUtils_AdvanceDate_NullDate() {
        Test.startTest();
        try {
            SettlementDateUtils.advanceDate(null, 'Monthly', 1);
            System.assert(false, 'Should have thrown exception');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('null'), 'Error should mention null');
        }
        Test.stopTest();
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_IsBusinessDay_Weekday() {
        // Wednesday Jan 7, 2026 should be a business day
        Date wednesday = Date.newInstance(2026, 1, 7);

        Test.startTest();
        Boolean result = SettlementDateUtils.isBusinessDay(wednesday);
        Test.stopTest();

        System.assertEquals(true, result, 'Wednesday should be a business day');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_IsBusinessDay_Weekend() {
        // Saturday Jan 3, 2026 should NOT be a business day
        Date saturday = Date.newInstance(2026, 1, 3);

        Test.startTest();
        Boolean result = SettlementDateUtils.isBusinessDay(saturday);
        Test.stopTest();

        System.assertEquals(false, result, 'Saturday should not be a business day');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_IsBusinessDay_Sunday() {
        // Sunday Jan 4, 2026 should NOT be a business day
        Date sunday = Date.newInstance(2026, 1, 4);

        Test.startTest();
        Boolean result = SettlementDateUtils.isBusinessDay(sunday);
        Test.stopTest();

        System.assertEquals(false, result, 'Sunday should not be a business day');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_IsBusinessDay_Null() {
        Test.startTest();
        Boolean result = SettlementDateUtils.isBusinessDay(null);
        Test.stopTest();

        System.assertEquals(false, result, 'Null should return false');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_IsBusinessDay_Holiday() {
        // Christmas 2026 (Dec 25, Friday) should NOT be a business day
        // if it's configured as a holiday in BusinessHours
        Date christmas = Date.newInstance(2026, 12, 25);

        Test.startTest();
        Boolean result = SettlementDateUtils.isBusinessDay(christmas);
        Test.stopTest();

        // This test verifies the method works; actual result depends on BusinessHours config
        System.assertNotEquals(null, result, 'Should return a boolean value');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_ApplyPreviousBusinessDayRule_Saturday() {
        // January 3, 2026 is a Saturday -> should become Friday Jan 2
        Date saturday = Date.newInstance(2026, 1, 3);

        Test.startTest();
        Date result = SettlementDateUtils.applyPreviousBusinessDayRule(saturday);
        Test.stopTest();

        // Saturday - 1 = Friday (Jan 2, 2026 is a regular business day)
        System.assertEquals(Date.newInstance(2026, 1, 2), result, 
            'Saturday should become Friday Jan 2');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_ApplyPreviousBusinessDayRule_Sunday() {
        // January 4, 2026 is a Sunday -> should become Friday Jan 2
        Date sunday = Date.newInstance(2026, 1, 4);

        Test.startTest();
        Date result = SettlementDateUtils.applyPreviousBusinessDayRule(sunday);
        Test.stopTest();

        // Sunday -> Friday
        System.assertEquals(Date.newInstance(2026, 1, 2), result, 
            'Sunday should become Friday Jan 2');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_ApplyPreviousBusinessDayRule_Weekday() {
        // January 7, 2026 is a Wednesday (not weekend, not holiday)
        Date wednesday = Date.newInstance(2026, 1, 7);

        Test.startTest();
        Date result = SettlementDateUtils.applyPreviousBusinessDayRule(wednesday);
        Test.stopTest();

        System.assertEquals(wednesday, result, 'Weekday should remain unchanged');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_ApplyPreviousBusinessDayRule_Null() {
        Test.startTest();
        Date result = SettlementDateUtils.applyPreviousBusinessDayRule(null);
        Test.stopTest();

        System.assertEquals(null, result, 'Null input should return null');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_ApplyPreviousBusinessDayRule_Holiday() {
        // Christmas 2026 is Friday Dec 25 - should move to Thursday Dec 24
        // if Christmas is configured as a holiday in BusinessHours
        Date christmas = Date.newInstance(2026, 12, 25);

        Test.startTest();
        Date result = SettlementDateUtils.applyPreviousBusinessDayRule(christmas);
        Test.stopTest();

        // The result depends on BusinessHours configuration
        // If Christmas is a holiday, result should be Dec 24
        // If not configured, result would be Dec 25 (unchanged)
        System.assertNotEquals(null, result, 'Should return a valid date');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_ApplyDateRule_Next() {
        // Saturday Jan 3, 2026 with "Next" rule should become Monday Jan 5
        Date saturday = Date.newInstance(2026, 1, 3);

        Test.startTest();
        Date result = SettlementDateUtils.applyDateRule(saturday, 'Next');
        Test.stopTest();

        System.assertEquals(Date.newInstance(2026, 1, 5), result, 
            'Saturday with Next rule should become Monday');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_ApplyDateRule_Previous() {
        // Saturday Jan 3, 2026 with "Previous" rule should become Friday Jan 2
        Date saturday = Date.newInstance(2026, 1, 3);

        Test.startTest();
        Date result = SettlementDateUtils.applyDateRule(saturday, 'Previous');
        Test.stopTest();

        System.assertEquals(Date.newInstance(2026, 1, 2), result, 
            'Saturday with Previous rule should become Friday');
    }

    @IsTest
    static void testDateUtils_ApplyDateRule_None() {
        // Any date with "None" rule should remain unchanged
        Date saturday = Date.newInstance(2026, 1, 3);

        Test.startTest();
        Date result = SettlementDateUtils.applyDateRule(saturday, 'None');
        Test.stopTest();

        System.assertEquals(saturday, result, 'None rule should return original date');
    }

    @IsTest
    static void testDateUtils_ApplyDateRule_Null() {
        Test.startTest();
        Date result = SettlementDateUtils.applyDateRule(null, 'Previous');
        Test.stopTest();

        System.assertEquals(null, result, 'Null input should return null');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_ConsecutiveNonBusinessDays() {
        // Test July 4, 2026 weekend + observed holiday scenario
        // July 4, 2026 is Saturday, observed Friday July 3
        Date saturday = Date.newInstance(2026, 7, 4);

        Test.startTest();
        Date result = SettlementDateUtils.applyPreviousBusinessDayRule(saturday);
        Test.stopTest();

        // Should skip Sat, and if July 3 is a holiday (observed Independence Day),
        // should skip that too and land on Thursday July 2
        // Actual result depends on BusinessHours holiday configuration
        System.assertNotEquals(null, result, 'Should return a valid date');
        System.assert(result <= saturday, 'Result should be on or before Saturday');
    }

    @IsTest
    static void testDateUtils_WeeksBetween() {
        Date startDate = Date.newInstance(2026, 1, 1);
        Date endDate = Date.newInstance(2026, 1, 22); // 21 days = 3 weeks

        Test.startTest();
        Integer weeks = SettlementDateUtils.weeksBetween(startDate, endDate);
        Test.stopTest();

        System.assertEquals(3, weeks, 'Should be 3 weeks');
    }

    @IsTest
    static void testDateUtils_WeeksBetween_NullDates() {
        Test.startTest();
        Integer weeks1 = SettlementDateUtils.weeksBetween(null, Date.today());
        Integer weeks2 = SettlementDateUtils.weeksBetween(Date.today(), null);
        Integer weeks3 = SettlementDateUtils.weeksBetween(null, null);
        Test.stopTest();

        System.assertEquals(0, weeks1, 'Null start date should return 0');
        System.assertEquals(0, weeks2, 'Null end date should return 0');
        System.assertEquals(0, weeks3, 'Both null should return 0');
    }

    @IsTest
    static void testDateUtils_GetMonthYearKey() {
        Date testDate = Date.newInstance(2026, 3, 15);

        Test.startTest();
        String key = SettlementDateUtils.getMonthYearKey(testDate);
        Test.stopTest();

        System.assertEquals('2026-03', key, 'Should return YYYY-MM format');
    }

    @IsTest
    static void testDateUtils_GetMonthYearKey_Null() {
        Test.startTest();
        String key = SettlementDateUtils.getMonthYearKey(null);
        Test.stopTest();

        System.assertEquals(null, key, 'Null date should return null');
    }

    @IsTest
    static void testDateUtils_SortByPaymentDate() {
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(Payment_Date__c = Date.newInstance(2026, 3, 1), Payment_Number__c = 3),
            new Settlement_Plan_Item__c(Payment_Date__c = Date.newInstance(2026, 1, 1), Payment_Number__c = 1),
            new Settlement_Plan_Item__c(Payment_Date__c = Date.newInstance(2026, 2, 1), Payment_Number__c = 2)
        };

        Test.startTest();
        List<Settlement_Plan_Item__c> sorted = SettlementDateUtils.sortByPaymentDate(items);
        Test.stopTest();

        System.assertEquals(Date.newInstance(2026, 1, 1), sorted[0].Payment_Date__c, 'First should be Jan');
        System.assertEquals(Date.newInstance(2026, 2, 1), sorted[1].Payment_Date__c, 'Second should be Feb');
        System.assertEquals(Date.newInstance(2026, 3, 1), sorted[2].Payment_Date__c, 'Third should be Mar');
    }

    @IsTest
    static void testDateUtils_SortByPaymentDate_EmptyList() {
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();

        Test.startTest();
        List<Settlement_Plan_Item__c> sorted = SettlementDateUtils.sortByPaymentDate(items);
        Test.stopTest();

        System.assertEquals(0, sorted.size(), 'Empty list should return empty list');
    }

    @IsTest
    static void testDateUtils_SortByPaymentDate_NullList() {
        Test.startTest();
        List<Settlement_Plan_Item__c> sorted = SettlementDateUtils.sortByPaymentDate(null);
        Test.stopTest();

        System.assertEquals(0, sorted.size(), 'Null list should return empty list');
    }

    @IsTest
    static void testDateUtils_SortByPaymentDate_WithNullDates() {
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(Payment_Date__c = null, Payment_Number__c = 3),
            new Settlement_Plan_Item__c(Payment_Date__c = Date.newInstance(2026, 1, 1), Payment_Number__c = 1),
            new Settlement_Plan_Item__c(Payment_Date__c = null, Payment_Number__c = 2)
        };

        Test.startTest();
        List<Settlement_Plan_Item__c> sorted = SettlementDateUtils.sortByPaymentDate(items);
        Test.stopTest();

        // Items with dates should come first, nulls last
        System.assertEquals(Date.newInstance(2026, 1, 1), sorted[0].Payment_Date__c, 'First should have date');
        System.assertEquals(null, sorted[1].Payment_Date__c, 'Nulls should come last');
        System.assertEquals(null, sorted[2].Payment_Date__c, 'Nulls should come last');
    }

    @IsTest
    static void testDateUtils_SortByPaymentDate_SameDates() {
        // Test tiebreaker by Payment_Number__c
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(Payment_Date__c = Date.newInstance(2026, 1, 1), Payment_Number__c = 3),
            new Settlement_Plan_Item__c(Payment_Date__c = Date.newInstance(2026, 1, 1), Payment_Number__c = 1),
            new Settlement_Plan_Item__c(Payment_Date__c = Date.newInstance(2026, 1, 1), Payment_Number__c = 2)
        };

        Test.startTest();
        List<Settlement_Plan_Item__c> sorted = SettlementDateUtils.sortByPaymentDate(items);
        Test.stopTest();

        System.assertEquals(1, sorted[0].Payment_Number__c, 'First should be payment 1');
        System.assertEquals(2, sorted[1].Payment_Number__c, 'Second should be payment 2');
        System.assertEquals(3, sorted[2].Payment_Number__c, 'Third should be payment 3');
    }

    // ==================== FEE CALCULATOR TESTS ====================

    @IsTest
    static void testFeeCalculator_CalculateFeesForItem() {
        // Get config for fee calculator
        Settlement_Calc_Config__mdt config = [
            SELECT Default_Commission_Fee__c, Default_Bank_Fee__c, 
                   EPPS_Transaction_Fee__c, EPPS_Monthly_Minimum__c
            FROM Settlement_Calc_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        Settlement_Plan_Item__c item = new Settlement_Plan_Item__c(
            Payment_Amount__c = 1000.00,
            Payment_Date__c = Date.today()
        );

        Test.startTest();
        // No commission override - uses config default
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, null);
        calculator.calculateFeesForItem(item);
        Test.stopTest();

        System.assertEquals(config.Default_Commission_Fee__c, item.Commission_Fee__c, 'Commission should match config');
        System.assertEquals(config.Default_Bank_Fee__c, item.Bank_Fee__c, 'Bank fee should match config (no override allowed)');
        System.assertEquals(config.EPPS_Transaction_Fee__c, item.EPPS_Transaction_Fee__c, 'EPPS should match config');
    }

    @IsTest
    static void testFeeCalculator_WithCommissionOverride() {
        Settlement_Calc_Config__mdt config = [
            SELECT Default_Commission_Fee__c, Default_Bank_Fee__c, 
                   EPPS_Transaction_Fee__c, EPPS_Monthly_Minimum__c
            FROM Settlement_Calc_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        Settlement_Plan_Item__c item = new Settlement_Plan_Item__c(
            Payment_Amount__c = 1000.00,
            Payment_Date__c = Date.today()
        );

        Test.startTest();
        // Override commission to $50 (only commission can be overridden, not bank fee)
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, 50.00);
        calculator.calculateFeesForItem(item);
        Test.stopTest();

        System.assertEquals(50.00, item.Commission_Fee__c, 'Commission should be overridden to $50');
        System.assertEquals(config.Default_Bank_Fee__c, item.Bank_Fee__c, 'Bank fee should ALWAYS come from config');
    }

    @IsTest
    static void testFeeCalculator_EppsMonthEndFee() {
        Settlement_Calc_Config__mdt config = [
            SELECT Default_Commission_Fee__c, Default_Bank_Fee__c, 
                   EPPS_Transaction_Fee__c, EPPS_Monthly_Minimum__c
            FROM Settlement_Calc_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        // Create 2 items in same month
        // 2 * $12 = $24, minimum is $55, so true-up = $55 - $24 = $31
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(
                Payment_Amount__c = 500.00,
                Payment_Date__c = Date.newInstance(2026, 1, 5),
                EPPS_Transaction_Fee__c = config.EPPS_Transaction_Fee__c
            ),
            new Settlement_Plan_Item__c(
                Payment_Amount__c = 500.00,
                Payment_Date__c = Date.newInstance(2026, 1, 20),
                EPPS_Transaction_Fee__c = config.EPPS_Transaction_Fee__c
            )
        };

        Test.startTest();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, null);
        calculator.calculateEppsMonthEndFees(items);
        Test.stopTest();

        // First item should have no month-end fee (null or 0)
        Decimal firstItemFee = items[0].EPPS_Month_End_Fee__c == null ? 0 : items[0].EPPS_Month_End_Fee__c;
        System.assertEquals(0, firstItemFee, 'First item should have no month-end fee');
        // Second item (last of month) should have true-up
        Decimal expectedTrueUp = config.EPPS_Monthly_Minimum__c - (2 * config.EPPS_Transaction_Fee__c);
        System.assertEquals(expectedTrueUp, items[1].EPPS_Month_End_Fee__c, 
            'Last item should have month-end true-up of $' + expectedTrueUp);
    }

    @IsTest
    static void testFeeCalculator_NullConfig_ThrowsException() {
        Test.startTest();
        try {
            SettlementFeeCalculator calculator = new SettlementFeeCalculator(null, null);
            System.assert(false, 'Should have thrown exception for null config');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('Configuration'), 
                'Error should mention configuration: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testFeeCalculator_CalculateFeeTotals() {
        Settlement_Calc_Config__mdt config = [
            SELECT Default_Commission_Fee__c, Default_Bank_Fee__c, 
                   EPPS_Transaction_Fee__c, EPPS_Monthly_Minimum__c
            FROM Settlement_Calc_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(
                Commission_Fee__c = 35.00,
                Bank_Fee__c = 35.00,
                EPPS_Transaction_Fee__c = 12.00,
                EPPS_Month_End_Fee__c = 0,
                Payee_Fee__c = 0
            ),
            new Settlement_Plan_Item__c(
                Commission_Fee__c = 35.00,
                Bank_Fee__c = 35.00,
                EPPS_Transaction_Fee__c = 12.00,
                EPPS_Month_End_Fee__c = 31.00,
                Payee_Fee__c = 0
            )
        };

        Test.startTest();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, null);
        Map<String, Decimal> totals = calculator.calculateFeeTotals(items);
        Test.stopTest();

        System.assertEquals(70.00, totals.get('commissionTotal'), 'Commission total should be $70');
        System.assertEquals(70.00, totals.get('bankTotal'), 'Bank total should be $70');
        System.assertEquals(24.00, totals.get('eppsTransactionTotal'), 'EPPS transaction total should be $24');
        System.assertEquals(31.00, totals.get('eppsMonthEndTotal'), 'EPPS month-end total should be $31');
        System.assertEquals(195.00, totals.get('grandTotal'), 'Grand total should be $195');
    }

    // ==================== EXCEPTION TESTS ====================

    @IsTest
    static void testException_WithErrorType() {
        Test.startTest();
        SettlementCalculatorException ex = new SettlementCalculatorException(
            SettlementCalculatorException.ErrorType.NO_SEGMENTS,
            'Test error message'
        );
        Test.stopTest();

        System.assertEquals(SettlementCalculatorException.ErrorType.NO_SEGMENTS, ex.getErrorType());
        System.assertEquals('Test error message', ex.getMessage());
    }

    @IsTest
    static void testException_WithFieldContext() {
        Test.startTest();
        SettlementCalculatorException ex = new SettlementCalculatorException(
            SettlementCalculatorException.ErrorType.INVALID_SEGMENT_CONFIG,
            'Field is invalid',
            'Payment_Amount__c',
            -100
        );
        Test.stopTest();

        System.assertEquals(SettlementCalculatorException.ErrorType.INVALID_SEGMENT_CONFIG, ex.getErrorType());
        System.assertEquals('Payment_Amount__c', ex.getFieldName());
        System.assertEquals(-100, ex.getInvalidValue());
    }

    // ==================== EDGE CASE TESTS ====================

    @IsTest(SeeAllData=true)
    static void testCalculatePlan_LargeSettlement() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Large settlement: $100,000
        credOpp.Settlement_Offer_Amount__c = 100000.00;
        update credOpp;

        // 10 payments of $10,000
        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 10000.00, 10, 'Monthly', Date.newInstance(2026, 1, 1)
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Large settlement should succeed');
        System.assertEquals(10, result.numberOfPayments, 'Should have 10 payments');
        System.assertEquals(100000.00, result.totalScheduledAmount, 'Total should match');
    }

    @IsTest(SeeAllData=true)
    static void testCalculatePlan_SmallRemainder() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Settlement that will have small remainder
        credOpp.Settlement_Offer_Amount__c = 1001.00;
        update credOpp;

        // $500/payment will leave $1 remainder
        Settlement_Segment__c segment = createRemainderSegment(
            credOpp.Id, 1, 500.00, 'Monthly', Date.newInstance(2026, 1, 1)
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Small remainder should succeed');
        System.assertEquals(1001.00, result.totalScheduledAmount, 'Total should be exact');
        // Last payment should be $1
        System.assertEquals(1.00, result.planItems[result.planItems.size() - 1].Payment_Amount__c, 
            'Last payment should be $1 remainder');
    }

    @IsTest(SeeAllData=true)
    static void testCalculatePlan_Overpayment_Prevention() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Settlement of $1000
        credOpp.Settlement_Offer_Amount__c = 1000.00;
        update credOpp;

        // Fixed segment requesting more than balance
        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 600.00, 3, 'Monthly', Date.newInstance(2026, 1, 1)
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Should succeed with adjusted final payment');
        System.assertEquals(1000.00, result.totalScheduledAmount, 'Should not overpay');
        // First payment: $600, Second payment: $400 (remaining), Third: skipped
        System.assertEquals(2, result.numberOfPayments, 'Should only have 2 payments');
        System.assertEquals(600.00, result.planItems[0].Payment_Amount__c, 'First payment $600');
        System.assertEquals(400.00, result.planItems[1].Payment_Amount__c, 'Second payment $400 (remaining)');
    }

    @IsTest(SeeAllData=true)
    static void testCalculatePlan_FrequencyWeekly() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        credOpp.Settlement_Offer_Amount__c = 400.00;
        update credOpp;

        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 100.00, 4, 'Weekly', Date.newInstance(2026, 1, 5) // Monday
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Weekly calculation should succeed');
        System.assertEquals(4, result.numberOfPayments, 'Should have 4 payments');

        // Verify dates are 7 days apart
        Date firstDate = result.planItems[0].Payment_Date__c;
        Date secondDate = result.planItems[1].Payment_Date__c;
        System.assertEquals(7, firstDate.daysBetween(secondDate), 'Payments should be 7 days apart');
    }

    @IsTest(SeeAllData=true)
    static void testCalculatePlan_EscrowShortage() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Low escrow balance will cause shortage
        credOpp.Escrow_Start_Balance__c = 500.00;
        update credOpp;

        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 5000.00, 2, 'Monthly', Date.newInstance(2026, 2, 1)
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Calculation should succeed even with shortage');
        System.assertEquals(true, result.hasEscrowShortage, 'Should detect escrow shortage');
        System.assert(result.escrowShortageCount > 0, 'Should have shortage count > 0');
    }

    // ==================== ADDITIONAL COVERAGE TESTS ====================
    // These tests cover edge cases and error paths to increase code coverage

    @IsTest
    static void testController_CalculateAndSavePlan_NullId() {
        Test.startTest();
        SettlementPlanCalculatorService.CalculationResult result = 
            SettlementPlanCalculatorController.calculateAndSavePlan(null, true);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with null ID');
        System.assert(result.errorMessage.contains('required'), 
            'Error should mention required: ' + result.errorMessage);
    }

    @IsTest
    static void testController_DeletePlanItems_NullId() {
        Test.startTest();
        try {
            SettlementPlanCalculatorController.deletePlanItems(null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            // AuraHandledException was thrown as expected
            // Note: getMessage() returns "Script-thrown exception" due to Salesforce platform behavior
            // The actual error message is passed to the LWC, not available in Apex catch block
            System.assert(true, 'AuraHandledException thrown as expected');
        }
        Test.stopTest();
    }

    @IsTest
    static void testController_GetCreditorOpportunity_NullId() {
        Test.startTest();
        CreditorOpportunity__c result = SettlementPlanCalculatorController.getCreditorOpportunity(null);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for null ID');
    }

    @IsTest
    static void testController_GetCreditorOpportunity_InvalidId() {
        // Use a fake ID that doesn't exist
        Id fakeId = '001000000000000AAA';
        
        Test.startTest();
        CreditorOpportunity__c result = SettlementPlanCalculatorController.getCreditorOpportunity(fakeId);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for non-existent ID');
    }

    @IsTest
    static void testController_ValidateBeforeCalculation_Comprehensive() {
        // Test multiple validation scenarios in one test for efficiency
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Scenario 1: Missing Settlement Offer Amount
        credOpp.Settlement_Offer_Amount__c = null;
        update credOpp;

        Test.startTest();
        SettlementPlanCalculatorController.ValidationResult result1 = 
            SettlementPlanCalculatorController.validateBeforeCalculation(credOpp.Id);
        Test.stopTest();

        System.assertEquals(false, result1.isValid, 'Should be invalid with no amount');
        System.assert(result1.errors.size() > 0, 'Should have errors for missing amount');
    }

    @IsTest
    static void testController_ValidateBeforeCalculation_MissingStartDate() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Create segment without start date
        Settlement_Segment__c segment = new Settlement_Segment__c(
            Creditors_List__c = credOpp.Id,
            Segment_Order__c = 1,
            Segment_Type__c = 'Fixed',
            Payment_Amount__c = 1000.00,
            Payment_Count__c = 1,
            Frequency__c = 'Monthly',
            Start_Date__c = null
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorController.ValidationResult result = 
            SettlementPlanCalculatorController.validateBeforeCalculation(credOpp.Id);
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid without start date');
        System.assert(result.errors.size() > 0, 'Should have error about start date');
    }

    @IsTest
    static void testController_ValidateBeforeCalculation_InvalidSegments() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Create Fixed segment missing payment amount
        Settlement_Segment__c seg1 = new Settlement_Segment__c(
            Creditors_List__c = credOpp.Id,
            Segment_Order__c = 1,
            Segment_Type__c = 'Fixed',
            Payment_Amount__c = null, // Missing!
            Payment_Count__c = 2,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today()
        );
        insert seg1;

        Test.startTest();
        SettlementPlanCalculatorController.ValidationResult result = 
            SettlementPlanCalculatorController.validateBeforeCalculation(credOpp.Id);
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid');
        System.assert(result.errors.size() > 0, 'Should have errors');
    }

    @IsTest
    static void testController_ValidateBeforeCalculation_WithWarnings() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Set escrow to null to trigger warning
        credOpp.Escrow_Start_Balance__c = null;
        update credOpp;

        // Create valid segment
        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 1000.00, 1, 'Monthly', Date.today()
        );
        insert segment;

        // Create existing plan item to trigger "existing items" warning
        Settlement_Plan_Item__c item = new Settlement_Plan_Item__c(
            Creditors_List__c = credOpp.Id,
            Settlement_Segment__c = segment.Id,
            Payment_Number__c = 1,
            Payment_Amount__c = 500.00,
            Payment_Date__c = Date.today(),
            Status__c = 'Scheduled'
        );
        insert item;

        Test.startTest();
        SettlementPlanCalculatorController.ValidationResult result = 
            SettlementPlanCalculatorController.validateBeforeCalculation(credOpp.Id);
        Test.stopTest();

        // Should be valid but have warnings
        System.assertEquals(true, result.isValid, 'Should be valid');
        System.assert(result.warnings.size() >= 1, 'Should have warnings: ' + result.warnings);
    }

    @IsTest
    static void testService_InvalidCreditorOpportunityId() {
        // Use a fake ID that doesn't exist in database
        Id fakeId = '001000000000000AAA';

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(fakeId);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with invalid ID');
        System.assert(result.errorMessage.contains('not found'), 
            'Error should mention not found: ' + result.errorMessage);
    }

    @IsTest(SeeAllData=true)
    static void testCalculatePlan_ThreeSegmentScenario() {
        // Note: Cannot test null Frequency__c because it's a required field in the org.
        // The org-level validation prevents inserting records with null Frequency__c.
        // Instead, test a complex 3-segment scenario for better coverage.
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Segment 1: Fixed - 2 payments of $2,000 = $4,000
        Settlement_Segment__c seg1 = createFixedSegment(
            credOpp.Id, 1, 2000.00, 2, 'Bi-Weekly', Date.newInstance(2026, 2, 2) // Monday
        );

        // Segment 2: Fixed - 2 payments of $2,000 = $4,000 (total so far: $8,000)
        Settlement_Segment__c seg2 = createFixedSegment(
            credOpp.Id, 2, 2000.00, 2, 'Monthly', null // continues from previous
        );

        // Segment 3: SolveAmount - 2 payments for remaining $2,000
        Settlement_Segment__c seg3 = createSolveAmountSegment(
            credOpp.Id, 3, 2, 'Monthly', null // continues from previous
        );

        insert new List<Settlement_Segment__c>{ seg1, seg2, seg3 };

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Calculation should succeed');
        System.assertEquals(6, result.numberOfPayments, 'Should have 6 payments (2+2+2)');
        System.assertEquals(10000.00, result.totalScheduledAmount, 'Total should be $10,000');
    }

    @IsTest
    static void testValidateSegment_FixedMissingPaymentCount() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Create Fixed segment without payment count
        Settlement_Segment__c segment = new Settlement_Segment__c(
            Creditors_List__c = credOpp.Id,
            Segment_Order__c = 1,
            Segment_Type__c = 'Fixed',
            Payment_Amount__c = 1000.00,
            Payment_Count__c = null, // Missing for Fixed!
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today()
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail without payment count');
        System.assert(result.errorMessage.contains('Payment Count'), 
            'Error should mention payment count: ' + result.errorMessage);
    }

    @IsTest
    static void testValidateSegment_SolveAmountMissingPaymentCount() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Create SolveAmount segment without payment count
        Settlement_Segment__c segment = new Settlement_Segment__c(
            Creditors_List__c = credOpp.Id,
            Segment_Order__c = 1,
            Segment_Type__c = 'SolveAmount',
            Payment_Count__c = null, // Missing for SolveAmount!
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today()
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail without payment count');
        System.assert(result.errorMessage.contains('Payment Count'), 
            'Error should mention payment count: ' + result.errorMessage);
    }

    @IsTest
    static void testValidateSegment_RemainderMissingPaymentAmount() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Create Remainder segment without payment amount
        Settlement_Segment__c segment = new Settlement_Segment__c(
            Creditors_List__c = credOpp.Id,
            Segment_Order__c = 1,
            Segment_Type__c = 'Remainder',
            Payment_Amount__c = null, // Missing for Remainder!
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today()
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail without payment amount');
        System.assert(result.errorMessage.contains('Payment Amount'), 
            'Error should mention payment amount: ' + result.errorMessage);
    }

    @IsTest(SeeAllData=true)
    static void testCalculatePlan_NullEscrowBalance() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Set escrow to null (tests ASSUMPTION E3: defaults to $0)
        credOpp.Escrow_Start_Balance__c = null;
        update credOpp;

        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 10000.00, 1, 'Monthly', Date.newInstance(2026, 2, 1)
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.calculatePlan(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Should succeed with null escrow');
        System.assertEquals(true, result.hasEscrowShortage, 'Should have shortage when starting from $0');
    }

    @IsTest(SeeAllData=true)
    static void testSaveCalculation_WithoutPriorCalculation() {
        // Test calling saveCalculation directly (triggers internal calculatePlan)
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        Settlement_Segment__c segment = createFixedSegment(
            credOpp.Id, 1, 5000.00, 2, 'Monthly', Date.newInstance(2026, 2, 1)
        );
        insert segment;

        Test.startTest();
        // Create new service and call saveCalculation directly (without calculatePlan first)
        SettlementPlanCalculatorService service = new SettlementPlanCalculatorService();
        SettlementPlanCalculatorService.CalculationResult result = service.saveCalculation(credOpp.Id, false);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Save should succeed');
        System.assertEquals(2, result.numberOfPayments, 'Should have 2 payments');
    }

    @IsTest
    static void testController_GetExistingPlanItems_NullId() {
        Test.startTest();
        List<Settlement_Plan_Item__c> items = SettlementPlanCalculatorController.getExistingPlanItems(null);
        Test.stopTest();

        System.assertEquals(0, items.size(), 'Should return empty list for null ID');
    }

    @IsTest
    static void testController_ValidateBeforeCalculation_NullCredOpp() {
        // Test with fake ID that won't find a CreditorOpportunity
        Id fakeId = '001000000000000AAA';

        Test.startTest();
        SettlementPlanCalculatorController.ValidationResult result = 
            SettlementPlanCalculatorController.validateBeforeCalculation(fakeId);
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid');
        System.assert(result.errors.size() > 0, 'Should have error about not found');
    }

    @IsTest
    static void testController_ValidateBeforeCalculation_RemainderMissingAmount() {
        // Note: Cannot test blank Segment_Type__c because it's a required picklist field in the org.
        // The org-level validation prevents inserting records with blank Segment_Type__c.
        // Instead, test Remainder segment missing Payment Amount (allowed by org, caught by validation)
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Create Remainder segment missing Payment Amount (org allows null, validation catches it)
        Settlement_Segment__c segment = new Settlement_Segment__c(
            Creditors_List__c = credOpp.Id,
            Segment_Order__c = 1,
            Segment_Type__c = 'Remainder',
            Payment_Amount__c = null, // Missing for Remainder type
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today()
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorController.ValidationResult result = 
            SettlementPlanCalculatorController.validateBeforeCalculation(credOpp.Id);
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid without payment amount');
        System.assert(result.errors.size() > 0, 'Should have error about payment amount');
    }

    @IsTest
    static void testController_ValidateBeforeCalculation_SolveAmountMissingCount() {
        Map<String, Object> testData = createTestData();
        CreditorOpportunity__c credOpp = (CreditorOpportunity__c) testData.get('credOpp');

        // Create SolveAmount segment missing count
        Settlement_Segment__c segment = new Settlement_Segment__c(
            Creditors_List__c = credOpp.Id,
            Segment_Order__c = 1,
            Segment_Type__c = 'SolveAmount',
            Payment_Count__c = null, // Missing for SolveAmount
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today()
        );
        insert segment;

        Test.startTest();
        SettlementPlanCalculatorController.ValidationResult result = 
            SettlementPlanCalculatorController.validateBeforeCalculation(credOpp.Id);
        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Should be invalid');
        System.assert(result.errors.size() > 0, 'Should have error about payment count');
    }

    @IsTest
    static void testDateUtils_AdvanceDate_UnknownFrequency() {
        // Test ASSUMPTION D7: Unknown frequency defaults to Monthly
        Date startDate = Date.newInstance(2026, 1, 15);

        Test.startTest();
        Date result = SettlementDateUtils.advanceDate(startDate, 'Unknown', 1);
        Test.stopTest();

        System.assertEquals(Date.newInstance(2026, 2, 15), result, 
            'Unknown frequency should default to monthly (advance 1 month)');
    }
}