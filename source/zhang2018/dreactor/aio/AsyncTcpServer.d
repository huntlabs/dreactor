/*
 * dreactor - A simple base net library
 *
 * Licensed under the Apache-2.0 License.
 *
 */
module zhang2018.dreactor.aio.AsyncTcpServer;

import zhang2018.dreactor.event.Event;
import zhang2018.dreactor.event.Poll;
import zhang2018.dreactor.aio.Acceptor;
import zhang2018.dreactor.aio.AsyncTcpBase;
import zhang2018.dreactor.event.GroupPoll;

import zhang2018.common.Log;

version(DREACTOR_OPENSSL){
	import deimos.openssl.ssl;
}

import std.socket;
import std.string;


final class AsyncTcpServer( T , A...): Event
{

	this(Poll poll , A args)
	{
		_args = args;
		_poll = poll;
		_acceptor = new Acceptor();
	}

	bool open(string ipaddr, ushort port ,int back_log = 1024 ,  bool breuse = true)
	{

		if(!_acceptor.open(ipaddr , port , back_log , breuse))
		{
			return false;
		}

		_poll.addEvent(this , _acceptor.fd ,  IOEventType.IO_EVENT_READ);

		return true;
	}

	version(DREACTOR_OPENSSL)
	{
		bool enable_ssl(string pem_path , string passwd = string.init , string ca_path = string.init)
		{
			_ssl_ctx = SSL_CTX_new(SSLv23_method());
			if(_ssl_ctx == null)
			{
				log_error("SSL_CTX_new");
				return false;
			}

			if(ca_path != "")
			{
				if(SSL_CTX_load_verify_locations(_ssl_ctx , toStringz(ca_path) , null) <= 0)
				{
					log_error("SSL_CTX_load_verify_locations ca_path " , ca_path);
					return false;
				}
			}

			if(pem_path != "")
			{
				if (SSL_CTX_use_certificate_file(_ssl_ctx, toStringz(pem_path), SSL_FILETYPE_PEM) <= 0)
				{
					log_error("SSL_CTX_use_certificate_file pem_path");
					return false;
				}


				if (passwd != null)
				{
					SSL_CTX_set_default_passwd_cb_userdata(_ssl_ctx, cast(void *)toStringz(passwd));
				}
				
				if (SSL_CTX_use_PrivateKey_file(_ssl_ctx, toStringz(pem_path), SSL_FILETYPE_PEM) <= 0)
				{
					log_error("SSL_CTX_use_PrivateKey_file pem_path");
					return false;
				}
				
				if (!SSL_CTX_check_private_key(_ssl_ctx))
				{
					log_error("SSL_CTX_check_private_key ");
					return false;
				}

			}

			return true;
		}
	}


	void close()
	{
		_isreadclose = true;
	}

	protected bool isReadyClose()
	{
		return _isreadclose;
	}


	protected bool onWrite()
	{
		return true;
	}

	protected bool onRead()
	{
		T t = new T(_poll , _args);
		Socket socket = _acceptor.accept();
		socket.blocking(false);
		t.setSocket(socket);
		version(DREACTOR_OPENSSL)
		{
			if(_ssl_ctx)
			{
				t.setSSL(_ssl_ctx);
			}
		}
		return t.open();
	}

	protected bool onClose()
	{
		_acceptor.close();
		return true;
	}

	protected bool	   			_isreadclose = false;
	protected Poll	   			_poll;
	protected Acceptor 			_acceptor;
	protected A					_args;
	version(DREACTOR_OPENSSL)
	{
		protected SSL_CTX*		_ssl_ctx = null;
	}
}

