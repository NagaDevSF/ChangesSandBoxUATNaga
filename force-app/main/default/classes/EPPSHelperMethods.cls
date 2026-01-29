public class EPPSHelperMethods {

	/* =======================
	  CONSTANTS / ENUMS
	  ======================= */

	public static final String EPPS_INTEGRATION_SETTING_MDT = 'EPPS_Integration_Setting__mdt';
	public static final String EPPS_INTEGRATION_OBJ_MDT = 'EPPS_Integration_Object__mdt';
	public static final String EPPS_INT_STATUS_FAILED = 'Failed';
	public static final String EPPS_INT_STATUS_SUCCESS = 'Success';
	public static final String EPPS_ADD_CARDHOLDER = 'AddCardHolder';
	public static final String EPPS_UPDATE_CARDHOLDER = 'UpdateCardHolder';
	public static final String SETTLEMENT_PLAN_STATUS_ACTIVE = 'Active';
	public static final String PAYMENT_PLAN_STATUS_ACTIVE = 'Active';
	public static final String PAYMENT_SCHEDULE_ITEM_STATUS_SCHEDULED = 'Scheduled';
	public static final String SETTLEMENT_PLAN_ITEM_STATUS_SCHEDULED = 'Scheduled';
	public static final String SETTLEMENT_PLAN_ITEM_STATUS_PROCESSING = 'Processing';
	public static final List<String> EPPS_SETTLED_STATUS = new List<String>{'Settled'};
    public static final String PSI_STATUS_SENT_TO_EPPS = 'Sent to EPPS';
	public static final String PSI_STATUS_FAILED_TO_EPPS = 'Failed to EPPS';

	public enum EPPSOperation { EPPS_ADD_CARDHOLDER, EPPS_UPDATE_CARDHOLDER }

	/* =======================
	  RESPONSE WRAPPER
	  ======================= */

	public class EPPSResponse {

		public String Method;
		public Boolean Success;
		public Integer HTTPResponseCode;
		public String SOAPRequestBody;
		public String SOAPResponseBody;
		public String LastError;
		public String StatusCode;

		// EFT-specific
		public Integer EftTransactionID;
		public Map<String, FindEFT_Wrapper> FoundEFTs;

		// Fee-specific
		public Map<String, FindFee_Wrapper> FoundFees;

		// ➜ NEW
		public String FeeID;

		// Base constructor
		public EPPSResponse(
		                    String theMethod,
		                    Boolean theSuccess,
		                    Integer responseCode,
		                    String requestBody,
		                    String responseBody,
		                    String theLastError
		) {
			Method = theMethod;
			Success = theSuccess;
			HTTPResponseCode = responseCode;
			SOAPRequestBody = requestBody;
			SOAPResponseBody = responseBody;
			LastError = theLastError;
		}

		// AddEFT constructor
		public EPPSResponse(
		                    String theMethod,
		                    Boolean theSuccess,
		                    Integer responseCode,
		                    String requestBody,
		                    String responseBody,
		                    String theLastError,
		                    Integer theID
		) {
			this(theMethod, theSuccess, responseCode, requestBody, responseBody, theLastError);
			EftTransactionID = theID;
		}

		// Find EFT constructor
		public EPPSResponse(
		                    String theMethod,
		                    Boolean theSuccess,
		                    Integer responseCode,
		                    String requestBody,
		                    String responseBody,
		                    String theLastError,
		                    Map<String, FindEFT_Wrapper> theFoundEFTs
		) {
			this(theMethod, theSuccess, responseCode, requestBody, responseBody, theLastError);
			FoundEFTs = theFoundEFTs;
		}

		// ✅ Find Fee constructor (NEW)
		public EPPSResponse(
		                    String theMethod,
		                    Boolean theSuccess,
		                    Integer responseCode,
		                    String requestBody,
		                    String responseBody,
		                    String theLastError,
		                    Map<String, FindFee_Wrapper> theFoundFees
		) {
			this(theMethod, theSuccess, responseCode, requestBody, responseBody, theLastError);
			FoundFees = theFoundFees;
		}

		// for addFee2
		public EPPSResponse(
		                    String theMethod,
		                    Boolean theSuccess,
		                    Integer responseCode,
		                    String requestBody,
		                    String responseBody,
		                    String theLastError,
		                    String theFeeID
		) {
			this(theMethod, theSuccess, responseCode, requestBody, responseBody, theLastError);
			this.FeeID = theFeeID;
		}
	}

	/* =======================
	  REQUEST / RESPONSE WRAPPERS
	  ======================= */

	public class Cardholder_Wrapper {
		public EPPSOperation Operation;
		public String RecordID;
		public String CardHolderID;
		public String FirstName;
		public String LastName;
		public DateTime DateOfBirth;
		public String SSN;
		public String Street;
		public String City;
		public String State;
		public String Zip;
		public String PhoneNumber;
		public String EmailAddress;

		public Cardholder_Wrapper(
		                          EPPSOperation theOperation,
		                          String theRecordID,
		                          String theCardHolderID,
		                          String theFirstName,
		                          String theLastName,
		                          String theStreet,
		                          String theCity,
		                          String theState,
		                          String theZip,
		                          String thePhoneNumber,
		                          String theEmailAddress
		) {
			Operation = theOperation;
			RecordID = theRecordID;
			CardHolderID = theCardHolderID;
			FirstName = theFirstName;
			LastName = theLastName;
			Street = theStreet;
			City = theCity;
			State = theState;
			Zip = theZip;
			PhoneNumber = thePhoneNumber;
			EmailAddress = theEmailAddress;
		}
	}

	public class EFT_Wrapper {

		public String CardHolderID;
		public DateTime EftDate;
		public Decimal EftAmount;
		public Decimal EftFee;
		public String AccountNumber;
		public String RoutingNumber;
		public String AccountType;
		public String Memo;
		public String EftTransactionID;

		public EFT_Wrapper() { }

		public EFT_Wrapper(
		                   String theCardHolderID,
		                   DateTime theEftDate,
		                   Decimal theEftAmount,
		                   Decimal theEftFee,
		                   String theAccountNumber,
		                   String theRoutingNumber,
		                   String theAccountType,
		                   String theMemo,
		                   String theEftTransactionID
		) {
			this.CardHolderID = theCardHolderID;
			this.EftDate = theEftDate;
			this.EftAmount = theEftAmount;
			this.EftFee = theEftFee;
			this.AccountNumber = theAccountNumber;
			this.RoutingNumber = theRoutingNumber;
			this.AccountType = theAccountType;
			this.Memo = theMemo;
			this.EftTransactionID = theEftTransactionID;
		}
	}

	public class FindEFT_Wrapper {
		public String CardHolderId;
		public String EftTransactionID;
		public DateTime EftDate;
		public Decimal EftAmount;
		public String AccountNumber;
		public String RoutingNumber;
		public String Memo;
		public String StatusCode;
		public DateTime StatusDate;
		public DateTime CreatedDate;
		public DateTime SettledDate;
		public DateTime ReturnedDate;
		public String NSFReturnCode;
	}

	public class Fee_Wrapper {

		// === Required Inputs ===
		public String CardHolderID;
		public Datetime FeeDate;
		public Decimal FeeAmount;

		// === NEW PER WSDL ===
		public String AccountNumber; // <AccountNumber>
		public String RoutingNumber; // <RoutingNumber>
		public String FeeID;

		// === Optional ===
		public String Description;
		public String FeeType;

		public String PaidToName;
		public String PaidToPhone;
		public String PaidToStreet;
		public String PaidToStreet2;
		public String PaidToCity;
		public String PaidToState;
		public String PaidToZip;

		public String ContactName;
		public String PaidToCustomerNumber;

		public Fee_Wrapper() { }

		public Fee_Wrapper(
		                   String cardHolderId,
		                   Datetime feeDate,
		                   Decimal feeAmount,
		                   String accountNumber,
		                   String routingNumber
		) {
			this.CardHolderID = cardHolderId;
			this.FeeDate = feeDate;
			this.FeeAmount = feeAmount;
			this.AccountNumber = accountNumber;
			this.RoutingNumber = routingNumber;
		}
	}

	/****************************************************************************
	 *  ADD OPERATIONS OUTPUT WRAPPER – scalar only
	 ****************************************************************************/
	public class AddResult_Wrapper {
		public String CardHolderID;
		public String FeeID;
		public String EftTransactionID;
		public String StatusCode;
		public Datetime StatusDate;
		public String Message;
		public String AccountNumber; // <AccountNumber>
		public String RoutingNumber; // <RoutingNumber>
	}

	public class FindFeeByCardHolderID_Wrapper {
		public String CardHolderID;
		public FindFeeByCardHolderID_Wrapper() { }
		public FindFeeByCardHolderID_Wrapper(String cardHolderId) {
			CardHolderID = cardHolderId;
		}
	}

	// ✅ Find Fee RESPONSE wrapper (NEW)
	public class FindFee_Wrapper {
		public String FeeID;
		public String CardHolderID;
		public String EftTransactionID;
		public Datetime FeeDate;
		public Decimal FeeAmount;
		public String Description;
		public String FeeType;
		public String StatusCode;
		public Datetime StatusDate;
	}

	public class FindEftByIDandDate_Wrapper {
		public String CardHolderID;
		public Datetime CreateDateFrom;
		public Datetime CreateDateTo;

		public FindEftByIDandDate_Wrapper() { }
		public FindEftByIDandDate_Wrapper(String chId, Datetime fromDate, Datetime toDate) {
			System.debug('🔥 CONSTRUCTOR HIT: ' + chId);
			this.CardHolderID = chId;
			CreateDateFrom = fromDate;
			CreateDateTo = toDate;
			System.debug('CardHolderID ' + CardHolderID);
		}
	}

	/**
	 * Returns all EPPS_Fee__mdt records keyed by MasterLabel
	 */
	public static Map<String, EPPS_Fee__mdt> getFeesByLabel() {

		Map<String, EPPS_Fee__mdt> results = new Map<String, EPPS_Fee__mdt> ();

		for (EPPS_Fee__mdt fee :[
		     SELECT MasterLabel,
		     DeveloperName,
		     Fee_Description__c,
		     Fee_Type__c,
		     Is_Settlement__c
		     FROM EPPS_Fee__mdt
		     ]) {
			results.put(fee.MasterLabel, fee);
		}

		return results;
	}

	/* =======================
	  HELPERS
	  ======================= */

	public static FindEFT_Wrapper FindEFTByTransactionID(
	                                                     List<FindEFT_Wrapper> theEFTs,
	                                                     String theTransactionID
	) {
		for (FindEFT_Wrapper w : theEFTs) {
			if (w.EftTransactionID == theTransactionID) {
				return w;
			}
		}
		return null;
	}

	public static Date getDateAfterBusinessDays(Integer businessDaysAhead) {
		BusinessHours bh = [
			SELECT Id
			FROM BusinessHours
			WHERE Name = 'Payment Business Hours'
			LIMIT 1
		];

		// Anchor at TODAY at 9:00 AM so we count full business days
		Datetime startDt = Datetime.newInstance(
			Date.today(),
			Time.newInstance(9, 0, 0, 0)
		);

		// 8 business hours per business day
		Long businessMillis = businessDaysAhead * 8 * 60 * 60 * 1000;

		Datetime result = BusinessHours.add(
			bh.Id,
			startDt,
			businessMillis
		);

		return result.date();
}

	/* =======================
	  EXCEPTION UTILITIES
	  ======================= */

	public static String getExceptionDetails(Exception ex) {
		List<String> lines = new List<String> ();
		lines.add('Exception Type: ' + ex.getTypeName());
		lines.add('Message       : ' + ex.getMessage());
		lines.add('Occurred At   : ' + Datetime.now().format());
		lines.add('User Id       : ' + UserInfo.getUserId());
		Integer lineNumber = extractLineNumber(ex.getStackTraceString());
		if (lineNumber != null) lines.add('Line Number   : ' + lineNumber);
		lines.add(ex.getStackTraceString());
		return String.join(lines, '\n');
	}

	private static Integer extractLineNumber(String stackTrace) {
		if (String.isBlank(stackTrace)) return null;
		Matcher m = Pattern.compile('line (\\d+)').matcher(stackTrace);
		return m.find() ? Integer.valueOf(m.group(1)) : null;
	}

	public static DateTime safeDate(DateTime val) {
		return val;
	}

	public static string safeString(String val)
	{
		if (String.isEmpty(val))
		return '';
		else
		return val;
	}

	public static string safeStringFromInt(integer val)
	{
		if (val == null)
		return '';
		else
		return String.valueOf(val);
	}
}