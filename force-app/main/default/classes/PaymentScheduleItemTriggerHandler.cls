public class PaymentScheduleItemTriggerHandler {

	public static final String APPROVAL_BLOCK_MSG = 'You cannot create, modify or delete this record because the related Opportunity is locked for approval.';

    // test coverage provided in CreditorOpportunityTriggerHandlerTest
	public static void blockDMLWhileRelatedOppIsLocked(List<Payment_Schedule_Item__c> psiList) {

		for (Payment_Schedule_Item__c psi : psiList) {
			if (String.isNotBlank(psi.Related_Opportunity__c) && Approval.isLocked(psi.Related_Opportunity__c)) {
				psi.addError(APPROVAL_BLOCK_MSG);
			}
		}
	}
}