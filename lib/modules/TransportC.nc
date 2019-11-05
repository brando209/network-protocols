configuration TransportC {
	provides interface Transport;
}
implementation {
	components TransportP;
	Transport = TransportP.Transport;
	
	components LinkStateRoutingP as Routing;
	TransportP.Routing -> Routing;
	
	components new SimpleSendC(AM_PACK) as Sender;
	TransportP.Sender -> Sender;

	components new ListC(socket_t, MAX_NUM_OF_SOCKETS) as SocketList;
	TransportP.SocketList -> SocketList;
	
	components new HashmapC(socket_store_t, MAX_NUM_OF_SOCKETS) as SocketMap;
	TransportP.SocketMap -> SocketMap;
	
	components new ListC(connection_t, MAX_NUM_OF_SOCKETS) as ConnectList;
	TransportP.ConnectList -> ConnectList;
	
	components new TimerMilliC() as SendTimer;
	TransportP.SendTimer -> SendTimer;
	
	components new TimerMilliC() as Timeout;
	TransportP.Timeout -> Timeout;
	
	components new ListC(pack, 100) as Unacked;
	TransportP.Unacked -> Unacked;	
}
