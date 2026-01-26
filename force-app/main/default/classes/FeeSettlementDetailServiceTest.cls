@isTest
private class FeeSettlementDetailServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create test account
        Account testAccount = TestDataFactory.makeAccount('Test Account for FeeSettlementDetail');

        // Create test opportunity
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert testOpp;

        // Create PaymentPlan
        PaymentPlan__c plan = new PaymentPlan__c(
            Opportunity__c = testOpp.Id,
            Version_Number__c = 1,
            Version_Status__c = 'Active'
        );
        insert plan;

        // Create Payment Schedule Items
        List<Payment_Schedule_Item__c> items = new List<Payment_Schedule_Item__c>();
        for (Integer i = 1; i <= 3; i++) {
            items.add(new Payment_Schedule_Item__c(
                Payment_Plan__c = plan.Id,
                Payment_Number__c = i,
                Payment_Date__c = Date.today().addDays(i * 7),
                Total_Payment__c = 150.00,
                Banking_Fee_Amount__c = 10.00,
                Status__c = 'Scheduled'
            ));
        }
        insert items;
    }

    @isTest
    static void testCreateBankingFeeDetails() {
        // Get test schedule items
        List<Payment_Schedule_Item__c> items = [
            SELECT Id, Banking_Fee_Amount__c
            FROM Payment_Schedule_Item__c
            ORDER BY Payment_Number__c
        ];
        System.assertEquals(3, items.size(), 'Should have 3 schedule items');

        Test.startTest();
        List<Fee_Settlement_Detail__c> feeDetails = FeeSettlementDetailService.createBankingFeeDetails(items);
        Test.stopTest();

        // Verify results
        System.assertEquals(3, feeDetails.size(), 'Should create 3 fee detail records');

        for (Fee_Settlement_Detail__c fsd : feeDetails) {
            System.assertEquals(FeeSettlementDetailService.FEE_TYPE_BANKING, fsd.Type__c, 'Type should be Banking Fee');
            System.assertEquals(10.00, fsd.Amount__c, 'Amount should be 10.00');
            System.assertNotEquals(null, fsd.Payment_Schedule_Item__c, 'Should have parent PSI reference');
        }
    }

    @isTest
    static void testCreateBankingFeeDetailsEmpty() {
        Test.startTest();
        List<Fee_Settlement_Detail__c> result = FeeSettlementDetailService.createBankingFeeDetails(
            new List<Payment_Schedule_Item__c>()
        );
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty list for empty input');
    }

    @isTest
    static void testCreateBankingFeeDetailsNull() {
        Test.startTest();
        List<Fee_Settlement_Detail__c> result = FeeSettlementDetailService.createBankingFeeDetails(null);
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty list for null input');
    }

    @isTest
    static void testCreateBankingFeeDetailsZeroAmount() {
        // Get test plan
        PaymentPlan__c plan = [SELECT Id FROM PaymentPlan__c LIMIT 1];

        // Create item with zero banking fee
        Payment_Schedule_Item__c itemWithZeroFee = new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id,
            Payment_Number__c = 99,
            Payment_Date__c = Date.today().addDays(100),
            Total_Payment__c = 150.00,
            Banking_Fee_Amount__c = 0,
            Status__c = 'Scheduled'
        );
        insert itemWithZeroFee;

        // Create item with null banking fee
        Payment_Schedule_Item__c itemWithNullFee = new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id,
            Payment_Number__c = 100,
            Payment_Date__c = Date.today().addDays(107),
            Total_Payment__c = 150.00,
            Banking_Fee_Amount__c = null,
            Status__c = 'Scheduled'
        );
        insert itemWithNullFee;

        List<Payment_Schedule_Item__c> itemsWithNoFee = new List<Payment_Schedule_Item__c>{
            itemWithZeroFee, itemWithNullFee
        };

        Test.startTest();
        List<Fee_Settlement_Detail__c> feeDetails = FeeSettlementDetailService.createBankingFeeDetails(itemsWithNoFee);
        Test.stopTest();

        System.assertEquals(0, feeDetails.size(), 'Should not create fee details for zero/null amounts');
    }

    @isTest
    static void testGetBankingFeesByScheduleItemIds() {
        // Get test schedule items
        List<Payment_Schedule_Item__c> items = [SELECT Id FROM Payment_Schedule_Item__c];
        Set<Id> itemIds = new Set<Id>();
        for (Payment_Schedule_Item__c item : items) {
            itemIds.add(item.Id);
        }

        // Create Fee_Settlement_Detail__c records
        List<Fee_Settlement_Detail__c> feeDetails = new List<Fee_Settlement_Detail__c>();
        Integer index = 0;
        for (Payment_Schedule_Item__c item : items) {
            feeDetails.add(new Fee_Settlement_Detail__c(
                Payment_Schedule_Item__c = item.Id,
                Type__c = FeeSettlementDetailService.FEE_TYPE_BANKING,
                Amount__c = 10.00 + index
            ));
            index++;
        }
        insert feeDetails;

        Test.startTest();
        Map<Id, Decimal> result = FeeSettlementDetailService.getBankingFeesByScheduleItemIds(itemIds);
        Test.stopTest();

        System.assertEquals(3, result.size(), 'Should return 3 entries');

        for (Id itemId : itemIds) {
            System.assert(result.containsKey(itemId), 'Should have entry for each PSI');
            System.assertNotEquals(null, result.get(itemId), 'Amount should not be null');
        }
    }

    @isTest
    static void testGetBankingFeesByScheduleItemIdsEmpty() {
        Test.startTest();
        Map<Id, Decimal> result = FeeSettlementDetailService.getBankingFeesByScheduleItemIds(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty map for empty input');
    }

    @isTest
    static void testGetBankingFeesByScheduleItemIdsNull() {
        Test.startTest();
        Map<Id, Decimal> result = FeeSettlementDetailService.getBankingFeesByScheduleItemIds(null);
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty map for null input');
    }

    @isTest
    static void testGetBankingFeesByScheduleItemIdsNoFeeDetails() {
        // Get test schedule items (no Fee_Settlement_Detail__c records exist)
        List<Payment_Schedule_Item__c> items = [SELECT Id FROM Payment_Schedule_Item__c];
        Set<Id> itemIds = new Set<Id>();
        for (Payment_Schedule_Item__c item : items) {
            itemIds.add(item.Id);
        }

        Test.startTest();
        Map<Id, Decimal> result = FeeSettlementDetailService.getBankingFeesByScheduleItemIds(itemIds);
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty map when no fee details exist');
    }

    @isTest
    static void testUpsertBankingFeeDetailCreate() {
        // Get a schedule item that doesn't have a fee detail
        Payment_Schedule_Item__c item = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        Test.startTest();
        Fee_Settlement_Detail__c result = FeeSettlementDetailService.upsertBankingFeeDetail(item.Id, 15.00);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a fee detail record');
        System.assertEquals(item.Id, result.Payment_Schedule_Item__c, 'Should reference the correct PSI');
        System.assertEquals(FeeSettlementDetailService.FEE_TYPE_BANKING, result.Type__c, 'Type should be Banking Fee');
        System.assertEquals(15.00, result.Amount__c, 'Amount should be 15.00');
        System.assertEquals(null, result.Id, 'Should be a new record (no Id yet)');
    }

    @isTest
    static void testUpsertBankingFeeDetailUpdate() {
        // Get a schedule item
        Payment_Schedule_Item__c item = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        // Create existing fee detail
        Fee_Settlement_Detail__c existing = new Fee_Settlement_Detail__c(
            Payment_Schedule_Item__c = item.Id,
            Type__c = FeeSettlementDetailService.FEE_TYPE_BANKING,
            Amount__c = 10.00
        );
        insert existing;

        Test.startTest();
        Fee_Settlement_Detail__c result = FeeSettlementDetailService.upsertBankingFeeDetail(item.Id, 25.00);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a fee detail record');
        System.assertEquals(existing.Id, result.Id, 'Should be the same record');
        System.assertEquals(25.00, result.Amount__c, 'Amount should be updated to 25.00');
    }

    @isTest
    static void testUpsertBankingFeeDetailNullId() {
        Test.startTest();
        Fee_Settlement_Detail__c result = FeeSettlementDetailService.upsertBankingFeeDetail(null, 15.00);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for null PSI Id');
    }

    @isTest
    static void testUpsertBankingFeeDetailZeroAmount() {
        // Get a schedule item that doesn't have a fee detail
        Payment_Schedule_Item__c item = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        Test.startTest();
        Fee_Settlement_Detail__c result = FeeSettlementDetailService.upsertBankingFeeDetail(item.Id, 0);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for zero amount when no existing record');
    }

    @isTest
    static void testConstantValue() {
        System.assertEquals('Banking Fee', FeeSettlementDetailService.FEE_TYPE_BANKING,
            'FEE_TYPE_BANKING constant should be "Banking Fee"');
    }
}
