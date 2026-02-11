/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSSettlementFeeStatusBatchTest
 * Author          : Shell Black (Sean Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By:
 * Last Modified On: Jan 27, 2026
 * Description     : Test class for Settlement status batch
 *						
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Sean Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
@isTest 
private class EPPSSettlementFeeStatusBatchTest {

	@isTest
	private static void testEPPSSettlementFeeStatusBatch() 
	{
		createTestData();

		Test.setMock(HttpCalloutMock.class, new EPPSSettlementFeeStatusBatchMock());
		EPPSSettlementFeeStatusBatchMock.reutrnErrors = false;
		Test.startTest();
			Database.executeBatch(new EPPSSettlementFeeStatusBatch(), 5);  
		Test.stopTest();
	}

	@isTest
	private static void testEPPSSettlementFeeStatusBatchNegativeResult() 
	{
		createTestData();

		Test.setMock(HttpCalloutMock.class, new EPPSSettlementFeeStatusBatchMock());
		EPPSSettlementFeeStatusBatchMock.reutrnErrors = true;
		Test.startTest();
			Database.executeBatch(new EPPSSettlementFeeStatusBatch(), 5);  
		Test.stopTest();
	}


	@IsTest
	private static void testExecute()
	{
		EPPSSettlementFeeStatusBatch theBatch = new EPPSSettlementFeeStatusBatch();
		theBatch.execute(null); 
	}
	private static Settlement_Plan_Item__c createTestData() {

    	// Create an Account
        Account testAccount = TestDataFactory.makeAccount('Test Account');
		Account testCreditor = TestDataFactory.makeAccount('Test Creditor');
		testCreditor.RecordTypeId = TestDataFactory.ACCOUNT_CREDITOR_RT_ID;
        update testCreditor;
        
		Account_Bank_Information__c acctBankInfo = new Account_Bank_Information__c();
		acctBankInfo.Account__c = testCreditor.Id;
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
            Status__c = EPPSHelperMethods.SETTLEMENT_PLAN_ITEM_STATUS_PROCESSING);// Processing
        
		insert spi;

		// create settlement fees
		Settlement_Fee__c sf1 = new Settlement_Fee__c(Settlement_Plan_Item__c = spi.Id);
		sf1.Type__c = 'SettlementPayment';
		sf1.Fee_Id__c = '11749828';
		sf1.Amount__c = 1000;

		Settlement_Fee__c sf2 = new Settlement_Fee__c(Settlement_Plan_Item__c = spi.Id);
		sf2.Type__c = 'Commission Fee';
		sf2.Fee_Id__c = '11749828';
		sf2.Amount__c = 200;

		Settlement_Fee__c sf3 = new Settlement_Fee__c(Settlement_Plan_Item__c = spi.Id);
		sf3.Fee_Id__c = '11749828';
		sf3.Type__c = 'Settlement Fee';
		sf3.Amount__c = 300;

		insert new List<Settlement_Fee__c>{sf1, sf2, sf3};

        return spi;
    }

	
}