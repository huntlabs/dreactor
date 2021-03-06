﻿/*
 * dreactor - A simple base net library
 *
 * Licensed under the Apache-2.0 License.
 *
 */
module zhang2018.dreactor.aio.AsyncTcpBase;

import core.stdc.errno;
import core.stdc.string;
import core.stdc.time;

version(DREACTOR_OPENSSL){

	import deimos.openssl.bio;
	import deimos.openssl.ssl;
	import deimos.openssl.err;
}
import std.container : DList;
import std.conv;
import std.socket;
import std.string;
import zhang2018.common.Log;
import zhang2018.dreactor.event.Event;
import zhang2018.dreactor.event.Poll;

import zhang2018.dreactor.openssl.Callback;

alias TcpWriteFinish = void delegate(Object ob);


class AsyncTcpBase:Event 
{
	//public function below


	this(Poll poll)
	{
		_poll = poll;
	}


	~this()
	{

	}

	version(DREACTOR_OPENSSL)
	{


		void doWrite_proxy_ssl(Object ob)
		{
			ProxySSL proxy = cast(ProxySSL)ob;
			if(++proxy.cur_suc == proxy.max_suc)
			{
				proxy.origin_cb(proxy.origin_ob);
			}

		}

	}


	// 0  		write_to_buff
	// 1  		suc
	// -1		failed
	public int doWrite(const byte[] writebuf , Object ob , TcpWriteFinish finish)
	{
		synchronized(this){
			version(DREACTOR_OPENSSL)
			{
				if(_ssl_ctx)
				{

					_proxy = new ProxySSL(finish , ob);
					int ret = SSL_write(_ssl , writebuf.ptr , cast(int)writebuf.length);
					//finish 
					if(ret != writebuf.length)
					{
						log_error("ssl_write error ret: " , ret , " len: " ,  writebuf.length);
						return -1;
					}

					if(_proxy.cur_suc == _proxy.max_suc)
					{
						delete _proxy;
						return 1;
					}
					else
					{
						return 0;
					}

			
		
				}
				else
				{
					return doWrite0(writebuf , ob , finish);
				}
			}
			else
			{
				return doWrite0(writebuf , ob , finish);
			}
		}
	}




	// 0  		write_to_buff
	// 1  		suc
	// -1		failed

	public int doWrite0(const byte[] writebuf , Object ob , TcpWriteFinish finish )
	{

			if(writebuf.length == 0)
			{
				return 1;
			}

			if(_writebuffer.empty())
			{
				long ret = _socket.send(writebuf);
				if(ret == writebuf.length)
				{
					return 1;
				}
				else if(ret > 0)
				{
					log_info("ret " , ret , " " , writebuf.length);
					QueueBuffer buffer = {writebuf.dup, ob , cast(int)ret , finish};
					_writebuffer.insertBack(buffer);
				
					schedule_write();
				}
				else
				{
					if(net_error())
					{
						log_error( "write net error");
						close();
						return -1;
					}
					//blocking rarely happened.
					//log_warning("blocking rarely happened");
					log_info("send -1 err : " , errno);
					QueueBuffer buffer = {writebuf.dup , ob , 0 , finish};
					_writebuffer.insertBack(buffer);
					schedule_write();
				}
				
			}
			else
			{
				QueueBuffer buffer = {writebuf.dup , ob , 0 , finish};
				_writebuffer.insertBack(buffer);
			}	

		return 0;
	}

	public void close()
	{
		//log_info("ready to close");
		if(!_isreadclose)
		{
			_isreadclose = true;
			schedule_write();
		}
	}

	public bool open()
	{
		_opentime = cast(int)time(null);
		_lastMsgTime = _opentime;
		_remoteipaddr = _socket.remoteAddress.toAddrString();

		version(DREACTOR_OPENSSL)
		{
			if(_ssl_ctx)
			{
				_ssl = SSL_new(_ssl_ctx);
				if(SSL_set_fd(_ssl , _socket.handle()) != 1)
				{
					log_error("ssl error socket " , _socket.handle());
					return false;
				}

				if(_clientSide)
				{
					SSL_set_connect_state(_ssl);
				}
				else
				{
					SSL_set_accept_state(_ssl);
				}

				bool flag = ssl_handshake();

				if(_clientSide)
					poll.modEvent(this ,_socket.handle , _curEventType =  IOEventType.IO_EVENT_READ);
				else
				   _poll.addEvent(this ,_socket.handle ,  _curEventType = IOEventType.IO_EVENT_READ);	
				
				return flag;
			}
			else
			{
				return onEstablished();
			}
		}
		else
		{
			return onEstablished();
		}



	}





	//protected function below


	//for ssl
	version(DREACTOR_OPENSSL)
	{

		bool ssl_handshake()
		{

			int r = SSL_do_handshake(_ssl);
			if( r == 0)
			{
				log_error("ssl error " , SSL_get_error(_ssl , r));
				return false;
			}
			else if( r == 1)
			{
				_ssl_status = true;

				if(_clientSide)
				{
					X509 *server_cert = SSL_get_peer_certificate(_ssl);
					if(server_cert == null)
					{
						log_error("server cert error");
						return false;
					}
					X509_free(server_cert);
				}
				//if (SSL_get_verify_result(_ssl) != X509_V_OK)

				_bio = BIO_new(BIO_f_null());
				_bio.ptr = cast(void *)this;
				_bio.method.bwrite = &openssl_cb_write;
				_bio.method.bread = &openssl_cb_read;
				SSL_set_bio(_ssl , _bio , _bio);

				//

				return onEstablished();
			}
			else if( r < 0)
			{
				int err = SSL_get_error(_ssl , r);
				if( err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE)
				{
	//				log_info("ssl want " , err);
					return true;
				}
				else
				{
					log_error("ssl error d" , err);
					return false;
				}
			}

			return true;

		}
	}



	//end ssl



	
	protected bool isReadyClose()
	{
		return _isreadclose;
	}

	protected bool onEstablished()
	{
		version(DREACTOR_OPENSSL)
		{
			if(_ssl_ctx == null)
				_poll.addEvent(this ,_socket.handle ,  _curEventType = IOEventType.IO_EVENT_READ); 
		}
		else
		{
			_poll.addEvent(this ,_socket.handle ,  _curEventType = IOEventType.IO_EVENT_READ); 
		}
		return doEstablished();
	}

	protected bool doEstablished()
	{
		return true;
	}

	protected bool onWrite()
	{
		synchronized(this){

			while(!_writebuffer.empty())
			{
				auto data = _writebuffer.front();
				long ret = _socket.send(data.buffer[data.index .. data.buffer.length]);
				if(ret == data.buffer.length - data.index)
				{
					if(data.finish !is null)
					{
						data.finish(data.ob);
					}
					_writebuffer.removeFront();
				}
				else if(ret > 0)
				{
					_writebuffer.front().index += ret;
					return true;
				}
				else if ( ret <= 0)
				{
					if(net_error())
					{
						log_error( "send net error");
						close();
						return false;
					}
					log_info("send -1 err : " , errno);
					return true;
				}

			}
			schedule_cancel_write();
		}

		return true;

	}

	protected bool onRead0()
	{
		long ret = _socket.receive(_readbuffer);
		_lastMsgTime = cast(int)time(null);
		if(ret > 0)
		{
			return doRead(_readbuffer , cast(int)ret);
		}
		if(ret == 0) 
		{	
			log_info("peer close socket " , _socket.handle );
			return false;
		}
		else if(ret == -1 && net_error())
		{
			log_error("error");
			return false;
		}
		
		return true;	
	}


	protected bool onRead()
	{

		version(DREACTOR_OPENSSL)
		{
			if(_ssl_ctx)
			{
				if(!_ssl_status)
				{
					return ssl_handshake();
				}
				int ret = SSL_read(_ssl , _readbuffer.ptr , cast(int)_readbuffer.length);
				_lastMsgTime =  cast(int)time(null);
				if(ret == 0)
				{
					log_error("ssl_read error " ,  SSL_get_error(_ssl , ret));
					return false;
				}
				else if(ret < 0)
				{
					int err = SSL_get_error(_ssl , ret);
					if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE)
					{
						return true;
					}
					else
					{
						log_error("ssl_read error " , err);
						return false;
					}
				}
				else{

					return doRead(_readbuffer , ret);
				}
		
			}
			else
			{
				return onRead0();
			}

		}
		else
		{
			return onRead0();
		}
	}

	protected @property void readBuff(byte []bt)
	{
		_readbuffer = bt;
	}


	protected bool doRead(byte[] data , int length)
	{
		return true;
	}


	protected bool onClose()
	{
		version(DREACTOR_OPENSSL)
		{
			if(_ssl_ctx)
			{
				_ssl_status = false;
				SSL_free(_ssl);
				_ssl = null;
				_bio = null;
			}
		}

		_isreadclose = false;
		_poll.delEvent(this , _socket.handle , _curEventType = IOEventType.IO_EVENT_NONE);
		_socket.close();
		return true;
	}

	protected @property poll()
	{
		return _poll;
	}

	void setSocket(Socket socket)
	{
		_socket = socket;
	}

	Socket getSocket()
	{
		return _socket;
	}

	version(DREACTOR_OPENSSL)
	{
		void setSSL(SSL_CTX *ssl_ctx)
		{
			_ssl_ctx = ssl_ctx;
		}
	}

	//private member's below
	private void schedule_write()
	{
		if(_curEventType & IOEventType.IO_EVENT_WRITE)
		{
			log_error("already IO_EVENT_WRITE");
		}
		
		_curEventType |= IOEventType.IO_EVENT_WRITE;
		_poll.modEvent(this , _socket.handle , _curEventType);
	}
	
	private void schedule_cancel_write()
	{
		if(! (_curEventType & IOEventType.IO_EVENT_WRITE))
		{
			log_error( "already no IO_EVENT_WRITE");
		}
		
		_curEventType &= ~IOEventType.IO_EVENT_WRITE;
		_poll.modEvent(this , _socket.handle , _curEventType);
	}


	private struct QueueBuffer
	{
		byte[] 			buffer;
		Object 			ob;
		int	   			index;
		TcpWriteFinish	finish;
	}



	//static function's below



	static public bool net_error()
	{
		int err = errno();
		if(err == 0 || err == EAGAIN || err == EWOULDBLOCK || err == EINTR || err == EINPROGRESS)
			return false;	
		return true;
	}

	protected DList!QueueBuffer _writebuffer;
	protected byte[]	_readbuffer;
	protected bool		_isreadclose = false;
	protected Socket 	_socket;
	protected Poll 		_poll;
	protected IOEventType 	_curEventType = IOEventType.IO_EVENT_NONE;
	

	protected uint			_opentime;
	protected uint			_lastMsgTime;
	protected string		_remoteipaddr;

	version(DREACTOR_OPENSSL)
	{
		SSL_CTX*				_ssl_ctx	= null;
		SSL*					_ssl		= null; 
		protected bool			_clientSide = false;		
		BIO*					_bio		= null;
		bool					_ssl_status  = false;		

		ProxySSL				_proxy		=	null;


		class ProxySSL
		{
			this(TcpWriteFinish cb , Object ob)
			{
				cur_suc = 0;
				max_suc = 0;
				origin_cb = cb;
				origin_ob = ob;
			}

			Object				origin_ob;
			TcpWriteFinish		origin_cb;
			int					cur_suc;
			int					max_suc;
		}

	}
}


