/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : OpportunityTriggerHandlerTest
 * Author          : Shell Black (Scott Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jan 27, 2026
 * Description     : This class provides full coverage for OpportunityTriggerHandler and EPPSManageCardHolderQueueable
 *                   and partial coverage for EPPSIntegrationMethodsEnhanced and EPPSHelperMethods
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Scott Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
@isTest
private class OpportunityTriggerHandlerTest {

    @TestSetup
    static void setup() {

        Account testAcc = TestDataFactory.makeAccount('Test for Platform Event');
		Opportunity testOpp = TestDataFactory.makeOpp(testAcc.Id, 'Test for Platform Event');
        // Create creditors and link to opportunity

        List<Account> cs = TestDataFactory.makeCreditorsAsAccount(3, 'Calc Cred');
        TestDataFactory.linkCredsToOpp(testOpp.Id, cs, 10000, 100, 3);
    }

	 private static Opportunity getOpp() {
        return [SELECT Id FROM Opportunity LIMIT 1];
    }

	@isTest
	static void testOppStageSigned() {
		
		Opportunity opp = getOpp();
					
		PaymentDraft__c d1 = new PaymentDraft__c(
            Opportunity__c = opp.Id,
            Draft_Name__c = 'D1',
			Settlement_Percentage__c = 10,
			Program_Fee_Percentage__c = 10,
			Setup_Fee__c = 35,
			Banking_Fee__c = 50,

            Configuration_JSON__c = '{"programType":"DCG_MOD"}',
            Calculations_JSON__c = '{"totalDebt":50000}',
			Is_Primary__c = true
        );

        insert d1;
		Test.setMock(HttpCalloutMock.class,new EPPSAddCardHolderMock(EPPSAddCardHolderMock.Mode.SUCCESS));

		Test.startTest();
		opp.Integrate_with_EPPS__c = true; // temporary control
		opp.StageName = OpportunityTriggerHandler.OPP_STAGE_SIGNED;

		update opp;

		Test.stopTest();

	}

	@IsTest
	static void testOppStageSignedFault() {

		Opportunity opp = getOpp();
					
		PaymentDraft__c d1 = new PaymentDraft__c(
            Opportunity__c = opp.Id,
            Draft_Name__c = 'D1',
			Settlement_Percentage__c = 10,
			Program_Fee_Percentage__c = 10,
			Setup_Fee__c = 35,
			Banking_Fee__c = 50,

            Configuration_JSON__c = '{"programType":"DCG_MOD"}',
            Calculations_JSON__c = '{"totalDebt":50000}',
			Is_Primary__c = true
        );

        insert d1;

		Test.setMock(HttpCalloutMock.class,new EPPSAddCardHolderMock(EPPSAddCardHolderMock.Mode.THROW_EXCEPTION));

		EPPSManageCardHolderQueueable.FORCE_EXCEPTION_IN_EXECUTE = true;

		Test.startTest();
		opp.Integrate_with_EPPS__c = true; // temporary control
		opp.StageName = OpportunityTriggerHandler.OPP_STAGE_SIGNED;

		update opp;

		Test.stopTest();
	}

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