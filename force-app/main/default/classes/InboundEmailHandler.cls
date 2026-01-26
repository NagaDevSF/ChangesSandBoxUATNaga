global class InboundEmailHandler implements Messaging.InboundEmailHandler { 
    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();

        // Check Automation Settings
        Automation_Settings__c settings = Automation_Settings__c.getInstance();
        if (settings == null || !settings.Activate_Automations__c) {
            System.debug('Automations disabled - exiting InboundEmailHandler');
            result.success = true; // Returning true even if automation is off to avoid bounceback
            return result;
        }

        System.debug('Apex Invoke');
        try {
            // Extract Lead ID from the subject line
            String leadIdFromSubject = extractLeadIdFromSubject(email.subject);
            System.debug('Extracted Lead ID --> ' + leadIdFromSubject);
    
            if (String.isNotBlank(leadIdFromSubject)) {
                List<Lead> leads = [SELECT Id, OwnerId FROM Lead WHERE Id = :leadIdFromSubject LIMIT 1];
    
                if (!leads.isEmpty()) {
                    Lead lead = leads[0];
                    System.debug('Lead ID found in Salesforce: ' + lead.Id);
    
                    EmailMessage em = new EmailMessage();
                    em.FromAddress = email.fromAddress;
                    em.ToAddress = (email.toAddresses != null && !email.toAddresses.isEmpty()) ? email.toAddresses[0] : null;
                    em.Incoming = true;
                    em.Lead__c = lead.Id;
    
                    em.Subject = removeLeadIdFromSubject(email.subject, leadIdFromSubject);
    
                    if (String.isNotBlank(email.plainTextBody)) {
                        em.TextBody = email.plainTextBody;
                    }
                    if (String.isNotBlank(email.htmlBody)) {
                        em.HtmlBody = email.htmlBody;
                    }
    
                    System.debug('Saving EmailMessage with Subject: ' + em.Subject);
                    insert em;
                    System.debug('EmailMessage inserted successfully. Id: ' + em.Id);
                    // Start Handle Attachments
                    System.debug('===== Starting Attachment Handling Section =====');
                    System.debug('EmailMessage Id after insert: ' + em.Id);
                    System.debug('Binary Attachments Null?: ' + (email.binaryAttachments == null));
                    System.debug('Binary Attachments Count: ' + (email.binaryAttachments != null ? email.binaryAttachments.size() : 0));
                    System.debug('Text Attachments Null?: ' + (email.textAttachments == null));
                    System.debug('Text Attachments Count: ' + (email.textAttachments != null ? email.textAttachments.size() : 0));
                   
                    if (email.binaryAttachments != null && email.binaryAttachments.size() > 0) {
                        List<Attachment> attsToInsert = new List<Attachment>();
                        for (Messaging.Inboundemail.BinaryAttachment binAtt : email.binaryAttachments) {
                            Attachment att = new Attachment();
                            att.ParentId = em.Id;
                            att.Name = binAtt.fileName;
                            att.Body = binAtt.body;
                            attsToInsert.add(att);
                            System.debug('Adding Binary Attachment: ' + binAtt.fileName);
                        }
                        insert attsToInsert;
                    }

                    if (email.textAttachments != null && email.textAttachments.size() > 0) {
                        List<Attachment> textAttsToInsert = new List<Attachment>();
                        for (Messaging.Inboundemail.TextAttachment txtAtt : email.textAttachments) {
                            Attachment att = new Attachment();
                            att.ParentId = em.Id;
                            att.Name = txtAtt.fileName;
                            att.Body = Blob.valueOf(txtAtt.body);
                            textAttsToInsert.add(att);
                            System.debug('Adding Text Attachment: ' + txtAtt.fileName);
                        }
                        insert textAttsToInsert;
                    }
                    System.debug('===== Attachment Handling Completed Successfully =====');
                    // End Attachment Handling
                }
            }
            result.success = true;
        } catch (Exception ex) {
            System.debug('Exception in InboundEmailHandler: ' + ex.getMessage());
            result.success = false;
        }
        System.debug('===== InboundEmailHandler Completed. Result: ' + result.success + ' =====');
        return result;
    }

    private String extractLeadIdFromSubject(String subject) {
        System.debug('Extracting Lead ID from subject');
        Pattern p = Pattern.compile('(00Q[a-zA-Z0-9]{12,15})$');
        Matcher m = p.matcher(subject != null ? subject.trim() : '');
        if (m.find()) {
            return m.group(1);
        }
        return null;
    }

    private String removeLeadIdFromSubject(String subject, String leadId) {
        if (String.isBlank(subject) || String.isBlank(leadId)) {
            return subject;
        }
        String cleaned = subject.trim();
        if (cleaned.endsWith(leadId)) {
            cleaned = cleaned.substring(0, cleaned.length() - leadId.length()).trim();
        }
        return cleaned;
    }
}