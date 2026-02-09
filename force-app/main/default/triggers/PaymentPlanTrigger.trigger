trigger PaymentPlanTrigger on PaymentPlan__c (before insert, before update, before delete) {

    if (Trigger.isBefore && Trigger.isInsert) {
        PaymentPlanTriggerHandler.blockDMLWhileRelatedOppIsLocked(Trigger.new);
        PaymentPlanTriggerHandler.preventDuplicateActivePaymentPlans(Trigger.new, null);
    }

    if (Trigger.isBefore && Trigger.isUpdate) {
        PaymentPlanTriggerHandler.blockDMLWhileRelatedOppIsLocked(Trigger.new);
        PaymentPlanTriggerHandler.preventDuplicateActivePaymentPlans(Trigger.new, Trigger.oldMap);
    }

    if (Trigger.isBefore && Trigger.isDelete) {
        PaymentPlanTriggerHandler.blockDMLWhileRelatedOppIsLocked(Trigger.old);
    }
}
