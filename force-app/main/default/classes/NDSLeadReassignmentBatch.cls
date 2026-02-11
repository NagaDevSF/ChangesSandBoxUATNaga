/**
 * Batch class to reassign leads owned by Sales_Rep_Debtifi users that need attention
 *
 * This class reassigns leads based on the following criteria:
 * 1. Group 1 (48 hours): NEW LEAD, ATTEMPTING, FOLLOW UP - not updated for 48 hours
 * 2. Group 2 (7 days): FUTURE FOLLOW UP, APPOINTMENT SET, WAITING ON DOCS,
 *    DOCS IN - REOPEN, Reduced pays with Creditor, Transfer - not updated for 7 days
 *
 * Exclusions:
 * - Leads with future LastActivityDate are skipped
 * - Only processes leads owned by users with role 'Sales_Rep_Debtifi'
 * - Reassigns only to users with role 'Sales_Rep_Debtifi'
 */
global class NDSLeadReassignmentBatch implements Database.Batchable<sObject>, Schedulable {

    // Cache for available users
    private List<User> eligibleUsers;

    // Cache for eligible owner IDs
    private Set<Id> eligibleOwnerIds;

    // Flag to control assignment rule firing
    private Boolean fireAssignmentRules;

    // Test-only flag to bypass date filtering for test coverage
    @TestVisible
    private static Boolean bypassDateFilter = false;

    /**
     * Constructor with optional assignment rule control
     */
    global NDSLeadReassignmentBatch() {
        this.fireAssignmentRules = false; // Default: don't fire assignment rules
    }

    global NDSLeadReassignmentBatch(Boolean fireAssignmentRules) {
        this.fireAssignmentRules = fireAssignmentRules;
    }

    /**
     * Start method for the batchable interface
     * Query for leads that need reassignment
     */
    global Database.QueryLocator start(Database.BatchableContext BC) {
        Datetime fortyEightHoursAgo = bypassDateFilter ? Datetime.now().addYears(10) : Datetime.now().addHours(-48);
        Datetime sevenDaysAgo = bypassDateFilter ? Datetime.now().addYears(10) : Datetime.now().addDays(-7);
        Date today = Date.today();
        Date twoDaysAgo = bypassDateFilter ? Date.today().addYears(10) : Date.today().addDays(-2);
        Date sevenDaysAgoDate = bypassDateFilter ? Date.today().addYears(10) : Date.today().addDays(-7);

        // Get all users with Sales_Rep_Debtifi role
        List<User> salesRepUsers = [
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND UserRole.DeveloperName = 'Sales_Rep_Debtifi'
        ];

        // Create set of eligible owner IDs
        eligibleOwnerIds = new Set<Id>();
        for (User u : salesRepUsers) {
            eligibleOwnerIds.add(u.Id);
        }

        return Database.getQueryLocator([
            SELECT Id, OwnerId, Pre_Deal_Status__c, LastModifiedDate, LastActivityDate
            FROM Lead
            WHERE OwnerId IN :eligibleOwnerIds  // Only leads owned by Sales_Rep_Debtifi users
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
            System.debug('No eligible users found for lead reassignment');
            return;
        }

        // Process the leads
        List<Lead> leadsToUpdate = new List<Lead>();

        for (Lead lead : scope) {
            // Get the next available user excluding current owner
            User nextUser = getNextUserExcludingCurrentOwner(lead.OwnerId);

            // Only update if we have a valid user and it's different from current owner
            if (nextUser != null && nextUser.Id != lead.OwnerId) {
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
        Database.executeBatch(new NDSLeadReassignmentBatch(), 200);
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

                System.debug('NDS Lead Reassignment Batch completed: ' +
                            job.JobItemsProcessed + ' of ' + job.TotalJobItems +
                            ' batches processed. Errors: ' + job.NumberOfErrors);
            } catch (Exception e) {
                System.debug('Could not retrieve job details: ' + e.getMessage());
            }
        } else {
            System.debug('NDS Lead Reassignment Batch finished (test context)');
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
     * If there's only one user, return null (no reassignment possible)
     */
    private User getNextUserExcludingCurrentOwner(Id currentOwnerId) {
        // Handle edge case when no eligible users
        if (eligibleUsers == null || eligibleUsers.isEmpty()) {
            return null;
        }

        // If there's only one user and they're the current owner, can't reassign
        if (eligibleUsers.size() == 1 && eligibleUsers[0].Id == currentOwnerId) {
            return null;
        }

        // Find the index of the current owner
        Integer currentIndex = -1;
        for (Integer i = 0; i < eligibleUsers.size(); i++) {
            if (eligibleUsers[i].Id == currentOwnerId) {
                currentIndex = i;
                break;
            }
        }

        // Calculate the next index
        Integer nextIndex;
        if (currentIndex == -1) {
            // Current owner not in eligible users list, start with first user
            nextIndex = 0;
        } else {
            // Move to next user in round-robin using Math.mod()
            nextIndex = currentIndex + 1;
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
        return Database.executeBatch(new NDSLeadReassignmentBatch(), 200);
    }

    /**
     * Static method to run the batch with assignment rules
     * Returns the batch job ID
     */
    public static Id runBatchWithAssignmentRules() {
        return Database.executeBatch(new NDSLeadReassignmentBatch(true), 200);
    }

    /**
     * Static method to schedule the batch job
     * Returns the scheduled job ID
     */
    public static String scheduleJob(String jobName, String cronExp) {
        NDSLeadReassignmentBatch scheduledBatch = new NDSLeadReassignmentBatch();
        return System.schedule(jobName, cronExp, scheduledBatch);
    }

    /**
     * Static method to schedule the batch job with assignment rules
     * Returns the scheduled job ID
     */
    public static String scheduleJobWithAssignmentRules(String jobName, String cronExp) {
        NDSLeadReassignmentBatch scheduledBatch = new NDSLeadReassignmentBatch(true);
        return System.schedule(jobName, cronExp, scheduledBatch);
    }
}