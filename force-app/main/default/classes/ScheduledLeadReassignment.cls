/**
 * @description Schedulable class to automatically reassign leads every 2 minutes
 *              This class queries leads based on specified criteria and reassigns them to a target owner
 * @author Salesforce Developer
 * @date 2025
 */
public class ScheduledLeadReassignment implements Schedulable, Database.Batchable<SObject> {

    private String targetOwnerUsername;
    private static final Integer BATCH_SIZE = 200;

    /**
     * @description Constructor with default owner
     */
    public ScheduledLeadReassignment() {
        this.targetOwnerUsername = 'Naga';
    }

    /**
     * @description Constructor with custom owner
     * @param ownerUsername Username or name of the target owner
     */
    public ScheduledLeadReassignment(String ownerUsername) {
        this.targetOwnerUsername = ownerUsername;
    }

    /**
     * @description Execute method called by the scheduler
     * @param sc SchedulableContext
     */
    public void execute(SchedulableContext sc) {
        // Execute the batch job
        Database.executeBatch(this, BATCH_SIZE);
    }

    /**
     * @description Start method for batch processing - returns a dummy query since Flow handles everything
     * @param bc Database.BatchableContext
     * @return Database.QueryLocator
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Return a simple query that returns 1 record to trigger the execute method once
        // The Flow will handle querying and filtering leads
        String query = 'SELECT Id FROM Lead LIMIT 1';
        return Database.getQueryLocator(query);
    }

    /**
     * @description Execute method for batch processing - calls the Flow
     * @param bc Database.BatchableContext
     * @param scope List of Lead records to process
     */
    public void execute(Database.BatchableContext bc, List<Lead> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        // Trigger the Lead Reassignment Flow
        try {
            Map<String, Object> flowInputs = new Map<String, Object>();
            Flow.Interview leadReassignmentFlow = new Flow.Interview.Lead_Reassignment_Flow(flowInputs);
            leadReassignmentFlow.start();
            System.debug('Lead Reassignment Flow triggered successfully');
        } catch (Exception e) {
            System.debug('Error triggering Lead Reassignment Flow: ' + e.getMessage());
        }
    }

    /**
     * @description Finish method for batch processing
     * @param bc Database.BatchableContext
     */
    public void finish(Database.BatchableContext bc) {
        System.debug('Lead reassignment batch completed');
    }

    /**
     * @description Schedule this job to run every 2 minutes
     *              Call this method from Anonymous Apex or another class
     */
    public static void scheduleEvery2Minutes() {
        // Abort any existing jobs first
        abortExistingJobs();

        // Schedule jobs every 2 minutes for the next hour
        // Note: Salesforce has a limit of 100 scheduled jobs
        for (Integer i = 0; i < 30; i++) {
            String cronExp = generateCronExpression(i * 2);
            String jobName = 'Lead Reassignment - ' + String.valueOf(i * 2) + ' min';
            System.schedule(jobName, cronExp, new ScheduledLeadReassignment());
        }

        System.debug('Scheduled 30 jobs to run every 2 minutes');
    }

    /**
     * @description Generate CRON expression for specific minute offset
     * @param minuteOffset Minute offset from current time
     * @return String CRON expression
     */
    private static String generateCronExpression(Integer minuteOffset) {
        DateTime now = DateTime.now().addMinutes(minuteOffset);
        return '0 ' + now.minute() + ' * * * ?';
    }

    /**
     * @description Abort all existing Lead Reassignment scheduled jobs
     */
    public static void abortExistingJobs() {
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name
                                  FROM CronTrigger
                                  WHERE CronJobDetail.Name LIKE 'Lead Reassignment%'];

        for (CronTrigger job : jobs) {
            System.abortJob(job.Id);
        }

        System.debug('Aborted ' + jobs.size() + ' existing jobs');
    }

    /**
     * @description Schedule this job to run at specific intervals throughout the hour
     *              This creates jobs that run every 2 minutes
     */
    public static void scheduleRecurring() {
        // Abort any existing jobs first
        abortExistingJobs();

        // Schedule jobs at 0, 2, 4, 6, ..., 58 minutes of every hour
        for (Integer minute = 0; minute < 60; minute += 2) {
            String cronExp = '0 ' + minute + ' * * * ?';
            String jobName = 'Lead Reassignment - Minute ' + minute;
            System.schedule(jobName, cronExp, new ScheduledLeadReassignment());
        }

        System.debug('Scheduled 30 recurring jobs to run every 2 minutes');
    }
}