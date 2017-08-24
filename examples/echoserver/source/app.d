
import zhang2018.dreactor.aio.AsyncTcpBase;

import zhang2018.dreactor.event.Poll;
import zhang2018.common.Log;

import std.conv;
import std.stdio;

class EchoBase : AsyncTcpBase
{
	this(Poll poll , byte[] buff)
	{
		readBuff = buff;
		super(poll);
	}

	override protected bool doRead(byte[] buffer , int len)
	{
		doWrite(buffer[0 .. len] , null , null);
		return true;
	}

}

int main()
{

	import zhang2018.dreactor.event.GroupPoll;
	import zhang2018.dreactor.aio.AsyncTcpBase;
	import zhang2018.dreactor.aio.AsyncTcpClient;
	import zhang2018.dreactor.aio.AsyncTcpServer;
	import zhang2018.dreactor.aio.AsyncGroupTcpServer;

	auto poll = new GroupPoll!();
	byte[] buffer = new byte[1024];
	auto server = new AsyncGroupTcpServer!(EchoBase,byte[])(poll , buffer);
	server.open("0.0.0.0" , 83);

	poll.start();
	poll.wait();


	return 0;
}




