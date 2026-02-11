/**
 * @description Test class for minimal NegotiationController
 */
@IsTest
public class NegotiationControllerTest {
    
    @IsTest
    static void testGetStatus() {
        Test.startTest();
        String result = NegotiationController.getStatus();
        Test.stopTest();
        
        System.assertEquals('inactive', result, 'Should return inactive status');
    }
    
    @IsTest
    static void testIsActive() {
        Test.startTest();
        Boolean result = NegotiationController.isActive();
        Test.stopTest();
        
        System.assertEquals(false, result, 'Should return false');
    }
}