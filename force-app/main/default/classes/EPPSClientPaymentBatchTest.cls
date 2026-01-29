/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSClientPaymentBatchTest
 * Author          : Shell Black (Scott Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jan 27, 2026
 * Description     : This class provides full coverage for EPPSClientPaymentBatch
 *                   and partial coverage for EPPSIntegrationMethodsEnhanced and EPPSHelperMethods
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Scott Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

@isTest(testFor='ApexClass:EPPSClientPaymentBatch,ApexClass:EPPSIntegrationMethodsEnhanced,ApexClass:EPPSHelperMethods')
private class EPPSClientPaymentBatchTest {

    /**
     * Utility to calculate the same target date used by the batch
     */
    private static Date getTargetDate() {
        return EPPSHelperMethods.getDateAfterBusinessDays(2);
    }

    private static Payment_Schedule_Item__c createTestData() {

    	// Create an Account
        Account testAccount = TestDataFactory.makeAccount('Test Account');

        // Create an Opportunity that will qualify for approval
        Opportunity testOpp = TestDataFactory.makeOpp(testAccount.Id, 'Test Opportunity');
		testOpp.StageName = 'Build Plan';
		testOpp.Integrate_with_EPPS__c = true;
		update testOpp;

		// Create Payment Plan
		PaymentPlan__c testPP = TestDataFactory.makePaymentPlanForOpp(testOpp.Id, 5000, 300, 12);
		testPP.Status__c = EPPSHelperMethods.PAYMENT_PLAN_STATUS_ACTIVE;
		update testPP;

        Payment_Schedule_Item__c psi = new Payment_Schedule_Item__c(
            Payment_Plan__c = testPP.Id,
            Payment_Date__c = getTargetDate(),
            Status__c = EPPSHelperMethods.PAYMENT_SCHEDULE_ITEM_STATUS_SCHEDULED,
            Total_Payment__c = 100,
			Payment_Number__c = 1
        );
        
		insert psi;

        return psi;
    }

    /**
     * Covers execute(Database.BatchableContext, scope)
     */
    @IsTest
    static void testBatchExecutionSuccess() {

        Test.setMock(HttpCalloutMock.class, new EPPSAddEFTMock('10004', '3044527'));

        Payment_Schedule_Item__c psi = createTestData();

        Test.startTest();
        Database.executeBatch(new EPPSClientPaymentBatch(), 1);
        Test.stopTest();

        Payment_Schedule_Item__c updatedPsi = [
            SELECT Status__c,
                   EPPS_EFT_Transaction_Id__c,
                   Last_EPPS_Integration__c
            FROM Payment_Schedule_Item__c
            WHERE Id = :psi.Id
        ];

        System.assertEquals(
            EPPSHelperMethods.PSI_STATUS_SENT_TO_EPPS,
            updatedPsi.Status__c,
            'PSI should be marked as sent'
        );
        System.assertEquals(
            '3044527',
            updatedPsi.EPPS_EFT_Transaction_Id__c
        );
        System.assertNotEquals(null, updatedPsi.Last_EPPS_Integration__c);
    }

    /**
     * Covers Schedulable.execute()
     */
    @IsTest
    static void testScheduledExecution() {

        Test.startTest();

        String jobId = System.schedule('EPPS Client Payment Batch Job', '0 0 0 1 1 ? 2099', new EPPSClientPaymentBatch());
        
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job ID should be returned');

        CronTrigger ct = [SELECT CronJobDetail.Name, CronJobDetail.JobType,
						State FROM CronTrigger WHERE Id = :jobId];

        System.assertEquals('EPPS Client Payment Batch Job', ct.CronJobDetail.Name);
        System.assertEquals('WAITING', ct.State);
    }

    @IsTest
    static void testBatch_ForcesCatchBlock() {

        // 🔥 Force AddEFT() to throw → hits catch(Exception e)
        Test.setMock(HttpCalloutMock.class, new EPPSAddEFTMock());

        Payment_Schedule_Item__c psi = createTestData();

        // ---- Execute batch ----
        Test.startTest();
        Database.executeBatch(new EPPSClientPaymentBatch(), 1);
        Test.stopTest();

        // ---- Assertions ----
        Payment_Schedule_Item__c updatedPsi = [
        SELECT Status__c, Last_EPPS_Integration__c
        FROM Payment_Schedule_Item__c
        WHERE Id = :psi.Id
        ];

        Assert.areEqual(
        EPPSHelperMethods.PSI_STATUS_FAILED_TO_EPPS,
        updatedPsi.Status__c,
        'PSI should be marked failed when AddEFT throws an exception'
        );

        System.assertNotEquals(
        null,
        updatedPsi.Last_EPPS_Integration__c,
        'Last_EPPS_Integration__c should be set even on failure'
        );
    }
}