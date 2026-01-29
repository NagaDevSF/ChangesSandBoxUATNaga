public class PaymentPlanService {

	public static void buildPaymentScheduleItems(List<Opportunity> oppList) {

		Map<Id, List<Payment_Schedule_Item__c>> returnMap = new Map<Id, List<Payment_Schedule_Item__c>>();

		Map<Id, PaymentDraft__c> primaryDraftMap = getPrimaryDraftPerOpp(oppList);
		// TODO add setSavepoint and rollback to this as its a complicated multi-save insert
		Map<Id, PaymentPlan__c> paymentPlanMap = new Map<Id, PaymentPlan__c>();

		for (Opportunity opp: oppList) {
			// TODO calling service does an opp query, refactor to pass in the needed data
			PaymentPlan__c thisPP = SalesCalculatorService.createNewVersion(opp.Id);

			// Set plan as Draft when created from contract signing
			thisPP.Status__c = 'Draft';
			thisPP.Version_Status__c = 'Draft';
			thisPP.Is_Active__c = false;

			// blend in the paymentdraft data into the PaymentPlan__c record
			PaymentDraft__c thisDraft = primaryDraftMap.get(opp.Id);

			// Check if a primary draft exists for this opportunity
			if (thisDraft != null) {
				thisPP.Settlement_Percentage__c = thisDraft.Settlement_Percentage__c != null ? thisDraft.Settlement_Percentage__c : 30;
				thisPP.Program_Fee_Percentage__c = thisDraft.Program_Fee_Percentage__c != null ? thisDraft.Program_Fee_Percentage__c : 30;
				thisPP.Setup_Fee__c = thisDraft.Setup_Fee__c != null ?  thisDraft.Setup_Fee__c  : 30;
				thisPP.Banking_Fee__c = thisDraft.Banking_Fee__c != null ? thisDraft.Banking_Fee__c : 50;
				//TODO there is no bank2 fee tracked on Draft
				thisPP.Bank2_Fee__c = thisDraft.Banking_Fee__c != null ? thisDraft.Banking_Fee__c : 55;
				// Setup Fee Payments from Setup_Fee_Term__c (number of payments), not Setup_Fee__c (dollar amount)
				thisPP.Setup_Fee_Payments__c = thisDraft.Setup_Fee_Term__c != null ? thisDraft.Setup_Fee_Term__c : 4;
			} else {
				// No primary draft found - use default values
				thisPP.Settlement_Percentage__c = 30;
				thisPP.Program_Fee_Percentage__c = 30;
				thisPP.Setup_Fee__c = 30;
				thisPP.Banking_Fee__c = 50;
				thisPP.Bank2_Fee__c = 55;
				thisPP.Setup_Fee_Payments__c = 4;
			}
			paymentPlanMap.put(opp.Id, thisPP);
		}

		Database.insert(paymentPlanMap.values(), AccessLevel.USER_MODE);

		// Get active draft items for each primary draft
		Map<Id, List<Payment_Draft_Item__c>> draftItemsMap = getActiveDraftItemsByDrafts(primaryDraftMap.values());

		for (Opportunity opp : oppList) {
			PaymentDraft__c thisDraft = primaryDraftMap.get(opp.Id);
			PaymentPlan__c thisPlan = paymentPlanMap.get(opp.Id);

			List<Payment_Schedule_Item__c> scheduleItems = new List<Payment_Schedule_Item__c>();

			// Copy from Payment_Draft_Item__c records instead of recalculating
			if (thisDraft != null && draftItemsMap.containsKey(thisDraft.Id)) {
				List<Payment_Draft_Item__c> draftItems = draftItemsMap.get(thisDraft.Id);
				Decimal runningBalance = 0;

				for (Payment_Draft_Item__c draftItem : draftItems) {
					Payment_Schedule_Item__c psi = new Payment_Schedule_Item__c();
					psi.Payment_Plan__c = thisPlan.Id;
					psi.Payment_Number__c = draftItem.Draft_Number__c;
					// Draft_Number__c on Payment_Schedule_Item__c is a String field
					psi.Draft_Number__c = draftItem.Draft_Number__c != null
						? String.valueOf(draftItem.Draft_Number__c.intValue())
						: null;
					psi.Payment_Date__c = draftItem.Draft_Due_Date__c;
					psi.Total_Payment__c = draftItem.Total_Draft__c;
					psi.Banking_Fee_Amount__c = draftItem.Banking_Fee__c;
					psi.Setup_Fee_Amount__c = draftItem.Setup_Fee__c;
					psi.Program_Fee_Amount__c = draftItem.Program_Fee__c;

					// Map Savings to To_Escrow_Amount
					if (draftItem.Savings__c != null) {
						psi.To_Escrow_Amount__c = draftItem.Savings__c;
					} else {
						// Calculate: Total - Banking - Setup - Program
						Decimal totalDraft = draftItem.Total_Draft__c != null ? draftItem.Total_Draft__c : 0;
						Decimal bankingFee = draftItem.Banking_Fee__c != null ? draftItem.Banking_Fee__c : 0;
						Decimal setupFee = draftItem.Setup_Fee__c != null ? draftItem.Setup_Fee__c : 0;
						Decimal programFee = draftItem.Program_Fee__c != null ? draftItem.Program_Fee__c : 0;
						psi.To_Escrow_Amount__c = totalDraft - bankingFee - setupFee - programFee;
					}

					// Set default status as Scheduled for new items
					psi.Status__c = 'Scheduled';

					scheduleItems.add(psi);
				}
			}

			returnMap.put(opp.Id, scheduleItems);
		}

		List<Payment_Schedule_Item__c> allPSIList = new List<Payment_Schedule_Item__c>();

		for (Id oppId : returnMap.keySet()) {
			allPSIList.addAll(returnMap.get(oppId));
		}

		Database.insert(allPSIList);
		//Database.insert(allPSIList, AccessLevel.USER_MODE);

		// Create Payment_Fee__c records for all inserted schedule items
		// Note: Only Banking, Program, and Setup fees are created as Payment_Fee__c records
		// Savings/Escrow is stored directly on Payment_Schedule_Item__c.To_Escrow_Amount__c
		List<Payment_Fee__c> allFeeRecords = new List<Payment_Fee__c>();
		for (Payment_Schedule_Item__c psi : allPSIList) {
			allFeeRecords.addAll(PaymentFeeService.createFeeRecordsForItem(
				psi,
				psi.Banking_Fee_Amount__c,
				psi.Program_Fee_Amount__c,
				psi.Setup_Fee_Amount__c
			));
		}
		if (!allFeeRecords.isEmpty()) {
			Database.insert(allFeeRecords);
		}

		//return returnMap;
	}
	

	public static Map<Id, List<CreditorOpportunity__c>> getCreditorOppsByOpps(List<Opportunity> oppList) {
        Map<Id, List<CreditorOpportunity__c>> resultMap = new Map<Id, List<CreditorOpportunity__c>>();

        if (oppList == null || oppList.isEmpty()) {
            return resultMap;
        }

        // Get all object fields dynamically
        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get('CreditorOpportunity__c')
                .getDescribe().fields.getMap();

        String fieldList = String.join(
            new List<String>(fieldMap.keySet()),
            ','
        );

        // Build & execute dynamic query
        String query = 'SELECT ' + fieldList + 
                       ' FROM CreditorOpportunity__c' +
                       ' WHERE Opportunity__c IN :oppList';

        List<CreditorOpportunity__c> creditorOpps = Database.query(query);

        // Group by Opportunity__c
        for (CreditorOpportunity__c co : creditorOpps) {
            if (co.Opportunity__c == null) continue;

            if (!resultMap.containsKey(co.Opportunity__c)) {
                resultMap.put(co.Opportunity__c, new List<CreditorOpportunity__c>());
            }
            resultMap.get(co.Opportunity__c).add(co);
        }

        return resultMap;
    }

	public static Map<Id, PaymentDraft__c> getPrimaryDraftPerOpp(List<Opportunity> oppList) {

		Map<Id, PaymentDraft__c> draftMap = new Map<Id, PaymentDraft__c>();

		// Dynamically gather all fields on PrimaryDraft__c
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get('PaymentDraft__c').getDescribe().fields.getMap();

        String fieldList = String.join(new List<String>(fieldMap.keySet()), ',');

        String soql = 'SELECT ' + fieldList +
                      ' FROM PaymentDraft__c' +
                      ' WHERE Opportunity__c IN :oppList' +
                      ' AND Is_Primary__c = TRUE';

        List<PaymentDraft__c> primaryDrafts = Database.query(soql);

        for (PaymentDraft__c draft : primaryDrafts) {
            if (draft.Opportunity__c != null) {
                draftMap.put(draft.Opportunity__c, draft);
            }
        }
		return draftMap;
	}

	/**
	 * Get active Payment_Draft_Item__c records for a collection of PaymentDraft__c records
	 * Returns a map keyed by PaymentDraft__c Id with list of active draft items
	 * @param drafts Collection of PaymentDraft__c records
	 * @return Map of Draft Id to List of active Payment_Draft_Item__c records
	 */
	public static Map<Id, List<Payment_Draft_Item__c>> getActiveDraftItemsByDrafts(List<PaymentDraft__c> drafts) {
		Map<Id, List<Payment_Draft_Item__c>> resultMap = new Map<Id, List<Payment_Draft_Item__c>>();

		if (drafts == null || drafts.isEmpty()) {
			return resultMap;
		}

		// Collect draft IDs
		Set<Id> draftIds = new Set<Id>();
		for (PaymentDraft__c draft : drafts) {
			if (draft != null && draft.Id != null) {
				draftIds.add(draft.Id);
				// Initialize empty list for each draft
				resultMap.put(draft.Id, new List<Payment_Draft_Item__c>());
			}
		}

		if (draftIds.isEmpty()) {
			return resultMap;
		}

		// Query active draft items for all drafts
		List<Payment_Draft_Item__c> draftItems = [
			SELECT Id, Payment_Draft__c, Draft_Number__c, Draft_Due_Date__c,
				   Total_Draft__c, Banking_Fee__c, Setup_Fee__c, Savings__c,
				   Program_Fee__c, Is_Active__c, Calculation_Version__c
			FROM Payment_Draft_Item__c
			WHERE Payment_Draft__c IN :draftIds
			AND Is_Active__c = true
			ORDER BY Draft_Number__c ASC
		];

		// Group by Payment_Draft__c
		for (Payment_Draft_Item__c item : draftItems) {
			if (item.Payment_Draft__c != null && resultMap.containsKey(item.Payment_Draft__c)) {
				resultMap.get(item.Payment_Draft__c).add(item);
			}
		}

		return resultMap;
	}

	public static Map<String, Object> buildConfig(Opportunity opp, PaymentDraft__c pd) {

		// TODO setting targetPaymentAmount from PaymentDraft__c Weekly_Payment__c
		Decimal targetPaymentAmount = pd.Weekly_Payment__c;

		Map<String, Object> config = new Map<String, Object>();

		// TODO taken from PaymentCalculatorController, should create shared helper for this to be used globally.
		config.put('programType', opp.Program_Type__c);
		config.put('paymentFrequency', opp.Payment_Frequency__c);
		// TODO how can I pull this off opportunity, values are PERCENT and DESIRED
		// probably look at the active payment draft this field Calculation_Mode__c confirm this
		config.put('calculationMode', pd.Calculation_Mode__c);
		String normalizedProgramType = (opp.Program_Type__c != null) ? opp.Program_Type__c.toUpperCase() : 'DCG_MOD';

		// Get min target percentages from config - fail fast if config unavailable
		PaymentCalcConfigSvc.ConfigDTO cfg = PaymentCalcConfigSvc.getRequiredConfig();
		Decimal minTargetPercentDcgDebt = cfg.minTargetPercentDcgDebt;
		Decimal minTargetPercentDcgMod = cfg.minTargetPercentDcgMod;
		Decimal minTargetPercent = (normalizedProgramType == 'DCG_DEBT') ? minTargetPercentDcgDebt : minTargetPercentDcgMod;
		if (pd.Target_Payment_Percent__c != null && pd.Target_Payment_Percent__c < minTargetPercent) {
			pd.Target_Payment_Percent__c = minTargetPercent;
		}

		Decimal workingTargetPaymentFloor = opp.Program_Type__c == 'DCG_DEBT' ? PaymentCalculatorController.WEEKLY_TARGET_PAYMENT_FLOOR_DCG_DEBT : PaymentCalculatorController.WEEKLY_TARGET_PAYMENT_FLOOR;

		// Get weekly to monthly conversion factor from config (already loaded above)
		Decimal weeklyToMonthlyFactor = cfg.weeklyToMonthlyFactor;

		Decimal normalizedWeeklyTarget = null;
		if (targetPaymentAmount != null) {
			normalizedWeeklyTarget = targetPaymentAmount;
			if (opp.Payment_Frequency__c == 'Monthly') {
				normalizedWeeklyTarget = normalizedWeeklyTarget / weeklyToMonthlyFactor;
			}
			if (normalizedWeeklyTarget < workingTargetPaymentFloor) {
				normalizedWeeklyTarget = workingTargetPaymentFloor;
				Decimal adjustedAmount = (opp.Payment_Frequency__c == 'Monthly')
					? normalizedWeeklyTarget * weeklyToMonthlyFactor
					: normalizedWeeklyTarget;
				targetPaymentAmount = adjustedAmount.setScale(2);
			} else {
				targetPaymentAmount = targetPaymentAmount.setScale(2);
			}
		}

		config.put('targetPaymentPercentage', pd.Target_Payment_Percent__c);
		config.put('targetPaymentAmount', targetPaymentAmount);
		config.put('setupFee', pd.Setup_Fee__c);
		config.put('setupFeePayments', pd.Setup_Fee_Term__c);
		// Maintain legacy key and add canonical key expected by CalculationService
		config.put('servicingFee', pd.Banking_Fee__c);
		config.put('bankingFee', pd.Banking_Fee__c);
		// TODO no field for bank2Fee on PaymentDraft__c
		//config.put('bank2Fee', bank2Fee);
		config.put('firstDraftDate', pd.First_Draft_Date__c);
		config.put('preferredDayOfWeek', pd.Preferred_Day_of_Week__c);
		config.put('noFeeProgram', pd.No_Fee_Program__c);

		// Additional Products (optional; additive weekly amount)
		if (pd.Total_Additional_Product_Fee__c != null) {
			config.put('additionalProductsWeeklyTotal', pd.Total_Additional_Product_Fee__c);
		}
		// Load CMDT-backed configuration for this program type - fail fast if unavailable
		PaymentCalcConfigSvc.ConfigDTO programCfg = PaymentCalcConfigSvc.getRequiredConfigForProgram(opp.Program_Type__c);

		// Percentages (override with No-Fee rule)
		Decimal settlementPct = programCfg.settlementPercent;
		Decimal programFeePct = programCfg.programFeePercent;
		Decimal baselineProgramFeePct = programFeePct;
		if (pd.No_Fee_Program__c == true) {
			config.put('noFeeProgramOriginalFeePercentage', baselineProgramFeePct);
			programFeePct = 0;
		} else {
			config.put('noFeeProgramOriginalFeePercentage', baselineProgramFeePct);
		}
		config.put('settlementPercentage', settlementPct);
		config.put('programFeePercentage', programFeePct);

		// Fees (prefer values passed from UI if present, else CMDT)
		if (config.get('bankingFee') == null) {
			config.put('bankingFee', programCfg.bankingFee);
			config.put('servicingFee', programCfg.bankingFee);
		}
		if (config.get('bank2Fee') == null) {
			config.put('bank2Fee', programCfg.bank2Fee);
		}

		// Split ratios
		config.put('programSplitRatio', programCfg.programSplitRatio);
		config.put('escrowSplitRatio', programCfg.escrowSplitRatio);

		// Add current payment to config for downstream calculations
		config.put('currentPayment', opp.Estimated_Current_Payment__c);

		// If using desired payment mode, normalize and supply required config keys
		if (pd.Calculation_Mode__c == 'desired_payment') {
			// Normalize target amount to weekly for CalculationService
			Decimal desiredWeekly = (normalizedWeeklyTarget != null)
				? normalizedWeeklyTarget
				: (targetPaymentAmount != null ? targetPaymentAmount : 0);
			if (desiredWeekly == null) desiredWeekly = 0;
			if (desiredWeekly < workingTargetPaymentFloor) {
				desiredWeekly = workingTargetPaymentFloor;
			}
			config.put('desiredWeeklyPayment', desiredWeekly);
			// Provide a sane cap for settlement percentage if not already present
			if (config.get('maxSettlementPercentage') == null) {
				Decimal cap = (config.get('settlementPercentage') != null)
					? (Decimal)config.get('settlementPercentage') : 60;
				config.put('maxSettlementPercentage', cap);
			}
		}

		return config;
	}

}