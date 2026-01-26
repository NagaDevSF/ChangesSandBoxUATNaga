/**
 * @description Reusable component for building payment segments.
 *              Manages dynamic segment rows with add/remove functionality.
 * @author Settlement Calculator Team
 * @date January 2026
 */
import { LightningElement, api, track } from 'lwc';

export default class SegmentBuilder extends LightningElement {
    @api isReadOnly = false;

    @api frequencyOptions = [
        { label: 'Weekly', value: 'Weekly' },
        { label: 'Bi-Weekly', value: 'Bi-Weekly' },
        { label: 'Semi-Monthly', value: 'Semi-Monthly' },
        { label: 'Monthly', value: 'Monthly' }
    ];

    @api segmentTypeOptions = [
        { label: 'Fixed', value: 'Fixed' },
        { label: 'Remainder', value: 'Remainder' },
        { label: 'SolveAmount', value: 'SolveAmount' }
    ];

    @track _segments = [];

    @api
    get segments() {
        return this._segments;
    }
    set segments(value) {
        // Deep clone to avoid mutation issues
        this._segments = value ? JSON.parse(JSON.stringify(value)) : [];
        // Ensure each segment has a unique key for rendering
        this._segments.forEach((seg, idx) => {
            if (!seg.key) {
                seg.key = `seg-${Date.now()}-${idx}`;
            }
        });
    }

    get hasSegments() {
        return this._segments && this._segments.length > 0;
    }

    // Negated getter for template use (LWC templates don't support ! operator)
    get isEditable() {
        return !this.isReadOnly;
    }

    get formattedSegments() {
        const lastIndex = this._segments.length - 1;
        return this._segments.map((seg, index) => ({
            ...seg,
            index: index,
            displayOrder: index + 1,
            showAmountField: seg.segmentType === 'Fixed' || seg.segmentType === 'Remainder',
            showCountField: seg.segmentType === 'Fixed' || seg.segmentType === 'SolveAmount',
            isFirstSegment: index === 0,
            isLastSegment: index === lastIndex,
            showOptionalHint: index !== 0, // Show hint for non-first segments
            startDateRequired: index === 0
        }));
    }

    // Event handlers
    handleAddSegment() {
        const newOrder = this._segments.length + 1;
        const newSegment = {
            key: `seg-${Date.now()}`,
            segmentOrder: newOrder,
            segmentType: 'Fixed',
            paymentAmount: null,
            paymentCount: null,
            frequency: 'Monthly',
            startDate: null
        };

        this._segments = [...this._segments, newSegment];
        this.fireChange();
    }

    /**
     * Handles non-numeric field changes (combobox, date)
     * These can update immediately as they don't have cursor position issues
     */
    handleFieldChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const field = event.target.dataset.field;
        let value = event.target.value;

        // Update the segment
        const segments = [...this._segments];
        segments[index] = {
            ...segments[index],
            [field]: value
        };

        // Reset dependent fields when segment type changes
        if (field === 'segmentType') {
            if (value === 'Remainder') {
                segments[index].paymentCount = null;
            } else if (value === 'SolveAmount') {
                segments[index].paymentAmount = null;
            }
        }

        this._segments = segments;
        this.fireChange();
    }

    /**
     * Handles numeric field changes (amount, count) on blur
     * Using onblur instead of onchange prevents cursor jumping during typing
     */
    handleNumericFieldBlur(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const field = event.target.dataset.field;
        let value = event.target.value;

        // Convert to number
        if (field === 'paymentAmount') {
            value = value ? parseFloat(value) : null;
        } else if (field === 'paymentCount') {
            value = value ? Math.floor(parseFloat(value)) : null;
        }

        // Update the segment
        const segments = [...this._segments];
        segments[index] = {
            ...segments[index],
            [field]: value
        };

        this._segments = segments;
        this.fireChange();
    }

    handleDeleteSegment(event) {
        const index = parseInt(event.target.dataset.index, 10);

        // Prevent deleting the last segment
        if (this._segments.length <= 1) {
            this.dispatchEvent(new CustomEvent('segmenterror', {
                detail: { message: 'Cannot delete the last segment. At least one segment is required.' }
            }));
            return;
        }

        const segments = this._segments.filter((_, idx) => idx !== index);

        // Renumber segments
        segments.forEach((seg, idx) => {
            seg.segmentOrder = idx + 1;
        });

        this._segments = segments;
        this.fireChange();
    }

    handleMoveUp(event) {
        const index = parseInt(event.target.dataset.index, 10);
        if (index <= 0) return;

        const segments = [...this._segments];
        [segments[index - 1], segments[index]] = [segments[index], segments[index - 1]];

        // Renumber
        segments.forEach((seg, idx) => {
            seg.segmentOrder = idx + 1;
        });

        this._segments = segments;
        this.fireChange();
    }

    handleMoveDown(event) {
        const index = parseInt(event.target.dataset.index, 10);
        if (index >= this._segments.length - 1) return;

        const segments = [...this._segments];
        [segments[index], segments[index + 1]] = [segments[index + 1], segments[index]];

        // Renumber
        segments.forEach((seg, idx) => {
            seg.segmentOrder = idx + 1;
        });

        this._segments = segments;
        this.fireChange();
    }

    fireChange() {
        // Clean up segments before sending to parent
        const cleanSegments = this._segments.map(seg => ({
            segmentOrder: seg.segmentOrder,
            segmentType: seg.segmentType,
            paymentAmount: seg.paymentAmount,
            paymentCount: seg.paymentCount,
            frequency: seg.frequency,
            startDate: seg.startDate
        }));

        this.dispatchEvent(new CustomEvent('segmentchange', {
            detail: { segments: cleanSegments }
        }));
    }

    // Validation helpers
    getSegmentTypeHelp(segmentType) {
        switch (segmentType) {
            case 'Fixed':
                return 'Fixed amount for a specific number of payments';
            case 'Remainder':
                return 'Fixed amount until balance is paid';
            case 'SolveAmount':
                return 'Calculate amount to pay off in N payments';
            default:
                return '';
        }
    }
}