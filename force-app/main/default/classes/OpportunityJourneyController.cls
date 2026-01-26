public with sharing class OpportunityJourneyController {
    
    /**
     * Retrieves Opportunity records filtered by stages: Contract Signed, Enrolled, NSF
     * @return List of Opportunity records
     */
    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getOpportunityJourneys() {
        try {
            return [
                SELECT Id, 
                       Name,
                       StageName,
                       Amount,
                       Owner.Name,
                       CreatedDate,
                       LastModifiedDate
                FROM Opportunity
                WHERE StageName IN ('Contract Signed', 'Enrolled', 'NSF')
                AND IsDeleted = false
                ORDER BY CreatedDate DESC
                LIMIT 1000
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving opportunity journeys: ' + e.getMessage());
        }
    }
    
    /**
     * Retrieves welcome cases for a specific opportunity
     * @param opportunityId The Id of the Opportunity
     * @return List of welcome case information
     */
    @AuraEnabled(cacheable=true)
    public static List<WelcomeCaseInfo> getWelcomeCasesForOpportunity(Id opportunityId) {
        if (opportunityId == null) {
            return new List<WelcomeCaseInfo>();
        }
        
        try {
            // Try to find cases related to this opportunity
            List<Case> welcomeCases = [
                SELECT Id, CaseNumber, Subject, Status, Priority, Description,
                       CreatedDate, LastModifiedDate,
                       Owner.Name
                FROM Case 
                WHERE AccountId IN (SELECT AccountId FROM Opportunity WHERE Id = :opportunityId)
                ORDER BY LastModifiedDate DESC
                LIMIT 10
            ];
            
            List<WelcomeCaseInfo> caseInfoList = new List<WelcomeCaseInfo>();
            
            for (Case c : welcomeCases) {
                WelcomeCaseInfo info = new WelcomeCaseInfo();
                info.Id = c.Id;
                info.CaseNumber = c.CaseNumber;
                info.Subject = c.Subject;
                info.Status = c.Status;
                info.Priority = c.Priority;
                info.Description = c.Description;
                info.CreatedDate = c.CreatedDate;
                info.LastModifiedDate = c.LastModifiedDate;
                info.ownerName = c.Owner?.Name;
                caseInfoList.add(info);
            }
            
            return caseInfoList;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving welcome cases: ' + e.getMessage());
        }
    }
    
    /**
     * Gets all related cases for an opportunity
     * @param opportunityId The Id of the Opportunity
     * @return List of related cases
     */
    @AuraEnabled(cacheable=true)
    public static List<Case> getRelatedCases(Id opportunityId) {
        if (opportunityId == null) {
            return new List<Case>();
        }
        
        try {
            return [
                SELECT Id, CaseNumber, Subject, Status, Priority, 
                       CreatedDate, LastModifiedDate, Owner.Name
                FROM Case 
                WHERE AccountId IN (SELECT AccountId FROM Opportunity WHERE Id = :opportunityId)
                ORDER BY LastModifiedDate DESC
                LIMIT 50
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving related cases: ' + e.getMessage());
        }
    }
    
    /**
     * Wrapper class for welcome case information
     */
    public class WelcomeCaseInfo {
        @AuraEnabled public String Id;
        @AuraEnabled public String CaseNumber;
        @AuraEnabled public String Subject;
        @AuraEnabled public String Status;
        @AuraEnabled public String Priority;
        @AuraEnabled public String Description;
        @AuraEnabled public DateTime CreatedDate;
        @AuraEnabled public DateTime LastModifiedDate;
        @AuraEnabled public String ownerName;
    }
}