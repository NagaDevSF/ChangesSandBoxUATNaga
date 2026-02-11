trigger LeadTrigger on Lead (before insert, after update) {
    // Handle before insert event
    if (Trigger.isBefore && Trigger.isInsert) {
        // Call the helper method to assign new leads
        LeadAssignmentHelper.assignNewLeads(Trigger.new);
    }

    // Handle after update event
    if (Trigger.isAfter && Trigger.isUpdate) {
        // Call the helper method to handle lead reassignment
        LeadReassignmentHandler.handleLeadReassignment(Trigger.new, Trigger.oldMap);
    }
}