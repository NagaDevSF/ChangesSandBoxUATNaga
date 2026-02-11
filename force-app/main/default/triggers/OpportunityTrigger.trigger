trigger OpportunityTrigger on Opportunity (after update) {
    if (Trigger.isUpdate && Trigger.isAfter) {
        OpportunityTriggerHandler.triggerPlatformEventForLWC(Trigger.new, Trigger.oldMap);
        OpportunityTriggerHandler.checkOppMovingToSignatureStage(Trigger.new, Trigger.oldMap);
    }
}