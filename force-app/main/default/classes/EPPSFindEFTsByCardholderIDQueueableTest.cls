/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSFindEFTsByCardholderIDQueueableTest
 * Author          : Shell Black (Sean Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jan 27, 2026
 * Description     : This class provides full coverage for EPPSFindEFTsByCardholderIDQueueableTest                  
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Sean Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

//@isTest (testFor='ApexClass:EPPSFindEFTsByCardholderIDQueueable,ApexClass:EPPSIntegrationMethodsEnhanced,ApexClass:EPPSIntegrationMethodsEnhanced,ApexClass:EPPSHelperMethods')
@isTest
public class EPPSFindEFTsByCardholderIDQueueableTest  
{

	@IsTest
    static void testSchedulerExecute() 
	{

        Test.startTest();

        // Schedule the job
        String cron = '0 0 1 * * ?';
        System.schedule(
            'EPPS Daily Job Test',
            cron,
            new EPPSDailyJobScheduler()
        );

        // Forces scheduler + queueable to run
        Test.stopTest();

        // Optional assertion: verify queueable was enqueued
        Integer jobCount = [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
        ];

        System.assert(jobCount > 0, 'Queueable job should have been enqueued');
    }
	
	@isTest
	static void TestFindEFTs()
	{
		CreateNSF = false;
		createTestData();

		Test.setMock(HttpCalloutMock.class, new EPPSFindEFTsMock(true));

		Test.startTest();
		System.enqueueJob(new EPPSFindEFTsByCardholderIDQueueable(null)); 
		Test.stopTest();
	}

	@isTest
	static void TestCleared()
	{
		CreateNSF = true;
		createTestData();

		Test.setMock(HttpCalloutMock.class, new EPPSFindEFTsMock(true));

		Test.startTest();
		System.enqueueJob(new EPPSFindEFTsByCardholderIDQueueable(null)); 
		Test.stopTest();
	}


	@isTest
	static void TestNegativeResult()
	{
		createTestData();
		Test.setMock(HttpCalloutMock.class, new EPPSFindEFTsMock(false));

		Test.startTest();
			System.enqueueJob(new EPPSFindEFTsByCardholderIDQueueable(null)); 
		Test.stopTest();
	}

	@isTest
	static void TestStartupWithCardholderIds()
	{
		createTestData();
		Test.setMock(HttpCalloutMock.class, new EPPSFindEFTsMock(true));
		Set<String> CardHolderIDs = new Set<String>();
		for (Integer i = 0; i < 200; i++)
		{
			CardHolderIDs.add(String.valueOf(i));
		}
		Test.startTest();
			System.enqueueJob(new EPPSFindEFTsByCardholderIDQueueable(CardHolderIDs)); 

		Test.stopTest();
	}


	static boolean CreateNSF = false;

	private static void createTestData()
	{
		// Create payment schedule records
		List<Payment_Schedule_Item__c> thePaymentSchedules = new List<Payment_Schedule_Item__c>();

		Account theAccount = new Account();
		theAccount.EPPS_ID__c = '1';
		theAccount.Name = 'Test Account';
		insert theAccount;
		
		Opportunity theOpty = new Opportunity();
		theOpty.AccountId = theAccount.Id;
		theOpty.Name = 'Test Opty';
		theOpty.StageName = 'Closed';
		theOpty.CloseDate = Date.today();
		insert theOpty;

		PaymentPlan__c thePaymentPlan = new PaymentPlan__c();
		thePaymentPlan.Version_Number__c = 1;
		thePaymentPlan.Opportunity__c = theOpty.Id;
		//thePaymentPlan
		insert thePaymentPlan;

		if (CreateNSF == true)
		{
			EPPSFindEFTsMock.ResponseBody = EPPSFindEFTsMock.CreateResponseBodyNSFReturnCode();		
		}
		else
		{
			EPPSFindEFTsMock.ResponseBody = EPPSFindEFTsMock.CreateResponseBody();	
		}

		integer theEFTTRansID = 10;
		for (Integer i = 0; i < 200; i++)
		{
			Payment_Schedule_Item__c theItem = new Payment_Schedule_Item__c();
			theItem.EPPS_EFT_Transaction_Id__c = String.valueOf(i + theEFTTRansID);
			theItem.Payment_Plan__c = thePaymentPlan.Id;
			theItem.Payment_Date__c = Datetime.now().addDays(i).date();
			theItem.Payment_Number__c = i;			
			thePaymentSchedules.add	(theItem);
		}
			
		insert thePaymentSchedules;
	}


}