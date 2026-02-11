/**
 * @description Utility class for date calculations in Settlement Calculator.
 *              Handles business day adjustments, frequency-based date advancement,
 *              and holiday awareness using Salesforce BusinessHours.
 * @lastModified January 2026 - Refactored to use BusinessHours
 *
 * ============================================================================
 * ASSUMPTIONS DOCUMENTED IN THIS FILE:
 * ============================================================================
 * D1: Business day payments move back 1 BUSINESS DAY (EPPS processing buffer)
 * D2: Weekend/holiday payments move back 2 BUSINESS DAYS using
 *     Salesforce BusinessHours.isWithin() which automatically handles both
 *     weekends AND holidays linked to the "Payment Business Hours" record.
 * D3: Date spacing uses ORIGINAL date (not adjusted) to prevent drift
 * D4: Semi-Monthly uses user-defined anchor days from segment Start_Date__c/End_Date__c
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
                throw new SettlementCalculatorException(
                    SettlementCalculatorException.ErrorType.DATE_CALCULATION_ERROR,
                    'Semi-Monthly requires anchor days. Use advanceDate(Date, String, Integer, Integer).'
                );
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
     * @description Advance a date based on frequency, with anchor days for Semi-Monthly.
     *              For non-semi-monthly frequencies, dayA and dayB are ignored.
     * @param currentDate The current date
     * @param frequency The frequency (Weekly, Bi-Weekly, Semi-Monthly, Monthly)
     * @param dayA First anchor day-of-month (used only for Semi-Monthly)
     * @param dayB Second anchor day-of-month (used only for Semi-Monthly)
     * @return The next date based on frequency
     */
    public static Date advanceDate(Date currentDate, String frequency, Integer dayA, Integer dayB) {
        if (currentDate == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.DATE_CALCULATION_ERROR,
                'Current date cannot be null'
            );
        }

        if (frequency == FREQ_SEMIMONTHLY) {
            return advanceSemiMonthly(currentDate, dayA, dayB);
        }

        // Non-semi-monthly: delegate to original method (ignores dayA/dayB)
        return advanceDate(currentDate, frequency);
    }

    /**
     * @description Advance date for semi-monthly frequency using user-defined anchor days.
     *              Builds two candidate dates in the current month (clamped to month-end),
     *              picks the earliest strictly after currentDate. If none found, moves to
     *              the next month and repeats.
     *
     * ASSUMPTION D4 (updated): Semi-Monthly uses user-defined anchor days instead of 1st/15th.
     * - dayA and dayB are day-of-month values derived from segment Start_Date__c and End_Date__c
     * - Month-end clamp: effectiveDay = min(anchorDay, daysInMonth) to handle Feb/short months
     * - Business-day adjustment still applied separately downstream
     *
     * @param currentDate The current date
     * @param dayA First anchor day-of-month
     * @param dayB Second anchor day-of-month
     * @return The next semi-monthly date
     */
    private static Date advanceSemiMonthly(Date currentDate, Integer dayA, Integer dayB) {
        if (dayA == null || dayB == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.DATE_CALCULATION_ERROR,
                'Semi-Monthly anchor days cannot be null'
            );
        }

        // Ensure dayA is the smaller anchor for consistent ordering
        Integer firstDay = Math.min(dayA, dayB);
        Integer secondDay = Math.max(dayA, dayB);

        // Try current month first, then next month (circuit breaker at 2 months)
        Date refDate = currentDate;
        for (Integer m = 0; m < 2; m++) {
            Integer year = refDate.year();
            Integer month = refDate.month();
            Integer daysInMonth = Date.daysInMonth(year, month);

            // Clamp anchors to month length
            Integer clampedFirst = Math.min(firstDay, daysInMonth);
            Integer clampedSecond = Math.min(secondDay, daysInMonth);

            // Build candidate dates in this month
            Date candidateA = Date.newInstance(year, month, clampedFirst);
            Date candidateB = Date.newInstance(year, month, clampedSecond);

            // Pick earliest candidate strictly after currentDate
            if (candidateA > currentDate) {
                return candidateA;
            }
            if (candidateB > currentDate) {
                return candidateB;
            }

            // Neither candidate works — move to next month
            refDate = Date.newInstance(year, month, 1).addMonths(1);
        }

        // Should never reach here — 2 months guarantees a result
        throw new SettlementCalculatorException(
            SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
            'Unable to determine next semi-monthly date after ' + currentDate
        );
    }

    // Maximum days to search for a business day (circuit breaker)
    private static final Integer MAX_BUSINESS_DAY_SEARCH = 30;

    /**
     * @description Apply "Previous Business Day" rule specifically for payment dates.
     *              Always adjusts dates back for EPPS processing buffer:
     *              - Business day: moves back 1 BUSINESS DAY
     *              - Weekend/Holiday: moves back 2 BUSINESS DAYS
     *              Uses BusinessHours.isWithin() which automatically handles both
     *              weekends AND holidays linked to the Business Hours record.
     *
     * ASSUMPTION D1: Business day payments move back 1 BUSINESS DAY (EPPS processing buffer)
     * ASSUMPTION D2: Weekend/holiday payments move back 2 BUSINESS DAYS
     * - Monday -> Friday (1 business day back, skips weekend)
     * - Tuesday -> Monday (1 business day back)
     * - Saturday -> Thursday (2 business days back)
     * - Sunday -> Thursday (2 business days back, skips Sat)
     * - Holiday -> 2 business days before the holiday
     *
     * @param originalDate The original payment date
     * @return The adjusted date (1 business day prior if business day, 2 if non-business day)
     * @throws SettlementCalculatorException if no business day found within 30 days
     */
    public static Date applyPreviousBusinessDayRule(Date originalDate) {
        if (originalDate == null) {
            return null;
        }

        // Determine how many business days to move back:
        // - Business day: 1 day back (EPPS processing buffer)
        // - Weekend/Holiday: 2 days back
        Integer businessDaysToMoveBack = isBusinessDay(originalDate) ? 1 : 2;

        Date adjustedDate = originalDate;
        Integer businessDayCount = 0;
        Integer iterations = 0;

        // isBusinessDay() uses BusinessHours.isWithin() which automatically
        // handles both weekends AND holidays linked to the Business Hours record
        while (businessDayCount < businessDaysToMoveBack) {
            adjustedDate = adjustedDate.addDays(-1);
            iterations++;

            if (isBusinessDay(adjustedDate)) {
                businessDayCount++;
            }

            // Circuit breaker to prevent infinite loops
            if (iterations >= MAX_BUSINESS_DAY_SEARCH) {
                throw new SettlementCalculatorException(
                    SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                    'Unable to find ' + businessDaysToMoveBack + ' business days within ' + MAX_BUSINESS_DAY_SEARCH + ' days of ' + originalDate
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

    /**
     * @description Result wrapper for date validation
     */
    public class DateValidationResult {
        @AuraEnabled public Boolean hasNonBusinessDays;
        @AuraEnabled public List<NonBusinessDayInfo> nonBusinessDays;

        public DateValidationResult() {
            this.hasNonBusinessDays = false;
            this.nonBusinessDays = new List<NonBusinessDayInfo>();
        }
    }

    /**
     * @description Info about a non-business day date
     */
    public class NonBusinessDayInfo {
        @AuraEnabled public Integer rowNumber;
        @AuraEnabled public Date paymentDate;
        @AuraEnabled public String dateType; // 'Weekend' or 'Holiday'

        public NonBusinessDayInfo(Integer rowNumber, Date paymentDate, String dateType) {
            this.rowNumber = rowNumber;
            this.paymentDate = paymentDate;
            this.dateType = dateType;
        }
    }

    /**
     * @description Validate payment dates and return info about any that fall on weekends/holidays.
     *              Used by LWC to warn user before saving with non-business day dates.
     * @param paymentDates List of dates to validate (index corresponds to row number - 1)
     * @return DateValidationResult with list of non-business day info
     */
    public static DateValidationResult validatePaymentDates(List<Date> paymentDates) {
        DateValidationResult result = new DateValidationResult();

        if (paymentDates == null || paymentDates.isEmpty()) {
            return result;
        }

        for (Integer i = 0; i < paymentDates.size(); i++) {
            Date paymentDate = paymentDates[i];
            if (paymentDate == null) {
                continue;
            }

            if (!isBusinessDay(paymentDate)) {
                result.hasNonBusinessDays = true;

                // Determine if it's a weekend or holiday
                Integer dayOfWeek = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(paymentDate), 7);
                // 0 = Sunday, 6 = Saturday
                String dateType = (dayOfWeek == 0 || dayOfWeek == 6) ? 'Weekend' : 'Holiday';

                result.nonBusinessDays.add(new NonBusinessDayInfo(i + 1, paymentDate, dateType));
            }
        }

        return result;
    }
}