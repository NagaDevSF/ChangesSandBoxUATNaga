/**
 * @description Enhanced Email Inbox Controller with User-Specific Actions
 * @author Claude Code Assistant
 * @date 2024
 * 
 * This controller implements user-specific email actions (seen/pinned) using 
 * the EmailUserAction__c junction object to prevent cross-user interference.
 */
public with sharing class EmailInboxControllerV2 {
    
    // Inner class for email information
    public class EmailInfo {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String fromAddress { get; set; }
        @AuraEnabled public String fromName { get; set; }
        @AuraEnabled public String toAddress { get; set; }
        @AuraEnabled public String toName { get; set; }
        @AuraEnabled public DateTime messageDate { get; set; }
        @AuraEnabled public DateTime createdDate { get; set; }
        @AuraEnabled public String textBody { get; set; }
        @AuraEnabled public String htmlBody { get; set; }
        @AuraEnabled public Boolean hasAttachment { get; set; }
        @AuraEnabled public Boolean incoming { get; set; }
        @AuraEnabled public String emailType { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Boolean isUnread { get; set; }
        
        // User-specific properties (now from junction object)
        @AuraEnabled public Boolean isSeen { get; set; }
        @AuraEnabled public Boolean isNew { get; set; }
        @AuraEnabled public Boolean isPinned { get; set; }
        @AuraEnabled public DateTime seenDate { get; set; }
        @AuraEnabled public DateTime pinnedDate { get; set; }
    }
    
    // Response wrapper for API calls
    public class EmailResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public List<EmailInfo> emails { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }
        @AuraEnabled public String lastEmailId { get; set; }
        
        public EmailResponse() {
            this.success = false;
            this.hasMore = false;
            this.emails = new List<EmailInfo>();
        }
    }

    /**
     * @description Mark an email as seen for the current user only
     * @param emailId The ID of the EmailMessage
     * @return Map<String,Object> Result with success status and message
     */
    @AuraEnabled
    public static Map<String,Object> markEmailAsSeen(String emailId) {
        Map<String,Object> result = new Map<String,Object>();
        
        try {
            String currentUserId = UserInfo.getUserId();
            System.debug('Marking email as seen for user: ' + currentUserId + ', Email: ' + emailId);
            
            // Validate email exists and is incoming
            List<EmailMessage> emails = [SELECT Id, Incoming FROM EmailMessage WHERE Id = :emailId LIMIT 1];
            
            if (emails.isEmpty()) {
                result.put('success', false);
                result.put('message', 'Email not found');
                return result;
            }
            
            EmailMessage email = emails[0];
            
            if (!email.Incoming) {
                result.put('success', false);
                result.put('message', 'Cannot mark outgoing email as seen');
                return result;
            }
            
            // Check if user action already exists
            List<EmailUserAction__c> existingActions = [
                SELECT Id, IsSeen__c, SeenDate__c 
                FROM EmailUserAction__c 
                WHERE Email__c = :emailId AND User__c = :currentUserId 
                LIMIT 1
            ];
            
            EmailUserAction__c userAction;
            
            if (existingActions.isEmpty()) {
                // Create new user action record
                userAction = new EmailUserAction__c(
                    Email__c = emailId,
                    User__c = currentUserId,
                    IsSeen__c = true,
                    SeenDate__c = DateTime.now()
                );
                insert userAction;
                System.debug('Created new EmailUserAction record for seen email');
            } else {
                // Update existing record
                userAction = existingActions[0];
                if (!userAction.IsSeen__c) {
                    userAction.IsSeen__c = true;
                    userAction.SeenDate__c = DateTime.now();
                    update userAction;
                    System.debug('Updated existing EmailUserAction record - marked as seen');
                } else {
                    System.debug('Email already marked as seen for this user');
                }
            }
            
            result.put('success', true);
            result.put('message', 'Email marked as seen successfully');
            
        } catch (Exception e) {
            System.debug('Error marking email as seen: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            result.put('success', false);
            result.put('message', 'Error marking email as seen: ' + e.getMessage());
        }
        
        return result;
    }

    /**
     * @description Toggle pin status for an email for the current user only
     * @param emailId The ID of the EmailMessage
     * @param isPinned Whether to pin (true) or unpin (false) the email
     * @return Map<String,Object> Result with success status and message
     */
    @AuraEnabled
    public static Map<String,Object> markEmailAsPinned(String emailId, Boolean isPinned) {
        Map<String,Object> result = new Map<String,Object>();
        
        try {
            String currentUserId = UserInfo.getUserId();
            System.debug('Setting email pin status for user: ' + currentUserId + ', Email: ' + emailId + ', Pinned: ' + isPinned);
            
            // Validate email exists
            List<EmailMessage> emails = [SELECT Id FROM EmailMessage WHERE Id = :emailId LIMIT 1];
            
            if (emails.isEmpty()) {
                result.put('success', false);
                result.put('message', 'Email not found');
                return result;
            }
            
            // Check if user action already exists
            List<EmailUserAction__c> existingActions = [
                SELECT Id, IsPinned__c, PinnedDate__c 
                FROM EmailUserAction__c 
                WHERE Email__c = :emailId AND User__c = :currentUserId 
                LIMIT 1
            ];
            
            EmailUserAction__c userAction;
            
            if (existingActions.isEmpty()) {
                // Create new user action record
                userAction = new EmailUserAction__c(
                    Email__c = emailId,
                    User__c = currentUserId,
                    IsPinned__c = isPinned,
                    PinnedDate__c = isPinned ? DateTime.now() : null
                );
                insert userAction;
                System.debug('Created new EmailUserAction record for pin status');
            } else {
                // Update existing record
                userAction = existingActions[0];
                userAction.IsPinned__c = isPinned;
                userAction.PinnedDate__c = isPinned ? DateTime.now() : null;
                update userAction;
                System.debug('Updated existing EmailUserAction record - pin status: ' + isPinned);
            }
            
            result.put('success', true);
            result.put('message', isPinned ? 'Email pinned successfully' : 'Email unpinned successfully');
            
        } catch (Exception e) {
            System.debug('Error updating pin status: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            result.put('success', false);
            result.put('message', 'Error updating pin status: ' + e.getMessage());
        }
        
        return result;
    }

    /**
     * @description Get inbound emails with user-specific seen and pin status
     * @param limitCount Number of emails to retrieve
     * @param lastEmailId Last email ID for pagination
     * @param fromDate Start date filter
     * @param toDate End date filter
     * @return EmailResponse containing emails with user-specific status
     */
    @AuraEnabled
    public static EmailResponse getInboundEmails(Integer limitCount, String lastEmailId, String fromDate, String toDate) {
        EmailResponse response = new EmailResponse();
        
        try {
            String currentUserId = UserInfo.getUserId();
            System.debug('Getting emails for user: ' + currentUserId);
            
            if (limitCount == null || limitCount <= 0) {
                limitCount = 50;
            }
            if (limitCount > 1000) {
                limitCount = 1000; // Prevent excessive queries
            }

            // Build dynamic SOQL query with legacy fields for migration
            String query = 'SELECT Id, Subject, FromAddress, FromName, ToAddress, ToName, ' +
                          'MessageDate, CreatedDate, TextBody, HtmlBody, HasAttachment, Incoming, ' +
                          'Status, RelatedToId, RelatedTo.Name, RelatedTo.Type, ParentId';
            
            // Always include legacy fields for backward compatibility
            query += ', Seen__c, Pin__c';
            
            query += ' FROM EmailMessage ';
            
            List<String> whereConditions = new List<String>();
            Map<String, Object> bindVars = new Map<String, Object>();
            
            // Base conditions
            whereConditions.add('(Incoming = true OR (Incoming = false AND CreatedById = :currentUserId))');
            bindVars.put('currentUserId', currentUserId);
            
            // Pagination
            if (String.isNotBlank(lastEmailId)) {
                whereConditions.add('CreatedDate < (SELECT CreatedDate FROM EmailMessage WHERE Id = :lastEmailId)');
                bindVars.put('lastEmailId', lastEmailId);
            }
            
            // Date filters
            if (String.isNotBlank(fromDate)) {
                whereConditions.add('MessageDate >= :fromDateTime');
                bindVars.put('fromDateTime', DateTime.valueOf(fromDate + ' 00:00:00'));
            }
            
            if (String.isNotBlank(toDate)) {
                whereConditions.add('MessageDate <= :toDateTime');
                bindVars.put('toDateTime', DateTime.valueOf(toDate + ' 23:59:59'));
            }
            
            // Combine conditions
            if (!whereConditions.isEmpty()) {
                query += 'WHERE ' + String.join(whereConditions, ' AND ');
            }
            
            query += ' ORDER BY CreatedDate DESC LIMIT :limitCount';
            bindVars.put('limitCount', limitCount + 1); // Get one extra to check if there are more
            
            System.debug('Executing query: ' + query);
            System.debug('With bind vars: ' + bindVars);
            
            List<EmailMessage> emails = Database.queryWithBinds(query, bindVars, System.AccessLevel.USER_MODE);
            
            // Check if there are more emails
            Boolean hasMore = emails.size() > limitCount;
            if (hasMore) {
                emails.remove(emails.size() - 1); // Remove the extra record
            }
            
            // Get user actions for these emails in batch
            Set<String> emailIds = new Set<String>();
            for (EmailMessage email : emails) {
                emailIds.add(email.Id);
            }
            
            Map<String, EmailUserAction__c> userActionsMap = new Map<String, EmailUserAction__c>();
            for (EmailUserAction__c action : [
                SELECT Email__c, IsSeen__c, IsPinned__c, SeenDate__c, PinnedDate__c
                FROM EmailUserAction__c 
                WHERE Email__c IN :emailIds AND User__c = :currentUserId
            ]) {
                userActionsMap.put(action.Email__c, action);
            }
            
            // Process emails with user-specific data
            List<EmailInfo> emailInfos = new List<EmailInfo>();
            String lastProcessedEmailId = null;
            
            for (EmailMessage email : emails) {
                EmailInfo emailInfo = convertToEmailInfo(email, userActionsMap.get(email.Id));
                emailInfos.add(emailInfo);
                lastProcessedEmailId = email.Id;
            }
            
            response.success = true;
            response.emails = emailInfos;
            response.hasMore = hasMore;
            response.lastEmailId = lastProcessedEmailId;
            response.message = 'Emails retrieved successfully';
            
            System.debug('Retrieved ' + emailInfos.size() + ' emails with user-specific actions');
            
        } catch (Exception e) {
            System.debug('Error retrieving emails: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            response.success = false;
            response.message = 'Error retrieving emails: ' + e.getMessage();
        }
        
        return response;
    }
    
    /**
     * @description Convert EmailMessage to EmailInfo with user-specific actions
     * @param email The EmailMessage record
     * @param userAction The user's specific action record (can be null)
     * @return EmailInfo with user-specific data
     */
    private static EmailInfo convertToEmailInfo(EmailMessage email, EmailUserAction__c userAction) {
        EmailInfo emailInfo = new EmailInfo();
        
        // Basic email properties
        emailInfo.id = email.Id;
        emailInfo.subject = email.Subject;
        emailInfo.fromAddress = email.FromAddress;
        emailInfo.fromName = email.FromName;
        emailInfo.toAddress = email.ToAddress;
        emailInfo.toName = email.ToAddress;
        emailInfo.messageDate = email.MessageDate;
        emailInfo.createdDate = email.CreatedDate;
        emailInfo.textBody = email.TextBody;
        emailInfo.htmlBody = email.HtmlBody;
        emailInfo.hasAttachment = email.HasAttachment;
        emailInfo.incoming = email.Incoming;
        emailInfo.status = email.Status;
        
        // Determine email type
        emailInfo.emailType = email.Incoming ? 'Received' : 'Sent';
        
        // User-specific properties with migration from legacy fields
        if (userAction != null) {
            emailInfo.isSeen = userAction.IsSeen__c;
            emailInfo.isPinned = userAction.IsPinned__c;
            emailInfo.seenDate = userAction.SeenDate__c;
            emailInfo.pinnedDate = userAction.PinnedDate__c;
        } else {
            // Migration logic: Check legacy fields first, then default to false
            Boolean legacySeen = false;
            Boolean legacyPinned = false;
            
            try {
                // Try to access legacy fields from the already queried email object
                if (email.get('Seen__c') != null) {
                    legacySeen = (Boolean) email.get('Seen__c');
                }
                if (email.get('Pin__c') != null) {
                    legacyPinned = (Boolean) email.get('Pin__c');
                }
            } catch (Exception e) {
                // Legacy fields don't exist or accessible, use defaults
                System.debug('Legacy field access failed: ' + e.getMessage());
            }
            
            emailInfo.isSeen = legacySeen;
            emailInfo.isPinned = legacyPinned;
            emailInfo.seenDate = legacySeen ? email.CreatedDate : null;
            emailInfo.pinnedDate = legacyPinned ? email.CreatedDate : null;
            
            // Auto-migration: Create user-specific record if legacy data exists
            if (legacySeen || legacyPinned) {
                migrateUserAction(email.Id, UserInfo.getUserId(), legacySeen, legacyPinned);
            }
        }
        
        // Determine if email is "new" (incoming and not seen by this user)
        emailInfo.isNew = (email.Incoming && !emailInfo.isSeen);
        
        // For outgoing emails, always consider them as "seen"
        if (!email.Incoming) {
            emailInfo.isSeen = true;
            emailInfo.isNew = false;
        }
        
        // Legacy unread property (for backward compatibility)
        emailInfo.isUnread = !emailInfo.isSeen;
        
        System.debug('Email ' + email.Id + ' - User-specific status: isSeen=' + emailInfo.isSeen + 
                    ', isPinned=' + emailInfo.isPinned + ', isNew=' + emailInfo.isNew);
        
        return emailInfo;
    }

    /**
     * @description Find Contact or Lead by email address for calendar integration
     * @param emailAddress The email address to search for
     * @return Map containing the found record details
     */
    @AuraEnabled
    public static Map<String,Object> findContactOrLeadByEmail(String emailAddress) {
        Map<String,Object> result = new Map<String,Object>();
        
        try {
            System.debug('Looking up Contact/Lead for email: ' + emailAddress);
            
            if (String.isBlank(emailAddress)) {
                result.put('success', false);
                result.put('message', 'Email address is required');
                return result;
            }
            
            // Search for Contact first
            List<Contact> contacts = [
                SELECT Id, Name, Email, AccountId, Account.Name 
                FROM Contact 
                WHERE Email = :emailAddress 
                LIMIT 1
            ];
            
            if (!contacts.isEmpty()) {
                Contact contact = contacts[0];
                result.put('success', true);
                result.put('recordId', contact.Id);
                result.put('recordName', contact.Name);
                result.put('recordType', 'Contact');
                result.put('accountId', contact.AccountId);
                result.put('accountName', contact.Account?.Name);
                result.put('message', 'Contact found: ' + contact.Name);
                
                System.debug('Found Contact: ' + contact.Name + ' (ID: ' + contact.Id + ')');
                return result;
            }
            
            // If no Contact found, search for Lead
            List<Lead> leads = [
                SELECT Id, Name, Email, Company 
                FROM Lead 
                WHERE Email = :emailAddress 
                LIMIT 1
            ];
            
            if (!leads.isEmpty()) {
                Lead lead = leads[0];
                result.put('success', true);
                result.put('recordId', lead.Id);
                result.put('recordName', lead.Name);
                result.put('recordType', 'Lead');
                result.put('company', lead.Company);
                result.put('message', 'Lead found: ' + lead.Name);
                
                System.debug('Found Lead: ' + lead.Name + ' (ID: ' + lead.Id + ')');
                return result;
            }
            
            // No Contact or Lead found
            result.put('success', false);
            result.put('message', 'No Contact or Lead found with email: ' + emailAddress);
            System.debug('No Contact or Lead found for email: ' + emailAddress);
            
        } catch (Exception e) {
            System.debug('Error in Contact/Lead lookup: ' + e.getMessage());
            result.put('success', false);
            result.put('message', 'Error looking up contact: ' + e.getMessage());
        }
        
        return result;
    }

    /**
     * @description Get user-specific email statistics
     * @return Map containing email counts for the current user
     */
    @AuraEnabled
    public static Map<String,Object> getUserEmailStats() {
        Map<String,Object> stats = new Map<String,Object>();
        
        try {
            String currentUserId = UserInfo.getUserId();
            
            // Get total emails for this user
            Integer totalEmails = [
                SELECT COUNT() 
                FROM EmailMessage 
                WHERE Incoming = true OR (Incoming = false AND CreatedById = :currentUserId)
            ];
            
            // Get user-specific seen/unseen counts
            Map<String, Integer> userActionCounts = new Map<String, Integer>();
            
            for (AggregateResult result : [
                SELECT COUNT(Id) cnt, IsSeen__c seen, IsPinned__c pinned
                FROM EmailUserAction__c 
                WHERE User__c = :currentUserId
                GROUP BY IsSeen__c, IsPinned__c
            ]) {
                Boolean isSeen = (Boolean) result.get('seen');
                Boolean isPinned = (Boolean) result.get('pinned');
                Integer count = (Integer) result.get('cnt');
                
                if (isSeen) {
                    Integer currentCount = userActionCounts.containsKey('seen') ? userActionCounts.get('seen') : 0;
                    userActionCounts.put('seen', currentCount + count);
                }
                if (isPinned) {
                    Integer currentCount = userActionCounts.containsKey('pinned') ? userActionCounts.get('pinned') : 0;
                    userActionCounts.put('pinned', currentCount + count);
                }
            }
            
            // Calculate unseen emails (total incoming - seen by user)
            Integer incomingEmails = [SELECT COUNT() FROM EmailMessage WHERE Incoming = true];
            Integer seenByUser = userActionCounts.containsKey('seen') ? userActionCounts.get('seen') : 0;
            Integer unseenEmails = incomingEmails - seenByUser;
            
            stats.put('totalEmails', totalEmails);
            stats.put('seenEmails', seenByUser);
            stats.put('unseenEmails', Math.max(0, unseenEmails)); // Ensure non-negative
            stats.put('pinnedEmails', userActionCounts.containsKey('pinned') ? userActionCounts.get('pinned') : 0);
            stats.put('success', true);
            
            System.debug('User email stats: ' + stats);
            
        } catch (Exception e) {
            System.debug('Error getting user email stats: ' + e.getMessage());
            stats.put('success', false);
            stats.put('message', 'Error retrieving email statistics');
        }
        
        return stats;
    }
    
    /**
     * @description Automatically migrate legacy email actions to user-specific records
     * @param emailId The email ID to migrate
     * @param userId The user ID
     * @param isSeen Whether the email was marked as seen
     * @param isPinned Whether the email was marked as pinned
     */
    private static void migrateUserAction(String emailId, String userId, Boolean isSeen, Boolean isPinned) {
        try {
            // Check if user action already exists
            List<EmailUserAction__c> existing = [
                SELECT Id FROM EmailUserAction__c 
                WHERE Email__c = :emailId AND User__c = :userId 
                LIMIT 1
            ];
            
            if (existing.isEmpty()) {
                // Create new user-specific record
                EmailUserAction__c userAction = new EmailUserAction__c(
                    Email__c = emailId,
                    User__c = userId,
                    IsSeen__c = isSeen,
                    IsPinned__c = isPinned,
                    SeenDate__c = isSeen ? DateTime.now() : null,
                    PinnedDate__c = isPinned ? DateTime.now() : null
                );
                
                insert userAction;
                System.debug('Migrated legacy action for email: ' + emailId + ', user: ' + userId);
            }
        } catch (Exception e) {
            System.debug('Failed to migrate user action: ' + e.getMessage());
            // Don't throw exception - migration is optional
        }
    }
}