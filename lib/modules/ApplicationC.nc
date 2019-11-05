configuration ApplicationC {
	provides interface Application;
}
implementation {
	components ApplicationP;
	Application = ApplicationP.Application;
	
	components TransportC as Transport;
	ApplicationP.Transport -> Transport;
	
	components new ListC(socket_t, 10) as ServerConnections;
	ApplicationP.ServerConnections -> ServerConnections;
	
	components new TimerMilliC() as ServerTimer;
	ApplicationP.ServerTimer -> ServerTimer;
	
	components new TimerMilliC() as ClientTimer;
	ApplicationP.ClientTimer -> ClientTimer;
}
