public class PaymentPlanTriggerHandler {

	public static final String APPROVAL_BLOCK_MSG = 'You cannot create, modify or delete this record because the related Opportunity is locked for approval.';

    // test coverage provided in CreditorOpportunityTriggerHandlerTest
	public static void blockDMLWhileRelatedOppIsLocked(List<PaymentPlan__c> ppList) {
		
		for (PaymentPlan__c pp : ppList) {
			if (String.isNotBlank(pp.Opportunity__c) && Approval.isLocked(pp.Opportunity__c)) {
				pp.addError(APPROVAL_BLOCK_MSG);
			}
		}
	}
}