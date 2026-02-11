/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSPaymentFeeStatusBatchMock
 * Author          : Shell Black (Sean Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By:
 * Last Modified On: Jan 27, 2026
 * Description     : Mock for Payment status batch
 *						
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Sean Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
global class EPPSPaymentFeeStatusBatchMock implements HttpCalloutMock
{
	 global HttpResponse respond(HttpRequest request) 
	 {
		HttpResponse response = new HttpResponse();
		response.setHeader('Content-Type', 'application/json');

		if (returnErrors == false)
		{
			response.setBody(CreateResponseBody());
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

	 ///  Replace with Response from findFeeById
	public static string CreateResponseBody()
	{
		string SoapBody = '<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body><FindFeeByIDResponse xmlns="http://tempuri.org/"><FindFeeByIDResult><FeeList><Fee><CardHolderID>12345</CardHolderID><FeeID>11749828</FeeID><EftTransactionID>12345</EftTransactionID><Party>Debt Program</Party><FeeAmount>22.00</FeeAmount><Description>Test</Description><Fee_Date>2026-01-09T00:00:00</Fee_Date><FeeType>Commission Fee</FeeType><PaidToName>Test</PaidToName><PaidToPhone>Test</PaidToPhone><PaidToStreet>Test</PaidToStreet><PaidToStreet2>Test</PaidToStreet2><PaidToCity>Test</PaidToCity><PaidToState>CA</PaidToState><PaidToZip>Test</PaidToZip><PaidToContactName>Test</PaidToContactName><BankReferenceID /><StatusCode>Pending</StatusCode><StatusDate>2026-01-08T00:00:00</StatusDate></Fee></FeeList><Message>Success</Message></FindFeeByIDResult></FindFeeByIDResponse></soap:Body></soap:Envelope>';		
		return SoapBody;
	}
}