public class PaymentScheduleItemTriggerHandler {

	public static final String APPROVAL_BLOCK_MSG = 'You cannot create, modify or delete this record because the related Opportunity is locked for approval.';

    // Statuses that should have null Draft_Number__c
    private static final Set<String> SKIP_DRAFT_STATUSES = new Set<String>{ 'NSF', 'Cancelled' };

    // test coverage provided in CreditorOpportunityTriggerHandlerTest
	public static void blockDMLWhileRelatedOppIsLocked(List<Payment_Schedule_Item__c> psiList) {

		for (Payment_Schedule_Item__c psi : psiList) {
			if (String.isNotBlank(psi.Related_Opportunity__c) && Approval.isLocked(psi.Related_Opportunity__c)) {
				psi.addError(APPROVAL_BLOCK_MSG);
			}
		}
	}

    /**
     * Recalculate Draft_Number__c for all items in affected Payment Plans when Status changes.
     * NSF and Cancelled items get null Draft_Number__c, others are numbered sequentially by date.
     */
    public static void recalculateDraftNumbersOnStatusChange(List<Payment_Schedule_Item__c> newList, Map<Id, Payment_Schedule_Item__c> oldMap) {
        // Collect Payment Plan IDs where Status changed
        Set<Id> affectedPlanIds = new Set<Id>();

        for (Payment_Schedule_Item__c item : newList) {
            Payment_Schedule_Item__c oldItem = oldMap.get(item.Id);
            if (oldItem != null && item.Status__c != oldItem.Status__c && item.Payment_Plan__c != null) {
                affectedPlanIds.add(item.Payment_Plan__c);
            }
        }

        if (affectedPlanIds.isEmpty()) {
            return;
        }

        // Query all items for affected plans, ordered by Payment_Date__c
        List<Payment_Schedule_Item__c> allItems = [
            SELECT Id, Payment_Plan__c, Payment_Date__c, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c IN :affectedPlanIds
            ORDER BY Payment_Plan__c, Payment_Date__c ASC, Payment_Number__c ASC
        ];

        // Group by Payment Plan
        Map<Id, List<Payment_Schedule_Item__c>> itemsByPlan = new Map<Id, List<Payment_Schedule_Item__c>>();
        for (Payment_Schedule_Item__c item : allItems) {
            if (!itemsByPlan.containsKey(item.Payment_Plan__c)) {
                itemsByPlan.put(item.Payment_Plan__c, new List<Payment_Schedule_Item__c>());
            }
            itemsByPlan.get(item.Payment_Plan__c).add(item);
        }

        // Recalculate draft numbers for each plan
        List<Payment_Schedule_Item__c> itemsToUpdate = new List<Payment_Schedule_Item__c>();

        for (Id planId : itemsByPlan.keySet()) {
            List<Payment_Schedule_Item__c> planItems = itemsByPlan.get(planId);
            Integer draftCounter = 0;

            for (Payment_Schedule_Item__c item : planItems) {
                String newDraftNumber;

                if (SKIP_DRAFT_STATUSES.contains(item.Status__c)) {
                    newDraftNumber = null;
                } else {
                    draftCounter++;
                    newDraftNumber = String.valueOf(draftCounter);
                }

                // Only update if changed
                if (item.Draft_Number__c != newDraftNumber) {
                    itemsToUpdate.add(new Payment_Schedule_Item__c(
                        Id = item.Id,
                        Draft_Number__c = newDraftNumber
                    ));
                }
            }
        }

        // Update records (use Database.update to avoid recursion issues)
        if (!itemsToUpdate.isEmpty()) {
            // Disable trigger recursion for this update
            TriggerRecursionControl.isRecalculatingDraftNumbers = true;
            try {
                Database.update(itemsToUpdate, false);
            } finally {
                TriggerRecursionControl.isRecalculatingDraftNumbers = false;
            }
        }
    }
}