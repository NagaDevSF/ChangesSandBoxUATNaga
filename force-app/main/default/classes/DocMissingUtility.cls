public class DocMissingUtility {
    
    // One-time method to refresh all existing cases with empty Docs_Missing__c field
    public static void refreshAllCasesWithEmptyDocs() {
        List<Case> casesToRefresh = [
            SELECT Id 
            FROM Case 
            WHERE Docs_Missing__c = null OR Docs_Missing__c = ''
            LIMIT 200
        ];
        
        if (!casesToRefresh.isEmpty()) {
            List<Id> caseIds = new List<Id>();
            for (Case c : casesToRefresh) {
                caseIds.add(c.Id);
            }
            ContentDocumentLinkHandler.initializeMissingDocs(caseIds);
        }
        
        System.debug('Refreshed ' + casesToRefresh.size() + ' cases');
    }
    
    // Method to refresh a specific case
    public static void refreshSpecificCase(Id caseId) {
        ContentDocumentLinkHandler.initializeMissingDocs(new List<Id>{caseId});
    }
}