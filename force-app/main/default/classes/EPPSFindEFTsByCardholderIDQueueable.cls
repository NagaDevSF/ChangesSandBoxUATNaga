/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSFindEFTsByCardholderIDQueueable
 * Author          : Shell Black (Sean Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By:
 * Last Modified On: Jan 27, 2026
 * Description     :             
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Sean Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
public class EPPSFindEFTsByCardholderIDQueueable implements Queueable, Database.AllowsCallouts
{
	// When the queuable is started with no context, the queueable will get the setting
	// for how many days to look back, gather all cardholder ID that newer than the number of days 
	//  we are to get status for.

	public EPPSFindEFTsByCardholderIDQueueable(Set<String> CardHolderIDs)
	{
        GetR_CodeRecords();
		settings = IntegrationLogUtil.getMetadataFieldValues(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT);
		integer LookBackDays = Integer.valueOf(settings.get('Lookback_for_Client_Payment_Status__c'));
        LookBackDays = 30;
		Date lookbackDate = Date.today().addDays(- LookBackDays);
		//  This must be the first run, find all cardholder IDs to see the jobs
		if (CardHolderIDs == null)
		{
			List<Payment_Schedule_Item__c> theItems =
			[SELECT Id, Payment_Plan__r.Opportunity__r.Account.EPPS_ID__c
			FROM Payment_Schedule_Item__c
			WHERE EPPS_EFT_Transaction_Id__c != null AND Payment_Date__c >= : lookbackDate];



			theCardHolderIDs = new Set<String> ();

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
	Set<String> cardHolderIDsToRemove = new Set<String> ();
	Map<String, Object> settings;

	public void execute(QueueableContext context)
	{
        GetR_CodeRecords();
		//  number of callouts per queuable.
		settings = IntegrationLogUtil.getMetadataFieldValues(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT);
		integer CalloutCount = Integer.valueOf(settings.get('Clients_per_Find_EFT_Batch__c'));
		integer LookBackDays = Integer.valueOf(settings.get('Lookback_for_Client_Payment_Status__c'));
		DateTime thePriorDay = DateTime.now().addDays(- LookBackDays);
		DateTime theStartDateTime = Datetime.newInstance(thePriorDay.year(), thePriorDay.month(), thePriorDay.day(), 0, 0, 0);
		DateTime theEndDateTime = Datetime.newInstance(DateTime.now().year(), DateTime.now().month(), DateTime.now().day(), 23, 59, 59);
		List<Payment_Schedule_Item__c> thePaymentSchedulesToUpdateList = new List<Payment_Schedule_Item__c> ();
        
        string CurrentCardHolderID = '';
		try
		{
			integer loopIndex = 1;
			            
			//  Loop through the CardholderIDs and chunk them based on the settings 	
			for (string CardholderID : theCardHolderIDs)
			{
                CurrentCardHolderID = CardholderID;
				if (loopIndex > CalloutCount)
				{
					break;
				}
				loopIndex++;

				
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
					if (response.FoundEFTs != null && response.FoundEFTs.size() > 0)
					{
						//  Build a list of payment record IDs based on EftTransactionIDs
						List<string> theEFTTransactionIds = new List<String> ();
						for (EPPSHelperMethods.FindEFT_Wrapper eft : response.FoundEFTs.values())
						{
							theEFTTransactionIds.add(eft.EftTransactionID);
						}

						//  Find the related Payment records and update the status.
						List<Payment_Schedule_Item__c> thePaymentScheduleItems = [
						                                                           SELECT Id, EPPS_EFT_Status__c,
						                                                           EPPS_EFT_Transaction_Id__c,
						                                                           Last_EPPS_Integration__c,
						                                                           EPPS_Settlement_Date__c,
						                                                           EPPS_Returned_Date__c,
						                                                           EPPS_NSF_Return_Code__c,
						                                                           Payment_Plan__r.Status__c
						                                                           FROM Payment_Schedule_Item__c
						                                                           WHERE
						                                                           EPPS_EFT_Transaction_Id__c IN :theEFTTransactionIds];

						//  Loop through the returned records and match up with a returned EFT and update the info.
						for (Payment_Schedule_Item__c thePaymentScheduleItem : thePaymentScheduleItems)
						{
							EPPSHelperMethods.FindEFT_Wrapper theWrapper = response.FoundEFTs.get(thePaymentScheduleItem.EPPS_EFT_Transaction_Id__c);
							if (theWrapper != null)
							{
								thePaymentScheduleItem.EPPS_EFT_Status__c = theWrapper.StatusCode;
								thePaymentScheduleItem.Last_EPPS_Integration__c = Datetime.now();
								thePaymentScheduleItem.EPPS_Settlement_Date__c = EPPSHelperMethods.safeDate(theWrapper.SettledDate);
								thePaymentScheduleItem.EPPS_Returned_Date__c = EPPSHelperMethods.safeDate(theWrapper.ReturnedDate);
								thePaymentScheduleItem.EPPS_NSF_Return_Code__c = theWrapper.NSFReturnCode;
								thePaymentScheduleItem.EPPS_Status_Date__c = EPPSHelperMethods.safeDate(theWrapper.StatusDate);

								if (EPPSHelperMethods.safeString(theWrapper.NSFReturnCode) == '')
								{
									if (EPPSHelperMethods.safeString(theWrapper.StatusCode) == EPPSHelperMethods.EPPS_EFT_STATUS_SETTLED)
									{
										thePaymentScheduleItem.Status__c = EPPSHelperMethods.EPPS_EFT_STATUS_CLEARED;
									}
								}
								else
								{
									thePaymentScheduleItem.Status__c = TranslateStatusCode(EPPSHelperMethods.safeString(theWrapper.NSFReturnCode));
								}

								DontAddDuplicates(thePaymentSchedulesToUpdateList, thePaymentScheduleItem);
							}
						}

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

			}
            update thePaymentSchedulesToUpdateList;
    
            StartNextQueue();
		}
		catch(Exception e)
		{
			IntegrationLogUtil.createLog(
			                             IntegrationLogUtil.logBuilder()
			                             .settings('EPPS_Integration_Setting__mdt')
			                             .objectMeta('EPPS_Integration_Object__mdt')
			                             .method('findEftByIDandDate')
			                             .exceptionMsg(EPPSHelperMethods.getExceptionDetails(e))
			                             .status(IntegrationLogUtil.LogStatus.Failure)
			                             .build());
            
            cardHolderIDsToRemove.add(CurrentCardHolderID);
			update thePaymentSchedulesToUpdateList;
			StartNextQueue();

		}
	}

	private static string TranslateStatusCode(string theRCode)
	{
		if (theR_CodesMap.containsKey(theRCode) == true)
		{
			return theR_CodesMap.get(theRCode);
		}
		return 'Unknown RCode Value';
	}

	static Map<String, String> theR_CodesMap = new Map<String, String> ();

	private static void GetR_CodeRecords()
	{
		List<EPPS_R_Code_Map__mdt> theR_CodeRecords = [SELECT R_Code__c, Status__c FROM EPPS_R_Code_Map__mdt];

		for (EPPS_R_Code_Map__mdt theR_Code : theR_CodeRecords)
		{
			theR_CodesMap.put(theR_Code.R_Code__c, theR_Code.Status__c);
		}       
	}

	private void StartNextQueue()
	{
		IntegrationLogUtil.flush();
        
        if (cardHolderIDsToRemove != null)
        {
            theCardHolderIDs.removeAll(cardHolderIDsToRemove);
        }

		if (theCardHolderIDs.size() > 0 && Test.isRunningTest() == false)
		{
			//  If we still have some cardholders left, start the queueable with the new list minus what was already processed.
			System.enqueueJob(new EPPSFindEFTsByCardholderIDQueueable(theCardHolderIDs)); // Start the Queueable
		} else
		{
			Map<String, Object> settings = IntegrationLogUtil.getMetadataFieldValues(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT);
			Integer batchSize = Integer.valueOf(settings.get('Batch_Size_for_Settlement_Fee_Status__c'));
			if (!Test.isRunningTest())
			{
				Database.executeBatch(new EPPSSettlementFeeStatusBatch(), batchSize);
			}
		}
	}

	private void DontAddDuplicates(List<Payment_Schedule_Item__c> theList, Payment_Schedule_Item__c theItem)
	{
		for (Payment_Schedule_Item__c theListItem : theList)
		{
			if (theListItem.Id == theItem.Id)
				return;
		}
		theList.add(theItem);
	}

}