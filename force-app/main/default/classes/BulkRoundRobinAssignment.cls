/**
 * @description Invocable class for round-robin lead assignment
 *              Assigns leads to owners in true round-robin fashion using Last_Assignment_Time__c
 *              to track which rep should receive the next lead
 * @author Salesforce Developer
 * @date 2025
 */
public without sharing class BulkRoundRobinAssignment {

    /**
     * @description Assigns leads to owners in round-robin fashion
     * @param requests List of RoundRobinRequest containing lead IDs and round-robin record IDs
     */
    @InvocableMethod(label='Round Robin Lead Assignment'
                     description='Assigns leads to owners in round-robin fashion from EDD Round Robin users')
    public static void assignLeadsRoundRobin(List<RoundRobinRequest> requests) {

        if (requests == null || requests.isEmpty()) {
            return;
        }

        // Process the first request (Flow will only send one)
        RoundRobinRequest req = requests[0];

        if (req.leadIds == null || req.leadIds.isEmpty()) {
            System.debug('No leads to assign');
            return;
        }

        if (req.roundRobinIds == null || req.roundRobinIds.isEmpty()) {
            System.debug('No round-robin users available for assignment');
            return;
        }

        // Query EDD_Round_Robin__c records ordered by Last_Assignment_Time__c ASC (oldest first = next in line)
        // NULLS FIRST ensures users who have never been assigned get priority
        List<EDD_Round_Robin__c> roundRobinUsers = [
            SELECT Id, EDD_User__c, Last_Assignment_Time__c
            FROM EDD_Round_Robin__c
            WHERE Id IN :req.roundRobinIds
            AND EDD_User__c != NULL
            ORDER BY Last_Assignment_Time__c ASC NULLS FIRST
        ];

        if (roundRobinUsers.isEmpty()) {
            System.debug('No valid round-robin users found');
            return;
        }

        Integer userCount = roundRobinUsers.size();
        Integer currentIndex = 0;

        // Build a map of User ID to Round Robin record for quick lookup
        Map<Id, Integer> userIdToIndex = new Map<Id, Integer>();
        for (Integer i = 0; i < userCount; i++) {
            userIdToIndex.put(roundRobinUsers[i].EDD_User__c, i);
        }

        // Query current lead owners
        Map<Id, Lead> currentLeads = new Map<Id, Lead>([
            SELECT Id, OwnerId
            FROM Lead
            WHERE Id IN :req.leadIds
        ]);

        // Prepare leads to update and round-robin records to update
        List<Lead> leadsToUpdate = new List<Lead>();
        Map<Id, EDD_Round_Robin__c> roundRobinToUpdate = new Map<Id, EDD_Round_Robin__c>();
        DateTime now = DateTime.now();
        Integer assignmentCounter = 0;

        for (Id leadId : req.leadIds) {
            Lead currentLead = currentLeads.get(leadId);
            Id currentOwnerId = currentLead != null ? currentLead.OwnerId : null;

            // Get the next user in round-robin sequence
            EDD_Round_Robin__c selectedRR = roundRobinUsers[currentIndex];
            Id newOwnerId = selectedRR.EDD_User__c;

            // If the selected user is the same as current owner, skip to next user
            if (newOwnerId == currentOwnerId && userCount > 1) {
                currentIndex = Math.mod(currentIndex + 1, userCount);
                selectedRR = roundRobinUsers[currentIndex];
                newOwnerId = selectedRR.EDD_User__c;
                System.debug('Skipped current owner, reassigning lead ' + leadId + ' to ' + newOwnerId);
            }

            System.debug('Assigning lead ' + leadId + ' to owner ' + newOwnerId +
                        ' (round-robin user: ' + selectedRR.Id + ', index: ' + currentIndex + ')');

            // Only update if owner is actually changing
            if (currentOwnerId != newOwnerId) {
                leadsToUpdate.add(new Lead(
                    Id = leadId,
                    OwnerId = newOwnerId
                ));

                // Update the Last_Assignment_Time__c for this round-robin record
                // Add seconds offset to maintain order within same batch
                roundRobinToUpdate.put(selectedRR.Id, new EDD_Round_Robin__c(
                    Id = selectedRR.Id,
                    Last_Assignment_Time__c = now.addSeconds(assignmentCounter)
                ));
                assignmentCounter++;
            }

            // Move to next rep for the next lead
            currentIndex = Math.mod(currentIndex + 1, userCount);
        }

        // Bulk update all leads
        if (!leadsToUpdate.isEmpty()) {
            try {
                update leadsToUpdate;
                System.debug('Successfully assigned ' + leadsToUpdate.size() + ' leads in round-robin fashion');
            } catch (Exception e) {
                System.debug('Error assigning leads: ' + e.getMessage());
                throw e;
            }
        }

        // Update Last_Assignment_Time__c for round-robin records
        if (!roundRobinToUpdate.isEmpty()) {
            try {
                update roundRobinToUpdate.values();
                System.debug('Updated Last_Assignment_Time__c for ' + roundRobinToUpdate.size() + ' round-robin users');
            } catch (Exception e) {
                System.debug('Error updating round-robin records: ' + e.getMessage());
                // Don't throw here - leads are already assigned
            }
        }
    }

    /**
     * @description Wrapper class for round-robin assignment request
     */
    public class RoundRobinRequest {

        /**
         * @description Collection of Lead IDs to assign
         */
        @InvocableVariable(required=true label='Lead IDs'
                          description='Collection of Lead IDs to be assigned')
        public List<Id> leadIds;

        /**
         * @description Collection of EDD_Round_Robin__c record IDs
         */
        @InvocableVariable(required=true label='Round Robin Record IDs'
                          description='Collection of EDD_Round_Robin__c record IDs for assignment')
        public List<Id> roundRobinIds;
    }
}