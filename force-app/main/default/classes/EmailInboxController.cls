/**
 * @description Controller for Email Inbox Utility Bar Component
 * @author Claude Code Assistant
 * @date 2025-01-25
 */
public with sharing class EmailInboxController {
    
    /**
     * @description Wrapper class for email data
     */
    public class EmailInfo {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String fromName { get; set; }
        @AuraEnabled public String fromAddress { get; set; }
        @AuraEnabled public String toAddress { get; set; }
        @AuraEnabled public String ccAddress { get; set; }
        @AuraEnabled public String bccAddress { get; set; }
        @AuraEnabled public String textBody { get; set; }
        @AuraEnabled public String htmlBody { get; set; }
        @AuraEnabled public DateTime createdDate { get; set; }
        @AuraEnabled public DateTime messageDate { get; set; }
        @AuraEnabled public String relativeDate { get; set; }
        @AuraEnabled public Boolean hasAttachment { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Boolean isSeen { get; set; }
        @AuraEnabled public Boolean isNew { get; set; }
        @AuraEnabled public Boolean isPinned { get; set; }
        @AuraEnabled public Boolean incoming { get; set; }
        @AuraEnabled public Id relatedToId { get; set; }
        @AuraEnabled public String relatedToName { get; set; }
        @AuraEnabled public String relatedToType { get; set; }
        @AuraEnabled public String relatedToIcon { get; set; }
        @AuraEnabled public String preview { get; set; }
        @AuraEnabled public String emailType { get; set; } // 'Sent' or 'Received'
    }
    
    /**
     * @description Wrapper class for email list response
     */
    public class EmailListResponse {
        @AuraEnabled public List<EmailInfo> emails { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public Integer unreadCount { get; set; }
        @AuraEnabled public Boolean hasMore { get; set; }
        @AuraEnabled public String lastEmailId { get; set; }
        
        public EmailListResponse() {
            this.emails = new List<EmailInfo>();
            this.totalCount = 0;
            this.unreadCount = 0;
            this.hasMore = false;
            this.lastEmailId = null;
        }
    }
    
    private static final Integer DEFAULT_LIMIT = 1000;
    private static final Integer MAX_LIMIT = 1000;
    
    /**
     * @description Get all emails (sent and received) for current user with pagination support
     * @param limitCount Number of emails to retrieve (default: 1000, max: 1000)
     * @param lastEmailId ID of last email for pagination (null for first page)
     * @param fromDate Start date filter (optional - if provided, filters from this date)
     * @param toDate End date filter (optional - if provided, filters to this date)
     * @return EmailListResponse with email data and metadata
     */
    @AuraEnabled
    public static EmailListResponse getInboundEmails(Integer limitCount, String lastEmailId, Date fromDate, Date toDate) {
        try {
            // Validate and set defaults
            if (limitCount == null || limitCount <= 0) {
                limitCount = DEFAULT_LIMIT;
            }
            if (limitCount > MAX_LIMIT) {
                limitCount = MAX_LIMIT;
            }
            
            EmailListResponse response = new EmailListResponse();
            
            // Build dynamic SOQL query
            String baseQuery = buildEmailQuery(limitCount, lastEmailId, fromDate, toDate);
            List<EmailMessage> emails = Database.query(baseQuery);
            
            // Batch load user actions for performance
            String currentUserId = UserInfo.getUserId();
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
            
            // Process email data with user-specific actions
            for (EmailMessage email : emails) {
                EmailInfo emailInfo = processEmailMessage(email, userActionsMap.get(email.Id));
                response.emails.add(emailInfo);
            }
            
            // Get total and unread counts
            response.totalCount = getTotalEmailCount(fromDate, toDate);
            response.unreadCount = getUnreadEmailCount(fromDate, toDate);
            
            // Check if there are more records
            response.hasMore = emails.size() == limitCount;
            if (!response.emails.isEmpty()) {
                response.lastEmailId = response.emails[response.emails.size() - 1].id;
            }
            
            return response;
            
        } catch (Exception e) {
            System.debug('Error in getInboundEmails: ' + e.getMessage());
            throw new AuraHandledException('Failed to retrieve emails: ' + e.getMessage());
        }
    }
    
    /**
     * @description Mark email as seen by updating the seen field on EmailMessage
     * @param emailId ID of the email to mark as seen
     * @return Map with success status and message details
     */
    @AuraEnabled
    public static Map<String,Object> markEmailAsSeen(String emailId) {
        Map<String,Object> res = new Map<String,Object>{ 'success' => false, 'message' => '' };
        
        if (String.isBlank(emailId)) { 
            res.put('message','Missing Email ID'); 
            return res; 
        }

        try {
            String currentUserId = UserInfo.getUserId();
            
            // Validate email exists and is incoming
            List<EmailMessage> emails = [SELECT Id, Incoming FROM EmailMessage WHERE Id = :emailId LIMIT 1];
            
            if (emails.isEmpty()) {
                res.put('message','EmailMessage not found'); 
                return res;
            }
            
            EmailMessage email = emails[0];
            
            // Check if user action already exists
            List<EmailUserAction__c> existingActions = [
                SELECT Id, IsSeen__c 
                FROM EmailUserAction__c 
                WHERE Email__c = :emailId AND User__c = :currentUserId 
                LIMIT 1
            ];
            
            EmailUserAction__c userAction;
            if (existingActions.isEmpty()) {
                // Create new user action
                userAction = new EmailUserAction__c(
                    Email__c = emailId,
                    User__c = currentUserId,
                    IsSeen__c = true,
                    SeenDate__c = DateTime.now()
                );
                insert userAction;
            } else {
                // Update existing action
                userAction = existingActions[0];
                if (!userAction.IsSeen__c) {
                    userAction.IsSeen__c = true;
                    userAction.SeenDate__c = DateTime.now();
                    update userAction;
                }
            }
            
            res.put('success', true);
            res.put('message', 'Email marked as seen successfully');
            System.debug('Email marked as seen for user: ' + currentUserId + ', email: ' + emailId);
            
            return res;
        } catch (Exception e) {
            res.put('message', 'Database error: ' + e.getMessage());
            System.debug('Error marking email as seen: ' + e.getMessage());
            return res;
        }
    }
    
    /**
     * @description Mark an email as pinned or unpinned
     * @param emailId ID of the email to pin/unpin
     * @param isPinned Whether to pin (true) or unpin (false) the email
     * @return Map containing success status and message
     */
    @AuraEnabled
    public static Map<String,Object> markEmailAsPinned(String emailId, Boolean isPinned) {
        Map<String,Object> res = new Map<String,Object>{ 'success' => false, 'message' => '' };
        
        if (String.isBlank(emailId)) { 
            res.put('message','Missing Email ID'); 
            return res; 
        }

        try {
            String currentUserId = UserInfo.getUserId();
            
            // Validate email exists
            List<EmailMessage> emails = [SELECT Id FROM EmailMessage WHERE Id = :emailId LIMIT 1];
            
            if (emails.isEmpty()) {
                res.put('message','EmailMessage not found'); 
                return res;
            }
            
            // Check if user action already exists
            List<EmailUserAction__c> existingActions = [
                SELECT Id, IsPinned__c, IsSeen__c
                FROM EmailUserAction__c 
                WHERE Email__c = :emailId AND User__c = :currentUserId 
                LIMIT 1
            ];
            
            EmailUserAction__c userAction;
            if (existingActions.isEmpty()) {
                // Create new user action
                userAction = new EmailUserAction__c(
                    Email__c = emailId,
                    User__c = currentUserId,
                    IsPinned__c = isPinned,
                    PinnedDate__c = isPinned ? DateTime.now() : null
                );
                insert userAction;
            } else {
                // Update existing action
                userAction = existingActions[0];
                userAction.IsPinned__c = isPinned;
                userAction.PinnedDate__c = isPinned ? DateTime.now() : null;
                update userAction;
            }
            
            res.put('success', true);
            res.put('message', isPinned ? 'Email pinned successfully' : 'Email unpinned successfully');
            System.debug('Email pin status updated for user: ' + currentUserId + ', email: ' + emailId + ' -> ' + isPinned);
            
            return res;
        } catch (Exception e) {
            res.put('message', 'Database error: ' + e.getMessage());
            System.debug('Error updating email pin status: ' + e.getMessage());
            return res;
        }
    }
    
    /**
     * @description Find Contact or Lead by email address for calendar integration
     * @param emailAddress Email address to search for
     * @return Map containing contact/lead information for Event relationship
     */
    @AuraEnabled
    public static Map<String,Object> findContactOrLeadByEmail(String emailAddress) {
        Map<String,Object> result = new Map<String,Object>{
            'success' => false,
            'recordId' => null,
            'recordType' => null,
            'recordName' => null,
            'message' => ''
        };
        
        if (String.isBlank(emailAddress)) {
            result.put('message', 'Email address is required');
            return result;
        }
        
        try {
            // First, search for Contact
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
                result.put('recordType', 'Contact');
                result.put('recordName', contact.Name);
                result.put('accountId', contact.AccountId);
                result.put('accountName', contact.Account?.Name);
                result.put('message', 'Contact found');
                return result;
            }
            
            // If no Contact found, search for Lead
            List<Lead> leads = [
                SELECT Id, Name, Email, Company, Status
                FROM Lead 
                WHERE Email = :emailAddress 
                LIMIT 1
            ];
            
            if (!leads.isEmpty()) {
                Lead lead = leads[0];
                result.put('success', true);
                result.put('recordId', lead.Id);
                result.put('recordType', 'Lead');
                result.put('recordName', lead.Name);
                result.put('company', lead.Company);
                result.put('leadStatus', lead.Status);
                result.put('message', 'Lead found');
                return result;
            }
            
            // No Contact or Lead found
            result.put('message', 'No Contact or Lead found with email: ' + emailAddress);
            System.debug('No Contact or Lead found for email: ' + emailAddress);
            return result;
            
        } catch (Exception e) {
            result.put('message', 'Error searching for Contact/Lead: ' + e.getMessage());
            System.debug('Error in findContactOrLeadByEmail: ' + e.getMessage());
            return result;
        }
    }
    
    /**
     * @description Get single email details by ID
     * @param emailId ID of the email to retrieve
     * @return EmailInfo with full email details
     */
    @AuraEnabled
    public static EmailInfo getEmailDetails(String emailId) {
        try {
            if (String.isBlank(emailId)) {
                throw new AuraHandledException('Email ID is required');
            }
            
            String currentUserEmail = UserInfo.getUserEmail();
            String currentUserId = UserInfo.getUserId();
            
            EmailMessage email = [
                SELECT Id, Subject, FromName, FromAddress, ToAddress, CcAddress, BccAddress,
                       TextBody, HtmlBody, CreatedDate, MessageDate, HasAttachment, Status, Incoming,
                       RelatedToId, RelatedTo.Name, RelatedTo.Type, ParentId, Seen__c, Pin__c
                FROM EmailMessage 
                WHERE Id = :emailId 
                AND (CreatedById = :currentUserId OR 
                     FromAddress = :currentUserEmail OR 
                     ToAddress LIKE :('%' + currentUserEmail + '%') OR 
                     CcAddress LIKE :('%' + currentUserEmail + '%') OR 
                     BccAddress LIKE :('%' + currentUserEmail + '%') OR
                     FromAddress = 'naga@dcgpro.com' OR 
                     ToAddress LIKE '%naga@dcgpro.com%' OR 
                     ToAddress LIKE '%potumartinagasaiharsha@gmail.com%' OR 
                     FromAddress LIKE '%potumartinagasaiharsha@gmail.com%')
                LIMIT 1
            ];
            
            // Get user action for this email
            List<EmailUserAction__c> userActions = [
                SELECT IsSeen__c, IsPinned__c, SeenDate__c, PinnedDate__c
                FROM EmailUserAction__c 
                WHERE Email__c = :emailId AND User__c = :currentUserId 
                LIMIT 1
            ];
            
            EmailUserAction__c userAction = userActions.isEmpty() ? null : userActions[0];
            
            return processEmailMessage(email, userAction);
            
        } catch (Exception e) {
            System.debug('Error getting email details: ' + e.getMessage());
            throw new AuraHandledException('Failed to retrieve email: ' + e.getMessage());
        }
    }
    
    /**
     * @description Get total count of all emails (sent and received) for current user
     * @param fromDate Start date filter (optional)
     * @param toDate End date filter (optional)
     * @return Integer count of total emails
     */
    @AuraEnabled(cacheable=true)
    public static Integer getTotalEmailCount(Date fromDate, Date toDate) {
        try {
            String currentUserEmail = UserInfo.getUserEmail();
            String currentUserId = UserInfo.getUserId();
            String queryString = 'SELECT COUNT() ' +
                                 'FROM EmailMessage ' +
                                 'WHERE IsDeleted = false ';
            
            // Add date filters only if provided
            if (fromDate != null) {
                DateTime fromDateTime = DateTime.newInstance(fromDate, Time.newInstance(0, 0, 0, 0));
                queryString += 'AND CreatedDate >= ' + fromDateTime.formatGmt('yyyy-MM-dd') + 'T00:00:00.000Z ';
            }
            if (toDate != null) {
                DateTime toDateTime = DateTime.newInstance(toDate, Time.newInstance(23, 59, 59, 999));
                queryString += 'AND CreatedDate <= ' + toDateTime.formatGmt('yyyy-MM-dd') + 'T23:59:59.999Z ';
            }
            
            queryString += 'AND (CreatedById = \'' + currentUserId + '\' OR ' +
                          'FromAddress = \'' + currentUserEmail + '\' OR ' +
                          'ToAddress LIKE \'%' + currentUserEmail + '%\' OR ' +
                          'CcAddress LIKE \'%' + currentUserEmail + '%\' OR ' +
                          'BccAddress LIKE \'%' + currentUserEmail + '%\' OR ' +
                          'FromAddress = \'naga@dcgpro.com\' OR ' +
                          'ToAddress LIKE \'%naga@dcgpro.com%\' OR ' +
                          'ToAddress LIKE \'%potumartinagasaiharsha@gmail.com%\' OR ' +
                          'FromAddress LIKE \'%potumartinagasaiharsha@gmail.com%\')';
            return Database.countQuery(queryString);
            
        } catch (Exception e) {
            System.debug('Error getting total email count: ' + e.getMessage());
            return 0;
        }
    }
    
    /**
     * @description Get count of unseen emails for current user
     * @param fromDate Start date filter (optional)
     * @param toDate End date filter (optional)
     * @return Integer count of unseen emails
     */
    @AuraEnabled(cacheable=true)
    public static Integer getUnreadEmailCount(Date fromDate, Date toDate) {
        try {
            String currentUserEmail = UserInfo.getUserEmail();
            String currentUserId = UserInfo.getUserId();
            
            // Get all incoming emails for the user that are not seen
            String queryString = 'SELECT COUNT() ' +
                                 'FROM EmailMessage ' +
                                 'WHERE Incoming = true ' +
                                 'AND IsDeleted = false ' +
                                 'AND Status = \'0\' '; // Status 0 = New (unseen)
            
            // Add date filters only if provided
            if (fromDate != null) {
                DateTime fromDateTime = DateTime.newInstance(fromDate, Time.newInstance(0, 0, 0, 0));
                queryString += 'AND CreatedDate >= ' + fromDateTime.formatGmt('yyyy-MM-dd') + 'T00:00:00.000Z ';
            }
            if (toDate != null) {
                DateTime toDateTime = DateTime.newInstance(toDate, Time.newInstance(23, 59, 59, 999));
                queryString += 'AND CreatedDate <= ' + toDateTime.formatGmt('yyyy-MM-dd') + 'T23:59:59.999Z ';
            }
            
            queryString += 'AND (ToAddress LIKE \'%' + currentUserEmail + '%\' OR ' +
                          'CcAddress LIKE \'%' + currentUserEmail + '%\' OR ' +
                          'BccAddress LIKE \'%' + currentUserEmail + '%\' OR ' +
                          'ToAddress LIKE \'%naga@dcgpro.com%\' OR ' +
                          'ToAddress LIKE \'%potumartinagasaiharsha@gmail.com%\')';
            
            return Database.countQuery(queryString);
            
        } catch (Exception e) {
            System.debug('Error getting unseen email count: ' + e.getMessage());
            return 0;
        }
    }
    
    /**
     * @description Build dynamic SOQL query for all user emails (sent and received)
     * @param limitCount Number of records to limit
     * @param lastEmailId Last email ID for pagination
     * @param fromDate Start date filter (optional)
     * @param toDate End date filter (optional)
     * @return String SOQL query
     */
    private static String buildEmailQuery(Integer limitCount, String lastEmailId, Date fromDate, Date toDate) {
        String currentUserEmail = UserInfo.getUserEmail();
        String currentUserId = UserInfo.getUserId();
        
        // Build query to include only emails related to current user
        String query = 'SELECT Id, Subject, FromName, FromAddress, ToAddress, CcAddress, BccAddress, ' +
                      'TextBody, HtmlBody, CreatedDate, MessageDate, HasAttachment, Status, Incoming, ' +
                      'RelatedToId, RelatedTo.Name, RelatedTo.Type, ParentId, Seen__c, Pin__c ' +
                      'FROM EmailMessage ' +
                      'WHERE IsDeleted = false ';
        
        // Add date filters only if provided
        if (fromDate != null) {
            DateTime fromDateTime = DateTime.newInstance(fromDate, Time.newInstance(0, 0, 0, 0));
            query += 'AND CreatedDate >= ' + fromDateTime.formatGmt('yyyy-MM-dd') + 'T00:00:00.000Z ';
        }
        if (toDate != null) {
            DateTime toDateTime = DateTime.newInstance(toDate, Time.newInstance(23, 59, 59, 999));
            query += 'AND CreatedDate <= ' + toDateTime.formatGmt('yyyy-MM-dd') + 'T23:59:59.999Z ';
        }
        
        query += 'AND (' +
                // Received emails: user is in To, CC, or BCC (regardless of Incoming flag)
                '(ToAddress LIKE \'%' + currentUserEmail + '%\' OR ' +
                'CcAddress LIKE \'%' + currentUserEmail + '%\' OR ' +
                'BccAddress LIKE \'%' + currentUserEmail + '%\') OR ' +
                // Sent emails: user is the sender (outgoing emails only)
                '(Incoming = false AND FromAddress = \'' + currentUserEmail + '\')' +
                ') ';
        
        // Add pagination condition if lastEmailId provided
        if (String.isNotBlank(lastEmailId)) {
            try {
                // Get the CreatedDate of the last email to use for pagination
                EmailMessage lastEmail = [SELECT CreatedDate FROM EmailMessage WHERE Id = :lastEmailId LIMIT 1];
                String lastCreatedDate = lastEmail.CreatedDate.formatGmt('yyyy-MM-dd') + 'T' + lastEmail.CreatedDate.formatGmt('HH:mm:ss') + '.000Z';
                query += 'AND CreatedDate < ' + lastCreatedDate + ' ';
            } catch (Exception e) {
                // If we can't find the last email, ignore pagination
                System.debug('Error with pagination lastEmailId: ' + e.getMessage());
            }
        }
        
        query += 'ORDER BY CreatedDate DESC LIMIT ' + limitCount;
        
        System.debug('EmailInboxController Query: ' + query);
        return query;
    }
    
    /**
     * @description Get current user's email address for notification filtering
     * @return String current user's email address
     */
    @AuraEnabled(cacheable=true)
    public static String getCurrentUserEmail() {
        try {
            return UserInfo.getUserEmail();
        } catch (Exception e) {
            System.debug('Error getting current user email: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Debug method to test email access
     * @return String debug information about emails
     */
    @AuraEnabled
    public static String debugEmailAccess() {
        try {
            String currentUserEmail = UserInfo.getUserEmail();
            String currentUserId = UserInfo.getUserId();
            
            String debugInfo = 'Current User: ' + currentUserEmail + ' (ID: ' + currentUserId + ')\n';
            
            // Count all emails in system
            Integer totalEmails = [SELECT COUNT() FROM EmailMessage WHERE IsDeleted = false];
            debugInfo += 'Total emails in system: ' + totalEmails + '\n';
            
            // Count emails from specific addresses
            Integer nagarEmails = [SELECT COUNT() FROM EmailMessage WHERE FromAddress = 'naga@dcgpro.com' AND IsDeleted = false];
            debugInfo += 'Emails from naga@dcgpro.com: ' + nagarEmails + '\n';
            
            Integer praneethEmails = [SELECT COUNT() FROM EmailMessage WHERE FromAddress = 'praneeth@dcgpro.com' AND IsDeleted = false];
            debugInfo += 'Emails from praneeth@dcgpro.com: ' + praneethEmails + '\n';
            
            Integer potumartEmails = [SELECT COUNT() FROM EmailMessage WHERE ToAddress LIKE '%potumartinagasaiharsha@gmail.com%' AND IsDeleted = false];
            debugInfo += 'Emails to potumartinagasaiharsha@gmail.com: ' + potumartEmails + '\n';
            
            // Get sample email data
            List<EmailMessage> sampleEmails = [SELECT Id, Subject, FromAddress, ToAddress, CreatedDate 
                                              FROM EmailMessage 
                                              WHERE IsDeleted = false 
                                              ORDER BY CreatedDate DESC 
                                              LIMIT 5];
            
            debugInfo += '\nSample emails:\n';
            for(EmailMessage email : sampleEmails) {
                debugInfo += 'From: ' + email.FromAddress + ' To: ' + email.ToAddress + ' Subject: ' + email.Subject + '\n';
            }
            
            return debugInfo;
            
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }
    
    /**
     * @description Process EmailMessage record into EmailInfo wrapper
     * @param email EmailMessage record
     * @return EmailInfo processed email data
     */
    private static EmailInfo processEmailMessage(EmailMessage email) {
        EmailInfo emailInfo = new EmailInfo();
        String userEmail = UserInfo.getUserEmail();
        
        emailInfo.id = email.Id;
        emailInfo.subject = String.isNotBlank(email.Subject) ? email.Subject : '(No Subject)';
        emailInfo.fromName = email.FromName;
        emailInfo.fromAddress = email.FromAddress;
        emailInfo.toAddress = email.ToAddress;
        emailInfo.ccAddress = email.CcAddress;
        emailInfo.bccAddress = email.BccAddress;
        emailInfo.textBody = email.TextBody;
        emailInfo.htmlBody = email.HtmlBody;
        emailInfo.createdDate = email.CreatedDate;
        emailInfo.messageDate = email.MessageDate != null ? email.MessageDate : email.CreatedDate;
        emailInfo.relativeDate = getRelativeTime(email.MessageDate != null ? email.MessageDate : email.CreatedDate);
        emailInfo.hasAttachment = email.HasAttachment;
        emailInfo.status = email.Status;
        emailInfo.incoming = email.Incoming;
        
        // Determine if this is sent or received email
        Boolean isSentByUser = (email.FromAddress == userEmail);
        emailInfo.emailType = isSentByUser ? 'Sent' : 'Received';
        
        // Use both Status field (existing unread logic) and new Seen__c field (NEW email logic)
        // For incoming emails, use Seen__c field for the Unseen filter functionality
        // For outgoing emails, use Status field (existing logic)
        if (email.Incoming) {
            emailInfo.isSeen = (email.Seen__c == true); // For incoming: use Seen__c field
        } else {
            emailInfo.isSeen = (email.Status == '1'); // For outgoing: use Status field (existing logic)
        }
        
        // Add isNew field for NEW email feature (green bar + NEW pill)
        emailInfo.isNew = (email.Incoming && !email.Seen__c); // NEW = Incoming AND not Seen
        
        // Add isPinned field from Pin__c database field
        emailInfo.isPinned = (email.Pin__c == true);
        
        System.debug('Email ' + email.Id + ' - Incoming: ' + email.Incoming + ' - isSeen: ' + emailInfo.isSeen + ' - isPinned: ' + emailInfo.isPinned);
        
        // Create email preview from body
        String bodyForPreview = String.isNotBlank(email.TextBody) ? email.TextBody : 
                               (String.isNotBlank(email.HtmlBody) ? email.HtmlBody.replaceAll('<[^>]+>', '') : '');
        emailInfo.preview = String.isNotBlank(bodyForPreview) ? 
                           (bodyForPreview.length() > 150 ? bodyForPreview.substring(0, 147) + '...' : bodyForPreview) :
                           'No preview available';
        
        // Process related record information
        if (email.RelatedToId != null && email.RelatedTo != null) {
            emailInfo.relatedToId = email.RelatedToId;
            emailInfo.relatedToName = email.RelatedTo.Name;
            emailInfo.relatedToType = email.RelatedTo.Type;
            emailInfo.relatedToIcon = getIconForObjectType(email.RelatedTo.Type);
        }
        
        return emailInfo;
    }
    
    /**
     * @description Process EmailMessage into EmailInfo with user-specific actions from junction object
     * @param email EmailMessage record to process
     * @param userAction User-specific action record (can be null)
     * @return EmailInfo processed email data with user-specific seen/pin status
     */
    private static EmailInfo processEmailMessage(EmailMessage email, EmailUserAction__c userAction) {
        EmailInfo emailInfo = new EmailInfo();
        String userEmail = UserInfo.getUserEmail();
        
        emailInfo.id = email.Id;
        emailInfo.subject = String.isNotBlank(email.Subject) ? email.Subject : '(No Subject)';
        emailInfo.fromName = email.FromName;
        emailInfo.fromAddress = email.FromAddress;
        emailInfo.toAddress = email.ToAddress;
        emailInfo.ccAddress = email.CcAddress;
        emailInfo.bccAddress = email.BccAddress;
        emailInfo.textBody = email.TextBody;
        emailInfo.htmlBody = email.HtmlBody;
        emailInfo.createdDate = email.CreatedDate;
        emailInfo.messageDate = email.MessageDate != null ? email.MessageDate : email.CreatedDate;
        emailInfo.relativeDate = getRelativeTime(email.MessageDate != null ? email.MessageDate : email.CreatedDate);
        emailInfo.hasAttachment = email.HasAttachment;
        emailInfo.status = email.Status;
        emailInfo.incoming = email.Incoming;
        
        // Determine if this is sent or received email
        Boolean isSentByUser = (email.FromAddress == userEmail);
        emailInfo.emailType = isSentByUser ? 'Sent' : 'Received';
        
        // Use junction object for user-specific seen/pin status
        if (userAction != null) {
            emailInfo.isSeen = userAction.IsSeen__c;
            emailInfo.isPinned = userAction.IsPinned__c;
        } else {
            // Fallback to legacy fields if no user action exists
            if (email.Incoming) {
                emailInfo.isSeen = (email.Seen__c == true);
            } else {
                emailInfo.isSeen = (email.Status == '1');
            }
            emailInfo.isPinned = (email.Pin__c == true);
        }
        
        // Add isNew field for NEW email feature (green bar + NEW pill)
        emailInfo.isNew = (email.Incoming && !emailInfo.isSeen);
        
        System.debug('Email ' + email.Id + ' - User-specific - isSeen: ' + emailInfo.isSeen + ' - isPinned: ' + emailInfo.isPinned);
        
        // Create email preview from body
        String bodyForPreview = String.isNotBlank(email.TextBody) ? email.TextBody : 
                               (String.isNotBlank(email.HtmlBody) ? email.HtmlBody.replaceAll('<[^>]+>', '') : '');
        emailInfo.preview = String.isNotBlank(bodyForPreview) ? 
                           (bodyForPreview.length() > 150 ? bodyForPreview.substring(0, 147) + '...' : bodyForPreview) :
                           'No preview available';
        
        // Process related record information
        if (email.RelatedToId != null && email.RelatedTo != null) {
            emailInfo.relatedToId = email.RelatedToId;
            emailInfo.relatedToName = email.RelatedTo.Name;
            emailInfo.relatedToType = email.RelatedTo.Type;
            emailInfo.relatedToIcon = getIconForObjectType(email.RelatedTo.Type);
        }
        
        return emailInfo;
    }
    
    /**
     * @description Get relative time string (e.g., "2 hours ago")
     * @param dateTime DateTime to convert
     * @return String relative time description
     */
    private static String getRelativeTime(DateTime emailDateTime) {
        if (emailDateTime == null) {
            return '';
        }
        
        Long diffInSeconds = (DateTime.now().getTime() - emailDateTime.getTime()) / 1000;
        
        if (diffInSeconds < 60) {
            return 'Just now';
        } else if (diffInSeconds < 3600) {
            Long minutes = diffInSeconds / 60;
            return minutes + (minutes == 1 ? ' minute ago' : ' minutes ago');
        } else if (diffInSeconds < 86400) {
            Long hours = diffInSeconds / 3600;
            return hours + (hours == 1 ? ' hour ago' : ' hours ago');
        } else if (diffInSeconds < 2592000) {
            Long days = diffInSeconds / 86400;
            return days + (days == 1 ? ' day ago' : ' days ago');
        } else {
            return emailDateTime.format('MMM d, yyyy');
        }
    }
    
    /**
     * @description Get SLDS icon name for object type
     * @param objectType Salesforce object type
     * @return String SLDS icon name
     */
    private static String getIconForObjectType(String objectType) {
        if (String.isBlank(objectType)) {
            return 'standard:default';
        }
        
        // Map common object types to SLDS icons
        Map<String, String> objectIconMap = new Map<String, String>{
            'Account' => 'standard:account',
            'Contact' => 'standard:contact',
            'Lead' => 'standard:lead',
            'Opportunity' => 'standard:opportunity',
            'Case' => 'standard:case',
            'Task' => 'standard:task',
            'Event' => 'standard:event',
            'Campaign' => 'standard:campaign'
        };
        
        return objectIconMap.get(objectType) != null ? 
               objectIconMap.get(objectType) : 'standard:default';
    }
    
}