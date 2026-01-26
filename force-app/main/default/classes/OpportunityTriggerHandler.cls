public class OpportunityTriggerHandler {
	
    public static final String PAYMENT_DRAFT_SYNC_STATUS_OUT_OF_SYNC = 'Out of Sync';
	public static final String OPP_STAGE_SIGNED = 'Contract Signed';

	public static void checkOppMovingToSignatureStage(List<Opportunity> oppList, Map<Id, Opportunity> oldMap) {

		// gather Ids of Opps moving to Signature Stage
		List<Opportunity> oppSignedList = new List<Opportunity>();
		List<Id> accountIds = new List<Id>();
		for (Opportunity opp : oppList) {
			if (String.isNotBlank(opp.StageName) && opp.StageName == OPP_STAGE_SIGNED
				&& opp.StageName != oldMap.get(opp.Id).StageName) {
					
				oppSignedList.add(opp);
				accountIds.add(opp.AccountId);
			}
		}

		if (!oppSignedList.isEmpty()) {
			 PaymentPlanService.buildPaymentScheduleItems(oppSignedList);
		}
	}
    
	public static void triggerPlatformEventForLWC(List<Opportunity> oppList, Map<Id, Opportunity> oldMap) {

		Map<Id, OpportunityUpdate__e> eventsMap = new Map<Id, OpportunityUpdate__e>();
		Set<Id> oppIdsSet = new Set<Id>();

		for (Opportunity opp : oppList) {

			if ((opp.Estimated_Total_Debt__c != oldMap.get(opp.Id).Estimated_Total_Debt__c)
			    || opp.Estimated_Current_Payment__c != oldMap.get(opp.Id).Estimated_Current_Payment__c) {

				oppIdsSet.add(opp.Id);
			}

		}
		if (!oppIdsSet.isEmpty()) {
			// we have at least one Opportunity where Total Debt and/or Estimated Current Payment changed
			List<PaymentDraft__c> pdList = [SELECT Id, Is_Active__c, Is_Primary__c, Sync_Status__c, 
											Invalidated_Date__c, Opportunity__c
											FROM PaymentDraft__c WHERE Opportunity__c IN :oppIdsSet
											AND Invalidated_Date__c = null];

			for (PaymentDraft__c pd : pdList) {
				pd.Is_Active__c = false;
				pd.Is_Primary__c = false;
				pd.Sync_Status__c = PAYMENT_DRAFT_SYNC_STATUS_OUT_OF_SYNC;
				pd.Invalidated_Date__c = Date.today();

				if (!eventsMap.containsKey(pd.Opportunity__c)) {
					// create platform event 
					OpportunityUpdate__e ev = new OpportunityUpdate__e(OpportunityId__c = pd.Opportunity__c, 
																		RecordId__c = pd.Opportunity__c,
																		Payment_Draft_Invalidated__c = true);
					eventsMap.put(pd.Opportunity__c, ev);
				}
			}

			// check if we have any Opportunities where a Payment Draft wasnt found
			for (Id oppId : oppIdsSet) {
				if (!eventsMap.containsKey(oppId)) {
					OpportunityUpdate__e ev = new OpportunityUpdate__e(OpportunityId__c = oppId, 
																		RecordId__c = oppId,
																		Payment_Draft_Invalidated__c = false);
					eventsMap.put(oppId, ev);
				}
			}
	
			update pdList;
			EventBus.publish(eventsMap.values());
		}
	}
}