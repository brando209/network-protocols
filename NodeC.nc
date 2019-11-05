/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;

    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;
    
    //Wire the SimpleSend interface used by Node to the one provided by SimpleFloodC
    components SimpleFloodC;
    Node.Flooder -> SimpleFloodC.Flooder;
    
    //Wire the NeighborDiscovery interface used by Node to the one provided by NeighborDiscoveryC
    components NeighborDiscoveryC as NeighborDiscovery;
    Node.NeighborDiscovery -> NeighborDiscovery;
    
    //Wire the LinkStateRouting interface used by Node to the one provided by LinkStateRoutingC
    components LinkStateRoutingC as LinkStateRouting;
    Node.LinkStateRouting -> LinkStateRouting;
    
    components TransportC as Transport;
    Node.Transport -> Transport;
    
    components ApplicationC as Application;
    Node.Application -> Application;
    
    //Wire the Timer interface
    components new TimerMilliC() as RoutingTimer;
	 Node.RoutingTimer -> RoutingTimer;
	 
	 components new TimerMilliC() as ClientWriteTimer;
	 Node.ClientWriteTimer -> ClientWriteTimer;
	 
	 components new TimerMilliC() as ServerAcceptTimer;
	 Node.ServerAcceptTimer -> ServerAcceptTimer;

	 components new ListC(socket_t, 10) as ClientConnections;
	 Node.ClientConnections -> ClientConnections;
	 
	 components new ListC(socket_t, 10) as ServerConnections;
	 Node.ServerConnections -> ServerConnections;
}
