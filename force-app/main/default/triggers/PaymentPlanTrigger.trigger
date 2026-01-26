trigger PaymentPlanTrigger on PaymentPlan__c (before insert, before update, before delete, 
												after insert, after update, after delete, after undelete) {
												
	if (Trigger.isInsert && Trigger.isBefore) {
		PaymentPlanTriggerHandler.blockDMLWhileRelatedOppIsLocked(Trigger.new);
	}
	
	if (Trigger.isUpdate && Trigger.isAfter) {
		PaymentPlanTriggerHandler.blockDMLWhileRelatedOppIsLocked(Trigger.new);
	}
	
	if (Trigger.isDelete && Trigger.isAfter) {
		PaymentPlanTriggerHandler.blockDMLWhileRelatedOppIsLocked(Trigger.old);
	}													
}