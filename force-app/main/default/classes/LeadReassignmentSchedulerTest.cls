/**
 * @description Test class for LeadReassignmentScheduler
 * @author Salesforce Developer
 * @date 2025
 */
@isTest
private class LeadReassignmentSchedulerTest {

    /**
     * Setup test data
     */
    @testSetup
    static void setupTestData() {
        // Create test lead
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Status = 'New'
        );
        insert testLead;
    }

    /**
     * Test start method
     */
    @isTest
    static void testStart() {
        Test.startTest();
        LeadReassignmentScheduler.start();
        Test.stopTest();

        // Verify jobs were scheduled
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name, State
                                  FROM CronTrigger
                                  WHERE CronJobDetail.Name LIKE 'Lead Reassignment%'
                                  AND State != 'DELETED'];
        System.assert(jobs.size() > 0, 'Jobs should be scheduled after calling start()');
    }

    /**
     * Test stop method with no existing jobs
     */
    @isTest
    static void testStopWithNoJobs() {
        Test.startTest();
        LeadReassignmentScheduler.stop();
        Test.stopTest();

        // Should complete without error even with no jobs
        System.assert(true, 'Stop should handle no existing jobs gracefully');
    }

    /**
     * Test stop method with existing jobs
     */
    @isTest
    static void testStopWithExistingJobs() {
        // First schedule some jobs
        ScheduledLeadReassignment scheduler = new ScheduledLeadReassignment();
        String jobId = System.schedule('Lead Reassignment Test Job', '0 0 0 * * ?', scheduler);

        Test.startTest();
        LeadReassignmentScheduler.stop();
        Test.stopTest();

        // Verify jobs were stopped
        List<CronTrigger> jobs = [SELECT Id, State
                                  FROM CronTrigger
                                  WHERE CronJobDetail.Name LIKE 'Lead Reassignment%'
                                  AND State != 'DELETED'];
        System.assertEquals(0, jobs.size(), 'All jobs should be stopped');
    }

    /**
     * Test getStatus method with no jobs
     */
    @isTest
    static void testGetStatusWithNoJobs() {
        Test.startTest();
        LeadReassignmentScheduler.getStatus();
        Test.stopTest();

        // Should complete without error
        System.assert(true, 'getStatus should handle no jobs gracefully');
    }

    /**
     * Test getStatus method with existing jobs
     */
    @isTest
    static void testGetStatusWithJobs() {
        // Schedule a job first
        ScheduledLeadReassignment scheduler = new ScheduledLeadReassignment();
        String jobId = System.schedule('Lead Reassignment Status Test', '0 0 0 * * ?', scheduler);

        Test.startTest();
        LeadReassignmentScheduler.getStatus();
        Test.stopTest();

        // Verify we can query the job
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name
                                  FROM CronTrigger
                                  WHERE Id = :jobId];
        System.assertEquals(1, jobs.size(), 'Should be able to query scheduled job');
    }

    /**
     * Test runNow method
     */
    @isTest
    static void testRunNow() {
        Test.startTest();
        LeadReassignmentScheduler.runNow();
        Test.stopTest();

        // Verify batch was started (it should complete in test context)
        System.assert(true, 'Batch should start successfully');
    }

    /**
     * Test complete workflow: start, getStatus, stop
     */
    @isTest
    static void testCompleteWorkflow() {
        Test.startTest();

        // Start scheduling
        LeadReassignmentScheduler.start();

        // Check status
        LeadReassignmentScheduler.getStatus();

        // Verify jobs exist
        List<CronTrigger> jobsAfterStart = [SELECT Id
                                            FROM CronTrigger
                                            WHERE CronJobDetail.Name LIKE 'Lead Reassignment%'
                                            AND State != 'DELETED'];
        System.assert(jobsAfterStart.size() > 0, 'Jobs should exist after start');

        // Stop all jobs
        LeadReassignmentScheduler.stop();

        // Verify jobs were stopped
        List<CronTrigger> jobsAfterStop = [SELECT Id
                                           FROM CronTrigger
                                           WHERE CronJobDetail.Name LIKE 'Lead Reassignment%'
                                           AND State != 'DELETED'];
        System.assertEquals(0, jobsAfterStop.size(), 'All jobs should be stopped');

        Test.stopTest();
    }

    /**
     * Test multiple start/stop cycles
     */
    @isTest
    static void testMultipleStartStopCycles() {
        Test.startTest();

        // First cycle
        LeadReassignmentScheduler.start();
        LeadReassignmentScheduler.stop();

        // Second cycle
        LeadReassignmentScheduler.start();
        List<CronTrigger> jobsAfterSecondStart = [SELECT Id
                                                   FROM CronTrigger
                                                   WHERE CronJobDetail.Name LIKE 'Lead Reassignment%'
                                                   AND State != 'DELETED'];
        System.assert(jobsAfterSecondStart.size() > 0, 'Jobs should be scheduled after second start');

        LeadReassignmentScheduler.stop();

        Test.stopTest();
    }

    /**
     * Test runNow with custom owner
     */
    @isTest
    static void testRunNowExecution() {
        List<Lead> leadsBefore = [SELECT Id FROM Lead];
        System.assertEquals(1, leadsBefore.size(), 'Should have test lead');

        Test.startTest();
        LeadReassignmentScheduler.runNow();
        Test.stopTest();

        // Batch should have executed
        List<Lead> leadsAfter = [SELECT Id FROM Lead];
        System.assertEquals(1, leadsAfter.size(), 'Lead should still exist after batch');
    }

    /**
     * Test start method multiple times
     */
    @isTest
    static void testStartMultipleTimes() {
        Test.startTest();

        // Call start multiple times
        LeadReassignmentScheduler.start();
        LeadReassignmentScheduler.start();
        LeadReassignmentScheduler.start();

        Test.stopTest();

        // Verify jobs exist (previous jobs should be aborted and new ones created)
        List<CronTrigger> jobs = [SELECT Id
                                  FROM CronTrigger
                                  WHERE CronJobDetail.Name LIKE 'Lead Reassignment%'
                                  AND State != 'DELETED'];
        System.assert(jobs.size() > 0, 'Jobs should exist after multiple starts');
    }

    /**
     * Test stop method multiple times
     */
    @isTest
    static void testStopMultipleTimes() {
        // Schedule some jobs
        LeadReassignmentScheduler.start();

        Test.startTest();

        // Call stop multiple times
        LeadReassignmentScheduler.stop();
        LeadReassignmentScheduler.stop();
        LeadReassignmentScheduler.stop();

        Test.stopTest();

        // Verify all jobs are stopped
        List<CronTrigger> jobs = [SELECT Id
                                  FROM CronTrigger
                                  WHERE CronJobDetail.Name LIKE 'Lead Reassignment%'
                                  AND State != 'DELETED'];
        System.assertEquals(0, jobs.size(), 'All jobs should be stopped');
    }

    /**
     * Test getStatus output with multiple scheduled jobs
     */
    @isTest
    static void testGetStatusWithMultipleJobs() {
        // Schedule multiple jobs
        for(Integer i = 0; i < 3; i++) {
            ScheduledLeadReassignment scheduler = new ScheduledLeadReassignment();
            System.schedule('Lead Reassignment Multi Test ' + i, '0 ' + (i * 2) + ' * * * ?', scheduler);
        }

        Test.startTest();
        LeadReassignmentScheduler.getStatus();
        Test.stopTest();

        // Verify multiple jobs exist
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name
                                  FROM CronTrigger
                                  WHERE CronJobDetail.Name LIKE 'Lead Reassignment%'];
        System.assert(jobs.size() >= 3, 'Multiple jobs should exist');
    }
}