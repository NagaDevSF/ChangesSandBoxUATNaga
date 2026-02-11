public with sharing class LeadEmailAttachmentController {
public class FileWrapper {
@AuraEnabled public Id recordId;
@AuraEnabled public String title;
@AuraEnabled public String downloadUrl;
@AuraEnabled public String fileType;
@AuraEnabled public String fileSize;
@AuraEnabled public Datetime createdDate;
@AuraEnabled public String source;

public FileWrapper(Id recordId, String title, String downloadUrl, String fileType, String fileSize, Datetime createdDate, String source) {
this.recordId = recordId;
this.title = title;
this.downloadUrl = downloadUrl;
this.fileType = fileType;
this.fileSize = fileSize;
this.createdDate = createdDate;
this.source = source;
}
}

@AuraEnabled(cacheable=true)
public static List<FileWrapper> getEmailAttachments(Id leadId) {
try {
if (leadId == null) {
throw new AuraHandledException('Lead ID is required');
}

// Collect all related entity IDs in a single list
Set<Id> entityIds = new Set<Id>();
Map<Id, String> entitySources = new Map<Id, String>();

// Use relationship queries to minimize SOQL calls
// Get emails related to the lead
for (EmailMessage em : [SELECT Id, Subject
FROM EmailMessage
WHERE RelatedToId = :leadId]) {
entityIds.add(em.Id);
entitySources.put(em.Id, 'Email: ' + (em.Subject.length() > 25 ? em.Subject.substring(0, 22) + '...' : em.Subject));
}

// Get email relations where Lead is in To/CC
for (EmailMessageRelation rel : [SELECT EmailMessageId, EmailMessage.Subject
FROM EmailMessageRelation
WHERE RelationId = :leadId
AND RelationType != 'FromAddress']) {
entityIds.add(rel.EmailMessageId);
entitySources.put(rel.EmailMessageId, 'Email: ' + (rel.EmailMessage.Subject.length() > 25 ? rel.EmailMessage.Subject.substring(0, 22) + '...' : rel.EmailMessage.Subject));
}

// Get tasks related to the lead
for (Task t : [SELECT Id, Subject
FROM Task
WHERE WhoId = :leadId]) {
entityIds.add(t.Id);
entitySources.put(t.Id, 'Task: ' + (t.Subject.length() > 25 ? t.Subject.substring(0, 22) + '...' : t.Subject));
}

if (entityIds.isEmpty()) {
return new List<FileWrapper>();
}

List<FileWrapper> results = new List<FileWrapper>();

// Get ContentDocumentLinks for modern files
for (ContentDocumentLink cdl : [SELECT ContentDocumentId, LinkedEntityId,
ContentDocument.Title,
ContentDocument.FileType,
ContentDocument.ContentSize,
ContentDocument.CreatedDate,
ContentDocument.LatestPublishedVersionId
FROM ContentDocumentLink
WHERE LinkedEntityId IN :entityIds]) {
String fileSize = formatFileSize(cdl.ContentDocument.ContentSize);
// Use direct URL format instead of getSalesforceBaseUrl
String downloadUrl = '/sfc/servlet.shepherd/version/download/' +
cdl.ContentDocument.LatestPublishedVersionId;

String source = entitySources.get(cdl.LinkedEntityId);

results.add(new FileWrapper(
cdl.ContentDocumentId,
cdl.ContentDocument.Title,
downloadUrl,
cdl.ContentDocument.FileType,
fileSize,
cdl.ContentDocument.CreatedDate,
source
));
}

// Get legacy Attachment records
for (Attachment att : [SELECT Id, Name, ContentType, BodyLength, CreatedDate, ParentId
FROM Attachment
WHERE ParentId IN :entityIds]) {
String fileSize = formatFileSize(att.BodyLength);
String fileType = att.ContentType;
// Use direct URL format instead of getSalesforceBaseUrl
String downloadUrl = '/servlet/servlet.FileDownload?file=' + att.Id;

String source = entitySources.get(att.ParentId);

results.add(new FileWrapper(
att.Id,
att.Name,
downloadUrl,
fileType,
fileSize,
att.CreatedDate,
source
));
}

return results;
} catch (Exception e) {
throw new AuraHandledException('Error retrieving attachments: ' + e.getMessage());
}
}

private static String formatFileSize(Decimal sizeInBytes) {
if (sizeInBytes < 1024) {
return sizeInBytes + ' B';
} else if (sizeInBytes < 1048576) {
return (sizeInBytes / 1024).setScale(1) + ' KB';
} else {
return (sizeInBytes / 1048576).setScale(1) + ' MB';
}
}
}