/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSSettlementFeeBatchTest
 * Author          : Shell Black (Scott Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jan 27, 2026
 * Description     : This class provides full coverage for EPPSSettlementFeeBatch and EPPSSettlementFeeBatchHelper
 *                   and partial coverage for EPPSIntegrationMethodsEnhanced and EPPSHelperMethods
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Scott Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
@isTest(testFor='ApexClass:EPPSSettlementFeeBatch,ApexClass:EPPSSettlementFeeBatchHelper,ApexClass:EPPSIntegrationMethodsEnhanced,ApexClass:EPPSHelperMethods')
private class EPPSSettlementFeeBatchTest {

	private static Settlement_Plan_Item__c createTestData() {

    	// Create an Account
        Account testAccount = TestDataFactory.makeAccount('Test Account');
		Account testCreditor = TestDataFactory.makeAccount('Test Creditor');

		Account_Bank_Information__c acctBankInfo = new Account_Bank_Information__c();
		acctBankInfo.Account__c = testAccount.Id;
		insert acctBankInfo;

        // Create an Opportunity that will qualify for approval
        Opportunity testOpp = TestDataFactory.makeOpp(testAccount.Id, 'Test Opportunity');
		testOpp.StageName = 'Build Plan';
		testOpp.Integrate_with_EPPS__c = true;
		update testOpp;

		CreditorOpportunity__c credOpp1 = new CreditorOpportunity__c(
            CreditorAccount__c = testCreditor.Id,
            Amount__c = 5000.00,
            Weekly_Payment__c = 100.00,
			Account_Bank_Information__c = acctBankInfo.Id,
			Opportunity__c = testOpp.Id,
            Frequency__c = 'Weekly');

		insert credOpp1;

		// Create Settlement Plan
		Settlement_Plan_Draft__c testSP = new Settlement_Plan_Draft__c();
		testSP.Status__c = EPPSHelperMethods.SETTLEMENT_PLAN_STATUS_ACTIVE;
		testSP.CreditorOpportunity__c = credOpp1.Id;
		testSP.Status__c = EPPSHelperMethods.PAYMENT_PLAN_STATUS_ACTIVE;
		insert testSP;

        Settlement_Plan_Item__c spi = new Settlement_Plan_Item__c(
            Settlement_Plan__c = testSP.Id,
            Payment_Date__c = Date.today(),
			Payment_Number__c = 1,
            Status__c = EPPSHelperMethods.SETTLEMENT_PLAN_ITEM_STATUS_SCHEDULED);
        
		insert spi;

		// create settlement fees
		Settlement_Fee__c sf1 = new Settlement_Fee__c(Settlement_Plan_Item__c = spi.Id);
		sf1.Type__c = 'SettlementPayment';
		sf1.Amount__c = 1000;

		Settlement_Fee__c sf2 = new Settlement_Fee__c(Settlement_Plan_Item__c = spi.Id);
		sf2.Type__c = 'Commission Fee';
		sf2.Amount__c = 200;

		Settlement_Fee__c sf3 = new Settlement_Fee__c(Settlement_Plan_Item__c = spi.Id);
		sf3.Type__c = 'Settlement Fee';
		sf3.Amount__c = 300;

		insert new List<Settlement_Fee__c>{sf1, sf2, sf3};

        return spi;
    }

	// -----------------------------
	// SUCCESS PATH
	// -----------------------------
	@IsTest
	static void testBatchSuccess() {

		Test.setMock(HttpCalloutMock.class,new EPPSAddFee2Mock('FEE-12345'));

		Settlement_Plan_Item__c spi = createTestData();

		Test.startTest();
		Database.executeBatch(new EPPSSettlementFeeBatch(), 1);
		Test.stopTest();

		Settlement_Fee__c sf = [SELECT Fee_Id__c, Status_Code__c FROM Settlement_Fee__c LIMIT 1];

		Assert.areEqual('Sent to EPPS', sf.Status_Code__c, 'Should be marked success');
		Assert.areNotEqual(null, sf.Fee_Id__c, 'FeeID should be populated');
	}

	@IsTest
	static void testBatchCatchExplicit() {

		Settlement_Plan_Item__c spi = createTestData();

		Test.startTest();
		Database.executeBatch(new EPPSSettlementFeeBatch(), 1);
		Test.stopTest();

		Settlement_Fee__c sf = [SELECT Status_Code__c FROM Settlement_Fee__c LIMIT 1];

		Assert.areEqual('Failed to EPPS', sf.Status_Code__c, 'Batch catch block should be executed');
	}

	// -----------------------------
	// SCHEDULABLE ENTRY POINT
	// -----------------------------
	@IsTest
	static void testSchedulableExecute() {

		Test.setMock(HttpCalloutMock.class,new EPPSAddFee2Mock('FEE-12345'));

		Test.startTest();
		String jobId = System.schedule('EPPS Settlement Fee Batch Test', '0 0 0 1 1 ? 2099', new EPPSSettlementFeeBatch());
		Test.stopTest();

		Assert.areNotEqual(null, jobId, 'Scheduled job should be created');
	}
}