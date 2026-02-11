/**
 * @description Helper class to schedule and manage Lead Reassignment jobs
 *              Provides easy methods to start, stop, and check status of scheduled jobs
 * @author Salesforce Developer
 * @date 2025
 */
public class LeadReassignmentScheduler {

    /**
     * @description Start the scheduled lead reassignment (every 2 minutes)
     *              Call this from Anonymous Apex: LeadReassignmentScheduler.start();
     */
    public static void start() {
        ScheduledLeadReassignment.scheduleRecurring();
        System.debug('Lead reassignment scheduled to run every 2 minutes');
    }

    /**
     * @description Stop all scheduled lead reassignment jobs
     *              Call this from Anonymous Apex: LeadReassignmentScheduler.stop();
     */
    public static void stop() {
        ScheduledLeadReassignment.abortExistingJobs();
        System.debug('All lead reassignment jobs stopped');
    }

    /**
     * @description Get status of all scheduled jobs
     *              Call this from Anonymous Apex: LeadReassignmentScheduler.getStatus();
     */
    public static void getStatus() {
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name, State, NextFireTime, PreviousFireTime
                                  FROM CronTrigger
                                  WHERE CronJobDetail.Name LIKE 'Lead Reassignment%'
                                  ORDER BY CronJobDetail.Name];

        System.debug('========== SCHEDULED JOBS STATUS ==========');
        System.debug('Total jobs: ' + jobs.size());

        for (CronTrigger job : jobs) {
            System.debug('Job: ' + job.CronJobDetail.Name);
            System.debug('  State: ' + job.State);
            System.debug('  Next Fire Time: ' + job.NextFireTime);
            System.debug('  Previous Fire Time: ' + job.PreviousFireTime);
            System.debug('---');
        }
    }

    /**
     * @description Run the lead reassignment immediately (for testing)
     *              Call this from Anonymous Apex: LeadReassignmentScheduler.runNow();
     */
    public static void runNow() {
        ScheduledLeadReassignment job = new ScheduledLeadReassignment();
        Database.executeBatch(job, 200);
        System.debug('Lead reassignment batch started immediately');
    }
}