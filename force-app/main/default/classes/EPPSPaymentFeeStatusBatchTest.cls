/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSPaymentFeeStatusBatchTest
 * Author          : Shell Black (Sean Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By:
 * Last Modified On: Jan 27, 2026
 * Description     : Test class to cover the EPPSPaymentFeeStatusBatchTest              
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Sean Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

@isTest 
private class EPPSPaymentFeeStatusBatchTest {

	@isTest
	private static void testEPPSPaymentFeeStatusBatch() 
	{
		createTestData();

		Test.setMock(HttpCalloutMock.class, new EPPSPaymentFeeStatusBatchMock());
		EPPSPaymentFeeStatusBatchMock.returnErrors = false;
		Test.startTest();
			Database.executeBatch(new EPPSPaymentFeeStatusBatch(), 5);  
		Test.stopTest();
	}

	@isTest
	private static void testEPPSPaymentFeeStatusBatchNegativeResult() 
	{
		createTestData();

		Test.setMock(HttpCalloutMock.class, new EPPSPaymentFeeStatusBatchMock());
		EPPSPaymentFeeStatusBatchMock.returnErrors = true;
		Test.startTest();
			Database.executeBatch(new EPPSPaymentFeeStatusBatch(), 5);  
		Test.stopTest();
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
		pf1.Fee_Id__c = '11749828';
		pf1.Amount__c = 100;

		Payment_Fee__c pf2 = new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id);
		pf2.Type__c = 'Program Fee';
		pf2.Fee_Id__c = '11749828';
		pf2.Amount__c = 200;

		Payment_Fee__c pf3 = new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id);
		pf3.Type__c = 'Wire Fee';
		pf3.Fee_Id__c = '11749828';
		pf3.Amount__c = 300;

		insert new List<Payment_Fee__c>{pf1, pf2, pf3};

        return psi;
    }

	private static Date getTargetDate() {
        return EPPSHelperMethods.getDateAfterBusinessDays(2);
    }
}