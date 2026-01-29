/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSPaymentFeeBatchTest
 * Author          : Shell Black (Scott Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jan 27, 2026
 * Description     : This class provides full coverage for EPPSPaymentFeeBatch and EPPSPaymentFeeBatchHelper
 *                   and partial coverage for EPPSIntegrationMethodsEnhanced and EPPSHelperMethods
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Scott Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
@isTest(testFor='ApexClass:EPPSPaymentFeeBatch,ApexClass:EPPSPaymentFeeBatchHelper,ApexClass:EPPSIntegrationMethodsEnhanced,ApexClass:EPPSHelperMethods')
private class EPPSPaymentFeeBatchTest {

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
		testOpp.Integrate_with_EPPS__c = true; // temporary control to limit API interactions with EPPS
		update testOpp;

		// Create Payment Plan
		PaymentPlan__c testPP = TestDataFactory.makePaymentPlanForOpp(testOpp.Id, 5000, 300, 12);
		testPP.Status__c = EPPSHelperMethods.PAYMENT_PLAN_STATUS_ACTIVE;
		update testPP;

        Payment_Schedule_Item__c psi = new Payment_Schedule_Item__c(
            Payment_Plan__c = testPP.Id,
            Payment_Date__c = getTargetDate(),
			EPPS_EFT_Status__c = EPPSHelperMethods.EPPS_SETTLED_STATUS[0],
            Status__c = EPPSHelperMethods.PAYMENT_SCHEDULE_ITEM_STATUS_SCHEDULED,
            Total_Payment__c = 100,
			Payment_Number__c = 1
        );
        
		insert psi;

		// create payment fees
		Payment_Fee__c pf1 = new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id);
		pf1.Type__c = 'Banking Fee';
		pf1.Amount__c = 100;

		Payment_Fee__c pf2 = new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id);
		pf2.Type__c = 'Commission Fee';
		pf2.Amount__c = 200;

		Payment_Fee__c pf3 = new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id);
		pf3.Type__c = 'Settlement Fee';
		pf3.Amount__c = 300;

		insert new List<Payment_Fee__c>{pf1, pf2, pf3};

        return psi;
    }

	// -----------------------------
	// SUCCESS PATH
	// -----------------------------
	@IsTest
	static void testBatchSuccess() {

		Test.setMock(HttpCalloutMock.class,new EPPSAddFee2Mock('FEE-12345'));

		Payment_Schedule_Item__c psi = createTestData();

		Test.startTest();
		Database.executeBatch(new EPPSPaymentFeeBatch(), 1);
		Test.stopTest();

		Payment_Fee__c pf = [SELECT Fee_Id__c, Status_Code__c FROM Payment_Fee__c LIMIT 1];

		Assert.areEqual('Sent to EPPS', pf.Status_Code__c, 'Should be marked success');
		Assert.areNotEqual(null, pf.Fee_Id__c, 'FeeID should be populated');
	}

	@IsTest
	static void testBatchCatchExplicit() {

		// Flip the test seam
		EPPSPaymentFeeBatch.FORCE_EXCEPTION_IN_EXECUTE = true;

		Payment_Schedule_Item__c psi = createTestData();

		Test.startTest();
		Database.executeBatch(new EPPSPaymentFeeBatch(), 1);
		Test.stopTest();

		Payment_Fee__c pf = [SELECT Status_Code__c FROM Payment_Fee__c LIMIT 1];

		Assert.areEqual('Failed to EPPS', pf.Status_Code__c, 'Batch catch block should be executed');
	}

	// -----------------------------
	// SCHEDULABLE ENTRY POINT
	// -----------------------------
	@IsTest
		static void testSchedulableExecute() {

		Test.setMock(HttpCalloutMock.class,new EPPSAddFee2Mock('FEE-12345'));

		Test.startTest();
		String jobId = System.schedule('EPPS Payment Fee Batch Test', '0 0 0 1 1 ? 2099', new EPPSPaymentFeeBatch());
		Test.stopTest();

		Assert.areNotEqual(null, jobId, 'Scheduled job should be created');
	}
}