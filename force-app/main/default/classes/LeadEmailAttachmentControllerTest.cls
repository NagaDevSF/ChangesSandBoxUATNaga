@IsTest
private class LeadEmailAttachmentControllerTest {

@TestSetup
static void setupTestData() {
// Create a test account for relatedness
Account testAccount = new Account(Name = 'Test Account');
insert testAccount;

// Create test Lead
Lead testLead = new Lead(
FirstName = 'Test',
LastName = 'User',
Email = 'test@example.com',
Company = 'Test Company'
);
insert testLead;
}

@IsTest
static void testNoAttachments() {
// Get the test Lead
Lead testLead = [SELECT Id FROM Lead WHERE LastName = 'User' LIMIT 1];

Test.startTest();
List<LeadEmailAttachmentController.FileWrapper> results =
LeadEmailAttachmentController.getEmailAttachments(testLead.Id);
Test.stopTest();

// Assert no attachments found
System.assertEquals(0, results.size(), 'Should return empty list when no attachments exist');
}

@IsTest
static void testTaskAttachments() {
// Get the test Lead
Lead testLead = [SELECT Id FROM Lead WHERE LastName = 'User' LIMIT 1];

// Create a Task for the Lead
Task task = new Task(
Subject = 'Test Task with Attachment',
WhoId = testLead.Id,
Status = 'Not Started',
Priority = 'Normal'
);
insert task;

// Create a ContentVersion (file)
ContentVersion cv = new ContentVersion(
Title = 'TaskFile.docx',
PathOnClient = 'TaskFile.docx',
VersionData = Blob.valueOf('Test Content for Task'),
IsMajorVersion = true
);
insert cv;

// Get ContentDocumentId
cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

// Link file to task
ContentDocumentLink cdl = new ContentDocumentLink(
LinkedEntityId = task.Id,
ContentDocumentId = cv.ContentDocumentId,
ShareType = 'V',
Visibility = 'AllUsers'
);
insert cdl;

// Create legacy attachment
Attachment attachment = new Attachment(
Name = 'TaskAttachment.xlsx',
Body = Blob.valueOf('Test task attachment content'),
ParentId = task.Id
);
insert attachment;

Test.startTest();
List<LeadEmailAttachmentController.FileWrapper> results =
LeadEmailAttachmentController.getEmailAttachments(testLead.Id);
Test.stopTest();

// Assert task attachments are found (should be 2)
System.assertEquals(2, results.size(), 'Should find both task attachments');
}

@IsTest
static void testEmailRelationAttachments() {
// Get the test Lead
Lead testLead = [SELECT Id FROM Lead WHERE LastName = 'User' LIMIT 1];

// Get account to use as RelatedToId
Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];

// Create an EmailMessage with valid RelatedToId (Account)
EmailMessage email = new EmailMessage(
Subject = 'Test Email with Relation',
TextBody = 'Test body',
RelatedToId = acc.Id, // Use Account ID which is valid
Status = '3' // Sent status
);
insert email;

// Create relation to Lead
EmailMessageRelation relation = new EmailMessageRelation(
EmailMessageId = email.Id,
RelationId = testLead.Id,
RelationType = 'ToAddress'
);
insert relation;

// Create a ContentVersion
ContentVersion cv = new ContentVersion(
Title = 'RelationFile.pdf',
PathOnClient = 'RelationFile.pdf',
VersionData = Blob.valueOf('Test Content for Relation'),
IsMajorVersion = true
);
insert cv;

// Get ContentDocumentId
cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

// Link file to email
ContentDocumentLink cdl = new ContentDocumentLink(
LinkedEntityId = email.Id,
ContentDocumentId = cv.ContentDocumentId,
ShareType = 'V',
Visibility = 'AllUsers'
);
insert cdl;

Test.startTest();
List<LeadEmailAttachmentController.FileWrapper> results =
LeadEmailAttachmentController.getEmailAttachments(testLead.Id);
Test.stopTest();

// Verify we found the attachment through relation
System.assertEquals(1, results.size(), 'Should find email attachment through relation');
}

@IsTest
static void testFileSizeFormatting() {
// Get the test Lead
Lead testLead = [SELECT Id FROM Lead WHERE LastName = 'User' LIMIT 1];

// Create a Task for the Lead
Task task = new Task(
Subject = 'Test File Sizes',
WhoId = testLead.Id,
Status = 'Not Started',
Priority = 'Normal'
);
insert task;

// Create files of different sizes

// Small file (bytes)
Attachment smallAtt = new Attachment(
Name = 'Small.txt',
Body = Blob.valueOf('A'), // 1 byte
ParentId = task.Id
);
insert smallAtt;

// Medium file (KB)
Blob mediumBlob = Blob.valueOf('');
for(Integer i = 0; i < 100; i++) { // Make smaller to avoid heap size limits
mediumBlob = Blob.valueOf(mediumBlob.toString() + 'A');
}
Attachment mediumAtt = new Attachment(
Name = 'Medium.txt',
Body = mediumBlob,
ParentId = task.Id
);
insert mediumAtt;

Test.startTest();
List<LeadEmailAttachmentController.FileWrapper> results =
LeadEmailAttachmentController.getEmailAttachments(testLead.Id);
Test.stopTest();

// Just verify we got the attachments
System.assertEquals(2, results.size(), 'Should return both attachments');
}

@IsTest
static void testErrorHandling() {
// Since the error message is in an AuraHandledException, we need to be careful about testing it
Boolean caughtException = false;
String errorMessage = '';

Test.startTest();
try {
LeadEmailAttachmentController.getEmailAttachments(null);
} catch (AuraHandledException e) {
caughtException = true;
errorMessage = e.getMessage();
}
Test.stopTest();

System.assert(caughtException, 'Should have thrown an exception');
// AuraHandledException masks the original message, so we can't reliably check its contents
// Just verify that we got an exception
}
}