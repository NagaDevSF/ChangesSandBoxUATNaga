@RestResource(urlMapping='/TwilioSMS/*')
global class TwilioSMSHandler {

    @HttpPost
    global static void receiveInboundSMS() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        // Check custom setting
        Automation_Settings__c settings = Automation_Settings__c.getInstance();
        if (settings == null || settings.Activate_Automations__c == false) {
            System.debug('Automation settings disabled — stopping execution.');
            
            // Respond to Twilio to prevent error on their end
            res.responseBody = Blob.valueOf('<Response></Response>');
            res.statusCode = 200;
            res.addHeader('Content-Type', 'text/xml');
            return;
        }

        Map<String, String> params = req.params;
        System.debug('Received Parameters: ' + params);

        String fromNumber = params.get('From');
        String messageBody = params.get('Body');

        System.debug('From Number: ' + fromNumber);
        System.debug('Message Body: ' + messageBody);

        if (String.isNotBlank(messageBody)) {
            String command = messageBody.trim().toUpperCase();
            System.debug('Normalized Command: ' + command);

            Boolean shouldUpdate = false;
            Boolean setDoNotCall = false;

            // Interpret SMS command
            if (command == 'STOP') {
                shouldUpdate = true;
                setDoNotCall = true;
            } else{
                shouldUpdate = true;
                setDoNotCall = false;
            } 
            // Proceed only if valid update and number provided
            if (shouldUpdate && String.isNotBlank(fromNumber)) {
                String cleanedInput = cleanPhone(fromNumber);
                System.debug('Clean From Number: ' + cleanedInput);

                if (cleanedInput.length() < 10) {
                    System.debug('Cleaned number too short: ' + cleanedInput);
                } else {
                    // Extract last 10 and 7 digits
                    String last10 = cleanedInput.substring(cleanedInput.length() - 10);
                    System.debug('Cleaned 10 digit :' + last10);
                    String last7 = cleanedInput.substring(cleanedInput.length() - 7);
                    

                    // Format last 7 digits in two styles
                    String formatPlain = last7;
                    String formatDashed = last7.substring(0, 3) + '-' + last7.substring(3);
                    System.debug('Cleaned 7 digit: ' + formatDashed);

                    // Query potential matches using LIKE
                    List<Lead> potentialLeads = [
                        SELECT Id, Phone, MobilePhone, DoNotCall
                        FROM Lead
                        WHERE
                            Phone LIKE :('%' + formatPlain + '%') OR
                            Phone LIKE :('%' + formatDashed + '%') OR
                            MobilePhone LIKE :('%' + formatPlain + '%') OR
                            MobilePhone LIKE :('%' + formatDashed + '%')
                    ];

                    System.debug('Potential Leads from LIKE query: ' + potentialLeads.size());

                    // Unique leads to update
                    Set<Id> matchedLeadIds = new Set<Id>();
                    List<Lead> leadsToUpdate = new List<Lead>();

                    for (Lead l : potentialLeads) {
                        String cleanedPhone = cleanPhone(l.Phone);
                        String cleanedMobile = cleanPhone(l.MobilePhone);

                        Boolean isMatch = cleanedPhone.endsWith(last10) || cleanedMobile.endsWith(last10);

                        if (isMatch && !matchedLeadIds.contains(l.Id)) {
                            if (setDoNotCall != l.DoNotCall) {
                                System.debug('Lead Phone Match : ' + cleanedPhone);
								System.debug('Lead MobilePhone Match : ' + cleanedMobile);
                                l.DoNotCall = setDoNotCall;
                                matchedLeadIds.add(l.Id);
                                leadsToUpdate.add(l);
                            }
                        }
                    }

                    // Perform update if needed
                    if (!leadsToUpdate.isEmpty()) {
                        try {
                            update leadsToUpdate;
                            System.debug('Updated ' + leadsToUpdate.size() + ' lead(s).');
                        } catch (DmlException e) {
                            System.debug('Failed to update leads: ' + e.getMessage());
                        }
                    } else {
                        System.debug('No leads matched by full 10-digit logic.');
                    }
                }
            }
        }

        // Always respond to Twilio with empty <Response>
        res.responseBody = Blob.valueOf('<Response></Response>');
        res.statusCode = 200;
        res.addHeader('Content-Type', 'text/xml');
    }

    // Helper to clean non-digit characters from phone number
    private static String cleanPhone(String phone) {
        if (phone == null) return '';
        return phone.replaceAll('[^0-9]', '');
    }
}