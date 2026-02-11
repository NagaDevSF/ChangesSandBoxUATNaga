/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSFindEFTsMock
 * Author          : Shell Black (Sean Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By:
 * Last Modified On: Jan 27, 2026
 * Description     : Test class to cover the EPPSFindEFTsMock              
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Sean Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
global class EPPSFindEFTsMock implements HttpCalloutMock 
{
	
	global EPPSFindEFTsMock(boolean returnNoErrors)
	{
		noErrors = returnNoErrors;
	}


	global HttpResponse respond(HttpRequest request) 
	{
		HttpResponse response = new HttpResponse();

		response.setHeader('Content-Type', 'application/json');
		response.setBody(ResponseBody);
		if (noErrors == true)
		{		
			response.setStatusCode(200);
		}
		else
		{
			response.setStatusCode(404);
		}
			
		return response;
	}

	public static string ResponseBody = '';
	Boolean noErrors = false;

	public static string CreateResponseBody()
	{
		string SoapBody = '<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body><FindEftByIDandDateResponse xmlns="http://tempuri.org/"><FindEftByIDandDateResult><EFTList><EFTTransactionDetail><CardHolderId>33344343</CardHolderId><EftTransactionID>10</EftTransactionID><EftDate>2026-01-06T00:00:00</EftDate><EftAmount>149.64</EftAmount><BankName /><BankCity /><BankState /><AccountNumber>123456</AccountNumber><RoutingNumber>123123123</RoutingNumber><Memo /><StatusCode>' + EPPSHelperMethods.EPPS_EFT_STATUS_SETTLED + '</StatusCode><StatusDate>2026-01-05T00:00:00</StatusDate><CreatedDate>2026-01-03T18:31:58</CreatedDate><SettledDate /><ReturnedDate /><NSFReturnCode /></EFTTransactionDetail><EFTTransactionDetail><CardHolderId>33344343</CardHolderId><EftTransactionID>11</EftTransactionID><EftDate>2026-01-06T00:00:00</EftDate><EftAmount>1005.00</EftAmount><BankName /><BankCity /><BankState /><AccountNumber>123456</AccountNumber><RoutingNumber>123123123</RoutingNumber><Memo /><StatusCode>Create EFT Pending</StatusCode><StatusDate>2026-01-05T00:00:00</StatusDate><CreatedDate>2026-01-04T11:41:32</CreatedDate><SettledDate /><ReturnedDate /><NSFReturnCode /></EFTTransactionDetail></EFTList><Message>Success</Message></FindEftByIDandDateResult></FindEftByIDandDateResponse></soap:Body></soap:Envelope>';
		return SoapBody;
	}
	
	public static string CreateResponseBodyNSFReturnCode()
	{
		string SoapBody = '<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body><FindEftByIDandDateResponse xmlns="http://tempuri.org/"><FindEftByIDandDateResult><EFTList><EFTTransactionDetail><CardHolderId>33344343</CardHolderId><EftTransactionID>10</EftTransactionID><EftDate>2026-01-06T00:00:00</EftDate><EftAmount>149.64</EftAmount><BankName /><BankCity /><BankState /><AccountNumber>123456</AccountNumber><RoutingNumber>123123123</RoutingNumber><Memo /><StatusCode>' + EPPSHelperMethods.EPPS_EFT_STATUS_SETTLED + '</StatusCode><StatusDate>2026-01-05T00:00:00</StatusDate><CreatedDate>2026-01-03T18:31:58</CreatedDate><SettledDate /><ReturnedDate /><NSFReturnCode>R01</NSFReturnCode></EFTTransactionDetail><EFTTransactionDetail><CardHolderId>33344343</CardHolderId><EftTransactionID>11</EftTransactionID><EftDate>2026-01-06T00:00:00</EftDate><EftAmount>1005.00</EftAmount><BankName /><BankCity /><BankState /><AccountNumber>123456</AccountNumber><RoutingNumber>123123123</RoutingNumber><Memo /><StatusCode>Create EFT Pending</StatusCode><StatusDate>2026-01-05T00:00:00</StatusDate><CreatedDate>2026-01-04T11:41:32</CreatedDate><SettledDate /><ReturnedDate /><NSFReturnCode /></EFTTransactionDetail></EFTList><Message>Success</Message></FindEftByIDandDateResult></FindEftByIDandDateResponse></soap:Body></soap:Envelope>';
		return SoapBody;
	}			
}