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


version(Windows)
{
	pragma (lib, "ws2_32.lib");
	pragma (lib, "wsock32.lib");
	
	public import core.sys.windows.winsock2;
	private import core.sys.windows.windows, std.windows.syserror;
	private alias _ctimeval = core.sys.windows.winsock2.timeval;
	private alias _clinger = core.sys.windows.winsock2.linger;
	
	enum socket_t : SOCKET { INVALID_SOCKET }
	private const int _SOCKET_ERROR = SOCKET_ERROR;
}
else version(Posix)
{

	
	import core.sys.posix.netdb;
	import core.sys.posix.sys.un : sockaddr_un;
	private import core.sys.posix.fcntl;
	private import core.sys.posix.unistd;
	private import core.sys.posix.arpa.inet;
	private import core.sys.posix.netinet.tcp;
	private import core.sys.posix.netinet.in_;
	private import core.sys.posix.sys.time;
	private import core.sys.posix.sys.select;
	private import core.sys.posix.sys.socket;
	private alias _ctimeval = core.sys.posix.sys.time.timeval;
	private alias _clinger = core.sys.posix.sys.socket.linger;
	
	private import core.stdc.errno;

}

version(DREACTOR_OPENSSL){
	
	import deimos.openssl.bio;
	import deimos.openssl.ssl;
	import deimos.openssl.err;
}


extern(C)   int openssl_TcpClient_cb_read(BIO *b , char *data , int len)
{
	TcpClient client = cast(TcpClient)b.ptr;
	return cast(int)client.read_inter(data , len);
}

extern(C)   int openssl_TcpClient_cb_write(BIO *b, const (char) * data, int len)
{
	TcpClient client = cast(TcpClient)b.ptr;
	return cast(int)client.send_inter(data , len);
}


enum IO_Result{

	RESULT_OK = 0,
	WRITE_READ_PART,
	WRITE_READ_ERROR,
	RESULT_IO_CONNECT_TIMEOUT,
	RESULT_IO_NET_ERROR,
};

alias TCCallBack = IO_Result delegate(const byte[]);

class TcpClient 
{

	enum IO_State
	{
		IO_CONNECTED,
		IO_READ,
		IO_WRITE,
		IO_HANDSHAKE,
	};

	this(int timeout = 3)
	{
		_timeout = timeout;
	}

	~this()
	{
		close();
	}

	void close()
	{
		if(_socket !is null)
		{
			version(DREACTOR_OPENSSL){
				if(_enable_ssl)
				{
					SSL_free(_ssl);
					SSL_CTX_free(_ssl_ctx);

					_bio = null;
					_ssl = null;
					_ssl_ctx = null;
				}
			}

			_socket.close();
			_socket = null;
		}
	}




	IO_Result connect(string host , ushort port )
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

		IO_Result ret = event_wait(IO_State.IO_CONNECTED , null );

		if( ret != IO_Result.RESULT_OK)
			return ret;

		ret = event_open();		
		if( ret != IO_Result.RESULT_OK)
			return event_wait(IO_State.IO_HANDSHAKE , null);

		return ret;
	}

	IO_Result read_wait(TCCallBack callback)
	{
		return event_wait(IO_State.IO_READ , callback);
	}

	IO_Result send(const char *data , int len)
	{
		version(DREACTOR_OPENSSL){
			if(_enable_ssl)
			{
				SSL_write(_ssl , data , len);
				return IO_Result.RESULT_OK;
			}
		}

		return send_inter(data , len);

	}


	void enable_ssl()
	{
		_enable_ssl = true;
		
		version(DREACTOR_OPENSSL){
			__gshared static initSSL = false;
			if(!initSSL)
			{
				SSL_load_error_strings();
				SSL_library_init();
				initSSL = true;
			}
			
			_ssl_ctx = SSL_CTX_new(SSLv23_client_method());
		}
	}

protected:

	IO_Result event_open()
	{
		version(DREACTOR_OPENSSL){
			if(_enable_ssl)
			{	
				_ssl = SSL_new(_ssl_ctx);
				if(SSL_set_fd(_ssl , _socket.handle) != 1)
				{
					log_error("open SSL_set_fd error");
					return IO_Result.RESULT_IO_NET_ERROR;
				}
				
				SSL_set_connect_state(_ssl);
				
				return event_handshake();
			}
			else
			{
				return IO_Result.RESULT_OK;
			}
		}
	}
	
	
	
	
	
	
	IO_Result event_handshake()
	{
		version(DREACTOR_OPENSSL){
			
			int r = SSL_do_handshake(_ssl);
			if( r == 0)
			{
				log_error("SSL_do_handshake error");
				return IO_Result.RESULT_IO_NET_ERROR;
			}
			else if( r == 1)
			{
				X509 *server_cert = SSL_get_peer_certificate(_ssl);
				if(server_cert == null)
				{
					log_error("SSL_get_peer_certificate error");
					return IO_Result.RESULT_IO_NET_ERROR;
				}
				X509_free(server_cert);
				
				// 		if (SSL_get_verify_result(_ssl) != X509_V_OK)
				// 			return IO_Result.RESULT_IO_NET_ERROR;
				
				_bio = BIO_new(BIO_f_null());
				_bio.ptr = cast(void *)this;
				_bio.method.bwrite = &openssl_TcpClient_cb_write;
				_bio.method.bread = &openssl_TcpClient_cb_read;
				SSL_set_bio(_ssl , _bio , _bio);
				return IO_Result.RESULT_OK;
			}
			else if( r < 0)
			{
				int err = SSL_get_error(_ssl , r );
				if(err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE)
				{
					return IO_Result.WRITE_READ_PART;
				}
				else
				{
					return IO_Result.RESULT_IO_NET_ERROR;
				}
			}
			else{
				return IO_Result.RESULT_IO_NET_ERROR;
			}
			
		}
		else{
			return IO_Result.RESULT_OK;
		}
		
		
	}


	IO_Result send_inter(const char *data , int len )
	{
		int sendsize = 0;
		long ret = .send(_socket.handle , data , len , 0);
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

		if(sendsize == len)
			return IO_Result.RESULT_OK;
		else
			return event_wait(IO_State.IO_WRITE ,
				(const byte[] buffer){
					long ret = .send(_socket.handle , cast(const char *)buffer[sendsize .. buffer.length].ptr , cast(int)(buffer.length - sendsize) , 0);

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

				});
				
	}


	protected long read_inter(char *data , int len)
	{
		long ret = .recv(_socket.handle , data , len , 0);
		BIO_clear_retry_flags(_bio);
		if(ret == 0) 
		{	
			log_error("receive error peer close");
			return 0;
		}
		else if(ret == -1 )
		{
			if(AsyncTcpBase.net_error())
			{
				log_error("read io error");
				return 0;
			}

			BIO_set_retry_read(_bio);
			return -1;
		}
		else
		{
			return ret;
		}

	}

	IO_Result event_read(TCCallBack dele)
	{
		version(DREACTOR_OPENSSL)
		{
			if(_enable_ssl){

				do{
					int ret = SSL_read(_ssl , _ssl_buffer.ptr , _ssl_buffer.length);
					if(ret < 0)
					{
						int err = SSL_get_error(_ssl , ret);
						if(err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE)
							return IO_Result.WRITE_READ_PART;
						return IO_Result.WRITE_READ_ERROR;
					}
					else if( ret == 0)
					{
						return IO_Result.RESULT_IO_NET_ERROR;
					}

					ret = dele(_ssl_buffer[ 0 .. ret]);
					if (ret == IO_Result.RESULT_OK)
						return IO_Result.RESULT_OK;

				}while(1);
			}

			long read_len = read_inter(cast(char *)_buffer.ptr , cast(int)_buffer.length);
			if(read_len < 0 )
				return IO_Result.WRITE_READ_PART;
			else if(read_len == -1)
				return IO_Result.RESULT_IO_NET_ERROR;


			return dele(_buffer[ 0 .. read_len]);
		}
	}

	IO_Result event_write(TCCallBack dele)
	{
		return dele(null);
	}




	IO_Result event_wait(IO_State state , TCCallBack callback)
	{

		TimeVal val;
		val.seconds = _timeout;
		val.microseconds = 0;

		do{	

			rset.reset();
			wset.reset();
			eset.reset();

			if(state == IO_State.IO_READ || state == IO_State.IO_HANDSHAKE)
			{
				rset.add(_socket.handle);
			}
			else
			{
				wset.add(_socket.handle);
			}
			eset.add(_socket.handle);

			int ret = Socket.select(rset ,wset , eset  , &val);		
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
					int result;
					_socket.getOption(SocketOptionLevel.SOCKET , SocketOption.ERROR ,result);
					log_error("error eset " , result);
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
				else if(state == IO_State.IO_HANDSHAKE && rset.isSet(_socket.handle))
				{
					IO_Result ret0 = event_handshake();
					if(ret0 != IO_Result.WRITE_READ_PART)
						return ret0;
				}
				else if(state == IO_State.IO_READ && rset.isSet(_socket.handle))
				{
					IO_Result ret0 = event_read(callback);
					if(ret0 != IO_Result.WRITE_READ_PART)
						return ret0;

				}
				else if(state == IO_State.IO_WRITE && wset.isSet(_socket.handle))
				{
					IO_Result ret0 = event_write(callback);
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

	version(DREACTOR_OPENSSL)
	{
		SSL_CTX*		_ssl_ctx = null;
		SSL*			_ssl = null;
		BIO*			_bio = null;
		byte[1024]		_ssl_buffer;
	}

	int				_timeout;
	bool			_enable_ssl;
	Socket 			_socket;
	byte[1024]		_buffer;
	SocketSet rset = new SocketSet();
	SocketSet wset = new SocketSet();
	SocketSet eset = new SocketSet();
}



unittest{

	TcpClient client = new TcpClient;
	client.enable_ssl();
	log_info(client.connect("www.baidu.com" , 443));
	string data = "GET / HTTP/1.1\r\nHost: www.baidu.com\r\n\r\n";
	log_info(client.send(cast(char *)data.ptr , cast(int)data.length));
	log_info(client.read_wait( (const byte[] buffer){
				log_info(cast(string)buffer);
				return IO_Result.RESULT_OK;
			}));



}