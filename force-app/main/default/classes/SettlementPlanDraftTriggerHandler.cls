/**
 * @description Handler for Settlement_Plan_Draft__c trigger.
 *              Enforces: only one Active plan per CreditorOpportunity.
 *
 *              When a draft's Status__c is set to 'Active' (insert or update),
 *              queries for existing Active siblings on the same CreditorOpportunity.
 *              If one exists, blocks the save with addError().
 *
 *              The existing activateDraft() service method archives old Active plans
 *              before activating the new one, so normal activation flow is not blocked.
 *              This trigger catches edge cases like direct DML or API updates.
 */
public with sharing class SettlementPlanDraftTriggerHandler {

    private List<Settlement_Plan_Draft__c> newList;
    private Map<Id, Settlement_Plan_Draft__c> oldMap;

    public SettlementPlanDraftTriggerHandler(
        List<Settlement_Plan_Draft__c> newList,
        Map<Id, Settlement_Plan_Draft__c> oldMap
    ) {
        this.newList = newList;
        this.oldMap = oldMap;
    }

    public void run() {
        if (Trigger.isBefore) {
            if (Trigger.isInsert || Trigger.isUpdate) {
                validateOneActivePerCreditorOpportunity();
            }
        }
    }

    /**
     * @description Prevents multiple Active drafts per CreditorOpportunity.
     *
     *  Step 1: Collect CreditorOpportunity IDs for drafts becoming Active.
     *  Step 2: Single bulkified SOQL query for existing Active siblings.
     *  Step 3: addError() on any draft that would create a duplicate.
     */
    private void validateOneActivePerCreditorOpportunity() {
        try {
            // Step 1: Collect parent IDs for records being set to Active.
            //         Also detect same-batch duplicates (two records in the same DML
            //         both becoming Active for the same CreditorOpportunity).
            Map<Id, Settlement_Plan_Draft__c> credOppToFirstDraft = new Map<Id, Settlement_Plan_Draft__c>();

            for (Settlement_Plan_Draft__c draft : this.newList) {
                if (draft.Status__c != SettlementDraftService.STATUS_ACTIVE) {
                    continue;
                }
                if (draft.CreditorOpportunity__c == null) {
                    continue;
                }

                // On insert: oldMap is null, so any insert with Active status counts
                // On update: only count if Status__c is changing TO Active
                Boolean isBecomingActive = (this.oldMap == null)
                    || (this.oldMap.get(draft.Id).Status__c != SettlementDraftService.STATUS_ACTIVE);

                if (isBecomingActive) {
                    // Same-batch duplicate check: if we already saw another draft
                    // becoming Active for this CreditorOpportunity, block this one
                    if (credOppToFirstDraft.containsKey(draft.CreditorOpportunity__c)) {
                        draft.addError(
                            'Only one Settlement Plan can be Active per Creditor Opportunity. ' +
                            'Archive or deactivate the existing Active plan first.'
                        );
                    } else {
                        credOppToFirstDraft.put(draft.CreditorOpportunity__c, draft);
                    }
                }
            }

            if (credOppToFirstDraft.isEmpty()) {
                return;
            }

            // Step 2: Query existing Active siblings in DB (one SOQL, bulkified)
            Set<Id> credOppIdsWithExistingActive = new Set<Id>();

            for (Settlement_Plan_Draft__c existing : [
                SELECT Id, CreditorOpportunity__c
                FROM Settlement_Plan_Draft__c
                WHERE CreditorOpportunity__c IN :credOppToFirstDraft.keySet()
                  AND Status__c = :SettlementDraftService.STATUS_ACTIVE
            ]) {
                // On update: exclude the record itself (already Active, just being re-saved)
                if (this.oldMap != null
                    && credOppToFirstDraft.containsKey(existing.CreditorOpportunity__c)
                    && credOppToFirstDraft.get(existing.CreditorOpportunity__c).Id == existing.Id) {
                    continue;
                }
                credOppIdsWithExistingActive.add(existing.CreditorOpportunity__c);
            }

            // Step 3: Block records that conflict with existing DB Active siblings
            for (Id credOppId : credOppIdsWithExistingActive) {
                if (credOppToFirstDraft.containsKey(credOppId)) {
                    credOppToFirstDraft.get(credOppId).addError(
                        'Only one Settlement Plan can be Active per Creditor Opportunity. ' +
                        'Archive or deactivate the existing Active plan first.'
                    );
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'SettlementPlanDraftTriggerHandler.validateOneActivePerCreditorOpportunity() failed: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
        }
    }
}