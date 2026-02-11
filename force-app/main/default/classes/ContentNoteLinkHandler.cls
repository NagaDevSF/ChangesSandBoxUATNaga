/**
 * @description Trigger handler for auto-syncing ContentNotes to related records.
 *              When a ContentNote is linked to an Account, it automatically syncs
 *              to all related Opportunities, Contacts, and Cases.
 * @author Claude Code
 * @date 2024-12-04
 */
public class ContentNoteLinkHandler {

    // Recursion prevention - Layer 1: Processing flag
    @TestVisible
    private static Boolean isProcessing = false;

    // Recursion prevention - Layer 2: Depth counter
    @TestVisible
    private static Integer recursionDepth = 0;

    // Recursion prevention - Layer 3: Processed operations tracking
    @TestVisible
    private static Set<String> processedOperations = new Set<String>();

    // Constants for governor limit management
    private static final Integer MAX_RECURSION_DEPTH = 3;
    private static final Integer MAX_DML_RECORDS = 9000;
    private static final Integer MAX_QUERY_RECORDS = 45000;

    /**
     * @description Main entry point called from ContentDocumentLinkTrigger
     * @param newLinks List of newly inserted ContentDocumentLinks
     * @param oldLinks List of deleted ContentDocumentLinks (for delete context)
     */
    public static void handleNoteChanges(List<ContentDocumentLink> newLinks, List<ContentDocumentLink> oldLinks) {
        // Recursion prevention check
        if (isProcessing) {
            System.debug('ContentNoteLinkHandler: Skipping - already processing');
            return;
        }

        recursionDepth++;

        if (recursionDepth > MAX_RECURSION_DEPTH) {
            System.debug('ContentNoteLinkHandler: Max recursion depth reached (' + MAX_RECURSION_DEPTH + ')');
            recursionDepth--;
            return;
        }

        try {
            isProcessing = true;

            if (newLinks != null && !newLinks.isEmpty()) {
                handleInsert(newLinks);
            }

            // Note: Delete handling is optional - Salesforce auto-cleans up links
            // when ContentDocument is deleted

        } catch (Exception e) {
            System.debug('Error in ContentNoteLinkHandler: ' + e.getMessage() + ' - ' + e.getStackTraceString());
        } finally {
            recursionDepth--;
            if (recursionDepth == 0) {
                isProcessing = false;
                processedOperations.clear();
            }
        }
    }

    /**
     * @description Handle insert of new ContentDocumentLinks
     * @param newLinks List of newly inserted links
     */
    private static void handleInsert(List<ContentDocumentLink> newLinks) {
        // Collect document IDs to check if they're ContentNotes
        Set<Id> documentIds = new Set<Id>();
        for (ContentDocumentLink link : newLinks) {
            documentIds.add(link.ContentDocumentId);
        }

        // Query to find which documents are ContentNotes (SNOTE)
        Map<Id, ContentDocument> noteDocuments = new Map<Id, ContentDocument>([
            SELECT Id, FileType
            FROM ContentDocument
            WHERE Id IN :documentIds
            AND FileType = 'SNOTE'
        ]);

        if (noteDocuments.isEmpty()) {
            System.debug('ContentNoteLinkHandler: No ContentNotes found in this batch');
            return;
        }

        // Filter to only ContentNote links that are linked to Accounts
        Set<Id> accountIds = new Set<Id>();
        Set<Id> noteDocumentIds = new Set<Id>();
        Map<Id, Set<Id>> accountToDocuments = new Map<Id, Set<Id>>();

        for (ContentDocumentLink link : newLinks) {
            // Only process ContentNotes
            if (!noteDocuments.containsKey(link.ContentDocumentId)) {
                continue;
            }

            // Check if linked to Account (ID prefix '001')
            String entityPrefix = String.valueOf(link.LinkedEntityId).substring(0, 3);
            if (entityPrefix == '001') {
                accountIds.add(link.LinkedEntityId);
                noteDocumentIds.add(link.ContentDocumentId);

                if (!accountToDocuments.containsKey(link.LinkedEntityId)) {
                    accountToDocuments.put(link.LinkedEntityId, new Set<Id>());
                }
                accountToDocuments.get(link.LinkedEntityId).add(link.ContentDocumentId);
            }
        }

        if (accountIds.isEmpty()) {
            System.debug('ContentNoteLinkHandler: No Account-linked notes found');
            return;
        }

        // Generate operation key for deduplication
        String operationKey = 'NOTE_SYNC:' +
            String.valueOf(accountIds.hashCode()) + '-' +
            String.valueOf(noteDocumentIds.hashCode());

        if (processedOperations.contains(operationKey)) {
            System.debug('ContentNoteLinkHandler: Operation already processed');
            return;
        }
        processedOperations.add(operationKey);

        // Sync notes to related records
        syncNotesToRelatedRecords(accountIds, noteDocumentIds, accountToDocuments);
    }

    /**
     * @description Sync notes to all related records of the Accounts
     * @param accountIds Set of Account IDs
     * @param documentIds Set of ContentDocument IDs (notes)
     * @param accountToDocuments Map of Account ID to its document IDs
     */
    private static void syncNotesToRelatedRecords(Set<Id> accountIds, Set<Id> documentIds,
                                                   Map<Id, Set<Id>> accountToDocuments) {
        // Get all related records for each Account
        Map<Id, Set<Id>> accountToRelatedIds = getAccountRelatedRecordIds(accountIds);

        // Build set of all target entity IDs
        Set<Id> allEntityIds = new Set<Id>();
        for (Set<Id> relatedIds : accountToRelatedIds.values()) {
            allEntityIds.addAll(relatedIds);
        }

        if (allEntityIds.isEmpty()) {
            System.debug('ContentNoteLinkHandler: No related records found for Accounts');
            return;
        }

        // Get existing links to prevent duplicates
        Set<String> existingLinkKeys = buildExistingLinksMap(documentIds, allEntityIds);

        // Build new links
        List<ContentDocumentLink> linksToCreate = new List<ContentDocumentLink>();

        for (Id accountId : accountIds) {
            Set<Id> relatedIds = accountToRelatedIds.get(accountId);
            Set<Id> docIds = accountToDocuments.get(accountId);

            if (relatedIds == null || docIds == null) continue;

            for (Id docId : docIds) {
                for (Id targetId : relatedIds) {
                    String linkKey = docId + '-' + targetId;

                    if (!existingLinkKeys.contains(linkKey)) {
                        ContentDocumentLink link = new ContentDocumentLink();
                        link.ContentDocumentId = docId;
                        link.LinkedEntityId = targetId;
                        link.ShareType = 'V';
                        link.Visibility = 'AllUsers';
                        linksToCreate.add(link);
                        existingLinkKeys.add(linkKey); // Prevent duplicates in same batch
                    }
                }
            }
        }

        // Insert links in batches
        if (!linksToCreate.isEmpty()) {
            insertLinksInBatches(linksToCreate);
        }
    }

    /**
     * @description Get all related record IDs for a set of Accounts
     * @param accountIds Set of Account IDs
     * @return Map of Account ID to Set of related record IDs
     */
    private static Map<Id, Set<Id>> getAccountRelatedRecordIds(Set<Id> accountIds) {
        Map<Id, Set<Id>> result = new Map<Id, Set<Id>>();

        // Initialize empty sets
        for (Id accId : accountIds) {
            result.put(accId, new Set<Id>());
        }

        // Get Opportunities
        for (Opportunity opp : [
            SELECT Id, AccountId
            FROM Opportunity
            WHERE AccountId IN :accountIds
            LIMIT :MAX_QUERY_RECORDS
        ]) {
            result.get(opp.AccountId).add(opp.Id);
        }

        // Get Contacts
        for (Contact con : [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId IN :accountIds
            LIMIT :MAX_QUERY_RECORDS
        ]) {
            result.get(con.AccountId).add(con.Id);
        }

        // Get Cases
        for (Case c : [
            SELECT Id, AccountId
            FROM Case
            WHERE AccountId IN :accountIds
            LIMIT :MAX_QUERY_RECORDS
        ]) {
            result.get(c.AccountId).add(c.Id);
        }

        return result;
    }

    /**
     * @description Build a set of existing link keys to prevent duplicates
     * @param documentIds Set of ContentDocument IDs
     * @param entityIds Set of potential target entity IDs
     * @return Set of existing link keys in format "docId-entityId"
     */
    private static Set<String> buildExistingLinksMap(Set<Id> documentIds, Set<Id> entityIds) {
        Set<String> existingKeys = new Set<String>();

        // Safety check for large volumes
        if (documentIds.size() > 2000 || entityIds.size() > 2000) {
            System.debug('ContentNoteLinkHandler: Large volume detected, using targeted approach');
            // For large volumes, we'll rely on Database.insert with allOrNone=false
            return existingKeys;
        }

        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :documentIds
            AND LinkedEntityId IN :entityIds
            LIMIT :MAX_QUERY_RECORDS
        ]) {
            existingKeys.add(link.ContentDocumentId + '-' + link.LinkedEntityId);
        }

        return existingKeys;
    }

    /**
     * @description Insert ContentDocumentLinks in batches with error handling
     * @param linksToCreate List of links to insert
     */
    private static void insertLinksInBatches(List<ContentDocumentLink> linksToCreate) {
        Integer totalLinks = linksToCreate.size();
        Integer successCount = 0;
        Integer duplicateCount = 0;
        Integer errorCount = 0;

        System.debug('ContentNoteLinkHandler: Inserting ' + totalLinks + ' note links');

        // Process in batches
        Integer batchSize = MAX_DML_RECORDS;
        for (Integer i = 0; i < totalLinks; i += batchSize) {
            Integer endIndex = Math.min(i + batchSize, totalLinks);
            List<ContentDocumentLink> batch = new List<ContentDocumentLink>();

            for (Integer j = i; j < endIndex; j++) {
                batch.add(linksToCreate[j]);
            }

            // Use allOrNone = false for graceful error handling
            Database.SaveResult[] results = Database.insert(batch, false);

            for (Integer j = 0; j < results.size(); j++) {
                if (results[j].isSuccess()) {
                    successCount++;
                } else {
                    for (Database.Error error : results[j].getErrors()) {
                        if (error.getStatusCode() == StatusCode.DUPLICATE_VALUE ||
                            error.getMessage().contains('DUPLICATE')) {
                            duplicateCount++;
                            System.debug('ContentNoteLinkHandler: Duplicate link prevented');
                        } else {
                            errorCount++;
                            System.debug('ContentNoteLinkHandler: Error inserting link - ' + error.getMessage());
                        }
                    }
                }
            }
        }

        System.debug('ContentNoteLinkHandler: Completed - Success: ' + successCount +
                     ', Duplicates: ' + duplicateCount + ', Errors: ' + errorCount);
    }

    /**
     * @description Reset static variables (for testing)
     */
    @TestVisible
    private static void resetState() {
        isProcessing = false;
        recursionDepth = 0;
        processedOperations.clear();
    }
}