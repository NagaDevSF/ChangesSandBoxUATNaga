/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSSettlementFeeBatch
 * Author          : Shell Black (Scott Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jan 27, 2026
 * Description     : Batch Class to Process Settlement Fees
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Scott Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
public class EPPSSettlementFeeBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {

    public void execute(SchedulableContext sc) {
	Map<String, Object> settings = IntegrationLogUtil.getMetadataFieldValues(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT);
        Integer batchSize = Integer.valueOf(settings.get('Batch_Size_for_Settlement_Fee_Batch__c'));
         Database.executeBatch(new EPPSSettlementFeeBatch(), batchSize);
    }
    public Database.QueryLocator start(Database.BatchableContext bc) {

		Date targetDate = Date.today();

        return Database.getQueryLocator([
            SELECT Id, Payment_Date__c,
            Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__c,
			Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Account_Number__c,
			Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Routing__c,
            Settlement_Plan__r.CreditorOpportunity__r.Opportunity__r.Account.EPPS_Id__c	,
			Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Name,
			Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Street_Address__c,
			Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.City__c,
			Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Bank_Phone__c,
			Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.State__c,
			Settlement_Plan__r.CreditorOpportunity__r.Account_Bank_Information__r.Zip_Code__c,
			Settlement_Plan__r.CreditorOpportunity__r.Settlement_Contact__r.Name,
			(SELECT Id, Amount__c, Type__c, Fee_Id__c, Status_Code__c
			 FROM Settlement_Fees__r WHERE Type__c != null)
            FROM Settlement_Plan_Item__c
            WHERE Status__c =: EPPSHelperMethods.SETTLEMENT_PLAN_ITEM_STATUS_SCHEDULED
              AND Payment_Date__c = :targetDate
			 AND Settlement_Plan__r.Status__c =: EPPSHelperMethods.SETTLEMENT_PLAN_STATUS_ACTIVE
			 AND Settlement_Plan__r.CreditorOpportunity__r.Opportunity__r.Integrate_with_EPPS__c = true // temporary control to limit API interactions with EPPS
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Settlement_Plan_Item__c> scope) {

        List<Settlement_Plan_Item__c> spiUpdates = new List<Settlement_Plan_Item__c>();
		List<Settlement_Fee__c> sfUpdates = new List<Settlement_Fee__c>();

		Map<Id, List<EPPSSettlementFeeBatchHelper.AddFee2Wrapper>> spiWrapper = EPPSSettlementFeeBatchHelper.buildAPICallMap(scope);

		for (Id spiId : spiWrapper.keySet()) {

			Settlement_Plan_Item__c spiUpdate = new Settlement_Plan_Item__c(Id = spiId, 
												Status__c = EPPSHelperMethods.SETTLEMENT_PLAN_ITEM_STATUS_PROCESSING);

			for (EPPSSettlementFeeBatchHelper.AddFee2Wrapper wrapper : spiWrapper.get(spiId)) {		

				try {
					EPPSHelperMethods.EPPSResponse resp = EPPSIntegrationMethodsEnhanced.addFee2(wrapper.feeWrapper);

					IntegrationLogUtil.createLog(IntegrationLogUtil.logBuilder()
					                             .settings(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT)
                        						 .objectMeta(EPPSHelperMethods.EPPS_INTEGRATION_OBJ_MDT)
					                             .record(wrapper.feeSettlementId)
					                             .method('AddFee2')
					                             .request(resp.SOAPRequestBody)
					                             .response(resp.SOAPResponseBody)
					                             .httpCode(resp.HTTPResponseCode)
                                                 .exceptionMsg(resp.LastError)
					                             .status(resp.Success ? IntegrationLogUtil.LogStatus.Success : IntegrationLogUtil.LogStatus.Failure)
					                             .build());
		
					Settlement_Fee__c thisFSD = new Settlement_Fee__c(Id = wrapper.feeSettlementId);
					
					if (String.isNotBlank(resp.FeeID)) {
						thisFSD.Fee_Id__c = resp.FeeID;
					}

					thisFSD.Status_Code__c = resp.Success ? 'Sent to EPPS' : 'Failed to EPPS';

					sfUpdates.add(thisFSD);

				} catch (Exception e) {
					IntegrationLogUtil.createLog(IntegrationLogUtil.logBuilder()
					                             .settings(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT)
                        						 .objectMeta(EPPSHelperMethods.EPPS_INTEGRATION_OBJ_MDT)
					                             .record(wrapper.feeSettlementId)
					                             .method('AddFee2')
					                             .request(null)
					                             .response(null)
					                             .httpCode(null)
												 .exceptionMsg(EPPSHelperMethods.getExceptionDetails(e))
					                             .status(IntegrationLogUtil.LogStatus.Failure) 
					                             .build());
					
					sfUpdates.add(new Settlement_Fee__c(Id = wrapper.feeSettlementId, Status_Code__c = 'Failed to EPPS'));
				}
			}
			spiUpdates.add(spiUpdate);
		}
        
        IntegrationLogUtil.flush();
        
        if (!spiUpdates.isEmpty()) {
            Database.update(spiUpdates);
        }

		if (!sfUpdates.isEmpty()) {
			Database.update(sfUpdates);
		}
    }

    public void finish(Database.BatchableContext bc) {
        // Optional: Send summary email or future retry logic
    }
}