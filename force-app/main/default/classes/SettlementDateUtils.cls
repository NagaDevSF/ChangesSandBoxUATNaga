/**
 * @description Utility class for date calculations in Settlement Calculator.
 *              Handles business day adjustments, frequency-based date advancement,
 *              and holiday awareness using Salesforce BusinessHours.
 * @lastModified January 2026 - Refactored to use BusinessHours
 *
 * ============================================================================
 * ASSUMPTIONS DOCUMENTED IN THIS FILE:
 * ============================================================================
 * D1 & D2: Weekend and holiday payments move back 2 BUSINESS DAYS using
 *          Salesforce BusinessHours.isWithin() which automatically handles both
 *          weekends AND holidays linked to the "Payment Business Hours" record.
 *          If the original date is already a business day, it returns unchanged.
 * D3: Date spacing uses ORIGINAL date (not adjusted) to prevent drift
 * D4: Semi-Monthly uses 1st/15th pattern (not +15 days)
 * D7: Unknown frequency defaults to Monthly
 * D8: BusinessHours Dependency - Settlement Calculator requires an active 
 *     BusinessHours record named "Payment Business Hours" with holidays linked.
 *     If not configured, calculation will fail with a clear error message.
 * ============================================================================
 */
public with sharing class SettlementDateUtils {

    // Frequency constants
    public static final String FREQ_WEEKLY = 'Weekly';
    public static final String FREQ_BIWEEKLY = 'Bi-Weekly';
    public static final String FREQ_SEMIMONTHLY = 'Semi-Monthly';
    public static final String FREQ_MONTHLY = 'Monthly';

    // Business Hours configuration
    private static final String PAYMENT_BUSINESS_HOURS_NAME = 'Payment Business Hours';
    private static Id paymentBusinessHoursId;
    private static Boolean businessHoursLoaded = false;

    /**
     * @description Get the Payment Business Hours Id (cached for performance)
     * @return Id of the Payment Business Hours record
     * @throws SettlementCalculatorException if BusinessHours not found
     */
    private static Id getPaymentBusinessHoursId() {
        if (!businessHoursLoaded) {
            List<BusinessHours> bhList = [
                SELECT Id 
                FROM BusinessHours 
                WHERE Name = :PAYMENT_BUSINESS_HOURS_NAME 
                AND IsActive = true
                LIMIT 1
            ];
            
            if (bhList.isEmpty()) {
                throw new SettlementCalculatorException(
                    SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                    'Business Hours record "' + PAYMENT_BUSINESS_HOURS_NAME + '" not found or not active. ' +
                    'Please configure Business Hours in Setup > Company Settings > Business Hours.'
                );
            }
            
            paymentBusinessHoursId = bhList[0].Id;
            businessHoursLoaded = true;
        }
        return paymentBusinessHoursId;
    }

    /**
     * @description Check if a date is a business day using BusinessHours
     *              Automatically handles weekends AND holidays linked to Business Hours
     * @param checkDate The date to check
     * @return True if the date is a business day
     */
    public static Boolean isBusinessDay(Date checkDate) {
        if (checkDate == null) {
            return false;
        }
        
        Id bhId = getPaymentBusinessHoursId();
        
        // Use 12:00 PM (noon) to be safely within 9-5 business hours window
        Datetime dt = Datetime.newInstance(checkDate, Time.newInstance(12, 0, 0, 0));
        
        return BusinessHours.isWithin(bhId, dt);
    }

    /**
     * @description Advance a date based on frequency
     * @param currentDate The current date
     * @param frequency The frequency (Weekly, Bi-Weekly, Semi-Monthly, Monthly)
     * @return The next date based on frequency
     */
    public static Date advanceDate(Date currentDate, String frequency) {
        if (currentDate == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.DATE_CALCULATION_ERROR,
                'Current date cannot be null'
            );
        }

        switch on frequency {
            when 'Weekly' {
                return currentDate.addDays(7);
            }
            when 'Bi-Weekly' {
                return currentDate.addDays(14);
            }
            when 'Semi-Monthly' {
                return advanceSemiMonthly(currentDate);
            }
            when 'Monthly' {
                return currentDate.addMonths(1);
            }
            when else {
                // ASSUMPTION D7: Unknown frequency defaults to Monthly
                // If frequency value isn't recognized, we default to monthly rather than throwing an error
                return currentDate.addMonths(1);
            }
        }
    }

    /**
     * @description Advance date for semi-monthly frequency (1st and 15th pattern)
     *              If current date is before 15th, moves to 15th of same month.
     *              If current date is 15th or later, moves to 1st of next month.
     *              Note: If start date is after the 15th (e.g., 20th), it will
     *              skip to 1st of next month, maintaining the 1st/15th pattern.
     *
     * ASSUMPTION D4: Semi-Monthly uses 1st/15th pattern ONLY.
     * - This is standard payroll/finance convention
     * - NOT the same as "every 15 days"
     * - Start on 20th -> jumps to 1st of next month (skips 15th)
     *
     * @param currentDate The current date
     * @return The next semi-monthly date
     */
    private static Date advanceSemiMonthly(Date currentDate) {
        Integer day = currentDate.day();
        Integer month = currentDate.month();
        Integer year = currentDate.year();

        if (day < 15) {
            // Move to 15th of same month
            return Date.newInstance(year, month, 15);
        } else {
            // Move to 1st of next month
            Date nextMonth = currentDate.addMonths(1);
            return Date.newInstance(nextMonth.year(), nextMonth.month(), 1);
        }
    }

    // Maximum days to search for a business day (circuit breaker)
    private static final Integer MAX_BUSINESS_DAY_SEARCH = 30;

    /**
     * @description Apply "Previous Business Day" rule specifically for payment dates.
     *              If date falls on weekend or holiday, moves back 2 BUSINESS DAYS.
     *              If date is already a business day, returns unchanged.
     *              Uses BusinessHours.isWithin() which automatically handles both
     *              weekends AND holidays linked to the Business Hours record.
     *
     * ASSUMPTION D1 & D2: Weekend and holiday payments move back 2 BUSINESS DAYS
     * - Saturday -> Thursday (skip Friday, count 2 business days back)
     * - Sunday -> Thursday (skip Friday, count 2 business days back)
     * - Holiday -> 2 business days before the holiday
     * - Business day -> Returns unchanged
     * - This is intentional, NOT a bug
     *
     * @param originalDate The original payment date
     * @return The adjusted date (2 business days prior if non-business day, unchanged if business day)
     * @throws SettlementCalculatorException if no business day found within 30 days
     */
    public static Date applyPreviousBusinessDayRule(Date originalDate) {
        if (originalDate == null) {
            return null;
        }

        // If already a business day, return unchanged
        if (isBusinessDay(originalDate)) {
            return originalDate;
        }

        // Not a business day - count back 2 business days
        Date adjustedDate = originalDate;
        Integer businessDayCount = 0;
        Integer iterations = 0;

        // isBusinessDay() uses BusinessHours.isWithin() which automatically
        // handles both weekends AND holidays linked to the Business Hours record
        while (businessDayCount < 2) {
            adjustedDate = adjustedDate.addDays(-1);
            iterations++;

            if (isBusinessDay(adjustedDate)) {
                businessDayCount++;
            }

            // Circuit breaker to prevent infinite loops
            if (iterations >= MAX_BUSINESS_DAY_SEARCH) {
                throw new SettlementCalculatorException(
                    SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                    'Unable to find 2 business days within ' + MAX_BUSINESS_DAY_SEARCH + ' days of ' + originalDate
                );
            }
        }

        return adjustedDate;
    }

    /**
     * @description Sort Settlement_Plan_Item__c records by Payment_Date__c ascending,
     *              then by Payment_Number__c as tiebreaker.
     *              Required because sObjects don't implement Comparable.
     * @param items List of items to sort
     * @return Sorted list (new list, original not modified)
     */
    public static List<Settlement_Plan_Item__c> sortByPaymentDate(List<Settlement_Plan_Item__c> items) {
        if (items == null || items.isEmpty()) {
            return items != null ? items : new List<Settlement_Plan_Item__c>();
        }
        
        // Build sortable list using wrapper class
        List<PaymentItemSortWrapper> wrappers = new List<PaymentItemSortWrapper>();
        for (Settlement_Plan_Item__c item : items) {
            wrappers.add(new PaymentItemSortWrapper(item));
        }
        wrappers.sort();
        
        // Extract sorted items
        List<Settlement_Plan_Item__c> sorted = new List<Settlement_Plan_Item__c>();
        for (PaymentItemSortWrapper w : wrappers) {
            sorted.add(w.item);
        }
        return sorted;
    }

    /**
     * @description Wrapper class to enable sorting of Settlement_Plan_Item__c by date
     */
    private class PaymentItemSortWrapper implements Comparable {
        public Settlement_Plan_Item__c item;
        
        public PaymentItemSortWrapper(Settlement_Plan_Item__c item) {
            this.item = item;
        }
        
        public Integer compareTo(Object other) {
            PaymentItemSortWrapper otherWrapper = (PaymentItemSortWrapper) other;
            
            // Compare by date first
            Date thisDate = this.item.Payment_Date__c;
            Date otherDate = otherWrapper.item.Payment_Date__c;
            
            if (thisDate == null && otherDate == null) {
                return compareByPaymentNumber(otherWrapper);
            }
            if (thisDate == null) return 1;  // Nulls last
            if (otherDate == null) return -1;
            
            if (thisDate < otherDate) return -1;
            if (thisDate > otherDate) return 1;
            
            // Dates equal - compare by payment number as tiebreaker
            return compareByPaymentNumber(otherWrapper);
        }
        
        private Integer compareByPaymentNumber(PaymentItemSortWrapper otherWrapper) {
            Decimal thisNum = this.item.Payment_Number__c != null ? this.item.Payment_Number__c : 0;
            Decimal otherNum = otherWrapper.item.Payment_Number__c != null ? otherWrapper.item.Payment_Number__c : 0;

            if (thisNum < otherNum) return -1;
            if (thisNum > otherNum) return 1;
            return 0;
        }
    }

    /**
     * @description Sort PaymentItemData DTOs by payment date, then payment number.
     */
    public static List<SettlementDraftService.PaymentItemData> sortDtosByPaymentDate(
        List<SettlementDraftService.PaymentItemData> items
    ) {
        if (items == null || items.isEmpty()) {
            return items != null ? items : new List<SettlementDraftService.PaymentItemData>();
        }

        List<DtoSortWrapper> wrappers = new List<DtoSortWrapper>();
        for (SettlementDraftService.PaymentItemData item : items) {
            wrappers.add(new DtoSortWrapper(item));
        }
        wrappers.sort();

        List<SettlementDraftService.PaymentItemData> sorted = new List<SettlementDraftService.PaymentItemData>();
        for (DtoSortWrapper w : wrappers) {
            sorted.add(w.item);
        }
        return sorted;
    }

    private class DtoSortWrapper implements Comparable {
        public SettlementDraftService.PaymentItemData item;

        public DtoSortWrapper(SettlementDraftService.PaymentItemData item) {
            this.item = item;
        }

        public Integer compareTo(Object other) {
            DtoSortWrapper otherWrapper = (DtoSortWrapper) other;
            Date thisDate = this.item.paymentDate;
            Date otherDate = otherWrapper.item.paymentDate;

            if (thisDate == null && otherDate == null) return 0;
            if (thisDate == null) return 1;
            if (otherDate == null) return -1;
            if (thisDate < otherDate) return -1;
            if (thisDate > otherDate) return 1;

            // Tiebreak by payment number
            Integer thisNum = this.item.paymentNumber != null ? this.item.paymentNumber : 0;
            Integer otherNum = otherWrapper.item.paymentNumber != null ? otherWrapper.item.paymentNumber : 0;
            return thisNum - otherNum;
        }
    }
}