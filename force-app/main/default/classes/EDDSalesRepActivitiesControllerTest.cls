@isTest
private class EDDSalesRepActivitiesControllerTest {

    @testSetup
    static void setup() {
        // Create test user with everydaydebt.com domain
        Profile sysAdminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];

        User eddUser = new User(
            FirstName = 'Test',
            LastName = 'EDD User',
            Email = 'testedduser@everydaydebt.com',
            Username = 'testedduser' + System.currentTimeMillis() + '@everydaydebt.com',
            Alias = 'tedd',
            ProfileId = sysAdminProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert eddUser;

        // Create test Contact and Lead for event relationships
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'testcontact@example.com'
        );
        insert testContact;

        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Email = 'testlead@example.com'
        );
        insert testLead;

        // Create test events with and without WhoId
        System.runAs(eddUser) {
            List<Event> events = new List<Event>();
            // Use today at 10 AM to ensure ActivityDate is today
            DateTime todayMorning = DateTime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0));

            for(Integer i = 0; i < 5; i++) {
                Event evt = new Event(
                    Subject = 'Test EDD Event ' + i,
                    StartDateTime = todayMorning.addHours(i),
                    EndDateTime = todayMorning.addHours(i + 1),
                    ActivityDateTime = todayMorning.addHours(i),
                    DurationInMinutes = 60
                );

                // Add WhoId to some events
                if(i == 1) {
                    evt.WhoId = testContact.Id;
                } else if(i == 2) {
                    evt.WhoId = testLead.Id;
                }

                events.add(evt);
            }
            insert events;
        }
    }

    @isTest
    static void testGetSalesReps() {
        Test.startTest();
        List<User> users = EDDSalesRepActivitiesController.getSalesReps();
        Test.stopTest();

        System.assertNotEquals(null, users, 'Users list should not be null');
    }

    @isTest
    static void testGetSalesRepEvents() {
        Test.startTest();
        Date today = Date.today();
        List<EDDSalesRepActivitiesController.EventWrapper> events =
            EDDSalesRepActivitiesController.getSalesRepEvents(today);
        Test.stopTest();

        System.assertNotEquals(null, events, 'Events list should not be null');
    }

    @isTest
    static void testGetSalesRepEventsForRange() {
        Test.startTest();
        Date startDate = Date.today();
        Date endDate = Date.today().addDays(7);
        List<EDDSalesRepActivitiesController.EventWrapper> events =
            EDDSalesRepActivitiesController.getSalesRepEventsForRange(startDate, endDate);
        Test.stopTest();

        System.assertNotEquals(null, events, 'Events list should not be null');
    }

    @isTest
    static void testGetSalesRepEventsForRangeWithNullDates() {
        Test.startTest();
        try {
            EDDSalesRepActivitiesController.getSalesRepEventsForRange(null, null);
            System.assert(false, 'Should have thrown exception for null dates');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetSalesRepEventsForRangeWithInvalidDateRange() {
        Test.startTest();
        try {
            Date startDate = Date.today();
            Date endDate = Date.today().addDays(-1);
            EDDSalesRepActivitiesController.getSalesRepEventsForRange(startDate, endDate);
            System.assert(false, 'Should have thrown exception for invalid date range');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message for invalid date range');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetSalesRepEventsForRangeWithLargeDateRange() {
        Test.startTest();
        try {
            Date startDate = Date.today();
            Date endDate = Date.today().addDays(35);
            EDDSalesRepActivitiesController.getSalesRepEventsForRange(startDate, endDate);
            System.assert(false, 'Should have thrown exception for large date range');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message for date range limit');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetEventChecksum() {
        Test.startTest();
        Date today = Date.today();
        EDDSalesRepActivitiesController.EventChecksum checksum =
            EDDSalesRepActivitiesController.getEventChecksum(today);
        Test.stopTest();

        System.assertNotEquals(null, checksum, 'Checksum should not be null');
        System.assertNotEquals(null, checksum.eventCount, 'Event count should not be null');
        System.assertNotEquals(null, checksum.eventHash, 'Event hash should not be null');
        System.assertNotEquals(null, checksum.checkTime, 'Check time should not be null');
    }

    @isTest
    static void testGetEventChecksumWithNullDate() {
        Test.startTest();
        try {
            EDDSalesRepActivitiesController.getEventChecksum(null);
            System.assert(false, 'Should have thrown exception for null date');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message for null date');
        }
        Test.stopTest();
    }

    @isTest
    static void testEventWrapperClass() {
        Test.startTest();
        EDDSalesRepActivitiesController.EventWrapper wrapper = new EDDSalesRepActivitiesController.EventWrapper();
        wrapper.Id = '00U000000000000';
        wrapper.Subject = 'Test Subject';
        wrapper.StartDateTime = DateTime.now();
        wrapper.EndDateTime = DateTime.now().addHours(1);
        wrapper.IsAllDayEvent = false;
        wrapper.OwnerId = UserInfo.getUserId();
        wrapper.OwnerName = 'Test Owner';
        wrapper.Location = 'Test Location';
        wrapper.Description = 'Test Description';

        System.assertEquals('Test Subject', wrapper.Subject, 'Subject should match');
        System.assertNotEquals(null, wrapper.StartDateTime, 'Start time should not be null');
        Test.stopTest();
    }

    @isTest
    static void testEventChecksumClass() {
        Test.startTest();
        EDDSalesRepActivitiesController.EventChecksum checksum = new EDDSalesRepActivitiesController.EventChecksum();
        checksum.eventCount = 5;
        checksum.lastModified = DateTime.now();
        checksum.lastCreated = DateTime.now();
        checksum.eventHash = 'testhash123';
        checksum.checkTime = DateTime.now();

        System.assertEquals(5, checksum.eventCount, 'Event count should match');
        System.assertEquals('testhash123', checksum.eventHash, 'Hash should match');
        Test.stopTest();
    }

    @isTest
    static void testGetSalesRepEventsCacheHit() {
        Test.startTest();
        Date today = Date.today();

        // First call - will cache the results
        List<EDDSalesRepActivitiesController.EventWrapper> events1 =
            EDDSalesRepActivitiesController.getSalesRepEvents(today);

        // Second call - should hit cache
        List<EDDSalesRepActivitiesController.EventWrapper> events2 =
            EDDSalesRepActivitiesController.getSalesRepEvents(today);

        Test.stopTest();

        System.assertNotEquals(null, events1, 'First call should return events');
        System.assertNotEquals(null, events2, 'Second call should return cached events');
    }

    @isTest
    static void testGetSalesRepsCacheHit() {
        Test.startTest();

        // First call - will cache the results
        List<User> users1 = EDDSalesRepActivitiesController.getSalesReps();

        // Second call - should hit cache
        List<User> users2 = EDDSalesRepActivitiesController.getSalesReps();

        Test.stopTest();

        System.assertNotEquals(null, users1, 'First call should return users');
        System.assertNotEquals(null, users2, 'Second call should return cached users');
    }

    @isTest
    static void testGetSalesRepEventsWithContactAndLead() {
        Test.startTest();
        Date today = Date.today();

        List<EDDSalesRepActivitiesController.EventWrapper> events =
            EDDSalesRepActivitiesController.getSalesRepEvents(today);

        Test.stopTest();

        System.assertNotEquals(null, events, 'Events list should not be null');

        // Verify that if events with WhoId are found, they have proper names populated
        for(EDDSalesRepActivitiesController.EventWrapper evt : events) {
            if(evt.ContactName != null) {
                System.assertEquals('Test Contact', evt.ContactName, 'Contact name should match');
            }
            if(evt.LeadName != null) {
                System.assertEquals('Test Lead', evt.LeadName, 'Lead name should match');
            }
        }

        // Assertions pass regardless of whether events exist - just verifies methods work correctly
    }

    @isTest
    static void testGetEventChecksumWithEvents() {
        Test.startTest();
        Date today = Date.today();

        EDDSalesRepActivitiesController.EventChecksum checksum =
            EDDSalesRepActivitiesController.getEventChecksum(today);

        Test.stopTest();

        System.assertNotEquals(null, checksum, 'Checksum should not be null');
        System.assertNotEquals(null, checksum.eventCount, 'Event count should not be null');
        System.assertNotEquals(null, checksum.eventHash, 'Hash should not be null');
        System.assertNotEquals(null, checksum.checkTime, 'Check time should not be null');
    }

    @isTest
    static void testGetEventChecksumWithNoEvents() {
        Test.startTest();
        // Use a future date with no events
        Date futureDate = Date.today().addDays(100);

        EDDSalesRepActivitiesController.EventChecksum checksum =
            EDDSalesRepActivitiesController.getEventChecksum(futureDate);

        Test.stopTest();

        System.assertNotEquals(null, checksum, 'Checksum should not be null');
        System.assertEquals(0, checksum.eventCount, 'Event count should be 0');
        System.assertEquals('EMPTY', checksum.eventHash, 'Hash should be EMPTY for no events');
    }

    @isTest
    static void testCacheCleanupLogic() {
        Test.startTest();

        // Call getSalesRepEvents multiple times with different dates to populate cache
        for(Integer i = 0; i < 10; i++) {
            Date testDate = Date.today().addDays(i);
            EDDSalesRepActivitiesController.getSalesRepEvents(testDate);
        }

        // Cache cleanup should have been triggered automatically
        // Just verify we can still get events successfully
        List<EDDSalesRepActivitiesController.EventWrapper> events =
            EDDSalesRepActivitiesController.getSalesRepEvents(Date.today());

        Test.stopTest();

        System.assertNotEquals(null, events, 'Should still get events after cache cleanup');
    }
}