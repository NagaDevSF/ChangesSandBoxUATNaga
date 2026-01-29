public class EPPSFindEFTsByCardholderIDQueueable  implements Queueable, Database.AllowsCallouts
{
	//  This is the queueable for finding EFTs by a date range.
	// When the queuable is started with no context, the queueable will get the setting
	// for how many days to look back, check the first day, and see the day with how many
	// days to look back are left and what the current day is.

	public EPPSFindEFTsByCardholderIDQueueable(Set<String> CardHolderIDs)
	{
		settings = IntegrationLogUtil.getMetadataFieldValues(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT);
		integer LookBackDays = Integer.valueOf(settings.get('Lookback_for_Client_Payment_Status__c'));
		Date lookbackDate = Date.today().addDays(-LookBackDays);
		//  This must be the first run, find all cardholder IDs to see the jobs
		if (CardHolderIDs == null) 
		{					
			List<Payment_Schedule_Item__c> theItems =
			[SELECT Id, Payment_Plan__r.Opportunity__r.Account.EPPS_ID__c
            FROM Payment_Schedule_Item__c
            WHERE EPPS_EFT_Transaction_Id__c != null AND Payment_Date__c >= :lookbackDate];

			theCardHolderIDs = new Set<String>();
		
			for (Payment_Schedule_Item__c theItem : theItems)
			{
				if (theItem.Payment_Plan__r.Opportunity__r.Account.EPPS_ID__c != null)
				{
					theCardHolderIDs.add(theItem.Payment_Plan__r.Opportunity__r.Account.EPPS_ID__c);						
				}				
			}            
		}
		else
		{
			theCardHolderIDs = CardHolderIDs;
		}
	}
	
	//  Number of callouts per queueable.
	
	Set<String> theCardHolderIDs;
	Set<String> cardHolderIDsToRemove = new Set<String>();
	Map<String, Object> settings ;

	public void execute(QueueableContext context) 	
	{			
		integer CalloutCount = Integer.valueOf(settings.get('Clients_per_Find_EFT_Batch__c'));
		integer LookBackDays = Integer.valueOf(settings.get('Lookback_for_Client_Payment_Status__c'));
		System.debug('**** CalloutCount: ' + CalloutCount + '  LookBackDays: ' + LookBackDays);
		DateTime thePriorDay = DateTime.now().addDays(-LookBackDays);
		DateTime theStartDateTime = Datetime.newInstance(thePriorDay.year(), thePriorDay.month(), thePriorDay.day(), 0,0,0);		
		DateTime theEndDateTime = Datetime.newInstance(DateTime.now().year(), DateTime.now().month(), DateTime.now().day(),23,59,59);
		
		try
		{		
			integer loopIndex = 0;	
			if (loopIndex < CalloutCount)
			{
				//  Loop through the CardholderIDs and chunk them based on the settings 	
				for (string CardholderID : theCardHolderIDs)
				{
					System.debug('**** request: ' + CardholderID + ' ' + theStartDateTime + ' ' + theEndDateTime);
					// Build the request wrapper
					EPPSHelperMethods.FindEftByIDandDate_Wrapper req =
						new EPPSHelperMethods.FindEftByIDandDate_Wrapper(
							CardholderID,
							theStartDateTime,
							theEndDateTime);

					// Invoke the EPPS SOAP callout
					EPPSHelperMethods.EPPSResponse response =
						EPPSIntegrationMethodsEnhanced.findEftByIDandDate(req);

					// Inspect the result
					if (response.success) 
					{
						System.debug('**** response succeesss');
						if (response.FoundEFTs != null && response.FoundEFTs.size() > 0)
						{
							System.debug('**** found EFTs:' + response.FoundEFTs);
							//  Build a list of payment record IDs based on EftTransactionIDs
							List<string> theEFTTransactionIds = new List<String>();
							for (EPPSHelperMethods.FindEFT_Wrapper eft : response.FoundEFTs.values()) 
							{
								theEFTTransactionIds.add(eft.EftTransactionID);
								System.debug('**** eft.EftTransactionID: ' + eft.EftTransactionID);
							}

							//  Find the related Payment records and update the status.
							List<Payment_Schedule_Item__c> thePaymentSchedules = [
																SELECT Id, EPPS_EFT_Status__c,
																EPPS_EFT_Transaction_Id__c,
																Last_EPPS_Integration__c,
																EPPS_Settlement_Date__c,
																EPPS_Returned_Date__c,
																EPPS_NSF_Return_Code__c					
																FROM Payment_Schedule_Item__c
																WHERE
																EPPS_EFT_Transaction_Id__c IN : theEFTTransactionIds];

							//  Loop through the returned records and match up with a returned EFT and update the info.
							for (Payment_Schedule_Item__c thePaymentSchedule : thePaymentSchedules)
							{					
								EPPSHelperMethods.FindEFT_Wrapper  theWrapper = response.FoundEFTs.get(thePaymentSchedule.EPPS_EFT_Transaction_Id__c);
								if (theWrapper != null)
								{
									System.debug('**** set status for: ' + theWrapper.EftTransactionID);
									thePaymentSchedule.EPPS_EFT_Status__c = theWrapper.StatusCode;
									thePaymentSchedule.Last_EPPS_Integration__c = Datetime.now();
									thePaymentSchedule.EPPS_Settlement_Date__c = EPPSHelperMethods.safeDate(theWrapper.SettledDate);
									thePaymentSchedule.EPPS_Returned_Date__c = EPPSHelperMethods.safeDate(theWrapper.ReturnedDate);
									thePaymentSchedule.EPPS_NSF_Return_Code__c = theWrapper.NSFReturnCode;
								}
							}

							update thePaymentSchedules;

							IntegrationLogUtil.createLog(
										IntegrationLogUtil.logBuilder()
										.settings('EPPS_Integration_Setting__mdt')
										.objectMeta('EPPS_Integration_Object__mdt')
										.method('findEftByIDandDate')
										.request(response.SOAPRequestBody)
										.response(response.SOAPResponseBody)
										.httpCode(response.HTTPResponseCode)
										.status(response.Success ? IntegrationLogUtil.LogStatus.Success : IntegrationLogUtil.LogStatus.Failure)
										.build());
						}

					} 
					else 
					{
							IntegrationLogUtil.createLog(
										IntegrationLogUtil.logBuilder()
										.settings('EPPS_Integration_Setting__mdt')
										.objectMeta('EPPS_Integration_Object__mdt')
										.method('findEftByIDandDate')
										.request(response.SOAPRequestBody)
										.response(response.SOAPResponseBody)
										.httpCode(response.HTTPResponseCode)
										.status(response.Success ? IntegrationLogUtil.LogStatus.Success : IntegrationLogUtil.LogStatus.Failure)
										.build());
					}
				
					cardHolderIDsToRemove.add(CardholderID);
					loopIndex ++;
				}
			}
			else 
			{
				StartNextQueue();
			}
		}
		catch (Exception e)
		{
			IntegrationLogUtil.createLog(
								IntegrationLogUtil.logBuilder()
								.settings('EPPS_Integration_Setting__mdt')
								.objectMeta('EPPS_Integration_Object__mdt')
								.method('findEftByIDandDate')
								.exceptionMsg(EPPSHelperMethods.getExceptionDetails(e))
								.status(IntegrationLogUtil.LogStatus.Failure)								
								.build());
		}

		StartNextQueue();
	}

	private void StartNextQueue()
	{
		IntegrationLogUtil.flush();
		
		theCardHolderIDs.removeAll(cardHolderIDsToRemove);

		if (theCardHolderIDs.size() > 0 && Test.isRunningTest() == false)
		{
			//  If we still have some cardholders left, start the queueable with the new list - what was already processed.
			System.enqueueJob(new EPPSFindEFTsByCardholderIDQueueable(theCardHolderIDs)); // Start the Queueable
		}
	}

}