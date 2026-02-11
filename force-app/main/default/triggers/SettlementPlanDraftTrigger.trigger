/**
 * @description Trigger on Settlement_Plan_Draft__c.
 *              Delegates all logic to SettlementPlanDraftTriggerHandler.
 *              One trigger per object — all events routed through handler.
 */
trigger SettlementPlanDraftTrigger on Settlement_Plan_Draft__c (before insert, before update) {
    new SettlementPlanDraftTriggerHandler(Trigger.new, Trigger.oldMap).run();
}