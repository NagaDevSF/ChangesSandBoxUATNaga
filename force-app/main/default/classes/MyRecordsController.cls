public with sharing class MyRecordsController {
    
    @AuraEnabled(cacheable=true)
    public static List<Lead> getMyLeads() {
        try {
            // Check if user has access to Lead object
            if (!Schema.SObjectType.Lead.isAccessible()) {
                throw new AuraHandledException('You do not have access to Lead records. Please contact your administrator.');
            }
            
            // Check if user has access to required fields
            if (!Schema.SObjectType.Lead.fields.Name.isAccessible() || 
                !Schema.SObjectType.Lead.fields.Phone.isAccessible()) {
                throw new AuraHandledException('You do not have access to required Lead fields. Please contact your administrator.');
            }
            
            List<Lead> leads = [
                SELECT Id, Name, Phone, Main_Source__c, Pre_Deal_Status__c, OwnerId
                FROM Lead 
                WHERE OwnerId = :UserInfo.getUserId()
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];
            
            System.debug('Found ' + leads.size() + ' leads for user ' + UserInfo.getUserId());
            return leads;
            
        } catch (Exception e) {
            System.debug('Error in getMyLeads: ' + e.getMessage() + ' Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving leads: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Integer getMyLeadsCount() {
        try {
            // Check if user has access to Lead object
            if (!Schema.SObjectType.Lead.isAccessible()) {
                throw new AuraHandledException('You do not have access to Lead records. Please contact your administrator.');
            }
            
            Integer leadCount = [
                SELECT COUNT()
                FROM Lead 
                WHERE OwnerId = :UserInfo.getUserId()
            ];
            
            System.debug('Found ' + leadCount + ' total leads for user ' + UserInfo.getUserId());
            return leadCount;
            
        } catch (Exception e) {
            System.debug('Error in getMyLeadsCount: ' + e.getMessage() + ' Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving lead count: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getMyOpportunities() {
        try {
            // Check if user has access to Opportunity object
            if (!Schema.SObjectType.Opportunity.isAccessible()) {
                throw new AuraHandledException('You do not have access to Opportunity records. Please contact your administrator.');
            }
            
            // Check if user has access to required fields
            if (!Schema.SObjectType.Opportunity.fields.Name.isAccessible()) {
                throw new AuraHandledException('You do not have access to required Opportunity fields. Please contact your administrator.');
            }
            
            List<Opportunity> opportunities = [
                SELECT Id, Name, Phone__c, Main_Source__c, OwnerId
                FROM Opportunity 
                WHERE OwnerId = :UserInfo.getUserId()
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];
            
            System.debug('Found ' + opportunities.size() + ' opportunities for user ' + UserInfo.getUserId());
            return opportunities;
            
        } catch (Exception e) {
            System.debug('Error in getMyOpportunities: ' + e.getMessage() + ' Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving opportunities: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Integer getMyOpportunitiesCount() {
        try {
            // Check if user has access to Opportunity object
            if (!Schema.SObjectType.Opportunity.isAccessible()) {
                throw new AuraHandledException('You do not have access to Opportunity records. Please contact your administrator.');
            }
            
            Integer opportunityCount = [
                SELECT COUNT()
                FROM Opportunity 
                WHERE OwnerId = :UserInfo.getUserId()
            ];
            
            System.debug('Found ' + opportunityCount + ' total opportunities for user ' + UserInfo.getUserId());
            return opportunityCount;
            
        } catch (Exception e) {
            System.debug('Error in getMyOpportunitiesCount: ' + e.getMessage() + ' Stack: ' + e.getStackTraceString());
            throw new AuraHandledException('Error retrieving opportunity count: ' + e.getMessage());
        }
    }
}