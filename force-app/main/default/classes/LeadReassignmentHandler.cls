// Handler Class
public class LeadReassignmentHandler {
    private static Boolean isRunning = false;
    
    public static void handleLeadReassignment(List<Lead> newLeads, Map<Id, Lead> oldLeadMap) {
        // Prevent recursive execution
        if (isRunning) return;
        isRunning = true;
        
        try {
            // Check if we're in a test context or if context is asynchronous
            Boolean isSyncContext = !System.isFuture() && !System.isBatch() && !System.isQueueable();
            
            // Collect leads that need reassignment
            Set<Id> leadsToReassign = new Set<Id>();
            for (Lead newLead : newLeads) {
                Lead oldLead = oldLeadMap.get(newLead.Id);
                // Only process leads where Spanish__c has changed to true
                if (newLead.Spanish__c && !oldLead.Spanish__c) {
                    leadsToReassign.add(newLead.Id);
                }
            }
            
            if (!leadsToReassign.isEmpty()) {
                if (isSyncContext && !Test.isRunningTest()) {
                    // In normal operation outside of tests, use async processing
                    reassignLeadsAsync(leadsToReassign);
                } else {
                    // In tests or if already in async context, process synchronously
                    reassignLeadsSynchronously(leadsToReassign);
                }
            }
        } finally {
            isRunning = false;
        }
    }
    
    @future
    public static void reassignLeadsAsync(Set<Id> leadIds) {
        reassignLeadsSynchronously(leadIds);
    }
    
    private static void reassignLeadsSynchronously(Set<Id> leadIds) {
        if (leadIds.isEmpty()) return;
        
        // Query for Spanish-speaking users
        List<User> spanishUsers = [SELECT Id FROM User WHERE Spanish__c = true AND IsActive = true LIMIT 1];
        if (spanishUsers.isEmpty()) return;
        
        // Get the first Spanish-speaking user
        Id spanishUserId = spanishUsers[0].Id;
        
        // Update the leads
        List<Lead> leadsToUpdate = [SELECT Id FROM Lead WHERE Id IN :leadIds];
        for (Lead lead : leadsToUpdate) {
            lead.OwnerId = spanishUserId;
        }
        
        update leadsToUpdate;
    }
}