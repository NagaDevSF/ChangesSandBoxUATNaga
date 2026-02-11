/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : OpportunityTriggerHandler
 * Author          : Shell Black (Scott Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jan 27, 2026
 * Description     : This class is the handler class for the Opportunity trigger
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Scott Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
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

		//  Get a list of accounts related to the optys		
		Map<Id, Account> theAccountMap = new Map<Id, Account>([SELECT Id, Account_Holder_Name__c, Account_Holder_Last_Name__c,
											Acct_Street_Address__c, City__c, State1__c, Zip_Code__c, EPPS_ID__c,
											Acct_Phone__c, Email__c, Date_of_Birth__c, EPPS_Cardholder_Sequence__c,
											BillingStreet, BillingState, BillingCity, BillingPostalCode
											FROM Account WHERE Id IN: accountIds]);

		if (!oppList.isEmpty()) {
			 PaymentPlanService.buildPaymentScheduleItems(oppSignedList);

			//  If it is moving to signed, we need to add a cardholder to EPPS.
			//  Build AddCardHolder Wrappers for each Opty moving to signed for any account that is not established in EPPS.
			List<EPPSHelperMethods.Cardholder_Wrapper> theCardholderWrappers = new	List<EPPSHelperMethods.Cardholder_Wrapper>();
			for (Opportunity opt: oppSignedList) {
				
				// temporary condition, we only want to send if the opp is marked as Integrate to EPPS
				if (opt.Integrate_with_EPPS__c) {
					Account theAccount = theAccountMap.get(opt.AccountId);
				
					if (String.isBlank(theAccount.EPPS_ID__c)) {
						EPPSHelperMethods.Cardholder_Wrapper theWrapper = new
						EPPSHelperMethods.Cardholder_Wrapper(EPPSHelperMethods.EPPSOperation.EPPS_ADD_CARDHOLDER,
															theAccount.Id,
															theAccount.EPPS_Cardholder_Sequence__c,
															theAccount.Account_Holder_Name__c,
															theAccount.Account_Holder_Last_Name__c,
															theAccount.BillingStreet,
															theAccount.BillingCity,
															theAccount.BillingState,
															theAccount.BillingPostalCode,
															theAccount.Acct_Phone__c,
															theAccount.Email__c);
				
						theCardholderWrappers.add(theWrapper);		
					}
				}
			}
			if (!theCardholderWrappers.isEmpty()) {
				ChunkCardholderWrappers (theCardholderWrappers);
			}
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

	public static void ChunkCardholderWrappers (List<EPPSHelperMethods.Cardholder_Wrapper> theCardholderWrapperList) {
		
		// TODO need to add coverage to support the split to work around gov limits
		if (theCardholderWrapperList.isEmpty() == false) {
			System.enqueueJob(new EPPSManageCardHolderQueueable(theCardholderWrapperList));
		}
		/*if (theCardholderWrapperList.isEmpty() == false) {
			if (theCardholderWrapperList.size() <= 50) {
				System.enqueueJob(new EPPSManageCardHolderQueueable(theCardholderWrapperList));

			} else {

				integer counter = theCardholderWrapperList.size();

				List<EPPSHelperMethods.Cardholder_Wrapper> wrapper0 = new List<EPPSHelperMethods.Cardholder_Wrapper>();
				List<EPPSHelperMethods.Cardholder_Wrapper> wrapper1 = new List<EPPSHelperMethods.Cardholder_Wrapper>();
				List<EPPSHelperMethods.Cardholder_Wrapper> wrapper2 = new List<EPPSHelperMethods.Cardholder_Wrapper>();
				List<EPPSHelperMethods.Cardholder_Wrapper> wrapper3 = new List<EPPSHelperMethods.Cardholder_Wrapper>();
				List<EPPSHelperMethods.Cardholder_Wrapper> wrapper4 = new List<EPPSHelperMethods.Cardholder_Wrapper>();

				for(Integer i = 0; i < counter; i++) {
					
					switch on Math.mod(i,5) {
						when 0{wrapper0.add(theCardholderWrapperList[i]);}
						when 1{wrapper1.add(theCardholderWrapperList[i]);}
						when 2{wrapper2.add(theCardholderWrapperList[i]);}
						when 3{wrapper3.add(theCardholderWrapperList[i]);}	
						when 4{wrapper4.add(theCardholderWrapperList[i]);}	
					}

				}

				System.enqueueJob(new EPPSManageCardHolderQueueable(wrapper0));
				System.enqueueJob(new EPPSManageCardHolderQueueable(wrapper1));
				System.enqueueJob(new EPPSManageCardHolderQueueable(wrapper2));
				System.enqueueJob(new EPPSManageCardHolderQueueable(wrapper3));
				System.enqueueJob(new EPPSManageCardHolderQueueable(wrapper4));
			}
		}*/
	}
}