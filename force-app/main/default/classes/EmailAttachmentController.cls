// File: force-app/main/default/classes/EmailAttachmentController.cls
public with sharing class EmailAttachmentController {

    public class DocWrapper {
        @AuraEnabled public Id    docId;
        @AuraEnabled public String title;
        @AuraEnabled public String downloadUrl;
        public DocWrapper(Id docId, String title, String downloadUrl) {
            this.docId       = docId;
            this.title       = title;
            this.downloadUrl = downloadUrl;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<DocWrapper> getEmailAttachments(Id recordId) {
        // 1) Find all Email-type Tasks on the record (Lead via WhoId, Case via WhatId)
        List<Task> emailTasks = [
            SELECT Id
              FROM Task
             WHERE (WhoId = :recordId OR WhatId = :recordId)
               AND Type       = 'Email'
               AND IsArchived = FALSE
        ];
        if (emailTasks.isEmpty()) {
            return new List<DocWrapper>();
        }

        // 2) Collect Task IDs
        Set<Id> taskIds = new Set<Id>();
        for (Task t : emailTasks) {
            taskIds.add(t.Id);
        }

        // 3) Find the EmailMessage records behind those Tasks
        List<EmailMessage> emails = [
            SELECT Id
              FROM EmailMessage
             WHERE ActivityId IN :taskIds
        ];
        if (emails.isEmpty()) {
            return new List<DocWrapper>();
        }

        // 4) Collect EmailMessage IDs
        Set<Id> emailIds = new Set<Id>();
        for (EmailMessage em : emails) {
            emailIds.add(em.Id);
        }

        // 5) Query ContentDocumentLink for those emails, pulling in VersionId & Title
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.LatestPublishedVersionId,
                   ContentDocument.Title
              FROM ContentDocumentLink
             WHERE LinkedEntityId IN :emailIds
        ];
        if (links.isEmpty()) {
            return new List<DocWrapper>();
        }

        // 6) Build and return wrappers
        List<DocWrapper> wrappers = new List<DocWrapper>();
        for (ContentDocumentLink cdl : links) {
            Id versionId = cdl.ContentDocument.LatestPublishedVersionId;
            String url = '/servlet/servlet.FileDownload?file=' + versionId;
            wrappers.add(
                new DocWrapper(
                    cdl.ContentDocumentId,
                    cdl.ContentDocument.Title,
                    url
                )
            );
        }
        return wrappers;
    }
}