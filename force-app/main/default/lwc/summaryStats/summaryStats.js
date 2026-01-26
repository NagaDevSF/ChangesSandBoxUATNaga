import { LightningElement, api } from 'lwc';

export default class SummaryStats extends LightningElement {
    // Optional: pass full schedule to infer weeks/date if props not provided
    @api items = [];

    // Explicit props from parent (preferred)
    @api weeklyPayment;      // New Weekly Payment
    @api programLength;      // Weeks to Payoff
    @api currentPayment;     // Current total weekly payment (from creditors)
    @api totalSavings;       // Estimated total savings (fallback only)
    @api totalDebt;          // Total of all creditor estimated balances
    @api firstDraftDate;     // First Draft Date (YYYY-MM-DD or ISO)

    // Helpers
    get hasItems() {
        return Array.isArray(this.items) && this.items.length > 0;
    }

    // New Weekly Payment
    // Prefer explicit weeklyPayment prop from parent when provided (user-entered value)
    // Fallback to schedule-based calculation if prop not provided
    get computedNewWeeklyPayment() {
        // Use explicit prop if provided (user's entered value takes priority)
        if (this.weeklyPayment != null && this.weeklyPayment > 0) {
            return this.weeklyPayment;
        }
        // Fallback to schedule-based calculation
        if (this.hasItems) {
            const first = this.items[0] || {};
            const payment = first.paymentAmount ?? first.totalPayment ?? first.draftAmount ?? 0;
            const setup = first.setupFee ?? first.setupFeePortion ?? 0;
            return Math.max(0, payment - setup);
        }
        return 0;
    }

    // Weeks to Payoff
    get computedWeeksToPayoff() {
        if (this.programLength != null) return this.programLength;
        return this.hasItems ? this.items.length : 0;
    }

    // Weekly Savings = currentPayment - newWeeklyPayment
    get computedWeeklySavings() {
        const current = this.currentPayment ?? 0;
        const next = this.computedNewWeeklyPayment ?? 0;
        return current - next;
    }

    // Percent Weekly Saving = (weeklySavings / currentPayment) * 100
    get computedPercentWeeklySaving() {
        const current = this.currentPayment ?? 0;
        if (!current) return 0;
        return (this.computedWeeklySavings / current) * 100;
    }

    // lightning-formatted-number percent expects a decimal (0-1)
    get computedPercentWeeklySavingDecimal() {
        return (this.computedPercentWeeklySaving || 0) / 100;
    }

    // Estimated total savings = Total Creditor Estimated Balance - Total of All Drafts
    get computedEstimatedTotalSavings() {
        const debt = Number(this.totalDebt || 0);
        if (this.hasItems && debt > 0) {
            const totalDrafts = this.items.reduce((sum, item) => {
                const payment = item.paymentAmount ?? item.totalPayment ?? item.draftAmount ?? 0;
                return sum + Number(payment || 0);
            }, 0);
            return debt - totalDrafts;
        }
        // Fallback to provided prop if schedule or debt not present
        return Number(this.totalSavings || 0);
    }

    // First Draft Date
    // Normalize to a local Date object to avoid timezone-related off-by-one issues
    get computedFirstDraftDate() {
        const raw = this.firstDraftDate
            || (this.hasItems ? (this.items[0]?.paymentDate || this.items[0]?.date) : null);
        return this.parseDateSafe(raw);
    }

    // Safely parse date strings (e.g., 'YYYY-MM-DD') into a local Date
    // Returns undefined if input is falsy to let lightning-formatted-date-time render nothing
    parseDateSafe(value) {
        if (!value) return undefined;
        try {
            if (value instanceof Date) return value;
            if (typeof value === 'string') {
                // If it's a bare date (YYYY-MM-DD), construct a local Date to avoid UTC shift
                const m = value.match(/^(\d{4})-(\d{2})-(\d{2})$/);
                if (m) {
                    const year = parseInt(m[1], 10);
                    const month = parseInt(m[2], 10) - 1;
                    const day = parseInt(m[3], 10);
                    return new Date(year, month, day);
                }
                // Otherwise, let Date parse ISO strings with time component
                const parsed = new Date(value);
                if (!isNaN(parsed)) return parsed;
            }
        } catch (e) {
            // fall through
        }
        return undefined;
    }
}