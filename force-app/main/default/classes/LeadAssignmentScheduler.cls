public class LeadAssignmentScheduler implements Schedulable {

    public void execute(SchedulableContext SC) {
        // Execute the batch job
        LeadAssignmentBatch batch = new LeadAssignmentBatch();
        Database.executeBatch(batch);
    }
}