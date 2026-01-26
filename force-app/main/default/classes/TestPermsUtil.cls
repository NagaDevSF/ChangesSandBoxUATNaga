@IsTest
public class TestPermsUtil {
    /**
     * Creates and returns a SysAdmin user for running SECURITY_ENFORCED paths.
     * Uses Test.getRunId() to keep usernames unique in parallel runs.
     */
    public static User createSysAdminUser() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String runId = String.valueOf(DateTime.now().getTime());
        User u = new User(
            FirstName = 'Test',
            LastName = 'SysAdmin',
            Alias = ('tsa' + runId).left(8),
            Email = 'sysadmin+' + runId + '@example.com',
            Username = 'sysadmin+' + runId + '@example.com',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = adminProfile.Id
        );
        insert u;
        return u;
    }
}