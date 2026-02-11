/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSPaymentFeeStatusBatch
 * Author          : Shell Black (Sean Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By:
 * Last Modified On: Jan 27, 2026
 * Description     : Batch class to find payment fees and update their status.
 *					 This class should not be scheduled.  It is ran when the 	
 *					 Settelement status batch completes.
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Sean Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
public class EPPSPaymentFeeStatusBatch implements Database.Batchable<SObject>, Database.AllowsCallouts 
{

    public Database.QueryLocator start(Database.BatchableContext bc) {

        Date targetDate = EPPSHelperMethods.getDateAfterBusinessDays(2);

        return Database.getQueryLocator([SELECT Id,
										Amount__c,
										Fee_Id__c,
										Name,
										Status_Code__c,
										Transaction_Id__c,
										Type__c
										FROM Payment_Fee__c
										WHERE Transaction_Id__c = null
										AND Fee_Id__c != null
										]);
    }

	//  Method executed per batch of records.
    public void execute(Database.BatchableContext bc, List<Payment_Fee__c> scope) 
	{
		for (Payment_Fee__c item : scope)
		{		
			item =  CalloutAndPopulateFields(item);			
		}

		Database.update(scope);

		IntegrationLogUtil.flush();
	}
	
	public Payment_Fee__c CalloutAndPopulateFields(Payment_Fee__c item)
	{
		try
		{
			EPPSHelperMethods.FindFee_Wrapper itemWrapper = new	EPPSHelperMethods.FindFee_Wrapper();							

			itemWrapper.FeeID = item.Fee_Id__c;
			
			// Callout to EPPS
			EPPSHelperMethods.EPPSResponse response = EPPSIntegrationMethodsEnhanced.findFeeById(itemWrapper);

			if (response.success) 
			{			
                if (response.FoundFees.containsKey(item.Fee_Id__c) == false)
                {
                    return item;  //  can happen if the fee being polled does not exist in EPPS
                }
                
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
		
		if (!Test.isRunningTest()) {
			Map<String, Object> settings = IntegrationLogUtil.getMetadataFieldValues(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT);
			Integer batchSize = Integer.valueOf(settings.get('Batch_Size_for_Client_Payment_Batch__c'));
			Database.executeBatch(new EPPSClientPaymentBatch(), batchSize);
		}
    }
}