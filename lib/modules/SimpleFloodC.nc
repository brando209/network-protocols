configuration SimpleFloodC{
	//Provides the SimpleSend interface in order to flood
	provides interface SimpleSend as Flooder;
}
implementation {
	//Export the implemention of SimpleSend.send() to SimpleFloodP
	components SimpleFloodP;	
	Flooder = SimpleFloodP.Flooder;
	
	//Wire the SimpleSend interface used by SimpleFloodP to the one provided by SimpleSendC
	components new SimpleSendC(AM_FLOODING) as Sender;
	SimpleFloodP.Sender -> Sender;
	
	//Wire the Receive interface used by SimpleFloodP to the one provided by AMReceiverC()
	components new AMReceiverC(AM_FLOODING) as Receiver;
	SimpleFloodP.Receiver -> Receiver;
	
	//Wire the List interface used by SimpleFloodP to the one provided by ListC()
   components new ListC(pack, 20) as KnownList;
   SimpleFloodP.KnownList -> KnownList;
}
