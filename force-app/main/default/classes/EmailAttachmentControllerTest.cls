// File: force-app/main/default/classes/EmailAttachmentControllerTest.cls
@IsTest
private class EmailAttachmentControllerTest {
    
    @IsTest static void testLead_NoTasks() {
        Lead lead = new Lead(LastName='NoTasks', Company='TestCo');
        insert lead;
        
        Test.startTest();
          List<EmailAttachmentController.DocWrapper> docs =
            EmailAttachmentController.getEmailAttachments(lead.Id);
        Test.stopTest();
        
        System.assertEquals(0, docs.size(),
            'Lead with no email-type tasks should return empty.');
    }
    
    @IsTest static void testLead_TasksNoEmails() {
        Lead lead = new Lead(LastName='TasksNoEmails', Company='TestCo');
        insert lead;
        
        insert new Task(
            WhoId   = lead.Id,
            Subject = 'Email Task Only',
            Type    = 'Email',
            Status  = 'Completed'
        );
        
        Test.startTest();
          List<EmailAttachmentController.DocWrapper> docs =
            EmailAttachmentController.getEmailAttachments(lead.Id);
        Test.stopTest();
        
        System.assertEquals(0, docs.size(),
            'Lead with Email task but no EmailMessage should return empty.');
    }
    
    @IsTest static void testCase_EmailsNoAttachments() {
        Case c = new Case(Subject='CaseNoAttach');
        insert c;
        
        insert new Task(
            WhatId  = c.Id,
            Subject = 'Email Task',
            Type    = 'Email',
            Status  = 'Completed'
        );
        
        insert new EmailMessage(
            RelatedToId = c.Id,
            ActivityId  = [SELECT Id FROM Task WHERE WhatId = :c.Id AND Type = 'Email' LIMIT 1].Id,
            Status      = '3',
            FromAddress = 'tester@org.com',
            FromName    = 'Tester',
            Subject     = 'No attach',
            HtmlBody    = '<p>none</p>'
        );
        
        Test.startTest();
          List<EmailAttachmentController.DocWrapper> docs =
            EmailAttachmentController.getEmailAttachments(c.Id);
        Test.stopTest();
        
        System.assertEquals(0, docs.size(),
            'Case with EmailMessage but no attachments linked should return empty.');
    }
    
    @IsTest static void testCase_EmailsWithAttachments() {
        Case c = new Case(Subject='CaseWithAttach');
        insert c;
        
        Task t = new Task(
            WhatId  = c.Id,
            Subject = 'Email Task',
            Type    = 'Email',
            Status  = 'Completed'
        );
        insert t;
        
        EmailMessage em = new EmailMessage(
            RelatedToId = c.Id,
            ActivityId  = t.Id,
            Status      = '3',
            FromAddress = 'tester@org.com',
            FromName    = 'Tester',
            Subject     = 'Has attach',
            HtmlBody    = '<p>see file</p>'
        );
        insert em;
        
        ContentVersion cv = new ContentVersion(
            Title        = 'Demo.txt',
            PathOnClient = 'Demo.txt',
            VersionData  = Blob.valueOf('hello')
        );
        insert cv;
        
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        insert new ContentDocumentLink(
            LinkedEntityId    = em.Id,
            ContentDocumentId = cv.ContentDocumentId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );

        Test.startTest();
          List<EmailAttachmentController.DocWrapper> docs =
            EmailAttachmentController.getEmailAttachments(c.Id);
        Test.stopTest();
        
        System.assertEquals(1, docs.size(), 'Should return one document');
        System.assertEquals(cv.ContentDocumentId, docs[0].docId,
            'docId should match linked document');
        System.assertEquals('Demo.txt', docs[0].title,
            'title should match ContentVersion');
      //  System.assert(docs[0].downloadUrl.endsWith(cv.LatestPublishedVersionId),
         //   'downloadUrl should reference the version Id');
    }
}