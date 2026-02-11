public without sharing class EDDSalesRepActivitiesController {
    // Simple in-memory cache to reduce queries
    private static Map<String, List<EventWrapper>> eventCache = new Map<String, List<EventWrapper>>();
    private static Map<String, DateTime> cacheTimestamps = new Map<String, DateTime>();
    private static final Integer CACHE_DURATION_MINUTES = 2;

    @AuraEnabled(cacheable=true)
    public static List<EventWrapper> getSalesRepEvents(Date activityDate) {
        String cacheKey = String.valueOf(activityDate);

        // Check cache first
        if (eventCache.containsKey(cacheKey)) {
            DateTime cachedTime = cacheTimestamps.get(cacheKey);
            if (cachedTime != null && cachedTime.addMinutes(CACHE_DURATION_MINUTES) > DateTime.now()) {
                System.debug('Returning cached events for ' + activityDate);
                return eventCache.get(cacheKey);
            }
        }

        // If not in cache or expired, query and cache
        List<EventWrapper> results = getSalesRepEventsForRange(activityDate, activityDate);
        eventCache.put(cacheKey, results);
        cacheTimestamps.put(cacheKey, DateTime.now());

        // Clean up old cache entries to prevent memory issues
        cleanupCache();

        return results;
    }

    private static void cleanupCache() {
        // Remove cache entries older than 5 minutes
        DateTime cutoffTime = DateTime.now().addMinutes(-5);
        List<String> keysToRemove = new List<String>();

        for (String key : cacheTimestamps.keySet()) {
            if (cacheTimestamps.get(key) < cutoffTime) {
                keysToRemove.add(key);
            }
        }

        for (String key : keysToRemove) {
            eventCache.remove(key);
            cacheTimestamps.remove(key);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<EventWrapper> getSalesRepEventsForRange(Date startDate, Date endDate) {
        try {
            // Validate input dates
            if (startDate == null || endDate == null) {
                throw new AuraHandledException('Start date and end date are required');
            }

            if (startDate > endDate) {
                throw new AuraHandledException('Start date cannot be after end date');
            }

            // Limit date range to prevent performance issues (max 31 days)
            Integer daysBetween = startDate.daysBetween(endDate);
            if (daysBetween > 31) {
                throw new AuraHandledException('Date range cannot exceed 31 days');
            }

            // Optimized query with everydaydebt.com domain - NO PROFILE FILTER
            List<Event> events = [
                SELECT Id, Subject, StartDateTime, EndDateTime, IsAllDayEvent, OwnerId, Owner.Name,
                       WhoId, WhatId, Location, Description, ActivityDateTime
                FROM Event
                WHERE ActivityDate >= :startDate
                AND ActivityDate <= :endDate
                AND StartDateTime != NULL
                AND EndDateTime != NULL
                AND OwnerId IN (
                    SELECT Id
                    FROM User
                    WHERE IsActive = true
                    AND Username LIKE '%everydaydebt.com'
                )
                ORDER BY StartDateTime ASC, OwnerId ASC
                LIMIT 500
            ];

            // Warn if we hit the limit
            if (events.size() == 500) {
                System.debug('WARNING: Hit 500 event limit for date range ' + startDate + ' to ' + endDate + '. Some events may not be displayed.');
            }

            // Get all related Contact and Lead IDs for batch queries
            Set<Id> contactIds = new Set<Id>();
            Set<Id> leadIds = new Set<Id>();

            for (Event evt : events) {
                if (evt.WhoId != null) {
                    String objectType = evt.WhoId.getSObjectType().getDescribe().getName();
                    if (objectType == 'Contact') {
                        contactIds.add(evt.WhoId);
                    } else if (objectType == 'Lead') {
                        leadIds.add(evt.WhoId);
                    }
                }
            }

            // Batch query for related records
            Map<Id, String> contactNames = new Map<Id, String>();
            Map<Id, String> leadNames = new Map<Id, String>();

            if (!contactIds.isEmpty()) {
                for (Contact c : [SELECT Id, Name FROM Contact WHERE Id IN :contactIds]) {
                    contactNames.put(c.Id, c.Name);
                }
            }

            if (!leadIds.isEmpty()) {
                for (Lead l : [SELECT Id, Name FROM Lead WHERE Id IN :leadIds]) {
                    leadNames.put(l.Id, l.Name);
                }
            }

            List<EventWrapper> eventWrappers = new List<EventWrapper>();
            for (Event e : events) {
                EventWrapper ew = new EventWrapper();
                ew.Id = e.Id;
                ew.Subject = e.Subject;
                ew.StartDateTime = e.StartDateTime;
                ew.EndDateTime = e.EndDateTime;
                ew.IsAllDayEvent = e.IsAllDayEvent;
                ew.OwnerId = e.OwnerId;
                ew.OwnerName = e.Owner.Name;
                ew.WhoId = e.WhoId;
                ew.WhatId = e.WhatId;
                ew.Location = e.Location;
                ew.Description = e.Description;
                ew.ActivityDateTime = e.ActivityDateTime;

                // Set Lead or Contact name
                if (e.WhoId != null) {
                    if (contactNames.containsKey(e.WhoId)) {
                        ew.ContactName = contactNames.get(e.WhoId);
                    } else if (leadNames.containsKey(e.WhoId)) {
                        ew.LeadName = leadNames.get(e.WhoId);
                    }
                }

                eventWrappers.add(ew);
            }

            return eventWrappers;

        } catch (Exception ex) {
            System.debug('Error in getSalesRepEventsForRange: ' + ex.getMessage());
            throw new AuraHandledException('Unable to fetch sales rep events: ' + ex.getMessage());
        }
    }

    // Cache for sales reps (they don't change often)
    private static List<User> cachedSalesReps;
    private static DateTime salesRepsCacheTime;

    @AuraEnabled(cacheable=true)
    public static List<User> getSalesReps() {
        try {
            // Check cache first (sales reps don't change often, cache for 10 minutes)
            if (cachedSalesReps != null && salesRepsCacheTime != null &&
                salesRepsCacheTime.addMinutes(10) > DateTime.now()) {
                System.debug('Returning cached sales reps');
                return cachedSalesReps;
            }

            // Query for everydaydebt.com users - NO PROFILE FILTER
            cachedSalesReps = [
                SELECT Id, Name, Email, SmallPhotoUrl, Username
                FROM User
                WHERE IsActive = true
                AND Username LIKE '%everydaydebt.com'
                ORDER BY Name ASC
                LIMIT 100
            ];

            salesRepsCacheTime = DateTime.now();
            return cachedSalesReps;
        } catch (Exception ex) {
            System.debug('Error in getSalesReps: ' + ex.getMessage());
            throw new AuraHandledException('Unable to fetch sales reps: ' + ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static EventChecksum getEventChecksum(Date activityDate) {
        try {
            // Validate input date
            if (activityDate == null) {
                throw new AuraHandledException('Activity date is required');
            }

            EventChecksum checksum = new EventChecksum();

            // OPTIMIZED: Single query to get all checksum data
            AggregateResult[] results = [
                SELECT COUNT(Id) eventCount,
                       MAX(LastModifiedDate) lastModified,
                       MAX(CreatedDate) lastCreated,
                       MAX(Id) maxEventId,
                       MIN(Id) minEventId,
                       SUM(DurationInMinutes) totalDuration
                FROM Event
                WHERE ActivityDate = :activityDate
                AND StartDateTime != NULL
                AND EndDateTime != NULL
                AND OwnerId IN (
                    SELECT Id
                    FROM User
                    WHERE IsActive = true
                    AND Username LIKE '%everydaydebt.com'
                )
            ];

            if (!results.isEmpty()) {
                AggregateResult result = results[0];
                checksum.eventCount = (Integer)result.get('eventCount');
                checksum.lastModified = (DateTime)result.get('lastModified');
                checksum.lastCreated = (DateTime)result.get('lastCreated');

                // Create a lightweight hash using min/max IDs and total duration
                String maxId = (String)result.get('maxEventId');
                String minId = (String)result.get('minEventId');
                Decimal totalDuration = (Decimal)result.get('totalDuration');

                if (maxId != null && minId != null) {
                    String hashInput = minId + '|' + maxId + '|' + checksum.eventCount + '|' +
                                      (totalDuration != null ? totalDuration.toPlainString() : '0');
                    checksum.eventHash = EncodingUtil.convertToHex(
                        Crypto.generateDigest('MD5', Blob.valueOf(hashInput))
                    );
                } else {
                    checksum.eventHash = 'EMPTY';
                }
            } else {
                checksum.eventCount = 0;
                checksum.eventHash = 'EMPTY';
            }

            checksum.checkTime = DateTime.now();

            return checksum;

        } catch (Exception ex) {
            System.debug('Error in getEventChecksum: ' + ex.getMessage());
            throw new AuraHandledException('Unable to get event checksum: ' + ex.getMessage());
        }
    }

    public class EventChecksum {
        @AuraEnabled public Integer eventCount;
        @AuraEnabled public DateTime lastModified;
        @AuraEnabled public DateTime lastCreated;
        @AuraEnabled public String eventHash;
        @AuraEnabled public DateTime checkTime;
    }

    public class EventWrapper {
        @AuraEnabled public Id Id;
        @AuraEnabled public String Subject;
        @AuraEnabled public Datetime StartDateTime;
        @AuraEnabled public Datetime EndDateTime;
        @AuraEnabled public Boolean IsAllDayEvent;
        @AuraEnabled public Id OwnerId;
        @AuraEnabled public String OwnerName;
        @AuraEnabled public Id WhoId;
        @AuraEnabled public String LeadName;
        @AuraEnabled public String ContactName;
        @AuraEnabled public Id WhatId;
        @AuraEnabled public String Location;
        @AuraEnabled public String Description;
        @AuraEnabled public Datetime ActivityDateTime;
    }
}