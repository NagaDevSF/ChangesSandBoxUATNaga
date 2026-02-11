public class CreditorOpportunityTriggerHandler {

    public static final String APPROVAL_BLOCK_MSG = 'You cannot create, modify or delete this record because the related Opportunity is locked for approval.';
    
	public static void blockDMLWhileRelatedOppIsLocked(List<CreditorOpportunity__c> coList) {
		
		for (CreditorOpportunity__c co : coList) {
			if (String.isNotBlank(co.Opportunity__c) && Approval.isLocked(co.Opportunity__c)) {
				co.addError(APPROVAL_BLOCK_MSG);
			}
		}
	}
}