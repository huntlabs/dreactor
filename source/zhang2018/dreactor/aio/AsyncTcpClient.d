/*
 * dreactor - A simple base net library
 *
 * Licensed under the Apache-2.0 License.
 *
 */
module zhang2018.dreactor.aio.AsyncTcpClient;

import zhang2018.dreactor.aio.AsyncTcpBase;
import zhang2018.dreactor.time.Timer;
import zhang2018.dreactor.event.Poll;
import zhang2018.dreactor.event.Event;
import zhang2018.common.Log;

version(DREACTOR_OPENSSL)
{
	import deimos.openssl.ssl;
}

import std.string;
import std.socket;
import std.conv;
import std.random;

class AsyncTcpClient:AsyncTcpBase
{

	//public function below
	version(DREACTOR_OPENSSL)
	{
		this(Group poll , int reconnecttime = 5 * 1000 , bool ssl = false )
		{
			int l = cast(int)poll.polls().length;
			int r = uniform(0 , l);
			this(poll.polls[r] , reconnecttime , ssl);
		}
		
		this(Poll poll , int reconnecttime = 5 * 1000 , bool ssl = false)
		{
			super(poll);
			_reconnecttime = reconnecttime;
			if(ssl)
				_ssl_ctx = SSL_CTX_new(SSLv23_client_method());
			_clientSide = true;
		}

		~this()
		{
			SSL_CTX_free(_ssl_ctx);
		}
	}
	else
	{
		this(Group poll , int reconnecttime = 5 * 1000 )
		{
			int l = cast(int)poll.polls().length;
			int r = uniform(0 , l);
			this(poll.polls[r] , reconnecttime );
		}

		this(Poll poll , int reconnecttime = 5 * 1000)
		{
			super(poll);
			_reconnecttime = reconnecttime;
		}
	}

	bool open(string host , ushort port)
	{
		string strPort = to!string(port);
		AddressInfo[] arr = getAddressInfo(host , strPort , AddressInfoFlags.CANONNAME);
		if(arr.length == 0)
		{
			log_error(host ~ ":" ~ strPort);
			return false;
		}

		_free = false;
		_host = host;
		_port = port;
		_socket = new Socket(arr[0].family , arr[0].type , arr[0].protocol);
		_socket.blocking(false);
		_socket.connect(arr[0].address);

		poll.addEvent(this , _socket.handle , _curEventType = IOEventType.IO_EVENT_WRITE);
		_status = Connect_Status.CLIENT_CONNECTING;
		return true;
	}


	bool doFirstConnectErr()
	{
		log_error("client connected error" ~ _host ~ ":" ~ to!string(_port));
		return true;
	}
	//protected function below

	override protected bool onEstablished()
	{
		_firstConnect = false;

		version(DREACTOR_OPENSSL)
		{	
			if(_ssl_ctx == null)
				poll.modEvent(this ,_socket.handle , _curEventType =  IOEventType.IO_EVENT_READ);
		}
		else
		{
			poll.modEvent(this ,_socket.handle , _curEventType =  IOEventType.IO_EVENT_READ);
		}
		return doEstablished();
	}

	void  onReconnect(TimerFd fd ) {
		log_warning("timer to reconnecting " , _host , " " , _port);
		open(_host , _port); 
	}

	public override int doWrite(const byte[] writebuf , Object ob , TcpWriteFinish finish )
	{
		version(DREACTOR_OPENSSL)
		{
			if(_ssl_ctx != null && _ssl_status == false)
			{
				log_error("ssl not shakedone");
				return -1;
			}

		}

		if(_status != Connect_Status.CLIENT_CONNECTED)
		{
			log_error("unconnected to the host");
			return -1;
		}

		return super.doWrite(writebuf , ob , finish);
	}

	override protected bool onWrite()
	{
		if(_status == Connect_Status.CLIENT_CONNECTING)
		{
			// for select mode. must check no error.
			int result;
			_socket.getOption(SocketOptionLevel.SOCKET , SocketOption.ERROR ,result);
			if(result != 0)
			{
				log_error("connect " ~ _host ~ ":" ~ to!string(_port)  ~ "error");
				return onClose();
			}

			_status = Connect_Status.CLIENT_CONNECTED;
			return super.open();
		}
		return super.onWrite();
	}



	override protected bool onClose()
	{
		bool isReconnected = true;
		super.onClose();

		if(_firstConnect)	//first must be connected error.
		{
			isReconnected = doFirstConnectErr();
			_firstConnect = false;
		}

		_status = Connect_Status.CLIENT_UNCONNECTED;

		if(_reconnect !is null)
			poll.delTimer(_reconnect);

		if(isReconnected && !_free)
		{
			_reconnect = poll.addTimer(&onReconnect , 3 * 1000 , WheelType.WHEEL_ONESHOT);
		}
		else
		{
			_firstConnect = true;
		}


		return _free;
	}

	void close(bool Free )
	{
		_free = Free;
		super.close();
	}


	//private member's below

	enum Connect_Status
	{
		CLIENT_UNCONNECTED = 0,
		CLIENT_CONNECTING,
		CLIENT_CONNECTED,
	}
	
	 
	protected Connect_Status _status = Connect_Status.CLIENT_UNCONNECTED;
	protected TimerFd		 _reconnect;
	protected int			 _reconnecttime;
	protected string		 _host;
	protected ushort		 _port;
	protected bool			 _firstConnect = true;
	protected bool			 _free = false;
}

