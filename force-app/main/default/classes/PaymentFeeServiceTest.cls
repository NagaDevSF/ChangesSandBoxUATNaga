@isTest
private class PaymentFeeServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create Account
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Create Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Create Payment Plan
        PaymentPlan__c plan = new PaymentPlan__c(
            Opportunity__c = opp.Id,
            Is_Active__c = true,
            Status__c = 'Active',
            Version_Number__c = 1
        );
        insert plan;

        // Create Payment Schedule Items
        List<Payment_Schedule_Item__c> items = new List<Payment_Schedule_Item__c>();
        for (Integer i = 0; i < 3; i++) {
            items.add(new Payment_Schedule_Item__c(
                Payment_Plan__c = plan.Id,
                Payment_Date__c = Date.today().addDays(i * 7),
                Total_Payment__c = 100,
                Status__c = 'Scheduled',
                Payment_Number__c = i + 1,
                Banking_Fee_Amount__c = 5,
                Program_Fee_Amount__c = 10,
                Setup_Fee_Amount__c = 15
            ));
        }
        insert items;
    }

    // ============ createFeeRecordsForItem Tests ============

    @isTest
    static void testCreateFeeRecordsForItem_NullPsi() {
        List<Payment_Fee__c> result = PaymentFeeService.createFeeRecordsForItem(null, 10, 20, 30);
        System.assertEquals(0, result.size(), 'Should return empty list for null PSI');
    }

    @isTest
    static void testCreateFeeRecordsForItem_PsiWithoutId() {
        Payment_Schedule_Item__c psi = new Payment_Schedule_Item__c();
        List<Payment_Fee__c> result = PaymentFeeService.createFeeRecordsForItem(psi, 10, 20, 30);
        System.assertEquals(0, result.size(), 'Should return empty list for PSI without Id');
    }

    @isTest
    static void testCreateFeeRecordsForItem_ValidPsi() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        Test.startTest();
        List<Payment_Fee__c> result = PaymentFeeService.createFeeRecordsForItem(psi, 10, 20, 30);
        Test.stopTest();

        System.assertEquals(3, result.size(), 'Should create 3 fee records');

        Map<String, Decimal> feeAmounts = new Map<String, Decimal>();
        for (Payment_Fee__c fee : result) {
            feeAmounts.put(fee.Type__c, fee.Amount__c);
            System.assertEquals(psi.Id, fee.Payment_Schedule_Item__c, 'Fee should be linked to PSI');
        }

        System.assertEquals(10, feeAmounts.get(PaymentFeeService.FEE_TYPE_BANKING), 'Banking fee should be 10');
        System.assertEquals(20, feeAmounts.get(PaymentFeeService.FEE_TYPE_PROGRAM), 'Program fee should be 20');
        System.assertEquals(30, feeAmounts.get(PaymentFeeService.FEE_TYPE_SETUP), 'Setup fee should be 30');
    }

    @isTest
    static void testCreateFeeRecordsForItem_NullAmounts() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        Test.startTest();
        List<Payment_Fee__c> result = PaymentFeeService.createFeeRecordsForItem(psi, null, null, null);
        Test.stopTest();

        System.assertEquals(3, result.size(), 'Should create 3 fee records even with null amounts');
        for (Payment_Fee__c fee : result) {
            System.assertEquals(0, fee.Amount__c, 'Null amounts should default to 0');
        }
    }

    // ============ createFeeRecordsForItems Tests ============

    @isTest
    static void testCreateFeeRecordsForItems_NullInputs() {
        List<Payment_Fee__c> result1 = PaymentFeeService.createFeeRecordsForItems(null, null);
        System.assertEquals(0, result1.size(), 'Should return empty list for null items');

        List<Payment_Fee__c> result2 = PaymentFeeService.createFeeRecordsForItems(new List<Payment_Schedule_Item__c>(), null);
        System.assertEquals(0, result2.size(), 'Should return empty list for empty items');

        List<Payment_Schedule_Item__c> items = [SELECT Id FROM Payment_Schedule_Item__c];
        List<Payment_Fee__c> result3 = PaymentFeeService.createFeeRecordsForItems(items, null);
        System.assertEquals(0, result3.size(), 'Should return empty list for null wrapper map');
    }

    @isTest
    static void testCreateFeeRecordsForItems_ValidInputs() {
        List<Payment_Schedule_Item__c> items = [SELECT Id FROM Payment_Schedule_Item__c];

        Map<Id, PaymentPlanEditorController.ScheduleItemWrapper> wrapperMap = new Map<Id, PaymentPlanEditorController.ScheduleItemWrapper>();
        for (Payment_Schedule_Item__c item : items) {
            PaymentPlanEditorController.ScheduleItemWrapper wrapper = new PaymentPlanEditorController.ScheduleItemWrapper();
            wrapper.id = item.Id;
            wrapper.bankingFee = 5;
            wrapper.programFee = 10;
            wrapper.setupFee = 15;
            wrapperMap.put(item.Id, wrapper);
        }

        Test.startTest();
        List<Payment_Fee__c> result = PaymentFeeService.createFeeRecordsForItems(items, wrapperMap);
        Test.stopTest();

        System.assertEquals(items.size() * 3, result.size(), 'Should create 3 fees per item');
    }

    @isTest
    static void testCreateFeeRecordsForItems_ItemNotInWrapperMap() {
        List<Payment_Schedule_Item__c> items = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 2];

        // Only add first item to wrapper map
        Map<Id, PaymentPlanEditorController.ScheduleItemWrapper> wrapperMap = new Map<Id, PaymentPlanEditorController.ScheduleItemWrapper>();
        PaymentPlanEditorController.ScheduleItemWrapper wrapper = new PaymentPlanEditorController.ScheduleItemWrapper();
        wrapper.id = items[0].Id;
        wrapper.bankingFee = 5;
        wrapper.programFee = 10;
        wrapper.setupFee = 15;
        wrapperMap.put(items[0].Id, wrapper);

        Test.startTest();
        List<Payment_Fee__c> result = PaymentFeeService.createFeeRecordsForItems(items, wrapperMap);
        Test.stopTest();

        System.assertEquals(3, result.size(), 'Should only create fees for items in wrapper map');
    }

    // ============ getFeesByScheduleItemIds Tests ============

    @isTest
    static void testGetFeesByScheduleItemIds_NullAndEmpty() {
        Map<Id, Map<String, Payment_Fee__c>> result1 = PaymentFeeService.getFeesByScheduleItemIds(null);
        System.assertEquals(0, result1.size(), 'Should return empty map for null');

        Map<Id, Map<String, Payment_Fee__c>> result2 = PaymentFeeService.getFeesByScheduleItemIds(new Set<Id>());
        System.assertEquals(0, result2.size(), 'Should return empty map for empty set');
    }

    @isTest
    static void testGetFeesByScheduleItemIds_WithFees() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        // Create fee records
        List<Payment_Fee__c> fees = new List<Payment_Fee__c>{
            new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id, Type__c = PaymentFeeService.FEE_TYPE_BANKING, Amount__c = 5),
            new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id, Type__c = PaymentFeeService.FEE_TYPE_PROGRAM, Amount__c = 10),
            new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id, Type__c = PaymentFeeService.FEE_TYPE_SETUP, Amount__c = 15)
        };
        insert fees;

        Test.startTest();
        Map<Id, Map<String, Payment_Fee__c>> result = PaymentFeeService.getFeesByScheduleItemIds(new Set<Id>{ psi.Id });
        Test.stopTest();

        System.assert(result.containsKey(psi.Id), 'Should contain PSI Id');
        System.assertEquals(3, result.get(psi.Id).size(), 'Should have 3 fee types');
        System.assertEquals(5, result.get(psi.Id).get(PaymentFeeService.FEE_TYPE_BANKING).Amount__c, 'Banking fee should be 5');
    }

    @isTest
    static void testGetFeesByScheduleItemIds_NoFees() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        Test.startTest();
        Map<Id, Map<String, Payment_Fee__c>> result = PaymentFeeService.getFeesByScheduleItemIds(new Set<Id>{ psi.Id });
        Test.stopTest();

        System.assert(result.containsKey(psi.Id), 'Should contain PSI Id');
        System.assertEquals(0, result.get(psi.Id).size(), 'Should have empty fee map');
    }

    // ============ upsertFeeRecords Tests ============

    @isTest
    static void testUpsertFeeRecords_NullId() {
        Test.startTest();
        PaymentFeeService.upsertFeeRecords(null, 10, 20, 30);
        Test.stopTest();
        // Should not throw exception
    }

    @isTest
    static void testUpsertFeeRecords_CreateNew() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        Test.startTest();
        PaymentFeeService.upsertFeeRecords(psi.Id, 10, 20, 30);
        Test.stopTest();

        List<Payment_Fee__c> fees = [SELECT Type__c, Amount__c FROM Payment_Fee__c WHERE Payment_Schedule_Item__c = :psi.Id];
        System.assertEquals(3, fees.size(), 'Should create 3 fee records');
    }

    @isTest
    static void testUpsertFeeRecords_UpdateExisting() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        // Create initial fees
        List<Payment_Fee__c> fees = new List<Payment_Fee__c>{
            new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id, Type__c = PaymentFeeService.FEE_TYPE_BANKING, Amount__c = 5),
            new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id, Type__c = PaymentFeeService.FEE_TYPE_PROGRAM, Amount__c = 10),
            new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id, Type__c = PaymentFeeService.FEE_TYPE_SETUP, Amount__c = 15)
        };
        insert fees;

        Test.startTest();
        PaymentFeeService.upsertFeeRecords(psi.Id, 100, 200, 300);
        Test.stopTest();

        List<Payment_Fee__c> updatedFees = [SELECT Type__c, Amount__c FROM Payment_Fee__c WHERE Payment_Schedule_Item__c = :psi.Id];
        System.assertEquals(3, updatedFees.size(), 'Should still have 3 fee records');

        Map<String, Decimal> amounts = new Map<String, Decimal>();
        for (Payment_Fee__c fee : updatedFees) {
            amounts.put(fee.Type__c, fee.Amount__c);
        }
        System.assertEquals(100, amounts.get(PaymentFeeService.FEE_TYPE_BANKING), 'Banking fee should be updated');
        System.assertEquals(200, amounts.get(PaymentFeeService.FEE_TYPE_PROGRAM), 'Program fee should be updated');
        System.assertEquals(300, amounts.get(PaymentFeeService.FEE_TYPE_SETUP), 'Setup fee should be updated');
    }

    // ============ bulkUpsertFeeRecords Tests ============

    @isTest
    static void testBulkUpsertFeeRecords_NullAndEmpty() {
        Test.startTest();
        PaymentFeeService.bulkUpsertFeeRecords(null, null);
        PaymentFeeService.bulkUpsertFeeRecords(new Set<Id>(), null);
        Test.stopTest();
        // Should not throw exception
    }

    @isTest
    static void testBulkUpsertFeeRecords_ValidInputs() {
        List<Payment_Schedule_Item__c> items = [SELECT Id FROM Payment_Schedule_Item__c];
        Set<Id> itemIds = new Set<Id>();
        Map<Id, PaymentPlanEditorController.ScheduleItemWrapper> wrapperMap = new Map<Id, PaymentPlanEditorController.ScheduleItemWrapper>();

        for (Payment_Schedule_Item__c item : items) {
            itemIds.add(item.Id);
            PaymentPlanEditorController.ScheduleItemWrapper wrapper = new PaymentPlanEditorController.ScheduleItemWrapper();
            wrapper.id = item.Id;
            wrapper.bankingFee = 5;
            wrapper.programFee = 10;
            wrapper.setupFee = 15;
            wrapperMap.put(item.Id, wrapper);
        }

        Test.startTest();
        PaymentFeeService.bulkUpsertFeeRecords(itemIds, wrapperMap);
        Test.stopTest();

        List<Payment_Fee__c> fees = [SELECT Id FROM Payment_Fee__c WHERE Payment_Schedule_Item__c IN :itemIds];
        System.assertEquals(items.size() * 3, fees.size(), 'Should create 3 fees per item');
    }

    @isTest
    static void testBulkUpsertFeeRecords_ItemNotInWrapperMap() {
        List<Payment_Schedule_Item__c> items = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 2];
        Set<Id> itemIds = new Set<Id>();
        for (Payment_Schedule_Item__c item : items) {
            itemIds.add(item.Id);
        }

        // Only add first item to wrapper map
        Map<Id, PaymentPlanEditorController.ScheduleItemWrapper> wrapperMap = new Map<Id, PaymentPlanEditorController.ScheduleItemWrapper>();
        PaymentPlanEditorController.ScheduleItemWrapper wrapper = new PaymentPlanEditorController.ScheduleItemWrapper();
        wrapper.id = items[0].Id;
        wrapper.bankingFee = 5;
        wrapper.programFee = 10;
        wrapper.setupFee = 15;
        wrapperMap.put(items[0].Id, wrapper);

        Test.startTest();
        PaymentFeeService.bulkUpsertFeeRecords(itemIds, wrapperMap);
        Test.stopTest();

        List<Payment_Fee__c> fees = [SELECT Id FROM Payment_Fee__c WHERE Payment_Schedule_Item__c IN :itemIds];
        System.assertEquals(3, fees.size(), 'Should only create fees for items in wrapper map');
    }

    // ============ deleteFeeRecords Tests ============

    @isTest
    static void testDeleteFeeRecords_NullAndEmpty() {
        Test.startTest();
        PaymentFeeService.deleteFeeRecords(null);
        PaymentFeeService.deleteFeeRecords(new Set<Id>());
        Test.stopTest();
        // Should not throw exception
    }

    @isTest
    static void testDeleteFeeRecords_ValidIds() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        // Create fee records
        List<Payment_Fee__c> fees = new List<Payment_Fee__c>{
            new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id, Type__c = PaymentFeeService.FEE_TYPE_BANKING, Amount__c = 5),
            new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id, Type__c = PaymentFeeService.FEE_TYPE_PROGRAM, Amount__c = 10),
            new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id, Type__c = PaymentFeeService.FEE_TYPE_SETUP, Amount__c = 15)
        };
        insert fees;

        System.assertEquals(3, [SELECT COUNT() FROM Payment_Fee__c WHERE Payment_Schedule_Item__c = :psi.Id], 'Should have 3 fees before delete');

        Test.startTest();
        PaymentFeeService.deleteFeeRecords(new Set<Id>{ psi.Id });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Payment_Fee__c WHERE Payment_Schedule_Item__c = :psi.Id], 'Should have 0 fees after delete');
    }

    // ============ createWireFeeRecord Tests ============

    @isTest
    static void testCreateWireFeeRecord_NullId() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            PaymentFeeService.createWireFeeRecord(null, PaymentFeeService.FEE_TYPE_WIRE, 100);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw exception for null ID');
    }

    @isTest
    static void testCreateWireFeeRecord_InvalidType() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            PaymentFeeService.createWireFeeRecord(psi.Id, 'Invalid Type', 100);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw exception for invalid type');
    }

    @isTest
    static void testCreateWireFeeRecord_BlankType() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            PaymentFeeService.createWireFeeRecord(psi.Id, '', 100);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw exception for blank type');
    }

    @isTest
    static void testCreateWireFeeRecord_ValidWireFee() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        Test.startTest();
        Id feeId = PaymentFeeService.createWireFeeRecord(psi.Id, PaymentFeeService.FEE_TYPE_WIRE, 100);
        Test.stopTest();

        System.assertNotEquals(null, feeId, 'Should return fee Id');

        Payment_Fee__c fee = [SELECT Type__c, Amount__c FROM Payment_Fee__c WHERE Id = :feeId];
        System.assertEquals(PaymentFeeService.FEE_TYPE_WIRE, fee.Type__c, 'Should be Wire Fee type');
        System.assertEquals(100, fee.Amount__c, 'Amount should be 100');
    }

    @isTest
    static void testCreateWireFeeRecord_WireReceivedFee() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        Test.startTest();
        Id feeId = PaymentFeeService.createWireFeeRecord(psi.Id, PaymentFeeService.FEE_TYPE_WIRE_RECEIVED, 200);
        Test.stopTest();

        Payment_Fee__c fee = [SELECT Type__c, Amount__c FROM Payment_Fee__c WHERE Id = :feeId];
        System.assertEquals(PaymentFeeService.FEE_TYPE_WIRE_RECEIVED, fee.Type__c, 'Should be Wire Received Fee type');
        System.assertEquals(200, fee.Amount__c, 'Amount should be 200');
    }

    @isTest
    static void testCreateWireFeeRecord_NullAmount() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        Test.startTest();
        Id feeId = PaymentFeeService.createWireFeeRecord(psi.Id, PaymentFeeService.FEE_TYPE_WIRE, null);
        Test.stopTest();

        Payment_Fee__c fee = [SELECT Amount__c FROM Payment_Fee__c WHERE Id = :feeId];
        System.assertEquals(0, fee.Amount__c, 'Null amount should default to 0');
    }

    // ============ getWireFeesByScheduleItemIds Tests ============

    @isTest
    static void testGetWireFeesByScheduleItemIds_NullAndEmpty() {
        Map<Id, List<Payment_Fee__c>> result1 = PaymentFeeService.getWireFeesByScheduleItemIds(null);
        System.assertEquals(0, result1.size(), 'Should return empty map for null');

        Map<Id, List<Payment_Fee__c>> result2 = PaymentFeeService.getWireFeesByScheduleItemIds(new Set<Id>());
        System.assertEquals(0, result2.size(), 'Should return empty map for empty set');
    }

    @isTest
    static void testGetWireFeesByScheduleItemIds_WithWireFees() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        // Create wire fee records
        List<Payment_Fee__c> fees = new List<Payment_Fee__c>{
            new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id, Type__c = PaymentFeeService.FEE_TYPE_WIRE, Amount__c = 100),
            new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id, Type__c = PaymentFeeService.FEE_TYPE_WIRE_RECEIVED, Amount__c = 200)
        };
        insert fees;

        Test.startTest();
        Map<Id, List<Payment_Fee__c>> result = PaymentFeeService.getWireFeesByScheduleItemIds(new Set<Id>{ psi.Id });
        Test.stopTest();

        System.assert(result.containsKey(psi.Id), 'Should contain PSI Id');
        System.assertEquals(2, result.get(psi.Id).size(), 'Should have 2 wire fees');
    }

    @isTest
    static void testGetWireFeesByScheduleItemIds_NoWireFees() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        Test.startTest();
        Map<Id, List<Payment_Fee__c>> result = PaymentFeeService.getWireFeesByScheduleItemIds(new Set<Id>{ psi.Id });
        Test.stopTest();

        System.assert(result.containsKey(psi.Id), 'Should contain PSI Id');
        System.assertEquals(0, result.get(psi.Id).size(), 'Should have empty wire fee list');
    }

    // ============ deleteWireFeeRecords Tests ============

    @isTest
    static void testDeleteWireFeeRecords_NullAndEmpty() {
        Test.startTest();
        PaymentFeeService.deleteWireFeeRecords(null);
        PaymentFeeService.deleteWireFeeRecords(new Set<Id>());
        Test.stopTest();
        // Should not throw exception
    }

    @isTest
    static void testDeleteWireFeeRecords_ValidIds() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        // Create wire fee records
        List<Payment_Fee__c> fees = new List<Payment_Fee__c>{
            new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id, Type__c = PaymentFeeService.FEE_TYPE_WIRE, Amount__c = 100),
            new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id, Type__c = PaymentFeeService.FEE_TYPE_WIRE_RECEIVED, Amount__c = 200)
        };
        insert fees;

        System.assertEquals(2, [SELECT COUNT() FROM Payment_Fee__c WHERE Payment_Schedule_Item__c = :psi.Id AND Type__c IN :PaymentFeeService.WIRE_FEE_TYPES], 'Should have 2 wire fees before delete');

        Test.startTest();
        PaymentFeeService.deleteWireFeeRecords(new Set<Id>{ psi.Id });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Payment_Fee__c WHERE Payment_Schedule_Item__c = :psi.Id AND Type__c IN :PaymentFeeService.WIRE_FEE_TYPES], 'Should have 0 wire fees after delete');
    }

    // ============ deleteWireFeeById Tests ============

    @isTest
    static void testDeleteWireFeeById_NullId() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            PaymentFeeService.deleteWireFeeById(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw exception for null ID');
    }

    @isTest
    static void testDeleteWireFeeById_NonWireFee() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        // Create non-wire fee record
        Payment_Fee__c fee = new Payment_Fee__c(
            Payment_Schedule_Item__c = psi.Id,
            Type__c = PaymentFeeService.FEE_TYPE_BANKING,
            Amount__c = 5
        );
        insert fee;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            PaymentFeeService.deleteWireFeeById(fee.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw exception for non-wire fee');
    }

    @isTest
    static void testDeleteWireFeeById_ValidWireFee() {
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        // Create wire fee record
        Payment_Fee__c fee = new Payment_Fee__c(
            Payment_Schedule_Item__c = psi.Id,
            Type__c = PaymentFeeService.FEE_TYPE_WIRE,
            Amount__c = 100
        );
        insert fee;

        Test.startTest();
        PaymentFeeService.deleteWireFeeById(fee.Id);
        Test.stopTest();

        List<Payment_Fee__c> remaining = [SELECT Id FROM Payment_Fee__c WHERE Id = :fee.Id];
        System.assertEquals(0, remaining.size(), 'Wire fee should be deleted');
    }

    // ============ Constants Tests ============

    @isTest
    static void testFeeTypeConstants() {
        System.assertEquals('Banking Fee', PaymentFeeService.FEE_TYPE_BANKING);
        System.assertEquals('Program Fee', PaymentFeeService.FEE_TYPE_PROGRAM);
        System.assertEquals('Setup Fee', PaymentFeeService.FEE_TYPE_SETUP);
        System.assertEquals('Wire Fee', PaymentFeeService.FEE_TYPE_WIRE);
        System.assertEquals('Wire Received Fee', PaymentFeeService.FEE_TYPE_WIRE_RECEIVED);

        System.assertEquals(3, PaymentFeeService.SCHEDULE_ITEM_FEE_TYPES.size());
        System.assert(PaymentFeeService.SCHEDULE_ITEM_FEE_TYPES.contains('Banking Fee'));
        System.assert(PaymentFeeService.SCHEDULE_ITEM_FEE_TYPES.contains('Program Fee'));
        System.assert(PaymentFeeService.SCHEDULE_ITEM_FEE_TYPES.contains('Setup Fee'));

        System.assertEquals(2, PaymentFeeService.WIRE_FEE_TYPES.size());
        System.assert(PaymentFeeService.WIRE_FEE_TYPES.contains('Wire Fee'));
        System.assert(PaymentFeeService.WIRE_FEE_TYPES.contains('Wire Received Fee'));
    }
}