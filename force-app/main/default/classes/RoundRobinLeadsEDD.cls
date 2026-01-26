/**
 * Round Robin Lead Assignment for Sales Rep EDD
 * Redistributes inactive leads among Sales Rep EDD users based on inactivity rules
 */
public class RoundRobinLeadsEDD implements Database.Batchable<sObject>, Schedulable {
    
    // Constants for timing rules
    private static final Integer GROUP1_HOURS = 48;
    private static final Integer GROUP1_DAYS = 2;
    private static final Integer GROUP2_DAYS = 7;
    
    // Status groupings - Using exact API names from your picklist
    private static final Set<String> GROUP1_STATUSES = new Set<String>{
        'NEW LEAD', 'ATTEMPTING', 'FOLLOW UP'
    };
    
    private static final Set<String> GROUP2_STATUSES = new Set<String>{
        'FUTURE FOLLOW UP', 'APPOINTMENT SET', 'Waiting On Docs', 
        'DOCS IN - REOPEN', 'Reduced pays with Creditor', 'Transfer'
    };
    
    // Instance variables for round-robin tracking
    @TestVisible private List<User> salesRepEDDUsers;
    @TestVisible private Integer currentUserIndex = 0;
    @TestVisible private Map<Id, Integer> userAssignmentCount;
    
    /**
     * Schedulable execute method
     */
    public void execute(SchedulableContext SC) {
        Database.executeBatch(new RoundRobinLeadsEDD(), 200);
    }
    
    /**
     * Batch start method - gather all eligible leads
     */
    public Database.QueryLocator start(Database.BatchableContext BC) {
        // Get all Sales Rep EDD users first
        salesRepEDDUsers = [
            SELECT Id, Name, IsActive 
            FROM User 
            WHERE UserRole.DeveloperName = 'Sales_Rep_EDD' 
                AND IsActive = true
            ORDER BY Name
        ];
        
        // If no users with role found in test, get current user
        if(salesRepEDDUsers.isEmpty() && Test.isRunningTest()) {
            salesRepEDDUsers = [
                SELECT Id, Name, IsActive 
                FROM User 
                WHERE Id = :UserInfo.getUserId()
            ];
        }
        
        // Initialize assignment counter
        userAssignmentCount = new Map<Id, Integer>();
        for(User u : salesRepEDDUsers) {
            userAssignmentCount.put(u.Id, 0);
        }
        
        // Build query WITHOUT bind variables (use string concatenation instead)
        DateTime group1ModifiedCutoff = DateTime.now().addHours(-GROUP1_HOURS);
        Date group1ActivityCutoff = Date.today().addDays(-GROUP1_DAYS);
        DateTime group2ModifiedCutoff = DateTime.now().addDays(-GROUP2_DAYS);
        Date group2ActivityCutoff = Date.today().addDays(-GROUP2_DAYS);
        
        // Get user IDs for query
        Set<Id> salesRepEDDUserIds = new Set<Id>();
        for(User u : salesRepEDDUsers) {
            salesRepEDDUserIds.add(u.Id);
        }
        
        // Build query with literal values
        String query = 'SELECT Id, OwnerId, Pre_Deal_Status__c, LastModifiedDate, ' +
                      'LastActivityDate, Lead_Source_EDD__c, Name ' +
                      'FROM Lead ' +
                      'WHERE IsConverted = false ' +
                      'AND Lead_Source_EDD__c != \'Legal\' ';
        
        // Add owner filter if we have users
        if(!salesRepEDDUserIds.isEmpty()) {
            String userIdString = '';
            for(Id userId : salesRepEDDUserIds) {
                if(userIdString != '') userIdString += ',';
                userIdString += '\'' + userId + '\'';
            }
            query += 'AND OwnerId IN (' + userIdString + ') ';
        }
        
        query += 'AND (LastActivityDate = null OR LastActivityDate <= TODAY) ' +
                 'AND (' +
                 // Group 1 conditions with literal status values
                 '(Pre_Deal_Status__c IN (\'NEW LEAD\',\'ATTEMPTING\',\'FOLLOW UP\') ' +
                 'AND LastModifiedDate < ' + group1ModifiedCutoff.format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + ' ' +
                 'AND (LastActivityDate = null OR LastActivityDate < ' + String.valueOf(group1ActivityCutoff) + ')) ' +
                 'OR ' +
                 // Group 2 conditions with literal status values
                 '(Pre_Deal_Status__c IN (\'FUTURE FOLLOW UP\',\'APPOINTMENT SET\',\'Waiting On Docs\',' +
                 '\'DOCS IN - REOPEN\',\'Reduced pays with Creditor\',\'Transfer\') ' +
                 'AND LastModifiedDate < ' + group2ModifiedCutoff.format('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + ' ' +
                 'AND (LastActivityDate = null OR LastActivityDate < ' + String.valueOf(group2ActivityCutoff) + ')) ' +
                 ')';
        
        System.debug('Query: ' + query);
        
        return Database.getQueryLocator(query);
    }
    
    /**
     * Batch execute method - process leads in chunks
     */
    public void execute(Database.BatchableContext BC, List<Lead> scope) {
        if(salesRepEDDUsers == null || salesRepEDDUsers.isEmpty()) {
            System.debug('No active Sales Rep EDD users found');
            return;
        }
        
        List<Lead> leadsToUpdate = new List<Lead>();
        DateTime group1ModifiedCutoff = DateTime.now().addHours(-GROUP1_HOURS);
        Date group1ActivityCutoff = Date.today().addDays(-GROUP1_DAYS);
        DateTime group2ModifiedCutoff = DateTime.now().addDays(-GROUP2_DAYS);
        Date group2ActivityCutoff = Date.today().addDays(-GROUP2_DAYS);
        
        for(Lead lead : scope) {
            // Double-check exclusions
            if(lead.Lead_Source_EDD__c == 'Legal' || 
               (lead.LastActivityDate != null && lead.LastActivityDate > Date.today())) {
                continue;
            }
            
            Lead leadToUpdate = new Lead(Id = lead.Id);
            Boolean shouldUpdate = false;
            
            // Check Group 1
            if(GROUP1_STATUSES.contains(lead.Pre_Deal_Status__c)) {
                if(lead.LastModifiedDate < group1ModifiedCutoff &&
                   (lead.LastActivityDate == null || lead.LastActivityDate < group1ActivityCutoff)) {
                    
                    // Reassign using round-robin
                    leadToUpdate.OwnerId = getNextUserId(lead.OwnerId);
                    leadToUpdate.Pre_Deal_Status__c = 'NEW LEAD';
                    shouldUpdate = true;
                    
                    System.debug('Group 1 Reassignment: Lead ' + lead.Name + 
                               ' from User ' + lead.OwnerId + ' to User ' + leadToUpdate.OwnerId);
                }
            }
            // Check Group 2
            else if(GROUP2_STATUSES.contains(lead.Pre_Deal_Status__c)) {
                if(lead.LastModifiedDate < group2ModifiedCutoff &&
                   (lead.LastActivityDate == null || lead.LastActivityDate < group2ActivityCutoff)) {
                    
                    // Reassign using round-robin
                    leadToUpdate.OwnerId = getNextUserId(lead.OwnerId);
                    leadToUpdate.Pre_Deal_Status__c = 'FOLLOW UP';
                    shouldUpdate = true;
                    
                    System.debug('Group 2 Reassignment: Lead ' + lead.Name + 
                               ' from User ' + lead.OwnerId + ' to User ' + leadToUpdate.OwnerId);
                }
            }
            
            if(shouldUpdate) {
                leadsToUpdate.add(leadToUpdate);
            }
        }
        
        // Update leads with error handling
        if(!leadsToUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(leadsToUpdate, false);
            
            Integer successCount = 0;
            for(Integer i = 0; i < results.size(); i++) {
                if(!results[i].isSuccess()) {
                    System.debug('Error updating lead ' + leadsToUpdate[i].Id + ': ' + 
                               results[i].getErrors()[0].getMessage());
                } else {
                    successCount++;
                }
            }
            
            System.debug('Successfully processed ' + successCount + ' of ' + leadsToUpdate.size() + ' leads');
        }
    }
    
    /**
     * Get next user ID in round-robin sequence
     */
    @TestVisible
    private Id getNextUserId(Id currentOwnerId) {
        if(salesRepEDDUsers == null || salesRepEDDUsers.isEmpty()) {
            return currentOwnerId;
        }
        
        // For single user, return same user
        if(salesRepEDDUsers.size() == 1) {
            return salesRepEDDUsers[0].Id;
        }
        
        // Find the user with the least assignments
        Id nextUserId = null;
        Integer minAssignments = 999999;
        
        for(User u : salesRepEDDUsers) {
            // Skip the current owner to ensure rotation
            if(u.Id == currentOwnerId) {
                continue;
            }
            
            Integer count = userAssignmentCount.get(u.Id);
            if(count != null && count < minAssignments) {
                minAssignments = count;
                nextUserId = u.Id;
            }
        }
        
        // If everyone has the same count or we couldn't find a different user,
        // use simple round-robin
        if(nextUserId == null) {
            currentUserIndex = Math.mod(currentUserIndex + 1, salesRepEDDUsers.size());
            nextUserId = salesRepEDDUsers[currentUserIndex].Id;
            
            // Make sure we're not assigning to the same user
            while(nextUserId == currentOwnerId && salesRepEDDUsers.size() > 1) {
                currentUserIndex = Math.mod(currentUserIndex + 1, salesRepEDDUsers.size());
                nextUserId = salesRepEDDUsers[currentUserIndex].Id;
            }
        }
        
        // Update assignment count
        if(userAssignmentCount.containsKey(nextUserId)) {
            userAssignmentCount.put(nextUserId, userAssignmentCount.get(nextUserId) + 1);
        } else {
            userAssignmentCount.put(nextUserId, 1);
        }
        
        return nextUserId;
    }
    
    /**
     * Batch finish method
     */
    public void finish(Database.BatchableContext BC) {
        // Get job details
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems
            FROM AsyncApexJob
            WHERE Id = :BC.getJobId()
        ];
        
        String emailBody = 'Round Robin Lead Assignment Batch completed.\n\n' +
                          'Job Status: ' + job.Status + '\n' +
                          'Total Batches: ' + job.TotalJobItems + '\n' +
                          'Processed Batches: ' + job.JobItemsProcessed + '\n' +
                          'Errors: ' + job.NumberOfErrors + '\n\n';
        
        if(salesRepEDDUsers != null && !salesRepEDDUsers.isEmpty()) {
            emailBody += 'Assignment Summary:\n';
            for(User u : salesRepEDDUsers) {
                Integer count = userAssignmentCount.get(u.Id);
                emailBody += u.Name + ': ' + (count != null ? count : 0) + ' leads\n';
            }
        }
        
        // Send to admins or log
        System.debug(emailBody);
    }
}