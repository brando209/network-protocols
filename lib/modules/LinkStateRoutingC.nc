configuration LinkStateRoutingC {
	provides interface LinkStateRouting;
}
implementation {
	//Export implementation of LinkStateRouting interface
	components LinkStateRoutingP;
	LinkStateRouting = LinkStateRoutingP.LinkStateRouting;
	
	components NeighborDiscoveryC;
	LinkStateRoutingP.NeighborDiscovery -> NeighborDiscoveryC;
	
	components SimpleFloodC;
	LinkStateRoutingP.LSPFlooder -> SimpleFloodC.Flooder;
	
   components new AMReceiverC(AM_FLOODING) as Receiver;
	LinkStateRoutingP.Receiver -> Receiver;
	
	components new ListC(LSP, 20) as LinkStateInfo;
	LinkStateRoutingP.LinkStateInfo -> LinkStateInfo;
	
	components new ListC(RouteEntry, 20) as Confirmed;
	LinkStateRoutingP.Confirmed -> Confirmed;
	
	components new ListC(RouteEntry, 20) as Tentative;
	LinkStateRoutingP.Tentative -> Tentative;
	
	components new HashmapC(RouteEntry, 20) as RoutingTable;
	LinkStateRoutingP.RoutingTable -> RoutingTable;
	
	components new TimerMilliC() as RoutingTimer;
	LinkStateRoutingP.RoutingTimer -> RoutingTimer;
}
