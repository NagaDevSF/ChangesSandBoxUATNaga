public class EmailMessageTriggerHandler {
    
    /**
     * Handle after insert events for EmailMessage
     */
    public static void handleAfterInsert(List<EmailMessage> newEmails) {
        try {
            System.debug('📧 EmailMessage Trigger: Processing ' + newEmails.size() + ' new emails');
            
            List<New_Email_Event__e> emailEvents = new List<New_Email_Event__e>();
            
            for (EmailMessage email : newEmails) {
                // Only create events for incoming emails (not sent emails)
                if (email.Incoming == true) {
                    System.debug('📧 Creating Platform Event for incoming email: ' + email.Subject);
                    
                    New_Email_Event__e emailEvent = new New_Email_Event__e(
                        Email_Id__c = email.Id,
                        Email_Subject__c = email.Subject,
                        From_Address__c = email.FromAddress,
                        Is_Incoming__c = email.Incoming
                    );
                    
                    emailEvents.add(emailEvent);
                }
            }
            
            // Publish Platform Events
            if (!emailEvents.isEmpty()) {
                System.debug('📧 Publishing ' + emailEvents.size() + ' Platform Events');
                
                List<Database.SaveResult> results = EventBus.publish(emailEvents);
                
                // Log results
                for (Integer i = 0; i < results.size(); i++) {
                    Database.SaveResult result = results[i];
                    if (result.isSuccess()) {
                        System.debug('📧 ✅ Platform Event published successfully for email: ' + emailEvents[i].Email_Subject__c);
                    } else {
                        System.debug('📧 ❌ Failed to publish Platform Event: ' + result.getErrors()[0].getMessage());
                    }
                }
            } else {
                System.debug('📧 No incoming emails to publish events for');
            }
            
        } catch (Exception e) {
            System.debug('📧 ❌ Error in EmailMessage trigger handler: ' + e.getMessage());
            System.debug('📧 Stack trace: ' + e.getStackTraceString());
        }
    }
}