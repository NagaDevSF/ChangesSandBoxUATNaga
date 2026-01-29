public class EPPSSettlementFeeStatusBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable 
{
	//  This is the method required for this batch to be scheduable.
    public void execute(SchedulableContext sc) 
	{       
												//  Change this to metadata record setting for EPPSSettlementFeeStatusBatch size
		Database.executeBatch(new EPPSSettlementFeeStatusBatch(), 5);
	}


    public Database.QueryLocator start(Database.BatchableContext bc) {

        Date targetDate = EPPSHelperMethods.getDateAfterBusinessDays(2);

        return Database.getQueryLocator([SELECT Id,
										Amount__c,
										Fee_Id__c,
										Name,
										Status_Code__c,
										Transaction_Id__c,
										Type__c,
										Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Opportunity__r.Account.EPPS_Id__c,		
										Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.City__c,
										Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Account_Number__c,
										Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Settlement_Contact__r.Name,
										Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.State__c,
										Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Street_Address__c,
										Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Zip_Code__c
										FROM Settlement_Fee__c
										WHERE Settlement_Plan_Item__r.Status__c = 'Processing'              
										//AND Payment_Plan__r.Status__c = 'Active'  ************ TODO!
									]);
    }

	//  Method executed per batch of records.
    public void execute(Database.BatchableContext bc, List<Settlement_Fee__c> scope) 
	{
		//  3 Callouts per record for each field containing a transaction ID.
		//  Payment_Amount_Eft_Transaction_Id__c, Bank_Fee_EFT_Transaction_Id__c, Commission_Fee_EFT_Transaction_Id__c
		//  Max callouts per execution 100.  Number of records per batch cannot exceed 100/number of fields to query on.
		//  Max Batch of 33 records

		//  Loop through the records, 1 callout per field
		//  Callout skipped if the FEE ID is blank/null
		for (Settlement_Fee__c item : scope)
		{		
			item =  CalloutAndPopulateFields(item);			
		}

		Database.update(scope);

		IntegrationLogUtil.flush();
	}
	
	public Settlement_Fee__c CalloutAndPopulateFields(Settlement_Fee__c item)
	{
		try
		{
			EPPSHelperMethods.FindFee_Wrapper itemWrapper = new	EPPSHelperMethods.FindFee_Wrapper();							

			itemWrapper.FeeID = item.Fee_Id__c;
			
			// Callout to EPPS
			EPPSHelperMethods.EPPSResponse response = EPPSIntegrationMethodsEnhanced.findFeeById(itemWrapper);

			if (response.success) 
			{			
				EPPSHelperMethods.FindFee_Wrapper wrapper = response.FoundFees.get(item.Fee_Id__c);

				item.Transaction_Id__c = EPPSHelperMethods.safeString(wrapper.EftTransactionID);
				item.Status_Code__c = EPPSHelperMethods.safeString(wrapper.StatusCode);
			
				//item.Status_Date__c = EPPSHelperMethods.safeDate(wrapper.StatusDate);				
				
				IntegrationLogUtil.createLog(
				IntegrationLogUtil.logBuilder()
				.settings(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT)
				.objectMeta(EPPSHelperMethods.EPPS_INTEGRATION_OBJ_MDT)
				.method('findFeeById')
				.request(response.SOAPRequestBody)
				.response(response.SOAPResponseBody)
				.httpCode(response.HTTPResponseCode)
				.status(response.Success ? IntegrationLogUtil.LogStatus.Success : IntegrationLogUtil.LogStatus.Failure)
				.build());

				}
				else
				{
					IntegrationLogUtil.createLog(
					IntegrationLogUtil.logBuilder()
					.settings(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT)
					.objectMeta(EPPSHelperMethods.EPPS_INTEGRATION_OBJ_MDT)
					.method('findFeeById')
					.request(response.SOAPRequestBody)
					.response(response.SOAPResponseBody)
					.httpCode(response.HTTPResponseCode)
					.status(response.Success ? IntegrationLogUtil.LogStatus.Success : IntegrationLogUtil.LogStatus.Failure)
					.build());
				}
		}
		catch (Exception e)
		{
			IntegrationLogUtil.createLog(
			IntegrationLogUtil.logBuilder()
			.settings(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT)
			.objectMeta(EPPSHelperMethods.EPPS_INTEGRATION_OBJ_MDT)
			.method('findFeeById')
			.exceptionMsg(EPPSHelperMethods.getExceptionDetails(e))
			.status(IntegrationLogUtil.LogStatus.Failure)
			.build());
		}
		return item;
	}

    public void finish(Database.BatchableContext bc) 
	{
		//  When it is done, start the 
 												//  Change this to metadata record setting for EPPSSettlementFeeStatusBatch size
		Database.executeBatch(new EPPSPaymentFeeStatusBatch(), 5);   
    }
}