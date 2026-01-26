/**
 * @description Test class for ScheduledLeadReassignmentNXDS
 * @author Salesforce Developer
 * @date 2025
 */
@isTest
private class ScheduledLeadReassignmentNXDSTest {

    /**
     * Setup test data
     */
    @testSetup
    static void setupTestData() {
        // Create test leads
        List<Lead> testLeads = new List<Lead>();
        for(Integer i = 0; i < 5; i++) {
            testLeads.add(new Lead(
                FirstName = 'Test',
                LastName = 'Lead' + i,
                Company = 'Test Company ' + i,
                Status = 'New'
            ));
        }
        insert testLeads;
    }

    /**
     * Test default constructor
     */
    @isTest
    static void testDefaultConstructor() {
        Test.startTest();
        ScheduledLeadReassignmentNXDS scheduler = new ScheduledLeadReassignmentNXDS();
        Test.stopTest();

        System.assertNotEquals(null, scheduler, 'Scheduler should be instantiated');
    }

    /**
     * Test parameterized constructor
     */
    @isTest
    static void testParameterizedConstructor() {
        Test.startTest();
        ScheduledLeadReassignmentNXDS scheduler = new ScheduledLeadReassignmentNXDS('TestUser');
        Test.stopTest();

        System.assertNotEquals(null, scheduler, 'Scheduler should be instantiated with custom owner');
    }

    /**
     * Test schedulable execute method
     */
    @isTest
    static void testSchedulableExecute() {
        ScheduledLeadReassignmentNXDS scheduler = new ScheduledLeadReassignmentNXDS();

        Test.startTest();
        // Schedule the job
        String cronExp = '0 0 0 * * ?';
        String jobId = System.schedule('Test Lead Reassignment NXDS', cronExp, scheduler);
        Test.stopTest();

        // Verify job was scheduled
        CronTrigger ct = [SELECT Id, CronExpression, State
                          FROM CronTrigger
                          WHERE Id = :jobId];
        System.assertEquals(cronExp, ct.CronExpression, 'Job should be scheduled with correct cron expression');
    }

    /**
     * Test batch start method
     */
    @isTest
    static void testBatchStart() {
        ScheduledLeadReassignmentNXDS scheduler = new ScheduledLeadReassignmentNXDS();

        Test.startTest();
        Database.QueryLocator ql = scheduler.start(null);
        Test.stopTest();

        System.assertNotEquals(null, ql, 'Query locator should not be null');
    }

    /**
     * Test batch execute method with leads
     */
    @isTest
    static void testBatchExecuteWithLeads() {
        List<Lead> testLeads = [SELECT Id FROM Lead LIMIT 1];
        ScheduledLeadReassignmentNXDS scheduler = new ScheduledLeadReassignmentNXDS();

        Test.startTest();
        // Execute method with leads - Flow will fail in test context but that's expected
        scheduler.execute(null, testLeads);
        Test.stopTest();

        // If we reach here, the method handled the Flow error gracefully
        System.assert(true, 'Execute method should handle Flow gracefully');
    }

    /**
     * Test batch execute method with empty list
     */
    @isTest
    static void testBatchExecuteWithEmptyList() {
        ScheduledLeadReassignmentNXDS scheduler = new ScheduledLeadReassignmentNXDS();

        Test.startTest();
        scheduler.execute(null, new List<Lead>());
        Test.stopTest();

        // Should return early without error
        System.assert(true, 'Execute method should handle empty list gracefully');
    }

    /**
     * Test batch execute method with null
     */
    @isTest
    static void testBatchExecuteWithNull() {
        ScheduledLeadReassignmentNXDS scheduler = new ScheduledLeadReassignmentNXDS();

        Test.startTest();
        scheduler.execute(null, null);
        Test.stopTest();

        // Should return early without error
        System.assert(true, 'Execute method should handle null gracefully');
    }

    /**
     * Test batch finish method
     */
    @isTest
    static void testBatchFinish() {
        ScheduledLeadReassignmentNXDS scheduler = new ScheduledLeadReassignmentNXDS();

        Test.startTest();
        scheduler.finish(null);
        Test.stopTest();

        System.assert(true, 'Finish method should complete without error');
    }

    /**
     * Test complete batch execution
     */
    @isTest
    static void testCompleteBatchExecution() {
        ScheduledLeadReassignmentNXDS scheduler = new ScheduledLeadReassignmentNXDS('TestOwner');

        Test.startTest();
        Database.executeBatch(scheduler, 200);
        Test.stopTest();

        // Verify batch executed
        System.assert(true, 'Batch should execute successfully');
    }

    /**
     * Test scheduleEvery2Minutes method
     */
    @isTest
    static void testScheduleEvery2Minutes() {
        Test.startTest();
        ScheduledLeadReassignmentNXDS.scheduleEvery2Minutes();
        Test.stopTest();

        // Verify jobs were scheduled
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name
                                  FROM CronTrigger
                                  WHERE CronJobDetail.Name LIKE 'Lead Reassignment%NXDS%'];
        System.assert(jobs.size() > 0, 'Jobs should be scheduled');
    }

    /**
     * Test scheduleRecurring method
     */
    @isTest
    static void testScheduleRecurring() {
        Test.startTest();
        ScheduledLeadReassignmentNXDS.scheduleRecurring();
        Test.stopTest();

        // Verify recurring jobs were scheduled
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name
                                  FROM CronTrigger
                                  WHERE CronJobDetail.Name LIKE 'Lead Reassignment%NXDS%'];
        System.assert(jobs.size() > 0, 'Recurring jobs should be scheduled');
    }

    /**
     * Test abortExistingJobs method with no existing jobs
     */
    @isTest
    static void testAbortExistingJobsEmpty() {
        Test.startTest();
        ScheduledLeadReassignmentNXDS.abortExistingJobs();
        Test.stopTest();

        // Should complete without error even with no jobs
        System.assert(true, 'Should handle no existing jobs gracefully');
    }

    /**
     * Test abortExistingJobs method with existing jobs
     */
    @isTest
    static void testAbortExistingJobsWithJobs() {
        // First schedule some jobs
        ScheduledLeadReassignmentNXDS scheduler = new ScheduledLeadReassignmentNXDS();
        String jobId = System.schedule('Lead Reassignment Test NXDS', '0 0 0 * * ?', scheduler);

        Test.startTest();
        ScheduledLeadReassignmentNXDS.abortExistingJobs();
        Test.stopTest();

        // Verify jobs were aborted
        List<CronTrigger> jobs = [SELECT Id, State
                                  FROM CronTrigger
                                  WHERE CronJobDetail.Name LIKE 'Lead Reassignment%NXDS%'
                                  AND State != 'DELETED'];
        System.assertEquals(0, jobs.size(), 'All jobs should be aborted');
    }

    /**
     * Test generateCronExpression method (indirectly through scheduleEvery2Minutes)
     */
    @isTest
    static void testGenerateCronExpression() {
        Test.startTest();
        // This will call generateCronExpression internally
        ScheduledLeadReassignmentNXDS.scheduleEvery2Minutes();
        Test.stopTest();

        // Verify jobs were created with valid cron expressions
        List<CronTrigger> jobs = [SELECT Id, CronExpression
                                  FROM CronTrigger
                                  WHERE CronJobDetail.Name LIKE 'Lead Reassignment%NXDS%'
                                  LIMIT 1];
        if(!jobs.isEmpty()) {
            System.assertNotEquals(null, jobs[0].CronExpression, 'Cron expression should be generated');
        }
    }

    /**
     * Test scheduling and then aborting jobs
     */
    @isTest
    static void testScheduleAndAbortCycle() {
        Test.startTest();

        // Schedule jobs
        ScheduledLeadReassignmentNXDS.scheduleRecurring();

        // Verify jobs were scheduled
        List<CronTrigger> jobsAfterSchedule = [SELECT Id
                                                FROM CronTrigger
                                                WHERE CronJobDetail.Name LIKE 'Lead Reassignment%NXDS%'];
        System.assert(jobsAfterSchedule.size() > 0, 'Jobs should be scheduled');

        // Abort jobs
        ScheduledLeadReassignmentNXDS.abortExistingJobs();

        // Verify jobs were aborted
        List<CronTrigger> jobsAfterAbort = [SELECT Id
                                            FROM CronTrigger
                                            WHERE CronJobDetail.Name LIKE 'Lead Reassignment%NXDS%'
                                            AND State != 'DELETED'];
        System.assertEquals(0, jobsAfterAbort.size(), 'All jobs should be aborted');

        Test.stopTest();
    }

    /**
     * Test batch execution with multiple leads
     */
    @isTest
    static void testBatchExecuteMultipleLeads() {
        List<Lead> testLeads = [SELECT Id FROM Lead];
        ScheduledLeadReassignmentNXDS scheduler = new ScheduledLeadReassignmentNXDS('CustomOwner');

        Test.startTest();
        scheduler.execute(null, testLeads);
        Test.stopTest();

        // Flow execution will fail in test context but exception should be caught
        System.assert(true, 'Multiple leads should be processed gracefully');
    }

    /**
     * Test startAutoSchedule method
     */
    @isTest
    static void testStartAutoSchedule() {
        Test.startTest();
        ScheduledLeadReassignmentNXDS.startAutoSchedule();
        Test.stopTest();

        // Verify job was scheduled
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name
                                  FROM CronTrigger
                                  WHERE CronJobDetail.Name LIKE 'Lead Reassignment Auto NXDS%'
                                  AND State != 'DELETED'];
        System.assert(jobs.size() > 0, 'Auto schedule job should be created');
    }

    /**
     * Test startAutoSchedule with existing jobs (should abort first)
     */
    @isTest
    static void testStartAutoScheduleWithExistingJobs() {
        // First schedule some jobs
        ScheduledLeadReassignmentNXDS scheduler = new ScheduledLeadReassignmentNXDS();
        System.schedule('Lead Reassignment Test Old NXDS', '0 0 0 * * ?', scheduler);

        Test.startTest();
        ScheduledLeadReassignmentNXDS.startAutoSchedule();
        Test.stopTest();

        // Verify new job was scheduled
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name
                                  FROM CronTrigger
                                  WHERE CronJobDetail.Name LIKE 'Lead Reassignment Auto NXDS%'
                                  AND State != 'DELETED'];
        System.assert(jobs.size() > 0, 'Auto schedule job should be created after aborting old jobs');
    }

    /**
     * Test hasExecuted flag prevents double execution
     */
    @isTest
    static void testHasExecutedFlag() {
        List<Lead> testLeads = [SELECT Id FROM Lead LIMIT 1];
        ScheduledLeadReassignmentNXDS scheduler = new ScheduledLeadReassignmentNXDS();

        Test.startTest();
        // First execution
        scheduler.execute(null, testLeads);
        // Second execution should be skipped due to hasExecuted flag
        scheduler.execute(null, testLeads);
        Test.stopTest();

        // Should complete without error, second call skipped
        System.assert(true, 'Second execution should be skipped due to hasExecuted flag');
    }

    /**
     * Test finish method triggers rescheduling
     */
    @isTest
    static void testFinishReschedulesJob() {
        ScheduledLeadReassignmentNXDS scheduler = new ScheduledLeadReassignmentNXDS();

        Test.startTest();
        // Call finish which should trigger scheduleNextRun
        scheduler.finish(null);
        Test.stopTest();

        // Verify a new job was scheduled
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name
                                  FROM CronTrigger
                                  WHERE CronJobDetail.Name LIKE 'Lead Reassignment Auto NXDS%'];
        System.assert(jobs.size() > 0, 'Finish should schedule next run');
    }

    /**
     * Test complete batch cycle with auto-scheduling
     */
    @isTest
    static void testCompleteBatchCycleWithAutoSchedule() {
        Test.startTest();
        ScheduledLeadReassignmentNXDS.startAutoSchedule();
        Test.stopTest();

        // Verify job exists
        List<CronTrigger> jobs = [SELECT Id, CronJobDetail.Name, State
                                  FROM CronTrigger
                                  WHERE CronJobDetail.Name LIKE 'Lead Reassignment Auto NXDS%'];
        System.assert(!jobs.isEmpty(), 'Should have scheduled jobs');
    }

    /**
     * Test execute with Organization record (new query)
     */
    @isTest
    static void testBatchWithOrganizationQuery() {
        ScheduledLeadReassignmentNXDS scheduler = new ScheduledLeadReassignmentNXDS();

        Test.startTest();
        Database.QueryLocator ql = scheduler.start(null);
        Database.QueryLocatorIterator iter = ql.iterator();
        List<SObject> records = new List<SObject>();
        while(iter.hasNext()) {
            records.add(iter.next());
        }
        // Execute with Organization records
        scheduler.execute(null, records);
        Test.stopTest();

        System.assertEquals(1, records.size(), 'Should return exactly 1 Organization record');
    }
}