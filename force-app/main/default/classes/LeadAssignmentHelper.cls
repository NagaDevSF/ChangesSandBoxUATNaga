public without sharing class LeadAssignmentHelper {

    // Assign new leads immediately after insertion
    public static void assignNewLeads(List<Lead> newLeads) {
        List<Lead> leadsToAssign = new List<Lead>();
        for (Lead lead : newLeads) {
            // Check if the lead meets the criteria for assignment
            if (lead.Status == 'New' && lead.Sales_Office_Ref__c == 'Debtifi') {
                leadsToAssign.add(lead);
            }
        }
        if (!leadsToAssign.isEmpty()) {
            reassignLeads(leadsToAssign);
        }
    }

    // Reassign leads to random users with CompanyName = 'Debtifi' and Profile = 'Sales Rep'
    public static void reassignLeads(List<Lead> leadsToReassign) {
        // Query active users with CompanyName = 'Debtifi' and Profile Name = 'Sales Rep'
        List<User> debtifiUsers = [
            SELECT Id 
            FROM User 
            WHERE CompanyName = 'Debtifi' 
            AND IsActive = true 
            AND Profile.Name = 'Sales Rep'
        ];
        if (debtifiUsers.isEmpty()) {
            return; // No users available for assignment
        }

        Map<Id, User> userMap = new Map<Id, User>(debtifiUsers);

        for (Lead lead : leadsToReassign) {
            if (userMap.size() > 0) {
                // Generate a random index to assign the lead to a random user
                Integer randomIndex = Math.abs(Math.mod(Crypto.getRandomInteger(), userMap.size())); // Ensure non-negative index
                Id newOwnerId = new List<Id>(userMap.keySet())[randomIndex];

                // Ensure the lead is not assigned to the same owner
                if (lead.OwnerId != newOwnerId) {
                    lead.OwnerId = newOwnerId; // Set the OwnerId field (no DML operation here)
                }
            }
        }
    }

    // Calculate the effective 48-hour window excluding weekends
    public static DateTime calculateEffective48HourWindow(DateTime currentDateTime) {
        Integer hoursToSubtract = 48;
        DateTime resultDateTime = currentDateTime;

        while (hoursToSubtract > 0) {
            resultDateTime = resultDateTime.addHours(-1); // Subtract 1 hour
            if (!isWeekend(resultDateTime)) {
                hoursToSubtract--; // Only count weekdays
            }
        }

        return resultDateTime;
    }

    // Check if a given DateTime falls on a weekend (Saturday or Sunday)
    private static Boolean isWeekend(DateTime dt) {
        String dayOfWeek = dt.format('u'); // 'u' returns day of week (1 = Monday, 7 = Sunday)
        return dayOfWeek == '6' || dayOfWeek == '7'; // 6 = Saturday, 7 = Sunday
    }
}