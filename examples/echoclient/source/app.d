

import zhang2018.dreactor.aio.AsyncTcpBase;

import zhang2018.dreactor.event.Poll;
import zhang2018.dreactor.time.Timer;
import zhang2018.dreactor.aio.AsyncTcpClient;
import zhang2018.common.Log;
import std.conv;
import std.string;

import std.stdio;





class EchoClient : AsyncTcpClient
{
	this(Group poll )
	{
		readBuff = new byte[1024];
		super(poll);
	}

	override bool doFirstConnectErr() 
	{
		return false;
	}

	override bool doEstablished()
	{

		byte[] buffer = new byte[256];
		for(int i = 0 ; i < 20000 ; i++)
			doWrite(buffer , null , null);

		return true;
	}
}




int main()
{

	import zhang2018.dreactor.event.GroupPoll;
	import zhang2018.dreactor.aio.AsyncTcpBase;
	import zhang2018.dreactor.aio.AsyncTcpClient;
	import zhang2018.dreactor.aio.AsyncTcpServer;
	import zhang2018.dreactor.event.Select;
	import std.stdio;
	import zhang2018.dreactor.io.TcpClient;



	auto poll = new GroupPoll!();


	AsyncTcpClient[] clients;
	for(int i = 0 ; i < 50000 ; i++)
	{
		auto client2 = new EchoClient(poll);
		client2.open("127.0.0.1" , 83);
		clients ~= client2;
	}


	poll.start();

	poll.wait();






	return 0;
}




