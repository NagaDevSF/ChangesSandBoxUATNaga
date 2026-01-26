/**
 * Batch class to reassign QRMCA leads that need attention
 * 
 * This class reassigns leads based on the following criteria:
 * 1. Group 1 (48 hours): NEW LEAD, ATTEMPTING, FOLLOW UP - not updated for 48 hours
 * 2. Group 2 (7 days): FUTURE FOLLOW UP, APPOINTMENT SET, WAITING ON DOCS, 
 *    DOCS IN - REOPEN, Reduced pays with Creditor, Transfer - not updated for 7 days
 * 
 * Exclusions:
 * - Leads with future LastActivityDate are skipped
 * - Only processes leads for Sales Office = 'QRMCA'
 * - Reassigns only to users with role 'Sales_Rep_Debtifi'
 * 
 * System Mode Considerations:
 * - Runs in system mode by default (no sharing restrictions)
 * - Uses DML options to optionally fire assignment rules
 * - All field-level security and sharing rules are bypassed
 */
global class QRMCALeadReassignmentBatch implements Database.Batchable<sObject>, Schedulable {
    
    // Cache for available users
    private List<User> eligibleUsers;
    
    // Flag to control assignment rule firing
    private Boolean fireAssignmentRules;
    
    /**
     * Constructor with optional assignment rule control
     */
    global QRMCALeadReassignmentBatch() {
        this.fireAssignmentRules = false; // Default: don't fire assignment rules
    }
    
    global QRMCALeadReassignmentBatch(Boolean fireAssignmentRules) {
        this.fireAssignmentRules = fireAssignmentRules;
    }
    
    /**
     * Start method for the batchable interface
     * Query for leads that need reassignment
     */
    global Database.QueryLocator start(Database.BatchableContext BC) {
        Datetime fortyEightHoursAgo = Datetime.now().addHours(-48);
        Datetime sevenDaysAgo = Datetime.now().addDays(-7);
        Date today = Date.today();
        Date twoDaysAgo = Date.today().addDays(-2); // For 48 hours comparison with LastActivityDate
        Date sevenDaysAgoDate = Date.today().addDays(-7); // For 7 days comparison with LastActivityDate
        
        return Database.getQueryLocator([
            SELECT Id, OwnerId, Pre_Deal_Status__c, LastModifiedDate, LastActivityDate
            FROM Lead
            WHERE Sales_Office_Ref__c = 'QRMCA'
            AND (LastActivityDate = null OR LastActivityDate <= :today)
            AND (
                // Group 1: 48 hours - NEW LEAD, ATTEMPTING, FOLLOW UP
                (Pre_Deal_Status__c IN ('NEW LEAD', 'ATTEMPTING', 'FOLLOW UP') 
                 AND LastModifiedDate < :fortyEightHoursAgo 
                 AND (LastActivityDate = null OR LastActivityDate < :twoDaysAgo))
                OR
                // Group 2: 7 days - Other active statuses
                (Pre_Deal_Status__c IN ('FUTURE FOLLOW UP', 'APPOINTMENT SET', 'Waiting On Docs', 
                                       'DOCS IN - REOPEN', 'Reduced pays with Creditor', 
                                       'Transfer') 
                 AND LastModifiedDate < :sevenDaysAgo 
                 AND (LastActivityDate = null OR LastActivityDate < :sevenDaysAgoDate))
            )
        ]);
    }
    
    /**
     * Execute method for the batchable interface
     * Process each batch of leads with system mode considerations
     */
    global void execute(Database.BatchableContext BC, List<Lead> scope) {
        // Initialize collection of eligible users if not already done
        if (eligibleUsers == null) {
            eligibleUsers = getEligibleUsers();
        }
        
        // Skip processing if no eligible users are available
        if (eligibleUsers.isEmpty()) {
            System.debug('No eligible users found for QRMCA lead reassignment');
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
                
                // Reset status based on current status group
                if (isGroup1Status(lead.Pre_Deal_Status__c)) {
                    lead.Pre_Deal_Status__c = 'NEW LEAD';
                } else {
                    // For Group 2 statuses, reset to FOLLOW UP for reassignment
                    lead.Pre_Deal_Status__c = 'FOLLOW UP';
                }
                
                leadsToUpdate.add(lead);
            }
        }
        
        // Update leads with optional assignment rule handling
        if (!leadsToUpdate.isEmpty()) {
            if (fireAssignmentRules) {
                // Fire assignment rules if enabled
                Database.DMLOptions dmlOpts = new Database.DMLOptions();
                dmlOpts.assignmentRuleHeader.useDefaultRule = true;
                
                List<Database.SaveResult> results = Database.update(leadsToUpdate, dmlOpts);
                
                // Handle any errors from assignment rule processing
                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        System.debug('Failed to update lead with assignment rules: ' + 
                                   leadsToUpdate[i].Id + ', Error: ' + 
                                   results[i].getErrors()[0].getMessage());
                    }
                }
            } else {
                // Standard update without assignment rules (faster, bypasses rules)
                try {
                    update leadsToUpdate;
                    System.debug('Successfully updated ' + leadsToUpdate.size() + ' leads in system mode');
                } catch (DmlException e) {
                    System.debug('DML Exception in lead update: ' + e.getMessage());
                    // Log individual errors if needed
                    for (Integer i = 0; i < e.getNumDml(); i++) {
                        System.debug('Failed to update lead: ' + e.getDmlId(i) + 
                                   ', Error: ' + e.getDmlMessage(i));
                    }
                }
            }
        }
    }
    
    /**
     * Execute method for the schedulable interface
     */
    global void execute(SchedulableContext SC) {
        Database.executeBatch(new QRMCALeadReassignmentBatch(), 200);
    }
    
    /**
     * Finish method for the batchable interface
     */
    global void finish(Database.BatchableContext BC) {
        // Handle null BatchableContext in test scenarios
        if (BC != null) {
            try {
                // Get batch job details for logging
                AsyncApexJob job = [
                    SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems, CompletedDate
                    FROM AsyncApexJob 
                    WHERE Id = :BC.getJobId()
                    LIMIT 1
                ];
                
                System.debug('QRMCA Lead Reassignment Batch completed: ' + 
                            job.JobItemsProcessed + ' of ' + job.TotalJobItems + 
                            ' batches processed. Errors: ' + job.NumberOfErrors);
            } catch (Exception e) {
                System.debug('Could not retrieve job details: ' + e.getMessage());
            }
        } else {
            System.debug('QRMCA Lead Reassignment Batch finished (test context)');
        }
        
        // Could add email notifications or other post-processing here
    }
    
    /**
     * Get eligible users for lead assignment
     * Made public for testing purposes
     */
    public List<User> getEligibleUsers() {
        return [
            SELECT Id, Name, IsActive
            FROM User 
            WHERE IsActive = true 
            AND UserRole.DeveloperName = 'Sales_Rep_Debtifi'
            ORDER BY Name
        ];
    }
    
    /**
     * Helper method to determine if a status is in Group 1 (48-hour rule)
     */
    private Boolean isGroup1Status(String status) {
        Set<String> group1Statuses = new Set<String>{
            'NEW LEAD', 'ATTEMPTING', 'FOLLOW UP'
        };
        return group1Statuses.contains(status);
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
     * Static method to run the batch (standard mode - no assignment rules)
     * Returns the batch job ID
     */
    public static Id runBatch() {
        return Database.executeBatch(new QRMCALeadReassignmentBatch(), 200);
    }
    
    /**
     * Static method to run the batch with assignment rules
     * Returns the batch job ID
     */
    public static Id runBatchWithAssignmentRules() {
        return Database.executeBatch(new QRMCALeadReassignmentBatch(true), 200);
    }
    
    /**
     * Static method to schedule the batch job
     * Returns the scheduled job ID
     */
    public static String scheduleJob(String jobName, String cronExp) {
        QRMCALeadReassignmentBatch scheduledBatch = new QRMCALeadReassignmentBatch();
        return System.schedule(jobName, cronExp, scheduledBatch);
    }
    
    /**
     * Static method to schedule the batch job with assignment rules
     * Returns the scheduled job ID
     */
    public static String scheduleJobWithAssignmentRules(String jobName, String cronExp) {
        QRMCALeadReassignmentBatch scheduledBatch = new QRMCALeadReassignmentBatch(true);
        return System.schedule(jobName, cronExp, scheduledBatch);
    }
}