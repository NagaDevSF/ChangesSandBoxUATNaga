public with sharing class OpportunityEmailAttachmentController {
    
    /**
     * Wrapper class to standardize file information
     */
    public class FileWrapper {
        @AuraEnabled public String id;           // File ID (ContentDocument or Attachment)
        @AuraEnabled public String name;         // File name
        @AuraEnabled public String contentType;  // MIME type
        @AuraEnabled public String size;         // Formatted size (e.g., "1.2 MB")
        @AuraEnabled public String source;       // Source (Email, Task, etc.)
        @AuraEnabled public DateTime createdDate; // When file was created
        @AuraEnabled public String sourceId;     // ID of the source record
        @AuraEnabled public String fileType;     // Type of file (ContentDocument or Attachment)
    }
    
    /**
     * Get all email attachments related to an Opportunity
     * @param opportunityId The ID of the Opportunity
     * @return List of FileWrapper objects containing attachment information
     */
    @AuraEnabled(cacheable=true)
    public static List<FileWrapper> getEmailAttachments(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity ID is required');
        }
        
        List<FileWrapper> results = new List<FileWrapper>();
        Set<String> processedIds = new Set<String>(); // Track the unique IDs we've processed
        
        try {
            // Get attachments from Tasks related to Opportunity
            List<FileWrapper> taskAttachments = getTaskAttachments(opportunityId);
            // Add all the task attachments
            for (FileWrapper fw : taskAttachments) {
                String uniqueId = fw.fileType + '_' + fw.id;
                if (!processedIds.contains(uniqueId)) {
                    results.add(fw);
                    processedIds.add(uniqueId);
                }
            }
            System.debug('Task attachments added: ' + results.size());
            
            // Get attachments from Emails directly related to the Opportunity
            List<FileWrapper> directEmailAttachments = getDirectEmailAttachments(opportunityId);
            for (FileWrapper fw : directEmailAttachments) {
                String uniqueId = fw.fileType + '_' + fw.id;
                if (!processedIds.contains(uniqueId)) {
                    results.add(fw);
                    processedIds.add(uniqueId);
                }
            }
            System.debug('After direct email attachments: ' + results.size());
            
            // Get attachments from Emails related to Contacts on the Opportunity
            List<FileWrapper> contactEmailAttachments = getContactEmailAttachments(opportunityId);
            for (FileWrapper fw : contactEmailAttachments) {
                String uniqueId = fw.fileType + '_' + fw.id;
                if (!processedIds.contains(uniqueId)) {
                    results.add(fw);
                    processedIds.add(uniqueId);
                }
            }
            System.debug('After contact email attachments: ' + results.size());
            
            // Get attachments from Emails related to the Account on the Opportunity
            List<FileWrapper> accountEmailAttachments = getAccountEmailAttachments(opportunityId);
            for (FileWrapper fw : accountEmailAttachments) {
                String uniqueId = fw.fileType + '_' + fw.id;
                if (!processedIds.contains(uniqueId)) {
                    results.add(fw);
                    processedIds.add(uniqueId);
                }
            }
            System.debug('After account email attachments: ' + results.size());
            
            // Get Files directly related to the Opportunity
            List<FileWrapper> opportunityFiles = getOpportunityFiles(opportunityId);
            for (FileWrapper fw : opportunityFiles) {
                String uniqueId = fw.fileType + '_' + fw.id;
                if (!processedIds.contains(uniqueId)) {
                    results.add(fw);
                    processedIds.add(uniqueId);
                }
            }
            System.debug('After opportunity files: ' + results.size());
            
            // Sort by created date (newest first)
            results.sort(new FileWrapperComparator());
            
            return results;
            
        } catch (Exception e) {
            System.debug('Error retrieving attachments: ' + e.getMessage() + '\n' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving attachments: ' + e.getMessage());
        }
    }
    
    /**
     * Get attachments from Tasks associated with the Opportunity
     */
    private static List<FileWrapper> getTaskAttachments(Id opportunityId) {
        List<FileWrapper> results = new List<FileWrapper>();
        
        // Get all tasks related to the Opportunity
        List<Task> tasks = [
            SELECT Id, Subject, CreatedDate
            FROM Task
            WHERE WhatId = :opportunityId
        ];
        
        if (tasks.isEmpty()) {
            return results;
        }
        
        Set<Id> taskIds = new Set<Id>();
        for (Task t : tasks) {
            taskIds.add(t.Id);
        }
        
        // Get ContentDocumentLinks for the tasks
        Map<Id, Task> taskMap = new Map<Id, Task>(tasks);
        List<ContentDocumentLink> cdls = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :taskIds
        ];
        
        // Get ContentVersions for files attached to tasks
        Set<Id> contentDocumentIds = new Set<Id>();
        Map<Id, Id> cdToTaskMap = new Map<Id, Id>();
        
        for (ContentDocumentLink cdl : cdls) {
            contentDocumentIds.add(cdl.ContentDocumentId);
            cdToTaskMap.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
        }
        
        if (!contentDocumentIds.isEmpty()) {
            List<ContentVersion> cvs = [
                SELECT Id, Title, ContentDocumentId, FileType, ContentSize, FileExtension, CreatedDate
                FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocumentIds
                AND IsLatest = true
            ];
            
            for (ContentVersion cv : cvs) {
                Id taskId = cdToTaskMap.get(cv.ContentDocumentId);
                Task sourceTask = taskMap.get(taskId);
                
                FileWrapper fw = new FileWrapper();
                fw.id = cv.ContentDocumentId;
                fw.name = cv.Title + (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : '');
                fw.contentType = getContentType(cv.FileExtension);
                fw.size = formatFileSize(cv.ContentSize);
                fw.source = 'Task: ' + sourceTask.Subject;
                fw.createdDate = cv.CreatedDate;
                fw.sourceId = taskId;
                fw.fileType = 'ContentDocument';
                
                results.add(fw);
            }
        }
        
        // Get legacy Attachments for tasks
        List<Attachment> taskAtts = [
            SELECT Id, Name, ParentId, ContentType, BodyLength, CreatedDate
            FROM Attachment
            WHERE ParentId IN :taskIds
        ];
        
        for (Attachment att : taskAtts) {
            Task sourceTask = taskMap.get(att.ParentId);
            
            FileWrapper fw = new FileWrapper();
            fw.id = att.Id;
            fw.name = att.Name;
            fw.contentType = att.ContentType;
            fw.size = formatFileSize(att.BodyLength);
            fw.source = 'Task: ' + sourceTask.Subject;
            fw.createdDate = att.CreatedDate;
            fw.sourceId = att.ParentId;
            fw.fileType = 'Attachment';
            
            results.add(fw);
        }
        
        return results;
    }
    
    /**
     * Get attachments from emails directly related to the Opportunity via RelatedToId
     */
    private static List<FileWrapper> getDirectEmailAttachments(Id opportunityId) {
        List<FileWrapper> results = new List<FileWrapper>();
        
        // Get emails directly related to this Opportunity
        List<EmailMessage> directEmails = [
            SELECT Id, Subject, CreatedDate
            FROM EmailMessage
            WHERE RelatedToId = :opportunityId
        ];
        
        if (directEmails.isEmpty()) {
            return results;
        }
        
        // Get email IDs
        Set<Id> emailIds = new Set<Id>();
        for (EmailMessage email : directEmails) {
            emailIds.add(email.Id);
        }
        
        // Get attachments for these emails
        results.addAll(getEmailAttachmentsForIds(emailIds));
        
        return results;
    }
    
    /**
     * Get attachments from emails related to Contacts that have OpportunityContactRole records
     * for the given Opportunity
     */
    private static List<FileWrapper> getContactEmailAttachments(Id opportunityId) {
        List<FileWrapper> results = new List<FileWrapper>();
        
        // Get contacts related to this opportunity via OpportunityContactRole
        List<OpportunityContactRole> roles = [
            SELECT ContactId
            FROM OpportunityContactRole
            WHERE OpportunityId = :opportunityId
        ];
        
        if (roles.isEmpty()) {
            return results;
        }
        
        // Extract contact IDs
        Set<Id> contactIds = new Set<Id>();
        for (OpportunityContactRole role : roles) {
            contactIds.add(role.ContactId);
        }
        
        // Get EmailMessageRelation records for these contacts
        List<EmailMessageRelation> relations = [
            SELECT EmailMessageId
            FROM EmailMessageRelation
            WHERE RelationId IN :contactIds
            AND RelationType IN ('FromAddress', 'ToAddress', 'CcAddress', 'BccAddress')
        ];
        
        if (relations.isEmpty()) {
            return results;
        }
        
        // Get email IDs
        Set<Id> emailIds = new Set<Id>();
        for (EmailMessageRelation relation : relations) {
            emailIds.add(relation.EmailMessageId);
        }
        
        // Get attachments for these emails
        results.addAll(getEmailAttachmentsForIds(emailIds));
        
        return results;
    }
    
    /**
     * Get attachments from emails related to the Account on the Opportunity
     */
    private static List<FileWrapper> getAccountEmailAttachments(Id opportunityId) {
        List<FileWrapper> results = new List<FileWrapper>();
        
        // Get the Account ID for this Opportunity
        Opportunity opp = [SELECT AccountId FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
        if (opp.AccountId == null) {
            return results;
        }
        
        // Get emails related to this Account
        List<EmailMessage> accountEmails = [
            SELECT Id, Subject, CreatedDate
            FROM EmailMessage
            WHERE RelatedToId = :opp.AccountId
        ];
        
        if (accountEmails.isEmpty()) {
            return results;
        }
        
        // Get email IDs
        Set<Id> emailIds = new Set<Id>();
        for (EmailMessage email : accountEmails) {
            emailIds.add(email.Id);
        }
        
        // Get attachments for these emails
        results.addAll(getEmailAttachmentsForIds(emailIds));
        
        return results;
    }
    
    /**
     * Get files directly attached to the Opportunity
     */
    private static List<FileWrapper> getOpportunityFiles(Id opportunityId) {
        List<FileWrapper> results = new List<FileWrapper>();
        
        // Get ContentDocumentLinks for the Opportunity
        List<ContentDocumentLink> cdls = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :opportunityId
        ];
        
        if (cdls.isEmpty()) {
            return results;
        }
        
        // Get ContentDocumentIds
        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink cdl : cdls) {
            contentDocumentIds.add(cdl.ContentDocumentId);
        }
        
        // Get ContentVersions for these files
        List<ContentVersion> cvs = [
            SELECT Id, Title, ContentDocumentId, FileType, ContentSize, FileExtension, CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds
            AND IsLatest = true
        ];
        
        for (ContentVersion cv : cvs) {
            FileWrapper fw = new FileWrapper();
            fw.id = cv.ContentDocumentId;
            fw.name = cv.Title + (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : '');
            fw.contentType = getContentType(cv.FileExtension);
            fw.size = formatFileSize(cv.ContentSize);
            fw.source = 'Opportunity Files';
            fw.createdDate = cv.CreatedDate;
            fw.sourceId = opportunityId;
            fw.fileType = 'ContentDocument';
            
            results.add(fw);
        }
        
        // Get legacy Attachments for the Opportunity
        List<Attachment> opptyAtts = [
            SELECT Id, Name, ContentType, BodyLength, CreatedDate
            FROM Attachment
            WHERE ParentId = :opportunityId
        ];
        
        for (Attachment att : opptyAtts) {
            FileWrapper fw = new FileWrapper();
            fw.id = att.Id;
            fw.name = att.Name;
            fw.contentType = att.ContentType;
            fw.size = formatFileSize(att.BodyLength);
            fw.source = 'Opportunity Attachments';
            fw.createdDate = att.CreatedDate;
            fw.sourceId = opportunityId;
            fw.fileType = 'Attachment';
            
            results.add(fw);
        }
        
        return results;
    }
    
    /**
     * Helper method to get attachments for a set of email IDs
     */
    private static List<FileWrapper> getEmailAttachmentsForIds(Set<Id> emailIds) {
        List<FileWrapper> results = new List<FileWrapper>();
        
        if (emailIds.isEmpty()) {
            return results;
        }
        
        // Get EmailMessage records
        Map<Id, EmailMessage> emailMap = new Map<Id, EmailMessage>([
            SELECT Id, Subject, CreatedDate
            FROM EmailMessage
            WHERE Id IN :emailIds
        ]);
        
        // Get ContentDocumentLinks for these emails
        List<ContentDocumentLink> cdls = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :emailIds
        ];
        
        Set<Id> contentDocumentIds = new Set<Id>();
        Map<Id, Id> cdToEmailMap = new Map<Id, Id>();
        
        for (ContentDocumentLink cdl : cdls) {
            contentDocumentIds.add(cdl.ContentDocumentId);
            cdToEmailMap.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
        }
        
        if (!contentDocumentIds.isEmpty()) {
            // Use a single query to get the latest versions
            Map<Id, ContentVersion> latestVersions = new Map<Id, ContentVersion>();
            
            for (ContentVersion cv : [
                SELECT Id, Title, ContentDocumentId, FileType, ContentSize, FileExtension, CreatedDate
                FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocumentIds
                AND IsLatest = true
            ]) {
                latestVersions.put(cv.ContentDocumentId, cv);
            }
            
            // Process the latest versions
            for (Id contentDocId : contentDocumentIds) {
                ContentVersion cv = latestVersions.get(contentDocId);
                if (cv != null) {
                    Id emailId = cdToEmailMap.get(contentDocId);
                    EmailMessage sourceEmail = emailMap.get(emailId);
                    
                    if (sourceEmail != null) {
                        FileWrapper fw = new FileWrapper();
                        fw.id = cv.ContentDocumentId;
                        fw.name = cv.Title + (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : '');
                        fw.contentType = getContentType(cv.FileExtension);
                        fw.size = formatFileSize(cv.ContentSize);
                        fw.source = 'Email: ' + sourceEmail.Subject;
                        fw.createdDate = cv.CreatedDate;
                        fw.sourceId = emailId;
                        fw.fileType = 'ContentDocument';
                        
                        results.add(fw);
                    }
                }
            }
        }
        
        // Get legacy Attachments for these emails
        List<Attachment> emailAtts = [
            SELECT Id, Name, ParentId, ContentType, BodyLength, CreatedDate
            FROM Attachment
            WHERE ParentId IN :emailIds
        ];
        
        for (Attachment att : emailAtts) {
            EmailMessage sourceEmail = emailMap.get(att.ParentId);
            
            if (sourceEmail != null) {
                FileWrapper fw = new FileWrapper();
                fw.id = att.Id;
                fw.name = att.Name;
                fw.contentType = att.ContentType;
                fw.size = formatFileSize(att.BodyLength);
                fw.source = 'Email: ' + sourceEmail.Subject;
                fw.createdDate = att.CreatedDate;
                fw.sourceId = att.ParentId;
                fw.fileType = 'Attachment';
                
                results.add(fw);
            }
        }
        
        return results;
    }
    
    /**
     * Format file size to human-readable format
     */
    private static String formatFileSize(Long byteSize) {
        if (byteSize < 1024) {
            return byteSize + ' B';
        } else if (byteSize < 1024 * 1024) {
            Decimal kbSize = byteSize / 1024.0;
            return kbSize.setScale(1) + ' KB';
        } else if (byteSize < 1024 * 1024 * 1024) {
            Decimal mbSize = byteSize / (1024.0 * 1024.0);
            return mbSize.setScale(1) + ' MB';
        } else {
            Decimal gbSize = byteSize / (1024.0 * 1024.0 * 1024.0);
            return gbSize.setScale(1) + ' GB';
        }
    }
    
    /**
     * Get content type from file extension
     */
    private static String getContentType(String extension) {
        if (String.isBlank(extension)) {
            return 'application/octet-stream';
        }
        
        Map<String, String> extensionToContentType = new Map<String, String>{
            'pdf' => 'application/pdf',
            'doc' => 'application/msword',
            'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'xls' => 'application/vnd.ms-excel',
            'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'ppt' => 'application/vnd.ms-powerpoint',
            'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            'txt' => 'text/plain',
            'csv' => 'text/csv',
            'png' => 'image/png',
            'jpg' => 'image/jpeg',
            'jpeg' => 'image/jpeg',
            'gif' => 'image/gif'
        };
        
        String contentType = extensionToContentType.get(extension.toLowerCase());
        return String.isNotBlank(contentType) ? contentType : 'application/octet-stream';
    }
    
    /**
     * Comparator for sorting FileWrapper objects by created date
     */
    private class FileWrapperComparator implements Comparator<FileWrapper> {
        public Integer compare(FileWrapper a, FileWrapper b) {
            // Sort by created date desc (newest first)
            if (a.createdDate > b.createdDate) {
                return -1;
            } else if (a.createdDate < b.createdDate) {
                return 1;
            }
            return 0;
        }
    }
}