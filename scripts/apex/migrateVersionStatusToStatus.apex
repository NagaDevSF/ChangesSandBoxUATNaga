// Data Migration: Consolidate Version_Status__c into Status__c
// Run this AFTER deploying the updated Status__c picklist values

// 1. Archived plans that still show Draft in Status__c
List<PaymentPlan__c> archivedPlans = [
    SELECT Id, Version_Status__c, Status__c
    FROM PaymentPlan__c
    WHERE Version_Status__c = 'Archived' AND Status__c = 'Draft'
];
for (PaymentPlan__c p : archivedPlans) {
    p.Status__c = 'Archived';
}

// 2. Pending_Review plans
List<PaymentPlan__c> pendingPlans = [
    SELECT Id, Version_Status__c, Status__c
    FROM PaymentPlan__c
    WHERE Version_Status__c = 'Pending_Review' AND Status__c != 'Pending_Review'
];
for (PaymentPlan__c p : pendingPlans) {
    p.Status__c = 'Pending_Review';
}

// 3. Any other mismatches where Version_Status__c has a meaningful value
//    but Status__c is still Draft (catch-all)
List<PaymentPlan__c> otherMismatches = [
    SELECT Id, Version_Status__c, Status__c
    FROM PaymentPlan__c
    WHERE Version_Status__c != null
    AND Version_Status__c != 'Draft'
    AND Status__c = 'Draft'
    AND Id NOT IN :archivedPlans
    AND Id NOT IN :pendingPlans
];
for (PaymentPlan__c p : otherMismatches) {
    p.Status__c = p.Version_Status__c;
}

List<PaymentPlan__c> allUpdates = new List<PaymentPlan__c>();
allUpdates.addAll(archivedPlans);
allUpdates.addAll(pendingPlans);
allUpdates.addAll(otherMismatches);

if (!allUpdates.isEmpty()) {
    update allUpdates;
    System.debug('Updated ' + allUpdates.size() + ' records:');
    System.debug('  Archived: ' + archivedPlans.size());
    System.debug('  Pending_Review: ' + pendingPlans.size());
    System.debug('  Other: ' + otherMismatches.size());
} else {
    System.debug('No records needed migration.');
}
