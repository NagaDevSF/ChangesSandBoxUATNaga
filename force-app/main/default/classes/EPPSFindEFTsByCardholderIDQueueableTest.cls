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

@isTest
public class EPPSFindEFTsByCardholderIDQueueableTest  
{
	@isTest
	static void TestFindEFTs()
	{

		createTestData();

		Test.setMock(HttpCalloutMock.class, new EPPSFindEFTsMock());

		Test.startTest();

			System.enqueueJob(new EPPSFindEFTsByCardholderIDQueueable(null)); 

		Test.stopTest();
	}


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

		EPPSFindEFTsMock.numRecords = 1;
		EPPSFindEFTsMock.ResponseBody = EPPSFindEFTsMock.CreateResponseBody();		
		for (Integer i = 0; i < EPPSFindEFTsMock.numRecords; i++)
		{
			Payment_Schedule_Item__c theItem = new Payment_Schedule_Item__c();
			theItem.EPPS_EFT_Transaction_Id__c = String.valueOf(i);
			theItem.Payment_Plan__c = thePaymentPlan.Id;
			theItem.Payment_Date__c = Datetime.now().addDays(i).date();
			theItem.Payment_Number__c = i;
			thePaymentSchedules.add	(theItem);
		}
			
		insert thePaymentSchedules;
	}


}