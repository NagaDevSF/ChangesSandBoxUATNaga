trigger PaymentScheduleItemTrigger on Payment_Schedule_Item__c (before insert, before update, before delete,
																after insert, after update, after delete, after undelete) {

	if (Trigger.isInsert && Trigger.isBefore) {
		PaymentScheduleItemTriggerHandler.blockDMLWhileRelatedOppIsLocked(Trigger.new);
	}

	if (Trigger.isUpdate && Trigger.isAfter) {
		PaymentScheduleItemTriggerHandler.blockDMLWhileRelatedOppIsLocked(Trigger.new);

		// Recalculate Draft Numbers when Status changes (skip if already in recursion)
		if (!TriggerRecursionControl.isRecalculatingDraftNumbers) {
			PaymentScheduleItemTriggerHandler.recalculateDraftNumbersOnStatusChange(Trigger.new, Trigger.oldMap);
		}
	}

	if (Trigger.isDelete && Trigger.isAfter) {
		PaymentScheduleItemTriggerHandler.blockDMLWhileRelatedOppIsLocked(Trigger.old);
	}
}