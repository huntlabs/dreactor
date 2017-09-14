
import zhang2018.dreactor.aio.AsyncTcpBase;

import zhang2018.dreactor.event.Poll;

import std.conv;
import std.stdio;
import std.string;
import std.conv;


import zhang2018.dreactor.openssl.Callback;

class MyHttpChannel : AsyncTcpBase
{
	this(Poll poll)
	{
		readBuff = new byte[1024];
		super(poll);
	}


	bool is_request_finish(ref bool finish, ref string url , ref string strbody)
	{
		import std.typecons : No;

		string str = cast(string)_readbuffer[0 .. _index];
		long header_pos = indexOf(str , "\r\n\r\n");

		if( header_pos == -1)
		{
			finish = false;
			return true;
		}

		string strlength = "content-length: ";
		int intlength = 0;
		long pos = indexOf(str , strlength , 0 , No.caseSensitive);
		if( pos != -1)
		{
			long left = indexOf(str , "\r\n" , cast(size_t)pos);
			if(pos == -1)
				return false;

			strlength = cast(string)_readbuffer[cast(size_t)(pos + strlength.length) .. cast(size_t)left];
			intlength = to!int(strlength);
		}
		 

		if(header_pos + 4 + intlength == _index)
		{
			finish = true;
		}
		else
		{
			finish = false;
			return true;
		}

		long pos_url = indexOf(str , "\r\n");
		if(pos_url == -1)
			return false;

		auto strs = split(cast(string)_readbuffer[0 .. cast(size_t)pos_url]);
		if(strs.length < 3)
			return false;

		url = strs[1];
		strbody = cast(string)_readbuffer[cast(size_t)(header_pos + 4) .. cast(size_t)_index];

		return true;
	}


	bool process_request(string url , string strbody)
	{
		string http_content = "HTTP/1.0 200 OK\r\nServer: kiss\r\nContent-Type: text/plain\r\nContent-Length: 10\r\n\r\nhelloworld";
		int ret = doWrite(cast(byte[])http_content , null , 
						delegate void(Object o){
						close();
			});

		if(ret == 1)
			return false;

		return true;
	}


	override protected bool doRead(byte[] buffer , int len)
	{

		_index += len;
		bool finish ;
		string strurl;
		string strbody;


		if(!is_request_finish(finish , strurl , strbody))
		{
			return false;
		}

		if(finish)
		{
			_index = 0;
			return process_request(strurl , strbody);
		}
		else if(_index == _readbuffer.length)
		{
			return false;
		}


		return true;
	}
	


	private int _index ;
	
}






int main()
{

	import zhang2018.dreactor.event.GroupPoll;
	import zhang2018.dreactor.aio.AsyncGroupTcpServer;
	import zhang2018.dreactor.aio.AsyncTcpServer;
	import zhang2018.dreactor.event.Select;
	import zhang2018.common.Log;


	log_debug("log_debug");
	log_info("log_info");
	log_error("log_error");
	log_debug("log_debug1");
	init_openssl_lib();
	auto poll = new GroupPoll!();
	auto server = new AsyncGroupTcpServer!MyHttpChannel(poll);
	server.enable_ssl("putao.com.pem");
	server.open("0.0.0.0" , 81);

	poll.start();
	poll.wait();

	return 0;
}





