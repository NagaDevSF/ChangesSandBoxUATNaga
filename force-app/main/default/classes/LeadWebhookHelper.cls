public class LeadWebhookHelper {
    
    @InvocableMethod(label='Format Lead for Webhook' description='Formats Lead data for webhook payload')
    public static List<PayloadData> formatLeadData(List<InputData> leads) {
        List<PayloadData> payloads = new List<PayloadData>();
        
        for (InputData leadInput : leads) {
            PayloadData payload = new PayloadData();
            
            Map<String, Object> data = new Map<String, Object>();
            
            // Basic Information
            data.put('Id', leadInput.leadId);
            data.put('Name', leadInput.leadName);
            data.put('FirstName', leadInput.firstName);
            data.put('LastName', leadInput.lastName);
            data.put('Email', leadInput.email);
            data.put('Phone', leadInput.phone);
            data.put('MobilePhone', leadInput.mobile);
            data.put('Company', leadInput.company);
            
            // Lead Status and Source
            data.put('Status', leadInput.status);
            data.put('LeadSource', leadInput.leadSource);
            data.put('Source__c', leadInput.leadSourceDCG);
            data.put('Lead_Source_QRMCA__c', leadInput.leadSourceQRMCA);
            data.put('Main_Source__c', leadInput.mainSource);
            data.put('Type__c', leadInput.inboundType);
            
            // Pre-Deal Information
            data.put('Pre_Deal_Status__c', leadInput.preDealStatus);
            data.put('Pre_Deal_Statuses_DC__c', leadInput.preDealStatusesDC);
            
            // Financial Information
            data.put('Est_Total_Debt__c', leadInput.estimatedTotalDebt);
            data.put('Estimated_Total_Amount__c', leadInput.estimatedTotalAmount);
            data.put('Est_weekly_payment__c', leadInput.estimatedWeeklyPayment);
            data.put('Desired_Weekly_Payment__c', leadInput.desiredWeeklyPayment);
            data.put('Estimated_Current_Payment__c', leadInput.estimatedCurrentPayment);
            data.put('Payment_Frequency__c', leadInput.paymentFrequency);
            data.put('Balance__c', leadInput.balance);
            data.put('Quiz_Quote__c', leadInput.quizQuote);
            data.put('AnnualRevenue', leadInput.annualRevenue);
            
            // Debt Types
            data.put('Personal_Consumer_Debt__c', leadInput.consumerDebt);
            data.put('Medical_Debt__c', leadInput.medicalDebt);
            data.put('Tax_Debt__c', leadInput.taxDebt);
            data.put('Funding__c', leadInput.funding);
            
            // Contact Information Extended
            data.put('Email_2__c', leadInput.email2);
            data.put('Phone_2__c', leadInput.phone2);
            data.put('Phone_3__c', leadInput.phone3);
            data.put('Mobile_Backup__c', leadInput.mobileBackup);
            data.put('Time_Zone_c__c', leadInput.timeZone);
            data.put('Area_Code__c', leadInput.areaCode);
            
            // Business Information
            data.put('Business_Type__c', leadInput.businessType);
            data.put('Type_of_Business__c', leadInput.typeOfBusiness);
            data.put('Business_Start_date__c', leadInput.businessStartDate);
            data.put('EIN__c', leadInput.ein);
            data.put('NumberOfEmployees', leadInput.numberOfEmployees);
            data.put('Website', leadInput.website);
            data.put('Industry', leadInput.industry);
            
            // Assignment Information
            data.put('Sales_Office_Ref__c', leadInput.salesOfficeRef);
            data.put('Integration_Assignement__c', leadInput.integrationAssignment);
            data.put('Round_Robin_Assignment_Date__c', leadInput.roundRobinAssignmentDate);
            data.put('OwnerId', leadInput.ownerId);
            
            // Legal Information
            data.put('Litigator__c', leadInput.litigator);
            data.put('Law_suite_occured__c', leadInput.lawSuiteOccuredDate);
            data.put('Lawyer__c', leadInput.lawyer);
            
            // Notes and Messages
            data.put('QuickNotes__c', leadInput.quickNotes);
            data.put('Description', leadInput.description);
            data.put('SMS_Message__c', leadInput.smsMessage);
            data.put('SMS_Message_Name__c', leadInput.smsMessageName);
            data.put('SMS_Status__c', leadInput.smsStatus);
            data.put('Assignment_Notes__c', leadInput.assignmentNotes);
            
            // Flags and Preferences
            data.put('Spanish__c', leadInput.spanish);
            data.put('Black_Listed__c', leadInput.blackListed);
            data.put('Duplicate__c', leadInput.duplicate);
            data.put('Nurturing__c', leadInput.nurturing);
            data.put('DoNotCall', leadInput.doNotCall);
            data.put('HasOptedOutOfEmail', leadInput.hasOptedOutOfEmail);
            data.put('HasOptedOutOfFax', leadInput.hasOptedOutOfFax);
            data.put('SFMC_Sync__c', leadInput.sfmcSync);
            data.put('No_Response__c', leadInput.noResponse);
            data.put('Call_Back_Required__c', leadInput.callBackRequired);
            
            // Campaign and UTM Information
            data.put('Campaign_Brand__c', leadInput.campaignBrand);
            data.put('utm_source__c', leadInput.utmSource);
            data.put('utm_campaign__c', leadInput.utmCampaign);
            data.put('utm_medium__c', leadInput.utmMedium);
            data.put('utm_content__c', leadInput.utmContent);
            data.put('utm_term__c', leadInput.utmTerm);
            data.put('Tag__c', leadInput.tag);
            
            // Document Information
            data.put('Docs_received__c', leadInput.docsReceived);
            data.put('Docs_links__c', leadInput.docsLinks);
            data.put('Doc_Submission_Status__c', leadInput.docSubmissionStatus);
            data.put('Send_QUIZ__c', leadInput.sendQuiz);
            
            // Address Information
            data.put('Street', leadInput.street);
            data.put('City', leadInput.city);
            data.put('State', leadInput.state);
            data.put('PostalCode', leadInput.postalCode);
            data.put('Country', leadInput.country);
            
            // Additional Fields
            data.put('Number__c', leadInput.leadNumber);
            data.put('Year__c', leadInput.yearField);
            data.put('Created_Date_Time__c', leadInput.createdDateTime);
            data.put('Updated_date_ref__c', leadInput.updatedDateRef);
            data.put('Rating', leadInput.rating);
            data.put('Labels__c', leadInput.labels);
            data.put('Lead_Level__c', leadInput.leadLevel);
            data.put('External_ID__c', leadInput.externalId);
            data.put('SSN__c', leadInput.ssn);
            data.put('Gender', leadInput.gender);
            
            // Round Robin Fields
            data.put('ZAP_RR_Cherry_QRMCA__c', leadInput.zapRRCherryQRMCA);
            data.put('RR_Marketing_QRMCA__c', leadInput.rrMarketingQRMCA);
            data.put('RR_Quiz_QRMCA__c', leadInput.rrQuizQRMCA);
            
            // Lender Information
            data.put('Lender_Name__c', leadInput.lenderName);
            data.put('Lender_1__c', leadInput.lender1);
            data.put('Lender_2__c', leadInput.lender2);
            data.put('Lender_3__c', leadInput.lender3);
            
            // Payment Information
            data.put('Payments_L1__c', leadInput.paymentsL1);
            data.put('Payments_L2__c', leadInput.paymentsL2);
            data.put('Payment_3__c', leadInput.payment3);
            data.put('Frequency_L1__c', leadInput.frequencyL1);
            data.put('Frequency_L2__c', leadInput.frequencyL2);
            data.put('Frequency_L3__c', leadInput.frequencyL3);
            
            payload.jsonPayload = JSON.serialize(data);
            payloads.add(payload);
        }
        
        return payloads;
    }
    
    public class InputData {
        @InvocableVariable(label='Lead ID' required=true)
        public String leadId;
        
        @InvocableVariable(label='Lead Name')
        public String leadName;
        
        @InvocableVariable(label='First Name')
        public String firstName;
        
        @InvocableVariable(label='Last Name')
        public String lastName;
        
        @InvocableVariable(label='Email')
        public String email;
        
        @InvocableVariable(label='Phone')
        public String phone;
        
        @InvocableVariable(label='Mobile Phone')
        public String mobile;
        
        @InvocableVariable(label='Company')
        public String company;
        
        @InvocableVariable(label='Status')
        public String status;
        
        @InvocableVariable(label='Lead Source')
        public String leadSource;
        
        @InvocableVariable(label='Lead Source DCG')
        public String leadSourceDCG;
        
        @InvocableVariable(label='Lead Source QRMCA')
        public String leadSourceQRMCA;
        
        @InvocableVariable(label='Main Source')
        public String mainSource;
        
        @InvocableVariable(label='Inbound Type')
        public String inboundType;
        
        @InvocableVariable(label='Pre Deal Status')
        public String preDealStatus;
        
        @InvocableVariable(label='Pre Deal Statuses DC')
        public String preDealStatusesDC;
        
        @InvocableVariable(label='Estimated Total Debt')
        public Decimal estimatedTotalDebt;
        
        @InvocableVariable(label='Estimated Total Amount')
        public Decimal estimatedTotalAmount;
        
        @InvocableVariable(label='Estimated Weekly Payment')
        public Decimal estimatedWeeklyPayment;
        
        @InvocableVariable(label='Desired Weekly Payment')
        public Decimal desiredWeeklyPayment;
        
        @InvocableVariable(label='Estimated Current Payment')
        public Decimal estimatedCurrentPayment;
        
        @InvocableVariable(label='Payment Frequency')
        public String paymentFrequency;
        
        @InvocableVariable(label='Balance')
        public Decimal balance;
        
        @InvocableVariable(label='Quiz Quote')
        public Decimal quizQuote;
        
        @InvocableVariable(label='Annual Revenue')
        public Decimal annualRevenue;
        
        @InvocableVariable(label='Consumer Debt')
        public Boolean consumerDebt;
        
        @InvocableVariable(label='Medical Debt')
        public Boolean medicalDebt;
        
        @InvocableVariable(label='Tax Debt')
        public Boolean taxDebt;
        
        @InvocableVariable(label='Funding')
        public Boolean funding;
        
        @InvocableVariable(label='Email 2')
        public String email2;
        
        @InvocableVariable(label='Phone 2')
        public String phone2;
        
        @InvocableVariable(label='Phone 3')
        public String phone3;
        
        @InvocableVariable(label='Mobile Backup')
        public String mobileBackup;
        
        @InvocableVariable(label='Time Zone')
        public String timeZone;
        
        @InvocableVariable(label='Area Code')
        public String areaCode;
        
        @InvocableVariable(label='Business Type')
        public String businessType;
        
        @InvocableVariable(label='Type of Business')
        public String typeOfBusiness;
        
        @InvocableVariable(label='Business Start Date')
        public Date businessStartDate;
        
        @InvocableVariable(label='EIN')
        public String ein;
        
        @InvocableVariable(label='Number of Employees')
        public Integer numberOfEmployees;
        
        @InvocableVariable(label='Website')
        public String website;
        
        @InvocableVariable(label='Industry')
        public String industry;
        
        @InvocableVariable(label='Sales Office Ref')
        public String salesOfficeRef;
        
        @InvocableVariable(label='Integration Assignment')
        public String integrationAssignment;
        
        @InvocableVariable(label='Round Robin Assignment Date')
        public DateTime roundRobinAssignmentDate;
        
        @InvocableVariable(label='Owner ID')
        public String ownerId;
        
        @InvocableVariable(label='Litigator')
        public Boolean litigator;
        
        @InvocableVariable(label='Law Suite Occured Date')
        public Date lawSuiteOccuredDate;
        
        @InvocableVariable(label='Lawyer')
        public String lawyer;
        
        @InvocableVariable(label='Quick Notes')
        public String quickNotes;
        
        @InvocableVariable(label='Description')
        public String description;
        
        @InvocableVariable(label='SMS Message')
        public String smsMessage;
        
        @InvocableVariable(label='SMS Message Name')
        public String smsMessageName;
        
        @InvocableVariable(label='SMS Status')
        public String smsStatus;
        
        @InvocableVariable(label='Assignment Notes')
        public String assignmentNotes;
        
        @InvocableVariable(label='Spanish')
        public Boolean spanish;
        
        @InvocableVariable(label='Black Listed')
        public Boolean blackListed;
        
        @InvocableVariable(label='Duplicate')
        public Boolean duplicate;
        
        @InvocableVariable(label='Nurturing')
        public Boolean nurturing;
        
        @InvocableVariable(label='Do Not Call')
        public Boolean doNotCall;
        
        @InvocableVariable(label='Has Opted Out Of Email')
        public Boolean hasOptedOutOfEmail;
        
        @InvocableVariable(label='Has Opted Out Of Fax')
        public Boolean hasOptedOutOfFax;
        
        @InvocableVariable(label='SFMC Sync')
        public Boolean sfmcSync;
        
        @InvocableVariable(label='No Response')
        public Boolean noResponse;
        
        @InvocableVariable(label='Call Back Required')
        public Boolean callBackRequired;
        
        @InvocableVariable(label='Campaign Brand')
        public String campaignBrand;
        
        @InvocableVariable(label='UTM Source')
        public String utmSource;
        
        @InvocableVariable(label='UTM Campaign')
        public String utmCampaign;
        
        @InvocableVariable(label='UTM Medium')
        public String utmMedium;
        
        @InvocableVariable(label='UTM Content')
        public String utmContent;
        
        @InvocableVariable(label='UTM Term')
        public String utmTerm;
        
        @InvocableVariable(label='Tag')
        public String tag;
        
        @InvocableVariable(label='Docs Received')
        public Boolean docsReceived;
        
        @InvocableVariable(label='Docs Links')
        public String docsLinks;
        
        @InvocableVariable(label='Doc Submission Status')
        public String docSubmissionStatus;
        
        @InvocableVariable(label='Send Quiz')
        public Boolean sendQuiz;
        
        @InvocableVariable(label='Street')
        public String street;
        
        @InvocableVariable(label='City')
        public String city;
        
        @InvocableVariable(label='State')
        public String state;
        
        @InvocableVariable(label='Postal Code')
        public String postalCode;
        
        @InvocableVariable(label='Country')
        public String country;
        
        @InvocableVariable(label='Lead Number')
        public String leadNumber;
        
        @InvocableVariable(label='Year Field')
        public Decimal yearField;
        
        @InvocableVariable(label='Created Date Time')
        public DateTime createdDateTime;
        
        @InvocableVariable(label='Updated Date Ref')
        public DateTime updatedDateRef;
        
        @InvocableVariable(label='Rating')
        public String rating;
        
        @InvocableVariable(label='Labels')
        public String labels;
        
        @InvocableVariable(label='Lead Level')
        public String leadLevel;
        
        @InvocableVariable(label='External ID')
        public String externalId;
        
        @InvocableVariable(label='SSN')
        public String ssn;
        
        @InvocableVariable(label='Gender')
        public String gender;
        
        @InvocableVariable(label='ZAP RR Cherry QRMCA')
        public Decimal zapRRCherryQRMCA;
        
        @InvocableVariable(label='RR Marketing QRMCA')
        public Decimal rrMarketingQRMCA;
        
        @InvocableVariable(label='RR Quiz QRMCA')
        public Decimal rrQuizQRMCA;
        
        @InvocableVariable(label='Lender Name')
        public String lenderName;
        
        @InvocableVariable(label='Lender 1')
        public String lender1;
        
        @InvocableVariable(label='Lender 2')
        public String lender2;
        
        @InvocableVariable(label='Lender 3')
        public String lender3;
        
        @InvocableVariable(label='Payments L1')
        public Decimal paymentsL1;
        
        @InvocableVariable(label='Payments L2')
        public Decimal paymentsL2;
        
        @InvocableVariable(label='Payment 3')
        public Decimal payment3;
        
        @InvocableVariable(label='Frequency L1')
        public String frequencyL1;
        
        @InvocableVariable(label='Frequency L2')
        public String frequencyL2;
        
        @InvocableVariable(label='Frequency L3')
        public String frequencyL3;
    }
    
    public class PayloadData {
        @InvocableVariable(label='JSON Payload')
        public String jsonPayload;
    }
}