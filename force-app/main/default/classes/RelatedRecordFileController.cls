public with sharing class RelatedRecordFileController {
    
    // Governor limit constants for safety
    private static final Integer SAFE_QUERY_LIMIT = 95;
    private static final Integer SAFE_DML_LIMIT = 145;
    private static final Integer SAFE_DML_ROWS = 9500;

    // Account-hub pattern: Helper method to get AccountId from any related object
    private static Id getAccountIdForRecord(Id recordId, String objectApiName) {
        if (recordId == null || String.isBlank(objectApiName)) return null;

        try {
            if (objectApiName == 'Account') {
                return recordId;
            } else if (objectApiName == 'Opportunity') {
                Opportunity opp = [SELECT AccountId FROM Opportunity WHERE Id = :recordId LIMIT 1];
                return opp.AccountId;
            } else if (objectApiName == 'Contact') {
                Contact con = [SELECT AccountId FROM Contact WHERE Id = :recordId LIMIT 1];
                return con.AccountId;
            } else if (objectApiName == 'Case') {
                Case c = [SELECT AccountId FROM Case WHERE Id = :recordId LIMIT 1];
                return c.AccountId;
            }
        } catch (Exception e) {
            System.debug('Error getting AccountId for record: ' + e.getMessage());
        }
        return null;
    }

    @AuraEnabled(cacheable=true)
    public static List<FileWrapper> getRecordFiles(Id recordId, String objectApiName) {
        List<FileWrapper> fileWrappers = new List<FileWrapper>();
        
        try {
            // First get all ContentDocumentLinks, then filter out ContentNotes
            List<ContentDocumentLink> allDocLinks = [
                SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension, 
                       ContentDocument.ContentSize, ContentDocument.CreatedDate, ContentDocument.CreatedBy.Name,
                       ContentDocument.FileType, LinkedEntityId
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :recordId 
                ORDER BY ContentDocument.CreatedDate DESC
            ];
            
            // Filter out ContentNotes (FileType = 'SNOTE')
            List<ContentDocumentLink> docLinks = new List<ContentDocumentLink>();
            for (ContentDocumentLink link : allDocLinks) {
                if (link.ContentDocument.FileType != 'SNOTE') {
                    docLinks.add(link);
                }
            }
            
            Set<Id> documentIds = new Set<Id>();
            for (ContentDocumentLink link : docLinks) {
                documentIds.add(link.ContentDocumentId);
            }
            
            Map<Id, ContentVersion> versionMap = new Map<Id, ContentVersion>();
            Set<Id> firstPublishLocationIds = new Set<Id>();

            if (!documentIds.isEmpty()) {
                List<ContentVersion> versions = [
                    SELECT Id, ContentDocumentId, Title, Description, FileExtension, ContentSize, CreatedDate, CreatedBy.Name, FirstPublishLocationId
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :documentIds AND IsLatest = true
                ];

                for (ContentVersion version : versions) {
                    versionMap.put(version.ContentDocumentId, version);
                    if (version.FirstPublishLocationId != null) {
                        firstPublishLocationIds.add(version.FirstPublishLocationId);
                    }
                }
            }

            // Get source object information
            Map<Id, String> sourceObjectMap = getSourceObjectInfo(firstPublishLocationIds);
            
            // Removed allLinksMap - no longer needed for sourceRecord
            
            for (ContentDocumentLink link : docLinks) {
                ContentVersion version = versionMap.get(link.ContentDocumentId);
                if (version != null) {
                    FileWrapper wrapper = new FileWrapper();
                    wrapper.documentId = link.ContentDocumentId;
                    wrapper.versionId = version.Id;
                    wrapper.fileName = version.Title;
                    wrapper.fileExtension = version.FileExtension;
                    wrapper.fileSize = formatFileSize(version.ContentSize);
                    wrapper.createdDate = version.CreatedDate.format('MM/dd/yyyy hh:mm a');
                    wrapper.createdBy = version.CreatedBy.Name;
                    wrapper.fileType = parseFileTypeFromDescription(version.Description);
                    wrapper.downloadUrl = '/sfc/servlet.shepherd/document/download/' + link.ContentDocumentId;
                    wrapper.sourceObject = version.FirstPublishLocationId != null
                        ? sourceObjectMap.get(version.FirstPublishLocationId)
                        : 'Unknown';

                    fileWrappers.add(wrapper);
                }
            }
            
        } catch (QueryException e) {
            System.debug(LoggingLevel.ERROR, 'Query error retrieving record files: ' + e.getMessage());
            throw new AuraHandledException('Unable to retrieve files. Please try again or contact support if the issue persists.');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Unexpected error retrieving record files: ' + e.getMessage() + ' - Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('An unexpected error occurred while retrieving files. Please refresh and try again.');
        }
        
        return fileWrappers;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getFileTypeOptions() {
        List<PicklistOption> fileTypeOptions = new List<PicklistOption>();
        fileTypeOptions.add(new PicklistOption('Voided Check', 'Voided_Check'));
        fileTypeOptions.add(new PicklistOption('Lender Agreements', 'Lender_Agreements'));
        fileTypeOptions.add(new PicklistOption('Bank Statements', 'Bank_Statements'));
        fileTypeOptions.add(new PicklistOption('Letter of Representation (LoR)', 'Letter_of_Representation'));
        fileTypeOptions.add(new PicklistOption('Payoff Letter', 'Payoff_Letter'));
        fileTypeOptions.add(new PicklistOption('EFT Form (if banking info is wrong)', 'EFT_Form'));
        fileTypeOptions.add(new PicklistOption('No-Fee Retainer Form (DocuSign)', 'No_Fee_Retainer_Form'));
        fileTypeOptions.add(new PicklistOption('Hardship Letter', 'Hardship_Letter'));
        fileTypeOptions.add(new PicklistOption('Contract/Agreement', 'Contract_Agreement'));
        fileTypeOptions.add(new PicklistOption('Invoice/Receipt', 'Invoice_Receipt'));
        fileTypeOptions.add(new PicklistOption('Identification Document', 'Identification_Document'));
        fileTypeOptions.add(new PicklistOption('Other', 'Other'));
        
        return fileTypeOptions;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<RelatedRecordWrapper> getRelatedRecords(Id recordId, String objectApiName) {
        List<RelatedRecordWrapper> relatedRecords = new List<RelatedRecordWrapper>();
        
        try {
            if (objectApiName == 'Case') {
                relatedRecords.addAll(getCaseRelatedRecords(recordId));
            } else if (objectApiName == 'Account') {
                relatedRecords.addAll(getAccountRelatedRecords(recordId));
            } else if (objectApiName == 'Contact') {
                relatedRecords.addAll(getContactRelatedRecords(recordId));
            } else if (objectApiName == 'Opportunity') {
                relatedRecords.addAll(getOpportunityRelatedRecords(recordId));
            }
        } catch (QueryException e) {
            System.debug(LoggingLevel.ERROR, 'Query error getting related records: ' + e.getMessage());
            // Return empty list instead of throwing exception for better UX
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Unexpected error getting related records: ' + e.getMessage() + ' - Stack: ' + e.getStackTraceString());
            // Return empty list to prevent UI breakage
        }
        
        return relatedRecords;
    }
    
    @AuraEnabled
    public static String updateFileType(Id versionId, String fileType) {
        try {
            if (versionId == null || String.isBlank(fileType)) {
                throw new AuraHandledException('Version ID and file type are required.');
            }
            ContentVersion version = [SELECT Id, Description, ContentDocumentId FROM ContentVersion WHERE Id = :versionId LIMIT 1];
            version.Description = 'FileType:' + fileType;
            update version;
            
            // Trigger docs_missing recalculation for affected cases
            refreshDocsMissing(version.ContentDocumentId);
            
            return 'Success';
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, 'DML error updating file type: ' + e.getMessage());
            throw new AuraHandledException('Unable to update document type. The file may be locked or you may not have permission to edit it.');
        } catch (QueryException e) {
            System.debug(LoggingLevel.ERROR, 'Query error finding file version: ' + e.getMessage());
            throw new AuraHandledException('Unable to find the specified file. It may have been deleted.');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Unexpected error updating file type: ' + e.getMessage() + ' - Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('An unexpected error occurred. Please refresh the page and try again.');
        }
    }
    
    @AuraEnabled
    public static String updateFileTypes(List<Id> versionIds, String fileType) {
        try {
            if (versionIds == null || versionIds.isEmpty() || String.isBlank(fileType)) {
                throw new AuraHandledException('Version IDs and file type are required.');
            }
            List<ContentVersion> versionsToUpdate = [SELECT Id, Description, ContentDocumentId FROM ContentVersion WHERE Id IN :versionIds];
            Set<Id> documentIds = new Set<Id>();
            
            for (ContentVersion version : versionsToUpdate) {
                version.Description = 'FileType:' + fileType;
                documentIds.add(version.ContentDocumentId);
            }
            
            if (!versionsToUpdate.isEmpty()) {
                update versionsToUpdate;
                
                // Trigger docs_missing recalculation for affected documents
                for (Id docId : documentIds) {
                    refreshDocsMissing(docId);
                }
            }
            return 'Success';
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, 'DML error updating multiple file types: ' + e.getMessage());
            throw new AuraHandledException('Unable to update some document types. Please check if any files are locked and try again.');
        } catch (QueryException e) {
            System.debug(LoggingLevel.ERROR, 'Query error finding file versions: ' + e.getMessage());
            throw new AuraHandledException('Unable to find some of the specified files. They may have been deleted.');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Unexpected error updating file types: ' + e.getMessage() + ' - Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('An unexpected error occurred while updating files. Please try again with fewer files.');
        }
    }
    
    @AuraEnabled
    public static void removeFileFromRecord(Id documentId, Id recordId) {
        try {
            List<ContentDocumentLink> links = [SELECT Id FROM ContentDocumentLink WHERE ContentDocumentId = :documentId AND LinkedEntityId = :recordId];
            if (!links.isEmpty()) {
                delete links;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error removing file from record: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String removeFileFromAllRelatedRecords(Id documentId, Id sourceRecordId, String objectApiName) {
        // Check governor limits before processing
        if (Limits.getDMLStatements() > SAFE_DML_LIMIT) {
            throw new AuraHandledException('System is busy. Please wait a moment and try again.');
        }
        
        try {
            // Get all ContentDocumentLinks for this document
            List<ContentDocumentLink> linksToDelete = [
                SELECT Id, LinkedEntityId, ShareType
                FROM ContentDocumentLink 
                WHERE ContentDocumentId = :documentId
            ];
            
            if (linksToDelete.isEmpty()) {
                return 'No file links found to delete.';
            }
            
            // Filter out inferred shares which cannot be deleted, then delete the rest
            List<ContentDocumentLink> deletableLinks = new List<ContentDocumentLink>();
            for (ContentDocumentLink link : linksToDelete) {
                if (link.ShareType != 'I') { // I = Inferred shares (cannot be deleted)
                    deletableLinks.add(link);
                }
            }
            
            if (!deletableLinks.isEmpty()) {
                Database.delete(deletableLinks, false);
            }
            
            return 'File removed successfully.';
            
        } catch (Exception e) {
            throw new AuraHandledException('Error removing file: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void inheritFilesFromRelatedRecords(Id newRecordId, String objectApiName) {
        try {
            List<RelatedRecordWrapper> relatedRecords = getRelatedRecords(newRecordId, objectApiName);
            Set<Id> allRelatedRecordIds = new Set<Id>();
            
            for (RelatedRecordWrapper record : relatedRecords) {
                allRelatedRecordIds.add(record.recordId);
            }
            
            if (!allRelatedRecordIds.isEmpty()) {
                // Get all files from related records
                // Get all existing links, then filter out ContentNotes
                List<ContentDocumentLink> allExistingLinks = [
                    SELECT ContentDocumentId, ContentDocument.FileType
                    FROM ContentDocumentLink 
                    WHERE LinkedEntityId IN :allRelatedRecordIds
                ];
                
                // Filter out ContentNotes (FileType = 'SNOTE')
                List<ContentDocumentLink> existingLinks = new List<ContentDocumentLink>();
                for (ContentDocumentLink link : allExistingLinks) {
                    if (link.ContentDocument.FileType != 'SNOTE') {
                        existingLinks.add(link);
                    }
                }
                
                Set<Id> contentDocumentIds = new Set<Id>();
                for (ContentDocumentLink link : existingLinks) {
                    contentDocumentIds.add(link.ContentDocumentId);
                }
                
                // Sync all existing files to the new record
                if (!contentDocumentIds.isEmpty()) {
                    syncFileToRecords(new List<Id>(contentDocumentIds), new List<Id>{newRecordId});
                }
            }
        } catch (Exception e) {
            System.debug('Error inheriting files from related records: ' + e.getMessage());
            throw new AuraHandledException('Error inheriting files: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void syncFileToRecords(List<Id> contentDocumentIds, List<Id> targetRecordIds) {
        // Check governor limits before processing
        Integer estimatedDML = contentDocumentIds.size() * targetRecordIds.size();
        if (Limits.getDMLRows() + estimatedDML > SAFE_DML_ROWS) {
            throw new AuraHandledException('Too many files to sync. Please select fewer files or records and try again.');
        }
        
        if (Limits.getQueries() > SAFE_QUERY_LIMIT) {
            throw new AuraHandledException('System is currently processing too many requests. Please try again in a moment.');
        }
        
        try {
            if (contentDocumentIds == null || contentDocumentIds.isEmpty() || 
                targetRecordIds == null || targetRecordIds.isEmpty()) {
                return;
            }
            
            List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
            
            Set<String> existingLinks = new Set<String>();
            List<ContentDocumentLink> existing = [
                SELECT ContentDocumentId, LinkedEntityId 
                FROM ContentDocumentLink 
                WHERE ContentDocumentId IN :contentDocumentIds 
                AND LinkedEntityId IN :targetRecordIds
            ];
            
            for (ContentDocumentLink link : existing) {
                existingLinks.add(String.valueOf(link.ContentDocumentId) + '_' + String.valueOf(link.LinkedEntityId));
            }
            
            for (Id documentId : contentDocumentIds) {
                for (Id recordId : targetRecordIds) {
                    String linkKey = String.valueOf(documentId) + '_' + String.valueOf(recordId);
                    if (!existingLinks.contains(linkKey)) {
                        ContentDocumentLink newLink = new ContentDocumentLink();
                        newLink.ContentDocumentId = documentId;
                        newLink.LinkedEntityId = recordId;
                        newLink.ShareType = 'V';
                        newLink.Visibility = 'AllUsers';
                        newLinks.add(newLink);
                    }
                }
            }
            
            if (!newLinks.isEmpty()) {
                insert newLinks;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error syncing files to records: ' + e.getMessage());
        }
    }
    
    private static List<RelatedRecordWrapper> getCaseRelatedRecords(Id caseId) {
        List<RelatedRecordWrapper> records = new List<RelatedRecordWrapper>();

        try {
            // Account-hub pattern: Get Account first, then all Account's related records
            Case caseRecord = [SELECT AccountId, Account.Name FROM Case WHERE Id = :caseId LIMIT 1];

            // NO ACCOUNT = SKIP SILENTLY (per user decision)
            if (caseRecord.AccountId == null) {
                System.debug('Case has no Account - skipping file sync');
                return records;
            }

            Id accountId = caseRecord.AccountId;

            // Add Account as sync target (the hub)
            records.add(new RelatedRecordWrapper(accountId, caseRecord.Account.Name, 'Account'));

            // Add all Account's related Contacts
            for (Contact c : [SELECT Id, Name FROM Contact WHERE AccountId = :accountId LIMIT 20]) {
                records.add(new RelatedRecordWrapper(c.Id, c.Name, 'Contact'));
            }

            // Add all Account's related Opportunities
            for (Opportunity o : [SELECT Id, Name FROM Opportunity WHERE AccountId = :accountId LIMIT 20]) {
                records.add(new RelatedRecordWrapper(o.Id, o.Name, 'Opportunity'));
            }

            // Add all Account's other Cases (exclude current one)
            for (Case c : [SELECT Id, CaseNumber FROM Case WHERE AccountId = :accountId AND Id != :caseId LIMIT 20]) {
                records.add(new RelatedRecordWrapper(c.Id, c.CaseNumber, 'Case'));
            }

        } catch (Exception e) {
            System.debug('Error getting case related records: ' + e.getMessage());
        }

        return records;
    }
    
    private static List<RelatedRecordWrapper> getAccountRelatedRecords(Id accountId) {
        List<RelatedRecordWrapper> records = new List<RelatedRecordWrapper>();

        // Account IS the hub - get all related records
        // Using LIMIT 20 for consistency with other methods
        for (Contact con : [SELECT Id, Name FROM Contact WHERE AccountId = :accountId LIMIT 20]) {
            records.add(new RelatedRecordWrapper(con.Id, con.Name, 'Contact'));
        }

        for (Opportunity opp : [SELECT Id, Name FROM Opportunity WHERE AccountId = :accountId LIMIT 20]) {
            records.add(new RelatedRecordWrapper(opp.Id, opp.Name, 'Opportunity'));
        }

        for (Case c : [SELECT Id, CaseNumber FROM Case WHERE AccountId = :accountId LIMIT 20]) {
            records.add(new RelatedRecordWrapper(c.Id, c.CaseNumber, 'Case'));
        }

        return records;
    }
    
    private static List<RelatedRecordWrapper> getContactRelatedRecords(Id contactId) {
        List<RelatedRecordWrapper> records = new List<RelatedRecordWrapper>();

        try {
            // Account-hub pattern: Get Account first, then all Account's related records
            Contact contact = [SELECT AccountId, Account.Name FROM Contact WHERE Id = :contactId LIMIT 1];

            // NO ACCOUNT = SKIP SILENTLY (per user decision)
            if (contact.AccountId == null) {
                System.debug('Contact has no Account - skipping file sync');
                return records;
            }

            Id accountId = contact.AccountId;

            // Add Account as sync target (the hub)
            records.add(new RelatedRecordWrapper(accountId, contact.Account.Name, 'Account'));

            // Add all Account's related Opportunities
            for (Opportunity o : [SELECT Id, Name FROM Opportunity WHERE AccountId = :accountId LIMIT 20]) {
                records.add(new RelatedRecordWrapper(o.Id, o.Name, 'Opportunity'));
            }

            // Add all Account's related Cases
            for (Case c : [SELECT Id, CaseNumber FROM Case WHERE AccountId = :accountId LIMIT 20]) {
                records.add(new RelatedRecordWrapper(c.Id, c.CaseNumber, 'Case'));
            }

            // Add all Account's other Contacts (exclude current one)
            for (Contact c : [SELECT Id, Name FROM Contact WHERE AccountId = :accountId AND Id != :contactId LIMIT 20]) {
                records.add(new RelatedRecordWrapper(c.Id, c.Name, 'Contact'));
            }

        } catch (Exception e) {
            System.debug('Error getting contact related records: ' + e.getMessage());
        }

        return records;
    }
    
    private static List<RelatedRecordWrapper> getOpportunityRelatedRecords(Id opportunityId) {
        List<RelatedRecordWrapper> records = new List<RelatedRecordWrapper>();

        try {
            // Account-hub pattern: Get Account first, then all Account's related records
            Opportunity opp = [SELECT AccountId, Account.Name FROM Opportunity WHERE Id = :opportunityId LIMIT 1];

            // NO ACCOUNT = SKIP SILENTLY (per user decision)
            if (opp.AccountId == null) {
                System.debug('Opportunity has no Account - skipping file sync');
                return records;
            }

            Id accountId = opp.AccountId;

            // Add Account as sync target (the hub)
            records.add(new RelatedRecordWrapper(accountId, opp.Account.Name, 'Account'));

            // Add all Account's related Contacts
            for (Contact c : [SELECT Id, Name FROM Contact WHERE AccountId = :accountId LIMIT 20]) {
                records.add(new RelatedRecordWrapper(c.Id, c.Name, 'Contact'));
            }

            // Add all Account's related Cases (ALL record types, not just Welcome/Legal)
            for (Case c : [SELECT Id, CaseNumber FROM Case WHERE AccountId = :accountId LIMIT 20]) {
                records.add(new RelatedRecordWrapper(c.Id, c.CaseNumber, 'Case'));
            }

            // Add all Account's other Opportunities (exclude current one)
            for (Opportunity o : [SELECT Id, Name FROM Opportunity WHERE AccountId = :accountId AND Id != :opportunityId LIMIT 20]) {
                records.add(new RelatedRecordWrapper(o.Id, o.Name, 'Opportunity'));
            }

        } catch (Exception e) {
            System.debug('Error getting opportunity related records: ' + e.getMessage());
        }

        return records;
    }
    
    // Helper method to get source object information from FirstPublishLocationIds
    private static Map<Id, String> getSourceObjectInfo(Set<Id> firstPublishLocationIds) {
        Map<Id, String> sourceObjectMap = new Map<Id, String>();

        if (firstPublishLocationIds == null || firstPublishLocationIds.isEmpty()) {
            return sourceObjectMap;
        }

        // Group IDs by object type using ID prefix
        Set<Id> caseIds = new Set<Id>();
        Set<Id> opportunityIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();

        for (Id recordId : firstPublishLocationIds) {
            if (recordId == null) {
                continue;
            }

            Schema.SObjectType sObjType = recordId.getSObjectType();
            if (sObjType == Case.SObjectType) {
                caseIds.add(recordId);
            } else if (sObjType == Opportunity.SObjectType) {
                opportunityIds.add(recordId);
            } else if (sObjType == Account.SObjectType) {
                accountIds.add(recordId);
            } else if (sObjType == Contact.SObjectType) {
                contactIds.add(recordId);
            }
        }

        // Bulk query each object type separately
        if (!caseIds.isEmpty()) {
            try {
                List<Case> cases = [SELECT Id, CaseNumber, Case_Number__c FROM Case WHERE Id IN :caseIds];
                for (Case c : cases) {
                    String caseDisplay = c.Case_Number__c != null ? c.Case_Number__c : ('CASE - ' + c.CaseNumber);
                    sourceObjectMap.put(c.Id, caseDisplay);
                }

                // Mark any IDs not found as deleted
                for (Id caseId : caseIds) {
                    if (!sourceObjectMap.containsKey(caseId)) {
                        sourceObjectMap.put(caseId, 'Deleted Record');
                    }
                }
            } catch (Exception e) {
                System.debug('Error querying Cases for source object info: ' + e.getMessage());
            }
        }

        if (!opportunityIds.isEmpty()) {
            try {
                List<Opportunity> opportunities = [SELECT Id, Name FROM Opportunity WHERE Id IN :opportunityIds];
                for (Opportunity opp : opportunities) {
                    sourceObjectMap.put(opp.Id, 'OPPORTUNITY - ' + opp.Name);
                }

                // Mark any IDs not found as deleted
                for (Id oppId : opportunityIds) {
                    if (!sourceObjectMap.containsKey(oppId)) {
                        sourceObjectMap.put(oppId, 'Deleted Record');
                    }
                }
            } catch (Exception e) {
                System.debug('Error querying Opportunities for source object info: ' + e.getMessage());
            }
        }

        if (!accountIds.isEmpty()) {
            try {
                List<Account> accounts = [SELECT Id, Name FROM Account WHERE Id IN :accountIds];
                for (Account acc : accounts) {
                    sourceObjectMap.put(acc.Id, 'ACCOUNT - ' + acc.Name);
                }

                // Mark any IDs not found as deleted
                for (Id accId : accountIds) {
                    if (!sourceObjectMap.containsKey(accId)) {
                        sourceObjectMap.put(accId, 'Deleted Record');
                    }
                }
            } catch (Exception e) {
                System.debug('Error querying Accounts for source object info: ' + e.getMessage());
            }
        }

        if (!contactIds.isEmpty()) {
            try {
                List<Contact> contacts = [SELECT Id, Name FROM Contact WHERE Id IN :contactIds];
                for (Contact con : contacts) {
                    sourceObjectMap.put(con.Id, 'CONTACT - ' + con.Name);
                }

                // Mark any IDs not found as deleted
                for (Id conId : contactIds) {
                    if (!sourceObjectMap.containsKey(conId)) {
                        sourceObjectMap.put(conId, 'Deleted Record');
                    }
                }
            } catch (Exception e) {
                System.debug('Error querying Contacts for source object info: ' + e.getMessage());
            }
        }

        // Handle any null IDs
        for (Id recordId : firstPublishLocationIds) {
            if (recordId == null) {
                continue;
            }
            if (!sourceObjectMap.containsKey(recordId)) {
                sourceObjectMap.put(recordId, 'Unknown');
            }
        }

        return sourceObjectMap;
    }

    // Helper method to refresh docs_missing for cases linked to a document
    private static void refreshDocsMissing(Id documentId) {
        if (documentId == null) return;
        
        try {
            // Find all case IDs linked to this document
            // Get all case links, then filter out ContentNotes
            List<ContentDocumentLink> allCaseLinks = [
                SELECT LinkedEntityId, ContentDocument.FileType
                FROM ContentDocumentLink 
                WHERE ContentDocumentId = :documentId 
                AND LinkedEntityId != null
            ];
            
            // Filter out ContentNotes (FileType = 'SNOTE')
            List<ContentDocumentLink> caseLinks = new List<ContentDocumentLink>();
            for (ContentDocumentLink link : allCaseLinks) {
                if (link.ContentDocument.FileType != 'SNOTE') {
                    caseLinks.add(link);
                }
            }
            
            Set<Id> caseIds = new Set<Id>();
            for (ContentDocumentLink link : caseLinks) {
                String recordId = String.valueOf(link.LinkedEntityId);
                // Check if it's a Case ID (starts with '500')
                if (recordId.length() >= 3 && recordId.substring(0, 3) == '500') {
                    caseIds.add(link.LinkedEntityId);
                }
            }
            
            if (!caseIds.isEmpty()) {
                // Trigger the docs_missing update via ContentDocumentLinkHandler
                ContentDocumentLinkHandler.initializeMissingDocs(new List<Id>(caseIds));
            }
        } catch (Exception e) {
            System.debug('Error refreshing docs_missing: ' + e.getMessage());
        }
    }
    
    // Removed getAllDocumentLinks - sourceRecord column removed
    
    // Removed determineSourceRecord - sourceRecord column removed
    
    private static String parseFileTypeFromDescription(String description) {
        if (String.isNotBlank(description) && description.startsWith('FileType:')) {
            return description.substring(9);
        }
        return 'Other';
    }
    
    private static String formatFileSize(Integer bytes) {
        if (bytes == null || bytes == 0) return '0 Bytes';
        Integer k = 1024;
        List<String> sizes = new List<String>{'Bytes', 'KB', 'MB', 'GB', 'TB'};
        Integer i = (Integer)(Math.log(bytes) / Math.log(k));
        // Prevent index out of bounds
        if (i >= sizes.size()) {
            i = sizes.size() - 1;
        }
        Decimal size = bytes / Math.pow(k, i);
        return size.setScale(2) + ' ' + sizes[i];
    }
    
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        
        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
    
    public class FileWrapper {
        @AuraEnabled public Id documentId;
        @AuraEnabled public Id versionId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public String fileSize;
        @AuraEnabled public String createdDate;
        @AuraEnabled public String createdBy;
        @AuraEnabled public String fileType;
        @AuraEnabled public String downloadUrl;
        @AuraEnabled public String sourceObject;
        // Removed sourceRecord - automatic sync enabled
    }
    
    public class RelatedRecordWrapper {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String objectLabel;
        
        public RelatedRecordWrapper(Id recordId, String name, String objectLabel) {
            this.recordId = recordId;
            this.name = name;
            this.objectLabel = objectLabel;
        }
    }
}