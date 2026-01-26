public class RoundRobinUnderwriterHandler {
    
    // Store last assigned underwriter index
    private static Integer roundRobinIndex = 0;

    // Main method to assign Underwriters in Round-Robin fashion
    public static void assignUnderwriter(List<Opportunity> opportunities) {
        try {
            // Fetch all active underwriters
            List<User> underwriters = [SELECT Id, CompanyName FROM User WHERE Profile.Name = 'UW' AND IsActive = TRUE];

            // Exit if no underwriters found
            if (underwriters.isEmpty()) {
                System.debug('⚠️ No underwriters found!');
                return;
            }

            List<Opportunity> oppsToUpdate = new List<Opportunity>();

            // Loop through Opportunities and assign underwriters
            for (Opportunity opp : opportunities) {
                if (opp.StageName == 'Docs Submitted to UW') {

                    // Get the Company Name of the Opportunity Owner
                    String ownerCompanyName = opp.Owner.CompanyName;

                    // Find underwriters matching the Owner's Company Name
                    List<User> filteredUnderwriters = new List<User>();
                    for (User u : underwriters) {
                        if (u.CompanyName == ownerCompanyName) {
                            filteredUnderwriters.add(u);
                        }
                    }

                    // If no matching underwriters found, skip this opportunity
                    if (filteredUnderwriters.isEmpty()) {
                        System.debug('⚠️ No matching underwriters for Owner\'s Company: ' + ownerCompanyName);
                        continue;
                    }

                    // Assign underwriter in round-robin fashion
                    opp.Underwriter__c = filteredUnderwriters[roundRobinIndex].Id;
                    oppsToUpdate.add(opp);

                    // ✅ Alternative Round-Robin Logic
                    roundRobinIndex = roundRobinIndex + 1;
                    if (roundRobinIndex >= filteredUnderwriters.size()) {
                        roundRobinIndex = 0; // Reset index when reaching the last underwriter
                    }
                }
            }

            // Perform bulk update
            if (!oppsToUpdate.isEmpty()) {
                update oppsToUpdate;
                System.debug('✅ Opportunities updated successfully with Underwriters!');
            }
        } catch (Exception e) {
            System.debug('⚠️ Error in RoundRobinUnderwriterHandler: ' + e.getMessage());
        }
    }

    // Trigger handler method
    public static void handleAfterUpdate(List<Opportunity> newOpps, Map<Id, Opportunity> oldOpps) {
        List<Opportunity> oppsToAssign = new List<Opportunity>();

        // Filter Opportunities where Stage = "Docs Submitted to UW"
        for (Opportunity opp : newOpps) {
            if (opp.StageName == 'Docs Submitted to UW') {
                oppsToAssign.add(opp);
            }
        }

        // Assign underwriters if needed
        if (!oppsToAssign.isEmpty()) {
            assignUnderwriter(oppsToAssign);
        }
    }
}