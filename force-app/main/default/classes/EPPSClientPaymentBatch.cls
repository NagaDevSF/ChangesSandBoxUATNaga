/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSClientPaymentBatch
 * Author          : Shell Black (Scot Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jan 27, 2026
 * Description     : This class is a batch apex class to find Payment Schedule Items
 *					 that need to be integrated with EPPS.
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Scott Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
 public class EPPSClientPaymentBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {
   
    public void execute(SchedulableContext sc) {

		Map<String, Object> settings = IntegrationLogUtil.getMetadataFieldValues(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT);
		Integer batchSize = Integer.valueOf(settings.get('Batch_Size_for_Client_Payment_Batch__c'));
		Database.executeBatch(new EPPSClientPaymentBatch(), batchSize);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {

        Date targetDate = EPPSHelperMethods.getDateAfterBusinessDays(2);

        return Database.getQueryLocator([
            SELECT Id, Payment_Date__c, Total_Payment__c, Bank2_Fee_Amount__c,
				   Payment_Plan__r.Opportunity__r.AccountId,
				   Payment_Plan__r.Opportunity__r.Account.EPPS_ID__c,
				   Payment_Plan__r.Opportunity__r.Account.Routing__c,
				   Payment_Plan__r.Opportunity__r.Account.Bank_Account__c,
				   Payment_Plan__r.Opportunity__r.Account.Bank_Account_Type__c
            	
            FROM Payment_Schedule_Item__c
            WHERE Status__c = :EPPSHelperMethods.PAYMENT_SCHEDULE_ITEM_STATUS_SCHEDULED
              AND Payment_Date__c = :targetDate
			  AND Payment_Plan__r.Status__c =: EPPSHelperMethods.PAYMENT_PLAN_STATUS_ACTIVE
			  AND Payment_Plan__r.Opportunity__r.Integrate_with_EPPS__c = true // temporary control to limit API interactions with EPPS
        ]); 
    }

    public void execute(Database.BatchableContext bc, List<Payment_Schedule_Item__c> scope) {

        List<Payment_Schedule_Item__c> psiUpdates = new List<Payment_Schedule_Item__c>();

		Set<Id> accountIds = new Set<Id>();
		
        for (Payment_Schedule_Item__c psi : scope) {

			// TODO add check that the relevant bank details are on the account
			// TODO check that the account has an EPPS ID

			try {

				EPPSHelperMethods.EFT_Wrapper wrapper = new EPPSHelperMethods.EFT_Wrapper(
				psi.Payment_Plan__r.Opportunity__r.Account.EPPS_ID__c,
				DateTime.newInstance(psi.Payment_Date__c,Time.newInstance(0,0,0,0)),
				psi.Total_Payment__c,
				psi.Bank2_Fee_Amount__c,
				psi.Payment_Plan__r.Opportunity__r.Account.Bank_Account__c,
				psi.Payment_Plan__r.Opportunity__r.Account.Routing__c,
				psi.Payment_Plan__r.Opportunity__r.Account.Bank_Account_Type__c,
				'',
				'');
					
				EPPSHelperMethods.EPPSResponse res = EPPSIntegrationMethodsEnhanced.AddEFT(wrapper);
                
				IntegrationLogUtil.createLog(IntegrationLogUtil.logBuilder()
					                            .settings(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT)
                        						.objectMeta(EPPSHelperMethods.EPPS_INTEGRATION_OBJ_MDT)
					                            .record(psi.Id)
					                            .method('AddEFT')
					                            .request(res.SOAPRequestBody)
					                            .response(res.SOAPResponseBody)
					                            .httpCode(res.HTTPResponseCode)
                                                .exceptionMsg(res.LastError)
					                            .status(res.Success ? IntegrationLogUtil.LogStatus.Success : IntegrationLogUtil.LogStatus.Failure)
					                            .build());

				// update PSI record with data from 
				if (res.Success) {
					psiUpdates.add(new Payment_Schedule_Item__c(Id = psi.Id, Last_EPPS_Integration__c = Datetime.now(),
									EPPS_EFT_Transaction_Id__c = String.valueOf(res.EftTransactionID), 
									Status__c = EPPSHelperMethods.PSI_STATUS_PROCESSING));
				} else {
					psiUpdates.add(new Payment_Schedule_Item__c(Id = psi.Id, Last_EPPS_Integration__c = Datetime.now(),
									Status__c = EPPSHelperMethods.PSI_STATUS_FAILED_TO_EPPS));
				}
			} catch (Exception e) {

				IntegrationLogUtil.createLog(IntegrationLogUtil.logBuilder()
					                            .settings(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT)
                        						.objectMeta(EPPSHelperMethods.EPPS_INTEGRATION_OBJ_MDT)
					                            .record(psi.Id)
					                            .method('AddEFT')
					                            .request(null)
					                            .response(null)
					                            .httpCode(null)
												.exceptionMsg(EPPSHelperMethods.getExceptionDetails(e))
					                            .status(IntegrationLogUtil.LogStatus.Failure) 
					                            .build());
					
				psiUpdates.add(new Payment_Schedule_Item__c(Id = psi.Id, Last_EPPS_Integration__c = Datetime.now(),
									Status__c = EPPSHelperMethods.PSI_STATUS_FAILED_TO_EPPS));

			}

		}
    
        IntegrationLogUtil.flush();
        
        if (!psiUpdates.isEmpty()) {
            Database.update(psiUpdates);
        }

	}

    public void finish(Database.BatchableContext bc) {

		if (!Test.isRunningTest()) {
			Map<String, Object> settings = IntegrationLogUtil.getMetadataFieldValues(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT);
			Integer batchSize = Integer.valueOf(settings.get('Batch_Size_for_Payment_Fee_Batch__c'));
			Database.executeBatch(new EPPSPaymentFeeBatch(), batchSize);
		}
    }
}