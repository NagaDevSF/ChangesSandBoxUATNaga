/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSManageFeesTest
 * Author          : Shell Black (Sean Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By:
 * Last Modified On: Jan 27, 2026
 * Description     : Test class to cover the EPPSManageFees class for voids and updates              
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Sean Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
@isTest 
private class EPPSManageFeesTest {

	@isTest
	private static void testSettlementUpdates() 
	{
		Settlement_Plan_Item__c theSPI = createSettlementTestData();

		Test.setMock(HttpCalloutMock.class, new EPPSManageFeesCalloutMock());
		EPPSManageFeesCalloutMock.returnErrors = false;
		Test.startTest();
		//  Record ID to settlment
			EPPSManageFees.updateSettlementLineItemFees(theSPI.Id);

			EPPSManageFees.updateSettlementDetailFee(theSettlementFee.Id);

			EPPSManageFees.updateSettlementDetailFeeByType(theSPI.Id, 'SettlementPayment');
		Test.stopTest();

	}

	@isTest
	private static void testSettlementVoids()
	{
		Settlement_Plan_Item__c theSPI = createSettlementTestData();

		Test.setMock(HttpCalloutMock.class, new EPPSManageFeesCalloutMock());
		EPPSManageFeesCalloutMock.returnErrors = false;
		EPPSManageFeesCalloutMock.createVoidResponse = true;
		Test.startTest();
		//  Record ID to settlment
			EPPSManageFees.voidSettlementLineItemFees(theSPI.Id);

			EPPSManageFees.voidSettlementDetailFee(theSettlementFee.Id);

			EPPSManageFees.voidSettlementDetailFeeByType(theSPI.Id, 'SettlementPayment');
		Test.stopTest();
	}



	@isTest
	private static void testPaymentUpdates() 
	{
		Payment_Schedule_Item__c thePPI = createPaymentTestData();

		Test.setMock(HttpCalloutMock.class, new EPPSManageFeesCalloutMock());
		EPPSManageFeesCalloutMock.returnErrors = false;
		Test.startTest();
		//  Record ID to settlment
		System.debug('**** thePPI.Id: ' + thePPI.Id);
			EPPSManageFees.updatePaymentLineItemFees(thePPI.Id);

			EPPSManageFees.updatePaymentDetailFee(thePaymentFee.Id);

			EPPSManageFees.updatePaymentDetailFeeByType(thePPI.Id, 'Banking Fee');
		Test.stopTest();
	}

	@isTest
	private static void testPaymentVoids()
	{
		Payment_Schedule_Item__c thePPI = createPaymentTestData();

		Test.setMock(HttpCalloutMock.class, new EPPSManageFeesCalloutMock());
		EPPSManageFeesCalloutMock.returnErrors = false;
		EPPSManageFeesCalloutMock.createVoidResponse = true;
		Test.startTest();
		//  Record ID to settlment
			EPPSManageFees.voidPaymentFees(thePPI.Id);

			EPPSManageFees.voidPaymentFee(thePaymentFee.Id);

			EPPSManageFees.voidPaymentFeeByType(thePPI.Id, 'Banking Fee');
		Test.stopTest();
	}


	static Settlement_Fee__c theSettlementFee = new Settlement_Fee__c();


	private static Settlement_Plan_Item__c createSettlementTestData() {

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
		sf1.Fee_Id__c = '11823125';
		sf1.Amount__c = 1000;		

		Settlement_Fee__c sf2 = new Settlement_Fee__c(Settlement_Plan_Item__c = spi.Id);
		sf2.Type__c = 'Commission Fee';
		sf2.Fee_Id__c = '11823125';
		sf2.Amount__c = 200;

		Settlement_Fee__c sf3 = new Settlement_Fee__c(Settlement_Plan_Item__c = spi.Id);
		sf3.Fee_Id__c = '11823125';
		sf3.Type__c = 'Settlement Fee';
		sf3.Amount__c = 300;

		insert new List<Settlement_Fee__c>{sf1, sf2, sf3};

		theSettlementFee = sf1;

        return spi;
    }


	static Payment_Fee__c thePaymentFee = new Payment_Fee__c();

	private static Payment_Schedule_Item__c createPaymentTestData() {

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
		pf1.Fee_Id__c = '11823125';
		pf1.Amount__c = 100;

		Payment_Fee__c pf2 = new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id);
		pf2.Type__c = 'Program Fee';
		pf2.Fee_Id__c = '11823125';
		pf2.Amount__c = 200;

		Payment_Fee__c pf3 = new Payment_Fee__c(Payment_Schedule_Item__c = psi.Id);
		pf3.Type__c = 'Wire Fee';
		pf3.Fee_Id__c = '11823125';
		pf3.Amount__c = 300;

		insert new List<Payment_Fee__c>{pf1, pf2, pf3};

		thePaymentFee = pf1;

        return psi;
    }

	private static Date getTargetDate() {
        return EPPSHelperMethods.getDateAfterBusinessDays(2);
    }
}