trigger PaymentPlanTrigger on PaymentPlan__c (before insert, before update, before delete, 
												after insert, after update, after delete, after undelete) {
												
	if (Trigger.isInsert && Trigger.isBefore) {
		PaymentPlanTriggerHandler.blockDMLWhileRelatedOppIsLocked(Trigger.new);
		PaymentPlanTriggerHandler.preventDuplicateActivePaymentPlans(Trigger.new, null);
	}

	if (Trigger.isUpdate && Trigger.isBefore) {
		PaymentPlanTriggerHandler.preventDuplicateActivePaymentPlans(Trigger.new, Trigger.oldMap);
	}

	if (Trigger.isUpdate && Trigger.isAfter) {
		PaymentPlanTriggerHandler.blockDMLWhileRelatedOppIsLocked(Trigger.new);
	}
	
	if (Trigger.isDelete && Trigger.isAfter) {
		PaymentPlanTriggerHandler.blockDMLWhileRelatedOppIsLocked(Trigger.old);
	}													
}