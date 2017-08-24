/*
 * dreactor - A simple base net library
 *
 * Licensed under the Apache-2.0 License.
 *
 */
module zhang2018.dreactor.io.TcpClient;

import zhang2018.dreactor.aio.AsyncTcpBase;
import zhang2018.common.Log;
import std.socket;
import std.conv;

alias TCCallBack = int delegate(immutable byte[] buffer);

class TcpClient 
{

	enum IO_State
	{
		IO_CONNECTED,
		IO_READ,
		IO_WRITE,
	};


	enum IO_Result{
		RESULT_OK = 0,
		WRITE_READ_PART,
		WRITE_READ_ERROR,
		RESULT_IO_CONNECT_TIMEOUT,
		RESULT_IO_NET_ERROR,
	}

	int connect(string host , ushort port , int milltimeout)
	{
		string strPort = to!string(port);
		AddressInfo[] arr = getAddressInfo(host , strPort , AddressInfoFlags.CANONNAME);
		if(arr.length == 0)
		{
			log_error(host ~ ":" ~ strPort);
			return IO_Result.RESULT_IO_NET_ERROR;
		}

		_socket = new Socket(arr[0].family , arr[0].type , arr[0].protocol);
		_socket.blocking(false);
		_socket.connect(arr[0].address);

		return event_wait(IO_State.IO_CONNECTED , null , milltimeout);

	}


	int do_write(const byte[] buffer , int milltimeout)
	{
		int sendsize = 0;
		long ret = _socket.send(buffer);

		if( ret == 0)
		{
			log_error("send error peer close");
			return IO_Result.WRITE_READ_ERROR;
		}
		else if( ret < 0 && AsyncTcpBase.net_error())
		{
			log_error("send io error");
			return IO_Result.WRITE_READ_ERROR;
		}
		else
		{
			sendsize += ret;
		}

		if(sendsize == buffer.length)
			return IO_Result.RESULT_OK;
		else
			return event_wait(IO_State.IO_WRITE ,
				(immutable byte[] buffer){
					long ret = _socket.send(buffer[sendsize .. buffer.length]);

					if(ret == 0)
					{
						log_error("send error peer close");
						return IO_Result.WRITE_READ_ERROR;
					}
					else if(ret < 0 && AsyncTcpBase.net_error())
					{
						log_error("send io error");
						return IO_Result.WRITE_READ_ERROR;
					}
					else
					{
						sendsize += ret;
					}

					if(sendsize < buffer.length)
						return IO_Result.WRITE_READ_PART;

					return IO_Result.RESULT_OK;

				}, milltimeout);
				
	}


	protected int do_read(TCCallBack callback)
	{
		long ret = _socket.receive(_buffer);

		if(ret > 0)
		{
			return callback(cast(immutable)_buffer[0 .. cast(uint)ret]);
		}
		else if(ret == 0) 
		{	
			log_error("receive error peer close");
			return IO_Result.WRITE_READ_ERROR;
		}
		else if(ret == -1 && AsyncTcpBase.net_error())
		{
			log_error("read io error");
			return IO_Result.WRITE_READ_ERROR;
		}
		else
		{
			return IO_Result.WRITE_READ_PART;
		}

	}


	int event_wait(IO_State state , TCCallBack callback , int milltimeout)
	{

		TimeVal val;
		val.seconds = milltimeout/1000 ;
		val.microseconds = milltimeout * 1000 - val.seconds * 1000 * 1000;

		do{	

			rset.reset();
			wset.reset();
			eset.reset();

			if(state == IO_State.IO_READ )
			{
				rset.add(_socket.handle);
			}
			else
			{
				wset.add(_socket.handle);
			}
			eset.add(_socket.handle);

			int ret = Socket.select(null ,wset , null  , &val);		
			if(ret < 0)
			{
				log_error("select failed ret " ~ to!string(ret));
				return IO_Result.RESULT_IO_NET_ERROR;
			}
			else if(ret == 0)
			{
				log_error("select timeout");
				return IO_Result.RESULT_IO_NET_ERROR;
			}
			else
			{
				if(eset.isSet(_socket.handle))
				{
					log_error("error eset");
					return IO_Result.RESULT_IO_NET_ERROR;
				}
				else if(state == IO_State.IO_CONNECTED && wset.isSet(_socket.handle))
				{
					int result;
					_socket.getOption(SocketOptionLevel.SOCKET , SocketOption.ERROR ,result);
				
					if(result == 0)
						return IO_Result.RESULT_OK;
					else 
						return IO_Result.RESULT_IO_NET_ERROR;
				
				}
				else if(state == IO_State.IO_READ && rset.isSet(_socket.handle))
				{
					int ret0 = do_read(callback);
					if(ret0 != IO_Result.WRITE_READ_PART)
						return ret0;

				}
				else if(state == IO_State.IO_WRITE && wset.isSet(_socket.handle))
				{
					int ret0 = callback(null);
					if(ret0 != IO_Result.WRITE_READ_PART)
						return ret0;
				}
				else
				{
					return IO_Result.RESULT_IO_NET_ERROR;
				}
			}
		}while(true);
			
	}

	Socket 			_socket;
	byte[1024]		_buffer;
	SocketSet rset = new SocketSet();
	SocketSet wset = new SocketSet();
	SocketSet eset = new SocketSet();
}



