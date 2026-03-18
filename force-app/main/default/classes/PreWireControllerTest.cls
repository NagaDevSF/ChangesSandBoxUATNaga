@IsTest
private class PreWireControllerTest {

    // ==================================================================================
    // TEST SETUP
    // ==================================================================================

    @TestSetup
    static void setupTestData() {
        Account acc = new Account(Name = 'Test Business Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Create a few Pre Wire records for testing
        List<Pre_Wire__c> wires = new List<Pre_Wire__c>();
        for (Integer i = 1; i <= 5; i++) {
            wires.add(new Pre_Wire__c(
                Opportunity__c = opp.Id,
                Date_Value__c = Date.today().addDays(i),
                Amount__c = 1000.00 * i
            ));
        }
        insert wires;
    }

    // ==================================================================================
    // HELPER METHODS
    // ==================================================================================

    private static Opportunity getTestOpportunity() {
        return [SELECT Id, AccountId FROM Opportunity WHERE Name = 'Test Opportunity' LIMIT 1];
    }

    private static List<Pre_Wire__c> getTestWires() {
        return [SELECT Id, Opportunity__c, Date_Value__c, Amount__c FROM Pre_Wire__c ORDER BY Date_Value__c ASC];
    }

    private static String buildInputJson(String id, String opportunityId, Date dateValue, Decimal amount) {
        Map<String, Object> input = new Map<String, Object>();
        if (id != null) {
            input.put('id', id);
        }
        input.put('opportunityId', opportunityId);
        input.put('dateValue', dateValue);
        input.put('amount', amount);
        return JSON.serialize(input);
    }

    // ==================================================================================
    // HAPPY PATH TESTS
    // ==================================================================================

    @IsTest
    static void testGetPreWireContext_Success() {
        Opportunity opp = getTestOpportunity();

        Test.startTest();
        PreWireController.PreWireContext ctx = PreWireController.getPreWireContext(opp.Id);
        Test.stopTest();

        Assert.areEqual(opp.Id, ctx.opportunityId, 'Should return the correct Opportunity ID');
        Assert.areEqual('Test Business Account', ctx.accountName, 'Should return the Account Name');
        Assert.areEqual(5, ctx.preWires.size(), 'Should return 5 pre wire records');

        // Verify sort order by date ascending
        for (Integer i = 0; i < ctx.preWires.size() - 1; i++) {
            Assert.isTrue(
                ctx.preWires[i].dateValue <= ctx.preWires[i + 1].dateValue,
                'Pre wires should be sorted by Date Value ascending'
            );
        }
    }

    @IsTest
    static void testCreatePreWire_Success() {
        Opportunity opp = getTestOpportunity();
        Date testDate = Date.today().addDays(10);
        Decimal testAmount = 2500.50;

        String inputJson = buildInputJson(null, opp.Id, testDate, testAmount);

        Test.startTest();
        PreWireController.PreWireRecord result = PreWireController.createPreWire(inputJson);
        Test.stopTest();

        Assert.isNotNull(result.id, 'Created record should have an ID');
        Assert.isNotNull(result.name, 'Created record should have an auto-number name');
        Assert.areEqual(opp.Id, result.opportunityId, 'Should be linked to the correct Opportunity');
        Assert.areEqual(testDate, result.dateValue, 'Should have the correct Date Value');
        Assert.areEqual(testAmount, result.amount, 'Should have the correct Amount');
        Assert.areEqual('Test Business Account', result.businessName, 'Should return the Account Name');

        // Verify the record was actually persisted
        List<Pre_Wire__c> wires = [SELECT Id FROM Pre_Wire__c WHERE Id = :result.id];
        Assert.areEqual(1, wires.size(), 'Record should exist in the database');
    }

    @IsTest
    static void testUpdatePreWire_Success() {
        List<Pre_Wire__c> wires = getTestWires();
        Pre_Wire__c wire = wires[0];
        Opportunity opp = getTestOpportunity();

        Date newDate = Date.today().addDays(99);
        Decimal newAmount = 7777.77;
        String inputJson = buildInputJson(wire.Id, opp.Id, newDate, newAmount);

        Test.startTest();
        PreWireController.PreWireRecord result = PreWireController.updatePreWire(inputJson);
        Test.stopTest();

        Assert.areEqual(wire.Id, result.id, 'Should return the same record ID');
        Assert.areEqual(newDate, result.dateValue, 'Should have the updated Date Value');
        Assert.areEqual(newAmount, result.amount, 'Should have the updated Amount');
        Assert.areEqual('Test Business Account', result.businessName, 'Should return the Account Name');

        // Verify in database
        Pre_Wire__c updated = [SELECT Date_Value__c, Amount__c FROM Pre_Wire__c WHERE Id = :wire.Id];
        Assert.areEqual(newDate, updated.Date_Value__c, 'Database should have updated Date Value');
        Assert.areEqual(newAmount, updated.Amount__c, 'Database should have updated Amount');
    }

    @IsTest
    static void testDeletePreWire_Success() {
        List<Pre_Wire__c> wires = getTestWires();
        String wireId = wires[0].Id;
        Integer countBefore = wires.size();

        Test.startTest();
        PreWireController.deletePreWire(wireId);
        Test.stopTest();

        List<Pre_Wire__c> remaining = [SELECT Id FROM Pre_Wire__c];
        Assert.areEqual(countBefore - 1, remaining.size(), 'Should have one fewer Pre Wire record');

        List<Pre_Wire__c> deleted = [SELECT Id FROM Pre_Wire__c WHERE Id = :wireId];
        Assert.areEqual(0, deleted.size(), 'Deleted record should no longer exist');
    }

    // ==================================================================================
    // NO DATA / NULL INPUT TESTS
    // ==================================================================================

    @IsTest
    static void testGetPreWireContext_BlankId() {
        Test.startTest();
        try {
            PreWireController.getPreWireContext('');
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Opportunity ID is required'), 'Should indicate ID is required');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetPreWireContext_NullId() {
        Test.startTest();
        try {
            PreWireController.getPreWireContext(null);
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Opportunity ID is required'), 'Should indicate ID is required');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreatePreWire_BlankInput() {
        Test.startTest();
        try {
            PreWireController.createPreWire('');
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Input data is required'), 'Should indicate input is required');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreatePreWire_NullInput() {
        Test.startTest();
        try {
            PreWireController.createPreWire(null);
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Input data is required'), 'Should indicate input is required');
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdatePreWire_BlankInput() {
        Test.startTest();
        try {
            PreWireController.updatePreWire('');
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Input data is required'), 'Should indicate input is required');
        }
        Test.stopTest();
    }

    @IsTest
    static void testDeletePreWire_BlankId() {
        Test.startTest();
        try {
            PreWireController.deletePreWire('');
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Pre Wire ID is required'), 'Should indicate ID is required');
        }
        Test.stopTest();
    }

    // ==================================================================================
    // ERROR HANDLING TESTS
    // ==================================================================================

    @IsTest
    static void testGetPreWireContext_InvalidOpportunityId() {
        // Use a fabricated ID that doesn't match any Opportunity
        String fakeOppId = Opportunity.SObjectType.getDescribe().getKeyPrefix() + '000000000000';

        Test.startTest();
        try {
            PreWireController.getPreWireContext(fakeOppId);
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Opportunity not found'), 'Should indicate Opportunity not found');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreatePreWire_InvalidJson() {
        Test.startTest();
        try {
            PreWireController.createPreWire('this is not json');
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Invalid input data'), 'Should indicate invalid input');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreatePreWire_MissingOpportunityId() {
        String inputJson = buildInputJson(null, null, Date.today(), 500.00);

        Test.startTest();
        try {
            PreWireController.createPreWire(inputJson);
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Opportunity is required'), 'Should indicate Opportunity is required');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreatePreWire_MissingDate() {
        Opportunity opp = getTestOpportunity();
        String inputJson = buildInputJson(null, opp.Id, null, 500.00);

        Test.startTest();
        try {
            PreWireController.createPreWire(inputJson);
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Date Value is required'), 'Should indicate Date is required');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreatePreWire_ZeroAmount() {
        Opportunity opp = getTestOpportunity();
        String inputJson = buildInputJson(null, opp.Id, Date.today(), 0);

        Test.startTest();
        try {
            PreWireController.createPreWire(inputJson);
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Amount must be greater than zero'), 'Should indicate invalid amount');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreatePreWire_NegativeAmount() {
        Opportunity opp = getTestOpportunity();
        String inputJson = buildInputJson(null, opp.Id, Date.today(), -100.00);

        Test.startTest();
        try {
            PreWireController.createPreWire(inputJson);
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Amount must be greater than zero'), 'Should indicate invalid amount');
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdatePreWire_MissingRecordId() {
        Opportunity opp = getTestOpportunity();
        String inputJson = buildInputJson(null, opp.Id, Date.today(), 500.00);

        Test.startTest();
        try {
            PreWireController.updatePreWire(inputJson);
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Pre Wire ID is required'), 'Should indicate record ID is required');
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdatePreWire_NonExistentRecord() {
        Opportunity opp = getTestOpportunity();
        String fakeId = Pre_Wire__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000';
        String inputJson = buildInputJson(fakeId, opp.Id, Date.today(), 500.00);

        Test.startTest();
        try {
            PreWireController.updatePreWire(inputJson);
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Pre Wire record not found'), 'Should indicate record not found');
        }
        Test.stopTest();
    }

    @IsTest
    static void testDeletePreWire_NonExistentRecord() {
        String fakeId = Pre_Wire__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000';

        Test.startTest();
        try {
            PreWireController.deletePreWire(fakeId);
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Pre Wire record not found'), 'Should indicate record not found');
        }
        Test.stopTest();
    }

    // ==================================================================================
    // BULK OPERATION TESTS
    // ==================================================================================

    @IsTest
    static void testGetPreWireContext_ManyRecords() {
        Opportunity opp = getTestOpportunity();

        // Create 200 additional Pre Wire records
        List<Pre_Wire__c> bulkWires = new List<Pre_Wire__c>();
        for (Integer i = 0; i < 200; i++) {
            bulkWires.add(new Pre_Wire__c(
                Opportunity__c = opp.Id,
                Date_Value__c = Date.today().addDays(i + 100),
                Amount__c = 100.00 + i
            ));
        }
        insert bulkWires;

        Test.startTest();
        PreWireController.PreWireContext ctx = PreWireController.getPreWireContext(opp.Id);
        Test.stopTest();

        // 5 from setup + 200 bulk = 205
        Assert.areEqual(205, ctx.preWires.size(), 'Should return all 205 pre wire records');
    }

    // ==================================================================================
    // EDGE CASE TESTS
    // ==================================================================================

    @IsTest
    static void testGetPreWireContext_OpportunityWithNoAccount() {
        // Create an Opportunity without an Account
        Opportunity oppNoAccount = new Opportunity(
            Name = 'No Account Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert oppNoAccount;

        Test.startTest();
        PreWireController.PreWireContext ctx = PreWireController.getPreWireContext(oppNoAccount.Id);
        Test.stopTest();

        Assert.areEqual('', ctx.accountName, 'Account name should be empty when no Account is linked');
        Assert.areEqual(0, ctx.preWires.size(), 'Should return no pre wire records');
    }

    @IsTest
    static void testGetPreWireContext_OpportunityWithNoWires() {
        // Create a fresh Opportunity with an Account but no Pre Wires
        Account acc = new Account(Name = 'Empty Wire Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Empty Wire Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Test.startTest();
        PreWireController.PreWireContext ctx = PreWireController.getPreWireContext(opp.Id);
        Test.stopTest();

        Assert.areEqual('Empty Wire Account', ctx.accountName, 'Should return the Account name');
        Assert.areEqual(0, ctx.preWires.size(), 'Should return no pre wire records');
    }

    @IsTest
    static void testCreatePreWire_LargeAmount() {
        Opportunity opp = getTestOpportunity();
        Decimal largeAmount = 9999999999999.99;
        String inputJson = buildInputJson(null, opp.Id, Date.today(), largeAmount);

        Test.startTest();
        PreWireController.PreWireRecord result = PreWireController.createPreWire(inputJson);
        Test.stopTest();

        Assert.areEqual(largeAmount, result.amount, 'Should handle large currency amounts');
    }

    @IsTest
    static void testCreatePreWire_SmallAmount() {
        Opportunity opp = getTestOpportunity();
        Decimal smallAmount = 0.01;
        String inputJson = buildInputJson(null, opp.Id, Date.today(), smallAmount);

        Test.startTest();
        PreWireController.PreWireRecord result = PreWireController.createPreWire(inputJson);
        Test.stopTest();

        Assert.areEqual(smallAmount, result.amount, 'Should handle minimum currency amounts');
    }

    @IsTest
    static void testUpdatePreWire_InvalidJson() {
        Test.startTest();
        try {
            PreWireController.updatePreWire('not valid json');
            Assert.fail('Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Invalid input data'), 'Should indicate invalid input');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateAndThenDelete() {
        Opportunity opp = getTestOpportunity();
        String inputJson = buildInputJson(null, opp.Id, Date.today().addDays(50), 999.99);

        Test.startTest();
        PreWireController.PreWireRecord created = PreWireController.createPreWire(inputJson);
        Assert.isNotNull(created.id, 'Record should be created');

        PreWireController.deletePreWire(created.id);
        Test.stopTest();

        List<Pre_Wire__c> remaining = [SELECT Id FROM Pre_Wire__c WHERE Id = :created.id];
        Assert.areEqual(0, remaining.size(), 'Deleted record should not exist');
    }
}
