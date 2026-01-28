/**
 * Simple class to control trigger recursion
 */
public class TriggerRecursionControl {
    // ==================================================================================
    // DEBUG LOGGING CONSTANTS
    // ==================================================================================
    private static final String LOG_PREFIX = '[TriggerRecursionControl]';
    private static final String LOG_DEBUG = '🔧';

    // Flag to prevent recursion when recalculating draft numbers
    public static Boolean isRecalculatingDraftNumbers {
        get {
            if (isRecalculatingDraftNumbers == null) {
                isRecalculatingDraftNumbers = false;
            }
            return isRecalculatingDraftNumbers;
        }
        set {
            System.debug(LOG_PREFIX + ' ' + LOG_DEBUG + ' isRecalculatingDraftNumbers set to: ' + value);
            isRecalculatingDraftNumbers = value;
        }
    }
}