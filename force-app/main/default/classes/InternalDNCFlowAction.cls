/**
 * @description Invocable Apex action for Flow to send phone numbers to Internal DNC API
 * Use this in Record-Triggered Flows when Opportunity stage changes to target stages
 */
public with sharing class InternalDNCFlowAction {

    /**
     * @description Input wrapper class for Flow invocable method
     */
    public class FlowInput {
        @InvocableVariable(label='Phone Number' description='Phone number to add to DNC list' required=true)
        public String phoneNumber;

        @InvocableVariable(label='Opportunity ID' description='Opportunity ID for logging purposes' required=false)
        public Id opportunityId;
    }

    /**
     * @description Output wrapper class for Flow invocable method
     */
    public class FlowOutput {
        @InvocableVariable(label='Success' description='Whether the API call was successful')
        public Boolean success;

        @InvocableVariable(label='Message' description='Response message from the API')
        public String message;

        @InvocableVariable(label='Numbers Added' description='Count of phone numbers successfully added')
        public Integer numbersAdded;

        @InvocableVariable(label='Numbers Skipped' description='Count of phone numbers skipped (duplicates/invalid)')
        public Integer numbersSkipped;

        @InvocableVariable(label='Error Message' description='Error message if the call failed')
        public String errorMessage;
    }

    /**
     * @description Invocable method to send phone number to DNC API
     * Called from Flow when Opportunity stage changes to Contract Signed, Enrolled, NSF, or Cancelled
     * @param inputs List of FlowInput containing phone numbers
     * @return List of FlowOutput with API response details
     */
    @InvocableMethod(
        label='Send Phone to Internal DNC'
        description='Sends phone number to Internal DNC API when Opportunity reaches target stages (Contract Signed, Enrolled, NSF, Cancelled)'
        category='DNC Integration'
    )
    public static List<FlowOutput> sendToDNC(List<FlowInput> inputs) {
        List<FlowOutput> outputs = new List<FlowOutput>();

        // Process each input - use async for trigger context
        for (FlowInput input : inputs) {
            FlowOutput output = new FlowOutput();

            if (String.isBlank(input.phoneNumber)) {
                output.success = false;
                output.message = 'No phone number provided';
                output.errorMessage = 'Phone number is blank or null';
                outputs.add(output);
                continue;
            }

            // Use async to avoid callout issues in trigger context
            InternalDNCService.sendPhoneToDNCAsync(input.phoneNumber, input.opportunityId);
            output.success = true;
            output.message = 'Phone number queued for DNC processing';
            output.numbersAdded = 0;
            output.numbersSkipped = 0;
            outputs.add(output);
        }

        return outputs;
    }
}