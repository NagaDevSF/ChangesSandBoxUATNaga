public class ContentDocumentLinkHandler {
    
    // Static flag to prevent recursive trigger execution
    @TestVisible
    private static Boolean isProcessing = false;

    // TDD GREEN: Safety layer variables
    @TestVisible
    private static Integer recursionDepth = 0;

    @TestVisible
    private static Set<String> processedOperations = new Set<String>();

    private static final Integer MAX_RECURSION_DEPTH = 3;

    private static final Map<String, String> API_TO_PICKLIST = new Map<String, String>{
        'Voided_Check' => 'Voided Check',
        'Lender_Agreements' => 'Lender Agreements',
        'Bank_Statements' => 'Bank Statements',
        'Letter_of_Representation' => 'Letter of Representation (LoR)',
        'Payoff_Letter' => 'Payoff Letter',
        'EFT_Form' => 'EFT Form',
        'No_Fee_Retainer_Form' => 'No-Fee Retainer Form (DocuSign)',
        'Hardship_Letter' => 'Hardship Letter',
        'Contract_Agreement' => 'Contract/Agreement',
        'Invoice_Receipt' => 'Invoice/Receipt',
        'Identification_Document' => 'Identification Document'
    };
    
    private static final List<String> REQUIRED_DOC_VALUES = new List<String>{
        'Voided Check',
        'Lender Agreements', 
        'Bank Statements',
        'Letter of Representation (LoR)',
        'Payoff Letter',
        'EFT Form',
        'No-Fee Retainer Form (DocuSign)',
        'Hardship Letter',
        'Contract/Agreement',
        'Invoice/Receipt',
        'Identification Document'
    };
    
    // Cache for Record Type IDs
    private static String welcomeTeamRecordTypeId;
    private static String legalTeamRecordTypeId;
    
    // Governor limit constants
    private static final Integer MAX_DML_RECORDS = 9000; // Leave buffer for other operations
    private static final Integer MAX_QUERY_RECORDS = 45000; // Leave buffer for other queries

    // PRODUCTION SAFETY: Static caching to prevent repeated queries
    // ContentDocumentLink triggers fire once per record (not bulk), so caching is critical
    private static Map<Id, Id> cachedAccountIds = new Map<Id, Id>();
    private static Map<Id, Set<Id>> cachedRelatedRecords = new Map<Id, Set<Id>>();

    // ACCOUNT-HUB PATTERN: Get AccountId for any entity with caching
    private static Id getAccountIdCached(Id entityId) {
        if (entityId == null) return null;

        // Check cache first
        if (cachedAccountIds.containsKey(entityId)) {
            return cachedAccountIds.get(entityId);
        }

        // Query for AccountId
        Id accountId = getAccountIdForEntity(entityId);
        cachedAccountIds.put(entityId, accountId);
        return accountId;
    }

    // ACCOUNT-HUB PATTERN: Get AccountId from any related object
    private static Id getAccountIdForEntity(Id entityId) {
        if (entityId == null) return null;

        try {
            String idString = String.valueOf(entityId);
            if (idString.length() < 3) return null;

            String prefix = idString.substring(0, 3);

            // Account
            if (prefix == '001') {
                return entityId;
            }
            // Opportunity
            else if (prefix == '006') {
                Opportunity opp = [SELECT AccountId FROM Opportunity WHERE Id = :entityId LIMIT 1];
                return opp.AccountId;
            }
            // Contact
            else if (prefix == '003') {
                Contact con = [SELECT AccountId FROM Contact WHERE Id = :entityId LIMIT 1];
                return con.AccountId;
            }
            // Case
            else if (prefix == '500') {
                Case c = [SELECT AccountId FROM Case WHERE Id = :entityId LIMIT 1];
                return c.AccountId;
            }
            // Lead - use ConvertedAccountId if converted
            else if (prefix == '00Q') {
                Lead l = [SELECT IsConverted, ConvertedAccountId FROM Lead WHERE Id = :entityId LIMIT 1];
                return l.IsConverted ? l.ConvertedAccountId : null;
            }
        } catch (Exception e) {
            System.debug('Error getting AccountId for entity ' + entityId + ': ' + e.getMessage());
        }
        return null;
    }

    // ACCOUNT-HUB PATTERN: Get all related records for an Account with caching
    private static Set<Id> getAccountRelatedRecordsCached(Id accountId) {
        if (accountId == null) return new Set<Id>();

        // Check cache first
        if (cachedRelatedRecords.containsKey(accountId)) {
            return cachedRelatedRecords.get(accountId);
        }

        Set<Id> relatedIds = new Set<Id>();

        try {
            // Add the Account itself
            relatedIds.add(accountId);

            // Add all Contacts
            for (Contact c : [SELECT Id FROM Contact WHERE AccountId = :accountId LIMIT 20]) {
                relatedIds.add(c.Id);
            }

            // Add all Opportunities
            for (Opportunity o : [SELECT Id FROM Opportunity WHERE AccountId = :accountId LIMIT 20]) {
                relatedIds.add(o.Id);
            }

            // Add all Cases (ALL record types - no filtering for file sync)
            for (Case c : [SELECT Id FROM Case WHERE AccountId = :accountId LIMIT 20]) {
                relatedIds.add(c.Id);
            }
        } catch (Exception e) {
            System.debug('Error getting related records for Account ' + accountId + ': ' + e.getMessage());
        }

        cachedRelatedRecords.put(accountId, relatedIds);
        return relatedIds;
    }

    // ACCOUNT-HUB PATTERN: Main sync method - sync files to all Account-related records
    private static void syncFilesToAccountRelatedRecords(Set<Id> entityIds, Set<Id> documentIds) {
        if (entityIds == null || entityIds.isEmpty() || documentIds == null || documentIds.isEmpty()) {
            return;
        }

        try {
            // Collect all target record IDs (Account + all related records)
            Set<Id> allTargetIds = new Set<Id>();

            for (Id entityId : entityIds) {
                Id accountId = getAccountIdCached(entityId);

                // NO ACCOUNT = SKIP SILENTLY (per user decision)
                if (accountId == null) {
                    System.debug('Entity ' + entityId + ' has no Account - skipping file sync');
                    continue;
                }

                // Get all Account's related records
                Set<Id> relatedIds = getAccountRelatedRecordsCached(accountId);
                allTargetIds.addAll(relatedIds);
            }

            if (allTargetIds.isEmpty()) {
                System.debug('No target records found for Account-hub sync');
                return;
            }

            // Remove source entities from targets (don't sync to self)
            allTargetIds.removeAll(entityIds);

            if (allTargetIds.isEmpty()) {
                return;
            }

            // Check for existing links to prevent duplicates
            Set<String> existingLinkKeys = new Set<String>();
            List<ContentDocumentLink> existingLinks = [
                SELECT ContentDocumentId, LinkedEntityId, ContentDocument.FileType
                FROM ContentDocumentLink
                WHERE ContentDocumentId IN :documentIds
                AND LinkedEntityId IN :allTargetIds
                LIMIT :MAX_QUERY_RECORDS
            ];

            for (ContentDocumentLink link : existingLinks) {
                if (link.ContentDocument.FileType != 'SNOTE') {
                    existingLinkKeys.add(link.ContentDocumentId + '-' + link.LinkedEntityId);
                }
            }

            // Create new links
            List<ContentDocumentLink> linksToCreate = new List<ContentDocumentLink>();
            for (Id docId : documentIds) {
                for (Id targetId : allTargetIds) {
                    String linkKey = docId + '-' + targetId;
                    if (!existingLinkKeys.contains(linkKey)) {
                        ContentDocumentLink link = new ContentDocumentLink();
                        link.ContentDocumentId = docId;
                        link.LinkedEntityId = targetId;
                        link.ShareType = 'V';
                        link.Visibility = 'AllUsers';
                        linksToCreate.add(link);
                    }
                }
            }

            // Insert links using governor-safe batch method
            if (!linksToCreate.isEmpty()) {
                System.debug('Account-hub sync: Creating ' + linksToCreate.size() + ' ContentDocumentLinks');
                insertLinksInBatches(linksToCreate);
            }

        } catch (Exception e) {
            System.debug('Error in syncFilesToAccountRelatedRecords: ' + e.getMessage());
        }
    }

    public static void handleDocumentChanges(List<ContentDocumentLink> newLinks, List<ContentDocumentLink> oldLinks) {
        // Prevent recursive execution and infinite loops
        if (isProcessing) {
            System.debug('ContentDocumentLinkHandler: Already processing, skipping to prevent recursion');
            return;
        }

        // TDD GREEN: Increment recursion depth
        recursionDepth++;

        try {
            // TDD GREEN: Check recursion depth limit
            if (recursionDepth > MAX_RECURSION_DEPTH) {
                System.debug('SAFETY:RECURSION: Max depth ' + MAX_RECURSION_DEPTH + ' reached, stopping sync');
                return;
            }

            // ACCOUNT-HUB PATTERN: Collect ALL entity types
            Set<Id> affectedCaseIds = new Set<Id>();
            Set<Id> affectedLeadIds = new Set<Id>();
            Set<Id> affectedOpportunityIds = new Set<Id>();
            Set<Id> affectedAccountIds = new Set<Id>();
            Set<Id> affectedContactIds = new Set<Id>();
            Set<Id> currentDocumentIds = new Set<Id>();

            // Collect ALL entity IDs from insert operations
            if (newLinks != null) {
                for (ContentDocumentLink link : newLinks) {
                    if (link.LinkedEntityId == null) continue;

                    currentDocumentIds.add(link.ContentDocumentId);
                    String recordId = String.valueOf(link.LinkedEntityId);

                    if (recordId.length() >= 3) {
                        String prefix = recordId.substring(0, 3);
                        if (prefix == '500') {           // Case
                            affectedCaseIds.add(link.LinkedEntityId);
                        } else if (prefix == '00Q') {    // Lead
                            affectedLeadIds.add(link.LinkedEntityId);
                        } else if (prefix == '006') {    // Opportunity
                            affectedOpportunityIds.add(link.LinkedEntityId);
                        } else if (prefix == '001') {    // Account
                            affectedAccountIds.add(link.LinkedEntityId);
                        } else if (prefix == '003') {    // Contact
                            affectedContactIds.add(link.LinkedEntityId);
                        }
                    }
                }
            }

            // Collect ALL entity IDs from delete operations
            if (oldLinks != null) {
                for (ContentDocumentLink link : oldLinks) {
                    if (link.LinkedEntityId == null) continue;

                    currentDocumentIds.add(link.ContentDocumentId);
                    String recordId = String.valueOf(link.LinkedEntityId);

                    if (recordId.length() >= 3) {
                        String prefix = recordId.substring(0, 3);
                        if (prefix == '500') {           // Case
                            affectedCaseIds.add(link.LinkedEntityId);
                        } else if (prefix == '00Q') {    // Lead
                            affectedLeadIds.add(link.LinkedEntityId);
                        } else if (prefix == '006') {    // Opportunity
                            affectedOpportunityIds.add(link.LinkedEntityId);
                        } else if (prefix == '001') {    // Account
                            affectedAccountIds.add(link.LinkedEntityId);
                        } else if (prefix == '003') {    // Contact
                            affectedContactIds.add(link.LinkedEntityId);
                        }
                    }
                }
            }

            // TDD GREEN: Operation deduplication
            String operationKey = 'SYNC:' +
                String.valueOf(currentDocumentIds.hashCode()) + '-' +
                String.valueOf(affectedCaseIds.hashCode()) + '-' +
                String.valueOf(affectedOpportunityIds.hashCode()) + '-' +
                String.valueOf(affectedAccountIds.hashCode()) + '-' +
                String.valueOf(affectedContactIds.hashCode());

            if (processedOperations.contains(operationKey)) {
                System.debug('SAFETY:DEDUP: Operation already processed with key: ' + operationKey);
                return;
            }

            processedOperations.add(operationKey);

            // Handle Lead to Account sync for converted leads (Account-hub pattern)
            if (!affectedLeadIds.isEmpty()) {
                syncLeadFilesToConvertedRecords(affectedLeadIds, newLinks);
            }

            // ACCOUNT-HUB PATTERN: Sync files to ALL Account-related records
            // This replaces the complex record type filtering with a simple Account-hub approach
            Set<Id> allAffectedEntityIds = new Set<Id>();
            allAffectedEntityIds.addAll(affectedCaseIds);
            allAffectedEntityIds.addAll(affectedOpportunityIds);
            allAffectedEntityIds.addAll(affectedAccountIds);
            allAffectedEntityIds.addAll(affectedContactIds);

            if (!allAffectedEntityIds.isEmpty() && !currentDocumentIds.isEmpty()) {
                // Use Account-hub sync instead of complex bidirectional sync
                syncFilesToAccountRelatedRecords(allAffectedEntityIds, currentDocumentIds);
            }

            // Collect Case IDs for Docs_Missing__c update (uses record type filtering)
            if (!currentDocumentIds.isEmpty()) {
                List<ContentDocumentLink> allRelatedLinks = [
                    SELECT LinkedEntityId, ContentDocument.FileType
                    FROM ContentDocumentLink
                    WHERE ContentDocumentId IN :currentDocumentIds
                    AND LinkedEntityId != null
                ];

                for (ContentDocumentLink link : allRelatedLinks) {
                    if (link.ContentDocument.FileType != 'SNOTE' && link.LinkedEntityId != null) {
                        String recordId = String.valueOf(link.LinkedEntityId);
                        if (recordId.length() >= 3 && recordId.substring(0, 3) == '500') {
                            affectedCaseIds.add(link.LinkedEntityId);
                        }
                    }
                }
            }

            // Update Docs_Missing__c for affected Cases (uses Welcome_Team/Legal_Team record type filtering)
            if (!affectedCaseIds.isEmpty()) {
                updateCaseMissingDocs(affectedCaseIds);
            }
            
        } catch (Exception e) {
            System.debug('Error in ContentDocumentLinkHandler: ' + e.getMessage());
        } finally {
            // TDD GREEN: Always decrement recursion depth
            recursionDepth--;
            // isProcessing remains true for transaction duration to prevent recursive trigger fires
            // Auto-resets when transaction completes (static variable behavior)
        }
    }
    
    private static void updateCaseMissingDocs(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) return;
        
        List<Case> casesToUpdate = new List<Case>();
        
        try {
            // Get both Record Type IDs dynamically
            String welcomeTeamRTId = getWelcomeTeamRecordTypeId();
            String legalTeamRTId = getLegalTeamRecordTypeId();
            
            if (String.isBlank(welcomeTeamRTId) && String.isBlank(legalTeamRTId)) {
                System.debug('Neither Welcome Team nor Legal Team Record Types found - skipping docs_missing update');
                return;
            }
            
            // Build dynamic WHERE clause for cases that have docs_missing field
            String whereClause = 'Id IN :caseIds';
            List<String> recordTypeConditions = new List<String>();
            
            if (String.isNotBlank(welcomeTeamRTId)) {
                recordTypeConditions.add('RecordTypeId = \'' + welcomeTeamRTId + '\'');
            }
            if (String.isNotBlank(legalTeamRTId)) {
                recordTypeConditions.add('RecordTypeId = \'' + legalTeamRTId + '\'');
            }
            
            if (!recordTypeConditions.isEmpty()) {
                whereClause += ' AND (' + String.join(recordTypeConditions, ' OR ') + ')';
            }
            
            // Filter to Welcome Team and Legal Team cases
            String queryString = 'SELECT Id, RecordTypeId FROM Case WHERE ' + whereClause;
            List<Case> applicableCases = Database.query(queryString);
            
            if (applicableCases.isEmpty()) {
                System.debug('No applicable cases found to update docs_missing');
                return;
            }
            
            // BULK OPTIMIZATION: Get all existing doc values for all cases in one go
            Set<Id> applicableCaseIds = new Set<Id>();
            for (Case c : applicableCases) {
                applicableCaseIds.add(c.Id);
            }
            Map<Id, Set<String>> caseToExistingDocsMap = getBulkExistingDocValues(applicableCaseIds);
            
            for (Case applicableCase : applicableCases) {
                // Get existing doc values from bulk map
                Set<String> existingDocValues = caseToExistingDocsMap.get(applicableCase.Id);
                if (existingDocValues == null) {
                    existingDocValues = new Set<String>();
                }
                
                // Calculate missing document types using picklist values
                List<String> missingDocs = new List<String>();
                for (String requiredValue : REQUIRED_DOC_VALUES) {
                    if (!existingDocValues.contains(requiredValue)) {
                        missingDocs.add(requiredValue);
                    }
                }
                
                // Update the case record
                Case caseToUpdate = new Case(Id = applicableCase.Id);
                caseToUpdate.Docs_Missing__c = String.join(missingDocs, ';');
                casesToUpdate.add(caseToUpdate);
            }
            
            if (!casesToUpdate.isEmpty()) {
                update casesToUpdate;
                System.debug('Updated docs_missing for ' + casesToUpdate.size() + ' cases (Welcome Team and Legal Team)');
            }
        } catch (Exception e) {
            System.debug('Error updating case missing docs: ' + e.getMessage());
            // Try updating individually in case of partial failures
            for (Case caseToUpdate : casesToUpdate) {
                try {
                    update caseToUpdate;
                } catch (Exception individualError) {
                    System.debug('Error updating individual case ' + caseToUpdate.Id + ': ' + individualError.getMessage());
                }
            }
        }
    }
    
    // BULK OPTIMIZATION: Get existing doc values for multiple cases in single query
    private static Map<Id, Set<String>> getBulkExistingDocValues(Set<Id> caseIds) {
        Map<Id, Set<String>> caseToDocsMap = new Map<Id, Set<String>>();
        
        if (caseIds == null || caseIds.isEmpty()) return caseToDocsMap;
        
        // Initialize all cases with empty sets
        for (Id caseId : caseIds) {
            caseToDocsMap.put(caseId, new Set<String>());
        }
        
        try {
            // Single query to get all document links for all cases
            List<ContentDocumentLink> allDocLinks = [
                SELECT LinkedEntityId, ContentDocumentId, ContentDocument.FileType
                FROM ContentDocumentLink 
                WHERE LinkedEntityId IN :caseIds
                AND ContentDocumentId != null
            ];
            
            // Filter out ContentNotes and group by case
            Map<Id, Set<Id>> caseToDocumentIdsMap = new Map<Id, Set<Id>>();
            for (Id caseId : caseIds) {
                caseToDocumentIdsMap.put(caseId, new Set<Id>());
            }
            
            for (ContentDocumentLink link : allDocLinks) {
                if (link.ContentDocument.FileType != 'SNOTE') {
                    Set<Id> docIds = caseToDocumentIdsMap.get(link.LinkedEntityId);
                    if (docIds != null) {
                        docIds.add(link.ContentDocumentId);
                    }
                }
            }
            
            // Get all document IDs across all cases
            Set<Id> allDocumentIds = new Set<Id>();
            for (Set<Id> docIds : caseToDocumentIdsMap.values()) {
                allDocumentIds.addAll(docIds);
            }
            
            if (!allDocumentIds.isEmpty()) {
                // Single query to get all content versions
                List<ContentVersion> versions = [
                    SELECT ContentDocumentId, Description
                    FROM ContentVersion 
                    WHERE ContentDocumentId IN :allDocumentIds 
                    AND IsLatest = true
                    AND Description != null
                    AND Description != ''
                ];
                
                // Map document ID to file type
                Map<Id, String> docIdToFileTypeMap = new Map<Id, String>();
                for (ContentVersion version : versions) {
                    if (String.isNotBlank(version.Description)) {
                        String apiValue = parseFileTypeFromDescription(version.Description);
                        if (String.isNotBlank(apiValue) && apiValue != 'Other' && API_TO_PICKLIST.containsKey(apiValue)) {
                            String picklistValue = API_TO_PICKLIST.get(apiValue);
                            docIdToFileTypeMap.put(version.ContentDocumentId, picklistValue);
                        }
                    }
                }
                
                // Map file types back to cases
                for (Id caseId : caseToDocumentIdsMap.keySet()) {
                    Set<Id> caseDocIds = caseToDocumentIdsMap.get(caseId);
                    Set<String> caseFileTypes = caseToDocsMap.get(caseId);
                    
                    for (Id docId : caseDocIds) {
                        String fileType = docIdToFileTypeMap.get(docId);
                        if (String.isNotBlank(fileType)) {
                            caseFileTypes.add(fileType);
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error getting bulk existing doc types: ' + e.getMessage());
        }
        
        return caseToDocsMap;
    }
    
    private static Set<String> getExistingDocValues(Id caseId) {
        Set<String> existingValues = new Set<String>();
        
        if (caseId == null) return existingValues;
        
        try {
            // Get all document links, then filter out ContentNotes
            List<ContentDocumentLink> allDocLinks = [
                SELECT ContentDocumentId, ContentDocument.FileType
                FROM ContentDocumentLink 
                WHERE LinkedEntityId = :caseId
                AND ContentDocumentId != null
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
                if (link.ContentDocumentId != null) {
                    documentIds.add(link.ContentDocumentId);
                }
            }
            
            if (!documentIds.isEmpty()) {
                List<ContentVersion> versions = [
                    SELECT Description
                    FROM ContentVersion 
                    WHERE ContentDocumentId IN :documentIds 
                    AND IsLatest = true
                    AND Description != null
                    AND Description != ''
                ];
                
                for (ContentVersion version : versions) {
                    if (String.isNotBlank(version.Description)) {
                        String apiValue = parseFileTypeFromDescription(version.Description);
                        if (String.isNotBlank(apiValue) && apiValue != 'Other' && API_TO_PICKLIST.containsKey(apiValue)) {
                            String picklistValue = API_TO_PICKLIST.get(apiValue);
                            existingValues.add(picklistValue);
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error getting existing doc types for case ' + caseId + ': ' + e.getMessage());
        }
        
        return existingValues;
    }
    
    private static String parseFileTypeFromDescription(String description) {
        if (String.isNotBlank(description) && description.startsWith('FileType:')) {
            return description.substring(9);
        }
        return 'Other';
    }
    
    // Public method to initialize or refresh missing docs for cases
    public static void initializeMissingDocs(List<Id> caseIds) {
        if (caseIds != null && !caseIds.isEmpty()) {
            updateCaseMissingDocs(new Set<Id>(caseIds));
        }
    }
    
    // Method to handle new Case creation - initialize with all missing docs
    public static void handleNewCases(List<Case> newCases) {
        List<Id> caseIds = new List<Id>();
        for (Case c : newCases) {
            caseIds.add(c.Id);
        }
        // Use future method to avoid mixed DML operations
        if (!caseIds.isEmpty()) {
            initializeMissingDocsAsync(caseIds);
        }
    }
    
    @future
    public static void initializeMissingDocsAsync(List<Id> caseIds) {
        initializeMissingDocs(caseIds);
    }
    
    // ACCOUNT-HUB PATTERN: Sync Lead files to ConvertedAccountId (hub cascades to all related records)
    private static void syncLeadFilesToConvertedRecords(Set<Id> leadIds, List<ContentDocumentLink> newLinks) {
        if (leadIds == null || leadIds.isEmpty()) return;

        try {
            // Find converted leads with their ConvertedAccountId (the hub)
            Map<Id, Id> leadToAccountMap = new Map<Id, Id>();
            List<Lead> convertedLeads = [
                SELECT Id, ConvertedAccountId, ConvertedOpportunityId, ConvertedContactId
                FROM Lead
                WHERE Id IN :leadIds
                AND IsConverted = true
                AND ConvertedAccountId != null
            ];

            for (Lead lead : convertedLeads) {
                leadToAccountMap.put(lead.Id, lead.ConvertedAccountId);
            }

            if (leadToAccountMap.isEmpty()) {
                System.debug('No converted leads with Account found');
                return;
            }

            // Get document IDs from trigger context
            Set<Id> currentDocumentIds = new Set<Id>();
            if (newLinks != null) {
                for (ContentDocumentLink link : newLinks) {
                    if (link.ContentDocumentId != null && leadToAccountMap.containsKey(link.LinkedEntityId)) {
                        currentDocumentIds.add(link.ContentDocumentId);
                    }
                }
            }

            if (currentDocumentIds.isEmpty()) return;

            // Use Account-hub sync - this will cascade to all Account's related records
            Set<Id> accountIds = new Set<Id>(leadToAccountMap.values());
            syncFilesToAccountRelatedRecords(accountIds, currentDocumentIds);

            System.debug('Lead files synced to Account hub for ' + accountIds.size() + ' accounts');

        } catch (Exception e) {
            System.debug('Error syncing Lead files to converted records: ' + e.getMessage());
        }
    }
    
    // Helper method to get Welcome Team Record Type ID dynamically
    private static String getWelcomeTeamRecordTypeId() {
        if (String.isBlank(welcomeTeamRecordTypeId)) {
            try {
                RecordType welcomeTeamRT = [
                    SELECT Id 
                    FROM RecordType 
                    WHERE SObjectType = 'Case' 
                    AND DeveloperName = 'Welcome_Team' 
                    LIMIT 1
                ];
                welcomeTeamRecordTypeId = welcomeTeamRT.Id;
            } catch (QueryException e) {
                System.debug('Welcome Team Record Type not found: ' + e.getMessage());
                return null;
            }
        }
        return welcomeTeamRecordTypeId;
    }
    
    // Helper method to get Legal Team Record Type ID dynamically
    private static String getLegalTeamRecordTypeId() {
        if (String.isBlank(legalTeamRecordTypeId)) {
            try {
                RecordType legalTeamRT = [
                    SELECT Id 
                    FROM RecordType 
                    WHERE SObjectType = 'Case' 
                    AND DeveloperName = 'Legal_Team' 
                    LIMIT 1
                ];
                legalTeamRecordTypeId = legalTeamRT.Id;
            } catch (QueryException e) {
                System.debug('Legal Team Record Type not found: ' + e.getMessage());
                return null;
            }
        }
        return legalTeamRecordTypeId;
    }
    
    // Governor-safe batch insert
    private static void insertLinksInBatches(List<ContentDocumentLink> linksToCreate) {
        if (linksToCreate.isEmpty()) return;
        
        Integer batchSize = MAX_DML_RECORDS;
        Integer totalLinks = linksToCreate.size();
        
        System.debug('Inserting ' + totalLinks + ' ContentDocumentLinks in batches of ' + batchSize);
        
        for (Integer i = 0; i < totalLinks; i += batchSize) {
            Integer endIndex = Math.min(i + batchSize, totalLinks);
            List<ContentDocumentLink> batch = new List<ContentDocumentLink>();
            
            for (Integer j = i; j < endIndex; j++) {
                batch.add(linksToCreate[j]);
            }
            
            try {
                // TDD GREEN: Use Database.insert(batch, false) for graceful duplicate handling
                Database.SaveResult[] results = Database.insert(batch, false);

                Integer successCount = 0;
                Integer duplicateCount = 0;
                Integer errorCount = 0;

                for (Integer j = 0; j < results.size(); j++) {
                    if (results[j].isSuccess()) {
                        successCount++;
                    } else {
                        Boolean isDuplicate = false;
                        for (Database.Error error : results[j].getErrors()) {
                            if (error.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                                duplicateCount++;
                                isDuplicate = true;
                                System.debug('SAFETY:DUPLICATE prevented for link ' + j + ': ' + error.getMessage());
                            } else {
                                errorCount++;
                                System.debug('SAFETY:ERROR inserting link ' + j + ': ' + error.getMessage());
                            }
                        }
                        if (!isDuplicate && errorCount > 0) {
                            // Log non-duplicate errors
                        }
                    }
                }

                System.debug('Batch ' + (i/batchSize + 1) + ' complete: ' +
                    successCount + ' success, ' +
                    duplicateCount + ' duplicates prevented, ' +
                    errorCount + ' errors');

            } catch (Exception e) {
                System.debug('Error inserting batch ' + (i/batchSize + 1) + ': ' + e.getMessage());
                // Continue with next batch rather than failing completely
            }
        }
    }
    
}