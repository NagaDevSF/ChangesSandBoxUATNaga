/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSSettlementFeeStatusBatch
 * Author          : Shell Black (Sean Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By:
 * Last Modified On: Jan 27, 2026
 * Description     : Batch class to find settlement fees and update their status.
 *					 When this batch completes, the payment status batch is ran
 *                   The settlement batch should not be scehdule separetly or it 
 *					 Will run twice.
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Sean Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
public class EPPSSettlementFeeStatusBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable 
{
	//  This is the method required for this batch to be scheduable.
    public void execute(SchedulableContext sc) 
	{       			
		Map<String, Object> settings = IntegrationLogUtil.getMetadataFieldValues(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT);									
		Integer batchSize = Integer.valueOf(settings.get('Batch_Size_for_Settlement_Fee_Status__c'));
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
										Settlement_Plan_Item__r.Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Zip_Code__c,
										Settlement_Plan_Item__r.Settlement_Plan__r.Id
										FROM Settlement_Fee__c
										WHERE Settlement_Plan_Item__r.Status__c = 'Processing'     
										AND Fee_Id__c != null         
										//AND Payment_Plan__r.Status__c = 'Active'  ************ TODO!
									]);
    }

	static string theSettlementType;
	static Map<Id, Settlement_Plan_Item__c> theSettlementPlanItems;
	static List<Settlement_Plan_Item__c> settlementPlanItemsToUpdate = new List<Settlement_Plan_Item__c>();

	//  Method executed per batch of records.
    public void execute(Database.BatchableContext bc, List<Settlement_Fee__c> scope) 
	{
		theSettlementType = EPPSHelperMethods.getSettlementPaymentType();

		//  gather all of the Settlement_Plan_Item__c records related to these Settlement Fees
		Set<Id> SettlementPlanItemIds = new Set<Id>();
		for (Settlement_Fee__c item : scope)
		{
			SettlementPlanItemIds.add(item.Settlement_Plan_Item__r.Id);
		}	
		
		theSettlementPlanItems = new Map<Id, Settlement_Plan_Item__c>([SELECT Id, Status__c FROM Settlement_Plan_Item__c WHERE Id IN: SettlementPlanItemIds]);

		//  Callout skipped if the FEE ID is blank/null
		for (Settlement_Fee__c item : scope)
		{		
			item =  CalloutAndPopulateFields(item);			
		}

		Database.update(scope);

		Database.update(settlementPlanItemsToUpdate);

		IntegrationLogUtil.flush();
	}
	
	public Settlement_Fee__c CalloutAndPopulateFields(Settlement_Fee__c item)
	{
		EPPSHelperMethods.EPPSResponse response;
		try
		{
			EPPSHelperMethods.FindFee_Wrapper itemWrapper = new	EPPSHelperMethods.FindFee_Wrapper();							

			itemWrapper.FeeID = item.Fee_Id__c;
			
			// Callout to EPPS
			response = EPPSIntegrationMethodsEnhanced.findFeeById(itemWrapper);
			if (response.success) 
			{	
                if (response.FoundFees.containsKey(item.Fee_Id__c) == false)
                {
                    return item;  //  can happen if the fee being polled does not exist in EPPS
                }
                
				EPPSHelperMethods.FindFee_Wrapper wrapper = response.FoundFees.get(item.Fee_Id__c);
				
				item.Transaction_Id__c = EPPSHelperMethods.safeString(wrapper.EftTransactionID);
				item.Status_Code__c = EPPSHelperMethods.safeString(wrapper.StatusCode);

				if (item.Type__c == theSettlementType)
				{
					//  Get the Settlement_Plan_Item__c
					if (theSettlementPlanItems.containsKey(item.Settlement_Plan_Item__r.Id) == true)
					{
						Settlement_Plan_Item__c thePlanItem = theSettlementPlanItems.get(item.Settlement_Plan_Item__r.Id);

						if (EPPSHelperMethods.safeString(wrapper.StatusCode) == EPPSHelperMethods.SETTLEMENT_FEE_STATUS_CODE_VOID)
						{
							thePlanItem.Status__c = EPPSHelperMethods.SETTLEMENT_FEE_STATUS_CODE_VOID;
						}
						if (EPPSHelperMethods.safeString(wrapper.StatusCode) == EPPSHelperMethods.SETTLEMENT_FEE_STATUS_CODE_TRANSMITTED)
						{
							thePlanItem.Status__c = EPPSHelperMethods.SETTLEMENT_PLAN_ITEM_STATUS_CLEARED;
						}

						settlementPlanItemsToUpdate.add(thePlanItem);
					}
				}

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
            .request(response.SOAPRequestBody)
			.response(response.SOAPResponseBody)
			.httpCode(response.HTTPResponseCode).method('findFeeById')
			.exceptionMsg(EPPSHelperMethods.getExceptionDetails(e))
			.status(IntegrationLogUtil.LogStatus.Failure)
			.build());
		}
		return item;
	}

    public void finish(Database.BatchableContext bc) 
	{
		//  When it is done, start the payment fee status batch
		if (Test.isRunningTest() == false)
		{
			Map<String, Object> settings = IntegrationLogUtil.getMetadataFieldValues(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT);
			Integer batchSize = Integer.valueOf(settings.get('Batch_Size_for_Payment_Fee_Status_Batch__c'));
			Database.executeBatch(new EPPSPaymentFeeStatusBatch(), batchSize);
   
		}
    }
}