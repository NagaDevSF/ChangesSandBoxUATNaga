/**
 * @description Controller for the Unified Notes Manager LWC component.
 *              Provides CRUD operations for ContentNotes with Account-centric architecture.
 *              Notes are linked to Account as the hub and visible on all related records.
 * @author Claude Code
 * @date 2024-12-04
 */
public with sharing class UnifiedNotesController {

    // Governor limit safety margins
    private static final Integer SAFE_QUERY_LIMIT = 95;
    private static final Integer SAFE_DML_LIMIT = 145;

    /**
     * @description Wrapper class for note data returned to LWC
     */
    public class NoteWrapper {
        @AuraEnabled public Id noteId;
        @AuraEnabled public String title;
        @AuraEnabled public String content;
        @AuraEnabled public String createdDate;
        @AuraEnabled public String createdBy;
        @AuraEnabled public Id createdById;
        @AuraEnabled public String lastModifiedDate;
        @AuraEnabled public String lastModifiedBy;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String sourceObject;
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public Boolean canDelete;

        public NoteWrapper() {
            this.canEdit = true;
            this.canDelete = true;
        }
    }

    /**
     * @description Get all notes visible on a record (Account-centric query)
     * @param recordId The ID of the current record
     * @param objectApiName The API name of the object (Account, Opportunity, Contact, Case, Lead)
     * @return List of NoteWrapper objects
     */
    @AuraEnabled(cacheable=true)
    public static List<NoteWrapper> getNotesForRecord(Id recordId, String objectApiName) {
        List<NoteWrapper> notes = new List<NoteWrapper>();

        try {
            // Get the Account ID (hub) for the record
            Id targetId = getAccountIdForRecord(recordId, objectApiName);
            if (targetId == null) {
                // If no Account found, try querying directly from the record
                targetId = recordId;
            }

            // Query ContentDocumentLinks for ContentNotes
            List<ContentDocumentLink> noteLinks = [
                SELECT ContentDocumentId,
                       ContentDocument.Title,
                       ContentDocument.CreatedDate,
                       ContentDocument.CreatedBy.Name,
                       ContentDocument.CreatedById,
                       ContentDocument.LastModifiedDate,
                       ContentDocument.LastModifiedBy.Name,
                       ContentDocument.LatestPublishedVersion.TextPreview,
                       LinkedEntityId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :targetId
                AND ContentDocument.FileType = 'SNOTE'
                ORDER BY ContentDocument.LastModifiedDate DESC
                LIMIT 200
            ];

            // Get full content from ContentNote
            Set<Id> documentIds = new Set<Id>();
            for (ContentDocumentLink link : noteLinks) {
                documentIds.add(link.ContentDocumentId);
            }

            Map<Id, ContentNote> contentNoteMap = new Map<Id, ContentNote>();
            if (!documentIds.isEmpty()) {
                for (ContentNote cn : [
                    SELECT Id, Title, Content, CreatedDate, CreatedById, CreatedBy.Name,
                           LastModifiedDate, LastModifiedBy.Name
                    FROM ContentNote
                    WHERE Id IN :documentIds
                ]) {
                    contentNoteMap.put(cn.Id, cn);
                }
            }

            // Collect all LinkedEntityIds for bulk label lookup
            Set<Id> allLinkedEntityIds = new Set<Id>();
            for (ContentDocumentLink link : noteLinks) {
                allLinkedEntityIds.add(link.LinkedEntityId);
            }

            // Get source object labels in bulk (single query per SObject type instead of per note)
            Map<Id, String> sourceLabelsMap = getSourceObjectLabelsInBulk(allLinkedEntityIds);

            // Build wrapper objects
            Id currentUserId = UserInfo.getUserId();
            for (ContentDocumentLink link : noteLinks) {
                ContentNote cn = contentNoteMap.get(link.ContentDocumentId);
                if (cn != null) {
                    NoteWrapper wrapper = new NoteWrapper();
                    wrapper.noteId = cn.Id;
                    wrapper.title = cn.Title;
                    wrapper.content = cn.Content != null ? stripHtmlTags(cn.Content.toString()) : '';
                    wrapper.createdDate = cn.CreatedDate.format('MM/dd/yyyy h:mm a');
                    wrapper.createdBy = cn.CreatedBy.Name;
                    wrapper.createdById = cn.CreatedById;
                    wrapper.lastModifiedDate = cn.LastModifiedDate.format('MM/dd/yyyy h:mm a');
                    wrapper.lastModifiedBy = cn.LastModifiedBy.Name;
                    wrapper.accountId = targetId;
                    wrapper.sourceObject = sourceLabelsMap.containsKey(link.LinkedEntityId)
                        ? sourceLabelsMap.get(link.LinkedEntityId)
                        : 'Record';
                    // Users can edit/delete any note (as per requirements)
                    wrapper.canEdit = true;
                    wrapper.canDelete = true;
                    notes.add(wrapper);
                }
            }

        } catch (Exception e) {
            System.debug('Error in getNotesForRecord: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            throw new AuraHandledException('Error loading notes: ' + e.getMessage());
        }

        return notes;
    }

    /**
     * @description Create a new note and link to Account (hub)
     * @param title The note title
     * @param content The note content (plain text)
     * @param recordId The ID of the current record
     * @param objectApiName The API name of the object
     * @return The ID of the created ContentNote
     */
    @AuraEnabled
    public static Id createNote(String title, String content, Id recordId, String objectApiName) {
        if (String.isBlank(title)) {
            throw new AuraHandledException('Note title is required');
        }
        if (String.isBlank(content)) {
            throw new AuraHandledException('Note content is required');
        }

        Savepoint sp = Database.setSavepoint();

        try {
            // Create the ContentNote
            ContentNote note = new ContentNote();
            note.Title = title.length() > 255 ? title.substring(0, 255) : title;
            note.Content = Blob.valueOf(content);
            insert note;

            // Determine Account ID (hub)
            Id accountId = getAccountIdForRecord(recordId, objectApiName);

            // Create link to current record
            ContentDocumentLink currentRecordLink = new ContentDocumentLink();
            currentRecordLink.ContentDocumentId = note.Id;
            currentRecordLink.LinkedEntityId = recordId;
            currentRecordLink.ShareType = 'V';
            currentRecordLink.Visibility = 'AllUsers';
            insert currentRecordLink;

            // If we have an Account and it's different from current record, link to Account too
            if (accountId != null && accountId != recordId) {
                ContentDocumentLink accountLink = new ContentDocumentLink();
                accountLink.ContentDocumentId = note.Id;
                accountLink.LinkedEntityId = accountId;
                accountLink.ShareType = 'V';
                accountLink.Visibility = 'AllUsers';

                // Check if link already exists (shouldn't, but safety check)
                List<ContentDocumentLink> existingLinks = [
                    SELECT Id FROM ContentDocumentLink
                    WHERE ContentDocumentId = :note.Id AND LinkedEntityId = :accountId
                    LIMIT 1
                ];

                if (existingLinks.isEmpty()) {
                    insert accountLink;
                }
            }

            return note.Id;

        } catch (Exception e) {
            Database.rollback(sp);
            System.debug('Error in createNote: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            throw new AuraHandledException('Error creating note: ' + e.getMessage());
        }
    }

    /**
     * @description Update an existing note
     * @param noteId The ID of the ContentNote to update
     * @param title The new title
     * @param content The new content
     * @return Success message
     */
    @AuraEnabled
    public static String updateNote(Id noteId, String title, String content) {
        if (String.isBlank(title)) {
            throw new AuraHandledException('Note title is required');
        }
        if (String.isBlank(content)) {
            throw new AuraHandledException('Note content is required');
        }

        try {
            // Query existing note
            List<ContentNote> notes = [
                SELECT Id, Title, Content, OwnerId
                FROM ContentNote
                WHERE Id = :noteId
                LIMIT 1
            ];

            if (notes.isEmpty()) {
                throw new AuraHandledException('Note not found');
            }

            ContentNote note = notes[0];
            note.Title = title.length() > 255 ? title.substring(0, 255) : title;
            note.Content = Blob.valueOf(content);
            update note;

            return 'Success';

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('Error in updateNote: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            throw new AuraHandledException('Error updating note: ' + e.getMessage());
        }
    }

    /**
     * @description Delete a note and all its links
     * @param noteId The ID of the ContentNote to delete
     * @return Success message
     */
    @AuraEnabled
    public static String deleteNote(Id noteId) {
        try {
            // Query the ContentDocument (parent of ContentNote)
            List<ContentDocument> docs = [
                SELECT Id FROM ContentDocument WHERE Id = :noteId LIMIT 1
            ];

            if (docs.isEmpty()) {
                throw new AuraHandledException('Note not found');
            }

            // Delete the ContentDocument (this cascades to ContentDocumentLinks)
            delete docs;

            return 'Success';

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('Error in deleteNote: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            throw new AuraHandledException('Error deleting note: ' + e.getMessage());
        }
    }

    /**
     * @description Get the Account ID for a given record
     * @param recordId The ID of the record
     * @param objectApiName The API name of the object
     * @return The Account ID or null if not found
     */
    @AuraEnabled(cacheable=true)
    public static Id getAccountIdForRecord(Id recordId, String objectApiName) {
        try {
            if (objectApiName == 'Account') {
                return recordId;
            } else if (objectApiName == 'Opportunity') {
                List<Opportunity> opps = [SELECT AccountId FROM Opportunity WHERE Id = :recordId LIMIT 1];
                return opps.isEmpty() ? null : opps[0].AccountId;
            } else if (objectApiName == 'Contact') {
                List<Contact> contacts = [SELECT AccountId FROM Contact WHERE Id = :recordId LIMIT 1];
                return contacts.isEmpty() ? null : contacts[0].AccountId;
            } else if (objectApiName == 'Case') {
                List<Case> cases = [SELECT AccountId FROM Case WHERE Id = :recordId LIMIT 1];
                return cases.isEmpty() ? null : cases[0].AccountId;
            }
            return null;
        } catch (Exception e) {
            System.debug('Error in getAccountIdForRecord: ' + e.getMessage());
            return null;
        }
    }

    /**
     * @description Strip HTML tags from content (ContentNote stores as HTML)
     * @param htmlContent The HTML content to strip
     * @return Plain text without HTML tags
     */
    private static String stripHtmlTags(String htmlContent) {
        if (String.isBlank(htmlContent)) {
            return '';
        }
        // Remove HTML tags
        String plainText = htmlContent.replaceAll('<[^>]+>', '');
        // Decode common HTML entities
        plainText = plainText.replace('&amp;', '&');
        plainText = plainText.replace('&lt;', '<');
        plainText = plainText.replace('&gt;', '>');
        plainText = plainText.replace('&quot;', '"');
        plainText = plainText.replace('&#39;', '\'');
        plainText = plainText.replace('&nbsp;', ' ');
        // Trim extra whitespace
        plainText = plainText.trim();
        return plainText;
    }

    /**
     * @description Get human-readable labels for multiple source objects in bulk.
     *              Uses one SOQL query per SObject type instead of one per record.
     * @param recordIds Set of record IDs to get labels for
     * @return Map of record ID to label string
     */
    private static Map<Id, String> getSourceObjectLabelsInBulk(Set<Id> recordIds) {
        Map<Id, String> labelMap = new Map<Id, String>();
        if (recordIds == null || recordIds.isEmpty()) {
            return labelMap;
        }

        // Group IDs by SObject type using ID prefix
        Set<Id> accountIds = new Set<Id>();
        Set<Id> opportunityIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        Set<Id> caseIds = new Set<Id>();

        for (Id recordId : recordIds) {
            if (recordId == null) continue;
            String prefix = String.valueOf(recordId).substring(0, 3);
            if (prefix == '001') {
                accountIds.add(recordId);
            } else if (prefix == '006') {
                opportunityIds.add(recordId);
            } else if (prefix == '003') {
                contactIds.add(recordId);
            } else if (prefix == '500') {
                caseIds.add(recordId);
            } else {
                labelMap.put(recordId, 'Record');
            }
        }

        // Query each type in bulk (max 4 queries instead of N)
        try {
            if (!accountIds.isEmpty()) {
                for (Account acc : [SELECT Id, Name FROM Account WHERE Id IN :accountIds LIMIT 200]) {
                    labelMap.put(acc.Id, 'Account: ' + acc.Name);
                }
            }

            if (!opportunityIds.isEmpty()) {
                for (Opportunity opp : [SELECT Id, Name FROM Opportunity WHERE Id IN :opportunityIds LIMIT 200]) {
                    labelMap.put(opp.Id, 'Opportunity: ' + opp.Name);
                }
            }

            if (!contactIds.isEmpty()) {
                for (Contact con : [SELECT Id, Name FROM Contact WHERE Id IN :contactIds LIMIT 200]) {
                    labelMap.put(con.Id, 'Contact: ' + con.Name);
                }
            }

            if (!caseIds.isEmpty()) {
                for (Case c : [SELECT Id, CaseNumber FROM Case WHERE Id IN :caseIds LIMIT 200]) {
                    labelMap.put(c.Id, 'Case: ' + c.CaseNumber);
                }
            }
        } catch (Exception e) {
            System.debug('Error getting source object labels in bulk: ' + e.getMessage());
        }

        return labelMap;
    }
}