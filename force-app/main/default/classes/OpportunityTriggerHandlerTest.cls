@isTest
private class OpportunityTriggerHandlerTest {

	@isTest
    static void testOppPlatformEvent() {

		Account testAcc = TestDataFactory.makeAccount('Test for Platform Event');

		Opportunity testOpp = TestDataFactory.makeOpp(testAcc.Id, 'Test for Platform Event');
		Opportunity testOpp2 = TestDataFactory.makeOpp(testAcc.Id, 'Test for Platform Event2');

		PaymentDraft__c d1 = new PaymentDraft__c(
            Opportunity__c = testOpp.Id,
            Draft_Name__c = 'D1',
            Configuration_JSON__c = '{"programType":"DCG_MOD"}',
            Calculations_JSON__c = '{"totalDebt":50000}'
        );
        insert d1;

		Test.startTest();

		testOpp.Estimated_Current_Payment__c = 34234;
		testOpp.Estimated_Total_Debt__c = 1321421;

		testOpp2.Estimated_Current_Payment__c = 11111;

		update new List<Opportunity>{testOpp, testOpp2};

		Test.stopTest();

		PaymentDraft__c d1a = [SELECT Id, Sync_Status__c, Invalidated_Date__c FROM PaymentDraft__c WHERE Id =: d1.Id];

		Assert.areEqual(OpportunityTriggerHandler.PAYMENT_DRAFT_SYNC_STATUS_OUT_OF_SYNC, d1a.Sync_Status__c, 'Payment Draft was not updated with correct status');
		Assert.areEqual(Date.today(), d1a.Invalidated_Date__c, 'Payment Draft was not updated with Invalidated Date');

	}
}