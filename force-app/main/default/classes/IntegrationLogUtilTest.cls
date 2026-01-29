@isTest
private class IntegrationLogUtilTest {

    // Metadata API names used throughout tests
    private static final String SETTINGS_MDT = 'EPPS_Integration_Setting__mdt';
    private static final String OBJECT_MDT   = 'EPPS_Integration_Object__mdt';

    // Arbitrary test SObject for mapping. Using Account as valid real object
    private static Account testAcct;

    @TestSetup
    static void setupMetadata() {
        // Create Account test record
        testAcct = new Account(Name = 'Test Account');
        insert testAcct;
    }

    @isTest
    static void testSuccessLoggingWorks() {
        IntegrationLogUtil.clear(); // reset caches/logs

        // Arrange
        IntegrationLogUtil.LogInput input =
            IntegrationLogUtil.logBuilder()
                .settings(SETTINGS_MDT)
                .objectMeta(OBJECT_MDT)
                .record(testAcct.Id)
                .method('UnitTestClass.successTest')
                .request('TEST REQUEST')
                .response('TEST RESPONSE')
                .httpCode(200)
                .status(IntegrationLogUtil.LogStatus.Success)
                .build();

        // Act
        Integration_Log__c log = IntegrationLogUtil.createLog(input);
        IntegrationLogUtil.flush();

        // Assert
        System.assertNotEquals(null, log, 'Returned log should not be null');

        Integration_Log__c stored = [
            SELECT System__c, Method__c, Status__c,
                   HTTP_Response_Code__c, Request__c, Response__c, Account__c
            FROM Integration_Log__c LIMIT 1
        ];

        System.assertEquals('Workday', stored.System__c);
        System.assertEquals('UnitTestClass.successTest', stored.Method__c);
        System.assertEquals('Success', stored.Status__c);
        System.assertEquals('TEST REQUEST', stored.Request__c);
        System.assertEquals('TEST RESPONSE', stored.Response__c);
        System.assertEquals(testAcct.Id, stored.Account__c,
            'Record lookup should map dynamically using metadata');
    }

    @isTest
    static void testFailureLoggingFiltered() {
        IntegrationLogUtil.clear();

        // Arrange – failure scenario
        IntegrationLogUtil.LogInput input =
            IntegrationLogUtil.logBuilder()
                .settings(SETTINGS_MDT)
                .objectMeta(OBJECT_MDT)
                .record(testAcct.Id)
                .method('UnitTestClass.failureTest')
                .request('REQ')
                .response('ERR')
                .httpCode(500)
                .status(IntegrationLogUtil.LogStatus.Failure)
                .build();

        // Act
        Integration_Log__c log = IntegrationLogUtil.createLog(input);
        IntegrationLogUtil.flush();

        // Assert — failure logging disabled by metadata, so: NO INSERT
        System.assertEquals(null, log, 'Log creation should have been skipped');

        List<Integration_Log__c> logs = [
            SELECT Id FROM Integration_Log__c
        ];
        System.assertEquals(0, logs.size(),
            'No logs should be stored when Fail flag is OFF');
    }

    @isTest
    static void testCacheAndClear() {
        IntegrationLogUtil.clear();

        // Trigger cache population
        IntegrationLogUtil.LogInput input =
            IntegrationLogUtil.logBuilder()
                .settings(SETTINGS_MDT)
                .objectMeta(OBJECT_MDT)
                .record(testAcct.Id)
                .method('CacheTest')
                .request('REQ')
                .response('RESP')
                .httpCode(200)
                .status(IntegrationLogUtil.LogStatus.Success)
                .build();

        IntegrationLogUtil.createLog(input);

        // Call clear
        IntegrationLogUtil.clear();

        // Ensure no pending logs after clear
        IntegrationLogUtil.flush(); // Should not insert any records

        System.assertEquals(0,
            [SELECT COUNT() FROM Integration_Log__c],
            'No logs should be inserted after clearing');
    }
}