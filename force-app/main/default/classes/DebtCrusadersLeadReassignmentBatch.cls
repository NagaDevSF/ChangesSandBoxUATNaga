/**
 * Batch class to reassign Debt Crusaders leads that need attention
 * 
 * This class reassigns leads based on the following criteria:
 * 1. Leads not updated for 72 hours (any status)
 * 2. Attempting - no response: older than 24 hours
 * 3. Follow Up - no response: older than 24 hours
 * 4. Follow Up - future: older than 60 days
 */
global class DebtCrusadersLeadReassignmentBatch implements Database.Batchable<sObject>, Schedulable {
    
    // Cache for available users
    private List<User> eligibleUsers;
    
    /**
     * Start method for the batchable interface
     * Query for leads that need reassignment
     */
    global Database.QueryLocator start(Database.BatchableContext BC) {
        Datetime seventyTwoHoursAgo = Datetime.now().addHours(-72);
        Datetime twentyFourHoursAgo = Datetime.now().addHours(-24);
        Datetime sixtyDaysAgo = Datetime.now().addDays(-60);
        
        return Database.getQueryLocator([
            SELECT Id, OwnerId, Pre_Deal_Statuses_DC__c, LastModifiedDate
            FROM Lead
            WHERE Sales_Office_Ref__c = 'Debt Crusaders'
            AND (
                (LastModifiedDate < :seventyTwoHoursAgo)
                OR
                (Pre_Deal_Statuses_DC__c = 'Attempting - no response' AND LastModifiedDate < :twentyFourHoursAgo)
                OR
                (Pre_Deal_Statuses_DC__c = 'Follow Up - no response' AND LastModifiedDate < :twentyFourHoursAgo)
                OR
                (Pre_Deal_Statuses_DC__c = 'Follow Up - future' AND LastModifiedDate < :sixtyDaysAgo)
            )
        ]);
    }
    
    /**
     * Execute method for the batchable interface
     * Process each batch of leads
     */
    global void execute(Database.BatchableContext BC, List<Lead> scope) {
        // Initialize collection of eligible users if not already done
        if (eligibleUsers == null) {
            eligibleUsers = getEligibleUsers();
        }
        
        // Skip processing if no eligible users are available
        if (eligibleUsers.isEmpty()) {
            System.debug('No eligible users found for lead reassignment');
            return;
        }
        
        // Process the leads
        List<Lead> leadsToUpdate = new List<Lead>();
        
        for (Lead lead : scope) {
            // Get the next available user excluding current owner
            User nextUser = getNextUserExcludingCurrentOwner(lead.OwnerId);
            
            // Only update if we have a valid user
            if (nextUser != null) {
                lead.OwnerId = nextUser.Id;
                lead.Pre_Deal_Statuses_DC__c = 'Assigned - not contacted';
                leadsToUpdate.add(lead);
            }
        }
        
        // Update all leads in a single DML operation
        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
    }
    
    /**
     * Execute method for the schedulable interface
     */
    global void execute(SchedulableContext SC) {
        Database.executeBatch(new DebtCrusadersLeadReassignmentBatch(), 200);
    }
    
    /**
     * Finish method for the batchable interface
     */
    global void finish(Database.BatchableContext BC) {
        // Could add logging or notifications here if needed
    }
    
    /**
     * Get eligible users for lead assignment
     * Made public for testing purposes
     */
    public List<User> getEligibleUsers() {
        return [
            SELECT Id, Name 
            FROM User 
            WHERE IsActive = true 
            AND UserRole.DeveloperName LIKE 'Sales_Rep_DC%'
            ORDER BY Name
        ];
    }
    
    /**
     * Get the next user in round-robin fashion, excluding the current owner
     * If there's only one user, the behavior depends on user count
     */
    private User getNextUserExcludingCurrentOwner(Id currentOwnerId) {
        // Handle edge case when no eligible users
        if (eligibleUsers == null || eligibleUsers.isEmpty()) {
            return null;
        }
        
        // If there's only one user, return that user (can't reassign to someone else)
        if (eligibleUsers.size() == 1) {
            return eligibleUsers[0]; // Return the only user regardless of current owner
        }
        
        // Find the index of the current owner
        Integer currentIndex = -1;
        for (Integer i = 0; i < eligibleUsers.size(); i++) {
            if (eligibleUsers[i].Id == currentOwnerId) {
                currentIndex = i;
                break;
            }
        }
        
        // Calculate the next index - if currentIndex is -1 (not found), start with the first user
        Integer nextIndex;
        if (currentIndex == -1) {
            nextIndex = 0;
        } else {
            nextIndex = currentIndex + 1;
            if (nextIndex >= eligibleUsers.size()) {
                nextIndex = 0;
            }
        }
        
        // If we're back to the current owner, move one more step
        if (nextIndex == currentIndex && eligibleUsers.size() > 1) {
            nextIndex = nextIndex + 1;
            if (nextIndex >= eligibleUsers.size()) {
                nextIndex = 0;
            }
        }
        
        return eligibleUsers[nextIndex];
    }
    
    /**
     * Static method to run the batch
     * Returns the batch job ID
     */
    public static Id runBatch() {
        return Database.executeBatch(new DebtCrusadersLeadReassignmentBatch(), 200);
    }
    
    /**
     * Static method to schedule the batch job
     * Returns the scheduled job ID
     */
    public static String scheduleJob(String jobName, String cronExp) {
        DebtCrusadersLeadReassignmentBatch scheduledBatch = new DebtCrusadersLeadReassignmentBatch();
        return System.schedule(jobName, cronExp, scheduledBatch);
    }
}