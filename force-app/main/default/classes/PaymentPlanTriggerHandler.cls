public class PaymentPlanTriggerHandler {

    // ==================================================================================
    // DEBUG LOGGING CONSTANTS
    // ==================================================================================
    private static final String LOG_PREFIX = '[PaymentPlanTriggerHandler]';
    private static final String LOG_ENTRY = '▶️';
    private static final String LOG_WARN = '⚠️';
    private static final String LOG_ERROR = '❌';

    public static final String APPROVAL_BLOCK_MSG = 'You cannot create, modify or delete this record because the related Opportunity is locked for approval.';

    public static final String DUPLICATE_ACTIVE_MSG = 'An active Payment Plan already exists for this Opportunity. Please deactivate the existing plan before activating a new one.';

    // ==================================================================================
    // RECURSION GUARDS
    // ==================================================================================
    private static Boolean isPreventDuplicateExecuting = false;
    private static Boolean isBlockDMLExecuting = false;

    public static void preventDuplicateActivePaymentPlans(List<PaymentPlan__c> newList, Map<Id, PaymentPlan__c> oldMap) {
        if (isPreventDuplicateExecuting) {
            return;
        }
        isPreventDuplicateExecuting = true;

        try {
            List<PaymentPlan__c> activePlans = new List<PaymentPlan__c>();
            Set<Id> oppIds = new Set<Id>();
            Set<Id> triggerRecordIds = new Set<Id>();

            for (PaymentPlan__c pp : newList) {
                if (pp.Status__c == 'Active' && pp.Opportunity__c != null) {
                    Boolean isNew = (oldMap == null);
                    Boolean statusChanged = (!isNew && pp.Status__c != oldMap.get(pp.Id).Status__c);
                    if (isNew || statusChanged) {
                        activePlans.add(pp);
                        oppIds.add(pp.Opportunity__c);
                        if (pp.Id != null) {
                            triggerRecordIds.add(pp.Id);
                        }
                    }
                }
            }

            if (activePlans.isEmpty()) {
                return;
            }

            // Query existing active plans outside the trigger batch
            Set<Id> oppsWithActivePlan = new Set<Id>();
            for (PaymentPlan__c existing : [
                SELECT Id, Opportunity__c
                FROM PaymentPlan__c
                WHERE Opportunity__c IN :oppIds
                  AND Status__c = 'Active'
                  AND Id NOT IN :triggerRecordIds
            ]) {
                oppsWithActivePlan.add(existing.Opportunity__c);
            }

            // Detect duplicates within the same trigger batch
            Set<Id> oppsSeenInBatch = new Set<Id>();
            for (PaymentPlan__c pp : activePlans) {
                if (oppsWithActivePlan.contains(pp.Opportunity__c) || oppsSeenInBatch.contains(pp.Opportunity__c)) {
                    pp.addError(DUPLICATE_ACTIVE_MSG);
                } else {
                    oppsSeenInBatch.add(pp.Opportunity__c);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_PREFIX + ' ' + LOG_ERROR + ' preventDuplicateActivePaymentPlans failed: ' + e.getMessage() + ' | StackTrace: ' + e.getStackTraceString());
            throw e;
        } finally {
            isPreventDuplicateExecuting = false;
        }
    }

    public static void blockDMLWhileRelatedOppIsLocked(List<PaymentPlan__c> ppList) {
        if (isBlockDMLExecuting) {
            return;
        }
        isBlockDMLExecuting = true;

        try {
            System.debug(LOG_PREFIX + ' ' + LOG_ENTRY + ' blockDMLWhileRelatedOppIsLocked | recordCount=' + (ppList != null ? ppList.size() : 0));

            Set<Id> oppIds = new Set<Id>();
            for (PaymentPlan__c pp : ppList) {
                if (pp.Opportunity__c != null) {
                    oppIds.add(pp.Opportunity__c);
                }
            }

            if (oppIds.isEmpty()) {
                return;
            }

            // Bulkified lock check — single call for all Opportunity IDs
            Map<Id, Boolean> lockStatus = Approval.isLocked(new List<Id>(oppIds));

            for (PaymentPlan__c pp : ppList) {
                if (pp.Opportunity__c != null && lockStatus.containsKey(pp.Opportunity__c) && lockStatus.get(pp.Opportunity__c)) {
                    System.debug(LOG_PREFIX + ' ' + LOG_WARN + ' Blocking DML - Opportunity locked | oppId=' + pp.Opportunity__c);
                    pp.addError(APPROVAL_BLOCK_MSG);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_PREFIX + ' ' + LOG_ERROR + ' blockDMLWhileRelatedOppIsLocked failed: ' + e.getMessage() + ' | StackTrace: ' + e.getStackTraceString());
            throw e;
        } finally {
            isBlockDMLExecuting = false;
        }
    }
}