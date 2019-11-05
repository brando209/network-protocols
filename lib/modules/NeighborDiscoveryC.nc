configuration NeighborDiscoveryC {
	provides interface NeighborDiscovery;
}
implementation {
	//Export implementation of NeighborDiscovery[run() & print()] to NeighborDiscoveryP
	components NeighborDiscoveryP;
	NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;
	
	//Wire the SimpleSend interface used by NeighborDiscoveryP to the one provided by SimpleSendC()
	components new SimpleSendC(AM_PACK) as Sender;
	NeighborDiscoveryP.Sender -> Sender;
	
	//Wire the Receive interface used by NeighborDiscoveryP to the one provided by AMReceiverC()
	components new AMReceiverC(AM_PACK) as Receiver;
	NeighborDiscoveryP.Receiver -> Receiver;
	
	//Wire the List<> interface used by NeighborDiscoveryP to the one provided by ListC
	components new ListC(neighbor, 20) as NeighborList;
	NeighborDiscoveryP.NeighborList -> NeighborList;
	
	//Wire the Timer interface used by NeighborDiscoveryP to the one provided by TimerMilliC
	components new TimerMilliC() as discoveryTimer;
	NeighborDiscoveryP.discoveryTimer -> discoveryTimer;
}
