/**
 * @description Invocable class for round-robin lead assignment
 *              Accepts collections of Lead IDs and Owner IDs and assigns them in round-robin fashion
 * @author Salesforce Developer
 * @date 2025
 */
public without sharing class BulkRoundRobinAssignment {

    /**
     * @description Assigns leads to owners in round-robin fashion
     * @param requests List of RoundRobinRequest containing lead IDs and owner IDs collections
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

        if (req.ownerIds == null || req.ownerIds.isEmpty()) {
            System.debug('No owners available for assignment');
            return;
        }

        // First, get current lead ownership
        Map<Id, Lead> currentLeads = new Map<Id, Lead>([
            SELECT Id, OwnerId
            FROM Lead
            WHERE Id IN :req.leadIds
        ]);

        // Perform round-robin assignment - rotate to next user in list
        List<Lead> leadsToUpdate = new List<Lead>();
        Integer userCount = req.ownerIds.size();

        for (Id leadId : req.leadIds) {
            Lead currentLead = currentLeads.get(leadId);
            Id newOwnerId;

            // Find current owner's position in round-robin list
            Integer currentOwnerIndex = -1;
            for (Integer i = 0; i < userCount; i++) {
                if (req.ownerIds[i] == currentLead.OwnerId) {
                    currentOwnerIndex = i;
                    break;
                }
            }

            if (currentOwnerIndex >= 0) {
                // Lead is owned by a round-robin user - assign to NEXT user in list
                Integer nextOwnerIndex = Math.mod(currentOwnerIndex + 1, userCount);
                newOwnerId = req.ownerIds[nextOwnerIndex];
                System.debug('Rotating lead ' + leadId + ' from user index ' + currentOwnerIndex + ' to ' + nextOwnerIndex);
            } else {
                // Lead is NOT owned by round-robin user - assign to first user
                newOwnerId = req.ownerIds[0];
                System.debug('Assigning new lead ' + leadId + ' to first round-robin user');
            }

            // Only update if owner is changing
            if (currentLead.OwnerId != newOwnerId) {
                leadsToUpdate.add(new Lead(
                    Id = leadId,
                    OwnerId = newOwnerId
                ));
            }
        }

        // Bulk update all leads
        if (!leadsToUpdate.isEmpty()) {
            try {
                update leadsToUpdate;
                Integer unchanged = req.leadIds.size() - leadsToUpdate.size();
                System.debug('Successfully rotated ' + leadsToUpdate.size() + ' leads to next round-robin user');
                if (unchanged > 0) {
                    System.debug(unchanged + ' leads already assigned to correct next user');
                }
            } catch (Exception e) {
                System.debug('Error reassigning leads: ' + e.getMessage());
                throw e;
            }
        } else {
            System.debug('All ' + req.leadIds.size() + ' leads already assigned to correct users - no rotation needed');
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
         * @description Collection of Owner IDs for round-robin assignment
         */
        @InvocableVariable(required=true label='Owner IDs'
                          description='Collection of User IDs from EDD Round Robin for assignment')
        public List<Id> ownerIds;
    }
}