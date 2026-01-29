@isTest
private class DeleteTwilioLogsBatchTest {

    @isTest
    static void testBatchExecution() {
        // Create test records
        List<TwilioSF__Log__c> testLogs = new List<TwilioSF__Log__c>();
        for (Integer i = 0; i < 10; i++) {
            testLogs.add(new TwilioSF__Log__c());
        }
        insert testLogs;

        // Verify records were created
        System.assertEquals(10, [SELECT COUNT() FROM TwilioSF__Log__c]);

        Test.startTest();
        DeleteTwilioLogsBatch batch = new DeleteTwilioLogsBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Verify records were deleted
        System.assertEquals(0, [SELECT COUNT() FROM TwilioSF__Log__c]);
    }

    @isTest
    static void testBatchWithNoRecords() {
        // Test with no records
        Test.startTest();
        DeleteTwilioLogsBatch batch = new DeleteTwilioLogsBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM TwilioSF__Log__c]);
    }
}