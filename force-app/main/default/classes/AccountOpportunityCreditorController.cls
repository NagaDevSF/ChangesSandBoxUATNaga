public with sharing class AccountOpportunityCreditorController {
    
    @AuraEnabled(cacheable=true)
    public static AccountOpportunityWrapper getAccountOpportunitiesWithCreditors(Id accountId) {
        try {
            AccountOpportunityWrapper wrapper = new AccountOpportunityWrapper();
            
            // Get Account basic info
            Account acc = [
                SELECT Id, Name, Type, Phone, BillingCity, BillingState
                FROM Account 
                WHERE Id = :accountId 
                LIMIT 1
            ];
            wrapper.account = acc;
            
            // Get Opportunities with their CreditorOpportunities
            List<Opportunity> opportunities = [
                SELECT Id, Name, Amount, StageName, CloseDate,
                       Estimated_Total_Debt__c, Est_weekly_payment__c, 
                       Estimated_Current_Payment__c, Payment_Frequency__c,
                       Desired_Weekly_Payment__c, Quiz_Quote__c,
                       (SELECT Id, Name, Creditor__c, Number__c, Amount__c,
                               Weekly_Payment__c, Frequency__c,
                               Estimated_Current_Weekly_Payment__c,
                               CreditorAccount__c, CreditorAccount__r.Name
                        FROM CreditorOpportunitys__r
                        ORDER BY CreatedDate DESC)
                FROM Opportunity 
                WHERE AccountId = :accountId 
                ORDER BY CreatedDate DESC
            ];
            
            // Get all CreditorOpportunity IDs to query related Negotiations
            Set<Id> creditorOppIds = new Set<Id>();
            for (Opportunity opp : opportunities) {
                for (CreditorOpportunity__c creditor : opp.CreditorOpportunitys__r) {
                    creditorOppIds.add(creditor.Id);
                }
            }
            
            // Query related Negotiations
            Map<Id, List<Negotiation__c>> creditorToNegotiations = new Map<Id, List<Negotiation__c>>();
            if (!creditorOppIds.isEmpty()) {
                List<Negotiation__c> negotiations = [
                    SELECT Id, Name, Negotiation_Status__c, Payment_Due_Date__c,
                           Number_of_Payments__c, Settlement_Offer_Amount__c,
                           Counter_Offer_Amount__c, Final_Agreed_Amount__c,
                           Actual_Payment_Amount__c, Creditors_List__c,
                           Negotiation_Date__c, Negotiation_Type__c, Outcome__c,
                           Active__c, Creditor_Representative__c, Next_Follow_Up_Date__c,
                           Payment_Date__c, Negotiation_Notes__c
                    FROM Negotiation__c
                    WHERE Creditors_List__c IN :creditorOppIds
                    AND Active__c = true
                    ORDER BY CreatedDate DESC
                ];
                
                // Group negotiations by CreditorOpportunity
                for (Negotiation__c neg : negotiations) {
                    if (!creditorToNegotiations.containsKey(neg.Creditors_List__c)) {
                        creditorToNegotiations.put(neg.Creditors_List__c, new List<Negotiation__c>());
                    }
                    creditorToNegotiations.get(neg.Creditors_List__c).add(neg);
                }
            }
            
            // Add negotiations to wrapper
            wrapper.creditorNegotiations = creditorToNegotiations;
            
            wrapper.opportunities = opportunities;
            wrapper.totalOpportunities = opportunities.size();
            
            // Calculate totals
            Decimal totalAmount = 0;
            Decimal totalEstimatedDebt = 0;
            Integer totalCreditors = 0;
            
            for (Opportunity opp : opportunities) {
                if (opp.Amount != null) {
                    totalAmount += opp.Amount;
                }
                if (opp.Estimated_Total_Debt__c != null) {
                    totalEstimatedDebt += opp.Estimated_Total_Debt__c;
                }
                totalCreditors += opp.CreditorOpportunitys__r.size();
            }
            
            wrapper.totalAmount = totalAmount;
            wrapper.totalEstimatedDebt = totalEstimatedDebt;
            wrapper.totalCreditors = totalCreditors;
            
            return wrapper;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving data: ' + e.getMessage());
        }
    }
    
    public class AccountOpportunityWrapper {
        @AuraEnabled public Account account { get; set; }
        @AuraEnabled public List<Opportunity> opportunities { get; set; }
        @AuraEnabled public Integer totalOpportunities { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }
        @AuraEnabled public Decimal totalEstimatedDebt { get; set; }
        @AuraEnabled public Integer totalCreditors { get; set; }
        @AuraEnabled public Map<Id, List<Negotiation__c>> creditorNegotiations { get; set; }
        
        public AccountOpportunityWrapper() {
            this.opportunities = new List<Opportunity>();
            this.totalOpportunities = 0;
            this.totalAmount = 0;
            this.totalEstimatedDebt = 0;
            this.totalCreditors = 0;
            this.creditorNegotiations = new Map<Id, List<Negotiation__c>>();
        }
    }
}