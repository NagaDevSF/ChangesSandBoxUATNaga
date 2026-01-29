/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSPaymentFeeBatch
 * Author          : Shell Black (Scott Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jan 27, 2026
 * Description     : Batch Class to Process Payment Fees
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Scott Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
public class EPPSPaymentFeeBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Schedulable {

	@TestVisible
	private static Boolean FORCE_EXCEPTION_IN_EXECUTE = false;

	public void execute(SchedulableContext sc) {

		Map<String, Object> settings = IntegrationLogUtil.getMetadataFieldValues(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT);
		Integer batchSize = Integer.valueOf(settings.get('Batch_Size_for_Payment_Fee_Batch__c'));
		Database.executeBatch(new EPPSPaymentFeeBatch(), batchSize);
	}

	public Database.QueryLocator start(Database.BatchableContext bc) {

		Map<String, Object> settings = IntegrationLogUtil.getMetadataFieldValues(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT);
		Date targetDate = EPPSHelperMethods.getDateAfterBusinessDays(Integer.valueOf(settings.get('Lookback_for_Payment_Fee_Batch__c')));

		return Database.getQueryLocator([
		                                SELECT Id, Payment_Date__c,
		                                Payment_Plan__r.Opportunity__r.Account.EPPS_Id__c,
										(SELECT Id, Amount__c, Type__c, Fee_Id__c, Status_Code__c
										FROM Payment_Fees__r WHERE Type__c != null
										AND Amount__c != null AND Fee_Id__c = null)
		                                FROM Payment_Schedule_Item__c
		                                WHERE EPPS_EFT_Status__c IN :EPPSHelperMethods.EPPS_SETTLED_STATUS
		                                AND Payment_Plan__r.Status__c = :EPPSHelperMethods.PAYMENT_PLAN_STATUS_ACTIVE
										AND Payment_Plan__r.Opportunity__r.Integrate_with_EPPS__c = true // temporary control to limit API interactions with EPPS
		                                ]);
	}

	public void execute(Database.BatchableContext bc, List<Payment_Schedule_Item__c> scope) {

		List<Payment_Fee__c> pfUpdates = new List<Payment_Fee__c> ();

		Map<Id, List<EPPSPaymentFeeBatchHelper.AddFee2Wrapper>> psiWrapper = EPPSPaymentFeeBatchHelper.buildAPICallMap(scope);

		for (Id psiId : psiWrapper.keySet()) {

			for (EPPSPaymentFeeBatchHelper.AddFee2Wrapper wrapper : psiWrapper.get(psiId)) {

				try {

					if (FORCE_EXCEPTION_IN_EXECUTE) {
						throw new CalloutException('Forced batch exception for test');
					}

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

					Payment_Fee__c thisFSD = new Payment_Fee__c(Id = wrapper.feeSettlementId);
					
					if (String.isNotBlank(resp.FeeID)) {
						thisFSD.Fee_Id__c = resp.FeeID;
					}

					thisFSD.Status_Code__c = resp.Success ? 'Sent to EPPS' : 'Failed to EPPS';

					pfUpdates.add(thisFSD);

				} catch(Exception e) {
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

					pfUpdates.add(new Payment_Fee__c(Id = wrapper.feeSettlementId, Status_Code__c = 'Failed to EPPS'));
				}
			}
		}

		IntegrationLogUtil.flush();

		if (!pfUpdates.isEmpty()) {
			Database.update(pfUpdates);
		}
	}

	public void finish(Database.BatchableContext bc) {
		Map<String, Object> settings = IntegrationLogUtil.getMetadataFieldValues(EPPSHelperMethods.EPPS_INTEGRATION_SETTING_MDT);
        Integer batchSize = Integer.valueOf(settings.get('Batch_Size_for_Settlement_Fee_Batch__c'));
        Database.executeBatch(new EPPSSettlementFeeBatch(), batchSize);
	}
}