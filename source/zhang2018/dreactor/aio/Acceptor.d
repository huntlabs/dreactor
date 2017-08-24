﻿/*
 * dreactor - A simple base net library
 *
 * Licensed under the Apache-2.0 License.
 *
 */
module zhang2018.dreactor.aio.Acceptor;

import zhang2018.common.Log;

import std.socket;
import std.string;
import std.conv;

import core.sys.posix.sys.socket;

final package class Acceptor
{
	this()
	{
		// Constructor code
	}

	bool open(string ipaddr, ushort port ,int back_log ,  bool breuse)
	{
	
		string strPort = to!string(port);
		AddressInfo[] arr = getAddressInfo(ipaddr , strPort , AddressInfoFlags.PASSIVE);
		if(arr.length == 0)
		{
			log_error("getAddressInfo" ~ ipaddr ~ ":" ~ strPort);
			return false;
		}
		_socket = new Socket(arr[0].family , arr[0].type , arr[0].protocol);
		uint use = 1;
		if(breuse)
		{	
			_socket.setOption(SocketOptionLevel.SOCKET , SocketOption.REUSEADDR , use);
			version(linux)
			{
				//SO_REUSEPORT
				_socket.setOption(SocketOptionLevel.SOCKET, cast(SocketOption) 15, use);
			}
		}
		_socket.bind(arr[0].address);
		_socket.blocking(false);
		_socket.listen(back_log);

		return true;
	}

	Socket accept()
	{
		return _socket.accept();
	}

	void close()
	{
		_socket.close();
	}

	@property
	int fd() 
	{
		return _socket.handle;
	}


	private Socket 	_socket;
}

