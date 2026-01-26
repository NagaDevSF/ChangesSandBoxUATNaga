/**
 * AnswerForce Phone Lookup REST API
 * Endpoint: /services/apexrest/AnswerForcePhoneLookup
 *
 * Usage: GET /services/apexrest/AnswerForcePhoneLookup?phone=4047719726
 *
 * Returns: Contact name/email and Case Manager name/email/phone
 *
 * Updated: Searches all Contact phone fields including Phone_2__c, Phone_3__c, Fax
 * Priority: Opportunity.Phone__c → Contact (Phone, Phone_2__c, Phone_3__c, MobilePhone, HomePhone, Fax)
 */
@RestResource(urlMapping='/AnswerForcePhoneLookup/*')
global with sharing class AnswerForcePhoneLookupAPI {

    // Active opportunity stages
    private static final Set<String> ACTIVE_STAGES = new Set<String>{
        'Waiting on Docs',
        'Approved/Ready to close',
        'Contract Sent',
        'Enrolled',
        'Submitted to UW',
        'Contract Signed',
        'NSF',
        'Build Plan',
        'Reassigned',
        'Qualified'
    };

    /**
     * GET endpoint to lookup case manager by phone number
     * @return LookupResponse wrapper with contact and case manager data
     */
    @HttpGet
    global static LookupResponse lookupByPhone() {
        LookupResponse response = new LookupResponse();

        try {
            // Always fetch all active case managers
            response.allCaseManagers = getAllActiveCaseManagers();
            // Get phone number from query parameters
            RestRequest req = RestContext.request;
            String phoneNumber = req.params.get('phone');

            // Validate input
            if (String.isBlank(phoneNumber)) {
                response.success = false;
                response.message = 'Phone number parameter is required';
                return response;
            }

            // Normalize phone number (remove formatting)
            String normalizedPhone = normalizePhoneNumber(phoneNumber);

            if (String.isBlank(normalizedPhone)) {
                response.success = false;
                response.message = 'Invalid phone number format';
                return response;
            }

            // Build flexible LIKE pattern to match formatted and unformatted phones
            String phonePattern = '%' + String.join(normalizedPhone.split(''), '%') + '%';

            System.debug('Normalized phone: ' + normalizedPhone);
            System.debug('Phone pattern: ' + phonePattern);

            // STEP 1: Query opportunities directly by Phone__c field (primary lookup)
            // Filter by active stages and case manager assigned
            List<Opportunity> opportunities = [
                SELECT Id,
                       Case_Manager__c,
                       Case_Manager__r.Id,
                       Case_Manager__r.Name,
                       Case_Manager__r.Email,
                       Case_Manager__r.Phone,
                       Case_Manager__r.IsActive,
                       Account.Id
                FROM Opportunity
                WHERE Phone__c LIKE :phonePattern
                  AND StageName IN :ACTIVE_STAGES
                  AND Case_Manager__c != null
                  AND Case_Manager__r.IsActive = true
                ORDER BY CreatedDate DESC
                LIMIT 10
            ];

            Opportunity opp = null;

            // If found via Opportunity.Phone__c, use it
            if (!opportunities.isEmpty()) {
                opp = opportunities[0];
                System.debug('Found opportunity via Opportunity.Phone__c: ' + opp.Id);
            } else {
                // STEP 2: Fallback - Search by Contact phones (Phone, MobilePhone, HomePhone)
                System.debug('No opportunity found via Opportunity.Phone__c, trying Contact phones...');

                List<Contact> contacts = [
                    SELECT Id, Name, Email,
                           (SELECT OpportunityId, Opportunity.Id, Opportunity.Case_Manager__c,
                                   Opportunity.Case_Manager__r.Id, Opportunity.Case_Manager__r.Name,
                                   Opportunity.Case_Manager__r.Email, Opportunity.Case_Manager__r.Phone,
                                   Opportunity.Case_Manager__r.IsActive, Opportunity.Account.Id,
                                   Opportunity.StageName
                            FROM OpportunityContactRoles
                            WHERE Opportunity.StageName IN :ACTIVE_STAGES
                              AND Opportunity.Case_Manager__c != null
                              AND Opportunity.Case_Manager__r.IsActive = true
                            ORDER BY Opportunity.CreatedDate DESC
                            LIMIT 1)
                    FROM Contact
                    WHERE Phone LIKE :phonePattern
                       OR MobilePhone LIKE :phonePattern
                       OR HomePhone LIKE :phonePattern
                       OR Phone_2__c LIKE :phonePattern
                       OR Phone_3__c LIKE :phonePattern
                       OR Fax LIKE :phonePattern
                    ORDER BY LastModifiedDate DESC
                    LIMIT 1
                ];

                // Check if we found a contact with an active opportunity
                if (!contacts.isEmpty() && !contacts[0].OpportunityContactRoles.isEmpty()) {
                    OpportunityContactRole ocr = contacts[0].OpportunityContactRoles[0];

                    // Build Opportunity object from OpportunityContactRole
                    opp = new Opportunity(
                        Id = ocr.OpportunityId,
                        Case_Manager__c = ocr.Opportunity.Case_Manager__c,
                        Account = new Account(Id = ocr.Opportunity.Account.Id)
                    );

                    // Populate Case_Manager__r relationship manually
                    opp.Case_Manager__r = ocr.Opportunity.Case_Manager__r;

                    System.debug('Found opportunity via Contact phone: ' + opp.Id);
                } else {
                    // No opportunity found via either method
                    response.success = false;
                    response.message = 'No active opportunity with assigned case manager found for phone: ' + phoneNumber;
                    System.debug('No active opportunity found for phone: ' + phoneNumber);
                    return response;
                }
            }

            // Find contact for this opportunity (via Account or OpportunityContactRole)
            Contact foundContact = null;

            // Try finding contact by Account first
            if (opp.Account != null && opp.Account.Id != null) {
                List<Contact> contacts = [
                    SELECT Id, Name, Email
                    FROM Contact
                    WHERE (Phone LIKE :phonePattern
                        OR MobilePhone LIKE :phonePattern
                        OR Phone_2__c LIKE :phonePattern
                        OR Phone_3__c LIKE :phonePattern
                        OR Fax LIKE :phonePattern)
                      AND AccountId = :opp.Account.Id
                    LIMIT 1
                ];

                if (!contacts.isEmpty()) {
                    foundContact = contacts[0];
                }
            }

            // If not found, try OpportunityContactRole
            if (foundContact == null) {
                List<OpportunityContactRole> roles = [
                    SELECT Contact.Id, Contact.Name, Contact.Email
                    FROM OpportunityContactRole
                    WHERE OpportunityId = :opp.Id
                      AND IsPrimary = true
                    LIMIT 1
                ];

                if (!roles.isEmpty()) {
                    foundContact = roles[0].Contact;
                }
            }

            // If still not found, search all contacts by phone
            if (foundContact == null) {
                List<Contact> contacts = [
                    SELECT Id, Name, Email
                    FROM Contact
                    WHERE Phone LIKE :phonePattern
                       OR MobilePhone LIKE :phonePattern
                       OR Phone_2__c LIKE :phonePattern
                       OR Phone_3__c LIKE :phonePattern
                       OR Fax LIKE :phonePattern
                    ORDER BY LastModifiedDate DESC
                    LIMIT 1
                ];

                if (!contacts.isEmpty()) {
                    foundContact = contacts[0];
                }
            }

            // Set opportunity ID
            response.opportunityId = opp.Id;

            // Set account ID from the opportunity
            if (opp.Account != null && opp.Account.Id != null) {
                response.accountId = opp.Account.Id;
            }

            // Build contact data
            if (foundContact != null) {
                response.contact = new ContactData();
                response.contact.id = foundContact.Id;
                response.contact.name = foundContact.Name;
                response.contact.email = foundContact.Email;
            }

            // Build case manager data
            if (opp.Case_Manager__r != null) {
                response.caseManager = new CaseManagerData();
                response.caseManager.id = opp.Case_Manager__r.Id;
                response.caseManager.name = opp.Case_Manager__r.Name;
                response.caseManager.email = opp.Case_Manager__r.Email;
                response.caseManager.phone = opp.Case_Manager__r.Phone;
            }

            response.success = true;
            response.message = 'Found case manager for phone: ' + phoneNumber;

        } catch (Exception e) {
            response.success = false;
            response.error = e.getTypeName() + ': ' + e.getMessage();
            response.message = 'An error occurred while processing your request';
            System.debug('AnswerForcePhoneLookupAPI Error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }

        return response;
    }

    /**
     * Normalize phone number by removing all non-digit characters
     * @param phone Raw phone number input
     * @return Normalized phone number (digits only)
     */
    private static String normalizePhoneNumber(String phone) {
        if (String.isBlank(phone)) {
            return null;
        }

        // Remove all non-digit characters
        String normalized = phone.replaceAll('[^0-9]', '');

        // Remove leading 1 for US numbers (optional)
        if (normalized.length() == 11 && normalized.startsWith('1')) {
            normalized = normalized.substring(1);
        }

        return normalized;
    }

    /**
     * Get all active case managers with Case Manager profile
     * @return List of CaseManagerData with name, email, and phone
     */
    private static List<CaseManagerData> getAllActiveCaseManagers() {
        List<CaseManagerData> caseManagers = new List<CaseManagerData>();

        // Query all active users with Case Manager profile
        List<User> users = [
            SELECT Id, Name, Email, Phone
            FROM User
            WHERE Profile.Name = 'Case Manager'
              AND IsActive = true
            ORDER BY Name
        ];

        // Convert to CaseManagerData list
        for (User u : users) {
            CaseManagerData cm = new CaseManagerData();
            cm.id = u.Id;
            cm.name = u.Name;
            cm.email = u.Email;
            cm.phone = u.Phone;
            caseManagers.add(cm);
        }

        return caseManagers;
    }

    // ========== WRAPPER CLASSES FOR JSON RESPONSE ==========

    /**
     * Main response wrapper
     */
    global class LookupResponse {
        public Boolean success;
        public String message;
        public String error;
        public String opportunityId;
        public String accountId;
        public ContactData contact;
        public CaseManagerData caseManager;
        public List<CaseManagerData> allCaseManagers;

        public LookupResponse() {
            this.success = false;
        }
    }

    /**
     * Contact data wrapper
     */
    global class ContactData {
        public String id;
        public String name;
        public String email;
    }

    /**
     * Case Manager data wrapper
     */
    global class CaseManagerData {
        public String id;
        public String name;
        public String email;
        public String phone;
    }
}