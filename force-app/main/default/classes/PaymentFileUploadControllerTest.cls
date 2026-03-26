/**
 * @description Test class for PaymentFileUploadController.
 * Covers validateUploadedRecords and createScheduleItemsFromUpload
 * with various valid, invalid, and edge-case scenarios.
 */
@IsTest
private class PaymentFileUploadControllerTest {

    // EPPS IDs used across tests
    private static final String EPPS_ID_1 = '956';
    private static final String EPPS_ID_2 = '739';
    private static final String EPPS_ID_3 = '907';
    private static final String EPPS_ID_NO_PLAN = '888';

    // ==================================================================================
    // TEST SETUP
    // ==================================================================================

    @TestSetup
    static void setupTestData() {
        // Create Account
        Account acc = new Account(Name = 'Test Upload Account');
        insert acc;

        // Create Opportunities with EPPS IDs
        List<Opportunity> opps = new List<Opportunity>();

        Opportunity opp1 = new Opportunity(
            Name = 'Test Opp 956',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            EPPS_ID__c = EPPS_ID_1
        );
        opps.add(opp1);

        Opportunity opp2 = new Opportunity(
            Name = 'Test Opp 739',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            EPPS_ID__c = EPPS_ID_2
        );
        opps.add(opp2);

        Opportunity opp3 = new Opportunity(
            Name = 'Test Opp 907',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            EPPS_ID__c = EPPS_ID_3
        );
        opps.add(opp3);

        // Opportunity with NO active plan
        Opportunity opp4 = new Opportunity(
            Name = 'Test Opp No Plan',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            EPPS_ID__c = EPPS_ID_NO_PLAN
        );
        opps.add(opp4);

        insert opps;

        // Create active Payment Plans for opp1, opp2, opp3 (NOT opp4)
        List<PaymentPlan__c> plans = new List<PaymentPlan__c>();

        PaymentPlan__c plan1 = new PaymentPlan__c(
            Opportunity__c = opp1.Id,
            Program_Type__c = 'DCG MOD',
            Total_Debt__c = 50000,
            Settlement_Percentage__c = 50,
            Program_Fee_Percentage__c = 20,
            Total_Program_Cost__c = 35000,
            Weekly_Payment__c = 500,
            Number_of_Payments__c = 70,
            First_Payment_Date__c = Date.today(),
            Status__c = 'Active',
            Version_Number__c = 1,
            Is_Active__c = true,
            Banking_Fee__c = 15,
            Setup_Fee__c = 1000,
            Setup_Fee_Payments__c = 5
        );
        plans.add(plan1);

        PaymentPlan__c plan2 = new PaymentPlan__c(
            Opportunity__c = opp2.Id,
            Program_Type__c = 'DCG MOD',
            Total_Debt__c = 40000,
            Settlement_Percentage__c = 50,
            Program_Fee_Percentage__c = 20,
            Total_Program_Cost__c = 28000,
            Weekly_Payment__c = 400,
            Number_of_Payments__c = 70,
            First_Payment_Date__c = Date.today(),
            Status__c = 'Active',
            Version_Number__c = 1,
            Is_Active__c = true,
            Banking_Fee__c = 20,
            Setup_Fee__c = 800,
            Setup_Fee_Payments__c = 4
        );
        plans.add(plan2);

        PaymentPlan__c plan3 = new PaymentPlan__c(
            Opportunity__c = opp3.Id,
            Program_Type__c = 'DCG MOD',
            Total_Debt__c = 60000,
            Settlement_Percentage__c = 50,
            Program_Fee_Percentage__c = 20,
            Total_Program_Cost__c = 42000,
            Weekly_Payment__c = 600,
            Number_of_Payments__c = 70,
            First_Payment_Date__c = Date.today(),
            Status__c = 'Active',
            Version_Number__c = 1,
            Is_Active__c = true,
            Banking_Fee__c = 15,
            Setup_Fee__c = 1200,
            Setup_Fee_Payments__c = 6
        );
        plans.add(plan3);

        insert plans;

        // Create existing schedule items for plan1 (to test Payment_Number__c auto-increment)
        List<Payment_Schedule_Item__c> existingItems = new List<Payment_Schedule_Item__c>();
        Date paymentDate = Date.today();

        for (Integer i = 1; i <= 3; i++) {
            Payment_Schedule_Item__c item = new Payment_Schedule_Item__c(
                Payment_Plan__c = plan1.Id,
                Payment_Number__c = i,
                Payment_Date__c = paymentDate,
                Total_Payment__c = 500,
                Setup_Fee_Amount__c = 200,
                Program_Fee_Amount__c = 0,
                Banking_Fee_Amount__c = 15,
                To_Escrow_Amount__c = 285,
                Status__c = 'Scheduled'
            );
            existingItems.add(item);
            paymentDate = paymentDate.addDays(7);
        }
        insert existingItems;
    }

    // ==================================================================================
    // HELPER METHODS
    // ==================================================================================

    /**
     * @description Build a JSON payload from a list of row maps.
     * Each map should contain keys: eppsId, clientName, bankName,
     * paymentDate, wireAmount, eppsAmount, commissionAmount, setupFee, notes
     */
    private static String buildJsonPayload(List<Map<String, Object>> rows) {
        return JSON.serialize(rows);
    }

    /**
     * @description Build a single upload row map with all fields populated.
     */
    private static Map<String, Object> buildRow(
        String eppsId,
        String clientName,
        String bankName,
        String paymentDate,
        Decimal wireAmount,
        Decimal eppsAmount,
        Decimal commissionAmount,
        Decimal setupFee,
        String notes
    ) {
        Map<String, Object> row = new Map<String, Object>();
        row.put('eppsId', eppsId);
        row.put('clientName', clientName);
        row.put('bankName', bankName);
        row.put('paymentDate', paymentDate);
        row.put('wireAmount', wireAmount);
        row.put('eppsAmount', eppsAmount);
        row.put('commissionAmount', commissionAmount);
        row.put('setupFee', setupFee);
        row.put('notes', notes);
        return row;
    }

    // ==================================================================================
    // VALIDATE UPLOADED RECORDS TESTS
    // ==================================================================================

    @IsTest
    static void testValidateUploadedRecords_Success() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        rows.add(buildRow(EPPS_ID_1, 'Client A', 'Bank A', '2026-04-01', 1000, 800, 150, 50, 'Note A'));
        rows.add(buildRow(EPPS_ID_2, 'Client B', 'Bank B', '2026-04-02', 2000, 1600, 300, 100, 'Note B'));
        rows.add(buildRow(EPPS_ID_3, 'Client C', 'Bank C', '2026-04-03', 3000, 2400, 450, 150, 'Note C'));

        String payload = buildJsonPayload(rows);

        Test.startTest();
        List<PaymentFileUploadController.ValidationResult> results =
            PaymentFileUploadController.validateUploadedRecords(payload);
        Test.stopTest();

        Assert.areEqual(3, results.size(), 'Should return 3 validation results');

        for (PaymentFileUploadController.ValidationResult vr : results) {
            Assert.isTrue(vr.isValid, 'Row with EPPS ID ' + vr.eppsId + ' should be valid');
            Assert.isNotNull(vr.opportunityId, 'Should have Opportunity Id');
            Assert.isNotNull(vr.opportunityName, 'Should have Opportunity Name');
            Assert.isNotNull(vr.paymentPlanId, 'Should have Payment Plan Id');
            Assert.isNotNull(vr.paymentPlanName, 'Should have Payment Plan Name');
            Assert.isNull(vr.errorMessage, 'Should have no error message');
        }
    }

    @IsTest
    static void testValidateUploadedRecords_InvalidEppsId() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        rows.add(buildRow('INVALID_1', 'Client X', 'Bank X', '2026-04-01', 500, 400, 75, 25, ''));
        rows.add(buildRow('INVALID_2', 'Client Y', 'Bank Y', '2026-04-02', 600, 480, 90, 30, ''));

        String payload = buildJsonPayload(rows);

        Test.startTest();
        List<PaymentFileUploadController.ValidationResult> results =
            PaymentFileUploadController.validateUploadedRecords(payload);
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Should return 2 validation results');

        for (PaymentFileUploadController.ValidationResult vr : results) {
            Assert.isFalse(vr.isValid, 'Row with invalid EPPS ID should be invalid');
            Assert.isTrue(
                vr.errorMessage.contains('No Opportunity found'),
                'Error should mention no Opportunity found. Actual: ' + vr.errorMessage
            );
            Assert.isNull(vr.opportunityId, 'Should not have Opportunity Id');
            Assert.isNull(vr.paymentPlanId, 'Should not have Payment Plan Id');
        }
    }

    @IsTest
    static void testValidateUploadedRecords_NoActivePlan() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        rows.add(buildRow(EPPS_ID_NO_PLAN, 'Client No Plan', 'Bank NP', '2026-04-01', 500, 400, 75, 25, ''));

        String payload = buildJsonPayload(rows);

        Test.startTest();
        List<PaymentFileUploadController.ValidationResult> results =
            PaymentFileUploadController.validateUploadedRecords(payload);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Should return 1 validation result');

        PaymentFileUploadController.ValidationResult vr = results[0];
        Assert.isFalse(vr.isValid, 'Row should be invalid — no active plan');
        Assert.isTrue(
            vr.errorMessage.contains('No active Payment Plan'),
            'Error should mention no active Payment Plan. Actual: ' + vr.errorMessage
        );
        Assert.isNotNull(vr.opportunityId, 'Should have matched Opportunity Id');
        Assert.isNull(vr.paymentPlanId, 'Should not have Payment Plan Id');
    }

    @IsTest
    static void testValidateUploadedRecords_MixedResults() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        // Valid row
        rows.add(buildRow(EPPS_ID_1, 'Client A', 'Bank A', '2026-04-01', 1000, 800, 150, 50, ''));
        // Invalid — non-existent EPPS ID
        rows.add(buildRow('DOES_NOT_EXIST', 'Client Z', 'Bank Z', '2026-04-02', 500, 400, 75, 25, ''));
        // Invalid — no active plan
        rows.add(buildRow(EPPS_ID_NO_PLAN, 'Client No Plan', 'Bank NP', '2026-04-03', 600, 480, 90, 30, ''));
        // Valid row
        rows.add(buildRow(EPPS_ID_2, 'Client B', 'Bank B', '2026-04-04', 2000, 1600, 300, 100, ''));
        // Invalid — blank EPPS ID
        rows.add(buildRow('', 'Client Blank', 'Bank Blank', '2026-04-05', 100, 80, 15, 5, ''));

        String payload = buildJsonPayload(rows);

        Test.startTest();
        List<PaymentFileUploadController.ValidationResult> results =
            PaymentFileUploadController.validateUploadedRecords(payload);
        Test.stopTest();

        Assert.areEqual(5, results.size(), 'Should return 5 validation results');

        // Row 0: valid
        Assert.isTrue(results[0].isValid, 'Row 0 should be valid');

        // Row 1: invalid EPPS ID
        Assert.isFalse(results[1].isValid, 'Row 1 should be invalid');
        Assert.isTrue(results[1].errorMessage.contains('No Opportunity found'), 'Row 1 error');

        // Row 2: no active plan
        Assert.isFalse(results[2].isValid, 'Row 2 should be invalid');
        Assert.isTrue(results[2].errorMessage.contains('No active Payment Plan'), 'Row 2 error');

        // Row 3: valid
        Assert.isTrue(results[3].isValid, 'Row 3 should be valid');

        // Row 4: blank EPPS ID
        Assert.isFalse(results[4].isValid, 'Row 4 should be invalid');
        Assert.isTrue(results[4].errorMessage.contains('EPPS ID is blank'), 'Row 4 error');
    }

    @IsTest
    static void testValidateUploadedRecords_TooManyRows() {
        // Build 2001 rows to exceed the 2000-row cap
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Integer i = 0; i < 2001; i++) {
            rows.add(buildRow('ID_' + i, 'Client ' + i, 'Bank', '2026-04-01', 100, 80, 15, 5, ''));
        }

        String payload = buildJsonPayload(rows);

        Test.startTest();
        Boolean exceptionThrown = false;
        String exceptionMessage = '';
        try {
            PaymentFileUploadController.validateUploadedRecords(payload);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            exceptionMessage = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(exceptionThrown, 'Should throw AuraHandledException for > 2000 rows');
    }

    // ==================================================================================
    // CREATE SCHEDULE ITEMS TESTS
    // ==================================================================================

    @IsTest
    static void testCreateScheduleItemsFromUpload_Success() {
        // Query plan1 to know its Id for assertions
        Opportunity opp1 = [SELECT Id FROM Opportunity WHERE EPPS_ID__c = :EPPS_ID_1 LIMIT 1];
        Opportunity opp2 = [SELECT Id FROM Opportunity WHERE EPPS_ID__c = :EPPS_ID_2 LIMIT 1];
        PaymentPlan__c plan1 = [SELECT Id FROM PaymentPlan__c WHERE Opportunity__c = :opp1.Id AND Is_Active__c = true LIMIT 1];
        PaymentPlan__c plan2 = [SELECT Id FROM PaymentPlan__c WHERE Opportunity__c = :opp2.Id AND Is_Active__c = true LIMIT 1];

        // Verify existing items on plan1 (should have 3 items, max Payment_Number = 3)
        Integer existingCount = [SELECT COUNT() FROM Payment_Schedule_Item__c WHERE Payment_Plan__c = :plan1.Id];
        Assert.areEqual(3, existingCount, 'Plan 1 should start with 3 existing items');

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        rows.add(buildRow(EPPS_ID_1, 'Client A', 'Bank A', '2026-05-01', 1000, 800, 150, 50, 'Wire note A'));
        rows.add(buildRow(EPPS_ID_2, 'Client B', 'Bank B', '2026-05-02', 2000, 1600, 300, 100, 'Wire note B'));

        String payload = buildJsonPayload(rows);

        Test.startTest();
        PaymentFileUploadController.ProcessingResult result =
            PaymentFileUploadController.createScheduleItemsFromUpload(payload);
        Test.stopTest();

        // Verify processing result summary
        Assert.areEqual(2, result.totalRows, 'Total rows should be 2');
        Assert.areEqual(2, result.successCount, 'All 2 rows should succeed');
        Assert.areEqual(0, result.failureCount, 'No failures expected');
        Assert.areEqual(2, result.results.size(), 'Should have 2 creation results');

        // Verify each result row
        for (PaymentFileUploadController.CreationResult cr : result.results) {
            Assert.isTrue(cr.isSuccess, 'Row ' + cr.rowIndex + ' should succeed');
            Assert.isNotNull(cr.scheduleItemId, 'Should have schedule item Id');
        }

        // Verify schedule items created for plan1 (had 3, should now have 4)
        List<Payment_Schedule_Item__c> plan1Items = [
            SELECT Id, Payment_Number__c, Total_Payment__c, To_Escrow_Amount__c,
                   Program_Fee_Amount__c, Setup_Fee_Amount__c, Banking_Fee_Amount__c, Status__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan1.Id
            ORDER BY Payment_Number__c ASC
        ];
        Assert.areEqual(4, plan1Items.size(), 'Plan 1 should now have 4 items');

        // The new item should have Payment_Number__c = 4 (max was 3)
        Payment_Schedule_Item__c newItem1 = plan1Items[3];
        Assert.areEqual(4, newItem1.Payment_Number__c, 'New item Payment_Number should be 4');
        Assert.areEqual(1000, newItem1.Total_Payment__c, 'Total_Payment__c should match wireAmount');
        Assert.areEqual(800, newItem1.To_Escrow_Amount__c, 'To_Escrow_Amount__c should match eppsAmount');
        Assert.areEqual(150, newItem1.Program_Fee_Amount__c, 'Program_Fee_Amount__c should match commissionAmount');
        Assert.areEqual(50, newItem1.Setup_Fee_Amount__c, 'Setup_Fee_Amount__c should match setupFee');
        Assert.areEqual('Wire', newItem1.Status__c, 'Status should be Wire');

        // Verify schedule items for plan2 (had 0, should now have 1)
        List<Payment_Schedule_Item__c> plan2Items = [
            SELECT Id, Payment_Number__c, Total_Payment__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan2.Id
            ORDER BY Payment_Number__c ASC
        ];
        Assert.areEqual(1, plan2Items.size(), 'Plan 2 should have 1 item');
        Assert.areEqual(1, plan2Items[0].Payment_Number__c, 'Plan 2 new item should start at Payment_Number 1');

        // Verify Payment_Fee__c records created (3 fees per item: Banking, Program, Setup)
        Set<Id> newItemIds = new Set<Id>();
        newItemIds.add(result.results[0].scheduleItemId);
        newItemIds.add(result.results[1].scheduleItemId);

        List<Payment_Fee__c> fees = [
            SELECT Id, Payment_Schedule_Item__c, Type__c, Amount__c
            FROM Payment_Fee__c
            WHERE Payment_Schedule_Item__c IN :newItemIds
        ];
        Assert.areEqual(6, fees.size(), 'Should have 6 fee records (3 per item)');
    }

    @IsTest
    static void testCreateScheduleItemsFromUpload_PartialSuccess() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        // Valid row
        rows.add(buildRow(EPPS_ID_1, 'Client A', 'Bank A', '2026-05-01', 1000, 800, 150, 50, ''));
        // Invalid — non-existent EPPS ID
        rows.add(buildRow('NONEXISTENT', 'Client X', 'Bank X', '2026-05-02', 500, 400, 75, 25, ''));
        // Invalid — no active plan
        rows.add(buildRow(EPPS_ID_NO_PLAN, 'Client NP', 'Bank NP', '2026-05-03', 600, 480, 90, 30, ''));
        // Valid row
        rows.add(buildRow(EPPS_ID_3, 'Client C', 'Bank C', '2026-05-04', 3000, 2400, 450, 150, ''));

        String payload = buildJsonPayload(rows);

        Test.startTest();
        PaymentFileUploadController.ProcessingResult result =
            PaymentFileUploadController.createScheduleItemsFromUpload(payload);
        Test.stopTest();

        Assert.areEqual(4, result.totalRows, 'Total rows should be 4');
        Assert.areEqual(2, result.successCount, 'Should have 2 successes');
        Assert.areEqual(2, result.failureCount, 'Should have 2 failures');

        // Row 0: success
        Assert.isTrue(result.results[0].isSuccess, 'Row 0 should succeed');
        Assert.isNotNull(result.results[0].scheduleItemId, 'Row 0 should have schedule item Id');

        // Row 1: failure
        Assert.isFalse(result.results[1].isSuccess, 'Row 1 should fail');
        Assert.isTrue(
            result.results[1].errorMessage.contains('No Opportunity found'),
            'Row 1 error should mention no Opportunity'
        );

        // Row 2: failure
        Assert.isFalse(result.results[2].isSuccess, 'Row 2 should fail');
        Assert.isTrue(
            result.results[2].errorMessage.contains('No active Payment Plan'),
            'Row 2 error should mention no active plan'
        );

        // Row 3: success
        Assert.isTrue(result.results[3].isSuccess, 'Row 3 should succeed');
        Assert.isNotNull(result.results[3].scheduleItemId, 'Row 3 should have schedule item Id');
    }

    @IsTest
    static void testCreateScheduleItemsFromUpload_DuplicateEppsIds() {
        // Multiple rows targeting the same EPPS ID (same Opportunity/Plan)
        Opportunity opp1 = [SELECT Id FROM Opportunity WHERE EPPS_ID__c = :EPPS_ID_1 LIMIT 1];
        PaymentPlan__c plan1 = [SELECT Id FROM PaymentPlan__c WHERE Opportunity__c = :opp1.Id AND Is_Active__c = true LIMIT 1];

        // Plan1 already has 3 items (Payment_Number 1-3)
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        rows.add(buildRow(EPPS_ID_1, 'Client A1', 'Bank A', '2026-06-01', 1000, 800, 150, 50, ''));
        rows.add(buildRow(EPPS_ID_1, 'Client A2', 'Bank A', '2026-06-08', 1100, 880, 165, 55, ''));
        rows.add(buildRow(EPPS_ID_1, 'Client A3', 'Bank A', '2026-06-15', 1200, 960, 180, 60, ''));

        String payload = buildJsonPayload(rows);

        Test.startTest();
        PaymentFileUploadController.ProcessingResult result =
            PaymentFileUploadController.createScheduleItemsFromUpload(payload);
        Test.stopTest();

        Assert.areEqual(3, result.totalRows, 'Total rows should be 3');
        Assert.areEqual(3, result.successCount, 'All 3 rows should succeed');
        Assert.areEqual(0, result.failureCount, 'No failures expected');

        // Verify sequential Payment_Number__c (existing max = 3, new = 4, 5, 6)
        List<Payment_Schedule_Item__c> allItems = [
            SELECT Id, Payment_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan1.Id
            ORDER BY Payment_Number__c ASC
        ];
        Assert.areEqual(6, allItems.size(), 'Plan should now have 6 total items');

        // Verify the new items have sequential payment numbers
        Assert.areEqual(4, allItems[3].Payment_Number__c, 'Fourth item should be Payment_Number 4');
        Assert.areEqual(5, allItems[4].Payment_Number__c, 'Fifth item should be Payment_Number 5');
        Assert.areEqual(6, allItems[5].Payment_Number__c, 'Sixth item should be Payment_Number 6');
    }

    @IsTest
    static void testCreateScheduleItemsFromUpload_EmptyPayload() {
        String payload = '[]';

        Test.startTest();
        PaymentFileUploadController.ProcessingResult result =
            PaymentFileUploadController.createScheduleItemsFromUpload(payload);
        Test.stopTest();

        Assert.areEqual(0, result.totalRows, 'Total rows should be 0');
        Assert.areEqual(0, result.successCount, 'Success count should be 0');
        Assert.areEqual(0, result.failureCount, 'Failure count should be 0');
        Assert.isTrue(result.results.isEmpty(), 'Results list should be empty');
    }

    @IsTest
    static void testCreateScheduleItemsFromUpload_NullPayload() {
        Test.startTest();
        PaymentFileUploadController.ProcessingResult result =
            PaymentFileUploadController.createScheduleItemsFromUpload(null);
        Test.stopTest();

        Assert.areEqual(0, result.totalRows, 'Total rows should be 0 for null payload');
        Assert.areEqual(0, result.successCount, 'Success count should be 0');
        Assert.areEqual(0, result.failureCount, 'Failure count should be 0');
    }

    @IsTest
    static void testValidateUploadedRecords_EmptyPayload() {
        String payload = '[]';

        Test.startTest();
        List<PaymentFileUploadController.ValidationResult> results =
            PaymentFileUploadController.validateUploadedRecords(payload);
        Test.stopTest();

        Assert.isTrue(results.isEmpty(), 'Should return empty list for empty payload');
    }

    @IsTest
    static void testValidateUploadedRecords_BlankEppsId() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        rows.add(buildRow(null, 'Client Null', 'Bank', '2026-04-01', 100, 80, 15, 5, ''));
        rows.add(buildRow('  ', 'Client Spaces', 'Bank', '2026-04-02', 100, 80, 15, 5, ''));

        String payload = buildJsonPayload(rows);

        Test.startTest();
        List<PaymentFileUploadController.ValidationResult> results =
            PaymentFileUploadController.validateUploadedRecords(payload);
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Should return 2 results');
        for (PaymentFileUploadController.ValidationResult vr : results) {
            Assert.isFalse(vr.isValid, 'Row with blank EPPS ID should be invalid');
            Assert.isTrue(
                vr.errorMessage.contains('EPPS ID is blank'),
                'Error should mention blank EPPS ID. Actual: ' + vr.errorMessage
            );
        }
    }

    @IsTest
    static void testCreateScheduleItemsFromUpload_FieldMappingsAndBankingFee() {
        // Test that Banking_Fee_Amount__c comes from the plan, not the upload row
        Opportunity opp2 = [SELECT Id FROM Opportunity WHERE EPPS_ID__c = :EPPS_ID_2 LIMIT 1];
        PaymentPlan__c plan2 = [SELECT Id, Banking_Fee__c FROM PaymentPlan__c WHERE Opportunity__c = :opp2.Id AND Is_Active__c = true LIMIT 1];

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        rows.add(buildRow(EPPS_ID_2, 'Client B', 'Bank B', '2026-07-01', 2000, 1600, 300, 100, 'Detail note'));

        String payload = buildJsonPayload(rows);

        Test.startTest();
        PaymentFileUploadController.ProcessingResult result =
            PaymentFileUploadController.createScheduleItemsFromUpload(payload);
        Test.stopTest();

        Assert.areEqual(1, result.successCount, 'Should succeed');

        // Verify field mappings on the created schedule item
        Payment_Schedule_Item__c createdItem = [
            SELECT Payment_Plan__c, Payment_Date__c, Total_Payment__c, To_Escrow_Amount__c,
                   Program_Fee_Amount__c, Setup_Fee_Amount__c, Banking_Fee_Amount__c, Status__c, Payment_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Id = :result.results[0].scheduleItemId
        ];

        Assert.areEqual(plan2.Id, createdItem.Payment_Plan__c, 'Should link to correct plan');
        Assert.areEqual(Date.valueOf('2026-07-01'), createdItem.Payment_Date__c, 'Payment date should match');
        Assert.areEqual(2000, createdItem.Total_Payment__c, 'Total_Payment should match wireAmount');
        Assert.areEqual(1600, createdItem.To_Escrow_Amount__c, 'To_Escrow should match eppsAmount');
        Assert.areEqual(300, createdItem.Program_Fee_Amount__c, 'Program_Fee should match commissionAmount');
        Assert.areEqual(100, createdItem.Setup_Fee_Amount__c, 'Setup_Fee should match setupFee');
        Assert.areEqual(plan2.Banking_Fee__c, createdItem.Banking_Fee_Amount__c, 'Banking_Fee should come from plan');
        Assert.areEqual('Wire', createdItem.Status__c, 'Status should be Wire');
        Assert.areEqual(1, createdItem.Payment_Number__c, 'Payment_Number should be 1 (no prior items)');

        // Verify fee records: Banking, Program, Setup
        List<Payment_Fee__c> fees = [
            SELECT Type__c, Amount__c
            FROM Payment_Fee__c
            WHERE Payment_Schedule_Item__c = :createdItem.Id
            ORDER BY Type__c ASC
        ];
        Assert.areEqual(3, fees.size(), 'Should create 3 fee records');

        // Fees are ordered alphabetically: Banking Fee, Program Fee, Setup Fee
        Assert.areEqual('Banking Fee', fees[0].Type__c, 'First fee should be Banking Fee');
        Assert.areEqual(plan2.Banking_Fee__c, fees[0].Amount__c, 'Banking fee amount should match plan');

        Assert.areEqual('Program Fee', fees[1].Type__c, 'Second fee should be Program Fee');
        Assert.areEqual(300, fees[1].Amount__c, 'Program fee amount should match commissionAmount');

        Assert.areEqual('Setup Fee', fees[2].Type__c, 'Third fee should be Setup Fee');
        Assert.areEqual(100, fees[2].Amount__c, 'Setup fee amount should match setupFee');
    }
}
