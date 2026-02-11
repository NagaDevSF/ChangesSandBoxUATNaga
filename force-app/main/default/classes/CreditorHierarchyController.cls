/**
 * @description Controller for Creditor Hierarchy LWC Component
 * @author Claude Code Assistant
 * @date 2025-10-17
 */
public with sharing class CreditorHierarchyController {
    
    /**
     * @description Wrapper class for Account data
     */
    public class AccountWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String accountNumber;
        @AuraEnabled public String primaryCreditorPhone;
        @AuraEnabled public String ein;
        @AuraEnabled public Integer creditorOpportunityCount;
        @AuraEnabled public List<CreditorOpportunityWrapper> creditorOpportunities;
        
        public AccountWrapper() {
            this.creditorOpportunities = new List<CreditorOpportunityWrapper>();
            this.creditorOpportunityCount = 0;
        }
    }
    
    /**
     * @description Wrapper class for CreditorOpportunity data
     */
    public class CreditorOpportunityWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Decimal weeklyPayment;
        @AuraEnabled public String frequency;
        @AuraEnabled public String opportunityNumber;
        @AuraEnabled public Boolean readyForLegal;
        @AuraEnabled public Integer negotiationsCount;
        @AuraEnabled public List<NegotiationWrapper> negotiations;
        
        public CreditorOpportunityWrapper() {
            this.negotiations = new List<NegotiationWrapper>();
            this.negotiationsCount = 0;
        }
    }
    
    /**
     * @description Wrapper class for Negotiation data
     */
    public class NegotiationWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String negotiationStatus;
        @AuraEnabled public Decimal settlementOfferAmount;
        @AuraEnabled public Decimal finalAgreedAmount;
        @AuraEnabled public Date paymentDueDate;
        @AuraEnabled public String statusColor;
        
        public NegotiationWrapper() {}
    }
    
    /**
     * @description Main method to get the creditor hierarchy data
     * @return Map<String, Object> containing hierarchy data and metadata
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getCreditorHierarchy() {
        try {
            Map<String, Object> result = new Map<String, Object>();
            List<AccountWrapper> accountWrappers = new List<AccountWrapper>();
            
            // Query all Creditor Accounts with their Creditor Opportunities
            List<Account> accounts = [
                SELECT Id, Name, AccountNumber, Primary_Creditor_Phone__c, 
                       EIN_Employer_Identification_Number__c
                FROM Account 
                WHERE Type = 'Creditor'
                  AND Id IN (SELECT CreditorAccount__c FROM CreditorOpportunity__c)
                ORDER BY Name
                LIMIT 200
            ];
            
            if (accounts.isEmpty()) {
                return buildEmptyResult();
            }
            
            // Get all CreditorOpportunities for these accounts
            Set<Id> accountIds = new Set<Id>();
            for (Account acc : accounts) {
                accountIds.add(acc.Id);
            }
            
            List<CreditorOpportunity__c> creditorOpportunities = [
                SELECT Id, Name, Amount__c, Weekly_Payment__c, 
                       Frequency__c, Number__c, Ready_for_Legal__c, CreditorAccount__c
                FROM CreditorOpportunity__c
                WHERE CreditorAccount__c IN :accountIds
                ORDER BY Name
            ];
            
            // Group opportunities by account
            Map<Id, List<CreditorOpportunity__c>> opportunitiesByAccount = new Map<Id, List<CreditorOpportunity__c>>();
            Set<Id> opportunityIds = new Set<Id>();
            
            for (CreditorOpportunity__c opp : creditorOpportunities) {
                if (!opportunitiesByAccount.containsKey(opp.CreditorAccount__c)) {
                    opportunitiesByAccount.put(opp.CreditorAccount__c, new List<CreditorOpportunity__c>());
                }
                opportunitiesByAccount.get(opp.CreditorAccount__c).add(opp);
                opportunityIds.add(opp.Id);
            }
            
            // Initialize empty negotiations map since the relationship structure is unclear
            Map<Id, List<Negotiation__c>> negotiationsByOpportunity = new Map<Id, List<Negotiation__c>>();
            
            // Build the hierarchy structure
            for (Account acc : accounts) {
                AccountWrapper accWrapper = new AccountWrapper();
                accWrapper.id = acc.Id;
                accWrapper.name = acc.Name;
                accWrapper.accountNumber = acc.AccountNumber;
                accWrapper.primaryCreditorPhone = acc.Primary_Creditor_Phone__c;
                accWrapper.ein = acc.EIN_Employer_Identification_Number__c;
                
                // Process CreditorOpportunities
                if (opportunitiesByAccount.containsKey(acc.Id)) {
                    List<CreditorOpportunity__c> accountOpportunities = opportunitiesByAccount.get(acc.Id);
                    accWrapper.creditorOpportunityCount = accountOpportunities.size();
                    
                    for (CreditorOpportunity__c opp : accountOpportunities) {
                        CreditorOpportunityWrapper oppWrapper = new CreditorOpportunityWrapper();
                        oppWrapper.id = opp.Id;
                        oppWrapper.name = opp.Name;
                        oppWrapper.amount = opp.Amount__c;
                        oppWrapper.weeklyPayment = opp.Weekly_Payment__c;
                        oppWrapper.frequency = opp.Frequency__c;
                        oppWrapper.opportunityNumber = opp.Number__c;
                        oppWrapper.readyForLegal = opp.Ready_for_Legal__c;
                        
                        // Negotiations are not available in current data model
                        oppWrapper.negotiationsCount = 0;
                        
                        accWrapper.creditorOpportunities.add(oppWrapper);
                    }
                }
                
                accountWrappers.add(accWrapper);
            }
            
            // Calculate summary statistics
            Integer totalAccounts = accountWrappers.size();
            Integer totalOpportunities = 0;
            Integer totalNegotiations = 0;
            Integer settledNegotiations = 0;
            
            for (AccountWrapper accWrapper : accountWrappers) {
                totalOpportunities += accWrapper.creditorOpportunityCount;
                for (CreditorOpportunityWrapper oppWrapper : accWrapper.creditorOpportunities) {
                    totalNegotiations += oppWrapper.negotiationsCount;
                    for (NegotiationWrapper negWrapper : oppWrapper.negotiations) {
                        if ('Settled'.equalsIgnoreCase(negWrapper.negotiationStatus)) {
                            settledNegotiations++;
                        }
                    }
                }
            }
            
            // Prepare result
            result.put('accounts', accountWrappers);
            result.put('summary', new Map<String, Object>{
                'totalAccounts' => totalAccounts,
                'totalCreditorOpportunities' => totalOpportunities,
                'totalNegotiations' => totalNegotiations,
                'settledNegotiations' => settledNegotiations,
                'lastRefresh' => System.now()
            });
            result.put('success', true);
            
            return result;
            
        } catch (Exception e) {
            System.debug('Error in getCreditorHierarchy: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            return new Map<String, Object>{
                'success' => false,
                'error' => 'Failed to load creditor hierarchy: ' + e.getMessage(),
                'accounts' => new List<AccountWrapper>(),
                'summary' => buildEmptySummary()
            };
        }
    }
    
    /**
     * @description Helper method to build empty result
     */
    private static Map<String, Object> buildEmptyResult() {
        return new Map<String, Object>{
            'success' => true,
            'accounts' => new List<AccountWrapper>(),
            'summary' => buildEmptySummary()
        };
    }
    
    /**
     * @description Helper method to build empty summary
     */
    private static Map<String, Object> buildEmptySummary() {
        return new Map<String, Object>{
            'totalAccounts' => 0,
            'totalCreditorOpportunities' => 0,
            'totalNegotiations' => 0,
            'settledNegotiations' => 0,
            'lastRefresh' => System.now()
        };
    }
    
    /**
     * @description Helper method to determine status color based on negotiation status
     * @param status The negotiation status
     * @return String representing the color class
     */
    private static String getStatusColor(String status) {
        if (String.isBlank(status)) {
            return 'gray';
        }
        
        String lowerStatus = status.toLowerCase();
        if (lowerStatus.contains('settled') || lowerStatus.contains('completed')) {
            return 'green';
        } else if (lowerStatus.contains('progress') || lowerStatus.contains('pending') || lowerStatus.contains('active')) {
            return 'yellow';
        } else if (lowerStatus.contains('declined') || lowerStatus.contains('cancelled') || lowerStatus.contains('failed')) {
            return 'red';
        }
        
        return 'blue'; // Default for other statuses
    }
    
    /**
     * @description Method to export hierarchy data to CSV format
     * @return String CSV content
     */
    @AuraEnabled
    public static String exportToCSV() {
        try {
            Map<String, Object> hierarchyData = getCreditorHierarchy();
            List<AccountWrapper> accounts = (List<AccountWrapper>) hierarchyData.get('accounts');
            
            String csvContent = 'Account Name,Account Number,Phone,EIN,Creditor Opportunity Name,Amount,Weekly Payment,Frequency,Number,Ready for Legal,Negotiation Name,Status,Settlement Offer,Final Amount,Due Date\n';
            
            for (AccountWrapper acc : accounts) {
                for (CreditorOpportunityWrapper credOpp : acc.creditorOpportunities) {
                    if (credOpp.negotiations.size() > 0) {
                        for (NegotiationWrapper neg : credOpp.negotiations) {
                            csvContent += buildCSVRow(acc, credOpp, neg);
                        }
                    } else {
                        // Include creditor opportunity even without negotiations
                        csvContent += buildCSVRow(acc, credOpp, null);
                    }
                }
            }
            
            return csvContent;
            
        } catch (Exception e) {
            throw new AuraHandledException('Failed to export data: ' + e.getMessage());
        }
    }
    
    /**
     * @description Helper method to build CSV row
     */
    private static String buildCSVRow(AccountWrapper acc, CreditorOpportunityWrapper credOpp, NegotiationWrapper neg) {
        String row = '';
        row += '"' + String.valueOf(acc.name != null ? acc.name : '').replace('"', '""') + '",';
        row += '"' + String.valueOf(acc.accountNumber != null ? acc.accountNumber : '').replace('"', '""') + '",';
        row += '"' + String.valueOf(acc.primaryCreditorPhone != null ? acc.primaryCreditorPhone : '').replace('"', '""') + '",';
        row += '"' + String.valueOf(acc.ein != null ? acc.ein : '').replace('"', '""') + '",';
        row += '"' + String.valueOf(credOpp.name != null ? credOpp.name : '').replace('"', '""') + '",';
        row += (credOpp.amount != null ? String.valueOf(credOpp.amount) : '') + ',';
        row += (credOpp.weeklyPayment != null ? String.valueOf(credOpp.weeklyPayment) : '') + ',';
        row += '"' + String.valueOf(credOpp.frequency != null ? credOpp.frequency : '').replace('"', '""') + '",';
        row += '"' + String.valueOf(credOpp.opportunityNumber != null ? credOpp.opportunityNumber : '').replace('"', '""') + '",';
        row += (credOpp.readyForLegal != null ? String.valueOf(credOpp.readyForLegal) : '') + ',';
        
        if (neg != null) {
            row += '"' + String.valueOf(neg.name != null ? neg.name : '').replace('"', '""') + '",';
            row += '"' + String.valueOf(neg.negotiationStatus != null ? neg.negotiationStatus : '').replace('"', '""') + '",';
            row += (neg.settlementOfferAmount != null ? String.valueOf(neg.settlementOfferAmount) : '') + ',';
            row += (neg.finalAgreedAmount != null ? String.valueOf(neg.finalAgreedAmount) : '') + ',';
            row += (neg.paymentDueDate != null ? String.valueOf(neg.paymentDueDate) : '') + '\n';
        } else {
            row += '"","",,\n';
        }
        
        return row;
    }
}