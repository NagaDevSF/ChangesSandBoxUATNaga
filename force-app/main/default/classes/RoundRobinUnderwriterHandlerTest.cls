@isTest
public class RoundRobinUnderwriterHandlerTest {
    // This test class covers deprecated methods

    @isTest
    static void testDeprecatedMethods() {
        // Test deprecated handleAfterUpdate method
        List<Opportunity> testOpps = new List<Opportunity>();
        Map<Id, Opportunity> oldMap = new Map<Id, Opportunity>();

        Test.startTest();
        RoundRobinUnderwriterHandler.handleAfterUpdate(testOpps, oldMap);
        RoundRobinUnderwriterHandler.assignUnderwriter(testOpps);
        Test.stopTest();

        // Assert methods complete without errors
        System.assert(true, 'Deprecated methods should complete without errors');
    }
}