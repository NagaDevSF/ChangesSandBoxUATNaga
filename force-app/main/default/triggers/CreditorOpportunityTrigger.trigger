trigger CreditorOpportunityTrigger on CreditorOpportunity__c (before insert, before update, before delete, 
																after insert, after update, after delete, after undelete) {

	if (Trigger.isInsert && Trigger.isBefore) {
		CreditorOpportunityTriggerHandler.blockDMLWhileRelatedOppIsLocked(Trigger.new);
	}
	
	if (Trigger.isUpdate && Trigger.isAfter) {
		CreditorOpportunityTriggerHandler.blockDMLWhileRelatedOppIsLocked(Trigger.new);
	}
	
	if (Trigger.isDelete && Trigger.isAfter) {
		CreditorOpportunityTriggerHandler.blockDMLWhileRelatedOppIsLocked(Trigger.old);
	}																
}