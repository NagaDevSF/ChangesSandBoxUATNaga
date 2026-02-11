@isTest
private class CreditorOpportunityTriggerHandlerTest {

	@testSetup
    static void setupData() {
        // Create an Account
        Account testAccount = TestDataFactory.makeAccount('Test Account');

        // Create an Opportunity that will qualify for approval
        Opportunity testOpp = TestDataFactory.makeOpp(testAccount.Id, 'Test Opportunity');
		testOpp.StageName = 'Build Plan';
		update testOpp;

		// Create Payment Plan
		PaymentPlan__c testPP = TestDataFactory.makePaymentPlanForOpp(testOpp.Id, 5000, 300, 12);

		// Create Payment Schedule Item
		Payment_Schedule_Item__c testPSI = new Payment_Schedule_Item__c();
		testPSI.Payment_Plan__c = testPP.Id;
		testPSI.Payment_Number__c = 1;
		testPSI.Payment_Date__c = Date.today().addDays(7);
		testPSI.Total_Payment__c = 100;
		insert testPSI;

        // Create Creditor Opportunity
		List<Account> cs = TestDataFactory.makeCreditorsAsAccount(1, 'Calc Cred');
        TestDataFactory.linkCredsToOpp(testOpp.Id, cs, 10000, 100, 1);
    }


    @isTest
    static void testBlockDMLWhenOppLocked() {
        // Retrieve Opportunity
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        
		// Submit for approval
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(testOpp.Id);
        Approval.ProcessResult result = Approval.process(req);

        // insert creditor opportunity
        try {
            List<Account> cs = TestDataFactory.makeCreditorsAsAccount(1, 'Calc Cred');
			TestDataFactory.linkCredsToOpp(testOpp.Id, cs, 10000, 100, 1);
            System.assert(false, 'Insert should have thrown an error on Creditor Opportunity due to locked Opportunity');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains(CreditorOpportunityTriggerHandler.APPROVAL_BLOCK_MSG),'Expected lock error, got: ' + e.getMessage());
        }
        
        // delete creditor opportunity
        try {
            CreditorOpportunity__c testCO = [SELECT Id FROM CreditorOpportunity__c LIMIT 1];
            delete testCO;
            System.assert(false, 'Delete should have thrown an error on Creditor Opportunity due to locked Opportunity');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains(CreditorOpportunityTriggerHandler.APPROVAL_BLOCK_MSG),'Expected lock error, got: ' + e.getMessage());
        }
        
        // insert payment plan
        try {
            PaymentPlan__c testPP = TestDataFactory.makePaymentPlanForOpp(testOpp.Id, 5000, 300, 12);
            System.assert(false, 'Insert should have thrown an error on Payment Plan due to locked Opportunity');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains(PaymentPlanTriggerHandler.APPROVAL_BLOCK_MSG),'Expected lock error, got: ' + e.getMessage());
        }
        
        PaymentPlan__c testPP = [SELECT Id FROM PaymentPlan__c LIMIT 1];
        
        // delete payment plan
        try {
            delete testPP;
            System.assert(false, 'Delete should have thrown an error on Creditor Opportunity due to locked Opportunity');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains(PaymentPlanTriggerHandler.APPROVAL_BLOCK_MSG),'Expected lock error, got: ' + e.getMessage());
        }
        
        // insert payment schedule item
        try {
            // Create Payment Schedule Item
            Payment_Schedule_Item__c testPSI = new Payment_Schedule_Item__c();
            testPSI.Payment_Plan__c = testPP.Id;
            testPSI.Payment_Number__c = 1;
            testPSI.Payment_Date__c = Date.today().addDays(7);
            testPSI.Total_Payment__c = 100;
            insert testPSI;
            System.assert(false, 'Insert should have thrown an error on Payment Schedule Item due to locked Opportunity');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains(PaymentScheduleItemTriggerHandler.APPROVAL_BLOCK_MSG),'Expected lock error, got: ' + e.getMessage());
        }
        
        // delete payment schedule item
        try {
            Payment_Schedule_Item__c testPSI = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];
            delete testPSI;
            System.assert(false, 'Delete should have thrown an error on Payment Schedule Item due to locked Opportunity');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains(PaymentScheduleItemTriggerHandler.APPROVAL_BLOCK_MSG),'Expected lock error, got: ' + e.getMessage());
        }
    }

    @isTest
    static void testAllowDMLWhenOppNotLocked() {
 
		// Retrieve Opportunity
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        
        // Create Payment Plan
		PaymentPlan__c testPP = TestDataFactory.makePaymentPlanForOpp(testOpp.Id, 5000, 300, 12);

		// Create Payment Plan Schedule
		Payment_Schedule_Item__c testPSI = new Payment_Schedule_Item__c();
		testPSI.Payment_Plan__c = testPP.Id;
		testPSI.Payment_Number__c = 1;
		testPSI.Payment_Date__c = Date.today().addDays(7);
		testPSI.Total_Payment__c = 100;
		insert testPSI;

        // Create Creditor Opportunity
		List<Account> cs = TestDataFactory.makeCreditorsAsAccount(1, 'Calc Cred');
        TestDataFactory.linkCredsToOpp(testOpp.Id, cs, 10000, 100, 1);
        
        Test.stopTest();

        System.assertNotEquals(null, testPSI.Id, 'Payment Schedule Item record should insert since Opportunity is NOT locked');
        System.assertNotEquals(null, testPP.Id, 'Payment Plan record should insert since Opportunity is NOT locked');
        System.assertEquals(2, [SELECT Id FROM CreditorOpportunity__c].size(), 'There should be 2 Creditor Opportunity records since Opportunity is NOT locked');
    }

}