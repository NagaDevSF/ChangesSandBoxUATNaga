/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSManageFeesCalloutMock
 * Author          : Shell Black (Sean Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By:
 * Last Modified On: Jan 27, 2026
 * Description     : Mock for Manage Fees (update and void)
 *						
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Sean Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
global class EPPSManageFeesCalloutMock implements HttpCalloutMock 
{

	 global HttpResponse respond(HttpRequest request) 
	 {
		HttpResponse response = new HttpResponse();
		response.setHeader('Content-Type', 'application/json');

		if (returnErrors == false)
		{
			if (createVoidResponse == false)
				response.setBody(CreateResponseBody());
			else
				response.setBody(CreateVoidResponseBody());
			
			response.setStatusCode(200);
		}
		else
		{
			response.setBody('');
			response.setStatusCode(400);
		}

		return response;
	 }

	 public static boolean returnErrors = false;

	 public static boolean createVoidResponse = false;

	 ///  Replace with Response from findFeeById
	public static string CreateResponseBody()
	{
		string SoapBody = '<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body><UpdateFee2Response xmlns="http://tempuri.org/"><UpdateFee2Result><CardHolderID>12345</CardHolderID><FeeID>11823125</FeeID><EftTransactionID /><StatusCode>pending</StatusCode><StatusDate>2026-01-26T12:20:30</StatusDate><Message>Success</Message></UpdateFee2Result></UpdateFee2Response></soap:Body></soap:Envelope>';
		return SoapBody;
	}

	public static string CreateVoidResponseBody()
	{
		string SoapBody = '<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body><VoidFeeResponse xmlns="http://tempuri.org/"><VoidFeeResult><FeeID>11823125</FeeID><StatusCode>Void</StatusCode><StatusDate>2026-01-28T00:00:00-08:00</StatusDate><Message>Success</Message></VoidFeeResult></VoidFeeResponse></soap:Body></soap:Envelope>';
		return SoapBody;
	}

//
}