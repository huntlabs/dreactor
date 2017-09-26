module zhang2018.dreactor.openssl.Callback;

version(DREACTOR_OPENSSL):

import deimos.openssl.bio;
import deimos.openssl.err;
import deimos.openssl.ssl;
import zhang2018.dreactor.aio.AsyncTcpBase;
import std.socket;
import zhang2018.common.Log;
import core.sys.posix.sys.socket;
import core.stdc.errno;
import core.stdc.string;




void init_openssl_lib()
{
	SSL_load_error_strings();
	SSL_library_init();
}


extern(C)  int openssl_cb_read(BIO *b , char *data , int len)
{
	AsyncTcpBase base = cast(AsyncTcpBase)b.ptr;
	auto fd = base.getSocket().handle;
	int read_len = cast(int)recv(fd , data , len ,0);
	BIO_clear_retry_flags(b);
	if(read_len <= 0)
	{
		version(Windows)
		{
			int my_error = WSAGetLastError();
			if(my_error == 0 || my_error == WSAEINPROGRESS || my_error == WSAEWOULDBLOCK || my_error == WSAEINTR)
			{
				log_info("BIO_set_retry_read windows errorno " , my_error);
				BIO_set_retry_read(b);
				return read_len;
			}
		}
		else
		{
			int my_error = errno();
			if(my_error == 0 || my_error == EAGAIN || my_error == EWOULDBLOCK || my_error == EINTR || my_error == EINPROGRESS )
			{
				log_info("BIO_set_retry_read linux errorno ", my_error , " len " , len);
				BIO_set_retry_read(b);
				return 0;
			}
		}

		log_error("cb_read error len " , len , "read_len " , read_len);
		return -1;
	}

	return read_len;
}

extern(C)  int openssl_cb_write(BIO *b, const (char) * data, int len)
{
	AsyncTcpBase base = cast(AsyncTcpBase)b.ptr;

	byte[] bydata = new byte[len];
	memcpy(bydata.ptr , data , len);

	++base._proxy.max_suc;

	int ret = base.doWrite0(bydata , base._proxy , &base.doWrite_proxy_ssl);
	if( ret > 0)
	{
		++base._proxy.cur_suc;
	}
	else if(ret < 0)
	{
		log_error("cb_write");
		return -1;
	}
	return len;
}

