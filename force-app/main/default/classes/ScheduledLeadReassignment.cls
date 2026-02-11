/**
 * @description Schedulable class to automatically reassign leads every 2 minutes 15 seconds
 *              This class queries leads based on specified criteria and reassigns them to a target owner
 * @author Salesforce Developer
 * @date 2025
 */
public class ScheduledLeadReassignment implements Schedulable, Database.Batchable<SObject>, Database.Stateful {

    // Flag to ensure Flow runs only once per batch execution
    private Boolean hasExecuted = false;

    private String targetOwnerUsername;
    private static final Integer BATCH_SIZE = 200;

    // Interval in seconds (2 minutes 15 seconds = 135 seconds)
    private static final Integer RESCHEDULE_INTERVAL_SECONDS = 135;
    private static final String JOB_NAME = 'Lead Reassignment Auto';

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
        // Return a simple query that returns exactly 1 record to trigger the execute method once
        // The Flow will handle querying and filtering leads
        String query = 'SELECT Id FROM Organization LIMIT 1';
        return Database.getQueryLocator(query);
    }

    /**
     * @description Execute method for batch processing - calls the Flow
     * @param bc Database.BatchableContext
     * @param scope List of SObject records to process
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        // Ensure Flow runs only once per batch execution
        if (hasExecuted) {
            System.debug('Flow already executed in this batch, skipping');
            return;
        }

        // Trigger the Lead Reassignment Flow only once
        try {
            Map<String, Object> flowInputs = new Map<String, Object>();
            Flow.Interview leadReassignmentFlow = new Flow.Interview.Lead_Reassignment_Flow(flowInputs);
            leadReassignmentFlow.start();
            hasExecuted = true;
            System.debug('Lead Reassignment Flow triggered successfully');
        } catch (Exception e) {
            System.debug('Error triggering Lead Reassignment Flow: ' + e.getMessage());
        }
    }

    /**
     * @description Finish method for batch processing - reschedules the job for the next interval
     * @param bc Database.BatchableContext
     */
    public void finish(Database.BatchableContext bc) {
        System.debug('Lead reassignment batch completed');

        // Reschedule the job for the next interval (2 min 15 sec from now)
        scheduleNextRun();
    }

    /**
     * @description Schedule the next run after the configured interval
     */
    private void scheduleNextRun() {
        try {
            // Clean up old completed/deleted jobs to prevent accumulation
            cleanupOldJobs();

            DateTime nextRun = DateTime.now().addSeconds(RESCHEDULE_INTERVAL_SECONDS);
            String cronExp = nextRun.second() + ' ' + nextRun.minute() + ' ' + nextRun.hour() + ' ' +
                            nextRun.day() + ' ' + nextRun.month() + ' ? ' + nextRun.year();

            System.schedule(JOB_NAME + ' - ' + nextRun.format('HH:mm:ss'), cronExp, new ScheduledLeadReassignment());
            System.debug('Scheduled next run at: ' + nextRun);
        } catch (Exception e) {
            System.debug('Error scheduling next run: ' + e.getMessage());
        }
    }

    /**
     * @description Clean up old completed/deleted jobs to prevent accumulation
     */
    private void cleanupOldJobs() {
        try {
            List<CronTrigger> oldJobs = [SELECT Id FROM CronTrigger
                                         WHERE CronJobDetail.Name LIKE 'Lead Reassignment Auto%'
                                         AND State = 'DELETED'
                                         LIMIT 20];
            for (CronTrigger job : oldJobs) {
                System.abortJob(job.Id);
            }
            if (!oldJobs.isEmpty()) {
                System.debug('Cleaned up ' + oldJobs.size() + ' old jobs');
            }
        } catch (Exception e) {
            System.debug('Error cleaning up old jobs: ' + e.getMessage());
        }
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
     * @description Start the self-rescheduling job that runs every 2 min 15 sec
     *              Call this method from Anonymous Apex to start the recurring job
     */
    public static void startAutoSchedule() {
        // Abort any existing jobs first
        abortExistingJobs();

        // Schedule the first run immediately (5 seconds from now to allow for processing)
        DateTime firstRun = DateTime.now().addSeconds(5);
        String cronExp = firstRun.second() + ' ' + firstRun.minute() + ' ' + firstRun.hour() + ' ' +
                        firstRun.day() + ' ' + firstRun.month() + ' ? ' + firstRun.year();

        System.schedule(JOB_NAME + ' - ' + firstRun.format('HH:mm:ss'), cronExp, new ScheduledLeadReassignment());
        System.debug('Started auto-scheduling. First run at: ' + firstRun + '. Interval: ' + RESCHEDULE_INTERVAL_SECONDS + ' seconds');
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