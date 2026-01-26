@isTest
private class SalesRepActivitiesControllerTest {
    
    @testSetup
    static void setup() {
        // Create test users with proper profiles
        Profile salesRepProfile = [SELECT Id FROM Profile WHERE Name = 'Sales Rep' LIMIT 1];
        Profile sysAdminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        
        User salesRep = new User(
            FirstName = 'Test',
            LastName = 'Sales Rep',
            Email = 'testsalesrep@dcgpro.com',
            Username = 'testsalesrep@dcgpro.com.test' + System.currentTimeMillis(),
            Alias = 'tsrep',
            ProfileId = salesRepProfile != null ? salesRepProfile.Id : sysAdminProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert salesRep;
        
        // Create test events
        System.runAs(salesRep) {
            List<Event> events = new List<Event>();
            DateTime now = DateTime.now();
            
            for(Integer i = 0; i < 5; i++) {
                events.add(new Event(
                    Subject = 'Test Event ' + i,
                    StartDateTime = now.addHours(i),
                    EndDateTime = now.addHours(i + 1),
                    ActivityDateTime = now.addHours(i)
                ));
            }
            insert events;
        }
    }
    
    @isTest
    static void testGetSalesReps() {
        Test.startTest();
        List<User> users = SalesRepActivitiesController.getSalesReps();
        Test.stopTest();
        
        System.assertNotEquals(null, users, 'Users list should not be null');
    }
    
    @isTest
    static void testGetSalesRepEvents() {
        Test.startTest();
        Date today = Date.today();
        List<SalesRepActivitiesController.EventWrapper> events = 
            SalesRepActivitiesController.getSalesRepEvents(today);
        Test.stopTest();
        
        System.assertNotEquals(null, events, 'Events list should not be null');
    }
    
    @isTest
    static void testGetSalesRepEventsForRange() {
        Test.startTest();
        Date startDate = Date.today();
        Date endDate = Date.today().addDays(7);
        List<SalesRepActivitiesController.EventWrapper> events = 
            SalesRepActivitiesController.getSalesRepEventsForRange(startDate, endDate);
        Test.stopTest();
        
        System.assertNotEquals(null, events, 'Events list should not be null');
    }
    
    @isTest
    static void testGetSalesRepEventsForRangeWithNullDates() {
        Test.startTest();
        try {
            SalesRepActivitiesController.getSalesRepEventsForRange(null, null);
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
            SalesRepActivitiesController.getSalesRepEventsForRange(startDate, endDate);
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
            SalesRepActivitiesController.getSalesRepEventsForRange(startDate, endDate);
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
        SalesRepActivitiesController.EventChecksum checksum = 
            SalesRepActivitiesController.getEventChecksum(today);
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
            SalesRepActivitiesController.getEventChecksum(null);
            System.assert(false, 'Should have thrown exception for null date');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message for null date');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testEventWrapperClass() {
        Test.startTest();
        SalesRepActivitiesController.EventWrapper wrapper = new SalesRepActivitiesController.EventWrapper();
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
        SalesRepActivitiesController.EventChecksum checksum = new SalesRepActivitiesController.EventChecksum();
        checksum.eventCount = 5;
        checksum.lastModified = DateTime.now();
        checksum.lastCreated = DateTime.now();
        checksum.eventHash = 'testhash123';
        checksum.checkTime = DateTime.now();
        
        System.assertEquals(5, checksum.eventCount, 'Event count should match');
        System.assertEquals('testhash123', checksum.eventHash, 'Hash should match');
        Test.stopTest();
    }
}