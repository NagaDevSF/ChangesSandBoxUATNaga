public class EPPSIntegrationMethodsEnhanced {

	static final String Success = 'Success';
	static final String Error = 'Error';

	public static EPPSHelperMethods.EPPSResponse addCardholder(EPPSHelperMethods.Cardholder_Wrapper wrapper) {

		HttpRequest req = new HttpRequest();
		req.setEndpoint('callout:EPPS_Named_Credential/eftservice.asmx');
		req.setMethod('POST');
		req.setHeader('Content-Type', 'text/xml; charset=utf-8');
		req.setHeader('SOAPAction', '"http://tempuri.org/AddCardHolder"');
		req.setTimeout(120000);

		String soapBody = BuildAddCardHolderXML(wrapper);
		req.setBody(soapBody);

		System.debug('SOAP REQUEST:\n' + soapBody);

		Http http = new Http();
		HttpResponse res;

		try {
			res = http.send(req);
		} catch(System.CalloutException ex) {
			// Transport-level failure (timeout, 500, SSL, etc.)
			return new EPPSHelperMethods.EPPSResponse(
			                                          'AddCardHolder',
			                                          false,
			                                          - 1,
			                                          soapBody,
			                                          null,
			                                          'Transport error: ' + ex.getMessage()
			);
		}

		// Non-200 HTTP response (rare but possible)
		if (res.getStatusCode() != 200) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'AddCardHolder',
			                                          false,
			                                          res.getStatusCode(),
			                                          soapBody,
			                                          res.getBody(),
			                                          'HTTP error: ' + res.getStatus()
			);
		}

		// HTTP 200 — must inspect SOAP body
		return parseAddCardHolderSoapResponse(soapBody, res.getBody());
	}

	static String BuildAddCardHolderXML(EPPSHelperMethods.Cardholder_Wrapper wrapper) {

		String xml =
		'<?xml version="1.0" encoding="utf-8"?>' +
		'<soap:Envelope ' +
		'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' +
		'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
		'xmlns:xsd="http://www.w3.org/2001/XMLSchema">' +
		'<soap:Body>' +
		'<AddCardHolder xmlns="http://tempuri.org/">' +
		'<UserName>{!$Credential.EPPS_External_Credential.Username}</UserName>' +
		'<PassWord>{!$Credential.EPPS_External_Credential.Password}</PassWord>' +
		'<CardHolderID>' + safe(wrapper.CardHolderID) + '</CardHolderID>' +
		'<FirstName>' + safe(wrapper.FirstName) + '</FirstName>' +
		'<LastName>' + safe(wrapper.LastName) + '</LastName>' +
		'<DateOfBirth>1985-06-15T00:00:00</DateOfBirth>' +
		// TODO add back in date of birth
		//'<DateOfBirth></DateOfBirth>' +
		'<SSN></SSN>' +
		'<Street>' + safe(wrapper.Street) + '</Street>' +
		'<City>' + safe(wrapper.City) + '</City>' +
		'<State>' + safe(wrapper.State).toUpperCase() + '</State>' +
		'<Zip>' + safe(wrapper.Zip) + '</Zip>' +
		'<PhoneNumber>' + normalizePhone(wrapper.PhoneNumber) + '</PhoneNumber>' +
		'<EmailAddress>' + safe(wrapper.EmailAddress) + '</EmailAddress>' +

		'</AddCardHolder>' +
		'</soap:Body>' +
		'</soap:Envelope>';

		return xml;
	}

	private static EPPSHelperMethods.EPPSResponse parseAddCardHolderSoapResponse(String requestXml, String responseXml) {

		try {
			Dom.Document doc = new Dom.Document();
			doc.load(responseXml);

			Dom.XmlNode envelope = doc.getRootElement();
			Dom.XmlNode body = envelope.getChildElement('Body', 'http://schemas.xmlsoap.org/soap/envelope/');

			if (body == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'AddCardHolder',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing Body'
				);
			}

			// 🔴 SOAP Fault (HTTP 200 but failure)
			Dom.XmlNode fault = body.getChildElement('Fault', 'http://schemas.xmlsoap.org/soap/envelope/');

			if (fault != null) {
				String faultString = getFaultText(fault, 'faultstring');
				String faultCode = getFaultText(fault, 'faultcode');

				return new EPPSHelperMethods.EPPSResponse(
				                                          'AddCardHolder',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'SOAP Fault [' + faultCode + ']: ' + faultString
				);
			}

			// Success / business response
			Dom.XmlNode responseNode = body.getChildElement('AddCardHolderResponse', 'http://tempuri.org/');

			Dom.XmlNode resultNode = responseNode == null
			? null
			: responseNode.getChildElement('AddCardHolderResult', 'http://tempuri.org/');

			if (resultNode == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'AddCardHolder',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing AddCardHolderResult'
				);
			}

			String message = getChildText(resultNode, 'Message');
			String status = getChildText(resultNode, 'StatusCode');

			Boolean success = (message == 'Success');

			return new EPPSHelperMethods.EPPSResponse(
			                                          'AddCardHolder',
			                                          success,
			                                          200,
			                                          requestXml,
			                                          responseXml,
			                                          message
			);

		} catch(Exception ex) {
			// XML parse error or unexpected structure
			return new EPPSHelperMethods.EPPSResponse(
			                                          'AddCardHolder',
			                                          false,
			                                          200,
			                                          requestXml,
			                                          responseXml,
			                                          'SOAP parse error: ' + ex.getMessage()
			);
		}
	}

	public static EPPSHelperMethods.EPPSResponse updateCardholder(EPPSHelperMethods.Cardholder_Wrapper wrapper) {

		HttpRequest req = new HttpRequest();
		req.setEndpoint('callout:EPPS_Named_Credential/eftservice.asmx');
		req.setMethod('POST');
		req.setHeader('Content-Type', 'text/xml; charset=utf-8');

		// WSDL-defined SOAPAction
		req.setHeader('SOAPAction', '"http://tempuri.org/UpdateCardHolder"');

		req.setTimeout(120000);

		String soapBody = buildUpdateCardHolderXML(wrapper);
		req.setBody(soapBody);

		System.debug('SOAP REQUEST:\n' + soapBody);

		Http http = new Http();
		HttpResponse res;

		try {
			res = http.send(req);
		} catch(System.CalloutException ex) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'UpdateCardHolder',
			                                          false,
			                                          - 1,
			                                          soapBody,
			                                          null,
			                                          'Transport error: ' + ex.getMessage()
			);
		}

		if (res.getStatusCode() != 200) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'UpdateCardHolder',
			                                          false,
			                                          res.getStatusCode(),
			                                          soapBody,
			                                          res.getBody(),
			                                          'HTTP error: ' + res.getStatus()
			);
		}

		return parseUpdateCardHolderSoapResponse(soapBody, res.getBody());
	}

	private static EPPSHelperMethods.EPPSResponse parseUpdateCardHolderSoapResponse(String requestXml, String responseXml) {

		try {
			Dom.Document doc = new Dom.Document();
			doc.load(responseXml);

			Dom.XmlNode envelope = doc.getRootElement();
			Dom.XmlNode body = envelope.getChildElement('Body', 'http://schemas.xmlsoap.org/soap/envelope/');

			if (body == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'UpdateCardHolder',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing Body'
				);
			}

			// SOAP Fault handling (HTTP 200 but failure)
			Dom.XmlNode fault = body.getChildElement('Fault', 'http://schemas.xmlsoap.org/soap/envelope/');

			if (fault != null) {
				String faultString = getFaultText(fault, 'faultstring');
				String faultCode = getFaultText(fault, 'faultcode');

				return new EPPSHelperMethods.EPPSResponse(
				                                          'UpdateCardHolder',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'SOAP Fault [' + faultCode + ']: ' + faultString
				);
			}

			Dom.XmlNode responseNode = body.getChildElement('UpdateCardHolderResponse', 'http://tempuri.org/');

			Dom.XmlNode resultNode = responseNode == null
			? null
			: responseNode.getChildElement('UpdateCardHolderResult', 'http://tempuri.org/');

			if (resultNode == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'UpdateCardHolder',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing UpdateCardHolderResult'
				);
			}

			String message = getChildText(resultNode, 'Message');
			String statusCode = getChildText(resultNode, 'StatusCode');

			Boolean success = (message == 'Success' || statusCode == '0');

			return new EPPSHelperMethods.EPPSResponse(
			                                          'UpdateCardHolder',
			                                          success,
			                                          200,
			                                          requestXml,
			                                          responseXml,
			                                          message
			);

		} catch(Exception ex) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'UpdateCardHolder',
			                                          false,
			                                          200,
			                                          requestXml,
			                                          responseXml,
			                                          'SOAP parse error: ' + ex.getMessage()
			);
		}
	}

	private static String buildUpdateCardHolderXML(EPPSHelperMethods.Cardholder_Wrapper wrapper) {

		return
		'<?xml version="1.0" encoding="utf-8"?>' +
		'<soap:Envelope ' +
		'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' +
		'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
		'xmlns:xsd="http://www.w3.org/2001/XMLSchema">' +
		'<soap:Body>' +
		'<UpdateCardHolder xmlns="http://tempuri.org/">' +
		'<UserName>{!$Credential.EPPS_External_Credential.Username}</UserName>' +
		'<PassWord>{!$Credential.EPPS_External_Credential.Password}</PassWord>' +
		'<CardHolderID>' + safe(wrapper.CardHolderID) + '</CardHolderID>' +
		'<Street>' + safe(wrapper.Street) + '</Street>' +
		'<City>' + safe(wrapper.City) + '</City>' +
		'<State>' + safe(wrapper.State).toUpperCase() + '</State>' +
		'<Zip>' + safe(wrapper.Zip) + '</Zip>' +
		'<PhoneNumber>' + normalizePhone(wrapper.PhoneNumber) + '</PhoneNumber>' +
		'<EmailAddress>' + safe(wrapper.EmailAddress) + '</EmailAddress>' +
		'</UpdateCardHolder>' +
		'</soap:Body>' +
		'</soap:Envelope>';
	}

	////////////////////////////////////////////
	/// Add EFT
	////////////////////////////////////////////
	public static EPPSHelperMethods.EPPSResponse AddEFT(EPPSHelperMethods.EFT_Wrapper theEFTWrapper) {

		HttpRequest req = new HttpRequest();
		req.setEndpoint('callout:EPPS_Named_Credential/eftservice.asmx');
		req.setMethod('POST');
		req.setHeader('Content-Type', 'text/xml; charset=utf-8');

		String soapEnvelope = BuildAddEftXML(theEFTWrapper);

		System.debug('🔹 [AddEFT] SOAP Request:\n' + soapEnvelope);

		req.setBody(soapEnvelope);
		req.setTimeout(120000);

		Http http = new Http();
		HttpResponse res = http.send(req);

		System.debug('🔹 [AddEFT] HTTP Status: ' + res.getStatusCode());
		System.debug('🔹 [AddEFT] SOAP Response:\n' + res.getBody());

		String responseXml = res.getBody();

		// ---- Transport error or SOAP Fault ----
		if (res.getStatusCode() != 200 || isSoapFault(responseXml)) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'AddEFT',
			                                          false,
			                                          res.getStatusCode(),
			                                          req.getBody(),
			                                          responseXml,
			                                          getSoapFaultMessage(responseXml),
			                                          - 1
			);
		}

		// ---- Success-path parsing (namespace + nesting safe) ----
		String statusCode = getSoapValue(responseXml, 'StatusCode');
		String message = getSoapValue(responseXml, 'Message');
		String eftTransactionStr = getSoapValue(responseXml, 'EftTransactionID');

		Boolean success = String.isNotBlank(statusCode) && !statusCode.toLowerCase().contains('error');

		Integer eftTransactionId = - 1;
		if (String.isNotBlank(eftTransactionStr)) {
			try {
				eftTransactionId = Integer.valueOf(eftTransactionStr);
			} catch(Exception ex) {
				System.debug('⚠️ [AddEFT] Failed to parse EftTransactionID: ' + eftTransactionStr);
			}
		}

		return new EPPSHelperMethods.EPPSResponse(
		                                          'AddEFT',
		                                          success,
		                                          res.getStatusCode(),
		                                          req.getBody(),
		                                          responseXml,
		                                          message,
		                                          eftTransactionId
		);
	}

	static String BuildAddEftXML(EPPSHelperMethods.EFT_Wrapper theEFTWrapper) {

		String xml =
		'<?xml version="1.0" encoding="utf-8"?>' +
		'<soap:Envelope ' +
		'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' +
		'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
		'xmlns:xsd="http://www.w3.org/2001/XMLSchema">' +
		'<soap:Body>' +
		'<AddEft xmlns="http://tempuri.org/">' +

		'<UserName>{!$Credential.EPPS_External_Credential.Username}</UserName>' +
		'<PassWord>{!$Credential.EPPS_External_Credential.Password}</PassWord>' +

		'<CardHolderID>' + safe(theEFTWrapper.CardHolderID) + '</CardHolderID>' +
		'<EftDate>' + safe(String.valueOf(theEFTWrapper.EftDate).replace(' ', 'T')) + '</EftDate>' +
		'<EftAmount>' + safe(theEFTWrapper.EftAmount != null ? theEFTWrapper.EftAmount.setScale(2).toPlainString() : null) + '</EftAmount>' +
		'<EftFee>' + safe(theEFTWrapper.EftFee != null ? theEFTWrapper.EftFee.setScale(2).toPlainString() : null) + '</EftFee>' +
		'<BankName></BankName>' +
		'<BankCity></BankCity>' +
		'<BankState></BankState>' +

		'<AccountNumber>' + safe(theEFTWrapper.AccountNumber) + '</AccountNumber>' +
		'<RoutingNumber>' + safe(theEFTWrapper.RoutingNumber) + '</RoutingNumber>' +
		'<AccountType>' + safe(theEFTWrapper.AccountType) + '</AccountType>' +
		'<Memo>' + safe(theEFTWrapper.Memo) + '</Memo>' +

		'</AddEft>' +
		'</soap:Body>' +
		'</soap:Envelope>';

		return xml;
	}

	public static EPPSHelperMethods.EPPSResponse addFee(EPPSHelperMethods.Fee_Wrapper wrapper) {
		HttpRequest req = new HttpRequest();
		req.setEndpoint('callout:EPPS_Named_Credential/eftservice.asmx');
		req.setMethod('POST');
		req.setHeader('Content-Type', 'text/xml; charset=utf-8');
		req.setHeader('SOAPAction', '"http://tempuri.org/AddFee"');
		req.setTimeout(120000);

		String soapBody = buildAddFeeXML(wrapper);
		req.setBody(soapBody);

		System.debug('SOAP REQUEST:\n' + soapBody);

		Http http = new Http();
		HttpResponse res;

		try {
			res = http.send(req);
		} catch(System.CalloutException ex) {
			// Transport-level failure
			return new EPPSHelperMethods.EPPSResponse(
			                                          'AddFee',
			                                          false,
			                                          - 1,
			                                          soapBody,
			                                          null,
			                                          'Transport error: ' + ex.getMessage()
			);
		}

		// Non-200 HTTP response
		if (res.getStatusCode() != 200) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'AddFee',
			                                          false,
			                                          res.getStatusCode(),
			                                          soapBody,
			                                          res.getBody(),
			                                          'HTTP error: ' + res.getStatus()
			);
		}

		// HTTP 200 — inspect SOAP body
		return parseAddFeeSoapResponse(soapBody, res.getBody());
	}

	private static String buildAddFeeXML(EPPSHelperMethods.Fee_Wrapper w) {
		String xml =
		'<?xml version="1.0" encoding="utf-8"?>' +
		'<soap:Envelope ' +
		'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' +
		'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
		'xmlns:xsd="http://www.w3.org/2001/XMLSchema">' +
		'<soap:Body>' +
		'<AddFee xmlns="http://tempuri.org/">' +
		'<UserName>{!$Credential.EPPS_External_Credential.Username}</UserName>' +
		'<PassWord>{!$Credential.EPPS_External_Credential.Password}</PassWord>' +
		'<CardHolderID>' + safe(w.CardHolderID) + '</CardHolderID>' +
		'<FeeDate>' + safe(formatSoapDateTime(w.FeeDate)) + '</FeeDate>' +
		'<FeeAmount>' + safe(soapDecimal(w.FeeAmount)) + '</FeeAmount>' +
		'<Description>' + safe(w.Description) + '</Description>' +
		'<FeeType>' + safe(w.FeeType) + '</FeeType>' +
		'<PaidToName>' + safe(w.PaidToName) + '</PaidToName>' +
		'<PaidToPhone>' + safe(w.PaidToPhone) + '</PaidToPhone>' +
		'<PaidToStreet>' + safe(w.PaidToStreet) + '</PaidToStreet>' +
		'<PaidToStreet2>' + safe(w.PaidToStreet2) + '</PaidToStreet2>' +
		'<PaidToCity>' + safe(w.PaidToCity) + '</PaidToCity>' +
		'<PaidToState>' + safe(w.PaidToState) + '</PaidToState>' +
		'<PaidToZip>' + safe(w.PaidToZip) + '</PaidToZip>' +
		'<ContactName>' + safe(w.ContactName) + '</ContactName>' +
		'<PaidToCustomerNumber>' + safe(w.PaidToCustomerNumber) + '</PaidToCustomerNumber>' +
		'</AddFee>' +
		'</soap:Body>' +
		'</soap:Envelope>';

		return xml;
	}

	private static EPPSHelperMethods.EPPSResponse parseAddFeeSoapResponse(String requestXml, String responseXml) {
		try {
			Dom.Document doc = new Dom.Document();
			doc.load(responseXml);

			Dom.XmlNode envelope = doc.getRootElement();
			Dom.XmlNode body = envelope.getChildElement('Body', 'http://schemas.xmlsoap.org/soap/envelope/');

			if (body == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'AddFee',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing Body'
				);
			}

			// 🔴 SOAP Fault (HTTP 200 but failure)
			Dom.XmlNode fault = body.getChildElement(
			                                         'Fault',
			                                         'http://schemas.xmlsoap.org/soap/envelope/'
			);

			if (fault != null) {
				String faultString = getFaultText(fault, 'faultstring');
				String faultCode = getFaultText(fault, 'faultcode');

				return new EPPSHelperMethods.EPPSResponse(
				                                          'AddFee',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'SOAP Fault [' + faultCode + ']: ' + faultString
				);
			}

			Dom.XmlNode responseNode = body.getChildElement('AddFeeResponse', 'http://tempuri.org/');

			Dom.XmlNode resultNode = responseNode == null
			? null
			: responseNode.getChildElement('AddFeeResult', 'http://tempuri.org/');

			if (resultNode == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'AddFee',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing AddFeeResult'
				);
			}

			String message = getChildText(resultNode, 'Message');
			String statusCode = getChildText(resultNode, 'StatusCode');

			Boolean success = statusCode == '0' || statusCode == 'Success' || message == 'Success';

			return new EPPSHelperMethods.EPPSResponse(
			                                          'AddFee',
			                                          success,
			                                          200,
			                                          requestXml,
			                                          responseXml,
			                                          message
			);

		} catch(Exception ex) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'AddFee',
			                                          false,
			                                          200,
			                                          requestXml,
			                                          responseXml,
			                                          'SOAP parse error: ' + ex.getMessage()
			);
		}
	}

	public static EPPSHelperMethods.EPPSResponse addFee2(EPPSHelperMethods.Fee_Wrapper wrapper) {

		HttpRequest req = new HttpRequest();
		req.setEndpoint('callout:EPPS_Named_Credential/eftservice.asmx');
		req.setMethod('POST');
		req.setHeader('Content-Type', 'text/xml; charset=utf-8');
		req.setHeader('SOAPAction', '"http://tempuri.org/AddFee2"');
		req.setTimeout(120000);

		String soapBody = buildAddFee2XML(wrapper);
		req.setBody(soapBody);

		System.debug('SOAP REQUEST (AddFee2):\n' + soapBody);

		Http http = new Http();
		HttpResponse res;

		try {
			res = http.send(req);
		} catch(System.CalloutException ex) {

			return new EPPSHelperMethods.EPPSResponse(
			                                          'AddFee2',
			                                          false,
			                                          - 1,
			                                          soapBody,
			                                          null,
			                                          'Transport error: ' + ex.getMessage()
			);
		}

		if (res.getStatusCode() != 200) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'AddFee2',
			                                          false,
			                                          res.getStatusCode(),
			                                          soapBody,
			                                          res.getBody(),
			                                          'HTTP error: ' + res.getStatus()
			);
		}

		return parseAddFee2SoapResponse(soapBody, res.getBody());
	}

	/****************************************************************************
	 *  ADDFEE2 XML BUILDER – WITH NEW FIELDS
	 ****************************************************************************/
	static String buildAddFee2XML(EPPSHelperMethods.Fee_Wrapper w) {

		String xml =
		'<?xml version="1.0" encoding="utf-8"?>' +
		'<soap:Envelope ' +
		'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' +
		'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
		'xmlns:xsd="http://www.w3.org/2001/XMLSchema">' +
		'<soap:Body>' +

		'<AddFee2 xmlns="http://tempuri.org/">' +

		'<UserName>{!$Credential.EPPS_External_Credential.Username}</UserName>' +
		'<PassWord>{!$Credential.EPPS_External_Credential.Password}</PassWord>' +

		'<CardHolderID>' + safe(w.CardHolderID) + '</CardHolderID>' +
		'<FeeDate>' + safe(String.valueOf(w.FeeDate).replace(' ', 'T')) + '</FeeDate>' +
		'<FeeAmount>' +
		safe(w.FeeAmount != null
		     ? w.FeeAmount.setScale(2).toPlainString()
		     : null
		) +
		'</FeeAmount>' +
		'<Description>' + safe(w.Description) + '</Description>' +
		'<FeeType>' + safe(w.FeeType) + '</FeeType>' +
		'<PaidToName>' + safe(w.PaidToName) + '</PaidToName>' +
		'<PaidToPhone>' + safe(w.PaidToPhone) + '</PaidToPhone>' +
		'<PaidToStreet>' + safe(w.PaidToStreet) + '</PaidToStreet>' +
		'<PaidToStreet2>' + safe(w.PaidToStreet2) + '</PaidToStreet2>' +
		'<PaidToCity>' + safe(w.PaidToCity) + '</PaidToCity>' +
		'<PaidToState>' + safe(w.PaidToState) + '</PaidToState>' +
		'<PaidToZip>' + safe(w.PaidToZip) + '</PaidToZip>' +
		'<ContactName>' + safe(w.ContactName) + '</ContactName>' +
		'<PaidToCustomerNumber>' + safe(w.PaidToCustomerNumber) + '</PaidToCustomerNumber>' +
		'<AccountNumber>' + safe(w.AccountNumber) + '</AccountNumber>' +
		'<RoutingNumber>' + safe(w.RoutingNumber) + '</RoutingNumber>' +

		'</AddFee2>' +
		'</soap:Body>' +
		'</soap:Envelope>';

		return xml;
	}

	/****************************************************************************
	 *  ADDFEE2 PARSER – CLEAN SEPARATION
	 ****************************************************************************/
	private static EPPSHelperMethods.EPPSResponse parseAddFee2SoapResponse(
	                                                                       String requestXml,
	                                                                       String responseXml
	) {
		try {
			Dom.Document doc = new Dom.Document();
			doc.load(responseXml);

			// ===============================
			// SOAP Envelope / Body
			// ===============================
			Dom.XmlNode envelope = doc.getRootElement();

			Dom.XmlNode body = envelope.getChildElement('Body', 'http://schemas.xmlsoap.org/soap/envelope/');

			if (body == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'AddFee2',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing Body'
				);
			}

			// ===============================
			// SOAP Fault handling
			// ===============================
			Dom.XmlNode fault = body.getChildElement(
			                                         'Fault',
			                                         'http://schemas.xmlsoap.org/soap/envelope/'
			);

			if (fault != null) {
				String faultMessage = null;

				Dom.XmlNode faultStringNode = fault.getChildElement('faultstring', null);
				if (faultStringNode != null) {
					faultMessage = faultStringNode.getText();
				}

				return new EPPSHelperMethods.EPPSResponse(
				                                          'AddFee2',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          faultMessage != null ? faultMessage : 'SOAP Fault'
				);
			}

			// ===============================
			// AddFee2Response / Result
			// ===============================
			Dom.XmlNode responseNode = body.getChildElement('AddFee2Response', 'http://tempuri.org/');

			if (responseNode == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'AddFee2',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing AddFee2Response'
				);
			}

			Dom.XmlNode resultNode = responseNode.getChildElement(
			                                                      'AddFee2Result',
			                                                      'http://tempuri.org/'
			);

			if (resultNode == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'AddFee2',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing AddFee2Result'
				);
			}

			// ===============================
			// Extract fields (tempuri namespace)
			// ===============================
			String cardHolderId = getChildText(resultNode, 'CardHolderID');
			String feeId = getChildText(resultNode, 'FeeID');
			String eftTxnId = getChildText(resultNode, 'EftTransactionID');
			String statusCode = getChildText(resultNode, 'StatusCode');
			String message = getChildText(resultNode, 'Message');

			Datetime statusDate = null;
			String statusDateStr = getChildText(resultNode, 'StatusDate');
			if (String.isNotBlank(statusDateStr)) {
				statusDate = Datetime.valueOfGmt(statusDateStr.replace('T', ' '));
			}

			Boolean success =
			String.isNotBlank(message) &&
			message.equalsIgnoreCase('Success');

			// ===============================
			// Build response
			// ===============================
			EPPSHelperMethods.EPPSResponse resp =
			new EPPSHelperMethods.EPPSResponse(
			                                   'AddFee2',
			                                   success,
			                                   200,
			                                   requestXml,
			                                   responseXml,
			                                   message,
			                                   feeId
			);

			// Optional scalar stamps (if you use them elsewhere)
			if (String.isNotBlank(eftTxnId)) {
				try {
					resp.EftTransactionID = Integer.valueOf(eftTxnId);
				} catch(Exception ignore) { }
			}

			// If you later add FeeID to EPPSResponse, stamp it here
			// resp.FeeID = feeId;

			return resp;

		} catch(Exception ex) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'AddFee2',
			                                          false,
			                                          200,
			                                          requestXml,
			                                          responseXml,
			                                          'SOAP parse error: ' + ex.getMessage()
			);
		}
	}


	public static EPPSHelperMethods.EPPSResponse findFeeByCardHolderID(
	                                                                   EPPSHelperMethods.FindFeeByCardHolderID_Wrapper wrapper
	) {
		HttpRequest req = new HttpRequest();
		req.setEndpoint('callout:EPPS_Named_Credential/eftservice.asmx');
		req.setMethod('POST');
		req.setHeader('Content-Type', 'text/xml; charset=utf-8');
		req.setHeader('SOAPAction', '"http://tempuri.org/FindFeeByCardHolderID"');
		req.setTimeout(120000);

		String soapBody = buildFindFeeByCardHolderIDXML(wrapper);
		req.setBody(soapBody);

		System.debug('SOAP REQUEST:\n' + soapBody);

		Http http = new Http();
		HttpResponse res;

		try {
			res = http.send(req);
		} catch(System.CalloutException ex) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'FindFeeByCardHolderID',
			                                          false,
			                                          - 1,
			                                          soapBody,
			                                          null,
			                                          'Transport error: ' + ex.getMessage()
			);
		}

		if (res.getStatusCode() != 200) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'FindFeeByCardHolderID',
			                                          false,
			                                          res.getStatusCode(),
			                                          soapBody,
			                                          res.getBody(),
			                                          'HTTP error: ' + res.getStatus()
			);
		}

		return parseFindFeeByCardHolderIDSoapResponse(soapBody, res.getBody());
	}

	private static String buildFindFeeByCardHolderIDXML(EPPSHelperMethods.FindFeeByCardHolderID_Wrapper w) {

		return
		'<?xml version="1.0" encoding="utf-8"?>' +
		'<soap:Envelope ' +
		'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' +
		'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
		'xmlns:xsd="http://www.w3.org/2001/XMLSchema">' +
		'<soap:Body>' +
		'<FindFeeByCardHolderID xmlns="http://tempuri.org/">' +
		'<UserName>{!$Credential.EPPS_External_Credential.Username}</UserName>' +
		'<PassWord>{!$Credential.EPPS_External_Credential.Password}</PassWord>' +
		'<CardHolderID>' + safe(w.CardHolderID) + '</CardHolderID>' +
		'</FindFeeByCardHolderID>' +
		'</soap:Body>' +
		'</soap:Envelope>';
	}

	private static EPPSHelperMethods.EPPSResponse parseFindFeeByCardHolderIDSoapResponse(String requestXml, String responseXml) {

		try {
			Dom.Document doc = new Dom.Document();
			doc.load(responseXml);

			Dom.XmlNode body =
			doc.getRootElement()
			.getChildElement('Body', 'http://schemas.xmlsoap.org/soap/envelope/');

			if (body == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'FindFeeByCardHolderID',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing Body'
				);
			}

			// 🔴 SOAP Fault
			Dom.XmlNode fault =
			body.getChildElement('Fault', 'http://schemas.xmlsoap.org/soap/envelope/');
			if (fault != null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'FindFeeByCardHolderID',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'SOAP Fault: ' + getFaultText(fault, 'faultstring')
				);
			}

			Dom.XmlNode resultNode =
			body.getChildElement('FindFeeByCardHolderIDResponse', 'http://tempuri.org/')
			.getChildElement('FindFeeByCardHolderIDResult', 'http://tempuri.org/');

			if (resultNode == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'FindFeeByCardHolderID',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Missing FindFeeByCardHolderIDResult'
				);
			}

			String message = getChildText(resultNode, 'Message');

			// ✅ Parse Fee array
			Map<String, EPPSHelperMethods.FindFee_Wrapper> foundFees =
			new Map<String, EPPSHelperMethods.FindFee_Wrapper> ();

			Dom.XmlNode feeListNode =
			resultNode.getChildElement('FeeList', 'http://tempuri.org/');

			if (feeListNode != null) {
				for (Dom.XmlNode feeNode : feeListNode.getChildElements()) {

					EPPSHelperMethods.FindFee_Wrapper fee =
					new EPPSHelperMethods.FindFee_Wrapper();

					fee.FeeID = getChildText(feeNode, 'FeeID');
					fee.CardHolderID = getChildText(feeNode, 'CardHolderID');
					fee.FeeDate = parseDateTime(getChildText(feeNode, 'FeeDate'));
					fee.FeeAmount = parseDecimal(getChildText(feeNode, 'FeeAmount'));
					fee.Description = getChildText(feeNode, 'Description');
					fee.FeeType = getChildText(feeNode, 'FeeType');
					fee.StatusCode = getChildText(feeNode, 'StatusCode');
					fee.StatusDate = parseDateTime(getChildText(feeNode, 'StatusDate'));

					if (fee.FeeID != null) {
						foundFees.put(fee.FeeID, fee);
					}
				}
			}

			return new EPPSHelperMethods.EPPSResponse(
			                                          'FindFeeByCardHolderID',
			                                          true,
			                                          200,
			                                          requestXml,
			                                          responseXml,
			                                          message,
			                                          foundFees
			);

		} catch(Exception ex) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'FindFeeByCardHolderID',
			                                          false,
			                                          200,
			                                          requestXml,
			                                          responseXml,
			                                          'SOAP parse error: ' + ex.getMessage()
			);
		}
	}

	public static EPPSHelperMethods.EPPSResponse findEftByIDandDate(EPPSHelperMethods.FindEftByIDandDate_Wrapper wrapper) {

		HttpRequest req = new HttpRequest();
		req.setEndpoint('callout:EPPS_Named_Credential/eftservice.asmx');
		req.setMethod('POST');
		req.setHeader('Content-Type', 'text/xml; charset=utf-8');
		req.setHeader('SOAPAction', '"http://tempuri.org/FindEftByIDandDate"');
		req.setTimeout(120000);

		String soapBody = buildFindEftByIDandDateXML(wrapper);
		req.setBody(soapBody);

		System.debug('SOAP REQUEST:\n' + soapBody);

		Http http = new Http();
		HttpResponse res;

		try {
			res = http.send(req);
		} catch(System.CalloutException ex) {
			// Transport-level failure
			return new EPPSHelperMethods.EPPSResponse(
			                                          'FindEftByIDandDate',
			                                          false,
			                                          - 1,
			                                          soapBody,
			                                          null,
			                                          'Transport error: ' + ex.getMessage()
			);
		}

		// Non-200 HTTP response
		if (res.getStatusCode() != 200) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'FindEftByIDandDate',
			                                          false,
			                                          res.getStatusCode(),
			                                          soapBody,
			                                          res.getBody(),
			                                          'HTTP error: ' + res.getStatus()
			);
		}

		// HTTP 200 — inspect SOAP body
		return parseFindEftByIDandDateSoapResponse(soapBody, res.getBody());
	}
	private static String buildFindEftByIDandDateXML(EPPSHelperMethods.FindEftByIDandDate_Wrapper w) {

		String xml =
		'<?xml version="1.0" encoding="utf-8"?>' +
		'<soap:Envelope ' +
		'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' +
		'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
		'xmlns:xsd="http://www.w3.org/2001/XMLSchema">' +
		'<soap:Body>' +
		'<FindEftByIDandDate xmlns="http://tempuri.org/">' +
		'<UserName>{!$Credential.EPPS_External_Credential.Username}</UserName>' +
		'<PassWord>{!$Credential.EPPS_External_Credential.Password}</PassWord>' +
		'<CardHolderID>' + safe(w.CardHolderID) + '</CardHolderID>' +
		'<CreateDateFrom>' + safe(formatSoapDateTime(w.CreateDateFrom)) + '</CreateDateFrom>' +
		'<CreateDateTo>' + safe(formatSoapDateTime(w.CreateDateTo)) + '</CreateDateTo>' +
		'</FindEftByIDandDate>' +
		'</soap:Body>' +
		'</soap:Envelope>';

		return xml;
	}
	private static EPPSHelperMethods.EPPSResponse parseFindEftByIDandDateSoapResponse(String requestXml, String responseXml) {

		Dom.Document doc = new Dom.Document();
		doc.load(responseXml);

		Dom.XmlNode envelope = doc.getRootElement();

		// SOAP Body
		Dom.XmlNode body = envelope.getChildElement('Body', 'http://schemas.xmlsoap.org/soap/envelope/');

		if (body == null) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'FindEftByIDandDate',
			                                          false,
			                                          200,
			                                          requestXml,
			                                          responseXml,
			                                          'Missing SOAP Body'
			);
		}

		// Response node (tempuri namespace)
		Dom.XmlNode responseNode = body.getChildElement('FindEftByIDandDateResponse', 'http://tempuri.org/');

		if (responseNode == null) {
			System.debug('❌ Missing FindEftByIDandDateResponse');
			return emptyEftResponse(requestXml, responseXml);
		}

		Dom.XmlNode resultNode = responseNode.getChildElement('FindEftByIDandDateResult', 'http://tempuri.org/');

		if (resultNode == null) {
			System.debug('❌ Missing FindEftByIDandDateResult');
			return emptyEftResponse(requestXml, responseXml);
		}

		Dom.XmlNode eftListNode = resultNode.getChildElement(
		                                                     'EFTList',
		                                                     'http://tempuri.org/'
		);
		if (eftListNode == null) {
			System.debug('ℹ️ No EFTList node present');
			return emptyEftResponse(requestXml, responseXml);
		}

		Map<String, EPPSHelperMethods.FindEFT_Wrapper> foundEfts = new Map<String, EPPSHelperMethods.FindEFT_Wrapper> ();

		// Iterate EFTTransactionDetail nodes
		for (Dom.XmlNode eftNode : eftListNode.getChildElements()) {

			if (eftNode.getName() != 'EFTTransactionDetail') {
				continue;
			}

			EPPSHelperMethods.FindEFT_Wrapper w =
			new EPPSHelperMethods.FindEFT_Wrapper();

			w.CardHolderId = getChildText(eftNode, 'CardHolderId');
			w.EftTransactionID = getChildText(eftNode, 'EftTransactionID');
			w.EftDate = getChildDate(eftNode, 'EftDate');
			w.EftAmount = getChildDecimal(eftNode, 'EftAmount');
			w.AccountNumber = getChildText(eftNode, 'AccountNumber');
			w.RoutingNumber = getChildText(eftNode, 'RoutingNumber');
			w.Memo = getChildText(eftNode, 'Memo');
			w.StatusCode = getChildText(eftNode, 'StatusCode');
			w.StatusDate = getChildDate(eftNode, 'StatusDate');
			w.CreatedDate = getChildDate(eftNode, 'CreatedDate');
			w.SettledDate = getChildDate(eftNode, 'SettledDate');
			w.ReturnedDate = getChildDate(eftNode, 'ReturnedDate');
			w.NSFReturnCode = getChildText(eftNode, 'NSFReturnCode');

			foundEfts.put(w.EftTransactionID, w);
		}

		if (foundEfts.isEmpty()) {
			System.debug('ℹ️ No EFTs returned');
		}

		return new EPPSHelperMethods.EPPSResponse(
		                                          'FindEftByIDandDate',
		                                          true,
		                                          200,
		                                          requestXml,
		                                          responseXml,
		                                          null,
		                                          foundEfts
		);
	}


	/****************************************************************************
	 *  FINDFEEBYID – CALLOUT
	 ****************************************************************************/
	public static EPPSHelperMethods.EPPSResponse findFeeById(EPPSHelperMethods.FindFee_Wrapper wrapper) {

		HttpRequest req = new HttpRequest();
		req.setEndpoint('callout:EPPS_Named_Credential/eftservice.asmx');
		req.setMethod('POST');
		req.setHeader('Content-Type', 'text/xml; charset=utf-8');
		req.setHeader('SOAPAction', '"http://tempuri.org/FindFeeByID"');
		req.setTimeout(120000);

		String soapBody = buildFindFeeByIdXML(wrapper);
		req.setBody(soapBody);

		System.debug('SOAP REQUEST:\n' + soapBody);

		Http http = new Http();

		try {
			HttpResponse res = http.send(req);

			if (res.getStatusCode() != 200) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'FindFeeByID',
				                                          false,
				                                          res.getStatusCode(),
				                                          soapBody,
				                                          res.getBody(),
				                                          'HTTP error: ' + res.getStatus()
				);
			}

			return parseFindFeeByIdSoapResponse(soapBody, res.getBody());

		} catch(System.CalloutException ex) {

			return new EPPSHelperMethods.EPPSResponse(
			                                          'FindFeeByID',
			                                          false,
			                                          - 1,
			                                          soapBody,
			                                          null,
			                                          'Transport error: ' + ex.getMessage()
			);
		}
	}

	/****************************************************************************
	 *  FINDFEEBYID – XML BUILDER
	 ****************************************************************************/
	static String buildFindFeeByIdXML(EPPSHelperMethods.FindFee_Wrapper wrapper) {

		String xml =
		'<?xml version="1.0" encoding="utf-8"?>' +
		'<soap:Envelope ' +
		'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' +
		'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
		'xmlns:xsd="http://www.w3.org/2001/XMLSchema">' +
		'<soap:Body>' +
		'<FindFeeByID xmlns="http://tempuri.org/">' +

		'<UserName>{!$Credential.EPPS_External_Credential.Username}</UserName>' +
		'<PassWord>{!$Credential.EPPS_External_Credential.Password}</PassWord>' +

		'<FeeID>' + safe(wrapper.FeeID) + '</FeeID>' +

		'</FindFeeByID>' +
		'</soap:Body>' +
		'</soap:Envelope>';

		return xml;
	}

	public static EPPSHelperMethods.EPPSResponse updateFee2(EPPSHelperMethods.Fee_Wrapper wrapper) {
		HttpRequest req = new HttpRequest();
		req.setEndpoint('callout:EPPS_Named_Credential/eftservice.asmx');
		req.setMethod('POST');
		req.setHeader('Content-Type', 'text/xml; charset=utf-8');
		req.setHeader('SOAPAction', '"http://tempuri.org/UpdateFee2"');
		req.setTimeout(120000);

		String soapBody = buildUpdateFee2XML(wrapper);
		req.setBody(soapBody);

		System.debug('SOAP REQUEST (UpdateFee2):\n' + soapBody);

		Http http = new Http();
		HttpResponse res;

		try {
			res = http.send(req);
		} catch(System.CalloutException ex) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'UpdateFee2',
			                                          false,
			                                          - 1,
			                                          soapBody,
			                                          null,
			                                          'Transport error: ' + ex.getMessage()
			);
		}

		if (res.getStatusCode() != 200) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'UpdateFee2',
			                                          false,
			                                          res.getStatusCode(),
			                                          soapBody,
			                                          res.getBody(),
			                                          'HTTP error: ' + res.getStatus()
			);
		}

		return parseUpdateFee2SoapResponse(soapBody, res.getBody());
	}

	private static String buildUpdateFee2XML(EPPSHelperMethods.Fee_Wrapper w) {

		String xml =
		'<?xml version="1.0" encoding="utf-8"?>' +
		'<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">' +
		'<soap:Body>' +
		'<UpdateFee2 xmlns="http://tempuri.org/">' +

		'<UserName>{!$Credential.EPPS_External_Credential.Username}</UserName>' +
		'<PassWord>{!$Credential.EPPS_External_Credential.Password}</PassWord>' +

		// REQUIRED
		'<FeeID>' + safe(w.FeeID) + '</FeeID>' +

		// OPTIONAL / UPDATABLE
		(w.FeeDate != null
		 ? '<FeeDate>' + formatSoapDateTime(w.FeeDate) + '</FeeDate>'
		 : '') +

		(w.FeeAmount != null
		 ? '<FeeAmount>' + soapDecimal(w.FeeAmount) + '</FeeAmount>'
		 : '') +

		(String.isNotBlank(w.Description)
		 ? '<Description>' + safe(w.Description) + '</Description>'
		 : '') +

		(String.isNotBlank(w.FeeType)
		 ? '<FeeType>' + safe(w.FeeType) + '</FeeType>'
		 : '') +

		(String.isNotBlank(w.PaidToName)
		 ? '<PaidToName>' + safe(w.PaidToName) + '</PaidToName>'
		 : '') +

		(String.isNotBlank(w.PaidToPhone)
		 ? '<PaidToPhone>' + safe(w.PaidToPhone) + '</PaidToPhone>'
		 : '') +

		(String.isNotBlank(w.PaidToStreet)
		 ? '<PaidToStreet>' + safe(w.PaidToStreet) + '</PaidToStreet>'
		 : '') +

		(String.isNotBlank(w.PaidToStreet2)
		 ? '<PaidToStreet2>' + safe(w.PaidToStreet2) + '</PaidToStreet2>'
		 : '') +

		(String.isNotBlank(w.PaidToCity)
		 ? '<PaidToCity>' + safe(w.PaidToCity) + '</PaidToCity>'
		 : '') +

		(String.isNotBlank(w.PaidToState)
		 ? '<PaidToState>' + safe(w.PaidToState) + '</PaidToState>'
		 : '') +

		(String.isNotBlank(w.PaidToZip)
		 ? '<PaidToZip>' + safe(w.PaidToZip) + '</PaidToZip>'
		 : '') +

		(String.isNotBlank(w.ContactName)
		 ? '<ContactName>' + safe(w.ContactName) + '</ContactName>'
		 : '') +

		(String.isNotBlank(w.PaidToCustomerNumber)
		 ? '<PaidToCustomerNumber>' + safe(w.PaidToCustomerNumber) + '</PaidToCustomerNumber>'
		 : '') +

		'</UpdateFee2>' +
		'</soap:Body>' +
		'</soap:Envelope>';

		return xml;
	}
	private static EPPSHelperMethods.EPPSResponse parseUpdateFee2SoapResponse(String requestXml, String responseXml) {

		try {
			Dom.Document doc = new Dom.Document();
			doc.load(responseXml);

			Dom.XmlNode body = doc.getRootElement().getChildElement('Body', 'http://schemas.xmlsoap.org/soap/envelope/');

			if (body == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'UpdateFee2',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing Body'
				);
			}

			// SOAP Fault
			Dom.XmlNode fault = body.getChildElement('Fault', 'http://schemas.xmlsoap.org/soap/envelope/');

			if (fault != null) {
				String faultMsg = getFaultText(fault, 'faultstring');
				return new EPPSHelperMethods.EPPSResponse(
				                                          'UpdateFee2',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          faultMsg
				);
			}

			Dom.XmlNode responseNode = body.getChildElement('UpdateFee2Response', 'http://tempuri.org/');
			Dom.XmlNode resultNode =
			responseNode == null
			? null
			: responseNode.getChildElement('UpdateFee2Result', 'http://tempuri.org/');

			if (resultNode == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'UpdateFee2',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing UpdateFee2Result'
				);
			}

			String feeId = getChildText(resultNode, 'FeeID');
			String eftTxnId = getChildText(resultNode, 'EftTransactionID');
			String statusCode = getChildText(resultNode, 'StatusCode');
			String message = getChildText(resultNode, 'Message');

			// ✅ Message drives success
			Boolean success = String.isNotBlank(message) && message.equalsIgnoreCase('Success');

			EPPSHelperMethods.EPPSResponse resp =
			new EPPSHelperMethods.EPPSResponse(
			                                   'UpdateFee2',
			                                   success,
			                                   200,
			                                   requestXml,
			                                   responseXml,
			                                   message,
			                                   feeId
			);

			if (String.isNotBlank(resp.StatusCode))
			{
				resp.StatusCode = statusCode;
			}

			// Optional EFT transaction id
			if (String.isNotBlank(eftTxnId)) {
				try {
					resp.EftTransactionID = Integer.valueOf(eftTxnId);
				} catch(Exception ignore) { }
			}

			return resp;

		} catch(Exception ex) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'UpdateFee2',
			                                          false,
			                                          200,
			                                          requestXml,
			                                          responseXml,
			                                          'SOAP parse error: ' + ex.getMessage()
			);
		}
	}

	public static EPPSHelperMethods.EPPSResponse voidFee(EPPSHelperMethods.Fee_Wrapper wrapper) {

		HttpRequest req = new HttpRequest();
		req.setEndpoint('callout:EPPS_Named_Credential/eftservice.asmx');
		req.setMethod('POST');
		req.setHeader('Content-Type', 'text/xml; charset=utf-8');
		req.setHeader('SOAPAction', '"http://tempuri.org/VoidFee"');
		req.setTimeout(120000);

		String soapBody = buildVoidFeeXML(wrapper);
		req.setBody(soapBody);

		System.debug('SOAP REQUEST (VoidFee):\n' + soapBody);

		Http http = new Http();
		HttpResponse res;

		try {
			res = http.send(req);
		} catch(System.CalloutException ex) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'VoidFee',
			                                          false,
			                                          - 1,
			                                          soapBody,
			                                          null,
			                                          'Transport error: ' + ex.getMessage()
			);
		}

		if (res.getStatusCode() != 200) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'VoidFee',
			                                          false,
			                                          res.getStatusCode(),
			                                          soapBody,
			                                          res.getBody(),
			                                          'HTTP error: ' + res.getStatus()
			);
		}

		return parseVoidFeeSoapResponse(soapBody, res.getBody());
	}

	private static String buildVoidFeeXML(EPPSHelperMethods.Fee_Wrapper w) {

		return
		'<?xml version="1.0" encoding="utf-8"?>' +
		'<soap:Envelope ' +
		'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' +
		'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
		'xmlns:xsd="http://www.w3.org/2001/XMLSchema">' +
		'<soap:Body>' +
		'<VoidFee xmlns="http://tempuri.org/">' +
		'<UserName>{!$Credential.EPPS_External_Credential.Username}</UserName>' +
		'<PassWord>{!$Credential.EPPS_External_Credential.Password}</PassWord>' +
		'<FeeID>' + safe(w.FeeID) + '</FeeID>' +
		'</VoidFee>' +
		'</soap:Body>' +
		'</soap:Envelope>';
	}

	private static EPPSHelperMethods.EPPSResponse parseVoidFeeSoapResponse(String requestXml, String responseXml) {

		try {
			Dom.Document doc = new Dom.Document();
			doc.load(responseXml);

			Dom.XmlNode body = doc.getRootElement().getChildElement('Body', 'http://schemas.xmlsoap.org/soap/envelope/');

			if (body == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'VoidFee',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing Body'
				);
			}

			/***********************
			 * SOAP FAULT
			 ***********************/
			Dom.XmlNode fault = body.getChildElement('Fault', 'http://schemas.xmlsoap.org/soap/envelope/');

			if (fault != null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'VoidFee',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'SOAP Fault: ' + getFaultText(fault, 'faultstring')
				);
			}

			/***********************
			 * RESPONSE NODE
			 ***********************/
			Dom.XmlNode responseNode = body.getChildElement('VoidFeeResponse', 'http://tempuri.org/');
			Dom.XmlNode resultNode = responseNode == null ? null : responseNode.getChildElement('VoidFeeResult', 'http://tempuri.org/');

			if (resultNode == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'VoidFee',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing VoidFeeResult'
				);
			}

			/***********************
			 * FIELD EXTRACTION
			 ***********************/
			String feeId = getChildText(resultNode, 'FeeID');
			String eftTxnId = getChildText(resultNode, 'EftTransactionID');
			String statusCode = getChildText(resultNode, 'StatusCode');
			String message = getChildText(resultNode, 'Message');

			// ✅ EPPS behavior: Message controls success
			Boolean success = String.isNotBlank(message) && message.equalsIgnoreCase('Success');

			EPPSHelperMethods.EPPSResponse resp =
			new EPPSHelperMethods.EPPSResponse(
			                                   'VoidFee',
			                                   success,
			                                   200,
			                                   requestXml,
			                                   responseXml,
			                                   message,
			                                   feeId
			);

			// Optional EFT Transaction ID
			if (String.isNotBlank(eftTxnId)) {
				try {
					resp.EftTransactionID = Integer.valueOf(eftTxnId);
				} catch(Exception ignore) { }
			}

			return resp;

		} catch(Exception ex) {
			return new EPPSHelperMethods.EPPSResponse(
			                                          'VoidFee',
			                                          false,
			                                          200,
			                                          requestXml,
			                                          responseXml,
			                                          'SOAP parse error: ' + ex.getMessage()
			);
		}
	}

	/****************************************************************************
	 *  FINDFEEBYID – PARSER
	 ****************************************************************************/
	private static EPPSHelperMethods.EPPSResponse parseFindFeeByIdSoapResponse(String requestXml, String responseXml) {

		try {

			Dom.Document doc = new Dom.Document();
			doc.load(responseXml);

			Dom.XmlNode envelope = doc.getRootElement();

			Dom.XmlNode body = envelope.getChildElement(
			                                            'Body',
			                                            'http://schemas.xmlsoap.org/soap/envelope/'
			);

			if (body == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'FindFeeByID',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing Body'
				);
			}

			/***********************
			 * SOAP FAULT
			 ***********************/
			Dom.XmlNode fault = body.getChildElement('Fault', 'http://schemas.xmlsoap.org/soap/envelope/');
			if (fault != null) {

				String faultString = fault.getChildElement('faultstring', 'http://tempuri.org/') != null
				? fault.getChildElement('faultstring', 'http://tempuri.org/').getText()
				: null;

				String faultCode = fault.getChildElement('faultcode', 'http://tempuri.org/') != null
				? fault.getChildElement('faultcode', 'http://tempuri.org/').getText()
				: null;

				return new EPPSHelperMethods.EPPSResponse(
				                                          'FindFeeByID',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'SOAP Fault [' + faultCode + ']: ' + faultString
				);
			}

			/***********************
			 * RESPONSE NODE
			 ***********************/
			Dom.XmlNode responseNode = body.getChildElement('FindFeeByIDResponse', 'http://tempuri.org/');

			if (responseNode == null) {
				return new EPPSHelperMethods.EPPSResponse(
				                                          'FindFeeByID',
				                                          false,
				                                          200,
				                                          requestXml,
				                                          responseXml,
				                                          'Invalid SOAP response: missing FindFeeByIDResponse'
				);
			}

			Dom.XmlNode resultNode = responseNode.getChildElement('FindFeeByIDResult', 'http://tempuri.org/');

			Dom.XmlNode feeListNode = resultNode == null
			? null
			: resultNode.getChildElement('FeeList', 'http://tempuri.org/');

			List<EPPSHelperMethods.FindFee_Wrapper> theFees = new List<EPPSHelperMethods.FindFee_Wrapper> ();

			if (feeListNode != null) {

				for (Dom.XmlNode feeNode : feeListNode.getChildren()) {

					EPPSHelperMethods.FindFee_Wrapper f = new EPPSHelperMethods.FindFee_Wrapper();

					f.CardHolderID = getChildText(feeNode, 'CardHolderID');
					f.FeeID = getChildText(feeNode, 'FeeID');
					f.FeeDate = getChildDate(feeNode, 'Fee_Date');
					f.FeeAmount = getChildDecimal(feeNode, 'FeeAmount');
					f.Description = getChildText(feeNode, 'Description');
					f.FeeType = getChildText(feeNode, 'FeeType');
					f.StatusCode = getChildText(feeNode, 'StatusCode');
					f.StatusDate = getChildDate(feeNode, 'StatusDate');
					f.EftTransactionID = getChildText(feeNode, 'EftTransactionID');

					theFees.add(f);
				}
			}

			String message = getChildText(resultNode, 'Message');

			Boolean success = (message == 'Success');

			return new EPPSHelperMethods.EPPSResponse(
			                                          'FindFeeByID',
			                                          success,
			                                          200,
			                                          requestXml,
			                                          responseXml,
			                                          null,
			                                          buildMapFromList(theFees)
			);

		} catch(Exception ex) {

			return new EPPSHelperMethods.EPPSResponse(
			                                          'FindFeeByID',
			                                          false,
			                                          200,
			                                          requestXml,
			                                          responseXml,
			                                          'SOAP parse error: ' + ex.getMessage()
			);
		}
	}

	/****************************************************************************
	 *  SMALL UTILITIES USED ABOVE
	 ****************************************************************************/

	static Decimal safe(Decimal d) {
		return d;
	}

	static String safe(String s) {
		if (s == null) {
			return '';
		}


		return s
		.replace('&', '&amp;')
		.replace('<', '&lt;')
		.replace('>', '&gt;')
		.replace('"', '&quot;')
		.replace('\'', '&apos;');
	}


	static Datetime getChildDate(Dom.XmlNode node, String name) {
		String txt = getChildText(node, name);
		return String.isBlank(txt) ? null : Datetime.valueOfGmt(txt.replace('T', ' '));
	}

	static Decimal getChildDecimal(Dom.XmlNode node, String name) {
		String txt = getChildText(node, name);
		return String.isBlank(txt) ? null : Decimal.valueOf(txt);
	}

	static Map<String, EPPSHelperMethods.FindFee_Wrapper> buildMapFromList(List<EPPSHelperMethods.FindFee_Wrapper> lst) {

		Map<String, EPPSHelperMethods.FindFee_Wrapper> m = new Map<String, EPPSHelperMethods.FindFee_Wrapper> ();

		for (EPPSHelperMethods.FindFee_Wrapper f : lst) {
			m.put(f.FeeID, f);
		}

		return m;
	}

	private static String getChildText(Dom.XmlNode parent, String name) {
		Dom.XmlNode child = parent.getChildElement(name, 'http://tempuri.org/');
		return child == null ? null : child.getText();
	}

	private static EPPSHelperMethods.EPPSResponse emptyEftResponse(String requestXml, String responseXml) {

		return new EPPSHelperMethods.EPPSResponse(
		                                          'FindEftByIDandDate',
		                                          true,
		                                          200,
		                                          requestXml,
		                                          responseXml,
		                                          null,
		                                          new Map<String, EPPSHelperMethods.FindEFT_Wrapper> ()
		);
	}

	private static String getFaultText(Dom.XmlNode fault, String name) {
		Dom.XmlNode child = fault.getChildElement(name, null);
		return child == null ? null : child.getText();
	}

	///////////////////////////////////////////////
	///  Support Methods
	///////////////////////////////////////////////
	static String GetXMLValue(String theXML, String theValue) {
		return theXML.substringBetween('<' + theValue + '>', '</' + theValue + '>');
	}

	static List<EPPSHelperMethods.FindEFT_Wrapper> GetEFTTransactionDetailRecords(String theXML) {
		List<EPPSHelperMethods.FindEFT_Wrapper> theWrappers = new List<EPPSHelperMethods.FindEFT_Wrapper> ();
		String theNodes = theXML.substringBetween('<EFTList>', '</EFTList>');

		if (theNodes != null && theNodes.contains('<EFTTransactionDetail>')) {
			Integer nodeCount = theNodes.countMatches('<EFTTransactionDetail>');
			System.debug('**** NodeCount: ' + nodeCount);

			if (nodeCount > 0) {
				Integer NodeStartPosition = 0;
				Integer NodeEndPosition = 0;

				for (Integer i = 0; i<nodeCount; i++) {
					EPPSHelperMethods.FindEFT_Wrapper theWrapper = new EPPSHelperMethods.FindEFT_Wrapper();

					NodeStartPosition = theNodes.indexOf('<EFTTransactionDetail>');
					NodeEndPosition = theNodes.indexOf('</EFTTransactionDetail>');
					String theNode = theNodes.substring(NodeStartPosition, NodeEndPosition);

					theWrapper.AccountNumber = GetXMLValue(theNode, 'AccountNumber');
					theWrapper.CardHolderId = GetXMLValue(theNode, 'CardHolderId');
					if (String.isBlank(GetXMLValue(theNode, 'CreatedDate')) == false)
					theWrapper.CreatedDate = Datetime.valueOf(GetXMLValue(theNode, 'CreatedDate').replace('T', ' '));
					theWrapper.EftAmount = Decimal.valueOf(GetXMLValue(theNode, 'EftAmount'));
					if (String.isBlank(GetXMLValue(theNode, 'EftDate')) == false)
					theWrapper.EftDate = Datetime.valueOf(GetXMLValue(theNode, 'EftDate').replace('T', ' '));
					theWrapper.EftTransactionID = GetXMLValue(theNode, 'EftTransactionID');
					theWrapper.Memo = GetXMLValue(theNode, 'Memo');
					theWrapper.NSFReturnCode = GetXMLValue(theNode, 'NSFReturnCode');
					if (String.isBlank(GetXMLValue(theNode, 'ReturnedDate')) == false)
					theWrapper.ReturnedDate = Datetime.valueOf(GetXMLValue(theNode, 'ReturnedDate').replace('T', ' '));
					theWrapper.RoutingNumber = GetXMLValue(theNode, 'RoutingNumber');
					if (String.isBlank(GetXMLValue(theNode, 'SettledDate')) == false)
					theWrapper.SettledDate = Datetime.valueOf(GetXMLValue(theNode, 'SettledDate').replace('T', ' '));
					theWrapper.StatusCode = GetXMLValue(theNode, 'StatusCode');
					if (String.isBlank(GetXMLValue(theNode, 'StatusDate')) == false)
					theWrapper.StatusDate = Datetime.valueOf(GetXMLValue(theNode, 'StatusDate').replace('T', ' '));

					theWrappers.add(theWrapper);

					theNodes = theNodes.substring(NodeEndPosition + 23);
				}

				return theWrappers;
			}
		}
		return null;
	}

	private static String getSoapValue(String xml, String tagName) {
		if (String.isBlank(xml)) return null;

		// 1) Direct match: <Tag>value</Tag>
		String val = xml.substringBetween('<' + tagName + '>', '</' + tagName + '>');
		if (String.isNotBlank(val)) return val;

		// 2) Namespaced match with DOTALL via inline (?s)
		//    e.g. <ns1:StatusCode>value</ns1:StatusCode>
		Pattern p = Pattern.compile('(?s)<[^>]*:' + tagName + '>(.*?)</[^>]*:' + tagName + '>');
		Matcher m = p.matcher(xml);
		if (m.find()) {
			return m.group(1);
		}

		return null;
	}

	private static String normalizePhone(String phone) {
		if (String.isBlank(phone)) {
			 return '';
		}

		// Remove anything that is NOT a digit
		return phone.replaceAll('[^0-9]', '');
	}

	private static Integer parseInt(String val) {
		return String.isBlank(val) ? null : Integer.valueOf(val);
	}

	private static Decimal parseDecimal(String val) {
		return String.isBlank(val) ? null : Decimal.valueOf(val);
	}

	private static Datetime parseDateTime(String val) {
		return String.isBlank(val) ? null : Datetime.valueOf(val);
	}
	private static Boolean isSoapFault(String xml) {
		return String.isNotBlank(xml) &&
		(xml.contains('<Fault>') || xml.contains(':Fault>'));
	}

	private static String getSoapFaultMessage(String xml) {
		if (String.isBlank(xml)) return 'Unknown SOAP fault';

		String fault = getSoapValue(xml, 'faultstring');
		if (String.isNotBlank(fault)) return fault;

		// EPPS sometimes embeds errors as Message
		fault = getSoapValue(xml, 'Message');
		if (String.isNotBlank(fault)) return fault;

		return 'Unknown SOAP fault';
	}
	private static String soapDecimal(Decimal d) {
		return d == null ? null : d.setScale(2).toPlainString();
	}

	private static String formatSoapDateTime(Datetime dt) {
		return dt == null ? null : dt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss');
	}

	private static String xmlTag(String tagName, String value) {
		return String.isBlank(value)
		? ''
		: '<' + tagName + '>' + escapeXml(value) + '</' + tagName + '>';
	}

	private static String xmlTagDecimal(String tagName, Decimal value) {
		return value == null
		? ''
		: '<' + tagName + '>' + value.setScale(2).toPlainString() + '</' + tagName + '>';
	}

	private static String xmlTagDateTime(String tagName, Datetime value) {
		return value == null
		? ''
		: '<' + tagName + '>' + value.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss') + '</' + tagName + '>';
	}


	private static String escapeXml(String val) {
		if (val == null) return null;

		return val
		.replace('&', '&amp;')
		.replace('<', '&lt;')
		.replace('>', '&gt;')
		.replace('"', '&quot;')
		.replace('\'', '&apos;');
	}
}