/*
 * dreactor - A simple base net library
 *
 * Licensed under the Apache-2.0 License.
 *
 */
module zhang2018.dreactor.aio.AsyncGroupTcpServer;

import zhang2018.dreactor.aio.AsyncTcpServer;
import zhang2018.dreactor.event.Poll;

class AsyncGroupTcpServer(T , A ...)
{
	this(Group group , A args)
	{
		// Constructor code
		auto polls = group.polls();
		for(int i = 0 ; i < polls.length ; i++)
		{
			_servers ~= new AsyncTcpServer!(T , A)(polls[i] , args);
		}
	}

	bool open(string ipaddr, ushort port ,int back_log = 1024 ,  bool breuse = true)
	{

		for(int i = 0 ; i < _servers.length ; i++)
		{	
			if(!_servers[i].open(ipaddr , port , back_log , breuse))
				return false;
		}
		return true;
	}

	version(DREACTOR_OPENSSL)
	{
		bool enable_ssl(string pem_path , string passwd = string.init , string ca_path = string.init)
		{
			for(int i = 0 ; i < _servers.length ; i++)
			{	
				if(!_servers[i].enable_ssl(pem_path , passwd ,ca_path))
					return false;
			}

			return true;
		}
	}

	void close()
	{
		for(int i = 0 ; i < _servers.length ; i++)
		{
			_servers[i].close();
		}
	}

	AsyncTcpServer!(T , A)[] _servers;
}

