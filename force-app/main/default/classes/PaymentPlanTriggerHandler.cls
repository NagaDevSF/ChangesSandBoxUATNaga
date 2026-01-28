public class PaymentPlanTriggerHandler {

    // ==================================================================================
    // DEBUG LOGGING CONSTANTS
    // ==================================================================================
    private static final String LOG_PREFIX = '[PaymentPlanTriggerHandler]';
    private static final String LOG_ENTRY = '▶️';
    private static final String LOG_WARN = '⚠️';

	public static final String APPROVAL_BLOCK_MSG = 'You cannot create, modify or delete this record because the related Opportunity is locked for approval.';

    // test coverage provided in CreditorOpportunityTriggerHandlerTest
	public static void blockDMLWhileRelatedOppIsLocked(List<PaymentPlan__c> ppList) {
        System.debug(LOG_PREFIX + ' ' + LOG_ENTRY + ' blockDMLWhileRelatedOppIsLocked | recordCount=' + (ppList != null ? ppList.size() : 0));

		for (PaymentPlan__c pp : ppList) {
			if (String.isNotBlank(pp.Opportunity__c) && Approval.isLocked(pp.Opportunity__c)) {
                System.debug(LOG_PREFIX + ' ' + LOG_WARN + ' Blocking DML - Opportunity locked | oppId=' + pp.Opportunity__c);
				pp.addError(APPROVAL_BLOCK_MSG);
			}
		}
	}
}