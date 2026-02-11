public class ConvosoFlowIntegration {
    
    @InvocableMethod(label='Send Lead to Convoso' description='Sends a lead to Convoso dialer with configurable options')
    public static List<ConvosoResponse> sendLeadToConvoso(List<ConvosoRequest> requests) {
        
        List<ConvosoResponse> responses = new List<ConvosoResponse>();
        
        for (ConvosoRequest request : requests) {
            ConvosoResponse response = new ConvosoResponse();
            
            try {
                // Validate required fields
                if (String.isBlank(request.phone_number)) {
                    response.isSuccess = false;
                    response.message = 'phone_number is required';
                    responses.add(response);
                    continue;
                }
                
                if (String.isBlank(request.list_id)) {
                    response.isSuccess = false;
                    response.message = 'list_id is required';
                    responses.add(response);
                    continue;
                }
                
                // Serialize the request object and call future method
                String requestJson = JSON.serialize(request);
                sendLeadToConvosoFuture(requestJson);
                
                // Return success immediately (actual API call happens asynchronously)
                response.isSuccess = true;
                response.statusCode = 202; // 202 = Accepted (processing asynchronously)
                response.message = 'Lead queued for submission to Convoso List ID: ' + request.list_id;
                response.responseBody = 'Request submitted asynchronously';
                
            } catch (Exception e) {
                response.isSuccess = false;
                response.message = 'Exception: ' + e.getMessage();
                response.statusCode = 0;
            }
            
            responses.add(response);
        }
        
        return responses;
    }
    
    @future(callout=true)
    public static void sendLeadToConvosoFuture(String requestJson) {
        try {
            // Deserialize the request
            ConvosoRequest request = (ConvosoRequest) JSON.deserialize(requestJson, ConvosoRequest.class);
            
            // Build the HTTP request
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://api.convoso.com/v1/leads/insert');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setTimeout(30000);
            
            // Build the request body with auth token
            String body = 'auth_token=h389s0s523gcnhod47y83qouxwe6p1dx';
            body += '&list_id=' + EncodingUtil.urlEncode(request.list_id != null ? request.list_id : '0', 'UTF-8');
            
            // Add required phone number
            body += '&phone_number=' + EncodingUtil.urlEncode(request.phone_number, 'UTF-8');
            
            // Add configuration fields with defaults if blank
            body += '&check_dup=' + EncodingUtil.urlEncode(String.isNotBlank(request.check_dup) ? request.check_dup : '0', 'UTF-8');
            body += '&check_dup_archive=' + EncodingUtil.urlEncode(String.isNotBlank(request.check_dup_archive) ? request.check_dup_archive : '0', 'UTF-8');
            body += '&check_dnc=' + EncodingUtil.urlEncode(String.isNotBlank(request.check_dnc) ? request.check_dnc : '0', 'UTF-8');
            body += '&check_wireless=' + EncodingUtil.urlEncode(String.isNotBlank(request.check_wireless) ? request.check_wireless : '0', 'UTF-8');
            body += '&hopper=' + EncodingUtil.urlEncode(String.isNotBlank(request.hopper) ? request.hopper : '1', 'UTF-8');
            body += '&hopper_priority=' + EncodingUtil.urlEncode(String.isNotBlank(request.hopper_priority) ? request.hopper_priority : '99', 'UTF-8');
            body += '&hopper_expires_in=' + EncodingUtil.urlEncode(String.isNotBlank(request.hopper_expires_in) ? request.hopper_expires_in : '0', 'UTF-8');
            body += '&update_if_found=' + EncodingUtil.urlEncode(String.isNotBlank(request.update_if_found) ? request.update_if_found : '0', 'UTF-8');
            body += '&update_order_by_last_called_time=' + EncodingUtil.urlEncode(String.isNotBlank(request.update_order_by_last_called_time) ? request.update_order_by_last_called_time : 'DESC', 'UTF-8');
            body += '&lead_id=' + EncodingUtil.urlEncode(String.isNotBlank(request.lead_id) ? request.lead_id : '0', 'UTF-8');
            body += '&phone_code=' + EncodingUtil.urlEncode(String.isNotBlank(request.phone_code) ? request.phone_code : '1', 'UTF-8');
            body += '&filter_phone_code=' + EncodingUtil.urlEncode(String.isNotBlank(request.filter_phone_code) ? request.filter_phone_code : '0', 'UTF-8');
            
            // Add optional fields only if they have values
            if (String.isNotBlank(request.inbound_type)) {
                body += '&inbound_type=' + EncodingUtil.urlEncode(request.inbound_type, 'UTF-8');
            }
            if (String.isNotBlank(request.blueinkdigital_token)) {
                body += '&blueinkdigital_token=' + EncodingUtil.urlEncode(request.blueinkdigital_token, 'UTF-8');
            }
            if (String.isNotBlank(request.reject_by_carrier_type)) {
                body += '&reject_by_carrier_type=' + EncodingUtil.urlEncode(request.reject_by_carrier_type, 'UTF-8');
            }
            if (String.isNotBlank(request.created_by)) {
                body += '&created_by=' + EncodingUtil.urlEncode(request.created_by, 'UTF-8');
            }
            if (String.isNotBlank(request.email)) {
                body += '&email=' + EncodingUtil.urlEncode(request.email, 'UTF-8');
            }
            if (String.isNotBlank(request.last_modified_by)) {
                body += '&last_modified_by=' + EncodingUtil.urlEncode(request.last_modified_by, 'UTF-8');
            }
            if (String.isNotBlank(request.owner_id)) {
                body += '&owner_id=' + EncodingUtil.urlEncode(request.owner_id, 'UTF-8');
            }
            if (String.isNotBlank(request.first_name)) {
                body += '&first_name=' + EncodingUtil.urlEncode(request.first_name, 'UTF-8');
            }
            if (String.isNotBlank(request.last_name)) {
                body += '&last_name=' + EncodingUtil.urlEncode(request.last_name, 'UTF-8');
            }
            if (String.isNotBlank(request.alt_phone_1)) {
                body += '&alt_phone_1=' + EncodingUtil.urlEncode(request.alt_phone_1, 'UTF-8');
            }
            if (String.isNotBlank(request.alt_phone_2)) {
                body += '&alt_phone_2=' + EncodingUtil.urlEncode(request.alt_phone_2, 'UTF-8');
            }
            if (String.isNotBlank(request.address1)) {
                body += '&address1=' + EncodingUtil.urlEncode(request.address1, 'UTF-8');
            }
            if (String.isNotBlank(request.address2)) {
                body += '&address2=' + EncodingUtil.urlEncode(request.address2, 'UTF-8');
            }
            if (String.isNotBlank(request.city)) {
                body += '&city=' + EncodingUtil.urlEncode(request.city, 'UTF-8');
            }
            if (String.isNotBlank(request.state)) {
                body += '&state=' + EncodingUtil.urlEncode(request.state, 'UTF-8');
            }
            if (String.isNotBlank(request.province)) {
                body += '&province=' + EncodingUtil.urlEncode(request.province, 'UTF-8');
            }
            if (String.isNotBlank(request.postal_code)) {
                body += '&postal_code=' + EncodingUtil.urlEncode(request.postal_code, 'UTF-8');
            }
            if (String.isNotBlank(request.country)) {
                body += '&country=' + EncodingUtil.urlEncode(request.country, 'UTF-8');
            }
            if (String.isNotBlank(request.gender)) {
                body += '&gender=' + EncodingUtil.urlEncode(request.gender, 'UTF-8');
            }
            if (String.isNotBlank(request.date_of_birth)) {
                body += '&date_of_birth=' + EncodingUtil.urlEncode(request.date_of_birth, 'UTF-8');
            }
            if (String.isNotBlank(request.notes)) {
                body += '&notes=' + EncodingUtil.urlEncode(request.notes, 'UTF-8');
            }
            if (String.isNotBlank(request.salesforceownerid)) {
                body += '&salesforceownerid=' + EncodingUtil.urlEncode(request.salesforceownerid, 'UTF-8');
            }
            
            // Add the new fields: consumer_debt, lead_source, and company
            if (String.isNotBlank(request.consumer_debt)) {
                body += '&consumer_debt=' + EncodingUtil.urlEncode(request.consumer_debt, 'UTF-8');
            }
            if (String.isNotBlank(request.lead_source)) {
                body += '&lead_source=' + EncodingUtil.urlEncode(request.lead_source, 'UTF-8');
            }
            if (String.isNotBlank(request.company)) {
                body += '&company=' + EncodingUtil.urlEncode(request.company, 'UTF-8');
            }
            
            req.setBody(body);
            
            // Send the request
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            // Log the response for debugging
            System.debug('Convoso API Response Code: ' + res.getStatusCode());
            System.debug('Convoso API Response Body: ' + res.getBody());
            System.debug('Convoso API Request Body: ' + body);
            
        } catch (Exception e) {
            System.debug('Exception in sendLeadToConvosoFuture: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
        }
    }
    
    // Input wrapper class with all Convoso API fields
    public class ConvosoRequest {
        // Required fields
        @InvocableVariable(label='list_id' description='Convoso List ID where lead will be added' required=true)
        public String list_id;
        
        @InvocableVariable(label='phone_number' description='Lead phone number' required=true)
        public String phone_number;
        
        // Configuration fields
        @InvocableVariable(label='check_dup' description='Check for duplicates (0 or 1)')
        public String check_dup;
        
        @InvocableVariable(label='check_dup_archive' description='Check for duplicates in archive (0 or 1)')
        public String check_dup_archive;
        
        @InvocableVariable(label='check_dnc' description='Check Do Not Call list (0 or 1)')
        public String check_dnc;
        
        @InvocableVariable(label='check_wireless' description='Check if wireless number (0 or 1)')
        public String check_wireless;
        
        @InvocableVariable(label='hopper' description='Add to hopper (0 or 1)')
        public String hopper;
        
        @InvocableVariable(label='hopper_priority' description='Priority in hopper (1-99)')
        public String hopper_priority;
        
        @InvocableVariable(label='hopper_expires_in' description='Hopper expiration time in minutes')
        public String hopper_expires_in;
        
        @InvocableVariable(label='update_if_found' description='Update if lead found (0 or 1)')
        public String update_if_found;
        
        @InvocableVariable(label='update_order_by_last_called_time' description='Update order (ASC or DESC)')
        public String update_order_by_last_called_time;
        
        @InvocableVariable(label='inbound_type' description='Inbound type for the lead')
        public String inbound_type;
        
        @InvocableVariable(label='blueinkdigital_token' description='BlueInkDigital token')
        public String blueinkdigital_token;
        
        @InvocableVariable(label='reject_by_carrier_type' description='Reject by carrier type')
        public String reject_by_carrier_type;
        
        @InvocableVariable(label='filter_phone_code' description='Filter by phone code')
        public String filter_phone_code;
        
        @InvocableVariable(label='lead_id' description='Lead ID (0 for new leads)')
        public String lead_id;
        
        @InvocableVariable(label='phone_code' description='Country phone code (1 for US)')
        public String phone_code;
        
        @InvocableVariable(label='created_by' description='Created by user')
        public String created_by;
        
        @InvocableVariable(label='email' description='Lead email address')
        public String email;
        
        @InvocableVariable(label='last_modified_by' description='Last modified by user')
        public String last_modified_by;
        
        @InvocableVariable(label='owner_id' description='Owner ID')
        public String owner_id;
        
        @InvocableVariable(label='first_name' description='Lead first name')
        public String first_name;
        
        @InvocableVariable(label='last_name' description='Lead last name')
        public String last_name;
        
        @InvocableVariable(label='alt_phone_1' description='Alternative phone number 1')
        public String alt_phone_1;
        
        @InvocableVariable(label='alt_phone_2' description='Alternative phone number 2')
        public String alt_phone_2;
        
        @InvocableVariable(label='address1' description='Address line 1')
        public String address1;
        
        @InvocableVariable(label='address2' description='Address line 2')
        public String address2;
        
        @InvocableVariable(label='city' description='City')
        public String city;
        
        @InvocableVariable(label='state' description='State')
        public String state;
        
        @InvocableVariable(label='province' description='Province')
        public String province;
        
        @InvocableVariable(label='postal_code' description='Postal/ZIP code')
        public String postal_code;
        
        @InvocableVariable(label='country' description='Country')
        public String country;
        
        @InvocableVariable(label='gender' description='Gender')
        public String gender;
        
        @InvocableVariable(label='date_of_birth' description='Date of birth')
        public String date_of_birth;
        
        @InvocableVariable(label='notes' description='Additional notes')
        public String notes;
        
        @InvocableVariable(label='salesforceownerid' description='Salesforce Owner ID')
        public String salesforceownerid;
        
        // New fields added
        @InvocableVariable(label='consumer_debt' description='Consumer debt information')
        public String consumer_debt;
        
        @InvocableVariable(label='lead_source' description='Source of the lead')
        public String lead_source;
        
        @InvocableVariable(label='company' description='Company name')
        public String company;
    }
    
    // Output wrapper class
    public class ConvosoResponse {
        @InvocableVariable(label='Success')
        public Boolean isSuccess;
        
        @InvocableVariable(label='Status Code')
        public Integer statusCode;
        
        @InvocableVariable(label='Response Message')
        public String message;
        
        @InvocableVariable(label='Response Body')
        public String responseBody;
    }
}