public with sharing class WelcomeTeamEventsController {

    /**
     * Get upcoming Welcome Team Calendly events (non-cancelled)
     * Returns the next 10 future events starting from current time, sorted by soonest first
     */
    @AuraEnabled(cacheable=true)
    public static List<Calendly__CalendlyAction__c> getWelcomeTeamEvents() {
        return [
            SELECT
                Id,
                Name,
                Calendly__InviteeName__c,
                Calendly__EventStartTime__c,
                Calendly__EventEndTime__c,
                Calendly__EventSubject__c,
                Calendly__EventTypeName__c
            FROM Calendly__CalendlyAction__c
            WHERE Calendly__EventPrimaryPublisherName__c = 'Welcome Team'
                AND Calendly__EventCanceled__c = false
                AND Calendly__InviteeCanceled__c = false
                AND Calendly__EventStartTime__c > :System.now()
            ORDER BY Calendly__EventStartTime__c ASC
            LIMIT 10
        ];
    }

    /**
     * Get total count of upcoming Welcome Team events (non-cancelled)
     * Only counts future events starting from current time
     */
    @AuraEnabled(cacheable=true)
    public static Integer getWelcomeTeamEventsCount() {
        return [
            SELECT COUNT()
            FROM Calendly__CalendlyAction__c
            WHERE Calendly__EventPrimaryPublisherName__c = 'Welcome Team'
                AND Calendly__EventCanceled__c = false
                AND Calendly__InviteeCanceled__c = false
                AND Calendly__EventStartTime__c > :System.now()
        ];
    }
}