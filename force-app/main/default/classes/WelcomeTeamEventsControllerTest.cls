@isTest
private class WelcomeTeamEventsControllerTest {

    @isTest
    static void testGetWelcomeTeamEvents() {
        Test.startTest();
        List<Calendly__CalendlyAction__c> events = WelcomeTeamEventsController.getWelcomeTeamEvents();
        Test.stopTest();

        // Verify the query executed successfully
        System.assertNotEquals(null, events, 'Events list should not be null');
        System.assert(events.size() <= 10, 'Should return maximum 10 events');
    }

    @isTest
    static void testGetWelcomeTeamEventsCount() {
        Test.startTest();
        Integer count = WelcomeTeamEventsController.getWelcomeTeamEventsCount();
        Test.stopTest();

        // Verify the query executed successfully
        System.assertNotEquals(null, count, 'Count should not be null');
        System.assert(count >= 0, 'Count should be non-negative');
    }
}